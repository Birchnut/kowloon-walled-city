class_name ChoiceButton
extends PanelContainer
## ChoiceButton — 두 줄짜리 넓은 버튼(제목 + 줄바꿈 되는 힌트). 결재 선택지·확인 창에 쓴다.
## PanelContainer + 투명 Button 조합이라 힌트가 길어도 높이가 알아서 늘어난다.

signal pressed

var variation: String = "Button"      # 스타일을 빌려올 버튼 타입(Button / ButtonRed / ButtonJade …)
var disabled: bool = false:
	set(v):
		disabled = v
		if _hit != null:
			_hit.disabled = v
		_apply(false)

var _title: Label
var _hint: Label
var _hit: Button
var _box: VBoxContainer
var _lead: Label


static func make(title: String, hint: String = "", variation_name: String = "Button", lead: String = "") -> ChoiceButton:
	var c := ChoiceButton.new()
	c.variation = variation_name
	c._build(title, hint, lead)
	return c


func _build(title: String, hint: String, lead: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, UI.TOUCH)
	var row := UI.hbox(10)
	add_child(row)
	if lead != "":
		_lead = UI.label(lead, "LabelGold")
		_lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_lead)
	_box = UI.vbox(0)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_box)
	_title = UI.label(title, "LabelBold", true)
	_box.add_child(_title)
	_hint = UI.label(hint, "LabelDim", true)
	_hint.visible = hint != ""
	_box.add_child(_hint)
	_hit = Button.new()
	_hit.theme_type_variation = "ButtonFlat"
	_hit.focus_mode = Control.FOCUS_NONE
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.disabled = disabled
	add_child(_hit)
	_hit.button_down.connect(_apply.bind(true))
	_hit.button_up.connect(_apply.bind(false))
	_hit.pressed.connect(func() -> void: pressed.emit())
	_apply(false)


func set_hint(hint: String) -> void:
	_hint.text = hint
	_hint.visible = hint != ""


func _apply(down: bool) -> void:
	var t := UI.theme()
	var st := "disabled" if disabled else ("pressed" if down else "normal")
	if t.has_stylebox(st, variation):
		add_theme_stylebox_override("panel", t.get_stylebox(st, variation))
	if _title != null:
		var cn := "font_disabled_color" if disabled else "font_color"
		if t.has_color(cn, variation):
			_title.add_theme_color_override("font_color", t.get_color(cn, variation))
