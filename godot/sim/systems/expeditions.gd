extends SimSystem
## expeditions — 탐험(GDD_PC §5). v4: **게임 시계(econ_days)만** 쓴다(배속을 따른다, 실제 시계 없음).
##  팀: 완공 탐험 거점 하나당 1팀(최대 destinations.teams.max). 주민 노동력과 분리(확정).
##  던전 재고: 목적지마다 stock{상품: 최대}가 있고, 털면 줄고 게임 시간으로 다시 찬다(regen = 하루에 최대치의 몇 %).
##  자동 파견 expedition_send {team, dest, provision, pick?}: 팀이 쉬는 중 + 목적지를 앎 + 비용(돈)·보급 확인 →
##   보상을 출발 때 결정론 RNG로 굴려(던전 재고를 넘지 않게, 재고에서 뺀다) 팀에 저장, started_at/completes_at(econ_days).
##   econ_days ≥ completes_at이면 done(expedition_done 한 번). 결과는 사라지지 않는다.
##  expedition_claim {team?}: done인 팀의 보상을 재고에 정확히 한 번(멱등). 발견: 거래처·도면·새 목적지.
##  직접 줍기(나중에 만들 미니게임과의 약속): run_begin {dest} → 팀 하나를 "run"으로, {stock, danger, seed}.
##   run_result {dest, loot{상품:n}, outcome:"boss"|"exit"|"down", finds:[String]} → 짐을 던전 재고·배낭 한도로 검사,
##   재고에서 빼고 창고에 넣는다(down이면 절반, 나머지는 lost), boss면 목적지 run.boss 덤. finds = "partner:id"|"blueprint:id"|"dest:id"
##   (그 목적지가 줄 수 있는 것만). 팀은 쉬는 중으로 돌아온다.
##  수정치: exp.yield(주력·덤 배수), exp.time(걸리는 날 배수), exp.cost(출발 비용 배수).
## 끄면: 탐험이 없다(질의는 빈 모양).

const STATE_NAME := {"idle": "쉬는 중", "out": "탐험 중", "done": "돌아옴", "run": "직접 줍는 중"}


func _d() -> Dictionary:
	return sim.db.get("destinations", {})


func _dest(id: String) -> Dictionary:
	return sim.item("destinations", id)


func _max_teams() -> int:
	return int(_d().get("teams", {}).get("max", 3))


func _sec_per_day() -> float:
	return float(sim.cfg("time.seconds_per_day", 600))


func on_new_game(state: CityState) -> void:
	for id: String in sim.items("destinations"):
		state.dests[id] = _fresh(id)
	_sync(state)


func _fresh(id: String) -> Dictionary:
	var st := {}
	var mx: Dictionary = _dest(id).get("stock", {})
	for g: String in mx:
		st[g] = float(mx[g])
	return {"known": bool(_dest(id).get("known", false)), "visits": 0, "new": false, "stock": st}


# ------------------------------------------------------------------ 팀 수 · 완료 판정
func _sync(state: CityState) -> void:
	for id: String in sim.items("destinations"):
		if not state.dests.has(id):
			state.dests[id] = _fresh(id)
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
		state.teams.append({"id": nid, "state": "idle", "dest": "", "started_at": 0.0, "completes_at": 0.0,
			"started_unix": 0, "completes_unix": 0, "provision": false, "reward": {}, "finds": [], "pick": ""})
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
	for t: Dictionary in state.teams:
		if t["state"] == "out" and state.econ_days + 1e-9 >= float(t["completes_at"]):
			t["state"] = "done"
			state.emit("expedition_done", {"team": int(t["id"])})
			sim.say(state, "탐험대 %d이(가) %s에서 돌아왔다. 짐을 풀어야 한다." % [int(t["id"]), _dname(str(t["dest"]))], "good")
			state.stat_add("exp_returns", 1.0)


var _sync_key := ""


