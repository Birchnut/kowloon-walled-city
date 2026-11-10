extends SimSystem
## research — 연구(GDD §10). data/progression/research.json: 세 갈래 × 네 단계.
##  research_start {id}: 공부방(완공)이 있어야, 한 번에 하나, 앞 단계가 끝나야, 돈(cost)을 시작할 때 낸다(장부 'build').
##  진행: 경제 시계로 days. 가동 중인 공부방이 하나도 없으면 멈춘다(미접속 빨리감기 중에도 경제 시계대로).
##  끝나면 state.research.done[id] = true, 효과는 Sim.mod 수정치로(키는 research.json effects), reveals 목적지 공개,
##  이벤트 research_done{id, name}, 기록 한 줄. research_cancel {}: 진행 중인 연구를 그만둔다(돈의 절반을 돌려받음).
##  상태: state.research = {done:{id:true}, active:{id, done_at(예상), left(남은 경제일)}}.
## 끄면: 연구가 없고 수정치에도 들어가지 않는다.


func _active(state: CityState) -> Dictionary:
	var a: Variant = state.research.get("active", {})
	return a if a is Dictionary else {}


func _done(state: CityState) -> Dictionary:
	if not (state.research.get("done") is Dictionary):
		state.research["done"] = {}
	return state.research["done"]


func _study_count(state: CityState, active_only: bool) -> int:
	var n := 0
	for b: Dictionary in sim.cover(state)["facs"]:
		if "study" in sim.bdef(str(b["type"])).get("services", []):
			if not active_only or b.get("active", false):
				n += 1
	return n


func _state_of(state: CityState, id: String) -> String:
	if _done(state).has(id):
		return "done"
	if str(_active(state).get("id", "")) == id:
		return "active"
	var r := sim.item("research", id)
	var req := str(r.get("requires", ""))
	if req != "" and not _done(state).has(req):
		return "locked"
	return "ready"


