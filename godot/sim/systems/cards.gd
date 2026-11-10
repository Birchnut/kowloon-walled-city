extends SimSystem
## 결재 — 하루 끝에 제안 카드가 올라온다(data/cards.json).
##  · 하루 per_day장까지. 먼저 다른 일이 예약한 카드(flags.card_queue: 덤·정책·카드의 후속), 그다음 조건(cond)이 맞는 카드 중
##    weight로 뽑는다. 같은 카드는 cooldown일 동안 다시 안 나오고, once면 평생 한 번.
##  · 쌓이는 상한 max_pending. 미접속 중에도 쌓인다(상한까지). 접속 중 expire_days를 넘긴 카드는 흐지부지 사라진다.
##  · card {uid, choice}: 고른 선택지의 effects(Expr)가 실행된다. 선택지에 needs가 있으면 그 조건이 맞아야 고를 수 있다.
##  · 부탁(mission): 선택지 효과 ["mission", id] → cards.json "missions"의 goal을 days일 안에 채우면 reward, 못 채우면 fail.
## 수치: data/economy.json "cards".


func _c(state: CityState) -> Dictionary:
	if not state.flags.has("cards"):
		state.flags["cards"] = {"next_uid": 1, "cool": {}, "used": {}}
	return state.flags["cards"]


func _missions() -> Dictionary:
	return sim.db.get("cards", {}).get("missions", {})


func on_hour(state: CityState, _hour: int) -> void:
	var active: Dictionary = state.flags.get("missions", {})
	for r: Dictionary in Ops.take_queue(state, "mission_requests"):
		var id := str(r.get("mission", ""))
		if _missions().has(id) and not active.has(id):
			active[id] = {"until": state.day + int(_missions()[id].get("days", 5))}
			sim.say(state, "약속: %s (%d일 안에)" % [_missions()[id].get("name", id), int(_missions()[id].get("days", 5))], "mission")
	for id: String in active.keys():
		var d: Dictionary = _missions().get(id, {})
		if sim.test(state, d.get("goal")):
			active.erase(id)
			state.stats["missions_done"] = int(state.stats.get("missions_done", 0)) + 1
			sim.say(state, str(d.get("done", "약속을 지켰다: %s." % d.get("name", id))), "good")
			sim.run(state, d.get("reward", []))
		elif state.day > int(active[id]["until"]) and not sim.offline:
			active.erase(id)
			state.stats["missions_failed"] = int(state.stats.get("missions_failed", 0)) + 1
			sim.say(state, str(d.get("failed", "약속을 못 지켰다: %s." % d.get("name", id))), "bad")
			sim.run(state, d.get("fail", []))
	state.flags["missions"] = active


func on_day_end(state: CityState) -> void:
	var c := _c(state)
	var defs := sim.items("cards")
	if not sim.offline:
		var keep_days := int(sim.num("cards.expire_days", 4))
		for p: Dictionary in state.pending_cards.duplicate():
			if state.day - int(p.get("day", state.day)) >= keep_days:
				state.pending_cards.erase(p)
				sim.say(state, "결재를 미룬 사이 '%s' 건은 흐지부지됐다." % p.get("title", ""), "")
				sim.run(state, defs.get(p.get("card", ""), {}).get("expire", []))
	var slots: int = mini(int(sim.num("cards.per_day", 3)), int(sim.num("cards.max_pending", 9)) - state.pending_cards.size())
	var added := 0
	var pending := {}
	for p: Dictionary in state.pending_cards:
		pending[p.get("card", "")] = true
	var later: Array = []
	for q: Dictionary in Ops.take_queue(state, "card_queue"):
		var id := str(q.get("card", ""))
		if added < slots and int(q.get("day", 0)) <= state.day and defs.has(id) and not pending.has(id):
			_push(state, id)
			pending[id] = true
			added += 1
		elif defs.has(id) and not pending.has(id):
			later.append(q)
	state.flags["card_queue"] = later
	while added < slots:
		var ids: Array = []
		var w: Array = []
		for id: String in defs:
			var d: Dictionary = defs[id]
			if pending.has(id) or float(d.get("weight", 1.0)) <= 0.0 or c["used"].has(id) or state.day < int(c["cool"].get(id, 0)):
				continue
			if sim.test(state, d.get("cond")):
				ids.append(id)
				w.append(float(d["weight"]) if d.has("weight") else 1.0)
		var i := sim.pick(state, w)
		if i < 0:
			break
		_push(state, str(ids[i]))
		pending[ids[i]] = true
		added += 1
	if added > 0:
		state.emit("cards_ready", {"count": state.pending_cards.size()})