func tick(state: CityState, dt: float) -> void:
	var k := "%d:%d" % [state.get_instance_id(), state.layout_rev()]
	if k != _sync_key or sim.no_cache:
		_sync_key = k
		_sync(state)
	_update(state)
	# 던전 재고가 다시 찬다
	for id: String in state.dests:
		var mx: Dictionary = _dest(id).get("stock", {})
		if mx.is_empty():
			continue
		var st: Dictionary = state.dests[id].get("stock", {})
		var rg := float(_dest(id).get("regen", 0.5)) * dt
		for g: String in mx:
			var cur := float(st.get(g, float(mx[g])))
			if cur < float(mx[g]):
				st[g] = minf(float(mx[g]), cur + float(mx[g]) * rg)
		state.dests[id]["stock"] = st


func on_command(state: CityState, name: String, _args: Dictionary, _result: Dictionary) -> void:
	if name in ["build", "demolish", "debug"]:
		_sync(state)
		_update(state)


func on_day_start(state: CityState) -> void:
	_sync(state)


# ------------------------------------------------------------------ 글
func _dname(id: String) -> String:
	return str(_dest(id).get("name", id))


func _team(state: CityState, id: int) -> Dictionary:
	for t: Dictionary in state.teams:
		if int(t["id"]) == id:
			return t
	return {}


func _idle_team(state: CityState) -> Dictionary:
	for t: Dictionary in state.teams:
		if t["state"] == "idle" and not t.get("retired", false):
			return t
	return {}


## 걸리는 경제일(배속을 따른다).
func _days(state: CityState, d: Dictionary) -> float:
	var base := float(d.get("days", float(d.get("seconds", 300)) / _sec_per_day()))
	return maxf(sim.step_days, base * sim.mod(state, "exp.time"))


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


## 던전 재고 비율(0..1, 최대치 합 대비).
func _stock_pct(state: CityState, id: String) -> float:
	var mx: Dictionary = _dest(id).get("stock", {})
	if mx.is_empty():
		return 1.0
	var a := 0.0
	var b := 0.0
	var st: Dictionary = state.dests.get(id, {}).get("stock", {})
	var auto := _auto_goods(_dest(id))
	for g: String in mx:
		if not auto.is_empty() and not auto.has(g):
			continue     # 직접 줍기만 꺼내는 것(통조림·부품 등)은 자동 파견 기준 비율에서 뺀다
		a += float(st.get(g, float(mx[g])))
		b += float(mx[g])
	return a / b if b > 0.0 else 1.0


## 자동 파견이 꺼내는 상품(주력·고르는 자재·덤).
func _auto_goods(d: Dictionary) -> Dictionary:
	var out := {}
	var g0 := str(d.get("primary", {}).get("good", ""))
	if g0 != "":
		out[g0] = true
	for m: String in d.get("picks", []):
		out[m] = true
	for bo: Dictionary in d.get("bonus", []):
		out[str(bo["good"])] = true
	return out


## 던전에서 g를 n개 빼 간다(재고가 없는 상품은 무한). 반환 = 실제로 뺀 양(정수).
func _take(state: CityState, id: String, g: String, n: float) -> float:
	var mx: Dictionary = _dest(id).get("stock", {})
	if not mx.has(g):
		return n
	var st: Dictionary = state.dests[id]["stock"]
	var have := floorf(float(st.get(g, float(mx[g]))) + 1e-6)
	var got := minf(n, maxf(0.0, have))
	st[g] = float(st.get(g, float(mx[g]))) - got
	return got


