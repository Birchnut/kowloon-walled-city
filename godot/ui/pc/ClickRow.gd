class_name ClickRow
extends PanelContainer
## 누를 수 있는 줄(알림·수요 줄·목록 행). PanelContainer 라서 줄바꿈 글자 높이에 맞게 커진다(Button 은 자식 크기를 모른다).
## 마우스를 올리면 밝아지고, 왼쪽 클릭으로 pressed.

signal pressed

var _hover := false
## 바탕 모양 이름(기본 = 밑줄 줄, 알림은 "PanelNote" 쪽지).
var base := "PanelRow":
	set(v):
		base = v
		theme_type_variation = v


func _init() -> void:
	theme_type_variation = "PanelRow"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		_hover = true
		theme_type_variation = base + "Hi")
	mouse_exited.connect(func() -> void:
		_hover = false
		theme_type_variation = base)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and _hover:
		Sfx.play("click")
		pressed.emit()
		accept_event()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
