extends SimSystem
## 허가 — 정책 축(data/policies.json)의 값을 고른다. 고른 값은 state.policies에만 적히고,
## 효과는 각 시스템이 sim.mod(), policy.<axis>.<값> 지표, intake/care 블록으로 읽어 간다.
## 명령 `policy {axis, value}` · 질의 `policies`. 잠긴 옵션(unlock)은 해금 전까지 못 고른다.


func on_new_game(state: CityState) -> void:
	for a: Dictionary in _axes():
		state.policies[a["axis"]] = str(a.get("default", a["options"][0]["id"]))


func _axes() -> Array:
	return sim.db.get("policies", {}).get("axes", [])


func can(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "policy":
		return null
	var axis := str(args.get("axis", ""))
	var value := str(args.get("value", ""))
	var o := sim.option(axis, value)
	if o.is_empty():
		return {"ok": false, "reason": "그런 정책은 없다."}
	if not sim.is_unlocked(state, o.get("unlock")):
		var hint := str(sim.item("unlocks", str(o.get("unlock", ""))).get("hint", "아직 때가 아니다."))
		return {"ok": false, "reason": "아직 고를 수 없다 — " + hint}
	return {"ok": true, "reason": ""}


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "policy":
		return null
	var axis := str(args["axis"])
	var value := str(args["value"])
	if str(state.policies.get(axis, "")) == value:
		return {"ok": true, "reason": ""}
	state.policies[axis] = value
	state.stats["policy_changes"] = int(state.stats.get("policy_changes", 0)) + 1
	var o := sim.option(axis, value)
	for a: Dictionary in _axes():
		if a["axis"] == axis:
			sim.say(state, "%s: 이제 '%s'." % [a["name"], o.get("name", value)], "policy")
	sim.touch()
	sim.run(state, o.get("on_select", []))
	return {"ok": true, "reason": ""}


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "policies":
		return null
	var out: Array = []
	for a: Dictionary in _axes():
		var opts: Array = []
		for o: Dictionary in a.get("options", []):
			var locked := not sim.is_unlocked(state, o.get("unlock"))
			opts.append({"id": o["id"], "name": o.get("name", o["id"]), "desc": o.get("desc", ""), "locked": locked,
				"lock_hint": str(sim.item("unlocks", str(o.get("unlock", ""))).get("hint", "")) if locked else ""})
		out.append({"axis": a["axis"], "name": a.get("name", a["axis"]), "desc": a.get("desc", ""),
			"options": opts, "value": str(state.policies.get(a["axis"], ""))})
	return out
