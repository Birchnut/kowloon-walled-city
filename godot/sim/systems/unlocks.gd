extends SimSystem
## 해금 — 레벨이 아니라 "조건의 조합"으로 열린다. data/unlocks.json의 각 항목은
##   { name, cond(조건식), log(열릴 때 기록), hint(잠겨 있을 때 UI에 보일 한 줄) }.
## 매시 조건을 보고, 맞으면 state.unlocked[id] = 날짜 + `unlock` 이벤트 + 기록.
## 무엇이 잠기는지는 콘텐츠 쪽이 정한다: facilities/businesses의 "unlock", policies 옵션의 "unlock" 이 여기 id를 가리킨다.
## 이 시스템을 끄면 전부 열린 것으로 친다(sim.is_unlocked).


func on_new_game(state: CityState) -> void:
	_check(state)


func on_hour(state: CityState, _hour: int) -> void:
	_check(state)


func _check(state: CityState) -> void:
	var defs := sim.items("unlocks")
	for id: String in defs:
		if state.unlocked.has(id) or not sim.test(state, defs[id].get("cond")):
			continue
		state.unlocked[id] = state.day
		state.emit("unlock", {"id": id})
		sim.say(state, str(defs[id].get("log", "%s: 이제 할 수 있다." % defs[id].get("name", id))), "unlock")
		sim.run(state, defs[id].get("effects", []))
		sim.touch()


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "unlocks":
		return null
	var out: Array = []
	var defs := sim.items("unlocks")
	for id: String in defs:
		out.append({"id": id, "name": defs[id].get("name", id), "hint": defs[id].get("hint", ""),
			"unlocked": state.unlocked.has(id), "day": int(state.unlocked.get(id, 0))})
	return out


func fast_forward(state: CityState, _hours: float, before: Dictionary, lines: Array) -> void:
	var defs := sim.items("unlocks")
	for id: String in defs:
		if state.unlocked.has(id) and not before.has("unlocked." + id):
			lines.append("새로 할 수 있게 된 일: %s." % defs[id].get("name", id))
