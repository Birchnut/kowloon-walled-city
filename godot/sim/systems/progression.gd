extends SimSystem
## progression — 해금(관문만). data/progression/unlocks.json의 단계를 order 순으로 보고, 조건(Expr + Metrics)이 참이 되면
##  그 단계의 시설을 state.unlocked[id] = 경제일로 영구히 연다(인구가 줄어도 닫지 않음, 제안 A8).
##  grade_name/title이 있으면 성채 등급(milestone)과 호칭(identity)을 바꾼다. features는 "feature:<이름>"으로 연다(B 파트가 읽음).
##  이벤트: unlock{id, name}, milestone{grade, grade_name, title}. 목표 문구(goals)는 B 파트.
## 끄면: 모든 시설이 처음부터 열려 있다(Sim.is_unlocked가 true).


func on_new_game(state: CityState) -> void:
	_check(state)


func tick(state: CityState, _dt: float) -> void:
	_happy(state)
	_check(state)


## 사치 시설 해금 조건 "행복도 n 이상을 m일 유지": 조건에 나오는 n마다 연속 시작 시각을 state.flags.happy_since[n]에 둔다(-1 = 끊김).
var _thr: Array = []


func setup(s: Sim) -> void:
	super.setup(s)
	_thr.clear()
	for id: String in sim.items("unlocks"):
		for c: Variant in sim.item("unlocks", id).get("cond", []):
			if c is Array and str(c[0]).begins_with("happy_held."):
				var k := str(c[0]).substr(11)
				if not (k in _thr):
					_thr.append(k)


func _happy(state: CityState) -> void:
	if _thr.is_empty():
		return
	var hs: Dictionary = state.flags.get("happy_since", {})
	for k: String in _thr:
		var on := state.happiness >= float(k)
		var cur := float(hs.get(k, -1.0))
		if on and cur < 0.0:
			hs[k] = state.econ_days
		elif not on and cur >= 0.0:
			hs[k] = -1.0
	state.flags["happy_since"] = hs


func _steps() -> Array:
	var ids: Array = sim.items("unlocks").keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(sim.item("unlocks", a).get("order", 0)) < int(sim.item("unlocks", b).get("order", 0)))
	return ids


func _check(state: CityState) -> void:
	var done: Dictionary = state.flags.get("unlock_steps", {})
	var m: Dictionary = {}
	for id: String in _steps():
		if done.has(id):
			continue
		var u := sim.item("unlocks", id)
		if m.is_empty():
			m = Metrics.compute(sim, state)
		if not Expr.test(u.get("cond", []), m):
			continue
		done[id] = state.econ_days
		state.flags["unlock_steps"] = done
		var names: Array = []
		for b: String in u.get("unlocks", []):
			if not state.unlocked.has(b):
				state.unlocked[b] = state.econ_days
				var nm := "주거" if b == "house" else str(sim.bdef(b).get("name", b))
				names.append(nm)
				state.emit("unlock", {"id": b, "name": nm})
		for f: String in u.get("features", []):
			state.unlocked["feature:" + f] = state.econ_days
		if u.has("grade_name"):
			state.milestone = int(u.get("order", 0))
			state.identity["grade_name"] = str(u["grade_name"])
			if u.has("title"):
				state.identity["title"] = str(u["title"])
			state.emit("milestone", {"grade": state.milestone, "grade_name": state.identity["grade_name"], "title": state.identity.get("title", "")})
			if int(u.get("order", 0)) > 0:
				sim.say(state, "성채 등급: %s. 이제 사람들은 %s(이)라 부른다." % [u["grade_name"], state.identity.get("title", "")], "good")
		if not names.is_empty() and int(u.get("order", 0)) > 0:
			sim.say(state, "새로 지을 수 있다: %s" % ", ".join(names), "good")
		state.stats["unlock_%s_day" % id] = state.econ_days
