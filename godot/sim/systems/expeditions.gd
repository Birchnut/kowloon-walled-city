extends SimSystem
## expeditions — 탐험(GDD §8, 브리프 §13). 실제 시간(sim.now_unix)으로만 흐른다(배속·경제 시계와 무관).
##  팀: 완공 탐험 거점 하나당 1팀(최대 destinations.teams.max). 주민 노동력과 분리(확정).
##  expedition_send {team, dest, provision, pick?}: 팀이 쉬는 중 + 목적지를 앎 + 비용(돈)·보급(끼니 n) 확인 →
##   보상을 출발 때 결정론 RNG로 굴려 팀에 저장(보장 주력 + 덤 + 발견), started_unix/completes_unix 기록.
##  now_unix ≥ completes_unix면 done(expedition_done 한 번). 결과는 사라지지 않는다.
##  expedition_claim {team?}: done인 팀의 보상을 재고에 정확히 한 번 넣는다(멱등). 발견 적용: 거래처·도면·새 목적지.
##  수정치: exp.yield(주력·덤 배수), exp.time(걸리는 시간 배수), exp.cost(출발 비용 배수).
##  시계 방어: now가 출발보다 앞서면(시계를 되돌림) 남은 시간은 전체 시간을 넘지 않는다. 앞으로 크게 뛰어도 팀마다 결과는 하나뿐.
## 끄면: 탐험이 없다(질의는 빈 모양).

const STATE_NAME := {"idle": "쉬는 중", "out": "탐험 중", "done": "돌아옴"}


func _d() -> Dictionary:
	return sim.db.get("destinations", {})


func _dest(id: String) -> Dictionary:
	return sim.item("destinations", id)


func _max_teams() -> int:
	return int(_d().get("teams", {}).get("max", 3))


func on_new_game(state: CityState) -> void:
	for id: String in sim.items("destinations"):
		state.dests[id] = {"known": bool(_dest(id).get("known", false)), "visits": 0, "new": false}
	state.stats["start_unix"] = float(sim.now_unix)
	_sync(state)


# ------------------------------------------------------------------ 팀 수 · 완료 판정
func _sync(state: CityState) -> void:
	for id: String in sim.items("destinations"):
		if not state.dests.has(id):
			state.dests[id] = {"known": bool(_dest(id).get("known", false)), "visits": 0, "new": false}
	var want := mini(_max_teams(), int(sim.cover(state).get("teams", 0)))
	var live := 0
	for t: Dictionary in state.teams:
		if not t.get("retired", false):
			live += 1
	# 늘리기: 은퇴 표시를 먼저 거둔다 → 그래도 모자라면 새 팀
	for t: Dictionary in state.teams:
		if live < want and t.get("retired", false):
			t.erase("retired")
			live += 1
	while live < want:
		var nid := 1
		var used := {}
		for t: Dictionary in state.teams:
			used[int(t["id"])] = true
		while used.has(nid):
			nid += 1
		state.teams.append({"id": nid, "state": "idle", "dest": "", "started_unix": 0, "completes_unix": 0, "provision": false,
			"reward": {}, "finds": [], "pick": ""})
		live += 1
	# 줄이기: 쉬는 팀부터 없앤다. 나가 있는 팀은 은퇴 표시 → 수령 뒤 사라진다.
	var i := state.teams.size() - 1
	while live > want and i >= 0:
		var t: Dictionary = state.teams[i]
		if not t.get("retired", false):
			if t["state"] == "idle":
				state.teams.remove_at(i)
			else:
				t["retired"] = true
			live -= 1
		i -= 1
	state.teams.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))


func _update(state: CityState) -> void:
	var now := sim.now_unix
	for t: Dictionary in state.teams:
		if t["state"] == "out" and now >= int(t["completes_unix"]):
			t["state"] = "done"
			state.emit("expedition_done", {"team": int(t["id"])})
			sim.say(state, "탐험대 %d이(가) %s에서 돌아왔다. 짐을 풀어야 한다." % [int(t["id"]), _dname(str(t["dest"]))], "good")
			state.stat_add("exp_returns", 1.0)


func tick(state: CityState, _dt: float) -> void:
	_update(state)


