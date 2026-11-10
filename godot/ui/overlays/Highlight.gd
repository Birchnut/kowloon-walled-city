class_name Highlight
extends Control
## Highlight — 튜토리얼 강조. 대상의 화면 영역을 꺾쇠로 감싸고 화살표를 통통 튀긴다. 터치를 먹지 않는다.
##   hl.point_at(func() -> Rect2: return some_control.get_global_rect(), true)   # true = 주변을 어둡게

var _target: Callable
var _dim: bool = false
var _rect: Rect2 = Rect2()
var _frame: PanelContainer
var _arrow: TextureRect
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = UI.panel("PanelBracket")
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_arrow = UI.icon_rect("down", Color.WHITE)
	add_child(_arrow)
	visible = false
	set_process(false)


func _ready() -> void:
	_arrow.modulate = UI.col("gold_hi")


func point_at(target: Callable, dim: bool = false) -> void:
	_target = target
	_dim = dim
	visible = true
	set_process(true)
	_process(0.0)


func clear() -> void:
	_target = Callable()
	visible = false
	set_process(false)
	_rect = Rect2()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var r := Rect2()
	if _target.is_valid():
		var v: Variant = _target.call()
		if v is Rect2:
			r = v
	var has := r.size.x > 1.0 and r.size.y > 1.0
	_frame.visible = has
	_arrow.visible = has
	if r != _rect:
		_rect = r
		queue_redraw()
	if not has:
		return
	var pulse := 2.0 if fmod(_t, 0.7) < 0.35 else 0.0
	var g := r.grow(6.0 + pulse)
	_frame.position = UI.snap(g.position - global_position)
	_frame.size = UI.snap(g.size)
	var bob := 4.0 if fmod(_t, 0.7) < 0.35 else 0.0
	var above := r.position.y > 150.0
	_arrow.flip_v = not above
	_arrow.position = UI.snap(Vector2(r.get_center().x - 12.0, (r.position.y - 38.0 - bob) if above else (r.end.y + 14.0 + bob)) - global_position)


func _draw() -> void:
	if not _dim or _rect.size.x <= 1.0:
		return
	var c := Color(UI.col("out"), 0.55)
	var r := Rect2(_rect.position - global_position, _rect.size).grow(6.0)
	draw_rect(Rect2(0, 0, size.x, r.position.y), c)
	draw_rect(Rect2(0, r.end.y, size.x, size.y - r.end.y), c)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), c)
	draw_rect(Rect2(r.end.x, r.position.y, size.x - r.end.x, r.size.y), c)