func _push(state: CityState, id: String) -> void:
	var c := _c(state)
	var d := sim.item("cards", id)
	var choices: Array = []
	for ch: Dictionary in d.get("choices", []):
		choices.append({"label": sim.fmt(state, str(ch.get("label", ""))), "hint": sim.fmt(state, str(ch.get("hint", ""))), "tags": ch.get("tags", [])})
	var uid := int(c["next_uid"])
	c["next_uid"] = uid + 1
	c["cool"][id] = state.day + int(d.get("cooldown", sim.num("cards.default_cooldown", 6)))
	if d.get("once", false):
		c["used"][id] = true
	state.pending_cards.append({"uid": uid, "card": id, "title": sim.fmt(state, str(d.get("title", id))),
		"body": sim.fmt(state, str(d.get("body", ""))), "speaker": sim.fmt(state, str(d.get("speaker", ""))), "choices": choices, "day": state.day})


func _find(state: CityState, uid: int) -> Dictionary:
	for p: Dictionary in state.pending_cards:
		if int(p.get("uid", -1)) == uid:
			return p
	return {}


func can(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "card":
		return null
	var p := _find(state, int(args.get("uid", -1)))
	if p.is_empty():
		return {"ok": false, "reason": "이미 지나간 건이다."}
	var choices: Array = sim.item("cards", str(p["card"])).get("choices", [])
	var i := int(args.get("choice", -1))
	if i < 0 or i >= choices.size():
		return {"ok": false, "reason": "그런 선택지는 없다."}
	if not sim.test(state, choices[i].get("needs")):
		return {"ok": false, "reason": str(choices[i].get("needs_hint", "지금은 고를 수 없다."))}
	return {"ok": true, "reason": ""}


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "card":
		return null
	var p := _find(state, int(args["uid"]))
	var ch: Dictionary = sim.item("cards", str(p["card"])).get("choices", [])[int(args["choice"])]
	state.pending_cards.erase(p)
	state.stats["cards_answered"] = int(state.stats.get("cards_answered", 0)) + 1
	for t: Variant in ch.get("tags", []):
		state.stats["chose_" + str(t)] = int(state.stats.get("chose_" + str(t), 0)) + 1
	sim.say(state, "결재 — %s: %s" % [p.get("title", ""), ch.get("label", "")], "card")
	sim.run(state, ch.get("effects", []))
	return {"ok": true, "reason": "", "card": p["card"], "choice": int(args["choice"])}


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "missions":
		return null
	var out: Array = []
	var active: Dictionary = state.flags.get("missions", {})
	for id: String in active:
		out.append({"id": id, "name": _missions().get(id, {}).get("name", id), "until": int(active[id]["until"])})
	return out


func metrics(state: CityState, m: Dictionary) -> void:
	m["cards_pending"] = float(state.pending_cards.size())
	for id: String in state.flags.get("missions", {}):
		m["mission." + id] = 1.0


func fast_forward(state: CityState, _hours: float, before: Dictionary, lines: Array) -> void:
	var n := state.pending_cards.size()
	if n > int(before.get("cards_pending", 0)):
		lines.append("결재 %d건이 책상에 쌓였다." % n)
