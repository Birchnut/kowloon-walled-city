extends SimSystem
## space — 공간: 주거 구역 칠하기(zone), 시설 짓기(build), 철거(demolish), 일시정지(pause), 공사(site) 진행,
## 자동 골조(supports), 층 해금(80%), range_preview 질의.
## 수치: config zone.shack_cost, floors.{threshold, eligible_cells, support_cost}, buildings.json cost·size·build_days.
## 끄면: 아무것도 지을 수 없고 공사가 멈추며 층이 열리지 않는다(나머지 경제는 돈다).


# ------------------------------------------------------------------ 틱: 공사 진행 · 하늘 · 층 해금
func tick(state: CityState, dt: float) -> void:
	var cov := sim.cover(state)
	for bid: int in (cov["sites"] as Array).duplicate():
		var b: Dictionary = state.buildings.get(bid, {})
		if b.get("kind", "") != "site":
			continue
		var days := maxf(float(b.get("days", sim.build_days(str(b["type"])))), 1e-6)
		b["progress"] = minf(1.0, float(b["progress"]) + dt / days)
		b["build_left"] = maxf(0.0, (1.0 - float(b["progress"])) * days)
		for p: Vector3i in Cover.bcells(b):
			if state.cells.has(p):
				state.cells[p]["progress"] = b["progress"]
		if float(b["progress"]) >= 1.0 - 1e-9:
			_complete(state, bid)
	# 하늘이 필요한 시설(옥상 텃밭·옥상 공원): 위에 무엇이든 서면 멈춘다(cause "sky"). 허물면 다시 돈다.
	for bid: int in cov["sky"]:
		var b: Dictionary = state.buildings.get(bid, {})
		if b.is_empty():
			continue
		var shade := not _sky_open(state, b["pos"], Cover.dims(b))
		if shade != bool(b.get("shade", false)):
			b["shade"] = shade
			state.emit("building_changed", {"bid": bid})
			sim.say(state, ("%s 위에 무언가가 들어서 해가 들지 않는다. 멈췄다." if shade else "%s에 다시 해가 든다.") % sim.bdef(str(b["type"])).get("name", ""), "warn" if shade else "")
	_check_floor(state)


func _complete(state: CityState, bid: int) -> void:
	var b: Dictionary = state.buildings[bid]
	var type := str(b["type"])
	state.buildings[bid] = {"id": bid, "kind": "facility", "type": type, "pos": b["pos"], "size": b["size"],
		"w": int(b["w"]), "h": int(b["h"]), "d": int(b["d"]), "rot": int(b.get("rot", 0)), "front": int(b.get("front", b.get("rot", 0))),
		"active": false, "paused": false, "staff": 0.0, "eff": 0.0, "cause": "staff", "built": state.day,
		"w_ratio": 1.0, "p_ratio": 1.0, "money_stop": false, "vice_rate": 0.0, "burn": "", "build_left": 0.0, "repair": null}
	for p: Vector3i in Cover.bcells(b):
		var c: Dictionary = state.cells[p]
		c["kind"] = "facility"
		c.erase("progress")
		c.erase("becomes")
		state.emit("cell_changed", {"pos": p})
	state.layout_changed()
	state.emit("building_changed", {"bid": bid})
	state.emit("construction_done", {"bid": bid, "type": type})
	state.stat_add("built." + type, 1.0)
	sim.say(state, "%s 완공." % sim.bdef(type).get("name", type))


## 발자국 위(맨 위층 바로 위부터 하늘까지)가 비었나.
func _sky_open(state: CityState, o: Vector3i, k: Vector3i) -> bool:
	for dx: int in k.x:
		for dy: int in k.y:
			for z: int in range(o.z + k.z, sim.F):
				var q := Vector3i(o.x + dx, o.y + dy, z)
				if state.cells.has(q):
					return false
	return true


