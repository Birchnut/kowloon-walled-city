class_name IsoCamera
extends Camera2D
## IsoCamera — 핀치 줌 + 드래그 팬 (터치 & 마우스). 탭(짧은 터치, 이동 거의 없음) → tapped(world_pos).
## emulate_touch_from_mouse=true 이므로 마우스도 터치 이벤트로 들어온다.

signal tapped(world_pos: Vector2)

var zoom_min: float = 0.6
var zoom_max: float = 3.0
var tap_max_move: float = 12.0   # px, 이 이하로 움직이면 탭
var tap_max_time: float = 0.35   # s

var _touches: Dictionary = {}     # index → position
var _drag_start: Vector2
var _drag_moved: float = 0.0
var _tap_time: float = 0.0
var _pinch_start_dist: float = 0.0
var _pinch_start_zoom: Vector2
var _dragging := false


func _ready() -> void:
	zoom_min = float(Data.cfg("camera/zoom_min", 0.6))
	zoom_max = float(Data.cfg("camera/zoom_max", 3.0))
	zoom = Vector2.ONE * float(Data.cfg("camera/zoom_default", 1.5))
	position_smoothing_enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton:
		# 데스크톱 휠 줌 (터치 에뮬레이션과 별개)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 / 1.1, event.position)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.factor, event.position)
	elif event is InputEventPanGesture:
		position -= event.delta * 4.0 / zoom


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_drag_start = e.position
			_drag_moved = 0.0
			_tap_time = Time.get_ticks_msec() / 1000.0
			_dragging = true
		elif _touches.size() == 2:
			var pts := _touches.values()
			_pinch_start_dist = pts[0].distance_to(pts[1])
			_pinch_start_zoom = zoom
			_dragging = false
	else:
		var was_single := _touches.size() == 1
		_touches.erase(e.index)
		if was_single and _dragging:
			var dt := Time.get_ticks_msec() / 1000.0 - _tap_time
			if _drag_moved <= tap_max_move and dt <= tap_max_time:
				tapped.emit(screen_to_world(e.position))
		_dragging = _touches.size() == 1


func _on_drag(e: InputEventScreenDrag) -> void:
	_touches[e.index] = e.position
	if _touches.size() == 1 and _dragging:
		position -= e.relative / zoom
		_drag_moved += e.relative.length()
	elif _touches.size() >= 2:
		var pts := _touches.values()
		var d: float = pts[0].distance_to(pts[1])
		if _pinch_start_dist > 1.0:
			var factor := d / _pinch_start_dist
			var z := clampf(_pinch_start_zoom.x * factor, zoom_min, zoom_max)
			zoom = Vector2.ONE * z


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var before := screen_to_world(screen_pos)
	var z := clampf(zoom.x * factor, zoom_min, zoom_max)
	zoom = Vector2.ONE * z
	var after := screen_to_world(screen_pos)
	position += before - after


## 화면 좌표 → 월드 좌표 (카메라 기준)
func screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp_size := get_viewport_rect().size
	return position + (screen_pos - vp_size * 0.5) / zoom