func can(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"research_start":
			var id := str(args.get("id", ""))
			var r := sim.item("research", id)
			if r.is_empty():
				return {"ok": false, "reason": "모르는 연구다.", "code": "unknown"}
			if _study_count(state, false) == 0:
				return {"ok": false, "reason": "공부방이 있어야 연구할 수 있다.", "code": "study"}
			if _done(state).has(id):
				return {"ok": false, "reason": "이미 끝낸 연구다.", "code": "done"}
			if not _active(state).is_empty():
				return {"ok": false, "reason": "이미 연구 중이다(한 번에 하나).", "code": "busy"}
			var req := str(r.get("requires", ""))
			if req != "" and not _done(state).has(req):
				return {"ok": false, "reason": "먼저 '%s'을(를) 끝내야 한다." % sim.item("research", req).get("name", req), "code": "locked"}
			var cost := float(r.get("cost", 0))
			if state.money + 1e-9 < cost:
				return {"ok": false, "reason": "돈이 모자란다(₩%d 필요)." % int(cost), "code": "money"}
			return {"ok": true, "reason": "", "code": "ok", "cost": {"money": cost, "goods": {}}}
		"research_cancel":
			if _active(state).is_empty():
				return {"ok": false, "reason": "진행 중인 연구가 없다.", "code": "none"}
			return {"ok": true, "reason": "", "code": "ok"}
	return null


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"research_start":
			var id := str(args["id"])
			var r := sim.item("research", id)
			var cost := float(r.get("cost", 0))
			state.money -= cost
			state.book("build", -cost)
			state.stat_add("research_spent", cost)
			var days := float(r.get("days", 1.0))
			state.research["active"] = {"id": id, "left": days, "done_at": state.econ_days + days}
			sim.say(state, "공부방에서 '%s' 연구를 시작했다(₩%d, %.1f일)." % [r.get("name", id), int(cost), days])
			return {"ok": true, "reason": "", "id": id}
		"research_cancel":
			var a := _active(state)
			var r := sim.item("research", str(a.get("id", "")))
			var back := floorf(float(r.get("cost", 0)) * 0.5)
			state.money += back
			state.book("build", back)
			state.research["active"] = {}
			sim.say(state, "'%s' 연구를 그만두었다(₩%d 돌려받음)." % [r.get("name", ""), int(back)])
			return {"ok": true, "reason": "", "refund": back}
	return null


func tick(state: CityState, dt: float) -> void:
	var a := _active(state)
	if a.is_empty():
		return
	if _study_count(state, true) == 0:
		a["done_at"] = state.econ_days + float(a.get("left", 0.0))
		return
	a["left"] = maxf(0.0, float(a.get("left", 0.0)) - dt)
	a["done_at"] = state.econ_days + dt + float(a["left"])
	if float(a["left"]) <= 1e-9:
		_finish(state, str(a["id"]))


func _finish(state: CityState, id: String) -> void:
	var r := sim.item("research", id)
	_done(state)[id] = true
	state.research["active"] = {}
	Sim.mods_changed(state)
	var extra: Array = []
	for d: String in r.get("reveals", []):
		if state.dests.has(d) and not bool(state.dests[d].get("known", false)):
			state.dests[d]["known"] = true
			state.dests[d]["new"] = true
			extra.append(str(sim.item("destinations", d).get("name", d)))
	state.stats["research_%s_day" % id] = state.econ_days
	state.emit("research_done", {"id": id, "name": str(r.get("name", id))})
	sim.say(state, "연구 완료: %s — %s%s" % [r.get("name", id), r.get("desc", ""), (" 새 목적지: " + ", ".join(extra)) if not extra.is_empty() else ""], "good")


func fast_forward(state: CityState, _econ_days: float, before: Dictionary, lines: Array) -> void:
	var bs: Dictionary = before.get("stats", {})
	for id: String in sim.items("research"):
		var k := "research_%s_day" % id
		if state.stats.has(k) and not bs.has(k):
			lines.append("연구가 끝났다: %s." % sim.item("research", id).get("name", id))


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "research":
		return null
	var br: Dictionary = sim.db.get("research", {}).get("branches", {})
	var nodes: Array = []
	var ids: Array = sim.items("research").keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ra := sim.item("research", a)
		var rb := sim.item("research", b)
		var ba := (br.keys() as Array).find(str(ra.get("branch", "")))
		var bb := (br.keys() as Array).find(str(rb.get("branch", "")))
		return ba < bb if ba != bb else int(ra.get("tier", 0)) < int(rb.get("tier", 0)))
	for id: String in ids:
		var r := sim.item("research", id)
		var st := _state_of(state, id)
		var hint := ""
		if st == "locked":
			hint = "먼저: " + str(sim.item("research", str(r.get("requires", ""))).get("name", ""))
		nodes.append({"id": id, "branch": r.get("branch", ""), "branch_name": br.get(r.get("branch", ""), ""), "tier": int(r.get("tier", 0)),
			"name": r.get("name", id), "desc": r.get("desc", ""), "cost": float(r.get("cost", 0)), "days": float(r.get("days", 1.0)),
			"state": st, "lock_hint": hint, "affordable": state.money + 1e-9 >= float(r.get("cost", 0))})
	var a := _active(state)
	var act := {}
	if not a.is_empty():
		act = {"id": a["id"], "name": sim.item("research", str(a["id"])).get("name", ""), "left_days": snappedf(float(a.get("left", 0.0)), 0.01),
			"paused": _study_count(state, true) == 0}
	var studies := _study_count(state, false)
	var hint := ""
	if studies == 0:
		hint = "공부방을 지으면 연구할 수 있다."
	elif not a.is_empty() and _study_count(state, true) == 0:
		hint = "공부방이 멈춰 연구도 멈췄다(토박이 일손 필요)."
	elif a.is_empty():
		hint = "연구를 하나 고르자. 한 번에 하나만 한다."
	return {"can": studies > 0 and a.is_empty(), "hint": hint, "active": act, "nodes": nodes, "done": _done(state).size(), "total": nodes.size()}


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name == "hud":
		var a := _active(state)
		out["research"] = {} if a.is_empty() else {"id": a["id"], "name": sim.item("research", str(a["id"])).get("name", ""), "left_days": snappedf(float(a.get("left", 0.0)), 0.01)}
