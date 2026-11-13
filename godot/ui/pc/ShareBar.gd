class_name ShareBar
extends Control
## 나뉜 막대. segs = [[비율, 색], …](합 1 이하). center = true 이면 가운데 눈금(위아래 차이용: 값은 -1..1, 가운데에서 좌우로).
## 마지막 장·치안·갈등 같은 종이 위 읽는 막대. 바탕은 테마 track 색.

var segs: Array = []:
	set(v):
		segs = v
		queue_redraw()
var center := false:
	set(v):
		center = v
		queue_redraw()
var signed_value := 0.0:
	set(v):
		signed_value = v
		queue_redraw()
var signed_col := Color.WHITE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(260, 12)


func _draw() -> void:
	var track := get_theme_color("track", "Kowloon") if has_theme_color("track", "Kowloon") else Color(0, 0, 0, 0.15)
	var bh := minf(size.y, 12.0)
	var y := floorf((size.y - bh) * 0.5)
	draw_rect(Rect2(0, y, size.x, bh), track)
	if center:
		var mid := size.x * 0.5
		var w := mid * clampf(absf(signed_value), 0.0, 1.0)
		if signed_value >= 0.0:
			draw_rect(Rect2(mid, y, maxf(2.0, w), bh), signed_col)
		else:
			draw_rect(Rect2(mid - maxf(2.0, w), y, maxf(2.0, w), bh), signed_col)
		draw_rect(Rect2(mid - 1, y - 3, 2, bh + 6), Color(0.1, 0.09, 0.07, 0.7))
		return
	var x := 0.0
	for s: Variant in segs:
		var r := clampf(float((s as Array)[0]), 0.0, 1.0)
		var w2 := size.x * r
		if w2 <= 0.0:
			continue
		draw_rect(Rect2(floorf(x), y, maxf(1.0, floorf(w2)), bh), (s as Array)[1])
		x += w2
