class_name RatioBarPc
extends Control
## 얇은 비율 막대. 1을 넘으면 꽉 차고 끝에 작은 표시(넘침). 100% 자리에 눈금.

var ratio: float = 0.0:
	set(v):
		ratio = v
		queue_redraw()
var col: Color = Color.WHITE:
	set(v):
		col = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.02, 0.03, 0.05, 0.9))
	var f := clampf(ratio, 0.0, 1.0)
	if f > 0.0:
		draw_rect(Rect2(Vector2(2, 2), Vector2(floorf((size.x - 4) * f), size.y - 4)), col)
	if ratio > 1.001:
		draw_rect(Rect2(Vector2(size.x - 4, 0), Vector2(4, size.y)), col.lightened(0.4))
