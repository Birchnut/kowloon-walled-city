class_name RatioBar
extends Control
## RatioBar — 얇은 비율 막대 하나(수요 충족·재고/한도·공급/수요·인력 have/need).
## 값은 질의가 준 것을 그대로 그린다(계산 없음). 색은 tone(ok/warn/bad/off/gold/jade/red …) → 팔레트.
##
##   var b := RatioBar.make(0.62, "warn")      # 0..1
##   b.set_ratio(1.2, "ok")                     # 1을 넘으면 끝에 작은 넘침 눈금
##   b.marker = 0.8                              # 기준선(선택, -1이면 없음)

var ratio: float = 0.0
var tone: String = "ok"
var marker: float = -1.0
var bar_h: float = 10.0


static func make(r: float = 0.0, t: String = "ok", h: float = 10.0) -> RatioBar:
	var b := RatioBar.new()
	b.ratio = r
	b.tone = t
	b.bar_h = h
	b.custom_minimum_size = Vector2(40, h + 2)
	return b


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_ratio(r: float, t: String = "") -> void:
	ratio = r
	if t != "":
		tone = t
	queue_redraw()


static func tone_color(t: String) -> Color:
	match t:
		"ok", "good", "jade", "full":
			return UI.col("jade")
		"warn", "low", "gold", "short":
			return UI.col("gold")
		"bad", "out", "red", "danger":
			return UI.col("red_hi")
		"off", "none", "dim":
			return UI.col("mute")
		"paper":
			return UI.col("paper2")
	return UI.col("jade")


func _draw() -> void:
	var r := Rect2(0, floorf((size.y - bar_h) * 0.5), size.x, bar_h)
	draw_rect(r, UI.col("out"))
	var inner := r.grow(-2)
	draw_rect(inner, UI.col("ink0"))
	var f := clampf(ratio, 0.0, 1.0)
	var w: float = floorf(inner.size.x * f / UI.UNIT) * UI.UNIT
	if f > 0.0 and w < UI.UNIT:
		w = UI.UNIT
	if w > 0.0:
		var c := tone_color(tone)
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), c)
		draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 2), Vector2(w, 2)), c.darkened(0.35))
	if ratio > 1.001:
		draw_rect(Rect2(inner.end.x - 4, inner.position.y - 2, 4, inner.size.y + 4), UI.col("paper"))
	if marker >= 0.0:
		var x: float = inner.position.x + floorf(inner.size.x * clampf(marker, 0.0, 1.0) / UI.UNIT) * UI.UNIT
		draw_rect(Rect2(x, r.position.y - 2, 2, r.size.y + 4), UI.col("paper"))
