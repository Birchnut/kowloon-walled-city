class_name PixelButton
extends Button
## PixelButton — 픽셀 버튼. 누르면 얼굴이 1px(논리 2px) 내려간다(스타일박스가 처리).
## 내용(아이콘+글자+배지)은 직접 배치한다 → 컬러 아이콘을 틴트 없이 쓸 수 있고 세로 배치가 된다.
##
##   var b := PixelButton.make("심기", "v_plant", "ButtonVerb", true)
##   b.set_badge(3)
##
## 스타일은 theme_type_variation(ButtonRed / ButtonJade / ButtonChip / ButtonVerb …)만 바꾸면 된다.

signal long_pressed

const LONG_PRESS_SEC := 0.45

var label_text: String = "":
	set(v):
		label_text = v
		if _label != null:
			_label.text = v
			_label.visible = v != ""
			_update_min()
var icon_name: String = "":
	set(v):
		icon_name = v
		if _icon != null:
			_icon.texture = UI.icon(v) if v != "" else null
			_icon.visible = v != ""
			_update_min()
var vertical: bool = false
var tint_icon: bool = true           # false = 아이콘 원색 그대로(컬러 아이콘)
var label_variation: String = ""     # 비우면 버튼 테마의 폰트/색을 따른다
var small: bool = false              # 작은 글자(Galmuri9)로. 색은 버튼 상태를 그대로 따른다
## 최소 크기. Button 은 스크립트의 _get_minimum_size 를 무시하므로 custom_minimum_size 를 직접 관리한다.
## → 바깥에서는 custom_minimum_size 대신 이 값을 고칠 것.
var min_size: Vector2 = Vector2(UI.TOUCH, UI.TOUCH):
	set(v):
		min_size = v
		_update_min()
var enable_long_press: bool = false

var _box: BoxContainer
var _icon: TextureRect
var _label: Label
var _badge: PanelContainer
var _badge_label: Label
var _badge_tween: Tween
var _press_t: float = -1.0
var _long_fired: bool = false


static func make(text: String = "", icon_id: String = "", variation: String = "", is_vertical: bool = false) -> PixelButton:
	var b := PixelButton.new()
	b.vertical = is_vertical
	b.label_text = text
	b.icon_name = icon_id
	if variation != "":
		b.theme_type_variation = variation
	return b


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE


func _ready() -> void:
	_box = BoxContainer.new()
	_box.vertical = vertical
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 2 if vertical else 6)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_icon = TextureRect.new()
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_box.add_child(_icon)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if label_variation != "":
		_label.theme_type_variation = label_variation
	_box.add_child(_label)
	# setter 재실행
	label_text = label_text
	icon_name = icon_name
	set_process(false)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	_layout()
	_update_min()


func _update_min() -> void:
	if _box == null:
		return
	var sb := get_theme_stylebox("normal")
	var m := _box.get_combined_minimum_size()
	if sb != null:
		m += sb.get_minimum_size()
	var want := Vector2(maxf(m.x, min_size.x), maxf(m.y, min_size.y))
	if want != custom_minimum_size:
		custom_minimum_size = want


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		_layout()


func _draw() -> void:
	_layout()


func _layout() -> void:
	if _box == null:
		return
	var mode := get_draw_mode()
	var style := "normal"
	var col_name := "font_color"
	match mode:
		DRAW_PRESSED, DRAW_HOVER_PRESSED:
			style = "pressed"
			col_name = "font_pressed_color"
		DRAW_DISABLED:
			style = "disabled"
			col_name = "font_disabled_color"
	var sb := get_theme_stylebox(style)
	var r := Rect2(Vector2.ZERO, size)
	if sb != null:
		r.position = Vector2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP))
		r.size = size - sb.get_minimum_size()
	if _box.position != r.position or _box.size != r.size:
		_box.position = r.position
		_box.size = r.size
	var col := get_theme_color(col_name)
	if label_variation == "":
		var f := UI.font("small") if small else get_theme_font("font")
		var fs := UI.font_size("small") if small else get_theme_font_size("font_size")
		if _label.get_theme_font("font") != f or _label.get_theme_font_size("font_size") != fs:
			_label.add_theme_font_override("font", f)
			_label.add_theme_font_size_override("font_size", fs)
			_update_min.call_deferred()
		_label.add_theme_color_override("font_color", col)
	_icon.modulate = col if tint_icon else (Color(1, 1, 1, 0.45) if mode == DRAW_DISABLED else Color.WHITE)
	if _badge != null:
		_badge.position = Vector2(size.x - _badge.size.x + 4, -6)


# ------------------------------------------------------------------ 배지
## 0 이하면 숨김.
func set_badge(n: int) -> void:
	if n <= 0:
		if _badge != null:
			_badge.visible = false
		return
	if _badge == null:
		_badge = PanelContainer.new()
		_badge.theme_type_variation = "PanelBadge"
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge_label = UI.label("", "LabelSmall")
		_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_badge.add_child(_badge_label)
		add_child(_badge)
	_badge_label.text = str(n) if n < 100 else "99+"
	_badge.visible = true
	_badge.reset_size()
	_badge.custom_minimum_size = Vector2(22, 22)
	_badge.pivot_offset = _badge.size * 0.5
	_layout()


## 배지를 몇 번 통통 튀긴다(카드 도착 등). 창은 강제로 열지 않는다.
func pulse_badge(times: int = 4) -> void:
	if _badge == null or not _badge.visible:
		return
	if _badge_tween != null and _badge_tween.is_valid():
		_badge_tween.kill()
	_badge.pivot_offset = _badge.size * 0.5
	_badge_tween = create_tween().set_loops(times)
	_badge_tween.tween_property(_badge, "scale", Vector2(1.5, 1.5), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_badge_tween.tween_property(_badge, "scale", Vector2.ONE, 0.22)
	_badge_tween.tween_interval(0.35)


# ------------------------------------------------------------------ 길게 누르기
func _on_down() -> void:
	if enable_long_press:
		_press_t = 0.0
		_long_fired = false
		set_process(true)


func _on_up() -> void:
	_press_t = -1.0
	set_process(false)


func _process(delta: float) -> void:
	if _press_t < 0.0:
		return
	_press_t += delta
	if not _long_fired and _press_t >= LONG_PRESS_SEC:
		_long_fired = true
		long_pressed.emit()


## 길게 누르기가 발동했으면 이번 pressed는 무시해야 한다.
func consume_long_press() -> bool:
	var f := _long_fired
	_long_fired = false
	return f
