extends SimSystem
## goals — 단계 목표(GDD §9, 확정: 단계 목표 + 이후 샌드박스). data/progression/goals.json.
##  목표는 order 순서로 하나씩 hud.next_goal에 보이지만, 먼저 이룬 것도 그때 끝난다(영구). 조건은 Expr + Metrics.
##  끝나면 보상(돈 → 장부 'reward', 상품, 새 목적지)을 주고 goal_done{id, text, rewards} 이벤트와 기록 한 줄.
##  성채 등급·호칭(milestone)은 progression(unlocks.json)이 바꾼다 — 목표의 unlock은 그 단계 이름을 보상 문구에 보탤 뿐.
##  마지막(final) 목표 뒤에는 샌드박스: 목표 없이 계속 돈다(hud.next_goal = "자유롭게 성채를 가꾸자").
##  검사 주기: 경제 4스텝(2경제시간)마다 + 명령 직후. 스텝 번호는 econ_days에서 나오므로 저장·불러오기와 무관하게 같다.
## 끄면: goals 질의는 해금 단계로 만든 기본 모양(Queries)이 된다.


func _ids() -> Array:
	var ids: Array = sim.items("goals").keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(sim.item("goals", a).get("order", 0)) < int(sim.item("goals", b).get("order", 0)))
	return ids


func _done(state: CityState) -> Dictionary:
	if not state.flags.has("goals"):
		state.flags["goals"] = {}
	return state.flags["goals"]


func on_new_game(state: CityState) -> void:
	_done(state)


func tick(state: CityState, dt: float) -> void:
	if sim.every(state, 4, dt):
		_check(state)


## G11: 튜토리얼 진행 저장 — cmd("tutorial", {step:int}) → state.flags.tutorial, hud.tutorial로 읽는다(저장됨).
func can(_state: CityState, name: String, args: Dictionary) -> Variant:
	if name == "tutorial":
		return {"ok": int(args.get("step", -1)) >= 0, "reason": "" if int(args.get("step", -1)) >= 0 else "step이 필요하다."}
	return null


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	if name == "tutorial":
		state.flags["tutorial"] = int(args.get("step", 0))
		return {"ok": true, "reason": "", "step": int(state.flags["tutorial"])}
	return null


func on_command(state: CityState, name: String, _args: Dictionary, _result: Dictionary) -> void:
	if name != "debug" and name != "tutorial":
		_check(state)


func _check(state: CityState) -> void:
	var done := _done(state)
	if done.size() >= sim.items("goals").size():
		return
	var m := Metrics.compute(sim, state)
	for id: String in _ids():
		if done.has(id):
			continue
		var g := sim.item("goals", id)
		if Expr.test(g.get("cond", []), m):
			done[id] = state.econ_days
			var lines := _grant(state, g)
			state.emit("goal_done", {"id": id, "text": str(g.get("text", id)), "rewards": lines})
			sim.say(state, "목표 달성: %s%s" % [g.get("text", id), (" — " + ", ".join(lines)) if not lines.is_empty() else ""], "good")
			state.stats["goal_%s_day" % id] = state.econ_days
			if g.get("final", false):
				sim.say(state, "구룡성채가 섰다. 이제부터는 목표 없이, 마음대로 쌓아 올리자.", "good")


## 보상을 주고 문구를 돌려준다.
func _grant(state: CityState, g: Dictionary) -> Array:
	var rw: Dictionary = g.get("rewards", {})
	var out: Array = []
	var money := float(rw.get("money", 0))
	if money > 0.0:
		state.money += money
		state.book("reward", money)
		out.append(Sim.won(money))
	var st: Dictionary = rw.get("stock", {})
	for gd: String in st:
		state.stock[gd] = float(state.stock.get(gd, 0.0)) + float(st[gd])
		state.stat_add("goal." + gd, float(st[gd]))
		out.append("%s %d" % [sim.gname(gd), int(st[gd])])
	for d: String in rw.get("reveal", []):
		if state.dests.has(d) and not bool(state.dests[d].get("known", false)):
			state.dests[d]["known"] = true
			state.dests[d]["new"] = true
			out.append("새 목적지: %s" % sim.item("destinations", d).get("name", d))
	return out


## 보상 미리보기 문구(질의용): 보상 + 같은 순간 열리는 해금.
func _reward_text(state: CityState, g: Dictionary) -> Array:
	var rw: Dictionary = g.get("rewards", {})
	var out: Array = []
	if float(rw.get("money", 0)) > 0.0:
		out.append(Sim.won(float(rw["money"])))
	for gd: String in rw.get("stock", {}):
		out.append("%s %d" % [sim.gname(gd), int(rw["stock"][gd])])
	for d: String in rw.get("reveal", []):
		out.append("새 목적지: %s" % sim.item("destinations", d).get("name", d))
	var u := sim.item("unlocks", str(g.get("unlock", "")))
	if not u.is_empty():
		var names: Array = []
		for b: String in u.get("unlocks", []):
			names.append(str(sim.bdef(b).get("name", b)))
		if not names.is_empty():
			out.append("열림: " + ", ".join(names))
		for f: String in u.get("features", []):
			if f.begins_with("policy_slot"):
				out.append("정책 칸 +1")
		if u.has("grade_name"):
			out.append("성채 등급: %s%s" % [u["grade_name"], (" · 호칭 " + str(u["title"])) if u.has("title") else ""])
	return out


func _progress(g: Dictionary, m: Dictionary) -> float:
	var p := 1.0
	for c: Variant in g.get("cond", []):
		if c is Array and c.size() == 3 and float(c[2]) > 0.0:
			p = minf(p, clampf(float(m.get(str(c[0]), 0.0)) / float(c[2]), 0.0, 1.0))
	return p


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "goals":
		return null
	var done := _done(state)
	var m := Metrics.compute(sim, state)
	var steps: Array = []
	var next_id := ""
	for id: String in _ids():
		var g := sim.item("goals", id)
		var d := done.has(id)
		if not d and next_id == "":
			next_id = id
		steps.append({"id": id, "text": str(g.get("text", id)), "done": d, "progress": 1.0 if d else snappedf(_progress(g, m), 0.01),
			"rewards": _reward_text(state, g), "final": bool(g.get("final", false)), "done_day": float(done.get(id, -1.0))})
	return {"grade": state.milestone, "grade_name": state.identity.get("grade_name", ""), "title": state.identity.get("title", ""),
		"steps": steps, "next": next_id, "sandbox": next_id == "", "done_count": done.size(), "total": steps.size()}


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name != "hud":
		return
	var done := _done(state)
	for id: String in _ids():
		if done.has(id):
			continue
		var g := sim.item("goals", id)
		var m := Metrics.compute(sim, state)
		out["next_goal"] = {"id": id, "text": str(g.get("text", id)), "progress": snappedf(_progress(g, m), 0.01), "rewards": _reward_text(state, g)}
		return
	out["next_goal"] = {"id": "", "text": "구룡성채 완성 — 이제 자유롭게 성채를 가꾸자", "progress": 1.0, "rewards": []}