# ------------------------------------------------------------------ 명령
func can(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"expedition_send":
			_sync(state)
			_update(state)
			var t := _team(state, int(args.get("team", -1)))
			if t.is_empty():
				return {"ok": false, "reason": "그런 탐험대가 없다(줍줍 본부를 지으면 팀이 생긴다).", "code": "team"}
			if t.get("retired", false):
				return {"ok": false, "reason": "거점이 헐린 팀이다.", "code": "team"}
			if t["state"] == "out" or t["state"] == "run":
				return {"ok": false, "reason": "이미 탐험 중이다.", "code": "busy"}
			if t["state"] == "done":
				return {"ok": false, "reason": "먼저 짐을 받아야 한다(수령).", "code": "claim"}
			var id := str(args.get("dest", ""))
			var c := _can_dest(state, id)
			if not c["ok"]:
				return c
			var d := _dest(id)
			if args.get("provision", false):
				var need := float(_d().get("provision", {}).get("n", 10))
				if _meal_have(state) + 1e-9 < need:
					return {"ok": false, "reason": Sim.kr("보급할 끼니 %d이(가) 모자란다." % int(need)), "code": "provision"}
			var picks: Array = d.get("picks", [])
			var pick := str(args.get("pick", ""))
			if pick != "" and not picks.is_empty() and not (pick in picks):
				return {"ok": false, "reason": "그곳에서 고를 수 없는 자재다.", "code": "pick"}
			var days := _days(state, d)
			return {"ok": true, "reason": "", "code": "ok", "cost": {"money": _cost(state, d), "goods": {}}, "days": days,
				"seconds": int(roundf(days * _sec_per_day()))}
		"expedition_claim":
			_update(state)
			var any := false
			for t: Dictionary in state.teams:
				if t["state"] == "done" and (not args.has("team") or int(t["id"]) == int(args["team"])):
					any = true
			if not any:
				return {"ok": false, "reason": "받을 짐이 없다.", "code": "nothing", "rewards": [], "finds": []}
			return {"ok": true, "reason": "", "code": "ok"}
		"run_begin":
			if DEST_ALIAS.has(str(args.get("dest", ""))):
				args["dest"] = DEST_ALIAS[str(args["dest"])]      # 시제품의 던전 id(같은 사전이 apply로 간다)
			_sync(state)
			_update(state)
			if not (state.flags.get("run", {}) as Dictionary).is_empty():
				return {"ok": false, "reason": "이미 직접 줍는 중이다.", "code": "busy"}
			if _idle_team(state).is_empty():
				return {"ok": false, "reason": "쉬는 탐험대가 없다(줍줍 본부의 팀이 모두 나가 있거나 본부가 없다).", "code": "busy"}
			var c := _can_dest(state, str(args.get("dest", "")))
			if not c["ok"]:
				return c
			return {"ok": true, "reason": "", "code": "ok", "cost": {"money": _cost(state, _dest(str(args["dest"]))), "goods": {}}}
		"run_result":
			if DEST_ALIAS.has(str(args.get("dest", ""))):
				args["dest"] = DEST_ALIAS[str(args["dest"])]
			return _check_result(state, args)
	return null


func _can_dest(state: CityState, id: String) -> Dictionary:
	var d := _dest(id)
	if d.is_empty():
		return {"ok": false, "reason": "모르는 목적지다.", "code": "dest"}
	if not bool(state.dests.get(id, {}).get("known", false)):
		return {"ok": false, "reason": "아직 모르는 곳이다 — %s." % str(d.get("reveal_hint", "탐험으로 알게 된다")), "code": "unknown"}
	var cost := _cost(state, d)
	if state.money + 1e-9 < cost:
		return {"ok": false, "reason": Sim.kr("출발 비용 %s이(가) 모자란다." % Sim.won(cost)), "code": "money"}
	return {"ok": true, "reason": "", "code": "ok"}


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"expedition_send":
			return _send(state, args)
		"expedition_claim":
			return _claim(state, args)
		"run_begin":
			return _run_begin(state, args)
		"run_result":
			return _run_result(state, args)
	return null


func _roll_n(state: CityState, lo: float, hi: float) -> float:
	if hi <= lo:
		return lo
	return lo + floorf(sim.roll(state) * (hi - lo + 1.0))


func _pay(state: CityState, d: Dictionary) -> void:
	var cost := _cost(state, d)
	if cost > 0.0:
		state.money -= cost
		state.book("build", -cost)
		state.stat_add("spent_expedition", cost)


func _send(state: CityState, args: Dictionary) -> Dictionary:
	var t := _team(state, int(args["team"]))
	var id := str(args["dest"])
	var d := _dest(id)
	var dst: Dictionary = state.dests[id]
	_pay(state, d)
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
	if g0 != "":
		n0 = _take(state, id, g0, n0)
		if n0 > 0.0:
			rw[g0] = n0
	for bo: Dictionary in d.get("bonus", []):
		if sim.roll(state) < float(bo.get("chance", 1.0)):
			var g := str(bo["good"])
			var n := _roll_n(state, float(bo.get("min", 0)), float(bo.get("max", 0)))
			if g != "parts":
				n = roundf(n * mult)
			n = _take(state, id, g, n)
			if n > 0.0:
				rw[g] = float(rw.get(g, 0.0)) + n
	var finds: Array = []
	for f: Dictionary in d.get("finds", []):
		if f.get("once", false) and int(dst.get("visits", 0)) > 0:
			continue
		if f.get("run_only", false):
			continue
		if sim.roll(state) < float(f.get("chance", 1.0)):
			finds.append({"type": str(f["type"]), "id": str(f["id"])})
	if int(dst.get("visits", 0)) == 0:
		for r: String in d.get("reveals", []):
			finds.append({"type": "dest", "id": r})
	dst["visits"] = int(dst.get("visits", 0)) + 1
	dst["new"] = false
	var days := _days(state, d)
	t["state"] = "out"
	t["dest"] = id
	t["started_at"] = state.econ_days
	t["completes_at"] = state.econ_days + days
	t["provision"] = prov
	t["reward"] = rw
	t["finds"] = finds
	t["pick"] = pick
	if not state.stats.has("first_send_day"):
		state.stats["first_send_day"] = state.econ_days
	state.stat_add("exp_sent", 1.0)
	state.stat_add("exp_sent_" + str(d.get("band", "near")), 1.0)
	state.stat_add("exp_team_days", days)
	sim.say(state, "탐험대 %d이(가) %s(으)로 떠났다(%s)." % [int(t["id"]), _dname(id), Queries.day_text(days)])
	return {"ok": true, "reason": "", "team": int(t["id"]), "completes_at": t["completes_at"], "days": days, "seconds": int(roundf(days * _sec_per_day()))}


func _claim(state: CityState, args: Dictionary) -> Dictionary:
	_update(state)
	var total := {}
	var find_text: Array = []
	var claimed := 0
	for t: Dictionary in state.teams:
		if t["state"] != "done" or (args.has("team") and int(t["id"]) != int(args["team"])):
			continue
		var rw: Dictionary = t["reward"]
		_deposit(state, rw, total)
		for f: Dictionary in t.get("finds", []):
			var ft := _apply_find(state, f)
			if ft != "":
				find_text.append(ft)
		state.emit("expedition_claimed", {"team": int(t["id"]), "rewards": _reward_lines(rw)})
		sim.say(state, "탐험대 %d의 짐: %s." % [int(t["id"]), _reward_text(rw) if not rw.is_empty() else "빈손"], "good")
		t["state"] = "idle"
		t["reward"] = {}
		t["finds"] = []
		state.stat_add("exp_claims_" + str(_dest(str(t["dest"])).get("band", "near")), 1.0)
		t["dest"] = ""
		claimed += 1
		state.stat_add("exp_claims", 1.0)
		if not state.stats.has("first_claim_day"):
			state.stats["first_claim_day"] = state.econ_days
	_drop_retired(state)
	for s: String in find_text:
		sim.say(state, s, "good")
	return {"ok": claimed > 0, "reason": "" if claimed > 0 else "받을 짐이 없다.", "rewards": _reward_lines(total), "finds": find_text, "teams": claimed}


func _deposit(state: CityState, rw: Dictionary, total: Dictionary) -> void:
	for g: String in rw:
		var n := float(rw[g])
		state.stock[g] = float(state.stock.get(g, 0.0)) + n
		sim.flow_add(g, "imp", n)
		state.stat_add("exp." + g, n)
		total[g] = float(total.get(g, 0.0)) + n


func _drop_retired(state: CityState) -> void:
	var i := state.teams.size() - 1
	while i >= 0:
		var t: Dictionary = state.teams[i]
		if t.get("retired", false) and t["state"] == "idle":
			state.teams.remove_at(i)
		i -= 1


# ------------------------------------------------------------------ 직접 줍기(약속만 — 미니게임은 나중)
func _run_conf(d: Dictionary) -> Dictionary:
	var base: Dictionary = _d().get("run", {})
	var own: Dictionary = d.get("run", {})
	var out := base.duplicate()
	out.merge(own, true)
	return out


## 미니게임 시제품의 상품 id → 도시 id(canned → cans, elec → elec_scrap). 같은 상품이 두 이름으로 오면 더한다.
const RUN_ALIAS := {"canned": "cans", "elec": "elec_scrap"}
const DEST_ALIAS := {"scrap_yard": "junk_yard"}


func _alias_loot(loot: Dictionary) -> Dictionary:
	var out := {}
	for g: Variant in loot:
		var k := str(RUN_ALIAS.get(str(g), str(g)))
		out[k] = int(out.get(k, 0)) + int(loot[g])
	return out


## 한도를 넘을 때 남길 순서: 값어치 높은 것부터(부품 → 전자 폐품 → 자재 → 통조림 → 고물), 같은 값이면 id 순.
const RUN_VALUE := {"parts": 10.0, "elec_scrap": 4.0, "metal": 3.0, "wood": 3.0, "concrete": 3.0, "cans": 2.0, "scrap": 1.0}


func _run_order(loot: Dictionary) -> Array:
	var ks: Array = loot.keys()
	ks.sort_custom(func(a: String, b: String) -> bool:
		var va := float(RUN_VALUE.get(a, 1.5))
		var vb := float(RUN_VALUE.get(b, 1.5))
		return va > vb if va != vb else a < b)
	return ks


## 지금 도시에 모자란 것(던전에서 나올 수 있는 상품 중) — 미니게임의 "지금 도시에 모자란 것" 줄. dest를 주면 그 던전 재고에 있는 것만.
func _run_wanted(state: CityState, dest: String) -> Array:
	var can_give := {}
	for id: String in sim.items("destinations"):
		if dest != "" and id != dest:
			continue
		for g: String in _dest(id).get("stock", {}):
			can_give[g] = true
	var need := {}
	for m: String in sim.db.get("upgrade_costs", {}).get("materials", []):
		need[m] = float(sim.db["upgrade_costs"]["items"]["2to3"].get("qty", 16))
	need["scrap"] = 30.0
	need["parts"] = 4.0
	need["elec_scrap"] = 10.0
	need["cans"] = 20.0
	var out: Array = []
	for g: String in _run_order(can_give):
		var short := float(state.stock.get(g, 0.0)) < float(need.get(g, 10.0))
		var f: Variant = state.flags.get("fill", {}).get(g)
		if f != null and float(f) < 0.999:
			short = true
		if short:
			out.append(g)
	return out


func _run_begin(state: CityState, args: Dictionary) -> Dictionary:
	var id := str(args["dest"])
	var d := _dest(id)
	var t := _idle_team(state)
	_pay(state, d)
	var seed := sim.rand_seed(state)
	t["state"] = "run"
	t["dest"] = id
	t["started_at"] = state.econ_days
	t["completes_at"] = state.econ_days
	state.flags["run"] = {"team": int(t["id"]), "dest": id, "seed": seed, "at": state.econ_days}
	state.dests[id]["visits"] = int(state.dests[id].get("visits", 0)) + 1
	state.dests[id]["new"] = false
	state.stat_add("run_begin", 1.0)
	var st := {}
	for g: String in state.dests[id].get("stock", {}):
		st[g] = int(floorf(float(state.dests[id]["stock"][g]) + 1e-6))
	sim.say(state, "탐험대 %d이(가) %s에 직접 들어갔다." % [int(t["id"]), _dname(id)])
	var rc := _run_conf(d)
	return {"ok": true, "reason": "", "stock": st, "danger": int(rc.get("danger", d.get("danger", 1))), "seed": seed,
		"carry": int(rc.get("carry", 40)), "carry_cap": int(rc.get("carry", 40)), "team": int(t["id"])}


func _check_result(state: CityState, args: Dictionary) -> Dictionary:
	var run: Dictionary = state.flags.get("run", {})
	var id := str(args.get("dest", ""))
	if run.is_empty():
		return {"ok": false, "reason": "직접 줍기를 시작하지 않았다(run_begin 먼저).", "code": "no_run"}
	if str(run.get("dest", "")) != id:
		return {"ok": false, "reason": "다른 목적지에서 시작한 줍기다.", "code": "dest"}
	var outcome := str(args.get("outcome", ""))
	if not (outcome in ["boss", "exit", "down"]):
		return {"ok": false, "reason": "결과는 boss·exit·down 중 하나여야 한다.", "code": "outcome"}
	var loot: Variant = args.get("loot", {})
	if not (loot is Dictionary):
		return {"ok": false, "reason": "짐(loot)은 {상품: 개수}여야 한다.", "code": "loot"}
	loot = _alias_loot(loot)
	var rc := _run_conf(_dest(id))
	var carry := int(rc.get("carry", 40))
	var total := 0
	var st: Dictionary = state.dests.get(id, {}).get("stock", {})
	for g: String in loot:
		var n := int(loot[g])
		if n < 0 or sim.good(g).is_empty():
			return {"ok": false, "reason": "모르는 상품이거나 음수: %s" % g, "code": "loot"}
		total += n
	# 재고·배낭 한도를 넘는 것은 거절하지 않고 run_result가 잘라 낸다(잘린 몫은 결과의 lost) — 결과가 팀을 묶어 두면 안 된다(통합 보고)
	return {"ok": true, "reason": "", "code": "ok", "carry_cap": carry}


func _run_result(state: CityState, args: Dictionary) -> Dictionary:
	var run: Dictionary = state.flags["run"]
	var id := str(args["dest"])
	var d := _dest(id)
	var outcome := str(args["outcome"])
	var loot: Dictionary = _alias_loot(args.get("loot", {}))
	var got := {}
	var lost: Array = []
	# loot = 미니게임 결과 화면의 "들고 나온 것"(쓰러졌을 때의 절반 잃음·두목의 큰 짐은 미니게임이 이미 반영했다 — 도시는 더 깎거나 얹지 않는다).
	# 잃은 것은 결과의 lost{good:n}(선택)로 받아 알림에만 쓴다.
	var cap_left := int(_run_conf(d).get("carry", 40))
	var st0: Dictionary = state.dests.get(id, {}).get("stock", {})
	var clipped := {}
	for g: String in _run_order(loot):
		var n := float(int(loot[g]))
		var ok_n := n
		if not st0.has(g):
			ok_n = 0.0                          # 이 던전에 없는 물건
		else:
			ok_n = minf(ok_n, floorf(float(st0[g]) + 1e-6))
		ok_n = minf(ok_n, float(maxi(0, cap_left)))
		if ok_n < n:
			clipped[g] = int(n - ok_n)
		cap_left -= int(ok_n)
		if ok_n > 0.0:
			_take(state, id, g, ok_n)
			got[g] = ok_n
	for g: String in clipped:
		lost.append({"good": g, "name": sim.gname(g), "n": int(clipped[g]), "why": "한도"})
	var lv: Variant = args.get("lost", {})
	if lv is Dictionary:
		var la := _alias_loot(lv)
		for g: String in la:
			if int(la[g]) > 0 and not sim.good(g).is_empty():
				lost.append({"good": g, "name": sim.gname(g), "n": int(la[g])})
	if outcome == "boss":
		var bonus: Dictionary = _run_conf(d).get("boss", {})
		for g: String in bonus:
			got[g] = float(got.get(g, 0.0)) + float(bonus[g])
	var total := {}
	_deposit(state, got, total)
	var allowed := {}
	for f: Dictionary in d.get("finds", []):
		allowed["%s:%s" % [f["type"], f["id"]]] = true
	for r: String in d.get("reveals", []):
		allowed["dest:" + r] = true
	var texts: Array = []
	for s: Variant in args.get("finds", []):
		var key := str(s)
		if not allowed.has(key):
			if not key.contains(":") or key.contains(" "):
				sim.say(state, Sim.kr("%s에서: %s" % [_dname(id), key]))     # 미니게임의 발견 문장은 성채 소식으로만
			continue
		var parts := key.split(":", true, 1)
		var ft := _apply_find(state, {"type": parts[0], "id": parts[1]})
		if ft != "":
			texts.append(ft)
	if (state.dests[id].get("runs", 0) as int) == 0:
		for r: String in d.get("reveals", []):
			var ft := reveal(state, r)
			if ft != "":
				texts.append(ft)
	state.dests[id]["runs"] = int(state.dests[id].get("runs", 0)) + 1
	var t := _team(state, int(run.get("team", -1)))
	if not t.is_empty():
		t["state"] = "idle"
		t["dest"] = ""
	state.flags["run"] = {}
	state.stat_add("run_" + outcome, 1.0)
	_drop_retired(state)
	var word: String = {"boss": "두목을 쓰러뜨리고", "exit": "중간에 빠져나와", "down": "쓰러져 실려 나와"}[outcome]
	sim.say(state, "%s에서 %s 짐을 풀었다: %s." % [_dname(id), word, _reward_text(got) if not got.is_empty() else "빈손"], "good" if outcome != "down" else "warn")
	for s: String in texts:
		sim.say(state, s, "good")
	return {"ok": true, "reason": "", "rewards": _reward_lines(got), "finds": texts, "lost": lost}


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
	if name == "run_wanted":
		var dd := str(_args.get("dest", ""))
		return _run_wanted(state, str(DEST_ALIAS.get(dd, dd)))
	if name != "expeditions":
		return null
	_sync(state)
	_update(state)
	var spd := _sec_per_day()
	var teams: Array = []
	for t: Dictionary in state.teams:
		var total := maxf(0.0, float(t.get("completes_at", 0.0)) - float(t.get("started_at", 0.0)))
		var left := 0.0
		if t["state"] == "out":
			left = clampf(float(t["completes_at"]) - state.econ_days, 0.0, total)
		teams.append({"id": int(t["id"]), "name": "탐험대 %d" % int(t["id"]), "state": t["state"], "state_name": STATE_NAME.get(t["state"], ""),
			"dest": t["dest"], "dest_name": _dname(str(t["dest"])) if str(t["dest"]) != "" else "",
			"days_left": snappedf(left, 0.001), "total_days": snappedf(total, 0.001),
			"seconds_left": int(roundf(left * spd)), "total_seconds": int(roundf(total * spd)),
			"reward_text": _reward_text(t["reward"]) if t["state"] == "done" else ("" if t["state"] == "idle" else ("직접 줍는 중" if t["state"] == "run" else "돌아오는 중")),
			"rewards": _reward_lines(t["reward"]) if t["state"] == "done" else [], "provision": bool(t.get("provision", false)),
			"retired": bool(t.get("retired", false))})
	var dests: Array = []
	var mats: Array = sim.db.get("upgrade_costs", {}).get("materials", [])
	var can_run := (state.flags.get("run", {}) as Dictionary).is_empty() and not _idle_team(state).is_empty()
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
				bon.append("도면(첫 방문)" if not f.get("run_only", false) else "도면(직접 줍기)")
		var k := 1.0 if pg == "parts" else mult
		var days := _days(state, d)
		var pct := _stock_pct(state, id)
		var rc := _run_conf(d)
		var danger := int(rc.get("danger", d.get("danger", 1)))
		var known := bool(st.get("known", false))
		dests.append({"id": id, "name": d.get("name", id), "desc": d.get("desc", ""), "map": d.get("map", [0.5, 0.5]), "band": d.get("band", "near"),
			"days": snappedf(days, 0.001), "total_days": snappedf(days, 0.001), "seconds": int(roundf(days * spd)),
			"primary": {"good": pg, "name": sim.gname(pg) if pg != "" else "고른 자재", "min": int(roundf(float(pr.get("min", 0)) * k)), "max": int(roundf(float(pr.get("max", 0)) * k))},
			"picks": picks, "bonus_text": "덤: " + ", ".join(bon) if not bon.is_empty() else "", "cost": {"money": _cost(state, d)},
			"known": known, "locked_hint": "" if known else str(d.get("reveal_hint", "탐험으로 알게 된다")),
			"visits": int(st.get("visits", 0)), "new": bool(st.get("new", false)),
			"stock_pct": snappedf(pct, 0.01),
			"stock_text": "털 것이 %d%% 남았다" % int(roundf(pct * 100.0)),
			"run": {"available": known and can_run, "danger": danger,
				"text": "위험 %d · 배낭 %d칸 · 두목을 잡으면 덤" % [danger, int(rc.get("carry", 40))] if known else "아직 모르는 곳"},
			"per_day": snappedf((float(pr.get("min", 0)) + float(pr.get("max", 0))) * 0.5 * k / maxf(days, 1e-6), 0.1),
			"per_hour": snappedf((float(pr.get("min", 0)) + float(pr.get("max", 0))) * 0.5 * k / maxf(days * spd / 3600.0, 1e-6), 0.1)})
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
		"materials": mat_rows, "now_unix": 0, "econ_days": state.econ_days, "run": state.flags.get("run", {})}


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
