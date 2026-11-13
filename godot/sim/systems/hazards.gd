extends SimSystem
## hazards — 불과 병(GDD_PC §3.1). config hazards.fire / hazards.disease. 세 자재 계열의 차이는 없다(확정: 세 계열 동등).
##
##  불: 2층이 열리면 켜진다(hazard_on{kind:"fire", grace_days}) — 유예(grace_days) 동안은 위험이 쌓이지 않는다.
##   쓰이는 건물(주민 있는 주거·완공 시설)마다 위험 fire_risk(0..1)가 쌓인다: 소방 범위 밖이면 risk_per_day, 안이면 그 × covered_mult.
##   한 경제시간마다 결정론 RNG: 위험 합 × ignite_per_day × dt 확률로 한 곳(위험 비례)에 불이 난다
##   (동시에 타는 곳은 max_burning + 건물 수/burning_per 이하, 불 사이 min_gap_days — 도시를 통째로 태우지 않는다).
##   타는 곳: 소방 범위 안이면 out_days(약 1시간) 만에 꺼지고 피해는 주민 1명이 흩어지는 것뿐.
##   범위 밖이면 burn_days 동안 타며 매시간 spread_per_day 확률로 옆 칸·위 칸(범위 밖인 것만)으로 번지고, 끝나면 "탐"(burnt):
##   주거의 주민은 흩어져(대기 주민 → 3일 안에 빈집을 찾거나 떠남) 아무도 못 살고, 시설은 멈춘다. 수리 repair{bid}(돈·고물·날짜).
##  병: 3층이 열리면 켜진다. 주거마다 쓰레기 trash(0..1)가 주민 비율만큼 쌓이고 넝마주이 조합 범위 안이면 치워진다.
##   한 경제시간마다 trash ≥ outbreak_at인 주거들에서 결정론 RNG로 발병 — 그 집과 이웃(가로·세로 1칸, 위아래 1층)의 쓰레기 많은 집이 앓는다.
##   앓는 집: 일손 절반(workforce), 행복 −sick_happy, 새로 들어오지 않음, leave_after일이 지나면 주민이 leave_per_day씩 떠난다.
##   sick_days 뒤 낫는다 — 무면허 의원 범위 안이면 clinic_days. 동시에 앓는 집은 상한(max_sick_frac).
##  표시: 셀 burn/sick/trash, 건물 burn/sick/sick_until/repair, 질의 hazards·coverage, hud.hazards·signals(alerts가 붙임), 알림(jump focus·lens).
##  디버그: start_fire{pos}, start_outbreak{pos}, set_hazard{kind, on}.
## 끄면: 불도 병도 없다(질의는 off 모양).

const TAGS := {"fire": "fire", "trash": "trash", "clinic": "clinic"}


func _f(k: String, d: float) -> float:
	return float(sim.cfg("hazards.fire." + k, d))


func _s(k: String, d: float) -> float:
	return float(sim.cfg("hazards.disease." + k, d))


func _hz(state: CityState) -> Dictionary:
	if not state.flags.has("hz"):
		state.flags["hz"] = {"fire": {"on": false, "since": -1.0, "last": -99.0}, "disease": {"on": false, "since": -1.0, "last": -99.0}, "forced": {}}
	return state.flags["hz"]


func _bump(state: CityState) -> void:
	state.flags["hz_rev"] = int(state.flags.get("hz_rev", 0)) + 1


# ------------------------------------------------------------------ 켜기
func _switch(state: CityState) -> void:
	var hz := _hz(state)
	var forced: Dictionary = hz.get("forced", {})
	for kind: String in ["fire", "disease"]:
		var want := state.floors_unlocked >= int(sim.cfg("hazards.%s.floor" % kind, 2 if kind == "fire" else 3))
		if forced.has(kind):
			want = bool(forced[kind])
		var h: Dictionary = hz[kind]
		if want and not bool(h["on"]):
			h["on"] = true
			var grace := float(sim.cfg("hazards.%s.grace_days" % kind, 2.0)) if not forced.has(kind) else 0.0
			h["since"] = state.econ_days + grace
			if bool(h.get("announced", false)):
				continue
			h["announced"] = true       # 도시마다 한 번만(저장에 남는다 — 불러와도, 디버그로 껐다 켜도 다시 알리지 않는다)
			state.emit("hazard_on", {"kind": kind, "grace_days": grace})
			state.stats["hazard_%s_on_day" % kind] = state.econ_days
			if kind == "fire":
				sim.say(state, "2층이 열렸다. 판자와 전선이 겹겹이 쌓이면 불이 난다 — %s 뒤부터. 양동이 소방대 범위(위아래 한 층까지)로 쓰이는 칸을 덮자." % Queries.day_text(grace), "warn")
			else:
				sim.say(state, "3층이 열렸다. 사람이 쌓이면 쓰레기도 쌓이고, 쓰레기는 병을 부른다 — %s 뒤부터. 넝마주이 조합과 무면허 의원을 세우자." % Queries.day_text(grace), "warn")
		elif not want and bool(h["on"]):
			h["on"] = false


