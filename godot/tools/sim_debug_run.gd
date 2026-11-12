extends SceneTree
## sim_debug_run — 봇을 N일 돌린 뒤 상태를 들여다본다(튜닝용): 계층별 주거의 수요 원인, 일손, 막힌 것.
##   godot --headless --path godot -s res://tools/sim_debug_run.gd -- bot=balanced days=11 seed=1 tier=3
func _init() -> void:
	var a := {"bot": "balanced", "days": "11", "seed": "1", "tier": "3"}
	for s: String in OS.get_cmdline_user_args():
		var kv := s.split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var sim := Sim.new()
	sim.setup(SimIO.load_db())
	var bot := Bot.new(sim, str(a["bot"]))
	var st := CityState.new()
	sim.new_game(st, int(a["seed"]))
	var every := maxf(1.0, float(bot.c("act_every_h", 1))) / 24.0
	var next := st.econ_days
	while st.econ_days < float(a["days"]):
		if st.econ_days + 1e-9 >= next:
			bot.act(st)
			next += every
		sim.step(st)
		st.events.clear()
	var t := int(a["tier"])
	var causes := {}
	var n := 0
	for b: Dictionary in sim.cover(st)["houses"]:
		if int(b["tier"]) != t:
			continue
		n += 1
		for nid: String in b["needs"]:
			var r: Dictionary = b["needs"][nid]
			if float(r.get("ratio", 0)) < 0.9:
				var k := "%s:%s" % [nid, r.get("cause", "")]
				causes[k] = int(causes.get(k, 0)) + 1
	print("day %.1f tier %d houses %d unmet %s" % [st.econ_days, t, n, str(causes)])
	print("labor ", st.labor)
	print("stock ", st.stock)
	var bl: Dictionary = bot.blocked
	var keys: Array = bl.keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return int(bl[x]) > int(bl[y]))
	for k: String in keys.slice(0, 25):
		print("  ", k, " — ", bl[k])
	var cnt := {}
	for b: Dictionary in st.buildings.values():
		if b["kind"] != "house":
			cnt[str(b["type"]) + ":" + str(b.get("cause", b["kind"]))] = int(cnt.get(str(b["type"]) + ":" + str(b.get("cause", b["kind"])), 0)) + 1
	print(cnt)
	print("unlocked ", st.flags.get("unlock_steps", {}).keys())
	print("goals ", st.flags.get("goals", {}).keys())
	quit()
