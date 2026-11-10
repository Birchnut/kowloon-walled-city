class_name FloorRail
extends VBoxContainer
## FloorRail — 우측 레일(폭 56). 위에서부터:
##   전체 · 열린 층 버튼(많으면 ▲ nF ▼) · 다음 층 진행 칩("5F 62%" — 80% 규칙의 눈에 보이는 목표)
##   · 렌즈(수요 색) · 회전 ⟲⟳ · 줌 ±
## cut: -1 = 전체(외관). n = z(0 = 지상) → 화면엔 (n+1)F. 고른 층 = 짓기의 작업 층이자 단면.
## 값은 hud.floors_unlocked / hud.floor_progress 를 그대로 쓴다.

signal cut_changed(n: int)
signal rotate_pressed(dir: int)
signal zoom_pressed(dir: int)
signal lens_toggled(on: bool)
signal progress_pressed

const FEW := 3           # 이 층수까지는 층마다 버튼. 넘으면 스테퍼.
const BTN := Vector2(56, 52)

var cut: int = -1
var floors: int = 0
var show_camera: bool = true:
	set(v):
		show_camera = v
		if _cam_box != null:
			_cam_box.visible = v
var lens_on: bool = false
var _all: PixelButton
var _floor_box: VBoxContainer
var _progress: ProgressChip
var _lens: PixelButton
var _cam_box: VBoxContainer
var _label: PixelButton
var _built_for: int = -999
var _last_cut: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	_all = _btn("전체", "")
	_all.small = true
	_all.toggle_mode = true
	_all.button_pressed = true
	_all.pressed.connect(func() -> void: set_cut(-1 if cut != -1 else _last_cut, true))
	add_child(_all)
	_floor_box = UI.vbox(2)
	add_child(_floor_box)
	_progress = ProgressChip.new()
	_progress.pressed.connect(func() -> void: progress_pressed.emit())
	add_child(_progress)
	add_child(UI.spacer(false, Vector2(0, 4)))
	_lens = _btn("수요", "eye")
	_lens.small = true
	_lens.vertical = true
	_lens.toggle_mode = true
	_lens.pressed.connect(func() -> void:
		lens_on = _lens.button_pressed
		lens_toggled.emit(lens_on))
	add_child(_lens)
	_cam_box = UI.vbox(2)
	add_child(_cam_box)
	var rl := _btn("", "rot_l")
	rl.pressed.connect(func() -> void: rotate_pressed.emit(-1))
	_cam_box.add_child(rl)
	var rr := _btn("", "rot_r")
	rr.pressed.connect(func() -> void: rotate_pressed.emit(1))
	_cam_box.add_child(rr)
	var zi := _btn("", "plus")
	zi.pressed.connect(func() -> void: zoom_pressed.emit(1))
	_cam_box.add_child(zi)
	var zo := _btn("", "minus")
	zo.pressed.connect(func() -> void: zoom_pressed.emit(-1))
	_cam_box.add_child(zo)


func _btn(text: String, icon_id: String) -> PixelButton:
	var b := PixelButton.make(text, icon_id, "ButtonRail")
	b.min_size = BTN
	return b


func set_lens(on: bool) -> void:
	lens_on = on
	_lens.set_pressed_no_signal(on)


## hud 에서: 열린 층 수와 다음 층 진행.
func refresh(hud: Dictionary) -> void:
	set_floors(int(hud.get("floors_unlocked", 1)))
	var fp := UI.to_dict(hud.get("floor_progress", {}))
	var max_f := int(Data.cfg("grid.max_floors", 10))
	if fp.is_empty() or floors >= max_f:
		_progress.visible = false
	else:
		_progress.visible = true
		var need := maxf(1.0, float(fp.get("need", 1)))
		var used := float(fp.get("used", 0))
		_progress.set_values(int(fp.get("z", floors - 1)) + 2, used / need, int(used), int(need))


func set_floors(n: int) -> void:
	n = maxi(1, n)
	if n == floors and _built_for == n:
		return
	floors = n
	if cut >= floors:
		set_cut(floors - 1, true)
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
	if floors <= FEW:
		for z in range(floors - 1, -1, -1):
			var b := _btn("%dF" % (z + 1), "")
			b.toggle_mode = true
			b.set_meta("z", z)
			b.pressed.connect(func() -> void: set_cut(z, true))
			_floor_box.add_child(b)
	else:
		var up := _btn("", "up")
		up.pressed.connect(func() -> void: set_cut(mini((cut + 1) if cut >= 0 else 0, floors - 1), true))
		_floor_box.add_child(up)
		_label = _btn("1F", "")
		_label.label_variation = "LabelGold"
		_label.pressed.connect(func() -> void: set_cut(-1 if cut != -1 else _last_cut, true))
		_floor_box.add_child(_label)
		var down := _btn("", "down")
		down.pressed.connect(func() -> void: set_cut(maxi(cut - 1, 0) if cut >= 0 else 0, true))
		_floor_box.add_child(down)
	_sync()


func _sync() -> void:
	_all.set_pressed_no_signal(cut == -1)
	for c in _floor_box.get_children():
		if c is PixelButton and c.has_meta("z"):
			(c as PixelButton).set_pressed_no_signal(int(c.get_meta("z")) == cut)
	if _label != null:
		_label.label_text = "전체" if cut < 0 else "%dF" % (cut + 1)


func floor_rect() -> Rect2:
	return _floor_box.get_global_rect()


func progress_rect() -> Rect2:
	return _progress.get_global_rect() if _progress.visible else Rect2()


## 다음 층 진행 칩: "5F" + 막대 + "62%". 누르면 80% 규칙 설명.
class ProgressChip extends Button:
	var _f := 2
	var _r := 0.0
	var _used := 0
	var _need := 116

	func _init() -> void:
		theme_type_variation = "ButtonFlat"
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(56, 56)

	func set_values(f: int, r: float, used: int, need: int) -> void:
		if f == _f and absf(r - _r) < 0.005:
			return
		_f = f
		_r = r
		_used = used
		_need = need
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, UI.col("out"))
		draw_rect(r.grow(-2), UI.col("ink1"))
		# 잠긴 층: 점선 테두리 느낌
		for x in range(4, int(size.x) - 4, 6):
			draw_rect(Rect2(x, 4, 3, 2), UI.col("line"))
		var f := UI.font("small")
		var fs := UI.font_size("small")
		var t1 := "%dF" % _f
		var w1 := f.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(floorf((size.x - w1) * 0.5), 8 + f.get_ascent(fs)), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.col("dim"))
		var bar := Rect2(6, 30, size.x - 12, 6)
		draw_rect(bar, UI.col("ink0"))
		var w := floorf(bar.size.x * clampf(_r, 0.0, 1.0) / 2.0) * 2.0
		draw_rect(Rect2(bar.position, Vector2(w, bar.size.y)), UI.col("gold"))
		var t2 := "%d%%" % int(floorf(clampf(_r, 0.0, 1.0) * 100.0))
		var w2 := f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(floorf((size.x - w2) * 0.5), 36 + f.get_ascent(fs) - 2), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.col("gold"))

	func info_text() -> String:
		return "%dF가 열리려면 %dF에서 %d칸이 쓰여야 한다(지금 %d칸). 사람 사는 집과 완공 시설만 센다." % [_f, _f - 1, _need, _used]