func on_command(state: CityState, name: String, _args: Dictionary, _result: Dictionary) -> void:
	if name in ["build", "demolish", "debug"]:
		_sync(state)
		_update(state)


func on_day_start(state: CityState) -> void:
	_sync(state)


func fast_forward(state: CityState, _econ_days: float, _before: Dictionary, lines: Array) -> void:
	_sync(state)
	_update(state)
	var done: Array = []
	for t: Dictionary in state.teams:
		if t["state"] == "done":
			done.append("탐험대 %d(%s)" % [int(t["id"]), _dname(str(t["dest"]))])
	if not done.is_empty():
		lines.append("돌아와 짐을 기다리는 탐험대: %s." % ", ".join(done))


# ------------------------------------------------------------------ 글
func _dname(id: String) -> String:
	return str(_dest(id).get("name", id))


func _team(state: CityState, id: int) -> Dictionary:
	for t: Dictionary in state.teams:
		if int(t["id"]) == id:
			return t
	return {}


func _seconds(state: CityState, d: Dictionary) -> int:
	return maxi(30, int(roundf(float(d.get("seconds", 300)) * sim.mod(state, "exp.time"))))


func _cost(state: CityState, d: Dictionary) -> float:
	return roundf(float(d.get("cost", {}).get("money", 0)) * sim.mod(state, "exp.cost"))


func _meal_have(state: CityState) -> float:
	var n := 0.0
	for g: String in _d().get("provision", {}).get("goods", []):
		n += float(state.stock.get(g, 0.0))
	return n


func _reward_lines(rw: Dictionary) -> Array:
	var out: Array = []
	for g: String in rw:
		out.append({"good": g, "name": sim.gname(g), "n": int(rw[g])})
	return out


func _reward_text(rw: Dictionary) -> String:
	var parts: Array = []
	for g: String in rw:
		parts.append("%s %d" % [sim.gname(g), int(rw[g])])
	return " · ".join(parts)


