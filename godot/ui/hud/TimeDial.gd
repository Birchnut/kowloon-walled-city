class_name TimeDial
extends Control
## TimeDial — 손톱만 한 해/달 시계. 성채 실루엣 위로 해가 뜨고 진다. Game.time_of_day() 로 돈다.

var tod: float = 0.25:
	set(v):
		if absf(v - tod) > 0.002:
			tod = v
			queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var disc := UI.misc("dial_disc")
	var ring := UI.misc("dial_ring")
	var city := UI.misc("dial_city")
	if disc == null:
		return
	# 하늘색: 밤(남색) ↔ 새벽·저녁(자주) ↔ 낮(뿌연 하늘)
	var sun_h := sin((tod - 0.25) * TAU)          # -1 한밤 … 1 한낮
	var sky := Color("1a2147")
	if sun_h > 0.25:
		sky = Color("7fa3b5")
	elif sun_h > -0.15:
		sky = Color("b4605a").lerp(Color("7fa3b5"), clampf((sun_h + 0.15) / 0.4, 0.0, 1.0)) if sun_h > 0.0 \
				else Color("1a2147").lerp(Color("b4605a"), clampf((sun_h + 0.15) / 0.15, 0.0, 1.0))
	draw_texture(disc, Vector2.ZERO, sky)
	var c := Vector2(20, 26)
	var r := 15.0
	var is_day := tod >= 0.25 and tod < 0.75
	var a := ((tod - 0.25) / 0.5 if is_day else fposmod(tod - 0.75, 1.0) / 0.5) * PI
	var p := c + Vector2(-cos(a) * r, -sin(a) * r)
	var spr := UI.icon("sun" if is_day else "moon")
	if spr != null:
		draw_texture(spr, UI.snap(p - Vector2(7, 7)))
	if city != null:
		draw_texture(city, Vector2.ZERO, UI.col("ink0") if sun_h > 0.0 else UI.col("out"))
		if sun_h <= 0.0:
			# 밤에는 창 몇 개
			for w in [Vector2(12, 28), Vector2(20, 30), Vector2(26, 28), Vector2(16, 32)]:
				draw_rect(Rect2(w, Vector2(2, 2)), UI.col("gold"))
	if ring != null:
		draw_texture(ring, Vector2.ZERO)
