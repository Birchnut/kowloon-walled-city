extends SimSystem
## 살림 — 식량·자재·일자리의 하루 흐름(매시 1/24씩).
##  · 일자리: 집이 있는 일할 수 있는 가구를 빈 일자리에 붙인다(households.json job_pref가 높은 업종 먼저). 가구 1 = 일손 1.
##  · 생산: 시설·가게의 produces × 일손 비율. 볕을 먹는 것(sun)은 그 칸의 볕만큼만(최소 sun_floor). 돈 생산은 바로 금고로.
##  · 소비: 집 있는 사람 1명당 eat. 공동부엌 하나마다 food_save만큼 덜 든다. 모자라면 돈으로 사 온다(food_price).
##    돈도 없으면 굶는다 → state.flags.food_short(0..1)에 적힌다(민심·이탈은 다른 시스템이 읽는다).
##  · 유지비: 시설 upkeep + 카드가 건 일일 요금(flags.daily_fee). 빚은 max_debt까지.
##  · 하루 끝: 자재가 목표보다 적으면 남는 돈(money_reserve 초과분)의 materials_buy_share까지 써서 사들인다. 일손 0으로 close_days를 버틴 가게, 금지된 업종의 가게는 문을 닫는다.
## 수치: data/economy.json "economy" · 생산량은 facilities.json / businesses.json.


func on_new_game(state: CityState) -> void:
	var s: Dictionary = sim.tune("economy.start", {})
	state.money = float(s.get("money", 60))
	state.food = float(s.get("food", 40))
	state.materials = float(s.get("materials", 20))


func _def(b: Dictionary) -> Dictionary:
	return sim.item("facilities" if b.get("facility", false) else "businesses", str(b.get("type", "")))


func _staff(b: Dictionary) -> float:
	var jobs := int(b.get("jobs", 0))
	return 1.0 if jobs <= 0 else float((b.get("workers", []) as Array).size()) / float(jobs)


func on_hour(state: CityState, _hour: int) -> void:
	for r: Dictionary in Ops.take_queue(state, "close_requests"):
		_close_matching(state, str(r.get("match", "")), int(r.get("count", 1)), "단속과 결재 끝에 가게가 빠진 자리.")
	_assign_jobs(state)
	var k := sim.pace("economy_mult") / 24.0
	var made := 0.0
	for b: Dictionary in state.businesses.values():
		var p: Dictionary = _def(b).get("produces", {})
		if p.is_empty():
			continue
		var staff := _staff(b)
		var sun := 1.0
		if _def(b).get("sun", false):
			sun = maxf(sim.num("economy.sun_floor", 0.3), Grid.sunlight(sim, state, b["cells"][0]))
		made += float(p.get("food", 0.0)) * staff * sun * sim.mod(state, "food.yield") * k
		state.materials += float(p.get("materials", 0.0)) * staff * sim.mod(state, "materials.yield") * k
		state.money += float(p.get("money", 0.0)) * staff * k
	state.food += made
	var m := sim.metrics(state)
	var need := 0.0
	for h: Dictionary in state.households.values():
		if h.get("home") != null:
			need += float(h["size"]) * float(sim.item("households", str(h["type"])).get("eat", 1.0))
	need *= sim.mod(state, "food.eat") * (1.0 - minf(0.3, float(m.get("count.kitchen", 0.0)) * float(sim.item("facilities", "kitchen").get("food_save", 0.0)))) / 24.0
	state.food -= need
	var unmet := 0.0
	if state.food < 0.0:
		var price := sim.num("economy.food_price", 0.4)
		var buy: float = minf(-state.food, maxf(0.0, state.money) / price)
		state.money -= buy * price
		state.food += buy
		state.stats["food_bought"] = float(state.stats.get("food_bought", 0.0)) + buy * price
		unmet = maxf(0.0, -state.food)
		state.food = 0.0
	state.flags["food_need_today"] = float(state.flags.get("food_need_today", 0.0)) + need
	state.flags["food_unmet_today"] = float(state.flags.get("food_unmet_today", 0.0)) + unmet
	state.stats["food_made_rate"] = made * 24.0
	state.stats["food_eat_rate"] = need * 24.0
	var fee := float(state.flags.get("daily_fee", 0.0))
	for c: Dictionary in state.cells.values():
		if c.get("kind", "") == "facility":
			fee += float(sim.def_of(c).get("upkeep", 0.0)) * sim.mod(state, "upkeep")
	if state.money > -sim.num("economy.max_debt", 200.0):
		state.money -= fee * k
	state.stats["upkeep_rate"] = fee


func _assign_jobs(state: CityState) -> void:
	var seekers: Array = []
	for id: int in state.households:
		var h: Dictionary = state.households[id]
		if h.get("home") != null and int(h.get("job", 0)) == 0 and sim.item("households", str(h["type"])).get("works", true):
			seekers.append(id)
	if seekers.is_empty():
		return
	seekers.sort()
	var open: Array = []
	for bid: int in state.businesses:
		if int(state.businesses[bid].get("jobs", 0)) > (state.businesses[bid]["workers"] as Array).size():
			open.append(bid)
	open.sort()
	for id: int in seekers:
		if open.is_empty():
			break
		var pref: Dictionary = sim.item("households", str(state.households[id]["type"])).get("job_pref", {})
		var best := 0
		var best_w := 0.0
		for bid: int in open:
			var b: Dictionary = state.businesses[bid]
			var w := float(pref.get(b.get("group", ""), 1.0)) * (1.5 - 0.5 * _staff(b))
			if w > best_w:
				best_w = w
				best = bid
		if best == 0:
			continue
		state.businesses[best]["workers"].append(id)
		state.households[id]["job"] = best
		if _staff(state.businesses[best]) >= 1.0:
			open.erase(best)


