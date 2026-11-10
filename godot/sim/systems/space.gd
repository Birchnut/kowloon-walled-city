extends SimSystem
## space — 공간: 주거 구역 칠하기(zone), 시설 짓기(build), 철거(demolish), 일시정지(pause), 공사(site) 진행,
## 자동 골조(supports), 층 해금(80%), range_preview 질의.
## 수치: config zone.shack_cost, floors.{threshold, eligible_cells, support_cost}, buildings.json cost·size·build_days.
## 끄면: 아무것도 지을 수 없고 공사가 멈추며 층이 열리지 않는다(나머지 경제는 돈다).


# ------------------------------------------------------------------ 틱: 공사 진행 · 층 해금
func tick(state: CityState, dt: float) -> void:
	for bid: int in state.buildings.keys():
		var b: Dictionary = state.buildings[bid]
		if b["kind"] != "site":
			continue
		var d := sim.bdef(str(b["type"]))
		b["progress"] = minf(1.0, float(b["progress"]) + dt / maxf(float(d.get("build_days", 0.05)), 1e-6))
		for p: Vector3i in Cover.footprint(b["pos"], int(b["size"])):
			if state.cells.has(p):
				state.cells[p]["progress"] = b["progress"]
		if float(b["progress"]) >= 1.0 - 1e-9:
			_complete(state, bid)
	_check_floor(state)


func _complete(state: CityState, bid: int) -> void:
	var b: Dictionary = state.buildings[bid]
	var type := str(b["type"])
	state.buildings[bid] = {"id": bid, "kind": "facility", "type": type, "pos": b["pos"], "size": b["size"],
		"active": false, "paused": false, "staff": 0.0, "eff": 0.0, "cause": "staff", "built": state.day,
		"w_ratio": 1.0, "p_ratio": 1.0, "money_stop": false, "vice_rate": 0.0}
	for p: Vector3i in Cover.footprint(b["pos"], int(b["size"])):
		var c: Dictionary = state.cells[p]
		c["kind"] = "facility"
		c.erase("progress")
		c.erase("becomes")
		state.emit("cell_changed", {"pos": p})
	state.layout_changed()
	state.emit("building_changed", {"bid": bid})
	sim.say(state, "%s 완공." % sim.bdef(type).get("name", type))


func floor_need() -> int:
	return int(ceilf(float(sim.cfg("floors.threshold", 0.8)) * float(sim.cfg("floors.eligible_cells", 144)) - 1e-6))


func _check_floor(state: CityState) -> void:
	if state.floors_unlocked >= sim.F:
		return
	var z := state.floors_unlocked - 1
	if Cover.used_cells(state, z) >= floor_need():
		state.floors_unlocked += 1
		state.emit("floor_unlocked", {"z": z + 1})
		state.stats["floor_%d_day" % (z + 2)] = state.econ_days
		sim.say(state, "%d층이 열렸다. 이제 그 위에도 지을 수 있다(아래가 비면 골조가 선다)." % (z + 2), "good")


