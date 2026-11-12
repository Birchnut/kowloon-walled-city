extends SimSystem
## upgrades — 수동 승급(확정): 만실 + 기본·승급 수요 충족(needs가 b.upgradable로 표시) + 돈 + 고른 한 계열 자재 qty(+추가 상품).
##  명령 upgrade {bids, material}: 묶음 전체가 가능할 때만 한꺼번에(원자적). 결제하면 비계(scaffold)가 서고 주민은 그대로 산다.
##  공사가 끝나면(upgrade_costs days) 계층·자재가 바뀌고 살던 주민이 새 계층이 된다.
##  정원이 줄면(12→8→6, GDD §3.3): 넘치는 주민은 같은(옛) 계층의 빈자리로 자동 이주 → 없으면 state.waiting(3경제일, 노동력으로 남음)
##  → 그 사이 빈자리가 나면 들어가고, 끝내 없으면 떠난다(기록에 남김). 인구는 조용히 사라지지 않는다.
## 끄면: 승급할 수 없고 대기 주민이 그대로 남는다.


func _cost(t: int) -> Dictionary:
	return sim.item("upgrade_costs", "%dto%d" % [t, t + 1])


func _mats() -> Array:
	return sim.db.get("upgrade_costs", {}).get("materials", [])


func _mat_name(m: String) -> String:
	return str(sim.db.get("upgrade_costs", {}).get("material_names", {}).get(m, sim.gname(m)))


## 묶음 승급 계획. 반환 {ok, reason, money, qty, extra{}, bids}
func _plan(state: CityState, args: Dictionary) -> Dictionary:
	var mat := str(args.get("material", ""))
	var bids: Array = []
	for x: Variant in args.get("bids", []):
		if not (int(x) in bids):
			bids.append(int(x))
	if bids.is_empty():
		return {"ok": false, "reason": "승급할 주거를 고르지 않았다."}
	if not (mat in _mats()):
		return {"ok": false, "reason": "자재를 목재·철제·콘크리트 중 하나로 골라야 한다."}
	var money := 0.0
	var qty := 0
	var extra := {}
	for bid: int in bids:
		var b: Dictionary = state.buildings.get(bid, {})
		if b.get("kind", "") != "house":
			return {"ok": false, "reason": "주거가 아니다."}
		if b.get("upgrading") != null:
			return {"ok": false, "reason": "이미 승급 공사 중인 주거가 있다."}
		if not b.get("ready", b.get("upgradable", false)):
			return {"ok": false, "reason": "아직 승급 조건이 안 된 주거가 있다(만실 + 기본·승급 수요 충족)."}
		var c := _cost(int(b["tier"]))
		money += float(c.get("money", 0))
		qty += int(c.get("qty", 0))
		for g: String in c.get("extra", {}):
			extra[g] = float(extra.get(g, 0.0)) + float(c["extra"][g])
	if state.money + 1e-9 < money:
		return {"ok": false, "reason": "돈이 모자란다(%s 필요)." % Sim.won(money), "money": money, "qty": qty, "extra": extra}
	if float(state.stock.get(mat, 0.0)) + 1e-9 < float(qty):
		return {"ok": false, "reason": Sim.kr("%s이(가) 모자란다(%d 필요, 지금 %d)." % [_mat_name(mat), qty, int(state.stock.get(mat, 0.0))]), "money": money, "qty": qty, "extra": extra}
	for g: String in extra:
		if float(state.stock.get(g, 0.0)) + 1e-9 < float(extra[g]):
			return {"ok": false, "reason": Sim.kr("%s이(가) 모자란다(%d 필요)." % [sim.gname(g), int(extra[g])]), "money": money, "qty": qty, "extra": extra}
	return {"ok": true, "reason": "", "money": money, "qty": qty, "extra": extra, "bids": bids, "material": mat}