func on_day_end(state: CityState) -> void:
	var need := float(state.flags.get("food_need_today", 0.0))
	state.flags["food_short"] = (float(state.flags.get("food_unmet_today", 0.0)) / need) if need > 0.0 else 0.0
	state.flags["food_need_today"] = 0.0
	state.flags["food_unmet_today"] = 0.0
	if float(state.flags["food_short"]) > 0.05:
		state.stats["hungry_days"] = int(state.stats.get("hungry_days", 0)) + 1
		if not sim.offline:
			sim.say(state, "먹을 게 모자랐다. 솥이 비었다.", "bad")
	# 자재 사들이기
	var hh := float(state.households.size())
	var target := sim.num("economy.materials_target", 30.0) + hh * sim.num("economy.materials_target_per_household", 0.25)
	var spare := state.money - sim.num("economy.money_reserve", 30.0)
	if state.materials < target and spare > 0.0:
		var price := sim.num("economy.materials_price", 2.0)
		var cap := (sim.num("economy.materials_buy_per_day", 20.0) + hh * sim.num("economy.materials_buy_per_household", 0.15)) * sim.mod(state, "materials.buy")
		var buy: float = minf(minf(target - state.materials, cap), spare * sim.num("economy.materials_buy_share", 0.3) / price)
		state.materials += buy
		state.money -= buy * price
		state.stats["materials_bought"] = float(state.stats.get("materials_bought", 0.0)) + buy * price
	if sim.offline:
		return
	# 문 닫는 가게: 일손이 끊긴 곳, 금지된 업종
	var ids: Array = state.businesses.keys()
	ids.sort()
	for bid: int in ids:
		var b: Dictionary = state.businesses[bid]
		if b.get("facility", false):
			continue
		var empty: int = (int(b.get("empty_days", 0)) + 1) if (int(b.get("jobs", 0)) > 0 and (b["workers"] as Array).is_empty()) else 0
		b["empty_days"] = empty
		var banned: bool = str(state.policies.get("permit." + str(b["group"]), "allow")) == "ban" and not b.get("protected", false)
		if empty >= int(sim.num("economy.close_days", 3)):
			_close(state, bid, "일손을 못 구해 문을 닫았다", "일손을 못 구해 가게가 빠진 자리.")
		elif banned and sim.roll(state) < sim.num("economy.ban_close_per_day", 0.34):
			_close(state, bid, "금지령에 간판을 내렸다", "금지령으로 가게가 빠진 자리.")


func _close(state: CityState, bid: int, log_tail: String, why: String) -> void:
	sim.say(state, "%s이(가) %s." % [_def(state.businesses[bid]).get("name", "가게"), log_tail], "bad")
	Ops.close_business(sim, state, bid, why)
	sim.touch()


func _close_matching(state: CityState, what: String, count: int, why: String) -> void:
	var ids: Array = []
	for bid: int in state.businesses:
		var b: Dictionary = state.businesses[bid]
		if not b.get("facility", false) and (str(b["type"]) == what or str(b["group"]) == what):
			ids.append(bid)
	ids.sort()
	for i: int in mini(count, ids.size()):
		var bid: int = ids[sim.roll_range(state, 0, ids.size() - 1)]
		ids.erase(bid)
		_close(state, bid, "문을 닫았다", why)


func metrics(state: CityState, m: Dictionary) -> void:
	m["food_short"] = float(state.flags.get("food_short", 0.0))
	m["food_balance"] = float(state.stats.get("food_made_rate", 0.0)) - float(state.stats.get("food_eat_rate", 0.0))


func describe(state: CityState, pos: Vector3i, cell: Dictionary, info: Dictionary) -> void:
	var bid := Ops.business_at(state, pos)
	if bid == 0:
		return
	var b: Dictionary = state.businesses[bid]
	var d := _def(b)
	if int(b.get("jobs", 0)) > 0:
		info["lines"].append("일손 %d/%d" % [(b["workers"] as Array).size(), int(b["jobs"])])
	var p: Dictionary = d.get("produces", {})
	var bits: Array = []
	for pair: Array in [["food", "식량"], ["materials", "자재"], ["money", "돈"]]:
		if float(p.get(pair[0], 0.0)) > 0.0:
			var x := float(p[pair[0]]) * _staff(b)
			if pair[0] == "food" and d.get("sun", false):
				x *= maxf(sim.num("economy.sun_floor", 0.3), Grid.sunlight(sim, state, pos))
			bits.append("%s +%.1f" % [pair[1], x])
	if not bits.is_empty():
		info["lines"].append("하루에 " + ", ".join(bits) + (" (볕 %d%%)" % int(Grid.sunlight(sim, state, pos) * 100.0) if d.get("sun", false) else ""))
	if float(d.get("upkeep", 0.0)) > 0.0:
		info["lines"].append("유지비 하루 ₩%.1f" % (float(d["upkeep"]) * sim.mod(state, "upkeep")))


func fast_forward(state: CityState, _hours: float, before: Dictionary, lines: Array) -> void:
	var bought := float(state.stats.get("food_bought", 0.0)) - float(before.get("stat.food_bought", 0.0))
	if float(state.flags.get("food_short", 0.0)) > 0.05:
		lines.append("먹을 게 떨어졌다. 사람들이 굶고 있다.")
	elif bought >= 1.0:
		lines.append("식량이 모자라 ₩%d어치를 사들였다." % int(bought))
