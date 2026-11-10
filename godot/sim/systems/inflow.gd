extends SimSystem
## 유입 — 누가 오고, 누가 대문 앞에 서고, 누가 떠나는가.
##  · 구직·생활 유입: 가구 유형별 pull(households.json) = 허가·열린 일자리·위신/악명·자재/경관 정책의 가중합. 가구가 많을수록 소문이 난다.
##  · 갈 곳 없는 사람들: 도시 크기에 비례(nowhere_*). 그중 dependent_ratio(약 20%)는 지금 일을 못 하고, 일부는 안에 사는 가족(kin)이 있다.
##  · 입주 정책(policies.json intake): 누구나 / 여력만큼(빈 방이 있을 때만) / 일꾼 우선(일 못 하는 사람은 돌려보냄).
##  · 집이 없으면 대문 앞에서 기다린다(home = null). 빈 방이 나면 든다. gate_patience_days를 넘기면 떠난다.
##  · 떠남(하루 끝, 접속 중에만): 굶주림·낮은 민심·오랜 실업. 대표인물(named.json)은 조건이 맞으면 찾아오고 제 발로는 안 떠난다.
## 수치: data/economy.json "inflow". 미접속 중에는 줄만 길어지고(상한까지) 아무도 떠나지 않는다.


func on_new_game(state: CityState) -> void:
	state.flags["inflow_acc"] = {}
	state.flags["named_seen"] = {}
	for t: String in sim.tune("inflow.start_households", []):
		Ops.add_household(sim, state, t)
	_named(state)


func on_hour(state: CityState, hour: int) -> void:
	for r: Dictionary in Ops.take_queue(state, "arrival_requests"):
		Ops.add_household(sim, state, str(r.get("type", "laborer")))
	for r: Dictionary in Ops.take_queue(state, "leave_requests"):
		_force_leave(state, str(r.get("type", "any")), int(r.get("count", 1)), str(r.get("reason", "card")))
	_named(state)
	if hour >= int(sim.num("inflow.arrive_from", 6)) and hour < int(sim.num("inflow.arrive_to", 22)):
		_arrivals(state)
	for h: Dictionary in state.households.values():
		if h.get("home") == null and not h.has("wait_since"):
			h["wait_since"] = state.day
	if not sim.offline:
		_move_in(state)


func _named(state: CityState) -> void:
	var seen: Dictionary = state.flags.get("named_seen", {})
	var defs := sim.items("named")
	for id: String in defs:
		if seen.has(id) or not sim.test(state, defs[id].get("cond")):
			continue
		seen[id] = state.day
		Ops.add_household(sim, state, str(defs[id].get("household", "laborer")),
			{"named": id, "size": int(defs[id].get("size", 1))})
		sim.say(state, str(defs[id].get("arrive", "%s이(가) 찾아왔다." % defs[id].get("name", id))), "named")
		sim.touch()
	state.flags["named_seen"] = seen


