class_name FloorRail
extends VBoxContainer
## FloorRail — 우측 레일. 단면(층) 고르기 + 회전 + 줌. 엄지 자리(화면 아래)를 먹지 않게 위쪽에 붙는다.
##  - 층이 적으면(≤ FEW) 층마다 버튼, 많으면 ▲ nF ▼ 스테퍼. nF 를 위아래로 끌면 훑는다.
##  - cut: -1 = 전체(외관). n = z 인덱스(0 = 지상) → 화면엔 (n+1)F.

signal cut_changed(n: int)
signal rotate_pressed(dir: int)
signal zoom_pressed(dir: int)

const FEW := 3
const SCRUB_PX := 22.0

var cut: int = -1
var floors: int = 0
var show_zoom: bool = true:
	set(v):
		show_zoom = v
		if _zoom_box != null:
			_zoom_box.visible = v
var _all: PixelButton
var _floor_box: VBoxContainer
var _zoom_box: VBoxContainer
var _label: PixelButton
var _built_for: int = -999
var _scrub_from: float = 0.0
var _scrub_cut: int = 0
var _scrubbing: bool = false
var _scrub_moved: bool = false
var _last_cut: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	_all = _btn("전체", "")
	_all.toggle_mode = true
	_all.button_pressed = true
	_all.pressed.connect(func() -> void: set_cut(-1 if cut != -1 else _last_cut, true))
	add_child(_all)
	_floor_box = UI.vbox(2)
	add_child(_floor_box)
	add_child(UI.spacer(false, Vector2(0, 6)))
	var rl := _btn("", "rot_l")
	rl.pressed.connect(func() -> void: rotate_pressed.emit(-1))
	add_child(rl)
	var rr := _btn("", "rot_r")
	rr.pressed.connect(func() -> void: rotate_pressed.emit(1))
	add_child(rr)
	_zoom_box = UI.vbox(2)
	add_child(_zoom_box)
	_zoom_box.add_child(UI.spacer(false, Vector2(0, 6)))
	var zi := _btn("", "plus")
	zi.pressed.connect(func() -> void: zoom_pressed.emit(1))
	_zoom_box.add_child(zi)
	var zo := _btn("", "minus")
	zo.pressed.connect(func() -> void: zoom_pressed.emit(-1))
	_zoom_box.add_child(zo)


func _btn(text: String, icon_id: String) -> PixelButton:
	var b := PixelButton.make(text, icon_id, "ButtonRail")
	b.min_size = Vector2(UI.TOUCH, UI.TOUCH)
	return b


## 지금 가장 높은 층 수(0이면 층 버튼 없음).
func set_floors(n: int) -> void:
	n = maxi(0, n)
	if n == floors and _built_for == n:
		return
	floors = n
	if cut >= floors:
		set_cut(floors - 1 if floors > 0 else -1, true)
	_rebuild()


func set_cut(n: int, announce: bool = false) -> void:
	n = clampi(n, -1, maxi(-1, floors - 1))
	if n == cut:
		_sync()
		return
	cut = n
	if n >= 0:
		_last_cut = n
	_sync()
	if announce:
		cut_changed.emit(cut)


func _rebuild() -> void:
	_built_for = floors
	for c in _floor_box.get_children():
		_floor_box.remove_child(c)
		c.queue_free()
	_label = null
	if floors <= 1:
		_all.visible = floors == 1
		if floors == 1:
			_add_floor_button(0)
		_sync()
		return
	_all.visible = true
	if floors <= FEW:
		for z in range(floors - 1, -1, -1):
			_add_floor_button(z)
	else:
		var up := _btn("", "up")
		up.pressed.connect(func() -> void: set_cut((cut + 1) if cut >= 0 else floors - 1, true))
		_floor_box.add_child(up)
		_label = _btn("1F", "")
		_label.label_variation = "LabelGold"
		_label.gui_input.connect(_on_label_input)
		_label.pressed.connect(func() -> void:
			if not _scrub_moved:
				set_cut(-1 if cut != -1 else _last_cut, true))
		_floor_box.add_child(_label)
		var down := _btn("", "down")
		down.pressed.connect(func() -> void: set_cut((cut - 1) if cut > 0 else (0 if cut == 0 else _last_cut), true))
		_floor_box.add_child(down)
	_sync()


func _add_floor_button(z: int) -> void:
	var b := _btn("%dF" % (z + 1), "")
	b.toggle_mode = true
	b.set_meta("z", z)
	b.pressed.connect(func() -> void: set_cut(z, true))
	_floor_box.add_child(b)


func _sync() -> void:
	_all.set_pressed_no_signal(cut == -1)
	for c in _floor_box.get_children():
		if c is PixelButton and c.has_meta("z"):
			(c as PixelButton).set_pressed_no_signal(int(c.get_meta("z")) == cut)
	if _label != null:
		_label.label_text = "전체" if cut < 0 else "%dF" % (cut + 1)


## nF 를 누른 채 위아래로 끌면 층을 훑는다.
func _on_label_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_scrubbing = ev.pressed
		if ev.pressed:
			_scrub_moved = false
			_scrub_from = ev.global_position.y
			_scrub_cut = cut if cut >= 0 else floors - 1
	elif ev is InputEventMouseMotion and _scrubbing:
		var steps := int(round((_scrub_from - ev.global_position.y) / SCRUB_PX))
		if steps != 0:
			_scrub_moved = true
		if _scrub_moved:
			set_cut(clampi(_scrub_cut + steps, 0, floors - 1), true)
