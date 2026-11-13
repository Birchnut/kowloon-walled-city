class_name PcButton
extends Button
## PcButton — PC판 버튼: [그림문자] 글자 [단축키]. 모양은 테마 변형(Button / ButtonToggle / ButtonGold / ButtonJade / ButtonRed / ButtonFlat / ButtonCard).
## 툴팁은 TipLayer.set_tip(btn, "제목\n설명") 으로. 단축키는 글자 옆에 작은 금색 글씨로 보인다(Jin: 키를 버튼에 보여 준다).
##   var b := PcButton.make("현황판", "metrics", "Tab")

var _box: HBoxContainer
var _pic: Picto
var _lab: Label
var _key: Label
var _badge: Label

var label_text: String = "":
	set(v):
		label_text = UI.no_hanja(v)
		if _lab != null:
			_lab.text = label_text
			_lab.visible = label_text != ""
			_fit()
var picto: String = "":
	set(v):
		picto = v
		if _pic != null:
			_pic.shape = v
			_pic.visible = v != ""
			_fit()
var picto_color: Color = Color(0, 0, 0, 0):
	set(v):
		picto_color = v
		if _pic != null and v.a > 0.0:
			_pic.color = v
var key_hint: String = "":
	set(v):
		key_hint = v
		if _key != null:
			_key.text = v
			_key.visible = v != ""
			_fit()
var min_w: float = 0.0
var min_h: float = 40.0
var label_variation: String = ""
var center: bool = true
## 누를 때 소리(Sfx 이름). 창 안 탭은 "tab", 소리 없이는 "".
var sfx_name: String = "click"
## 마우스를 올릴 때 아주 작은 소리(Sfx "hover") — 짓기 카드에만 켠다.
var hover_sfx: bool = false


static func make(txt: String = "", pic: String = "", key: String = "", variation: String = "") -> PcButton:
	var b := PcButton.new()
	b.label_text = txt
	b.picto = pic
	b.key_hint = key
	if variation != "":
		b.theme_type_variation = variation
	return b


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(func() -> void:
		if sfx_name != "":
			Sfx.play(sfx_name))
	mouse_entered.connect(func() -> void:
		if hover_sfx and not disabled:
			Sfx.play("hover"))


func _ready() -> void:
	_box = HBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 6)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER if center else BoxContainer.ALIGNMENT_BEGIN
	add_child(_box)
	_pic = Picto.new()
	_box.add_child(_pic)
	_lab = Label.new()
	_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if label_variation != "":
		_lab.theme_type_variation = label_variation
	_box.add_child(_lab)
	_key = Label.new()
	_key.theme_type_variation = "LabelKey"
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_box.add_child(_key)
	label_text = label_text
	picto = picto
	key_hint = key_hint
	picto_color = picto_color
	_fit()


func set_badge(n: int, tone: String = "red") -> void:
	if n <= 0:
		if _badge != null:
			_badge.visible = false
		return
	if _badge == null:
		_badge = Label.new()
		_badge.theme_type_variation = "LabelSmall"
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		_badge.add_theme_stylebox_override("normal", sb)
		_badge.z_index = 2
		add_child(_badge)
	(_badge.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = UI.col("red") if tone == "red" else UI.col("jade_d")
	_badge.text = str(n) if n < 100 else "99+"
	_badge.visible = true
	_badge.reset_size()
	_badge.position = Vector2(size.x - _badge.size.x + 4, -8)


func _fit() -> void:
	if _box == null:
		return
	var sb := get_theme_stylebox("normal")
	var m := _box.get_combined_minimum_size()
	if sb != null:
		m += sb.get_minimum_size()
	custom_minimum_size = Vector2(maxf(m.x, min_w), maxf(m.y, min_h))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_DRAW:
		_place()


func _place() -> void:
	if _box == null:
		return
	var st := "normal"
	var col_name := "font_color"
	match get_draw_mode():
		DRAW_PRESSED, DRAW_HOVER_PRESSED:
			st = "pressed"
			col_name = "font_pressed_color"
		DRAW_HOVER:
			st = "hover"
			col_name = "font_hover_color"
		DRAW_DISABLED:
			st = "disabled"
			col_name = "font_disabled_color"
	var sb := get_theme_stylebox(st)
	var r := Rect2(Vector2.ZERO, size)
	if sb != null:
		r.position = Vector2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP))
		r.size = size - sb.get_minimum_size()
	_box.position = r.position
	_box.size = r.size
	if label_variation == "":
		_lab.add_theme_color_override("font_color", get_theme_color(col_name))
		_lab.add_theme_font_override("font", get_theme_font("font"))
		_lab.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
	if picto_color.a <= 0.0:
		_pic.color = get_theme_color(col_name)
	_pic.modulate.a = 0.45 if disabled else 1.0
	_key.modulate.a = 0.5 if disabled else 1.0
	var kc := get_theme_color(col_name)
	_key.add_theme_color_override("font_color", Color(kc.r, kc.g, kc.b, 0.78))
	if _badge != null and _badge.visible:
		_badge.position = Vector2(size.x - _badge.size.x + 4, -8)