func can(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "upgrade":
		return null
	var p := _plan(state, args)
	p["cost"] = {"money": p.get("money", 0.0), "goods": {}}
	if p.has("material") and p.get("qty", 0) > 0:
		p["cost"]["goods"][p["material"]] = p["qty"]
	for g: String in p.get("extra", {}):
		p["cost"]["goods"][g] = p["extra"][g]
	p["supports"] = 0
	return p


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "upgrade":
		return null
	var p := _plan(state, args)
	if not p["ok"]:
		return p
	var mat: String = p["material"]
	state.money -= float(p["money"])
	state.book("build", -float(p["money"]))
	state.stat_add("spent_upgrade", float(p["money"]))
	state.stock[mat] = float(state.stock.get(mat, 0.0)) - float(p["qty"])
	state.stat_add("used." + mat, float(p["qty"]))
	for g: String in p["extra"]:
		state.stock[g] = float(state.stock.get(g, 0.0)) - float(p["extra"][g])
		state.stat_add("used." + g, float(p["extra"][g]))
	for bid: int in p["bids"]:
		var b: Dictionary = state.buildings[bid]
		var t := int(b["tier"])
		b["upgrading"] = {"to": t + 1, "material": mat, "done_at": state.econ_days + float(_cost(t).get("days", 0.05))}
		b["upgradable"] = false
		b["ready"] = false
		state.cells[b["pos"]]["scaffold"] = true
		state.emit("cell_changed", {"pos": b["pos"]})
		state.emit("building_changed", {"bid": bid})
	sim.say(state, "주거 %d채에 비계를 올렸다(%s)." % [(p["bids"] as Array).size(), _mat_name(mat)])
	return {"ok": true, "reason": "", "count": (p["bids"] as Array).size()}


# ------------------------------------------------------------------ 틱: 공사 완료 · 대기 주민
func tick(state: CityState, dt: float) -> void:
	for b: Dictionary in sim.cover(state)["houses"]:
		var up: Variant = b.get("upgrading")
		if up != null and state.econ_days + 1e-9 >= float(up["done_at"]):
			_finish(state, b)
	if not state.waiting.is_empty():
		_place_waiting(state, dt)


func _finish(state: CityState, b: Dictionary) -> void:
	var up: Dictionary = b["upgrading"]
	var old_t := int(b["tier"])
	var new_t := int(up["to"])
	var cap := int(sim.tier(new_t).get("cap", 4))
	var res := int(b["residents"])
	var movers := maxi(0, res - cap)
	b["tier"] = new_t
	b["material"] = str(up["material"])
	b["cap"] = cap
	b["residents"] = res - movers
	b["upgrading"] = null
	b["needs"] = {}
	b.erase("psig")
	b.erase("nsig")
	b.erase("sdm")
	b.erase("sdc")
	b["grow"] = 0.0
	b["leave"] = 0.0
	var c: Dictionary = state.cells[b["pos"]]
	c["tier"] = new_t
	c["material"] = str(up["material"])
	c["scaffold"] = false
	state.emit("cell_changed", {"pos": b["pos"]})
	state.emit("building_changed", {"bid": int(b["id"])})
	state.emit("house_upgraded", {"bid": int(b["id"]), "tier": new_t, "material": str(up["material"])})
	var key := "first_upgrade_t%d_day" % new_t
	if not state.stats.has(key):
		state.stats[key] = state.econ_days
	state.stat_add("upgrades_t%d" % new_t, 1.0)
	if movers > 0:
		var moved := _move_into(state, old_t, movers, int(b["id"]))
		var left := movers - moved
		var msg := "%s %d명이 %s이(가) 되었다. 자리가 줄어 %d명은 같은 계층 빈집으로 옮겼다" % [sim.tname(old_t), res - movers, sim.tname(new_t), moved]
		if left > 0:
			var w: Dictionary = state.waiting.get(old_t, {"count": 0, "days_left": 0.0})
			w["count"] = int(w["count"]) + left
			w["days_left"] = float(sim.cfg("upgrade.waiting_days", 3))
			state.waiting[old_t] = w
			msg += ", %d명은 빈집을 기다린다(%d일 안에 없으면 떠난다)" % [left, int(w["days_left"])]
		sim.say(state, msg + ".", "warn" if left > 0 else "")


## 같은 계층 주거의 빈자리(cap − 주민)에 n명을 넣는다. 반환 = 넣은 수. 목표 인원(target)까지 찬 곳을 먼저 피한다.
func _move_into(state: CityState, t: int, n: int, skip: int) -> int:
	var moved := 0
	for pass_i: int in 2:
		for b: Dictionary in state.buildings.values():
			if moved >= n:
				return moved
			if b["kind"] != "house" or int(b["tier"]) != t or int(b["id"]) == skip:
				continue
			var lim := int(b.get("target", 0)) if pass_i == 0 else int(b["cap"])
			var room := mini(lim, int(b["cap"])) - int(b["residents"])
			if room <= 0:
				continue
			var k := mini(room, n - moved)
			b["residents"] = int(b["residents"]) + k
			moved += k
			state.emit("building_changed", {"bid": int(b["id"])})
	return moved


func _place_waiting(state: CityState, dt: float) -> void:
	for t: Variant in state.waiting.keys():
		var w: Dictionary = state.waiting[t]
		if int(w["count"]) > 0:
			var m := _move_into(state, int(t), int(w["count"]), -1)
			w["count"] = int(w["count"]) - m
		if not sim.offline:     # 미접속 중에는 대기 주민의 남은 날도 멈춘다(보호)
			w["days_left"] = float(w["days_left"]) - dt
		if int(w["count"]) > 0 and float(w["days_left"]) <= 0.0:
			sim.say(state, "빈집을 끝내 못 찾은 %s %d명이 성채를 떠났다." % [sim.tname(int(t)), int(w["count"])], "bad")
			state.stat_add("left", float(w["count"]))
			state.stat_add("left_waiting", float(w["count"]))
			w["count"] = 0
		if int(w["count"]) <= 0:
			state.waiting.erase(t)


# ------------------------------------------------------------------ 미리보기(info)
func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name != "info" or not (out is Dictionary) or out.get("kind", "") != "house":
		return
	var b: Dictionary = state.buildings.get(int(out["bid"]), {})
	var t := int(b.get("tier", 1))
	var c := _cost(t)
	var u := {"ready": false, "blockers": [], "to_tier": 0, "to_name": "", "cost": {"money": 0, "qty": 0, "extra": {}},
		"materials": [], "preview": {}, "upgrading": b.get("upgrading")}
	out["upgrade"] = u
	if c.is_empty():
		u["blockers"].append("최고 계층이다.")
		return
	var nt := t + 1
	u["to_tier"] = nt
	u["to_name"] = sim.tname(nt)
	u["cost"] = {"money": int(c.get("money", 0)), "qty": int(c.get("qty", 0)), "extra": c.get("extra", {})}
	for m: String in _mats():
		var have := float(state.stock.get(m, 0.0))
		u["materials"].append({"id": m, "name": _mat_name(m), "have": int(have), "enough": have + 1e-9 >= float(c.get("qty", 0))})
	if b.get("upgrading") != null:
		u["blockers"].append("승급 공사 중.")
	var res := int(b.get("residents", 0))
	var cap := int(b.get("cap", 0))
	if res < cap:
		u["blockers"].append("만실이어야 한다(%d/%d)." % [res, cap])
	var ok := float(sim.cfg("population.ok_ratio", 0.9))
	for nid: String in sim.items("needs"):
		var n := sim.item("needs", nid)
		if int(n.get("tier", 0)) != t or n.get("role", "") == "luxury":
			continue
		if float(b.get("needs", {}).get(nid, {}).get("ratio", 0.0)) < ok:
			u["blockers"].append("%s 수요 미충족: %s" % ["기본" if n["role"] == "basic" else "승급 조건", n.get("name", nid)])
	if state.money + 1e-9 < float(c.get("money", 0)):
		u["blockers"].append("돈이 모자란다(%s)." % Sim.won(float(c.get("money", 0))))
	var any_mat := false
	for m: Dictionary in u["materials"]:
		any_mat = any_mat or m["enough"]
	if not any_mat:
		u["blockers"].append("세 자재 중 하나가 %d개 있어야 한다." % int(c.get("qty", 0)))
	for g: String in c.get("extra", {}):
		if float(state.stock.get(g, 0.0)) + 1e-9 < float(c["extra"][g]):
			u["blockers"].append("%s %d개가 필요하다." % [sim.gname(g), int(c["extra"][g])])
	u["ready"] = bool(b.get("ready", b.get("upgradable", false))) and (u["blockers"] as Array).is_empty()
	u["preview"] = _preview(state, [b])


## 승급 미리보기(여러 주거 합산). bids의 주거들은 서로의 빈자리로 치지 않는다.
func _preview(state: CityState, houses: Array) -> Dictionary:
	var skip := {}
	for b: Dictionary in houses:
		skip[int(b["id"])] = true
	var cap_from := 0
	var cap_to_sum := 0
	var movers := 0
	var labor := {}
	var tax_now := 0.0
	var tax_after := 0.0
	var tax_full := 0.0
	var water := [0.0, 0.0]
	var pw := 0.0
	var movers_by := {}
	var to_tiers := {}
	for b: Dictionary in houses:
		var t := int(b["tier"])
		var nt := t + 1
		var res := int(b.get("residents", 0))
		var cap_to := int(sim.tier(nt).get("cap", 0))
		var stay := mini(res, cap_to)
		var mv := maxi(0, res - cap_to)
		cap_from += int(b.get("cap", 0))
		cap_to_sum += cap_to
		movers += mv
		movers_by[t] = int(movers_by.get(t, 0)) + mv
		to_tiers[nt] = true
		labor[t] = int(labor.get(t, 0)) - int(floorf(stay * float(sim.tier(t).get("labor", 1.0))))
		labor[nt] = int(labor.get(nt, 0)) + int(floorf(stay * float(sim.tier(nt).get("labor", 1.0))))
		tax_now += float(b.get("tax", 0.0))
		tax_after += float(stay) * float(sim.tier(nt).get("tax", 0.0))
		tax_full += float(cap_to) * float(sim.tier(nt).get("tax", 0.0))
		water[0] += stay * float(sim.tier(nt).get("water", 0)) - res * float(sim.tier(t).get("water", 0))
		water[1] += cap_to * float(sim.tier(nt).get("water", 0)) - res * float(sim.tier(t).get("water", 0))
		pw += cap_to * float(sim.tier(nt).get("power", 0)) - res * float(sim.tier(t).get("power", 0))
	var vac := 0
	for t: int in movers_by:
		for o: Dictionary in state.buildings.values():
			if o["kind"] == "house" and int(o["tier"]) == t and not skip.has(int(o["id"])):
				vac += maxi(0, int(o["cap"]) - int(o["residents"]))
	if movers_by.is_empty() and houses.size() > 0:
		var t0 := int(houses[0]["tier"])
		for o: Dictionary in state.buildings.values():
			if o["kind"] == "house" and int(o["tier"]) == t0 and not skip.has(int(o["id"])):
				vac += maxi(0, int(o["cap"]) - int(o["residents"]))
	var demand: Array = ["물 %+.1f/일 (지금 인원 기준), 만실이면 %+.1f/일" % [water[0], water[1]]]
	if absf(pw) > 0.01:
		demand.append("전기 %+.1f (만실 기준)" % pw)
	for nt: int in to_tiers:
		var new_needs: Array = []
		for nid: String in sim.items("needs"):
			var n := sim.item("needs", nid)
			if int(n.get("tier", 0)) == nt and n.get("role", "") != "luxury":
				new_needs.append(str(n.get("name", nid)))
		demand.append("%s 수요: %s" % [sim.tname(nt), ", ".join(new_needs)])
	if movers > 0:
		demand.append("%d명이 이주해야 한다 / 같은 계층 빈자리 %d%s" % [movers, vac, "" if vac >= movers else " — 모자라면 %d일 대기 뒤 떠난다" % int(sim.cfg("upgrade.waiting_days", 3))])
	var lab: Array = []
	var ts: Array = labor.keys()
	ts.sort()
	for t: int in ts:
		lab.append({"tier": t, "name": sim.tname(t), "delta": int(labor[t])})
	return {"cap_from": cap_from, "cap_to": cap_to_sum, "movers": movers, "vacancies": vac, "labor": lab,
		"tax_now": snappedf(tax_now, 0.1), "tax_after_now": snappedf(tax_after, 0.1),
		"tax_full": snappedf(tax_full, 0.1), "tax_delta": snappedf(tax_full - tax_now, 0.1), "demand_text": demand}


func query(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"upgradable":
			var by := {}
			for b: Dictionary in state.buildings.values():
				if b["kind"] == "house" and b.get("upgradable", false) and (not args.has("tier") or int(args["tier"]) == int(b["tier"])):
					var t := int(b["tier"])
					if not by.has(t):
						by[t] = []
					by[t].append(int(b["id"]))
			var out: Array = []
			var ts: Array = by.keys()
			ts.sort()
			for t: int in ts:
				out.append({"tier": t, "tier_name": sim.tname(t), "count": (by[t] as Array).size(), "bids": by[t]})
			return out
		"upgrade_preview":
			var houses: Array = []
			for x: Variant in args.get("bids", []):
				var b: Dictionary = state.buildings.get(int(x), {})
				if b.get("kind", "") == "house" and int(b["tier"]) < sim.max_tier() and not (b in houses):
					houses.append(b)
			var p := _plan(state, args)
			var pv := _preview(state, houses)
			pv["ok"] = bool(p.get("ok", false))
			pv["blockers"] = [] if pv["ok"] else [str(p.get("reason", ""))]
			pv["cost"] = {"money": p.get("money", 0.0), "qty": p.get("qty", 0), "extra": p.get("extra", {})}
			return pv
	return null
