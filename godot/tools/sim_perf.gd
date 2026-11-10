extends SceneTree
## sim_perf — 큰 도시(주거 약 1,000채)에서 경제 스텝 시간을 잰다. 결과 지문도 찍는다(최적화 전후 비교용).
##   godot --headless --path godot -s res://tools/sim_perf.gd -- [houses=1000] [steps=96] [warm=48] [offline=1]
## 도시: 층마다 2×2 자리 여섯 곳(시장·서비스·공급)을 두고 나머지 120칸이 주거. 계층은 층마다 다르다(z % 5 + 1).
## 출력: 스텝당 평균/최대 ms, 시스템별 평균 ms, 지문(계층 인구·돈·재고 합), offline=1이면 미접속 8시간 정산 시간.


func _init() -> void:
	var args := {"houses": "1000", "steps": "96", "warm": "240", "offline": "1", "topup": "1"}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var db := SimIO.load_db()
	var sim := Sim.new()
	sim.setup(db)
	var st := make_city(sim, int(args["houses"]))
	print("houses %d facilities %d pop %d" % [count(st, "house"), count(st, "facility"), st.population()])
	var topup: bool = args["topup"] == "1"
	for i: int in int(args["warm"]):
		if topup:
			_topup(sim, st)
		sim.step(st)
	st.events.clear()
	var nd0: Variant = sim.systems[sim.sys_ids.find("needs")] if sim.sys_ids.has("needs") else null
	if nd0 != null and "dbg_slow" in nd0:
		nd0.dbg_slow = 0
		nd0.dbg_made = 0
	var n := int(args["steps"])
	var per := {}
	var tot := 0.0
	var mx := 0.0
	for i: int in n:
		if topup:
			_topup(sim, st)
		var t0 := Time.get_ticks_usec()
		# 시스템별로 재기 위해 Sim.step을 그대로 흉내 낸다(같은 순서).
		sim._fa.clear()
		for k: int in sim.systems.size():
			var s0 := Time.get_ticks_usec()
			sim.systems[k].tick(st, sim.step_days)
			var id: String = sim.sys_ids[k]
			per[id] = float(per.get(id, 0.0)) + float(Time.get_ticks_usec() - s0) / 1000.0
		sim._fold_flow(st)
		var d0 := st.day
		st.econ_days = roundf((st.econ_days + sim.step_days) / sim.step_days) * sim.step_days
		sim._derive_clock(st)
		if st.day != d0:
			for s: SimSystem in sim.systems:
				s.on_day_end(st, d0)
			for s: SimSystem in sim.systems:
				s.on_day_start(st)
			st.settle()
		st.events.clear()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		tot += ms
		mx = maxf(mx, ms)
	print("topup=%s " % args["topup"], "STEP avg %.2f ms  max %.2f ms  (%d steps)" % [tot / n, mx, n])
	var ids: Array = per.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return per[a] > per[b])
	for id: String in ids:
		print("  %-12s %.2f ms" % [id, float(per[id]) / n])
	print("FINGERPRINT ", fingerprint(sim, st))
	var nd: Variant = sim.systems[sim.sys_ids.find("needs")] if sim.sys_ids.has("needs") else null
	if nd != null and "dbg_slow" in nd:
		print("needs skipped(total) ", nd.dbg_slow, " made ", nd.dbg_made)
	if args["offline"] == "1":
		var t1 := Time.get_ticks_msec()
		var econ := 8.0 * 3600.0 * float(sim.cfg("time.offline_speed", 0.25)) / float(sim.cfg("time.seconds_per_day", 600))
		var r := sim.fast_forward(st, econ)
		print("OFFLINE 8h (%.1f econ days) %.2f s  lines %d" % [econ, float(Time.get_ticks_msec() - t1) / 1000.0, (r.get("lines", []) as Array).size()])
		print("FINGERPRINT_OFF ", fingerprint(sim, st))
	sim.systems.clear()
	quit()


## 정상 운영 흉내: 생산 시설이 없는 상품을 매 스텝 채운다(계약·생산이 돌아가는 도시). topup=0이면 바닥나는 위기 도시.
static func _topup(sim: Sim, st: CityState) -> void:
	for g: String in sim.items("goods"):
		if float(st.stock.get(g, 0.0)) < 3000.0:
			st.stock[g] = 5000.0


static func count(st: CityState, kind: String) -> int:
	var n := 0
	for b: Dictionary in st.buildings.values():
		if b["kind"] == kind:
			n += 1
	return n


