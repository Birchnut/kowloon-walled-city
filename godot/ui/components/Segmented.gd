class_name Segmented
extends HBoxContainer
## Segmented — 칩 한 줄(하나만 켜짐). 켜진 칩은 상아 마작패.
##
##   seg.set_options([{id="ban", name="금지"}, {id="ok", name="허가", locked=true}], "ban")
##   seg.selected.connect(func(id): ...)
##
## locked 옵션은 회색 + 자물쇠, 눌러도 selected 대신 locked_pressed 가 나간다.

signal selected(id: String)
signal locked_pressed(id: String)

var value: String = ""
var chip_variation: String = "ButtonChip"
var equal_width: bool = true
var _buttons: Dictionary = {}    # id -> PixelButton
var _locked: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_options(options: Array, current: String = "") -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_buttons.clear()
	_locked.clear()
	value = current
	for o in options:
		if not (o is Dictionary):
			continue
		var id := str(o.get("id", ""))
		var b := PixelButton.make(str(o.get("name", id)), str(o.get("icon", "")), str(o.get("variation", chip_variation)))
		b.toggle_mode = true
		b.button_pressed = id == current
		if equal_width:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bool(o.get("locked", false)):
			_locked[id] = true
			b.icon_name = "lock"
			b.modulate = Color(1, 1, 1, 0.5)
		b.pressed.connect(_on_pressed.bind(id))
		add_child(b)
		_buttons[id] = b


func set_value(id: String) -> void:
	value = id
	for k in _buttons:
		(_buttons[k] as PixelButton).set_pressed_no_signal(k == id)


func button(id: String) -> PixelButton:
	return _buttons.get(id)


func _on_pressed(id: String) -> void:
	if _locked.has(id):
		set_value(value)
		locked_pressed.emit(id)
		return
	if id == value:
		set_value(value)   # 다시 눌러도 꺼지지 않는다
		return
	set_value(id)
	selected.emit(id)
