class_name PcWindow
extends PanelContainer
## PcWindow — 창 하나(현황판·경제·교역·탐험·성채·승급…). 제목 띠를 끌어 옮기고, ×나 Esc로 닫는다.
## 처음 열 때는 화면 가운데(위 띠 아래). 옮긴 자리는 다음에 열 때도 기억한다.
## 하위 클래스: _build(body) 한 번, _refresh() 는 열려 있는 동안 poll 초마다, open(arg) 로 탭·행을 고른다.

signal closed

var ui: Node = null                 # UIRoot
var win_id: String = ""
var title_text: String = ""
var key_hint: String = ""
var want_size: Vector2 = Vector2(1200, 760)
var poll: float = 1.0
var body: VBoxContainer
var _title: Label
var _sub: Label
var _moved := false
var _drag := false
var _drag_off := Vector2.ZERO
var _poll_t := 0.0
var _built := false


func _init() -> void:
	theme_type_variation = "PanelWindow"
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false


func _ready() -> void:
	var v := UI.vbox(0)
	add_child(v)
	var bar := UI.panel("PanelTitle")
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.gui_input.connect(_on_bar_input)
	v.add_child(bar)
	var hb := UI.hbox(10)
	bar.add_child(hb)
	_title = UI.label(title_text, "LabelHead")
	hb.add_child(_title)
	_sub = UI.label("", "LabelDim")
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_sub)
	if key_hint != "":
		hb.add_child(UI.label("[%s]" % key_hint, "LabelKey"))
	var x := PcButton.make("", "close", "Esc", "ButtonFlat")
	x.min_h = 36
	x.pressed.connect(close)
	TipLayer.set_tip(x, "닫기 [Esc]")
	hb.add_child(x)
	var m := UI.margin(14, 10, 14, 12)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(m)
	body = UI.vbox(8)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(body)
	_build(body)
	_built = true


func set_subtitle(s: String) -> void:
	if _sub != null:
		_sub.text = UI.no_hanja(s)


## 하위 클래스가 채운다.
func _build(_b: VBoxContainer) -> void:
	pass


func _refresh() -> void:
	pass


## arg: 탭·행 이름(jump 의 arg). 하위 클래스가 처리.
func _on_open(_arg: String) -> void:
	pass


func is_open() -> bool:
	return visible


func open(arg: String = "") -> void:
	var was := visible
	visible = true
	_fit()
	if not was:
		Sfx.play("window_open")
	_on_open(arg)
	_refresh()
	_poll_t = poll
	_fit.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play("window_close")
	closed.emit()


func _fit() -> void:
	var vr := get_viewport_rect().size
	var top := 64.0
	var sz := Vector2(minf(want_size.x, vr.x - 40.0), minf(want_size.y, vr.y - top - 24.0))
	size = sz
	custom_minimum_size = Vector2.ZERO
	if not _moved:
		position = Vector2(floorf((vr.x - sz.x) * 0.5), floorf(top + maxf(0.0, (vr.y - top - sz.y) * 0.4)))
	else:
		position = Vector2(clampf(position.x, 0, vr.x - 120), clampf(position.y, 0, vr.y - 60))


func _process(delta: float) -> void:
	if not visible:
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = poll
		_refresh()


func _on_bar_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
		_drag_off = get_global_mouse_position() - global_position
		get_parent().move_child(self, -1)
	elif ev is InputEventMouseMotion and _drag:
		_moved = true
		var vr := get_viewport_rect().size
		var p := get_global_mouse_position() - _drag_off
		global_position = Vector2(clampf(p.x, -size.x + 120, vr.x - 120), clampf(p.y, 0, vr.y - 48)).floor()


func _gui_input(ev: InputEvent) -> void:
	# 창을 누르면 앞으로
	if ev is InputEventMouseButton and ev.pressed:
		get_parent().move_child(self, -1)


# ------------------------------------------------------------------ 공용 조각
## 탭 줄: [[id, 이름], …] → 누르면 cb(id). 돌려준 사전 id -> 버튼.
static func tabs(parent: Control, items: Array, cb: Callable) -> Dictionary:
	var row := UI.hbox(4)
	parent.add_child(row)
	var out := {}
	for it: Array in items:
		var b := PcButton.make(str(it[1]), str(it[2]) if it.size() > 2 else "", "", "ButtonToggle")
		b.toggle_mode = true
		b.min_h = 38
		var id: String = it[0]
		b.pressed.connect(func() -> void: cb.call(id))
		row.add_child(b)
		out[id] = b
	return out


static func set_tab(btns: Dictionary, id: String) -> void:
	for k: String in btns:
		(btns[k] as Button).set_pressed_no_signal(k == id)


## 세로 스크롤 목록. 돌려준 VBox 에 행을 넣는다.
static func scroll_list(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(v)
	return v


static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


## 비율 막대(0..1+). 색은 상태.
static func bar(ratio: float, st: String, w: float = 120.0, h: float = 10.0) -> Control:
	var r := RatioBarPc.new()
	r.ratio = ratio
	r.col = UI.state_col(st)
	r.custom_minimum_size = Vector2(w, h)
	return r


## 단락 제목(금색 작은 글씨 + 선)
static func section(parent: Control, text: String) -> void:
	var h := UI.hbox(8)
	parent.add_child(h)
	h.add_child(UI.label(text, "LabelGoldSmall"))
	var sep := HSeparator.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sep)
