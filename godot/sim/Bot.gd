class_name Bot
extends RefCounted
## Bot — 성향이 다른 자동 플레이어(data/bots.json). 사람처럼 Sim.apply()의 명령만 쓴다(규칙을 건드리지 않는다).
## 합격 기준(D7) 확인용: 봇들을 30일 돌려 서로 다른 성채가 나오는지 본다. tools/sim_run.gd가 부른다.
##  · plants: 위에서부터 보며 조건(when)·돈이 되는 것을 at 좌표 가까운 자리에 심는다(항목당 count개까지).
##  · zones: 첫 앵커를 심은 뒤 한 번 칠한다(zone + cols 또는 rect).
##  · policies / policy_rules: 고를 수 있게 되는 대로 맞춘다. rules는 when이 참인 동안 덮어쓴다.
##  · collect: {ratio: 0.5} = 수금함이 그만큼 차면 거둔다 / {every_days: 3} = 사흘에 한 번 몰아서.
##  · cards: 선택지 tags를 prefer(+1) / avoid(−2)로 채점해 고른다. delay_days만큼 묵혔다가 답한다.
##  · online_from / online_hours: 하루 중 접속해 있는 시간(그 밖은 fast_forward = 미접속).
## 봇의 기억은 state.flags["bot"]에 둔다(스냅샷에서 이어 돌릴 수 있게).

var sim: Sim
var id: String = ""
var conf: Dictionary = {}


func _init(s: Sim, bot_id: String) -> void:
	sim = s
	id = bot_id
	conf = sim.item("bots", bot_id)


func _mem(state: CityState) -> Dictionary:
	if not state.flags.has("bot"):
		state.flags["bot"] = {"id": id, "planted": {}, "zoned": false, "last_collect": 0}
	return state.flags["bot"]


## 지금 접속 중인가. 첫날은 시작하자마자 first_session_hours 동안 접속(첫 앵커를 심어야 하니까).
func online(state: CityState) -> bool:
	var span := float(conf.get("online_hours", 24))
	if span >= 24.0:
		return true
	var start := float(sim.cfg("time.start_hour", 6))
	if state.day == 1 and state.hour >= start and state.hour < start + float(conf.get("first_session_hours", 1)):
		return true
	var from := float(conf.get("online_from", 20))
	return state.hour >= from and state.hour < from + span


## 다음 접속까지 남은 도시 시간(미접속일 때만 의미 있음).
func hours_until_online(state: CityState) -> float:
	var from := float(conf.get("online_from", 20))
	return from - state.hour if state.hour < from else 24.0 - state.hour + from


## 한 번의 "손길": 정책 → 심기 → 긋기 → 거두기 → 결재.
func act(state: CityState) -> void:
	var mem := _mem(state)
	_policies(state)
	_plant(state, mem)
	if not mem["zoned"] and int(state.stats.get("plants", 0)) > 0:
		mem["zoned"] = true
		_zones(state)
	_collect(state, mem)
	_cards(state)


func _policies(state: CityState) -> void:
	var want: Dictionary = conf.get("policies", {}).duplicate()
	for r: Dictionary in conf.get("policy_rules", []):
		if sim.test(state, r.get("when")):
			want.merge(r.get("set", {}), true)
	for axis: String in want:
		if str(state.policies.get(axis, "")) != str(want[axis]):
			sim.apply(state, "policy", {"axis": axis, "value": str(want[axis])})


func _plant(state: CityState, mem: Dictionary) -> void:
	var list: Array = conf.get("plants", [])
	for i: int in list.size():
		var e: Dictionary = list[i]
		var key := str(i)
		if int(mem["planted"].get(key, 0)) >= int(e.get("count", 1)) or not sim.test(state, e.get("when")):
			continue
		var fid := str(e.get("facility", ""))
		var cost: Dictionary = {}
		for f: Dictionary in sim.query(state, "facilities", {}):
			if f["id"] == fid and not f["locked"]:
				cost = f["cost"]
		if cost.is_empty():
			continue
		var free: bool = float(cost["money"]) == 0.0
		if not free and (state.money < float(cost["money"]) + float(conf.get("plant_reserve", 15)) or state.materials < float(cost["materials"])):
			if e.get("wait", false):
				return
			continue
		var at: Array = e.get("at", [sim.W / 2, sim.H / 2])
		var best := Vector3i(-1, -1, -1)
		var best_d := 1.0e9
		for p: Vector3i in sim.query(state, "plant_spots", {"facility": fid}):
			if e.get("ground", false) and p.z > 0:
				continue
			var d := float((p.x - int(at[0])) * (p.x - int(at[0])) + (p.y - int(at[1])) * (p.y - int(at[1]))) + float(p.z) * float(e.get("z_cost", 3.0))
			if d < best_d:
				best_d = d
				best = p
		if best.x < 0:
			continue
		if sim.apply(state, "plant", {"facility": fid, "pos": best}).get("ok", false):
			mem["planted"][key] = int(mem["planted"].get(key, 0)) + 1
			return


func _zones(state: CityState) -> void:
	for z: Dictionary in conf.get("zones", []):
		var cols: Array = z.get("cols", []).duplicate()
		if z.has("rect"):
			var r: Array = z["rect"]
			for x: int in range(int(r[0]), int(r[2]) + 1):
				for y: int in range(int(r[1]), int(r[3]) + 1):
					cols.append([x, y])
		for c: Array in cols:
			sim.apply(state, "zone", {"col": Vector2i(int(c[0]), int(c[1])), "zone": str(z.get("zone", ""))})


func _collect(state: CityState, mem: Dictionary) -> void:
	var how: Dictionary = conf.get("collect", {"ratio": 0.5})
	if how.has("every_days"):
		if state.day - int(mem["last_collect"]) >= int(how["every_days"]):
			mem["last_collect"] = state.day
			sim.apply(state, "collect", {})
		return
	for p: Dictionary in sim.query(state, "collect_points", {}):
		if float(p["ratio"]) >= float(how.get("ratio", 0.5)) and float(p["amount"]) >= 1.0:
			sim.apply(state, "collect", {"point": int(p["id"])})


func _cards(state: CityState) -> void:
	var rule: Dictionary = conf.get("cards", {})
	var prefer: Array = rule.get("prefer", [])
	var avoid: Array = rule.get("avoid", [])
	for p: Dictionary in state.pending_cards.duplicate():
		if state.day - int(p.get("day", state.day)) < int(rule.get("delay_days", 0)):
			continue
		var order: Array = []
		for i: int in (p["choices"] as Array).size():
			var score := 0.0
			for t: Variant in p["choices"][i].get("tags", []):
				if t in prefer:
					score += 1.0 + 0.1 * float(prefer.size() - prefer.find(t)) / float(prefer.size())
				if t in avoid:
					score -= 2.0
			order.append([score, i])
		order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
		for o: Array in order:
			if sim.apply(state, "card", {"uid": int(p["uid"]), "choice": int(o[1])}).get("ok", false):
				break