func _arrivals(state: CityState) -> void:
	var m := sim.metrics(state)
	var acc: Dictionary = state.flags.get("inflow_acc", {})
	var hours: float = maxf(1.0, sim.num("inflow.arrive_to", 22) - sim.num("inflow.arrive_from", 6))
	var k := sim.pace("inflow_mult") * sim.mod(state, "inflow.all")
	k *= maxf(0.2, 1.0 + (state.morale - sim.num("inflow.morale_ref", 50.0)) * sim.num("inflow.morale_k", 0.01))
	if float(m.get("crowd_over", 0.0)) > 0.0:
		k *= sim.num("inflow.water_full_factor", 0.2)
	var intake: Dictionary = sim.option("intake", str(state.policies.get("intake", ""))).get("intake", {})
	var hh := float(m.get("households", 0.0))
	var scale := minf(1.0 + hh * sim.num("inflow.seeker_per_household", 0.03), sim.num("inflow.seeker_scale_max", 8.0))
	var gate := {"waiting": int(m.get("waiting", 0)), "free": int(m.get("vacancies", 0)),
		"max": int(sim.num("inflow.gate_base", 6.0) + hh * sim.num("inflow.gate_per_household", 0.06)),
		"capacity_only": bool(intake.get("capacity_only", false))}
	var defs := sim.items("households")
	for type: String in defs:
		var pull: Dictionary = defs[type].get("pull", {})
		if pull.is_empty():
			continue
		var rate := maxf(0.0, Expr.linear(pull.get("terms", []), m, float(pull.get("base", 0.0))))
		acc[type] = float(acc.get(type, 0.0)) + rate * scale * float(intake.get("seekers", 1.0)) * sim.mod(state, "inflow." + type) * k / hours
		while float(acc[type]) >= 1.0:
			acc[type] = float(acc[type]) - 1.0
			_admit(state, type, gate)
	var nowhere := minf(sim.num("inflow.nowhere_base", 0.8) + hh * sim.num("inflow.nowhere_per_household", 0.03), sim.num("inflow.nowhere_max", 14.0))
	acc["_nowhere"] = float(acc.get("_nowhere", 0.0)) + nowhere * k / hours
	var types: Dictionary = sim.tune("inflow.nowhere_types", {"laborer": 1})
	while float(acc["_nowhere"]) >= 1.0:
		acc["_nowhere"] = float(acc["_nowhere"]) - 1.0
		if sim.randf(state) < sim.num("inflow.dependent_ratio", 0.2):
			if intake.get("dependents", true):
				_admit(state, "dependent", gate)
			else:
				state.stats["turned_dependents"] = int(state.stats.get("turned_dependents", 0)) + 1
		else:
			_admit(state, str(types.keys()[sim.pick(state, types.values())]), gate)
	state.flags["inflow_acc"] = acc


func _admit(state: CityState, type: String, gate: Dictionary) -> void:
	if gate["waiting"] >= gate["max"] or (gate["capacity_only"] and gate["waiting"] >= gate["free"] + int(sim.num("inflow.capacity_slack", 1))):
		state.stats["turned_away"] = int(state.stats.get("turned_away", 0)) + 1
		return
	var extra := {}
	if type == "dependent" and sim.randf(state) < sim.num("inflow.kin_chance", 0.6):
		extra["kin"] = _pick_kin(state)
	Ops.add_household(sim, state, type, extra)
	state.stats["arrived_total"] = int(state.stats.get("arrived_total", 0)) + 1
	gate["waiting"] += 1


## 딸린 식구를 받아 줄 만한 가구(가족 단위일수록 잘 뽑힌다).
func _pick_kin(state: CityState) -> int:
	var ids: Array = state.households.keys()
	ids.sort()
	var w: Array = []
	for id: int in ids:
		var d := sim.item("households", str(state.households[id]["type"]))
		w.append(float(d.get("family", 0.0)) if d.get("works", true) else 0.0)
	var i := sim.pick(state, w)
	return int(ids[i]) if i >= 0 else 0


## 빈 방에 든다: 제 손으로 지은(예약된) 칸이 먼저, 그다음 아무 빈자리.
func _move_in(state: CityState) -> void:
	var waiting: Array = []
	for id: int in state.households:
		if state.households[id].get("home") == null:
			waiting.append(id)
	if waiting.is_empty():
		return
	waiting.sort()
	var open: Array = []
	var reserved := {}
	for pos: Vector3i in state.cells:
		var c: Dictionary = state.cells[pos]
		if c.get("kind", "") != "housing" or Ops.free_slots(sim, c) <= 0:
			continue
		var owner := int(c.get("owner", 0))
		if (c.get("residents", []) as Array).is_empty() and owner != 0 and state.households.has(owner) and state.households[owner].get("home") == null:
			reserved[owner] = pos
		else:
			open.append(pos)
	var moved := false
	for id: int in waiting:
		if reserved.has(id):
			Ops.move_in(state, id, reserved[id])
			moved = true
		elif not open.is_empty():
			var pos: Vector3i = open[0]
			Ops.move_in(state, id, pos)
			moved = true
			if Ops.free_slots(sim, state.cells[pos]) <= 0:
				open.pop_front()
	if moved:
		sim.touch()


func _force_leave(state: CityState, type: String, count: int, reason: String) -> void:
	var ids: Array = []
	for id: int in state.households:
		var h: Dictionary = state.households[id]
		if str(h.get("named", "")) == "" and (type == "any" or str(h["type"]) == type):
			ids.append(id)
	ids.sort()
	for i: int in mini(count, ids.size()):
		var id: int = ids[sim.randi_range(state, 0, ids.size() - 1)]
		ids.erase(id)
		Ops.remove_household(state, id, reason)


