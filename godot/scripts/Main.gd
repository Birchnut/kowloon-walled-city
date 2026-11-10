extends Node2D
## Main — 씬 루트. 데이터 로드 확인 → 세이브 로드/새 게임 → 격자·카메라·HUD 연결.

@onready var grid: IsoGrid = $World/IsoGrid
@onready var camera: IsoCamera = $Camera
@onready var hud: Control = $UI/HUD
@onready var section_stub: PanelContainer = $UI/SectionStub
@onready var section_label: Label = $UI/SectionStub/Margin/VBox/Body


func _ready() -> void:
	if not Data.load_ok:
		push_error("[Main] 데이터 로드 실패 — data/*.json 확인")
	var loaded := Save.load_or_new()
	grid.bind_city(Save.city)
	_center_camera()
	camera.tapped.connect(_on_tapped)
	EventBus.cell_selected.connect(_on_cell_selected)
	EventBus.cell_deselected.connect(func(): section_stub.visible = false)
	EventBus.game_loaded.connect(_on_game_loaded)
	EventBus.data_reloaded.connect(func(): grid.bind_city(Save.city))
	section_stub.visible = false
	if loaded and not Clock.last_catchup.is_empty():
		_on_game_loaded(Clock.last_catchup)
	print("[Main] 준비 완료. %s / 금고 %d / 인구 %d" % [Clock.clock_text(), Save.city.treasury, Save.city.population()])


func _center_camera() -> void:
	var r := grid.bounds_rect()
	camera.position = grid.position + r.get_center()


func _on_tapped(world_pos: Vector2) -> void:
	var local := grid.to_local(world_pos)
	var cell := grid.pick_cell(local)
	grid.select_cell(cell)


func _on_cell_selected(cell: Vector3i) -> void:
	var c := Save.city.get_cell(cell)
	section_stub.visible = true
	if c.is_empty() or c.get("use", "empty") == "empty":
		section_label.text = "(%d, %d, %d층) 빈 땅" % [cell.x, cell.y, cell.z]
		return
	var mat := str(Data.material_by_id.get(c["material"], {}).get("name", c["material"]))
	var ind := str(Data.industry_by_id.get(c.get("industry_id", ""), {}).get("name", "-"))
	var occ := "없음"
	if int(c["occupant_id"]) >= 0 and Save.city.households.has(int(c["occupant_id"])):
		var hh: Dictionary = Save.city.households[int(c["occupant_id"])]
		occ = "%s %d명" % [hh["type"], hh["size"]]
		if hh.get("named_id", "") != "":
			occ += " (" + str(Data.resident_by_id.get(hh["named_id"], {}).get("name", "")) + ")"
	section_label.text = "(%d, %d, %d층)\n용도: %s\n자재: %s\n업종: %s\n입주: %s\n건물 나이: %.1f일\n대기 수입: %d" % [
		cell.x, cell.y, cell.z, c["use"], mat, ind, occ, float(c["age_days"]), int(c.get("pending_income", 0))]


func _on_game_loaded(summary: Dictionary) -> void:
	if Save.city != null and grid.city != Save.city:
		grid.bind_city(Save.city)
	if summary.is_empty():
		return
	var hours := float(summary.get("simulated_hours", 0.0))
	if hours < 0.5:
		return
	var msg := "자리를 비운 사이 %.1f일이 흘렀다." % float(summary.get("simulated_days", 0.0))
	if summary.get("capped", false):
		msg += " (최대 보상 한도 적용)"
	hud.call("show_toast", msg)
