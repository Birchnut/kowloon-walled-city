class_name DragScroll
extends Control
## DragScroll — 손가락(또는 마우스)으로 끄는 스크롤 영역. 가로/세로 한 축.
## ScrollContainer 대신 쓰는 이유: 끌기 시작하면 안쪽 버튼의 눌림을 확실히 취소해야 하고
## (스크롤하다 버튼이 눌리면 안 된다), 데스크톱·웹에서도 마우스로 끌 수 있어야 한다.
##
##   var sc := DragScroll.new(); sc.horizontal = true
##   sc.set_content(hbox)       # 안쪽 버튼들은 자동으로 mouse_filter = PASS 가 된다

signal scrolled

const DRAG_START := 10.0

var horizontal: bool = false
var content: Control = null
var offset: float = 0.0
var _pressing: bool = false
var _dragging: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _vel: float = 0.0
var _thumb: ColorRect


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_thumb = ColorRect.new()
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.z_index = 1
	add_child(_thumb)
	set_process(false)


func _ready() -> void:
	_thumb.color = UI.col("line")
	resized.connect(_relayout)


func set_content(c: Control) -> void:
	if content != null and content.get_parent() == self:
		remove_child(content)
		content.queue_free()
	content = c
	add_child(c)
	move_child(_thumb, -1)
	c.minimum_size_changed.connect(_relayout)
	offset = 0.0
	adopt_buttons()
	_relayout()


## 안쪽 버튼이 이벤트를 위로 흘려보내게 한다(내용이 바뀌면 다시 부를 것).
func adopt_buttons(node: Node = null) -> void:
	if node == null:
		node = content
	if node == null:
		return
	for ch in node.get_children():
		if ch is BaseButton:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		adopt_buttons(ch)


func _get_minimum_size() -> Vector2:
	if content == null:
		return Vector2.ZERO
	var m := content.get_combined_minimum_size()
	return Vector2(0, m.y) if horizontal else Vector2(m.x, 0)


func max_offset() -> float:
	if content == null:
		return 0.0
	return maxf(0.0, (content.size.x - size.x) if horizontal else (content.size.y - size.y))


func scroll_to(v: float) -> void:
	offset = clampf(v, 0.0, max_offset())
	_apply()


func _relayout() -> void:
	if content == null:
		return
	if horizontal:
		content.size = Vector2(maxf(content.get_combined_minimum_size().x, size.x), size.y)
	else:
		content.size = Vector2(size.x, 0)
		content.size = Vector2(size.x, maxf(content.get_combined_minimum_size().y, size.y))
	offset = clampf(offset, 0.0, max_offset())
	_apply()
	update_minimum_size()


func _apply() -> void:
	if content == null:
		return
	var o: float = round(offset / UI.UNIT) * UI.UNIT
	content.position = Vector2(-o, 0) if horizontal else Vector2(0, -o)
	var mo := max_offset()
	_thumb.visible = mo > 1.0
	if mo > 1.0:
		if horizontal:
			var w: float = maxf(24.0, size.x * size.x / content.size.x)
			_thumb.size = Vector2(w, 2)
			_thumb.position = Vector2((size.x - w) * offset / mo, size.y - 2)
		else:
			var h: float = maxf(24.0, size.y * size.y / content.size.y)
			_thumb.size = Vector2(2, h)
			_thumb.position = Vector2(size.x - 2, (size.y - h) * offset / mo)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_pressing = true
				_dragging = false
				_press_pos = ev.global_position
				_vel = 0.0
				set_process(false)
			else:
				if _dragging:
					accept_event()
					set_process(absf(_vel) > 40.0)
				_pressing = false
				_dragging = false
		elif ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			var dir := -1.0 if ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1.0
			scroll_to(offset + dir * 56.0)
			scrolled.emit()
			accept_event()
	elif ev is InputEventMouseMotion and _pressing:
		var d: Vector2 = ev.global_position - _press_pos
		var along := d.x if horizontal else d.y
		var cross := d.y if horizontal else d.x
		if not _dragging and absf(along) > DRAG_START and absf(along) >= absf(cross):
			_dragging = true
			_cancel_presses(content)
		if _dragging:
			var rel: float = ev.relative.x if horizontal else ev.relative.y
			scroll_to(offset - rel)
			_vel = lerpf(_vel, -rel * 60.0, 0.5)
			scrolled.emit()
			accept_event()


## 끌기가 시작되면 안쪽 버튼들의 "누르는 중"을 취소한다(disabled 를 껐다 켜면 눌림 시도가 지워진다).
func _cancel_presses(node: Node) -> void:
	if node == null:
		return
	for ch in node.get_children():
		if ch is BaseButton and not (ch as BaseButton).disabled:
			(ch as BaseButton).disabled = true
			(ch as BaseButton).disabled = false
		_cancel_presses(ch)


func _process(delta: float) -> void:
	# 관성
	offset += _vel * delta
	_vel *= pow(0.04, delta)
	if offset <= 0.0 or offset >= max_offset() or absf(_vel) < 20.0:
		_vel = 0.0
		set_process(false)
	scroll_to(offset)
