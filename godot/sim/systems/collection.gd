extends SimSystem
## 수금 — 세금이 공간이 된다(D4), 안 거두면 부패한다(D3).
##  · 심은 앵커마다 수금함(collect point) 하나. 앵커의 catchment(칸) 안에 있는 기둥의 집·가게가 가장 가까운 수금함에 돈을 낸다.
##    어느 수금 구역에도 안 드는 칸은 한 푼도 안 낸다(비공식 구역).
##  · 내는 돈: 일하는 가구 dues × 주거 배율, 가게 dues × 일손 비율. 세금 정책(dues 배율), 장려 감면(dues.<업종>),
##    위신(prestige_k), 악명(notoriety_k: 오락·음성 수입이 는다)이 곱해진다.
##  · 수금함은 cap까지 찬다(cap = 하루 수입 × cap_days, 최소 base_cap). ready_ratio를 넘기면 `collect_ready`.
##    skim_threshold를 넘긴 채 skim_grace_hours가 지나면 수금원이 시간당 skim_rate씩 떼어 뒷골목 금고(alley_fund)로 옮긴다.
##    떼인 만큼 악명이 오른다(skim_notoriety). 자경단 초소가 있으면 덜 떼인다(skim_guard).
##  · collect {point}: 쌓인 돈을 금고로. 상납(flags.tribute)이 있으면 그만큼 윗선 몫. 찬 만큼 확률이 오르는 덤(data/loot.json) 굴림(하루 loot_per_day번까지).
## 수치: data/economy.json "collection".


func on_new_game(state: CityState) -> void:
	_sync(state)


func on_command(state: CityState, name: String, _args: Dictionary, _result: Dictionary) -> void:
	if name == "plant" or name == "demolish":
		_sync(state)


## 앵커 셀 ↔ 수금함을 맞춘다(상태만 보고).
func _sync(state: CityState) -> void:
	var at := {}
	for id: int in state.collect_points.keys():
		var p: Dictionary = state.collect_points[id]
		if state.cells.get(p["pos"], {}).get("kind", "") != "facility":
			state.collect_points.erase(id)
		else:
			at[p["pos"]] = id
	for pos: Vector3i in state.cells:
		if state.cells[pos].get("kind", "") == "facility" and not at.has(pos):
			var id := state.new_id()
			state.collect_points[id] = {"id": id, "pos": pos, "amount": 0.0, "cap": sim.num("collection.base_cap", 30.0),
				"skimmed": 0.0, "over_hours": 0.0, "ready": false, "rate": 0.0, "type": str(state.cells[pos]["type"])}


## 기둥 → 그 기둥이 돈을 내는 수금함 id(없으면 0).
func _cover(state: CityState) -> Dictionary:
	var ids: Array = state.collect_points.keys()
	ids.sort()
	var cover := {}
	for x: int in sim.W:
		for y: int in sim.H:
			var best := 0
			var best_d := 1.0e9
			for id: int in ids:
				var p: Vector3i = state.collect_points[id]["pos"]
				var r := float(sim.item("facilities", str(state.collect_points[id]["type"])).get("catchment", 3.0))
				var d2 := float((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y))
				if d2 <= r * r and d2 < best_d:
					best_d = d2
					best = id
			cover[Vector2i(x, y)] = best
	return cover


## 이 칸이 하루에 내는 돈.
func _dues(state: CityState, cell: Dictionary) -> float:
	var kind := str(cell.get("kind", ""))
	var k := sim.mod(state, "dues") * (1.0 + state.prestige * sim.num("collection.prestige_k", 0.003)) * sim.pace("economy_mult")
	if kind == "housing":
		var mult := float(sim.item("housing", str(cell["type"])).get("dues", 1.0))
		var sum := 0.0
		for id: int in cell.get("residents", []):
			var h: Dictionary = state.households.get(id, {})
			if int(h.get("job", 0)) != 0:
				sum += float(sim.item("households", str(h["type"])).get("dues", 0.0))
		return sum * mult * k
	if kind == "business":
		var d := sim.def_of(cell)
		var b: Dictionary = state.businesses.get(int(cell.get("owner", 0)), {})
		var jobs := int(b.get("jobs", 0))
		var staff := 1.0 if jobs <= 0 else float((b.get("workers", []) as Array).size()) / float(jobs)
		var grp := str(d.get("group", ""))
		return float(d.get("dues", 0.0)) * staff * k * sim.mod(state, "dues." + grp) \
			* (1.0 + state.notoriety * float(sim.tune("collection.notoriety_k", {}).get(grp, 0.0)))
	return 0.0