func on_day_end(state: CityState) -> void:
	if sim.offline:
		return
	var ids: Array = state.households.keys()
	ids.sort()
	var limit: int = maxi(1, int(float(ids.size()) * sim.num("inflow.max_leave_share", 0.12)))
	var short := float(state.flags.get("food_short", 0.0))
	var low := maxf(0.0, sim.num("inflow.leave_below", 30.0) - state.morale) * sim.num("inflow.morale_leave_k", 0.004)
	var gone := {"gate": 0, "hunger": 0, "morale": 0, "jobless": 0}
	var total := 0
	for id: int in ids:
		var h: Dictionary = state.households[id]
		if str(h.get("named", "")) != "":
			continue
		if h.get("home") == null:
			if state.day - int(h.get("wait_since", state.day)) >= int(sim.num("inflow.gate_patience_days", 3)):
				Ops.remove_household(state, id, "gate")
				gone["gate"] += 1
			continue
		var idle := 0
		if sim.item("households", str(h["type"])).get("works", true) and int(h.get("job", 0)) == 0:
			idle = int(h.get("idle", 0)) + 1
		h["idle"] = idle
		var p_job := sim.num("inflow.jobless_leave", 0.3) if idle >= int(sim.num("inflow.jobless_days", 4)) else 0.0
		var p_hunger := short * sim.num("inflow.hunger_leave", 0.25)
		var p := p_job + p_hunger + low
		if total < limit and p > 0.0 and sim.randf(state) < p:
			var why := "hunger" if (p_hunger >= p_job and p_hunger >= low) else ("jobless" if p_job >= low else "morale")
			Ops.remove_household(state, id, why)
			gone[why] += 1
			total += 1
	var bits: Array = []
	for pair: Array in [["hunger", "굶주려서"], ["jobless", "일이 없어서"], ["morale", "못 살겠다며"], ["gate", "대문 앞에서 기다리다"]]:
		if gone[pair[0]] > 0:
			bits.append("%s %d가구" % [pair[1], gone[pair[0]]])
	if not bits.is_empty():
		sim.say(state, "떠난 사람들: %s." % ", ".join(bits), "bad")


func fast_forward(state: CityState, _hours: float, before: Dictionary, lines: Array) -> void:
	var m := sim.metrics(state)
	var came := int(m.get("households", 0)) - int(before.get("households", 0))
	if int(m.get("waiting", 0)) > 0:
		lines.append("대문 앞에 %d가구가 기다린다%s." % [int(m["waiting"]), (" (그사이 %d가구가 새로 왔다)" % came) if came > 0 else ""])
	var turned := int(state.stats.get("turned_away", 0)) - int(before.get("stat.turned_away", 0))
	if turned > 0:
		lines.append("자리가 없어 %d가구가 발길을 돌렸다." % turned)


## "김씨네(일꾼 2명)" — 화면에 보일 가구 이름.
func _label(state: CityState, id: int) -> String:
	var h: Dictionary = state.households.get(id, {})
	if h.is_empty():
		return "?"
	var d := sim.item("households", str(h["type"]))
	var names: Array = sim.db.get("named", {}).get("surnames", ["김"])
	var who := str(sim.item("named", str(h.get("named", ""))).get("name", "%s씨네" % names[id % names.size()]))
	var job := int(h.get("job", 0))
	var work := ""
	if state.businesses.has(job):
		var b: Dictionary = state.businesses[job]
		work = ", " + str(sim.item("facilities" if b.get("facility", false) else "businesses", str(b["type"])).get("name", "일터"))
	return "%s(%s %d명%s)" % [who, d.get("name", h["type"]), int(h["size"]), work]


func describe(state: CityState, _pos: Vector3i, cell: Dictionary, info: Dictionary) -> void:
	if cell.get("kind", "") != "housing":
		return
	var res: Array = cell.get("residents", [])
	if res.is_empty():
		info["lines"].append("빈 방. 다음에 오는 사람이 든다.")
		return
	var names: Array = []
	for id: int in res.slice(0, 4):
		names.append(_label(state, id))
	info["lines"].append("사는 사람: " + ", ".join(names) + ((" 외 %d가구" % (res.size() - 4)) if res.size() > 4 else ""))
