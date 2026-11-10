class_name Meter
extends Control
## Meter — 얇은 지표 막대(위신·악명·민심). 이름표 + 막대. 값이 바뀌면 굴러가고 한 번 번쩍인다.

var caption: String = "":
	set(v):
		caption = v
		queue_redraw()
var tone: String = "gold"       # 팔레트 이름: gold / red / jade
var max_value: float = 100.0
var shown: float = 0.0          # 화면에 그려지는 값(트윈)
var _target: float = -1.0
var _flash: float = 0.0
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(60, 20)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_value(v: float, animate: bool = true) -> void:
	v = clampf(v, 0.0, max_value)
	if is_equal_approx(v, _target):
		return
	var first := _target < 0.0
	_target = v
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if first or not animate or not is_inside_tree():
		shown = v
		queue_redraw()
		return
	_flash = 1.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(_set_shown, shown, v, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_flash, 1.0, 0.0, 0.8)


func _set_shown(v: float) -> void:
	shown = v
	queue_redraw()


func _set_flash(v: float) -> void:
	_flash = v
	queue_redraw()


func _draw() -> void:
	var f := UI.font("small")
	var fs := UI.font_size("small")
	var cap_w := 0.0
	if caption != "":
		cap_w = f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0
		draw_string(f, Vector2(0, floor((size.y - f.get_height(fs)) * 0.5) + f.get_ascent(fs)), caption,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.col("dim").lerp(UI.col(tone + "_hi"), _flash))
	var h := 10.0
	var r := Rect2(cap_w, floor((size.y - h) * 0.5) + 1.0, maxf(8.0, size.x - cap_w), h)
	# 홈
	draw_rect(r, UI.col("out"))
	draw_rect(r.grow(-2), UI.col("ink0"))
	# 채움
	var inner := r.grow(-2)
	var w: float = floor(inner.size.x * clampf(shown / max_value, 0.0, 1.0) / UI.UNIT) * UI.UNIT
	if w > 0.0:
		var base := UI.col(tone)
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), base.lerp(Color.WHITE, _flash * 0.6))
		draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 2), Vector2(w, 2)), UI.col(tone + "_d"))
	# 눈금(25/50/75)
	for i in [1, 2, 3]:
		var x: float = inner.position.x + floor(inner.size.x * i / 4.0 / UI.UNIT) * UI.UNIT
		draw_rect(Rect2(x, inner.position.y, 2, 2), UI.col("ink3"))
