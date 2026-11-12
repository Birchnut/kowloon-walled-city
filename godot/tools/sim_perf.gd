extends SceneTree
## sim_perf — 큰 도시(v4: 16×16×10, 주거 약 1,800채)에서 경제 스텝 시간을 잰다. 결과 지문도 찍는다(최적화 전후 비교용).
##   godot --headless --path godot -s res://tools/sim_perf.gd -- [houses=1800] [steps=96] [warm=240] [hazards=1]
## 도시: 층마다 2×2 구멍 아홉 곳(x,y ∈ {3,8,13})에 시장·놀 것·방재·서비스·공급을 두고 나머지 220칸이 주거. 계층은 층마다 다르다.
## hazards=1이면 불·병을 켠다(방재 범위가 덮는 도시 — 정상 운영). 출력: 스텝당 평균/최대 ms, 시스템별 평균 ms, 지문.


func _init() -> void:
	var args := {"houses": "1800", "steps": "96", "warm": "240", "offline": "0", "topup": "1", "hazards": "1"}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var db := SimIO.load_db()
	var sim := Sim.new()
	sim.setup(db)
	var st := make_city(sim, int(args["houses"]))
	if args["hazards"] == "1":
		sim.apply(st, "debug", {"op": "set_hazard", "kind": "fire", "on": true})
		sim.apply(st, "debug", {"op": "set_hazard", "kind": "disease", "on": true})
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
	var all_ms: Array = []
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
		all_ms.append(ms)
	all_ms.sort()
	print("topup=%s " % args["topup"], "STEP avg %.2f ms  median %.2f ms  max %.2f ms  (%d steps, day boundary = settle)" % [tot / n, all_ms[n / 2], mx, n])
	var ids: Array = per.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return per[a] > per[b])
	for id: String in ids:
		print("  %-12s %.2f ms" % [id, float(per[id]) / n])
	print("FINGERPRINT ", fingerprint(sim, st))
	var nd: Variant = sim.systems[sim.sys_ids.find("needs")] if sim.sys_ids.has("needs") else null
	if nd != null and "dbg_slow" in nd:
		print("needs skipped(total) ", nd.dbg_slow, " made ", nd.dbg_made)
	var hz: Dictionary = sim.query(st, "hazards")
	print("hazards: fires %d burnt %d outbreaks %d sick now %d fire cover %.2f trash cover %.2f" % [int(st.stats.get("fires", 0)), int(st.stats.get("burnt", 0)),
		int(st.stats.get("outbreaks", 0)), (hz["disease"]["sick"] as Array).size(), float(hz["fire"]["covered_pct"]), float(hz["disease"]["trash_covered_pct"])])
	var tq := Time.get_ticks_usec()
	for i: int in 10:
		sim.query(st, "hud")
		sim.query(st, "metrics")
	print("query hud+metrics avg %.2f ms" % (float(Time.get_ticks_usec() - tq) / 10000.0))
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


## 2×2 구멍(층마다 아홉 곳): x, y ∈ {3, 8, 13}. 1×2 시설 둘 또는 2×2 하나.
static func make_city(sim: Sim, houses: int) -> CityState:
	var st := CityState.new()
	sim.new_game(st, 1)
	sim.apply(st, "debug", {"op": "unlock_all"})
	st.money = 1.0e7
	st.floors_unlocked = sim.F
	var holes := [["market_mall", ["fire_bucket", "trash_guild"], "market_hall", ["mahjong", "teahouse"], "market_alley", ["clinic", "karaoke"],
			["fire_bucket", "trash_guild"], "bathhouse", ["study", "dentist"]],
		["market_hall", ["clinic", "salon"], ["fire_bucket", "trash_guild"], "market_alley", ["pharmacy", "karaoke"], "#util", ["mahjong", "shrine"],
			"market_mall", ["fire_bucket", "clinic"]]]
	var placed := 0
	var z := 0
	while placed < houses and z < sim.F:
		var k := 0
		for bx: int in [3, 8, 13]:
			for by: int in [3, 8, 13]:
				var o := Vector3i(bx, by, z)
				var what: Variant = holes[z % 2][k]
				k += 1
				if what is Array:
					_put(sim, st, str(what[0]), o)
					_put(sim, st, str(what[1]), o + Vector3i(1, 0, 0))
				elif str(what) == "#util":
					for dx: int in 2:
						for dy: int in 2:
							_put(sim, st, "water_pipe" if dx == 0 else "power_tap", o + Vector3i(dx, dy, 0))
				elif not _put(sim, st, str(what), o):
					_put(sim, st, "market_hall", o)
		var tier := z % 5 + 1
		for x: int in sim.W:
			for y: int in sim.H:
				var p := Vector3i(x, y, z)
				if st.cells.has(p) or placed >= houses:
					continue
				_house(sim, st, p, tier)
				placed += 1
		z += 1
	for g: String in sim.items("goods"):
		st.stock[g] = 5000.0
	var want := {"water_plant": 30, "power_waste": 30}
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
	var k := sim.fp(type, 0)
	for q: Vector3i in Cover.cells_of(p, k.x, k.y, k.z):
		if st.cells.has(q) or q.x >= sim.W or q.y >= sim.H or q.z >= sim.F:
			return false
	var bid := st.new_id()
	st.buildings[bid] = {"id": bid, "kind": "facility", "type": type, "pos": p, "size": maxi(k.x, k.y), "w": k.x, "h": k.y, "d": k.z, "rot": 0,
		"active": false, "paused": false, "staff": 0.0, "eff": 0.0, "cause": "staff", "built": 1, "w_ratio": 1.0, "p_ratio": 1.0,
		"money_stop": false, "vice_rate": 0.0, "burn": "", "build_left": 0.0, "repair": null}
	for q: Vector3i in Cover.cells_of(p, k.x, k.y, k.z):
		st.cells[q] = {"kind": "facility", "bid": bid, "type": type, "tier": 0, "material": "", "seed": 1, "origin": p, "size": maxi(k.x, k.y),
			"w": k.x, "h": k.y, "d": k.z, "rot": 0, "scaffold": false, "burn": "", "sick": false, "trash": 0.0}
	return true


static func _house(sim: Sim, st: CityState, p: Vector3i, tier: int) -> void:
	var cap := int(sim.tier(tier)["cap"])
	var bid := st.new_id()
	st.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": tier, "material": "common" if tier == 1 else "wood",
		"residents": cap, "cap": cap, "happiness": 50.0, "needs": {}, "need_state": "warn", "upgradable": false, "upgrading": null,
		"grow": 0.0, "leave": 0.0, "target": cap, "tax": 0.0, "util_extra": {}, "arriving": 0.0, "burn": "", "sick": false, "repair": null}
	st.cells[p] = {"kind": "house", "bid": bid, "type": "house", "tier": tier, "material": "common", "seed": 1, "origin": p, "size": 1,
		"w": 1, "h": 1, "d": 1, "rot": 0, "scaffold": false, "burn": "", "sick": false, "trash": 0.0}