static func fingerprint(sim: Sim, st: CityState) -> String:
	var m := Metrics.compute(sim, st)
	var s := 0.0
	for g: String in st.stock:
		s += float(st.stock[g])
	return "pop %d/%d/%d/%d/%d money %.3f stock %.3f hap %.4f" % [int(m["pop.t1"]), int(m["pop.t2"]), int(m["pop.t3"]), int(m["pop.t4"]), int(m["pop.t5"]), st.money, s, st.happiness]


## 2×2 자리(층마다 여섯 곳): x∈{1,5,9}, y∈{2,8}.
static func make_city(sim: Sim, houses: int) -> CityState:
	var st := CityState.new()
	sim.new_game(st, 1)
	sim.apply(st, "debug", {"op": "unlock_all"})
	st.money = 1.0e7
	st.floors_unlocked = sim.F
	var slots_fac := [["market4", "bathhouse", "casino", "market3", "market2", "#small"],
		["market3", "#util", "market2", "market4", "#small", "bathhouse"]]
	var smalls := ["stall", "shrine", "teahouse", "mahjong", "dentist", "study", "karaoke", "roof_garden", "suit_shop", "radio_shop"]
	var utils := ["power_ext", "power_ext", "water_ext", "water_ext"]
	var placed := 0
	var z := 0
	var si := 0
	while placed < houses and z < sim.F:
		var k := 0
		for bx: int in [1, 5, 9]:
			for by: int in [2, 8]:
				var o := Vector3i(bx, by, z)
				var what: String = slots_fac[z % 2][k]
				k += 1
				if what == "#small" or what == "#util":
					var lst: Array = smalls if what == "#small" else utils
					var j := 0
					for dx: int in 2:
						for dy: int in 2:
							var t: String = lst[(si + j) % lst.size()]
							j += 1
							_put(sim, st, t, o + Vector3i(dx, dy, 0))
					si += 4
				else:
					_put(sim, st, what, o)
		var tier := z % 5 + 1
		for x: int in sim.W:
			for y: int in sim.H:
				var p := Vector3i(x, y, z)
				if st.cells.has(p) or placed >= houses:
					continue
				_house(sim, st, p, tier)
				placed += 1
		z += 1
	# 넉넉한 재고와 넉넉한 물·전기(시험 도시: 바깥 연결 추가분)
	for g: String in sim.items("goods"):
		st.stock[g] = 5000.0
	var want := {"water_plant": 30, "chp": 12}
	for type: String in want:
		var n: int = want[type]
		for zz: int in range(sim.F - 1, -1, -1):
			for x: int in range(0, sim.W - 1, 2):
				for y: int in range(0, sim.H - 1, 2):
					if n > 0 and _put(sim, st, type, Vector3i(x, y, zz)):
						n -= 1
	st.layout_changed()
	return st


static func _put(sim: Sim, st: CityState, type: String, p: Vector3i) -> bool:
	var d := sim.bdef(type)
	var size := int(d.get("size", 1))
	for dx: int in size:
		for dy: int in size:
			if st.cells.has(p + Vector3i(dx, dy, 0)) or p.x + dx >= sim.W or p.y + dy >= sim.H or p.z >= sim.F:
				return false
	var bid := st.new_id()
	st.buildings[bid] = {"id": bid, "kind": "facility", "type": type, "pos": p, "size": size, "active": false, "paused": false, "staff": 0.0,
		"eff": 0.0, "cause": "staff", "built": 1, "w_ratio": 1.0, "p_ratio": 1.0, "money_stop": false, "vice_rate": 0.0}
	for q: Vector3i in Cover.footprint(p, size):
		st.cells[q] = {"kind": "facility", "bid": bid, "type": type, "tier": 0, "material": "", "seed": 1, "origin": p, "size": size, "scaffold": false}
	return true


static func _house(sim: Sim, st: CityState, p: Vector3i, tier: int) -> void:
	var cap := int(sim.tier(tier)["cap"])
	var bid := st.new_id()
	st.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": tier, "material": "common" if tier == 1 else "wood",
		"residents": cap, "cap": cap, "happiness": 50.0, "needs": {}, "need_state": "warn", "upgradable": false, "upgrading": null,
		"grow": 0.0, "leave": 0.0, "target": cap, "tax": 0.0, "util_extra": {}}
	st.cells[p] = {"kind": "house", "bid": bid, "type": "house", "tier": tier, "material": "common", "seed": 1, "origin": p, "size": 1, "scaffold": false}