func on_command(state: CityState, _name: String, _args: Dictionary, _result: Dictionary) -> void:
	_switch(state)


# ------------------------------------------------------------------ 틱
func tick(state: CityState, dt: float) -> void:
	_switch(state)
	var hz := _hz(state)
	var cov := sim.cover(state)
	var fire: Dictionary = hz["fire"]
	var dis: Dictionary = hz["disease"]
	# 수리 진행(불이 꺼져 있어도) — 수리 중인 건물 목록만 본다
	var reps: Dictionary = hz.get("repairs", {})     # {bid: true} — 정수 키는 저장 왕복에도 정수로 돌아온다
	if not reps.is_empty():
		for bid: int in reps.keys():
			var b: Dictionary = state.buildings.get(bid, {})
			var rp: Variant = b.get("repair")
			if not (rp is Dictionary):
				reps.erase(bid)
			elif state.econ_days + 1e-9 >= float(rp["done_at"]):
				reps.erase(bid)
				_repaired(state, b)
	if not sim.every(state, 2, dt):
		return
	# 손실 장부(주거-일, 한 경제시간마다): 탄·타는 주거, 앓는 주거(절반으로 셈)
	var dth := sim.step_days * 2.0
	var nh := 0
	var nb := 0
	var ns := 0
	for b: Dictionary in cov["houses"]:
		nh += 1
		if str(b.get("burn", "")) != "":
			nb += 1
		if b.get("sick", false):
			ns += 1
	state.stat_add("house_days", float(nh) * dth)
	if nb > 0:
		state.stat_add("hz_fire_house_days", float(nb) * dth)
	if ns > 0:
		state.stat_add("hz_sick_house_days", float(ns) * dth * 0.5)
	if bool(fire["on"]):
		_fire_tick(state, cov, fire, dth)
	if bool(dis["on"]):
		_disease_tick(state, cov, dis, dth)
	elif ns > 0:
		for b: Dictionary in cov["houses"]:
			if b.get("sick", false):
				_heal(state, b)


func _covered(state: CityState, cov: Dictionary, tag: String, bid: int) -> bool:
	var lst: Variant = cov["hz"].get(tag, {}).get(bid)
	if lst == null:
		return false
	for fb: int in lst:
		var f: Dictionary = state.buildings.get(fb, {})
		if f.get("active", false):
			return true
	return false


func _used(b: Dictionary) -> bool:
	if b["kind"] == "house":
		return int(b["residents"]) > 0
	return b["kind"] == "facility"


# ------------------------------------------------------------------ 불
func _fire_tick(state: CityState, cov: Dictionary, fire: Dictionary, dt: float) -> void:
	var active := state.econ_days + 1e-9 >= float(fire["since"])
	var burning: Array = []
	var cands: Array = []
	var weights: Array = []
	var total := 0.0
	var n_used := 0
	var rate := _f("risk_per_day", 0.35)
	var cm := _f("covered_mult", 0.1)
	for b: Dictionary in cov["all"]:
		var bn := str(b.get("burn", ""))
		if bn == "burning":
			burning.append(b)
			continue
		if bn != "" or not _used(b):
			continue
		n_used += 1
		if not active:
			continue
		var c := _covered(state, cov, "fire", int(b["id"]))
		var r := minf(1.0, float(b.get("fire_risk", 0.0)) + rate * dt * (cm if c else 1.0))
		b["fire_risk"] = r
		if r > 0.0:
			cands.append(b)
			weights.append(r)
			total += r
	# 타는 곳: 꺼지거나 번지거나 탄다
	for b: Dictionary in burning:
		var c := _covered(state, cov, "fire", int(b["id"]))
		var left := float(b.get("fire_left", 0.0))
		if c:
			left = minf(left, _f("out_days", 0.04))
		left -= dt
		b["fire_left"] = left
		if not c and burning.size() < _max_burning(n_used):
			for nb: Dictionary in _neighbours(state, b):
				if burning.size() >= _max_burning(n_used):
					break
				if str(nb.get("burn", "")) != "" or not _used(nb) or _covered(state, cov, "fire", int(nb["id"])):
					continue
				if sim.roll(state) < _f("spread_per_day", 2.0) * dt:
					_ignite(state, cov, nb, true)
					burning.append(nb)
		if left <= 0.0:
			_burn_out(state, b, c)
	if not active:
		return
	if burning.size() >= _max_burning(n_used) or state.econ_days - float(fire.get("last", -99.0)) < _f("min_gap_days", 0.15):
		return
	var p := minf(0.5, total * _f("ignite_per_day", 0.05) * dt)
	if p <= 0.0 or sim.roll(state) >= p:
		return
	var x := sim.roll(state) * total
	for i: int in cands.size():
		x -= float(weights[i])
		if x < 0.0 or i == cands.size() - 1:
			_ignite(state, cov, cands[i], false)
			fire["last"] = state.econ_days
			break


