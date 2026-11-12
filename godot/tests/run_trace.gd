extends SceneTree
## 한 판을 자동으로 돌리며 몇 초마다 봇의 목표·위치를 찍는다: -- profile=average seed=7 every=20
const RunWorld = preload("res://expedition/RunWorld.gd")
const AutoPlayer = preload("res://expedition/AutoPlayer.gd")
const RunCfg = preload("res://expedition/RunCfg.gd")
func _initialize() -> void:
	var prof := "average"
	var sd := 7
	var every := 20.0
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"profile": prof = kv[1]
			"seed": sd = int(kv[1])
			"every": every = float(kv[1])
	var w := RunWorld.new()
	w.fx = false
	w.setup("scrap_yard", {"stock": RunCfg.file("run_goods")["sample_begin"]["stock"].duplicate(), "danger": 2, "seed": sd})
	var bot := AutoPlayer.new()
	bot.setup(prof, sd)
	var next := 0.0
	while not w.finished and w.time < 700:
		bot.fill(w.input, w, 1.0 / 30.0)
		w.step(1.0 / 30.0)
		if w.time >= next:
			next += every
			var en := 0
			for e in w.enemies:
				if not e.dead and e.aware: en += 1
			print("vel=%s knock=%s hs=%.2f open=%s ", w.player.vel, " ", w.player.knock, " ", w.hitstop, " ", w.pack_open)
			print("t=%.0f room=%d pos=%s cell=%s hp=%d goal=%s move=%s state=%s aware=%d slots=%d noise=%.0f/%d" % [w.time, w.cur_room, w.player.pos.round(), w.to_cell(w.player.pos), w.player.hp, bot.goal_desc, w.input.move, w.player.state, en, w.pack_slots_used(), w.noise, w.noise_level])
	print("end ", w.outcome, " ", w.time)
	quit()