# ------------------------------------------------------------------ 명령
func can(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"expedition_send":
			_sync(state)
			_update(state)
			var t := _team(state, int(args.get("team", -1)))
			if t.is_empty():
				return {"ok": false, "reason": "그런 탐험대가 없다(탐험 거점을 지으면 팀이 생긴다).", "code": "team"}
			if t.get("retired", false):
				return {"ok": false, "reason": "거점이 헐린 팀이다.", "code": "team"}
			if t["state"] == "out":
				return {"ok": false, "reason": "이미 탐험 중이다.", "code": "busy"}
			if t["state"] == "done":
				return {"ok": false, "reason": "먼저 짐을 받아야 한다(수령).", "code": "claim"}
			var id := str(args.get("dest", ""))
			var d := _dest(id)
			if d.is_empty():
				return {"ok": false, "reason": "모르는 목적지다.", "code": "dest"}
			if not bool(state.dests.get(id, {}).get("known", false)):
				return {"ok": false, "reason": "아직 모르는 곳이다 — %s." % str(d.get("reveal_hint", "탐험으로 알게 된다")), "code": "unknown"}
			var cost := _cost(state, d)
			if state.money + 1e-9 < cost:
				return {"ok": false, "reason": "출발 비용 ₩%d이(가) 모자란다." % int(cost), "code": "money"}
			if args.get("provision", false):
				var need := float(_d().get("provision", {}).get("n", 10))
				if _meal_have(state) + 1e-9 < need:
					return {"ok": false, "reason": "보급할 끼니 %d이(가) 모자란다." % int(need), "code": "provision"}
			var picks: Array = d.get("picks", [])
			var pick := str(args.get("pick", ""))
			if pick != "" and not picks.is_empty() and not (pick in picks):
				return {"ok": false, "reason": "그곳에서 고를 수 없는 자재다.", "code": "pick"}
			return {"ok": true, "reason": "", "code": "ok", "cost": {"money": cost, "goods": {}}, "seconds": _seconds(state, d)}
		"expedition_claim":
			_update(state)
			var any := false
			for t: Dictionary in state.teams:
				if t["state"] == "done" and (not args.has("team") or int(t["id"]) == int(args["team"])):
					any = true
			if not any:
				return {"ok": false, "reason": "받을 짐이 없다.", "code": "nothing", "rewards": [], "finds": []}
			return {"ok": true, "reason": "", "code": "ok"}
	return null


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"expedition_send":
			return _send(state, args)
		"expedition_claim":
			return _claim(state, args)
	return null


func _roll_n(state: CityState, lo: float, hi: float) -> float:
	if hi <= lo:
		return lo
	return lo + floorf(sim.roll(state) * (hi - lo + 1.0))


func _send(state: CityState, args: Dictionary) -> Dictionary:
	var t := _team(state, int(args["team"]))
	var id := str(args["dest"])
	var d := _dest(id)
	var dst: Dictionary = state.dests[id]
	var cost := _cost(state, d)
	if cost > 0.0:
		state.money -= cost
		state.book("build", -cost)
	var prov := bool(args.get("provision", false))
	if prov:
		var left := float(_d().get("provision", {}).get("n", 10))
		while left > 1e-9:
			var best := ""
			for g: String in _d().get("provision", {}).get("goods", []):
				if float(state.stock.get(g, 0.0)) > 1e-9 and (best == "" or float(state.stock[g]) > float(state.stock[best])):
					best = g
			if best == "":
				break
			var take := minf(left, float(state.stock[best]))
			state.stock[best] = float(state.stock[best]) - take
			sim.flow_add(best, "cons", take)
			left -= take
	var mult := sim.mod(state, "exp.yield") * (1.0 + (float(_d().get("provision", {}).get("bonus", 0.25)) if prov else 0.0))
	var rw := {}
	var pr: Dictionary = d.get("primary", {})
	var g0 := str(pr.get("good", ""))
	var picks: Array = d.get("picks", [])
	var pick := str(args.get("pick", ""))
	if not picks.is_empty():
		if pick == "":
			pick = str(picks[0])
			for m: String in picks:
				if float(state.stock.get(m, 0.0)) < float(state.stock.get(pick, 0.0)):
					pick = m
		g0 = pick
	var n0 := _roll_n(state, float(pr.get("min", 0)), float(pr.get("max", 0)))
	if g0 != "parts":
		n0 = roundf(n0 * mult)
	if g0 != "" and n0 > 0.0:
		rw[g0] = n0
	for bo: Dictionary in d.get("bonus", []):
		if sim.roll(state) < float(bo.get("chance", 1.0)):
			var g := str(bo["good"])
			var n := _roll_n(state, float(bo.get("min", 0)), float(bo.get("max", 0)))
			if g != "parts":
				n = roundf(n * mult)
			if n > 0.0:
				rw[g] = float(rw.get(g, 0.0)) + n
	var finds: Array = []
	for f: Dictionary in d.get("finds", []):
		if f.get("once", false) and int(dst.get("visits", 0)) > 0:
			continue
		if sim.roll(state) < float(f.get("chance", 1.0)):
			finds.append({"type": str(f["type"]), "id": str(f["id"])})
	if int(dst.get("visits", 0)) == 0:
		for r: String in d.get("reveals", []):
			finds.append({"type": "dest", "id": r})
	dst["visits"] = int(dst.get("visits", 0)) + 1
	dst["new"] = false
	var now := sim.now_unix
	var sec := _seconds(state, d)
	t["state"] = "out"
	t["dest"] = id
	t["started_unix"] = now
	t["completes_unix"] = now + sec
	t["provision"] = prov
	t["reward"] = rw
	t["finds"] = finds
	t["pick"] = pick
	if not state.stats.has("first_send_unix"):
		state.stats["first_send_unix"] = float(now)
		state.stats["first_send_day"] = state.econ_days
	state.stat_add("exp_sent", 1.0)
	state.stat_add("exp_sent_" + str(d.get("band", "near")), 1.0)
	state.stat_add("exp_team_seconds", float(sec))
	sim.say(state, "탐험대 %d이(가) %s(으)로 떠났다(%s)." % [int(t["id"]), _dname(id), _dur(sec)])
	return {"ok": true, "reason": "", "team": int(t["id"]), "completes_unix": now + sec, "seconds": sec}


static func _dur(sec: int) -> String:
	if sec >= 3600:
		var h := sec / 3600
		var m := (sec % 3600) / 60
		return "%d시간 %d분" % [h, m] if m > 0 else "%d시간" % h
	return "%d분" % maxi(1, sec / 60)


func _claim(state: CityState, args: Dictionary) -> Dictionary:
	_update(state)
	var total := {}
	var find_text: Array = []
	var claimed := 0
	for t: Dictionary in state.teams:
		if t["state"] != "done" or (args.has("team") and int(t["id"]) != int(args["team"])):
			continue
		var rw: Dictionary = t["reward"]
		for g: String in rw:
			var n := float(rw[g])
			state.stock[g] = float(state.stock.get(g, 0.0)) + n
			sim.flow_add(g, "imp", n)
			state.stat_add("exp." + g, n)
			total[g] = float(total.get(g, 0.0)) + n
		for f: Dictionary in t.get("finds", []):
			var ft := _apply_find(state, f)
			if ft != "":
				find_text.append(ft)
		var lines := _reward_lines(rw)
		state.emit("expedition_claimed", {"team": int(t["id"]), "rewards": lines})
		sim.say(state, "탐험대 %d의 짐: %s." % [int(t["id"]), _reward_text(rw) if not rw.is_empty() else "빈손"], "good")
		t["state"] = "idle"
		t["reward"] = {}
		t["finds"] = []
		state.stat_add("exp_claims_" + str(_dest(str(t["dest"])).get("band", "near")), 1.0)
		t["dest"] = ""
		claimed += 1
		state.stat_add("exp_claims", 1.0)
		if not state.stats.has("first_claim_unix"):
			state.stats["first_claim_unix"] = float(sim.now_unix)
			state.stats["first_claim_day"] = state.econ_days
	# 은퇴 표시된 팀은 수령 뒤 없앤다
	var i := state.teams.size() - 1
	while i >= 0:
		var t: Dictionary = state.teams[i]
		if t.get("retired", false) and t["state"] == "idle":
			state.teams.remove_at(i)
		i -= 1
	for s: String in find_text:
		sim.say(state, s, "good")
	return {"ok": claimed > 0, "reason": "" if claimed > 0 else "받을 짐이 없다.", "rewards": _reward_lines(total), "finds": find_text, "teams": claimed}


func _apply_find(state: CityState, f: Dictionary) -> String:
	var id := str(f.get("id", ""))
	match str(f.get("type", "")):
		"partner":
			if state.partners.has(id):
				return ""
			state.partners[id] = true
			var nm := str(sim.db.get("partners", {}).get("partners", {}).get(id, {}).get("name", id))
			return "새 거래처: %s — 교역 화면에서 계약을 맺을 수 있다." % nm
		"blueprint":
			var bp: Dictionary = state.flags.get("blueprints", {})
			if bp.has(id):
				return ""
			bp[id] = true
			state.flags["blueprints"] = bp
			var bn := id
			for b: String in sim.items("buildings"):
				if str(sim.bdef(b).get("blueprint", "")) == id:
					bn = str(sim.bdef(b).get("name", b))
			return "도면을 찾았다: %s." % bn
		"dest":
			return reveal(state, id)
	return ""


## 목적지를 알게 한다(발견·목표·연구 공용). 반환 = 기록 문장("" = 이미 앎).
func reveal(state: CityState, id: String) -> String:
	if not state.dests.has(id) or bool(state.dests[id].get("known", false)):
		return ""
	state.dests[id]["known"] = true
	state.dests[id]["new"] = true
	return "지도에 새 목적지: %s." % _dname(id)


# ------------------------------------------------------------------ 질의
func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "expeditions":
		return null
	_sync(state)
	_update(state)
	var now := sim.now_unix
	var teams: Array = []
	for t: Dictionary in state.teams:
		var total := maxi(0, int(t["completes_unix"]) - int(t["started_unix"]))
		var left := 0
		if t["state"] == "out":
			left = clampi(int(t["completes_unix"]) - now, 0, total)
		teams.append({"id": int(t["id"]), "name": "탐험대 %d" % int(t["id"]), "state": t["state"], "state_name": STATE_NAME.get(t["state"], ""),
			"dest": t["dest"], "dest_name": _dname(str(t["dest"])) if str(t["dest"]) != "" else "",
			"seconds_left": left, "total_seconds": total,
			"reward_text": _reward_text(t["reward"]) if t["state"] == "done" else ("" if t["state"] == "idle" else "돌아오는 중"),
			"rewards": _reward_lines(t["reward"]) if t["state"] == "done" else [], "provision": bool(t.get("provision", false)),
			"retired": bool(t.get("retired", false))})
	var dests: Array = []
	var mats: Array = sim.db.get("upgrade_costs", {}).get("materials", [])
	for id: String in sim.items("destinations"):
		var d := _dest(id)
		var st: Dictionary = state.dests.get(id, {})
		var pr: Dictionary = d.get("primary", {})
		var picks: Array = []
		for g: String in d.get("picks", []):
			picks.append({"good": g, "name": sim.gname(g)})
		var pg := str(pr.get("good", ""))
		var mult := sim.mod(state, "exp.yield")
		var bon: Array = []
		for bo: Dictionary in d.get("bonus", []):
			var g := str(bo["good"])
			var ch := float(bo.get("chance", 1.0))
			if ch >= 1.0:
				bon.append("%s %d~%d" % [sim.gname(g), int(bo.get("min", 0)), int(bo.get("max", 0))])
			else:
				bon.append("%s(%d%%)" % [sim.gname(g), int(roundf(ch * 100.0))])
		for f: Dictionary in d.get("finds", []):
			if f.get("once", false) and int(st.get("visits", 0)) > 0:
				continue
			if f["type"] == "partner":
				bon.append("거래처 발견")
			elif f["type"] == "blueprint":
				bon.append("도면(첫 방문)")
		var k := 1.0 if pg == "parts" else mult
		dests.append({"id": id, "name": d.get("name", id), "desc": d.get("desc", ""), "map": d.get("map", [0.5, 0.5]), "band": d.get("band", "near"),
			"seconds": _seconds(state, d),
			"primary": {"good": pg, "name": sim.gname(pg) if pg != "" else "고른 자재", "min": int(roundf(float(pr.get("min", 0)) * k)), "max": int(roundf(float(pr.get("max", 0)) * k))},
			"picks": picks, "bonus_text": "덤: " + ", ".join(bon) if not bon.is_empty() else "", "cost": {"money": _cost(state, d)},
			"known": bool(st.get("known", false)), "locked_hint": "" if bool(st.get("known", false)) else str(d.get("reveal_hint", "탐험으로 알게 된다")),
			"visits": int(st.get("visits", 0)), "new": bool(st.get("new", false)),
			"per_hour": snappedf((float(pr.get("min", 0)) + float(pr.get("max", 0))) * 0.5 * k * 3600.0 / float(maxi(1, _seconds(state, d))), 0.1)})
	var pv: Dictionary = _d().get("provision", {})
	var gn: Array = []
	for g: String in pv.get("goods", []):
		gn.append(sim.gname(g))
	var mat_rows: Array = []
	for m: String in mats + ["parts"]:
		mat_rows.append({"id": m, "name": sim.gname(m), "have": int(state.stock.get(m, 0.0))})
	var live := 0
	for t: Dictionary in state.teams:
		if not t.get("retired", false):
			live += 1
	return {"teams": teams, "slots": {"have": live, "max": _max_teams()}, "dests": dests,
		"provision": {"good_text": "끼니 %d(%s)" % [int(pv.get("n", 10)), "·".join(gn)], "bonus_text": "수확 +%d%%" % int(roundf(float(pv.get("bonus", 0.25)) * 100.0)),
			"enough": _meal_have(state) + 1e-9 >= float(pv.get("n", 10))},
		"materials": mat_rows, "now_unix": now}


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name != "hud":
		return
	_update(state)
	var done := 0
	var idle := 0
	for t: Dictionary in state.teams:
		if t["state"] == "done":
			done += 1
		elif t["state"] == "idle" and not t.get("retired", false):
			idle += 1
	out["teams_done"] = done
	out["teams_idle"] = idle