func _max_burning(n_used: int) -> int:
	return int(_f("max_burning", 2)) + n_used / maxi(1, int(_f("burning_per", 150)))


func _ignite(state: CityState, cov: Dictionary, b: Dictionary, spread: bool) -> void:
	var c := _covered(state, cov, "fire", int(b["id"]))
	b["burn"] = "burning"
	b["fire_risk"] = 0.0
	b["fire_left"] = _f("out_days", 0.04) if c else _f("burn_days", 0.3)
	_cells_set(state, b, "burn", "burning")
	_bump(state)
	state.stat_add("fires", 1.0)
	if not state.stats.has("first_fire_day"):
		state.stats["first_fire_day"] = state.econ_days
	var pos: Vector3i = b["pos"]
	state.emit("fire_spread" if spread else "fire_started", {"bid": int(b["id"]), "pos": pos})
	state.emit("building_changed", {"bid": int(b["id"])})
	var nm := _bname(b)
	if spread:
		sim.say(state, "불이 %s(으)로 번졌다(%d층). 소방 범위 밖이다." % [nm, pos.z + 1], "bad")
	elif c:
		sim.say(state, "%s에서 불이 났다(%d층). 양동이 줄이 벌써 서 있다." % [nm, pos.z + 1], "warn")
	else:
		sim.say(state, "%s에서 불이 났다(%d층). 소방 범위 밖이라 아무도 오지 않는다." % [nm, pos.z + 1], "bad")


func _burn_out(state: CityState, b: Dictionary, covered: bool) -> void:
	b.erase("fire_left")
	var pos: Vector3i = b["pos"]
	if covered:
		b["burn"] = ""
		_cells_set(state, b, "burn", "")
		if b["kind"] == "house" and int(b["residents"]) > 0:
			_scatter(state, b, 1)
		sim.say(state, "%s의 불을 껐다. 그을음만 남았다." % _bname(b))
		state.emit("fire_out", {"bid": int(b["id"]), "pos": pos, "burnt": false})
	else:
		b["burn"] = "burnt"
		_cells_set(state, b, "burn", "burnt")
		state.stat_add("burnt", 1.0)
		var lost := 0
		if b["kind"] == "house":
			lost = int(b["residents"])
			# 집을 잃은 주민 중 burn_leave_frac은 성채를 떠나고 나머지만 빈집을 찾는다(대기 주민)
			var gone := int(floorf(float(lost) * _f("burn_leave_frac", 0.5) + 0.5))
			if gone > 0:
				b["residents"] = int(b["residents"]) - gone
				state.stat_add("left", float(gone))
				state.stat_add("left_fire", float(gone))
			_scatter(state, b, lost - gone)
			b["grow"] = 0.0
			b["arriving"] = 0.0
			b["upgradable"] = false
			b["ready"] = false
		sim.say(state, "%s이(가) 다 탔다%s. 수리해야 다시 쓴다." % [_bname(b), (" — 주민 %d명이 흩어졌다" % lost) if lost > 0 else ""], "bad")
		state.emit("fire_out", {"bid": int(b["id"]), "pos": pos, "burnt": true})
	_bump(state)
	state.emit("building_changed", {"bid": int(b["id"])})


## 주민 n명이 흩어진다 — 같은 계층 대기 주민이 되어 빈집을 찾는다(3일 안에 못 찾으면 떠난다). 인구는 조용히 사라지지 않는다.
func _scatter(state: CityState, b: Dictionary, n: int) -> void:
	n = mini(n, int(b["residents"]))
	if n <= 0:
		return
	b["residents"] = int(b["residents"]) - n
	var t := int(b["tier"])
	var w: Dictionary = state.waiting.get(t, {"count": 0, "days_left": 0.0})
	w["count"] = int(w["count"]) + n
	w["days_left"] = maxf(float(w.get("days_left", 0.0)), float(sim.cfg("upgrade.waiting_days", 3)))
	state.waiting[t] = w
	state.stat_add("scattered", float(n))


func _neighbours(state: CityState, b: Dictionary) -> Array:
	var out: Array = []
	var seen := {int(b["id"]): true}
	for p: Vector3i in Cover.bcells(b):
		for dv: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1)]:
			var q := p + dv
			if not state.cells.has(q):
				continue
			var nb := int(state.cells[q]["bid"])
			if seen.has(nb):
				continue
			seen[nb] = true
			var o: Dictionary = state.buildings.get(nb, {})
			if o.get("kind", "") == "house" or o.get("kind", "") == "facility":
				out.append(o)
	return out


func _bname(b: Dictionary) -> String:
	if b["kind"] == "house":
		return "%s의 집" % sim.tname(int(b["tier"]))
	return str(sim.bdef(str(b["type"])).get("name", b["type"]))