## 명령이 성공한 직후에도 층 해금을 본다(파트 C): 정시·스텝을 기다리지 않게(디버그 채우기·철거 뒤 등).
func on_command(state: CityState, _name: String, _args: Dictionary, _result: Dictionary) -> void:
	_check_floor(state)


## 층 하나에서 다음 층을 여는 데 필요한 쓰이는 칸 수(80% × 부지 칸 수).
func floor_need() -> int:
	return Cover.floor_need(sim)


func _check_floor(state: CityState) -> void:
	if state.floors_unlocked >= sim.F:
		return
	var z := state.floors_unlocked - 1
	if Cover.used_cells_fast(sim, state, z) >= floor_need():
		state.floors_unlocked += 1
		state.emit("floor_unlocked", {"z": z + 1})
		state.stats["floor_%d_day" % (z + 2)] = state.econ_days
		sim.say(state, "%d층 받침이 올랐다. 그 위에도 지을 수 있다(아래가 비면 골조가 선다)." % (z + 2), "good")
		sim.chron(state, "floor", "%d층 받침이 올랐다." % (z + 2))


# ------------------------------------------------------------------ 자리·골조
func _inside(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < sim.W and p.y < sim.H and p.z >= 0 and p.z < sim.F


## 칸 하나에 지을 수 있나. 반환 "" = 된다.
func _free_reason(state: CityState, p: Vector3i) -> String:
	if not _inside(p):
		return "부지 밖이다."
	if p.z >= state.floors_unlocked:
		return "%d층 받침은 아직 오르지 않았다(아래층 칸의 여덟 할이 쓰이면 오른다)." % (p.z + 1)
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
			var b: Dictionary = state.buildings.get(int(c["bid"]), {})
			var dc := _demolish_cost(state, b)
			if dc > state.money + 1e-9:
				return {"ok": false, "reason": "받침 값 %s이(가) 모자란다(위에 %d개 층이 얹혀 있다)." % [Sim.won(dc), int(Cover.depth_of_b(state, b, sim.F))],
					"code": "money", "supports": 0, "cost": {"money": dc, "goods": {}}}
			return {"ok": true, "reason": "", "supports": 0, "cost": {"money": dc, "goods": {}}}
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
			skipped.append({"pos": p, "reason": "아직 주거를 지정할 수 없다.", "code": "locked"})
		return {"good": good, "skipped": skipped, "supports": sup_all, "money": 0.0}
	var spent := 0.0
	for p: Vector3i in cells:
		var r := _free_reason(state, p)
		var code := _free_code(state, p)
		if r == "" and p in good:
			r = "같은 칸을 두 번 골랐다."
			code = "occupied"
		if r != "":
			skipped.append({"pos": p, "reason": r, "code": code})
			continue
		var sup := supports_for(state, good + [p])
		var extra: Array = []
		for q: Vector3i in sup:
			if not (q in sup_all):
				extra.append(q)
		var c := unit + _support_cost(extra.size())
		if spent + c > money + 1e-9:
			skipped.append({"pos": p, "reason": "돈이 모자란다(%s 필요)." % Sim.won(ceilf(c)), "code": "money"})
			continue
		spent += c
		good.append(p)
		sup_all.append_array(extra)
	return {"good": good, "skipped": skipped, "supports": sup_all, "money": spent}


func _can_zone(state: CityState, args: Dictionary) -> Dictionary:
	var cells := _cells_arg(args)
	if cells.is_empty():
		return {"ok": false, "reason": "칸을 고르지 않았다.", "code": "bounds", "supports": 0, "cost": {}}
	var plan := _plan_zone(state, cells)
	var ok := not (plan["good"] as Array).is_empty()
	var reason := "" if ok else str(plan["skipped"][0]["reason"])
	var code := "ok"
	if not ok:
		code = str(plan["skipped"][0].get("code", "occupied"))
	return {"ok": ok, "reason": reason, "code": code, "supports": (plan["supports"] as Array).size(), "cost": {"money": plan["money"], "goods": {}},
		"built": (plan["good"] as Array).size(), "skipped": plan["skipped"], "support_cells": plan["supports"]}


## 시설 짓기 판정. 결과에 cells(발자국 전부)·supports(생길 골조 칸)·code(ok|bounds|locked_floor|occupied|shape|sky|floor|money|goods|locked).
func _can_build(state: CityState, args: Dictionary) -> Dictionary:
	var type := str(args.get("type", ""))
	var d := sim.bdef(type)
	var pos: Variant = args.get("pos", null)
	var rot := int(args.get("rot", 0)) % 2
	var cost0: Dictionary = sim.build_cost(type)
	var cells: Array = []
	var fail := func(r: String, code: String, sup: Array = []) -> Dictionary:
		return {"ok": false, "reason": r, "code": code, "supports": sup, "support_count": sup.size(), "support_cells": sup, "cells": cells, "cost": cost0}
	if d.is_empty():
		return fail.call("모르는 시설이다.", "locked")
	if not (pos is Vector3i):
		return fail.call("자리를 고르지 않았다.", "bounds")
	var k := sim.fp(type, rot)
	cells = Cover.cells_of(pos, k.x, k.y, k.z)
	if not sim.is_unlocked(state, type):
		return fail.call("아직 지을 수 없다 — %s" % _lock_hint(type), "locked")
	if d.has("blueprint") and not state.flags.get("blueprints", {}).has(str(d["blueprint"])):
		return fail.call("도면이 있어야 짓는다(회색 띠에서 찾는다).", "locked")
	var multi: bool = cells.size() > 1
	if not _inside(pos):
		return fail.call("부지 밖이다.", "bounds")
	for p: Vector3i in cells:
		var code := _free_code(state, p)
		if code == "ok":
			continue
		var r := _free_reason(state, p)
		if not multi or code == "locked_floor":
			if code == "locked_floor" and k.z > 1 and p.z > (pos as Vector3i).z:
				r = "%d개 층짜리라 %d층도 열려 있어야 한다." % [k.z, p.z + 1]
			return fail.call(r, code)
		var msg := "%d×%d 자리가 모자란다: %s" % [k.x, k.y, r]
		if code == "occupied" and _free_count(state, (pos as Vector3i).z, k.x, k.y) == 0 and _free_count(state, (pos as Vector3i).z, k.y, k.x) == 0:
			msg += " 이 층에는 빈 %d×%d 자리가 없다 — 주거 몇 칸을 허물면(무료, 주민은 빈집을 찾는다) 자리가 생긴다." % [k.x, k.y]
		return fail.call(msg, "shape")
	var mf := int(d.get("min_floor", 0))
	if (pos as Vector3i).z < mf:
		return fail.call("%d층 이상에만 지을 수 있다." % (mf + 1), "floor")
	if d.get("needs_sky", false) or d.get("open_sky", false):
		if not _sky_open(state, pos, k):
			return fail.call("위가 뚫린 자리여야 한다(위에 건물이 있다).", "sky")
	var oz := _org_conflict(state, type, cells)
	if oz != "":
		return fail.call(oz, "org_zone")
	var sup := supports_for(state, cells)
	var money := float(cost0["money"]) + _support_cost(sup.size())
	var goods: Dictionary = cost0["goods"]
	var cost := {"money": money, "goods": goods}
	var base := {"supports": sup, "support_count": sup.size(), "support_cells": sup, "cells": cells, "cost": cost, "rot": rot,
		"w": k.x, "h": k.y, "d": k.z, "build_days": snappedf(sim.build_days(type), 0.01)}
	var warn := _shade_warning(state, cells)
	if warn != "":
		base["warn"] = warn
	if state.money + 1e-9 < money:
		base.merge({"ok": false, "reason": "돈이 모자란다(%s 필요, 지금 %s)." % [Sim.won(money), Sim.won(state.money)], "code": "money"})
		return base
	for g: String in goods:
		if float(state.stock.get(g, 0.0)) + 1e-9 < float(goods[g]):
			base.merge({"ok": false, "reason": Sim.kr("%s이(가) 모자란다(%d 필요, 지금 %d)." % [sim.gname(g), int(goods[g]), int(state.stock.get(g, 0.0))]), "code": "goods"})
			return base
	base.merge({"ok": true, "reason": "", "code": "ok"})
	return base


## 조직 층 규칙(v0.5): 십삼요회 시설과 연우당 시설은 같은 층에도, 맞닿은 층에도 둘 수 없다(사이에 한 층). 반환 ""이면 된다.
func _org_conflict(state: CityState, type: String, cells: Array) -> String:
	var org := str(sim.bdef(type).get("org", ""))
	if org == "" or not sim.enabled.has("org"):
		return ""
	var zmin := 99
	var zmax := -1
	for p: Vector3i in cells:
		zmin = mini(zmin, p.z)
		zmax = maxi(zmax, p.z)
	var cov := sim.cover(state)
	var found: Array = []        # [층, 시설 id]
	for bid: int in cov["org"]:
		if str(cov["org"][bid]) == org:
			continue
		var b: Dictionary = state.buildings.get(bid, {})
		found.append([b["pos"], str(b["type"]), Cover.dims(b).z])
	for bid: int in cov["sites"]:
		var s: Dictionary = state.buildings.get(bid, {})
		var so := str(sim.bdef(str(s.get("type", ""))).get("org", ""))
		if so != "" and so != org:
			found.append([s["pos"], str(s["type"]), int(s.get("d", 1))])
	for f: Array in found:
		var z0: int = (f[0] as Vector3i).z
		var z1: int = z0 + int(f[2]) - 1
		if zmax >= z0 - 1 and zmin <= z1 + 1:
			var names: Dictionary = sim.cfg("org.names", {})
			var other := "yeonu" if org == "thirteen" else "thirteen"
			return "%s 시설과 %s 시설은 같은 층에도, 맞닿은 층에도 둘 수 없다. %d층에 %s이(가) 있다. 사이에 한 층을 비워야 한다." % [
				str(names.get(org, org)), str(names.get(other, other)), z0 + 1, sim.bdef(str(f[1])).get("name", f[1])]
	return ""


## 받침 값(v0.5): 위에 덮인 층이 있는 건물을 헐 때 드는 돈. 덮인 층 수 × layers.demolish_per_floor × 그 건물의 값. 위에 아무것도 없으면 0.
func _demolish_cost(state: CityState, b: Dictionary) -> float:
	if b.is_empty():
		return 0.0
	var per := float(sim.cfg("layers.demolish_per_floor", 0.5))
	if per <= 0.0:
		return 0.0
	var depth := Cover.depth_of_b(state, b, sim.F)
	if depth <= 0:
		return 0.0
	var base := 0.0
	if b["kind"] == "house":
		var tab: Array = sim.cfg("hazards.repair.house_money", [30, 120, 500, 1500, 3000])
		base = float(tab[clampi(int(b.get("tier", 1)) - 1, 0, tab.size() - 1)])
	else:
		base = float(sim.bdef(str(b.get("type", ""))).get("cost", {}).get("money", 0))
	return ceilf(base * per * float(depth))


## 이 칸들에 지으면 아래 하늘 시설이 그늘에 드나(경고 문장).
func _shade_warning(state: CityState, cells: Array) -> String:
	for bid: int in sim.cover(state)["sky"]:
		var b: Dictionary = state.buildings.get(bid, {})
		if b.is_empty() or b.get("shade", false):
			continue
		var o: Vector3i = b["pos"]
		var k := Cover.dims(b)
		for p: Vector3i in cells:
			if p.x >= o.x and p.x < o.x + k.x and p.y >= o.y and p.y < o.y + k.y and p.z >= o.z + k.z:
				return Sim.kr("여기에 지으면 %s이(가) 그늘에 들어 멈춘다." % sim.bdef(str(b["type"])).get("name", ""))
	return ""


## _free_reason의 기계 코드: bounds | locked_floor | occupied | ok
func _free_code(state: CityState, p: Vector3i) -> String:
	if not _inside(p):
		return "bounds"
	if p.z >= state.floors_unlocked:
		return "locked_floor"
	if state.cells.has(p):
		return "occupied"
	return "ok"


## z층의 빈 w×h 자리 수(가능한 origin 수).
func _free_count(state: CityState, z: int, w: int, h: int) -> int:
	var n := 0
	for x: int in sim.W - w + 1:
		for y: int in sim.H - h + 1:
			var ok := true
			for dx: int in w:
				for dy: int in h:
					if state.cells.has(Vector3i(x + dx, y + dy, z)):
						ok = false
						break
				if not ok:
					break
			if ok:
				n += 1
	return n


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
	var rot := int(c["rot"])
	var w := int(c["w"])
	var h := int(c["h"])
	var dd := int(c["d"])
	_add_supports(state, c["support_cells"])
	state.money -= float(c["cost"]["money"])
	state.book("build", -float(c["cost"]["money"]))
	state.stat_add("spent_build", float(c["cost"]["money"]))
	for g: String in c["cost"]["goods"]:
		state.stock[g] = float(state.stock.get(g, 0.0)) - float(c["cost"]["goods"][g])
		state.stat_add("used." + g, float(c["cost"]["goods"][g]))
	var bid := state.new_id()
	var seed := sim.rand_seed(state)
	var days := sim.build_days(type)
	var look := str(d.get("look", ""))
	state.buildings[bid] = {"id": bid, "kind": "site", "type": type, "pos": pos, "size": maxi(w, h), "w": w, "h": h, "d": dd, "rot": rot,
		"progress": 0.0, "days": days, "build_left": days, "front": rot}
	for p: Vector3i in Cover.cells_of(pos, w, h, dd):
		state.cells[p] = {"kind": "site", "bid": bid, "type": type, "tier": 0, "material": "", "seed": seed, "look": look,
			"origin": pos, "size": maxi(w, h), "w": w, "h": h, "d": dd, "rot": rot, "front": rot, "scaffold": false, "progress": 0.0,
			"becomes": {"kind": "facility", "type": type, "w": w, "h": h, "d": dd, "rot": rot}, "burn": "", "sick": false, "trash": 0.0}
		state.emit("cell_changed", {"pos": p})
	state.emit("building_changed", {"bid": bid})
	state.layout_changed()
	return {"ok": true, "reason": "", "bid": bid, "supports": (c["support_cells"] as Array).size(), "build_days": days}


func _demolish(state: CityState, pos: Variant) -> Dictionary:
	var c := state.cell(pos)
	var bid := int(c["bid"])
	var b: Dictionary = state.buildings[bid]
	var cells := Cover.bcells(b)
	var dcost := _demolish_cost(state, b)
	if dcost > 0.0:
		state.money -= dcost
		state.book("build", -dcost)
		state.stat_add("spent_demolish", dcost)
		sim.say(state, "받침 값 %s을(를) 냈다(위에 %d개 층이 얹혀 있었다)." % [Sim.won(dcost), Cover.depth_of_b(state, b, sim.F)])
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
	state.stat_add("demolished", 1.0)
	state.layout_changed()
	return {"ok": true, "reason": ""}


# ------------------------------------------------------------------ 질의
func query(state: CityState, name: String, args: Dictionary) -> Variant:
	if name == "demolish_preview":
		return _demolish_preview(state, args.get("pos"))
	if name != "range_preview":
		return null
	var type := str(args.get("type", ""))
	var pos: Variant = args.get("pos", null)
	var d := sim.bdef(type)
	var rg := Cover.rng_of(d)
	if d.is_empty() or not (pos is Vector3i) or rg.is_empty():
		return {"cells": [], "by_floor": {}, "houses": 0, "text": "범위가 없는 시설이다."}
	var k := sim.fp(type, int(args.get("rot", 0)))
	var cells := Cover.range_cells(sim, pos, k.x, k.y, k.z, rg)
	var by := {}
	for p: Vector3i in cells:
		if not by.has(p.z):
			by[p.z] = []
		by[p.z].append(p)
	var n := 0
	for b: Dictionary in sim.cover(state)["houses"]:
		if Cover.reach(pos, k.x, k.y, k.z, rg, b["pos"]):
			n += 1
	return {"cells": cells, "by_floor": by, "houses": n, "text": "%s · 닿는 주거 %d채" % [Cover.range_text(rg), n]}


## 철거 미리보기(G4): {ok, title, lines:[String]} — 밀려나는 주민, 잃는 것, 골조가 남는지.
func _demolish_preview(state: CityState, pos: Variant) -> Dictionary:
	if not (pos is Vector3i) or not state.cells.has(pos):
		return {"ok": false, "title": "철거할 건물이 없다", "lines": []}
	var b: Dictionary = state.buildings.get(int(state.cells[pos]["bid"]), {})
	if b.is_empty():
		return {"ok": false, "title": "철거할 건물이 없다", "lines": []}
	var lines: Array = []
	var title := ""
	if b["kind"] == "house":
		var t := int(b["tier"])
		title = "%s의 집 철거" % sim.tname(t)
		if int(b["residents"]) > 0:
			lines.append("%s %d명이 빈집을 찾는다(%d일 안에 못 찾으면 떠난다)." % [sim.tname(t), int(b["residents"]), int(sim.cfg("upgrade.waiting_days", 3))])
		if t > 1:
			lines.append("%s 계층 집과 그 자재(환불 없음)를 잃는다." % sim.tname(t))
		var hc := _demolish_cost(state, b)
		lines.append("주거 철거는 돈이 들지 않는다." if hc <= 0.0 else "받침 %d층: 위에 층이 얹혀 있어 %s이(가) 든다." % [Cover.depth_of_b(state, b, sim.F), Sim.won(hc)])
	else:
		var d := sim.bdef(str(b["type"]))
		title = "%s 철거" % d.get("name", b["type"])
		var cost: Dictionary = d.get("cost", {})
		var parts: Array = [Sim.won(float(cost.get("money", 0)))]
		for g: String in cost.get("goods", {}):
			parts.append("%s %d" % [sim.gname(g), int(cost["goods"][g])])
		lines.append("건설비(%s)는 돌려받지 못한다." % ", ".join(parts))
		if d.has("range"):
			lines.append("범위 안 주거 %d채가 이 시설을 잃는다." % int(sim.cover(state).get("served", {}).get(int(b["id"]), 0)))
		if d.get("landmark", false):
			lines.append("명소다. 다시 세우려면 처음부터 비용이 든다.")
		if d.has("teams"):
			lines.append("회띠꾼 한 팀이 줄어든다(나가 있는 팀은 돌아와 짐을 푼 뒤 해산).")
		if d.has("contract_slots"):
			lines.append("계약 자리 %d개가 줄어든다." % int(d["contract_slots"]))
	if b["kind"] != "house":
		var fc := _demolish_cost(state, b)
		if fc > 0.0:
			lines.append("받침 %d층: 위에 층이 얹혀 있어 %s이(가) 더 든다." % [Cover.depth_of_b(state, b, sim.F), Sim.won(fc)])
	var above := false
	for p: Vector3i in Cover.bcells(b):
		if state.cells.has(p + Vector3i(0, 0, 1)) or state.supports.has(p + Vector3i(0, 0, 1)):
			above = true
	lines.append("위층이 있어 그 자리에 골조가 남는다." if above else "위에 아무것도 없어 빈 칸이 된다.")
	return {"ok": true, "title": title, "lines": lines}
