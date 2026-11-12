class_name FootprintDraw
extends Control
## 시설 모양 그림: 발자국 w×h 칸(금색) + 범위 r(옅은 사각, 칸에 맞춤). 층이 둘이면 옆에 겹친 판.
## 범위가 크면 줄여 그린다(칸 크기 4~12px).

var w: int = 1
var h: int = 1
var floors: int = 1
var r: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(120, 120)


func _draw() -> void:
	var span := maxi(w, h) + 2 * r
	var cell := clampf(floorf(112.0 / float(maxi(span, 1))), 4.0, 14.0)
	var tot := Vector2((w + 2 * r) * cell, (h + 2 * r) * cell)
	var o := ((size - tot) * 0.5).floor()
	if r > 0:
		draw_rect(Rect2(o, tot), Color(0.25, 0.7, 0.56, 0.18))
		for i in range(w + 2 * r + 1):
			draw_line(o + Vector2(i * cell, 0), o + Vector2(i * cell, tot.y), Color(0.25, 0.7, 0.56, 0.25), 1.0)
		for j in range(h + 2 * r + 1):
			draw_line(o + Vector2(0, j * cell), o + Vector2(tot.x, j * cell), Color(0.25, 0.7, 0.56, 0.25), 1.0)
		draw_rect(Rect2(o, tot), Color(0.5, 0.88, 0.75, 0.8), false, 2.0)
	var fo := o + Vector2(r * cell, r * cell)
	if floors > 1:
		draw_rect(Rect2(fo + Vector2(4, -4), Vector2(w * cell, h * cell)), Color(0.6, 0.45, 0.17, 0.9))
	draw_rect(Rect2(fo, Vector2(w * cell, h * cell)), Color(0.91, 0.71, 0.29, 1.0))
	for i in range(1, w):
		draw_line(fo + Vector2(i * cell, 0), fo + Vector2(i * cell, h * cell), Color(0.36, 0.26, 0.09), 1.0)
	for j in range(1, h):
		draw_line(fo + Vector2(0, j * cell), fo + Vector2(w * cell, j * cell), Color(0.36, 0.26, 0.09), 1.0)
