extends SimSystem
## 돌봄 — 일을 못 하는 가구(dependent)를 어떻게 대하는가. 정책 축 care(policies.json의 care 블록).
##  · 각자도생(none): 비용 0. 아무 일도 없다(차가운 골목은 meters.json의 항으로).
##  · 공동부조(mutual): 하루에 가구당 cost만큼 돈이 든다. 대신 가구당 food_gift만큼 반찬이 돌고(할매 반찬),
##    야매 의원이 있으면 날마다 recover 확률로 병자가 일꾼으로 돌아온다.
##  · 추방(expel): 하루 expel_per_day 가구를 내보낸다. 안에 가족(kin)이 있으면 그 가구가 households.json kin_leave 확률로 같이 떠난다.
##    위신·민심 타격은 "가족 단위 가구의 비중(family_share)"에 비례 — 농사꾼 마을에서는 크게, 건달·단신 일꾼 성채에서는 거의 조용히 지나간다.
## 수치: data/economy.json "care" (expel_prestige, expel_morale, expel_notoriety) · 정책별 수치는 policies.json.


func _conf(state: CityState) -> Dictionary:
	return sim.option("care", str(state.policies.get("care", ""))).get("care", {})


func on_day_end(state: CityState) -> void:
	var conf := _conf(state)
	var deps: Array = []
	for id: int in state.households:
		var h: Dictionary = state.households[id]
		if not sim.item("households", str(h["type"])).get("works", true) and h.get("home") != null:
			deps.append(id)
	deps.sort()
	var cost := float(conf.get("cost", 0.0)) * float(deps.size()) * sim.pace("economy_mult")
	if cost > 0.0:
		state.money -= cost
		state.stats["care_spent"] = float(state.stats.get("care_spent", 0.0)) + cost
		state.food += float(conf.get("food_gift", 0.0)) * float(deps.size())
	if sim.offline:
		return
	var recover := float(conf.get("recover", 0.0))
	if recover > 0.0 and float(sim.metrics(state).get("count.clinic", 0.0)) > 0.0:
		for id: int in deps:
			var h: Dictionary = state.households[id]
			if str(h.get("named", "")) == "" and sim.randf(state) < recover:
				h["type"] = str(sim.tune("care.recover_as", "laborer"))
				state.stats["recovered"] = int(state.stats.get("recovered", 0)) + 1
				sim.say(state, "의원 신세를 지던 사람이 다시 일을 나간다.", "good")
	_expel(state, int(conf.get("expel_per_day", 0)))


func _expel(state: CityState, quota: int) -> void:
	if quota <= 0:
		return
	var targets: Array = []
	for id: int in state.households:
		if not sim.item("households", str(state.households[id]["type"])).get("works", true):
			targets.append(id)
	targets.sort()
	# 이름 없는 사람부터. 대표인물은 맨 마지막에.
	targets.sort_custom(func(a: int, b: int) -> bool:
		var na := str(state.households[a].get("named", "")) != ""
		var nb := str(state.households[b].get("named", "")) != ""
		return a < b if na == nb else nb)
	var family := float(sim.metrics(state).get("family_share", 0.0))
	var out := 0
	var followed := 0
	for id: int in targets.slice(0, quota):
		var h: Dictionary = state.households[id]
		var kin := int(h.get("kin", 0))
		var who := str(sim.item("named", str(h.get("named", ""))).get("name", ""))
		Ops.remove_household(state, id, "expelled")
		out += 1
		if who != "":
			sim.say(state, "%s을(를) 내보냈다. 골목이 한동안 조용했다." % who, "bad")
		if state.households.has(kin):
			var kd := sim.item("households", str(state.households[kin]["type"]))
			if str(state.households[kin].get("named", "")) == "" and sim.randf(state) < float(kd.get("kin_leave", 0.0)):
				Ops.remove_household(state, kin, "followed_kin")
				followed += 1
				sim.say(state, "내보낸 노인의 식구인 %s 가구가 짐을 쌌다." % kd.get("name", "어느"), "bad")
	if out == 0:
		return
	state.stats["expelled"] = int(state.stats.get("expelled", 0)) + out
	state.prestige = clampf(state.prestige - sim.num("care.expel_prestige", 2.0) * family * float(out), 0.0, 100.0)
	state.morale = clampf(state.morale - sim.num("care.expel_morale", 3.0) * family * float(out + followed), 0.0, 100.0)
	state.notoriety = clampf(state.notoriety + sim.num("care.expel_notoriety", 0.4) * float(out), 0.0, 100.0)
	if family < 0.3:
		sim.say(state, "일 못 하는 %d가구를 내보냈다. 아무도 묻지 않았다." % out, "")
	else:
		sim.say(state, "일 못 하는 %d가구를 내보냈다. 대문 앞에서 한참 우는 소리가 났다." % out, "bad")
	sim.touch()


func metrics(state: CityState, m: Dictionary) -> void:
	var mutual := str(state.policies.get("care", "")) == "mutual"
	# 돌봄을 택했을 때만 돌아오는 좋은 영향(할매가 애를 봐 준다).
	m["care_helpers"] = float(m.get("dependents", 0.0)) if mutual else 0.0
	m["care_cost"] = float(_conf(state).get("cost", 0.0)) * float(m.get("dependents", 0.0))


func describe(state: CityState, _pos: Vector3i, cell: Dictionary, info: Dictionary) -> void:
	for id: int in cell.get("residents", []):
		var h: Dictionary = state.households.get(id, {})
		if not h.is_empty() and not sim.item("households", str(h["type"])).get("works", true):
			var kin := int(h.get("kin", 0))
			var tail := " 이 성채 안에 식구가 산다." if state.households.has(kin) else ""
			info["lines"].append("지금은 일을 못 하는 사람이 산다.%s" % tail)
			return
