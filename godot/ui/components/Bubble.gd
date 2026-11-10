class_name Bubble
extends Control
## Bubble — 수금 말풍선. 꼬리 끝이 기준점(anchor). 금이 차오르고, 다 차면 통통 뛰고, 떼이는 중이면 빨갛게 떤다.
## 누르면 tapped(point_id). 터치 영역 56×62.

signal tapped(point_id: int)

const W := 44.0
const H := 50.0

var point_id: int = 0
var ratio: float = 0.0:
	set(v):
		if not is_equal_approx(v, ratio):
			ratio = clampf(v, 0.0, 1.0)
			queue_redraw()
var ready_now: bool = false:
	set(v):
		if v != ready_now:
			ready_now = v
			_update_anim()
var hot: bool = false:
	set(v):
		if v != hot:
			hot = v
			_update_anim()
var anchor: Vector2 = Vector2.ZERO:
	set(v):
		anchor = v
		_apply_pos()
var _t: float = 0.0
var _ofs: Vector2 = Vector2.ZERO
var _pop: float = 0.0      # 등장 연출 0..1


func _init() -> void:
	size = Vector2(56, 62)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_t = randf() * 3.0
	set_process(false)


func _ready() -> void:
	_pop = 0.0
	var tw := create_tween()
	tw.tween_method(_set_pop, 0.0, 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_update_anim()


func _set_pop(v: float) -> void:
	_pop = v
	pivot_offset = Vector2(size.x * 0.5, size.y)
	scale = Vector2(v, v)


func _update_anim() -> void:
	set_process(ready_now or hot)
	if not (ready_now or hot):
		_ofs = Vector2.ZERO
		_apply_pos()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var o := Vector2.ZERO
	if hot:
		# 떼이는 중: 좌우로 잘게 떤다
		o.x = 2.0 if fmod(_t, 0.12) < 0.06 else -2.0
		if fmod(_t, 1.6) > 0.8:
			o.x = 0.0
	elif ready_now:
		# 준비됨: 2px씩 통통
		var ph := fmod(_t, 1.2)
		o.y = -4.0 if ph < 0.15 else (-2.0 if ph < 0.3 else 0.0)
	if o != _ofs:
		_ofs = o
		_apply_pos()


func _apply_pos() -> void:
	position = UI.snap(anchor - Vector2(size.x * 0.5, size.y) + _ofs)


func _draw() -> void:
	var bg := UI.misc("bubble_bg")
	if bg == null:
		draw_circle(size * 0.5, 20, UI.col("ink2"))
		return
	var o := Vector2((size.x - W) * 0.5, size.y - H)
	draw_texture(bg, o)
	# 채움: 아래에서 위로
	var fill := UI.misc("bubble_fill_ready" if (ready_now or hot) else "bubble_fill")
	var body_h := 42.0
	var fh: float = floor(body_h * ratio / UI.UNIT) * UI.UNIT
	if fill != null and fh > 0.0:
		var src := Rect2(0, body_h - fh, W, fh)
		draw_texture_rect_region(fill, Rect2(o + Vector2(0, body_h - fh), Vector2(W, fh)), src)
	var coin := UI.icon("coin")
	if coin != null:
		draw_texture(coin, o + Vector2((W - 24) * 0.5, 10), Color.WHITE if (ready_now or hot or ratio > 0.5) else Color(1, 1, 1, 0.8))
	if hot:
		var ring := UI.misc("bubble_ring_hot")
		if ring != null:
			draw_texture(ring, o)
	elif ready_now:
		var ring2 := UI.misc("bubble_ring_ready")
		if ring2 != null:
			draw_texture(ring2, o)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		accept_event()
		tapped.emit(point_id)


## 꼬리 끝이 아니라 몸통 가운데(동전이 날아갈 출발점).
func coin_origin() -> Vector2:
	return global_position + Vector2(size.x * 0.5, size.y - H + 22.0)
