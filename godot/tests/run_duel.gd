extends SceneTree
## 한 종류의 적과 자동 플레이어를 빈 방에서 붙여 본다: -- kind=dog profile=average n=40
const RunWorld = preload("res://expedition/RunWorld.gd")
const AutoPlayer = preload("res://expedition/AutoPlayer.gd")
const RunCfg = preload("res://expedition/RunCfg.gd")
func _initialize() -> void:
	var kind := "dog"
	var prof := "average"
	var n := 40
	var hp0 := 0
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"kind": kind = kv[1]
			"profile": prof = kv[1]
			"n": n = int(kv[1])
			"hp": hp0 = int(kv[1])
	var hits := 0
	var attacks := 0
	var won := 0
	var dodges := 0
	var tsum := 0.0
	for k in n:
		var w := RunWorld.new()
		w.fx = false
		w.setup("scrap_yard", {"stock": RunCfg.file("run_goods")["sample_begin"]["stock"].duplicate(), "danger": 2, "seed": 100 + k})
		for e in w.enemies:
			e.dead = true
		w.enemies.clear()
		w.junks.clear()
		w.wires.clear()
		var e
		if kind == "boss":
			e = w.boss
			var rr: Rect2 = w._room_rect(e.room)
			w.player.pos = Vector2(rr.get_center().x, rr.end.y - 40)
			w.visited[e.room] = true
			w._room_step()
			w.player.hp = int(hp0) if hp0 > 0 else w.player.hp
		else:
			e = w._spawn_enemy(kind, w.player.pos + Vector2(70, 0), w.cur_room)
			e.aware = true
			e.set_state("circle" if kind == "dog" else "chase", 0.8)
		var bot := AutoPlayer.new()
		bot.setup(prof, k)
		var tele_prev := false
		var t := 0.0
		while t < 120.0 and not e.dead and w.player.hp > 0 and not w.finished:
			bot.fill(w.input, w, 1.0 / 60.0)
			w.step(1.0 / 60.0)
			t += 1.0 / 60.0
			if e.state == "tele" and not tele_prev:
				attacks += 1
			tele_prev = e.state == "tele"
		hits += w.hits_taken
		dodges += w.dodges
		tsum += t
		if e.dead:
			won += 1
		if kind == "boss":
			print("  run %d: t=%.0f boss_hp=%d hp=%d" % [k, t, e.hp, w.player.hp])
	print("%s vs %s: attacks=%d hits=%d dodges=%d won=%d/%d avg_t=%.1f" % [prof, kind, attacks, hits, dodges, won, n, tsum / n])
	quit()