func on_hour(state: CityState, _hour: int) -> void:
	_sync(state)
	var cover := _cover(state)
	var income := {}
	var informal := 0.0
	var informal_cells := 0
	for pos: Vector3i in state.cells:
		var x := _dues(state, state.cells[pos])
		var kind := str(state.cells[pos].get("kind", ""))
		var pt := int(cover.get(Vector2i(pos.x, pos.y), 0))
		if pt == 0:
			informal += x
			if kind == "housing" or kind == "business":
				informal_cells += 1
		elif x > 0.0:
			income[pt] = float(income.get(pt, 0.0)) + x
	state.stats["informal_rate"] = informal
	state.stats["informal_cells"] = informal_cells
	var guard := minf(0.9, float(sim.metrics(state).get("count.watch_post", 0.0)) * float(sim.item("facilities", "watch_post").get("skim_guard", 0.0)))
	var ids: Array = state.collect_points.keys()
	ids.sort()
	var total_rate := 0.0
	for id: int in ids:
		var p: Dictionary = state.collect_points[id]
		var rate := float(income.get(id, 0.0))
		total_rate += rate
		p["rate"] = rate
		p["cap"] = maxf(sim.num("collection.base_cap", 30.0), rate * sim.num("collection.cap_days", 1.2))
		var amount := float(p["amount"]) + rate / 24.0
		var cap := float(p["cap"])
		var skim := maxf(0.0, amount - cap)
		amount -= skim
		if amount >= cap * sim.num("collection.skim_threshold", 0.8):
			p["over_hours"] = float(p["over_hours"]) + 1.0
			if float(p["over_hours"]) > sim.num("collection.skim_grace_hours", 6.0):
				var take := amount * sim.num("collection.skim_rate", 0.04) * (1.0 - guard)
				amount -= take
				skim += take
		else:
			p["over_hours"] = 0.0
		if skim > 0.0:
			p["skimmed"] = float(p["skimmed"]) + skim
			state.alley_fund += skim
			state.notoriety = clampf(state.notoriety + skim * sim.num("collection.skim_notoriety", 0.02), 0.0, 100.0)
			state.stats["skim_total"] = float(state.stats.get("skim_total", 0.0)) + skim
		p["amount"] = amount
		var ready: bool = amount >= cap * sim.num("collection.ready_ratio", 0.5)
		if ready and not p.get("ready", false):
			state.emit("collect_ready", {"point": id})
		p["ready"] = ready
	state.stats["dues_rate"] = total_rate


