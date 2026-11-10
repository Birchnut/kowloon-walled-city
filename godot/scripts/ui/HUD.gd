extends Control
## HUD — 상단바(일/시, 금고, 인구, 위신) + 하단 탭(정책/제안/성채/기록) 스텁 + 제안 카드 오버레이 스텁.

@onready var clock_label: Label = %ClockLabel
@onready var title_label: Label = %TitleLabel
@onready var treasury_label: Label = %TreasuryLabel
@onready var pop_label: Label = %PopLabel
@onready var prestige_label: Label = %PrestigeLabel
@onready var toast: Label = %Toast
@onready var cards_overlay: Control = %CardsOverlay
@onready var tab_panel: PanelContainer = %TabPanel
@onready var tab_title: Label = %TabTitle
@onready var tab_body: Label = %TabBody

var _toast_timer: float = 0.0
var _log_lines: Array[String] = []
var _active_tab: String = ""


func _ready() -> void:
	EventBus.hour_changed.connect(func(_h): _refresh())
	EventBus.day_ended.connect(_on_day_ended)
	EventBus.game_loaded.connect(func(_s): _bind_city())
	EventBus.data_reloaded.connect(func(): _bind_city())
	cards_overlay.visible = false
	tab_panel.visible = false
	toast.visible = false
	%TabPolicy.pressed.connect(func(): _toggle_tab("policy"))
	%TabProposal.pressed.connect(func(): _toggle_tab("proposal"))
	%TabCastle.pressed.connect(func(): _toggle_tab("castle"))
	%TabLog.pressed.connect(func(): _toggle_tab("log"))
	%CardsClose.pressed.connect(func(): cards_overlay.visible = false)
	for i in 3:
		var btn: Button = cards_overlay.get_node("Panel/VBox/Cards/Card%d" % (i + 1))
		btn.pressed.connect(func(): _pick_card(i))
	call_deferred("_bind_city")


func _bind_city() -> void:
	if Save.city == null:
		return
	if not Save.city.changed.is_connected(_refresh):
		Save.city.changed.connect(_refresh)
	if not Save.city.log_line.is_connected(_on_log):
		Save.city.log_line.connect(_on_log)
	_refresh()


func _process(delta: float) -> void:
	# 시계는 분 단위로 계속 갱신
	clock_label.text = Clock.clock_text()
	if Clock.view_override >= 0.0:
		clock_label.text += " [감상]"
	if toast.visible:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast.visible = false


func _refresh() -> void:
	if Save.city == null:
		return
	var s := Save.city.summary()
	title_label.text = str(s["title"])
	treasury_label.text = "₩%d" % s["treasury"]
	pop_label.text = "인구 %d" % s["population"]
	prestige_label.text = "위신 %d" % s["prestige"]
	if _active_tab != "":
		_fill_tab(_active_tab)


func show_toast(text: String, seconds: float = 3.5) -> void:
	toast.text = text
	toast.visible = true
	_toast_timer = seconds


func _on_log(text: String) -> void:
	_log_lines.append("[%s] %s" % [Clock.clock_text(), text])
	if _log_lines.size() > 200:
		_log_lines.pop_front()
	if _active_tab == "log":
		_fill_tab("log")


func _on_day_ended(day: int) -> void:
	# 하루 끝 → 제안 카드 3장 (스텁: 내용은 PLACEHOLDER)
	cards_overlay.visible = true
	%CardsTitle.text = "%d일차 끝 — 제안 카드" % (day + 1)
	EventBus.proposal_cards_requested.emit(day)


func _pick_card(i: int) -> void:
	show_toast("카드 %d 선택 (스텁: 효과 미구현)" % (i + 1))
	cards_overlay.visible = false


func _toggle_tab(id: String) -> void:
	if _active_tab == id:
		_active_tab = ""
		tab_panel.visible = false
		return
	_active_tab = id
	tab_panel.visible = true
	_fill_tab(id)


func _fill_tab(id: String) -> void:
	match id:
		"policy":
			tab_title.text = "정책 (스텁)"
			var lines := PackedStringArray()
			for ax in Data.policies.get("axes", []):
				var sel = Save.city.policies.get(ax["id"])
				var names := PackedStringArray()
				var sel_arr: Array = sel if typeof(sel) == TYPE_ARRAY else [sel]
				for opt in ax.get("options", []):
					if opt["id"] in sel_arr:
						names.append(opt["name"])
				lines.append("• %s: %s" % [ax["name"], ", ".join(names)])
			tab_body.text = "\n".join(lines)
		"proposal":
			tab_title.text = "제안 (스텁)"
			tab_body.text = "하루 끝에 카드 3장이 뜹니다. (N 키로 하루 넘기기)"
		"castle":
			tab_title.text = "성채 (스텁)"
			var s := Save.city.summary()
			tab_body.text = "건물 %d칸 / 일터 %d / 노동 %d명 / 호칭 %s\n누적 수입 %d, 부패 손실 %d, 유입 %d가구" % [
				s["cells"], s["workplaces"], s["workers"], s["title"],
				Save.city.stats["total_income"], Save.city.stats["total_spoiled"], Save.city.stats["arrivals"]]
		"log":
			tab_title.text = "기록"
			var tail := _log_lines.slice(maxi(0, _log_lines.size() - 12))
			tab_body.text = "\n".join(tail) if not tail.is_empty() else "(아직 기록 없음)"
