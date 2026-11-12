class_name FloorPanel
extends PanelContainer
## 왼쪽 아래: 보는 층 + 렌즈 + 카메라 안내.
##  층: [전체] [1F] … [nF] + 잠긴 다음 층 칸("3F 잠김 · 37%" — 무엇의 %인지 툴팁에 문장으로). PgUp/PgDn 과 같이 움직인다(뷰의 floor_cut 을 읽는다).
##  렌즈: 수요 · 시장 · 놀 곳 · 소방 · 수거 · 의원 · 계층 · 행복 — 하나만 켠다. 범위 렌즈는 coverage 질의.

signal floor_pressed(z: int)
signal lens_pressed(id: String)

const LENSES := [
	["needs", "수요", "warn", "수요 렌즈\n집마다 수요가 채워졌는지(초록·노랑·빨강)."],
	["market", "시장", "market", "시장 범위\n시장 범위 안의 집(초록)과 밖의 집(빨강)."],
	["fun", "놀 곳", "fun", "놀 곳 범위\n놀 것 시설 범위 안·밖의 집."],
	["fire", "소방", "fire", "소방 범위\n소방대가 닿는 집과 닿지 않는 집(불이 나면 번진다)."],
	["trash", "수거", "trash", "쓰레기 수거 범위\n범위 밖에 쓰레기가 쌓이면 병이 돈다."],
	["clinic", "의원", "clinic", "의원 범위\n의원 범위 안이면 병이 빨리 낫는다."],
	["tier", "계층", "tier", "계층 렌즈\n집마다 계층 색."],
	["happiness", "행복", "smile", "행복 렌즈\n집마다 행복도 색."],
]

var _floor_col: HFlowContainer
var _floor_btns: Dictionary = {}     # z -> Button (-1 = 전체)
var _lock_btn: PcButton
var _lens_btns: Dictionary = {}
var _floors_n: int = -1
var _cut: int = -99
var lens: String = ""
var _hud: Dictionary = {}


func _init() -> void:
	theme_type_variation = "PanelBar"
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var v := UI.vbox(6)
	add_child(v)
	var fh := UI.hbox(6)
	v.add_child(fh)
	fh.add_child(Picto.make("floor", UI.col("paper2")))
	fh.add_child(UI.label("보는 층", "LabelGoldSmall"))
	_floor_col = HFlowContainer.new()
	_floor_col.add_theme_constant_override("h_separation", 3)
	_floor_col.add_theme_constant_override("v_separation", 3)
	v.add_child(_floor_col)
	_lock_row = UI.hbox(6)
	v.add_child(_lock_row)
	v.add_child(HSeparator.new())
	var lh := UI.hbox(6)
	v.add_child(lh)
	lh.add_child(Picto.make("eye", UI.col("paper2")))
	lh.add_child(UI.label("렌즈", "LabelGoldSmall"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	v.add_child(grid)
	for l: Array in LENSES:
		var b := PcButton.make(l[1], l[2], "", "ButtonToggle")
		b.toggle_mode = true
		b.min_h = 32
		b.min_w = 94
		b.center = false
		var id: String = l[0]
		b.pressed.connect(func() -> void: lens_pressed.emit("" if lens == id else id))
		TipLayer.set_tip(b, l[3])
		grid.add_child(b)
		_lens_btns[id] = b
	var hint := UI.label("휠 확대 · 우클릭 끌기 이동 · Q/E 회전", "LabelMute")
	v.add_child(hint)
	TipLayer.set_tip(hint, "카메라\n휠 = 확대·축소 · 가운데/오른쪽 끌기·WASD·방향키 = 이동 · Q/E = 90° 돌리기 · PgUp/PgDn 또는 [ ] = 보는 층. F1 = 조작 전부.")


var _lock_row: HBoxContainer
var _lock_bar: RatioBarPc


func refresh(h: Dictionary) -> void:
	_hud = h
	var n := int(h.get("floors_unlocked", 1))
	if n != _floors_n:
		_floors_n = n
		_rebuild_floors()
	var fp := UI.to_dict(h.get("floor_progress", {}))
	if _lock_btn != null:
		var need := float(fp.get("need", 0))
		var used := float(fp.get("used", 0))
		var r := used / maxf(used + need, 1.0)
		_lock_btn.label_text = "%dF 열림까지 %s" % [n + 1, UI.pct(r)]
		_lock_bar.ratio = r
	var cut := int(Q.view().get("floor_cut")) if Q.view() != null and Q.view().get("floor_cut") != null else -1
	set_cut(cut)


func _rebuild_floors() -> void:
	PcWindow.clear(_floor_col)
	PcWindow.clear(_lock_row)
	_floor_btns.clear()
	var maxf_ := int(UI.to_dict(_hud.get("grid", {})).get("floors", 10))
	if _floors_n < maxf_:
		_lock_btn = PcButton.make("", "lock", "", "ButtonFlat")
		_lock_btn.min_h = 28
		_lock_btn.center = false
		TipLayer.set_tip(_lock_btn, func() -> String:
			var fp := UI.to_dict(_hud.get("floor_progress", {}))
			return "%d층은 아직 잠겼다\n%s\n쓰이는 칸 = 사람이 사는 집 + 다 지은 시설. 빈집·공사장·골조는 세지 않는다." % [_floors_n + 1, str(fp.get("text", "아래층을 더 채우면 열린다."))])
		_lock_row.add_child(_lock_btn)
		_lock_bar = RatioBarPc.new()
		_lock_bar.col = UI.col("jade")
		_lock_bar.custom_minimum_size = Vector2(100, 10)
		_lock_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lock_row.add_child(_lock_bar)
	else:
		_lock_btn = null
	for z in range(-1, _floors_n):
		var b := PcButton.make("전체" if z < 0 else "%dF" % (z + 1), "", "", "ButtonToggle")
		b.toggle_mode = true
		b.min_h = 30
		b.min_w = 52
		var zz := z
		b.pressed.connect(func() -> void: floor_pressed.emit(zz))
		TipLayer.set_tip(b, "모든 층을 본다" if z < 0 else "%d층만 본다 [PgUp/PgDn]\n위층을 걷어 내고 이 층을 보여 준다. 짓기는 이 층에." % (z + 1))
		_floor_col.add_child(b)
		_floor_btns[z] = b
	_cut = -99


func set_cut(z: int) -> void:
	if z == _cut:
		return
	_cut = z
	for k: int in _floor_btns:
		(_floor_btns[k] as Button).set_pressed_no_signal(k == z)


func set_lens(id: String) -> void:
	lens = id
	for k: String in _lens_btns:
		(_lens_btns[k] as Button).set_pressed_no_signal(k == id)


func lens_rect(id: String) -> Rect2:
	return (_lens_btns[id] as Control).get_global_rect() if _lens_btns.has(id) else Rect2()


func floors_rect() -> Rect2:
	return _floor_col.get_global_rect()
