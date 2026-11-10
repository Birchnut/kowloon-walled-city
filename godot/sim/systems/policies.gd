extends SimSystem
## policies — 정책(GDD §10). data/progression/policies.json. 칸 수 = 열린 "feature:policy_slot_N"의 수(unlocks.json).
##  policy_set {id, on}: 켜기는 빈 칸이 있어야, 같은 group(예: 감세/중과세)은 하나만. 끄기는 언제나.
##  효과는 Sim.mod 수정치(effects). 켜져 있는 동안 유지비: upkeep(₩/일) + upkeep_per_vice × 음성 시설 수 → 장부 'upkeep'.
##  돈이 모자라 유지비를 못 내면 그 정책이 저절로 꺼진다(기록 한 줄) — 금고는 음수가 되지 않는다.
##  상태: state.policies = {id: true}. 바뀌면 Sim.mods_changed.
## 끄면: 정책이 없고 수정치에도 들어가지 않는다.


func slots(state: CityState) -> int:
	var n := 0
	for k: String in state.unlocked:
		if k.begins_with("feature:policy_slot"):
			n += 1
	if not sim.enabled.has("progression"):
		n = 3
	return n


func _on_count(state: CityState) -> int:
	var n := 0
	for id: String in state.policies:
		if state.policies[id]:
			n += 1
	return n


func _cost_per_day(state: CityState, p: Dictionary) -> float:
	var c := float(p.get("upkeep", 0.0))
	var pv := float(p.get("upkeep_per_vice", 0.0))
	if pv > 0.0:
		c += pv * float((sim.cover(state).get("vice", []) as Array).size())
	return c


func can(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "policy_set":
		return null
	var id := str(args.get("id", ""))
	var p := sim.item("policies", id)
	if p.is_empty():
		return {"ok": false, "reason": "모르는 정책이다.", "code": "unknown"}
	if not bool(args.get("on", true)):
		return {"ok": true, "reason": "", "code": "ok"}
	if state.policies.get(id, false):
		return {"ok": false, "reason": "이미 켜져 있다.", "code": "on"}
	if _on_count(state) >= slots(state):
		return {"ok": false, "reason": "정책 칸이 없다(지금 %d칸 — 성채가 자라면 늘어난다)." % slots(state), "code": "slots"}
	var g := str(p.get("group", ""))
	if g != "":
		for o: String in state.policies:
			if o != id and state.policies[o] and str(sim.item("policies", o).get("group", "")) == g:
				return {"ok": false, "reason": Sim.kr("'%s'과(와) 함께 켤 수 없다." % sim.item("policies", o).get("name", o)), "code": "group"}
	return {"ok": true, "reason": "", "code": "ok"}


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "policy_set":
		return null
	var id := str(args["id"])
	var on := bool(args.get("on", true))
	var p := sim.item("policies", id)
	if on:
		state.policies[id] = true
		sim.say(state, "정책을 켰다: %s." % p.get("name", id))
	else:
		state.policies.erase(id)
		sim.say(state, "정책을 껐다: %s." % p.get("name", id))
	Sim.mods_changed(state)
	return {"ok": true, "reason": "", "on": on}


func tick(state: CityState, dt: float) -> void:
	if state.policies.is_empty():
		return
	for id: String in state.policies.keys():
		if not state.policies[id]:
			continue
		var c := _cost_per_day(state, sim.item("policies", id)) * dt
		if c <= 0.0:
			continue
		if state.money + 1e-9 < c:
			state.policies.erase(id)
			Sim.mods_changed(state)
			sim.say(state, "돈이 없어 정책 '%s'이(가) 꺼졌다." % sim.item("policies", id).get("name", id), "warn")
			continue
		state.money -= c
		state.book("upkeep", -c)
		state.stat_add("policy_upkeep", c)


## 설명 글의 {upkeep}·{upkeep_per_vice}를 데이터 값으로 채운다("유지비 ₩60/일").
static func desc(p: Dictionary) -> String:
	var t := str(p.get("desc", ""))
	for k: String in ["upkeep_per_vice", "upkeep"]:
		t = t.replace("{%s}" % k, Sim.won(float(p.get(k, 0))))
	return t


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "policies":
		return null
	var items: Array = []
	var max_s := slots(state)
	for id: String in sim.items("policies"):
		var p := sim.item("policies", id)
		var on := bool(state.policies.get(id, false))
		var locked := max_s == 0
		var cost := _cost_per_day(state, p)
		items.append({"id": id, "name": p.get("name", id), "desc": desc(p), "on": on, "locked": locked,
			"lock_hint": "세입자 60명이 되면 정책 칸이 열린다" if locked else "", "upkeep": snappedf(cost, 0.1), "group": p.get("group", "")})
	return {"slots": {"used": _on_count(state), "max": max_s}, "items": items}