func _cells_set(state: CityState, b: Dictionary, key: String, v: Variant) -> void:
	for p: Vector3i in Cover.bcells(b):
		if state.cells.has(p) and state.cells[p].get(key) != v:
			state.cells[p][key] = v
			state.emit("cell_changed", {"pos": p})


# ------------------------------------------------------------------ 수리
func _repair_cost(b: Dictionary) -> Dictionary:
	var money := 0.0
	var cells := Cover.bcells(b).size()
	if b["kind"] == "house":
		var tab: Array = sim.cfg("hazards.repair.house_money", [20, 60, 150, 400, 900])
		money = float(tab[clampi(int(b["tier"]) - 1, 0, tab.size() - 1)])
	else:
		money = roundf(float(sim.bdef(str(b["type"])).get("cost", {}).get("money", 0)) * float(sim.cfg("hazards.repair.facility_frac", 0.4)))
	var scrap := float(sim.cfg("hazards.repair.scrap_per_cell", 3)) * float(cells)
	var goods := {"scrap": scrap}
	# 승급한 집은 그 계층으로 올릴 때 쓴 자재의 mat_frac만큼(집의 자재 계열로) 다시 든다
	if b["kind"] == "house" and int(b["tier"]) >= 2 and str(b.get("material", "")) != "":
		var up: Dictionary = sim.db.get("upgrade_costs", {}).get("items", {}).get("%dto%d" % [int(b["tier"]) - 1, int(b["tier"])], {})
		var q := ceilf(float(up.get("qty", 0)) * float(sim.cfg("hazards.repair.mat_frac", 0.5)))
		if q > 0.0:
			goods[str(b["material"])] = q
	var days := float(sim.cfg("hazards.repair.days", 0.25)) if b["kind"] == "house" else float(sim.cfg("hazards.repair.facility_days", sim.cfg("hazards.repair.days", 0.25)))
	return {"money": money, "goods": goods, "days": days}


