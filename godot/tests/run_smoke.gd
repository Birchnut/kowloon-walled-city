extends SceneTree
const RunWorld = preload("res://expedition/RunWorld.gd")
func _initialize() -> void:
	var wd := RunWorld.new()
	wd.fx = false
	wd.setup("scrap_yard", {"stock": {"scrap": 45, "metal": 30, "elec": 16, "wood": 12, "concrete": 12, "parts": 6, "canned": 10}, "danger": 2, "seed": 3})
	var t0 := Time.get_ticks_msec()
	for k in 3000:
		wd.input.move = Vector2(1, 0.2)
		wd.input.aim = wd.player.pos + Vector2(30, 0)
		wd.input.attack = k % 20 == 0
		wd.step(1.0 / 60.0)
	print("ok pos=", wd.player.pos, " hp=", wd.player.hp, " noise=", wd.noise, " ms=", Time.get_ticks_msec() - t0, " enemies=", wd.enemies.size(), " room=", wd.cur_room)
	quit()