func can(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "collect":
		return null
	var total := 0.0
	for id: int in _targets(state, args):
		total += float(state.collect_points[id]["amount"])
	if args.has("point") and not state.collect_points.has(int(args["point"])):
		return {"ok": false, "reason": "그런 수금함은 없다."}
	return {"ok": total >= 1.0, "reason": "" if total >= 1.0 else "아직 거둘 게 없다."}


func _targets(state: CityState, args: Dictionary) -> Array:
	if args.has("point"):
		return [int(args["point"])] if state.collect_points.has(int(args["point"])) else []
	var ids: Array = state.collect_points.keys()
	ids.sort()
	return ids


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "collect":
		return null
	var got := 0.0
	var skimmed := 0.0
	var loot: Array = []
	var tribute := clampf(float(state.flags.get("tribute", 0.0)), 0.0, 0.9)
	for id: int in _targets(state, args):
		var p: Dictionary = state.collect_points[id]
		var amount := float(p["amount"])
		if amount < 0.01:
			continue
		var ratio := amount / maxf(float(p["cap"]), 1.0)
		state.money += amount * (1.0 - tribute)
		state.stats["tribute_total"] = float(state.stats.get("tribute_total", 0.0)) + amount * tribute
		state.stats["collected_total"] = float(state.stats.get("collected_total", 0.0)) + amount
		state.stats["collects"] = int(state.stats.get("collects", 0)) + 1
		state.emit("collected", {"point": id, "amount": amount, "skimmed": float(p["skimmed"])})
		if float(p["skimmed"]) > 0.5:
			sim.say(state, "%s 수금함: ₩%d. 수금원이 그사이 ₩%d을(를) 챙겼다." % [sim.item("facilities", str(p["type"])).get("name", ""), int(amount), int(float(p["skimmed"]))], "bad")
		else:
			state.notoriety = clampf(state.notoriety - sim.num("collection.clean_notoriety", 0.05), 0.0, 100.0)
		got += amount
		skimmed += float(p["skimmed"])
		p["amount"] = 0.0
		p["skimmed"] = 0.0
		p["over_hours"] = 0.0
		p["ready"] = false
		var today: Dictionary = state.flags.get("loot_day", {"day": 0, "count": 0})
		if int(today["day"]) != state.day:
			today = {"day": state.day, "count": 0}
		if int(today["count"]) < int(sim.num("collection.loot_per_day", 3)) and sim.roll(state) < sim.num("collection.loot_chance", 0.3) * minf(ratio, 1.0):
			today["count"] = int(today["count"]) + 1
			state.flags["loot_day"] = today
			var item := _roll_loot(state)
			if not item.is_empty():
				loot.append(item)
	if tribute > 0.0 and got > 0.0:
		sim.say(state, "거둔 돈 ₩%d 중 ₩%d은(는) 윗선 몫으로 빠졌다." % [int(got), int(got * tribute)], "bad")
	return {"ok": true, "reason": "", "amount": got * (1.0 - tribute), "skimmed": skimmed, "loot": loot}


func _roll_loot(state: CityState) -> Dictionary:
	var defs := sim.items("loot")
	var ids: Array = []
	var w: Array = []
	for id: String in defs:
		if sim.test(state, defs[id].get("cond")):
			ids.append(id)
			w.append(float(defs[id].get("weight", 1.0)))
	var i := sim.pick(state, w)
	if i < 0:
		return {}
	var d: Dictionary = defs[ids[i]]
	sim.say(state, "덤: " + str(d.get("text", "")), "loot")
	sim.run(state, d.get("effects", []))
	state.stats["loot_found"] = int(state.stats.get("loot_found", 0)) + 1
	return {"id": ids[i], "text": sim.fmt(state, str(d.get("text", "")))}


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "collect_points":
		return null
	var out: Array = []
	for id: int in _targets(state, {}):
		var p: Dictionary = state.collect_points[id]
		out.append({"id": id, "pos": p["pos"], "amount": float(p["amount"]), "cap": float(p["cap"]),
			"ratio": float(p["amount"]) / maxf(float(p["cap"]), 1.0), "skimmed": float(p["skimmed"]),
			"ready": p.get("ready", false), "rate": float(p.get("rate", 0.0)), "type": p.get("type", "")})
	return out


func metrics(state: CityState, m: Dictionary) -> void:
	var full := 0.0
	var held := 0.0
	for p: Dictionary in state.collect_points.values():
		held += float(p["amount"])
		if float(p["amount"]) >= float(p["cap"]) * sim.num("collection.skim_threshold", 0.8):
			full += 1.0
	m["collect_full"] = full
	m["collect_held"] = held
	m["dues_rate"] = float(state.stats.get("dues_rate", 0.0))
	m["informal_rate"] = float(state.stats.get("informal_rate", 0.0))
	m["informal_cells"] = float(state.stats.get("informal_cells", 0))


func describe(state: CityState, pos: Vector3i, cell: Dictionary, info: Dictionary) -> void:
	var pt := int(_cover(state).get(Vector2i(pos.x, pos.y), 0))
	var kind := str(cell.get("kind", ""))
	if kind == "facility":
		for id: int in state.collect_points:
			var p: Dictionary = state.collect_points[id]
			if p["pos"] == pos:
				info["lines"].append("수금함: ₩%d / %d (하루 ₩%d이 모인다)" % [int(float(p["amount"])), int(float(p["cap"])), int(float(p.get("rate", 0.0)))])
				if float(p["skimmed"]) > 0.5:
					info["lines"].append("수금원이 ₩%d을 챙겼다. 오래 두면 더 챙긴다." % int(float(p["skimmed"])))
				var c: Dictionary = can(state, "collect", {"point": id})
				info["actions"].append({"id": "collect", "label": "거두기", "cmd": "collect", "args": {"point": id}, "ok": c["ok"], "reason": c["reason"]})
		return
	if pt == 0:
		info["lines"].append("수금 구역 밖 — 아무도 걷으러 오지 않는다(비공식 구역). 앵커를 가까이 심으면 구역에 든다.")
	elif kind == "housing" or kind == "business":
		var name := str(sim.item("facilities", str(state.collect_points[pt]["type"])).get("name", "앵커"))
		info["lines"].append("%s 수금함으로 하루 ₩%.1f을 낸다." % [name, _dues(state, cell)])
	elif kind == "":
		info["lines"].append("%s의 수금 구역." % sim.item("facilities", str(state.collect_points[pt]["type"])).get("name", "앵커"))


func fast_forward(state: CityState, _hours: float, before: Dictionary, lines: Array) -> void:
	var skim := float(state.stats.get("skim_total", 0.0)) - float(before.get("stat.skim_total", 0.0))
	var m := sim.metrics(state)
	if skim >= 1.0:
		lines.append("수금함 %d곳이 넘쳐 수금원이 ₩%d을 챙겼다." % [maxi(1, int(m.get("collect_full", 0))), int(skim)])
	if float(m.get("collect_held", 0.0)) >= 1.0:
		lines.append("수금함에 ₩%d이 쌓여 있다." % int(float(m["collect_held"])))