func can(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "repair":
		return null
	var b: Dictionary = state.buildings.get(int(args.get("bid", -1)), {})
	if b.is_empty():
		return {"ok": false, "reason": "그런 건물이 없다.", "code": "state"}
	if str(b.get("burn", "")) != "burnt":
		return {"ok": false, "reason": "탄 건물이 아니다.", "code": "state"}
	if b.get("repair") != null:
		return {"ok": false, "reason": "이미 수리 중이다.", "code": "busy"}
	var c := _repair_cost(b)
	if state.money + 1e-9 < float(c["money"]):
		return {"ok": false, "reason": "수리비 %s이(가) 모자란다." % Sim.won(float(c["money"])), "code": "money", "cost": c}
	for g: String in c["goods"]:
		if float(state.stock.get(g, 0.0)) + 1e-9 < float(c["goods"][g]):
			return {"ok": false, "reason": "%s %d이(가) 모자란다(지금 %d)." % [sim.gname(g), int(c["goods"][g]), int(state.stock.get(g, 0.0))], "code": "goods", "cost": c}
	return {"ok": true, "reason": "", "code": "ok", "cost": c, "days": c["days"]}


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"repair":
			var b: Dictionary = state.buildings[int(args["bid"])]
			var c := _repair_cost(b)
			state.money -= float(c["money"])
			state.book("build", -float(c["money"]))
			state.stat_add("spent_repair", float(c["money"]))
			for g: String in c["goods"]:
				state.stock[g] = float(state.stock.get(g, 0.0)) - float(c["goods"][g])
				state.stat_add("used." + g, float(c["goods"][g]))
			b["repair"] = {"money": c["money"], "goods": c["goods"], "days": c["days"], "done_at": state.econ_days + float(c["days"])}
			var hz := _hz(state)
			if not hz.has("repairs"):
				hz["repairs"] = {}
			hz["repairs"][int(b["id"])] = true
			_bump(state)
			state.emit("building_changed", {"bid": int(b["id"])})
			sim.say(state, "%s 수리를 시작했다(%s, %s)." % [_bname(b), Sim.won(float(c["money"])), Queries.day_text(float(c["days"]))])
			return {"ok": true, "reason": "", "bid": int(b["id"]), "days": c["days"]}
	return null


func _repaired(state: CityState, b: Dictionary) -> void:
	b["repair"] = null
	b["burn"] = ""
	b["fire_risk"] = 0.0
	_cells_set(state, b, "burn", "")
	_bump(state)
	state.emit("repaired", {"bid": int(b["id"])})
	state.emit("building_changed", {"bid": int(b["id"])})
	sim.say(state, "%s 수리가 끝났다." % _bname(b), "good")


# ------------------------------------------------------------------ 병
func _disease_tick(state: CityState, cov: Dictionary, dis: Dictionary, dt: float) -> void:
	var active := state.econ_days + 1e-9 >= float(dis["since"])
	var per := _s("trash_per_day", 0.35)
	var clear := _s("clear_per_day", 2.0)
	var at := _s("outbreak_at", 0.7)
	var cm := _s("covered_mult", 0.1)
	var ccap := _s("covered_cap", 0.5)
	var cw := _s("covered_weight", 0.05)
	var cands: Array = []
	var weights: Array = []
	var total := 0.0
	var n_sick := 0
	var nh := 0
	for b: Dictionary in cov["houses"]:
		nh += 1
		var tr := float(b.get("trash", 0.0))
		var res := int(b["residents"])
		var tc := _covered(state, cov, "trash", int(b["id"]))
		if tc:
			# 수거 범위 안: 새로 덮이면 먼저 싹 치우고(tclean), 그 뒤로는 넝마주이가 다 못 따라간 몫이 covered_mult만큼 천천히 쌓여 covered_cap에서 멈춘다
			if not b.get("tcov", false):
				b["tcov"] = true
				b["tclean"] = true
			if b.get("tclean", false):
				tr = maxf(0.0, tr - clear * dt)
				if tr <= 0.0:
					b.erase("tclean")
			elif tr > ccap:
				tr = maxf(ccap, tr - clear * dt)
			elif active and res > 0:
				tr = minf(ccap, tr + per * cm * dt * float(res) / maxf(1.0, float(b["cap"])))
		else:
			if b.get("tcov", false):
				b.erase("tcov")
				b.erase("tclean")
			if active and res > 0:
				tr = minf(1.0, tr + per * dt * float(res) / maxf(1.0, float(b["cap"])))
		if tr != float(b.get("trash", 0.0)):
			b["trash"] = tr
			var shown := snappedf(tr, 0.1)
			var cl: Dictionary = state.cells.get(b["pos"], {})
			if not cl.is_empty() and float(cl.get("trash", 0.0)) != shown:
				cl["trash"] = shown
				state.emit("cell_changed", {"pos": b["pos"]})
		if b.get("sick", false):
			n_sick += 1
			_sick_tick(state, cov, b, dt)
			continue
		if active and res > 0:
			var w := 0.0
			if tr >= at:
				w = (tr - at) / maxf(1e-6, 1.0 - at) + 0.1
			elif tc and tr >= ccap - 1e-6:
				w = cw      # 범위 안이어도 오래 쌓이면 가끔 작은 병(의원 범위면 금방 낫고, 나으면 넝마주이가 싹 치운다)
			if w > 0.0:
				cands.append(b)
				weights.append(w)
				total += w
	if not active or cands.is_empty():
		return
	var cap := maxi(int(_s("max_sick_min", 6)), int(float(nh) * _s("max_sick_frac", 0.08)))
	if n_sick >= cap or state.econ_days - float(dis.get("last", -99.0)) < _s("min_gap_days", 0.2):
		return
	var p := minf(0.5, total * _s("outbreak_per_day", 0.08) * dt)
	if sim.roll(state) >= p:
		return
	var x := sim.roll(state) * total
	for i: int in cands.size():
		x -= float(weights[i])
		if x < 0.0 or i == cands.size() - 1:
			_outbreak(state, cov, cands[i], cap - n_sick)
			dis["last"] = state.econ_days
			break


func _outbreak(state: CityState, cov: Dictionary, b: Dictionary, room: int) -> void:
	var o: Vector3i = b["pos"]
	var group: Array = [b]
	for h: Dictionary in cov["houses"]:
		if group.size() >= mini(room, int(_s("cluster_max", 6))):
			break
		if h == b or h.get("sick", false) or int(h["residents"]) == 0:
			continue
		var p: Vector3i = h["pos"]
		if absi(p.x - o.x) <= 1 and absi(p.y - o.y) <= 1 and absi(p.z - o.z) <= 1 and float(h.get("trash", 0.0)) >= _s("cluster_trash", 0.4):
			group.append(h)
	var bids: Array = []
	for h: Dictionary in group:
		var c := _covered(state, cov, "clinic", int(h["id"]))
		h["sick"] = true
		h["sick_since"] = state.econ_days
		h["sick_until"] = state.econ_days + (_s("clinic_days", 0.6) if c else _s("sick_days", 2.5))
		_cells_set(state, h, "sick", true)
		bids.append(int(h["id"]))
		state.emit("building_changed", {"bid": int(h["id"])})
	_bump(state)
	state.stat_add("outbreaks", 1.0)
	state.stat_add("sick_houses", float(bids.size()))
	if not state.stats.has("first_outbreak_day"):
		state.stats["first_outbreak_day"] = state.econ_days
	state.emit("outbreak", {"bids": bids, "pos": o})
	sim.say(state, "%d층 쓰레기 더미 옆에서 병이 돈다. 주거 %d채가 앓는다%s." % [o.z + 1, bids.size(),
		"" if _covered(state, cov, "clinic", int(b["id"])) else " — 의원 범위 밖이라 오래 간다"], "bad")


func _sick_tick(state: CityState, cov: Dictionary, b: Dictionary, dt: float) -> void:
	if _covered(state, cov, "clinic", int(b["id"])):
		b["sick_until"] = minf(float(b["sick_until"]), state.econ_days + _s("clinic_days", 0.6))
	if state.econ_days + 1e-9 >= float(b["sick_until"]):
		_heal(state, b, _covered(state, cov, "trash", int(b["id"])))
		return
	if state.econ_days - float(b.get("sick_since", state.econ_days)) >= _s("leave_after", 1.0) and int(b["residents"]) > 0:
		b["sick_leave"] = float(b.get("sick_leave", 0.0)) + _s("leave_per_day", 2.0) * dt
		while float(b["sick_leave"]) >= 1.0 and int(b["residents"]) > 0:
			b["residents"] = int(b["residents"]) - 1
			b["sick_leave"] = float(b["sick_leave"]) - 1.0
			state.stat_add("left", 1.0)
			state.stat_add("left_sick", 1.0)
			state.emit("building_changed", {"bid": int(b["id"])})


func _heal(state: CityState, b: Dictionary, cleared: bool = false) -> void:
	b["sick"] = false
	b.erase("sick_until")
	b.erase("sick_since")
	b.erase("sick_leave")
	b["trash"] = 0.0 if cleared else minf(float(b.get("trash", 0.0)), 0.3)
	_cells_set(state, b, "sick", false)
	_cells_set(state, b, "trash", snappedf(float(b["trash"]), 0.1))
	_bump(state)
	state.emit("outbreak_end", {"bids": [int(b["id"])]})
	state.emit("building_changed", {"bid": int(b["id"])})


# ------------------------------------------------------------------ 디버그(Debug.gd가 부른다)
func debug(state: CityState, args: Dictionary) -> Dictionary:
	var cov := sim.cover(state)
	match str(args.get("op", "")):
		"start_fire", "start_outbreak":
			var pos: Variant = args.get("pos", null)
			if pos == null:     # 자리를 안 주면 주민 있는 주거 하나를 결정론 RNG로
				var cand: Array = []
				for h: Dictionary in cov["houses"]:
					if int(h["residents"]) > 0 and str(h.get("burn", "")) == "" and not h.get("sick", false):
						cand.append(h)
				if cand.is_empty():
					return {"ok": false, "reason": "불·병을 낼 주거가 없다."}
				pos = cand[int(sim.roll(state) * cand.size()) % cand.size()]["pos"]
			if not (pos is Vector3i) or not state.cells.has(pos):
				return {"ok": false, "reason": "그 칸에 건물이 없다."}
			var b: Dictionary = state.buildings.get(int(state.cells[pos]["bid"]), {})
			if str(args["op"]) == "start_fire":
				if b.get("kind", "") == "site" or str(b.get("burn", "")) != "":
					return {"ok": false, "reason": "불을 낼 수 없는 건물이다."}
				_ignite(state, cov, b, false)
			else:
				if b.get("kind", "") != "house":
					return {"ok": false, "reason": "주거만 앓는다."}
				b["trash"] = 1.0
				_outbreak(state, cov, b, 99)
			return {"ok": true, "reason": ""}
		"set_hazard":
			var kind := str(args.get("kind", ""))
			if not (kind in ["fire", "disease"]):
				return {"ok": false, "reason": "kind는 fire 또는 disease."}
			_hz(state)["forced"][kind] = bool(args.get("on", true))
			_switch(state)
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "모르는 디버그 명령."}


