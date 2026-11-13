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
	# 가는 막대: 높이는 최대 6px, 칸 가운데. 바탕색은 테마(먹빛 / 종이)에서 읽는다.
	var bh := minf(size.y, 6.0)
	var y := floorf((size.y - bh) * 0.5)
	var track := get_theme_color("track", "Kowloon") if has_theme_color("track", "Kowloon") else Color(1, 1, 1, 0.14)
	draw_rect(Rect2(0, y, size.x, bh), track)
	var f := clampf(ratio, 0.0, 1.0)
	if f > 0.0:
		draw_rect(Rect2(0, y, maxf(2.0, floorf(size.x * f)), bh), col)
	if ratio > 1.001:
		draw_rect(Rect2(size.x - 3, y - 1, 3, bh + 2), col.lightened(0.3))