# ------------------------------------------------------------------ 자리·골조
func _inside(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < sim.W and p.y < sim.H and p.z >= 0 and p.z < sim.F


## 칸 하나에 지을 수 있나. 반환 "" = 된다.
func _free_reason(state: CityState, p: Vector3i) -> String:
	if not _inside(p):
		return "부지 밖이다."
	if p.z >= state.floors_unlocked:
		return "%d층은 아직 열리지 않았다(아래층을 80%% 채우면 열린다)." % (p.z + 1)
	if state.cells.has(p):
		return "이미 건물이 있다."
	return ""


## 칸들 아래 빈 곳에 생겨야 할 골조 위치(중복 없이). 기존 칸이나 골조를 만나면 멈춘다.
static func supports_for(state: CityState, cells: Array) -> Array:
	var out: Array = []
	var seen := {}
	for p: Vector3i in cells:
		var z := p.z - 1
		while z >= 0:
			var q := Vector3i(p.x, p.y, z)
			if state.cells.has(q) or state.supports.has(q) or seen.has(q):
				break
			if not (q in cells):
				out.append(q)
				seen[q] = true
			z -= 1
	return out


func _add_supports(state: CityState, list: Array) -> void:
	for q: Vector3i in list:
		if not state.supports.has(q):
			state.supports[q] = true
			state.emit("support_changed", {"pos": q})


## 골조는 같은 기둥 위쪽에 셀이 있을 때만 남긴다.
func _prune_column(state: CityState, x: int, y: int) -> void:
	var top := -1
	for z: int in range(sim.F - 1, -1, -1):
		if state.cells.has(Vector3i(x, y, z)):
			top = z
			break
	for z: int in sim.F:
		var q := Vector3i(x, y, z)
		if state.supports.has(q) and z >= top:
			state.supports.erase(q)
			state.emit("support_changed", {"pos": q})


func _support_cost(n: int) -> float:
	return float(sim.cfg("floors.support_cost", 0)) * float(n)


# ------------------------------------------------------------------ can / apply
func can(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"zone": return _can_zone(state, args)
		"build": return _can_build(state, args)
		"demolish":
			var c := state.cell(args.get("pos", Vector3i(-1, -1, -1)))
			if c.is_empty():
				return {"ok": false, "reason": "철거할 건물이 없다.", "supports": 0, "cost": {}}
			return {"ok": true, "reason": "", "supports": 0, "cost": {}}
		"pause":
			var b: Dictionary = state.buildings.get(int(args.get("bid", -1)), {})
			if b.get("kind", "") != "facility":
				return {"ok": false, "reason": "멈출 수 있는 시설이 아니다."}
			return {"ok": true, "reason": ""}
	return null


func _cells_arg(args: Dictionary) -> Array:
	var out: Array = []
	for p: Variant in args.get("cells", []):
		if p is Vector3i:
			out.append(p)
		elif p is Array and p.size() == 3:
			out.append(Vector3i(int(p[0]), int(p[1]), int(p[2])))
	return out


## zone: 되는 칸만 짓는다. ok = 한 칸이라도 지을 수 있으면.
func _plan_zone(state: CityState, cells: Array) -> Dictionary:
	var unit := float(sim.cfg("zone.shack_cost", 5))
	var money := state.money
	var good: Array = []
	var skipped: Array = []
	var sup_all: Array = []
	if not sim.is_unlocked(state, "house"):
		for p: Vector3i in cells:
			skipped.append({"pos": p, "reason": "아직 주거를 지정할 수 없다."})
		return {"good": good, "skipped": skipped, "supports": sup_all, "money": 0.0}
	var spent := 0.0
	for p: Vector3i in cells:
		var r := _free_reason(state, p)
		if r == "" and p in good:
			r = "같은 칸을 두 번 골랐다."
		if r != "":
			skipped.append({"pos": p, "reason": r})
			continue
		var sup := supports_for(state, good + [p])
		var extra: Array = []
		for q: Vector3i in sup:
			if not (q in sup_all):
				extra.append(q)
		var c := unit + _support_cost(extra.size())
		if spent + c > money + 1e-9:
			skipped.append({"pos": p, "reason": "돈이 모자란다(₩%d 필요)." % int(ceilf(c))})
			continue
		spent += c
		good.append(p)
		sup_all.append_array(extra)
	return {"good": good, "skipped": skipped, "supports": sup_all, "money": spent}


func _can_zone(state: CityState, args: Dictionary) -> Dictionary:
	var cells := _cells_arg(args)
	if cells.is_empty():
		return {"ok": false, "reason": "칸을 고르지 않았다.", "supports": 0, "cost": {}}
	var plan := _plan_zone(state, cells)
	var ok := not (plan["good"] as Array).is_empty()
	var reason := "" if ok else str(plan["skipped"][0]["reason"])
	return {"ok": ok, "reason": reason, "supports": (plan["supports"] as Array).size(), "cost": {"money": plan["money"], "goods": {}},
		"built": (plan["good"] as Array).size(), "skipped": plan["skipped"], "support_cells": plan["supports"]}


func _can_build(state: CityState, args: Dictionary) -> Dictionary:
	var type := str(args.get("type", ""))
	var d := sim.bdef(type)
	var pos: Variant = args.get("pos", null)
	var fail := func(r: String) -> Dictionary: return {"ok": false, "reason": r, "supports": 0, "cost": d.get("cost", {})}
	if d.is_empty():
		return fail.call("모르는 시설이다.")
	if not (pos is Vector3i):
		return fail.call("자리를 고르지 않았다.")
	if not sim.is_unlocked(state, type):
		return fail.call("아직 지을 수 없다 — %s" % _lock_hint(type))
	if d.has("blueprint") and not state.flags.get("blueprints", {}).has(str(d["blueprint"])):
		return fail.call("도면이 있어야 짓는다(탐험에서 찾는다).")
	var size := int(d.get("size", 1))
	var cells := Cover.footprint(pos, size)
	for p: Vector3i in cells:
		var r := _free_reason(state, p)
		if r != "":
			return fail.call(r if size == 1 else "2×2 자리 중 한 칸: " + r)
	if d.get("open_sky", false):
		for p: Vector3i in cells:
			for z: int in range(p.z + 1, sim.F):
				if state.cells.has(Vector3i(p.x, p.y, z)):
					return fail.call("하늘이 열린 자리여야 한다(위에 건물이 있다).")
	var sup := supports_for(state, cells)
	var money := float(d.get("cost", {}).get("money", 0)) + _support_cost(sup.size())
	var goods: Dictionary = d.get("cost", {}).get("goods", {})
	var cost := {"money": money, "goods": goods}
	if state.money + 1e-9 < money:
		return {"ok": false, "reason": "돈이 모자란다(₩%d 필요, 지금 ₩%d)." % [int(money), int(state.money)], "supports": sup.size(), "cost": cost, "support_cells": sup}
	for g: String in goods:
		if float(state.stock.get(g, 0.0)) + 1e-9 < float(goods[g]):
			return {"ok": false, "reason": "%s이(가) 모자란다(%d 필요, 지금 %d)." % [sim.gname(g), int(goods[g]), int(state.stock.get(g, 0.0))], "supports": sup.size(), "cost": cost, "support_cells": sup}
	return {"ok": true, "reason": "", "supports": sup.size(), "cost": cost, "support_cells": sup}


func _lock_hint(id: String) -> String:
	for uid: String in sim.items("unlocks"):
		var u: Dictionary = sim.item("unlocks", uid)
		if id in u.get("unlocks", []):
			return Queries.cond_text(sim, u.get("cond", []))
	return "해금 조건 없음"


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"zone": return _zone(state, args)
		"build": return _build(state, args)
		"demolish": return _demolish(state, args.get("pos"))
		"pause":
			var b: Dictionary = state.buildings[int(args["bid"])]
			b["paused"] = bool(args.get("on", true))
			state.emit("building_changed", {"bid": int(args["bid"])})
			return {"ok": true, "reason": ""}
	return null


func _zone(state: CityState, args: Dictionary) -> Dictionary:
	var plan := _plan_zone(state, _cells_arg(args))
	if (plan["good"] as Array).is_empty():
		return {"ok": false, "reason": str(plan["skipped"][0]["reason"]) if not (plan["skipped"] as Array).is_empty() else "칸이 없다.", "built": 0, "skipped": plan["skipped"]}
	_add_supports(state, plan["supports"])
	state.money -= float(plan["money"])
	state.book("build", -float(plan["money"]))
	var cap := int(sim.tier(1).get("cap", 4))
	for p: Vector3i in plan["good"]:
		var bid := state.new_id()
		var seed := sim.rand_seed(state)
		state.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": 1, "material": "common", "residents": 0,
			"cap": cap, "happiness": 50.0, "needs": {}, "need_state": "warn", "upgradable": false, "upgrading": null,
			"grow": 0.0, "leave": 0.0, "target": 0, "tax": 0.0, "util_extra": {}}
		state.cells[p] = {"kind": "house", "bid": bid, "type": "house", "tier": 1, "material": "common", "seed": seed,
			"origin": p, "size": 1, "scaffold": false}
		state.emit("cell_changed", {"pos": p})
		state.emit("building_changed", {"bid": bid})
	state.layout_changed()
	state.stat_add("shacks_built", float((plan["good"] as Array).size()))
	return {"ok": true, "reason": "", "built": (plan["good"] as Array).size(), "skipped": plan["skipped"],
		"supports": (plan["supports"] as Array).size()}


func _build(state: CityState, args: Dictionary) -> Dictionary:
	var c := _can_build(state, args)   # 다시 계산(원자적: 지지대·비용·건물을 한 번에)
	if not c["ok"]:
		return c
	var type := str(args["type"])
	var d := sim.bdef(type)
	var pos: Vector3i = args["pos"]
	var size := int(d.get("size", 1))
	_add_supports(state, c["support_cells"])
	state.money -= float(c["cost"]["money"])
	state.book("build", -float(c["cost"]["money"]))
	for g: String in c["cost"]["goods"]:
		state.stock[g] = float(state.stock.get(g, 0.0)) - float(c["cost"]["goods"][g])
		state.stat_add("used." + g, float(c["cost"]["goods"][g]))
	var bid := state.new_id()
	var seed := sim.rand_seed(state)
	state.buildings[bid] = {"id": bid, "kind": "site", "type": type, "pos": pos, "size": size, "progress": 0.0}
	for p: Vector3i in Cover.footprint(pos, size):
		state.cells[p] = {"kind": "site", "bid": bid, "type": type, "tier": 0, "material": "", "seed": seed,
			"origin": pos, "size": size, "scaffold": false, "progress": 0.0, "becomes": {"kind": "facility", "type": type}}
		state.emit("cell_changed", {"pos": p})
	state.emit("building_changed", {"bid": bid})
	state.layout_changed()
	return {"ok": true, "reason": "", "bid": bid, "supports": (c["support_cells"] as Array).size()}


func _demolish(state: CityState, pos: Variant) -> Dictionary:
	var c := state.cell(pos)
	var bid := int(c["bid"])
	var b: Dictionary = state.buildings[bid]
	var cells := Cover.footprint(b["pos"], int(b.get("size", 1)))
	if b["kind"] == "house" and int(b["residents"]) > 0:
		var t := int(b["tier"])
		var w: Dictionary = state.waiting.get(t, {"count": 0, "days_left": 0.0})
		w["count"] = int(w["count"]) + int(b["residents"])
		w["days_left"] = float(sim.cfg("upgrade.waiting_days", 3))
		state.waiting[t] = w
		sim.say(state, "주거를 허물어 %s %d명이 빈집을 찾아 기다린다(%d일 안에 못 찾으면 떠난다)." % [sim.tname(t), int(b["residents"]), int(w["days_left"])], "warn")
	state.buildings.erase(bid)
	for p: Vector3i in cells:
		state.cells.erase(p)
		if state.cells.has(p + Vector3i(0, 0, 1)) or state.supports.has(p + Vector3i(0, 0, 1)):
			state.supports[p] = true
			state.emit("support_changed", {"pos": p})
		state.emit("cell_changed", {"pos": p})
	for p: Vector3i in cells:
		_prune_column(state, p.x, p.y)
	state.emit("building_changed", {"bid": bid})
	state.layout_changed()
	return {"ok": true, "reason": ""}


# ------------------------------------------------------------------ 질의
func query(state: CityState, name: String, args: Dictionary) -> Variant:
	if name != "range_preview":
		return null
	var type := str(args.get("type", ""))
	var pos: Variant = args.get("pos", null)
	var d := sim.bdef(type)
	if d.is_empty() or not (pos is Vector3i) or not d.has("range"):
		return {"cells": [], "houses": 0, "text": "범위가 없는 시설이다."}
	var size := int(d.get("size", 1))
	var rng := int(d["range"])
	var cells := Cover.range_cells(sim, pos, size, rng)
	var n := 0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house" and Cover.dist(sim, b["pos"], pos, size) <= rng:
			n += 1
	var md := int(sim.cfg("distance.max_floor_delta", 2))
	return {"cells": cells, "houses": n, "text": "범위 %d칸(위아래 %d층까지, 한 층 = 2칸) · 닿는 주거 %d채" % [rng, md, n]}