# ------------------------------------------------------------------ 질의
func _pct(state: CityState, cov: Dictionary, tag: String, houses_only: bool) -> float:
	var n := 0
	var c := 0
	for b: Dictionary in (cov["houses"] if houses_only else cov["all"]):
		if not _used(b):
			continue
		n += 1
		if _covered(state, cov, tag, int(b["id"])):
			c += 1
	return 1.0 if n == 0 else float(c) / float(n)


func query(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"hazards":
			return _hazards_q(state)
		"coverage":
			return _coverage_q(state, str(args.get("kind", "fire")))
	return null


var _q_key := ""
var _q_val: Dictionary = {}


func _hazards_q(state: CityState) -> Dictionary:
	var key := "%d:%d:%d:%d:%d" % [state.get_instance_id(), roundi(state.econ_days / sim.step_days), int(state.flags.get("hz_rev", 0)), state.layout_rev(), state.next_id]
	if key == _q_key and not sim.no_cache:
		return _q_val.duplicate(true)
	_q_val = _hazards_q_raw(state)
	_q_key = key
	return _q_val.duplicate(true)


func _hazards_q_raw(state: CityState) -> Dictionary:
	var hz := _hz(state)
	var cov := sim.cover(state)
	var burning: Array = []
	var burnt: Array = []
	var sick: Array = []
	var trash_hi := 0
	var nh := 0
	var at := _s("outbreak_at", 0.7)
	var n_all := 0
	var c_fire := 0
	var n_h := 0
	var c_trash := 0
	var c_clinic := 0
	for b: Dictionary in cov["all"]:
		var bn := str(b.get("burn", ""))
		var bid := int(b["id"])
		if bn == "burning":
			burning.append({"bid": bid, "pos": b["pos"]})
		elif bn == "burnt":
			var c := _repair_cost(b)
			burnt.append({"bid": bid, "pos": b["pos"], "repairing": b.get("repair") != null,
				"repair_text": "수리 중" if b.get("repair") != null else "수리 %s + %s · %s" % [Sim.won(float(c["money"])), _goods_text(c["goods"]), Queries.day_text(float(c["days"]))]})
		var used := _used(b)
		if used:
			n_all += 1
			if _covered(state, cov, "fire", bid):
				c_fire += 1
		if b["kind"] == "house":
			nh += 1
			if float(b.get("trash", 0.0)) >= at:
				trash_hi += 1
			if b.get("sick", false):
				sick.append({"bid": bid, "pos": b["pos"], "days_left": snappedf(maxf(0.0, float(b.get("sick_until", 0.0)) - state.econ_days), 0.01)})
			if used:
				n_h += 1
				if _covered(state, cov, "trash", bid):
					c_trash += 1
				if _covered(state, cov, "clinic", bid):
					c_clinic += 1
	var fpct := 1.0 if n_all == 0 else float(c_fire) / float(n_all)
	var tpct := 1.0 if n_h == 0 else float(c_trash) / float(n_h)
	var cpct := 1.0 if n_h == 0 else float(c_clinic) / float(n_h)
	var f: Dictionary = hz["fire"]
	var d: Dictionary = hz["disease"]
	var fgrace := maxf(0.0, float(f["since"]) - state.econ_days) if bool(f["on"]) else 0.0
	var dgrace := maxf(0.0, float(d["since"]) - state.econ_days) if bool(d["on"]) else 0.0
	var ft := "2층이 열리면 불이 나기 시작한다."
	if bool(f["on"]):
		ft = "소방 범위가 쓰이는 칸의 %d%%를 덮는다." % int(roundf(fpct * 100.0))
		if fgrace > 0.0:
			ft = "%s 뒤부터 불이 난다. " % Queries.day_text(fgrace) + ft
		if not burning.is_empty():
			ft += " 지금 %d곳이 탄다." % burning.size()
		if not burnt.is_empty():
			ft += " 탄 건물 %d — 수리하자." % burnt.size()
	var dt := "3층이 열리면 쓰레기와 병이 생긴다."
	if bool(d["on"]):
		dt = "넝마주이 조합이 주거의 %d%%, 의원이 %d%%를 덮는다." % [int(roundf(tpct * 100.0)), int(roundf(cpct * 100.0))]
		if dgrace > 0.0:
			dt = "%s 뒤부터 병이 돈다. " % Queries.day_text(dgrace) + dt
		if not sick.is_empty():
			dt += " 앓는 집 %d채." % sick.size()
	return {"fire": {"on": bool(f["on"]), "since_day": float(state.stats.get("hazard_fire_on_day", -1.0)), "grace_left": snappedf(fgrace, 0.01),
			"covered_pct": snappedf(fpct, 0.01), "burning": burning, "burnt": burnt, "text": ft},
		"disease": {"on": bool(d["on"]), "since_day": float(state.stats.get("hazard_disease_on_day", -1.0)), "grace_left": snappedf(dgrace, 0.01),
			"covered_pct": snappedf(cpct, 0.01), "trash_covered_pct": snappedf(tpct, 0.01), "sick": sick,
			"trash_pct": snappedf(float(trash_hi) / float(maxi(1, nh)), 0.01), "text": dt}}


## coverage {kind}: 렌즈용 — covered/uncovered = 쓰이는 칸(주민 있는 주거·완공 시설의 칸) 중 범위 안/밖.
func _coverage_q(state: CityState, kind: String) -> Dictionary:
	var cov := sim.cover(state)
	var covered: Array = []
	var uncovered: Array = []
	var houses_only := kind != "fire"
	var test: Callable
	var label := ""
	if kind in TAGS:
		var tag: String = TAGS[kind]
		test = func(b: Dictionary) -> bool: return _covered(state, cov, tag, int(b["id"]))
		label = {"fire": "소방", "trash": "쓰레기 수거", "clinic": "의원"}[kind]
	elif kind == "market":
		test = func(b: Dictionary) -> bool:
			for fb: int in cov["markets"].get(int(b["id"]), []):
				if state.buildings.get(fb, {}).get("active", false):
					return true
			return false
		label = "시장"
	elif kind == "fun" or kind.begins_with("service:"):
		var tags: Array = ["mahjong", "teahouse", "karaoke", "casino"] if kind == "fun" else []
		if kind.begins_with("service:"):
			var sid := kind.substr(8)       # 시설 id(예: service:shrine) 또는 서비스 태그
			tags = sim.bdef(sid).get("services", [sid])
		test = func(b: Dictionary) -> bool:
			var sv: Dictionary = cov["services"].get(int(b["id"]), {})
			for t: String in tags:
				for fb: int in sv.get(t, []):
					if state.buildings.get(fb, {}).get("active", false):
						return true
			return false
		label = "놀 거리" if kind == "fun" else str(sim.bdef(kind.substr(8)).get("name", kind.substr(8)))
	else:
		return {"covered": [], "uncovered": [], "pct": 0.0, "text": "모르는 범위 종류다."}
	for b: Dictionary in (cov["houses"] if houses_only else cov["all"]):
		if not _used(b):
			continue
		var cells := Cover.bcells(b)
		if test.call(b):
			covered.append_array(cells)
		else:
			uncovered.append_array(cells)
	var n := covered.size() + uncovered.size()
	var pct := 1.0 if n == 0 else float(covered.size()) / float(n)
	var why := ""
	if kind in TAGS and pct < 1.0:
		# 왜 덮이지 않나: 그 범위 시설이 공사 중이거나 멈춰 있으면 그렇게 말한다(통합 보고: "0%"만으로는 공사 중인지 알 수 없었다)
		var tag2: String = TAGS[kind]
		var n_site := 0
		var n_off := 0
		for fb: Dictionary in state.buildings.values():
			if not (tag2 in sim.bdef(str(fb.get("type", ""))).get("services", [])):
				continue
			if fb["kind"] == "site":
				n_site += 1
			elif fb["kind"] == "facility" and not fb.get("active", false):
				n_off += 1
		if n_site > 0:
			why += " — %d곳 공사 중" % n_site
		if n_off > 0:
			var oc := Sim.off_reason(_first_off(state, tag2))
			why += " — %d곳 멈춤(%s)" % [n_off, {"paused": "멈춰 둠", "money": "돈 없음", "raid": "단속", "fire": "불", "burnt": "탐", "repair": "수리 중", "sky": "하늘 막힘"}.get(oc, "일손 부족")]
	return {"covered": covered, "uncovered": uncovered, "pct": snappedf(pct, 0.01),
		"text": "%s 범위: 쓰이는 칸 %d%% (밖 %d칸)%s" % [label, int(roundf(pct * 100.0)), uncovered.size(), why]}


func _goods_text(g: Dictionary) -> String:
	var parts: Array = []
	for k: String in g:
		parts.append("%s %d" % [sim.gname(k), int(g[k])])
	return " + ".join(parts)


func _first_off(state: CityState, tag: String) -> Dictionary:
	for fb: Dictionary in state.buildings.values():
		if fb["kind"] == "facility" and not fb.get("active", false) and tag in sim.bdef(str(fb["type"])).get("services", []):
			return fb
	return {}


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name == "hud":
		var q := _hazards_q(state)
		out["hazards"] = {"fire": {"on": q["fire"]["on"], "burning": (q["fire"]["burning"] as Array).size(), "burnt": (q["fire"]["burnt"] as Array).size(),
				"covered_pct": q["fire"]["covered_pct"], "grace_left": q["fire"]["grace_left"]},
			"disease": {"on": q["disease"]["on"], "sick_houses": (q["disease"]["sick"] as Array).size(), "covered_pct": q["disease"]["covered_pct"],
				"trash_covered_pct": q["disease"]["trash_covered_pct"], "grace_left": q["disease"]["grace_left"]}}
	elif name == "info" and out is Dictionary and out.has("bid"):
		var b: Dictionary = state.buildings.get(int(out["bid"]), {})
		if b.is_empty() or b["kind"] == "site":
			return
		out["burn"] = str(b.get("burn", ""))
		out["sick"] = bool(b.get("sick", false))
		var cov := sim.cover(state)
		out["covered"] = {"fire": _covered(state, cov, "fire", int(b["id"])), "trash": _covered(state, cov, "trash", int(b["id"])),
			"clinic": _covered(state, cov, "clinic", int(b["id"]))}
		if str(b.get("burn", "")) == "burnt":
			var c := _repair_cost(b)
			var ok := can(state, "repair", {"bid": int(b["id"])}) as Dictionary
			out["repair"] = {"ok": bool(ok["ok"]), "reason": str(ok["reason"]), "repairing": b.get("repair") != null,
				"cost_text": "%s + 고물 %d" % [Sim.won(float(c["money"])), int(c["goods"]["scrap"])], "days": c["days"]}
			if out.has("actions"):
				out["actions"].push_front({"id": "repair", "label": "수리", "enabled": bool(ok["ok"]), "reason": str(ok["reason"])})
		if b.get("sick", false):
			out["sick_text"] = "앓는 중 — %s 뒤 낫는다(일손 절반, 행복 −)" % Queries.day_text(maxf(0.0, float(b.get("sick_until", 0.0)) - state.econ_days))
