extends SimSystem
## 심기·긋기·철거 — 플레이어가 땅에 직접 하는 일 셋.
##  · plant {facility, pos}: 앵커(시설) 한 칸을 심는다. 지상 빈 칸이거나 기존 칸 바로 위. 첫 앵커(starter 3종)는 공짜,
##    그 뒤로는 값 × (1 + 이미 심은 수 × plots.cost_growth). 비워 둔(keep) 기둥·하늘을 열어 둬야 하는 칸 위에는 못 심는다.
##  · zone {col, zone}: 기둥에 housing / work / keep(비움) / ""(지움)을 칠한다. 이미 지어진 기둥은 keep으로 못 칠한다.
##  · demolish {pos}: 맨 위 칸만 철거(위에 얹힌 게 있으면 거부). 살던 가구는 대문 앞으로. 자재 일부 회수.
## 수치: data/economy.json "plots" (cost_growth, demolish_cost, salvage, facility_material) · 시설 값은 facilities.json cost.

const ZONES := {"housing": "주거", "work": "일터", "keep": "비움"}


func _cost(state: CityState, id: String) -> Dictionary:
	var d := sim.item("facilities", id)
	if d.get("starter", false) and int(state.stats.get("plants", 0)) == 0:
		return {"money": 0.0, "materials": 0.0}
	var k := 1.0 + sim.num("plots.cost_growth", 0.15) * float(int(state.stats.get("plants", 0)))
	var c: Dictionary = d.get("cost", {})
	return {"money": roundf(float(c.get("money", 0)) * k), "materials": roundf(float(c.get("materials", 0)) * k)}


func _spot_reason(state: CityState, d: Dictionary, pos: Vector3i) -> String:
	if not Grid.inside(sim, pos.x, pos.y) or pos.z < 0 or pos.z >= sim.F:
		return "부지 밖이다."
	if state.cells.has(pos):
		return "이미 뭔가 있는 칸이다."
	if state.zones.get(Vector2i(pos.x, pos.y), "") == "keep":
		return "비워 두기로 한 칸이다."
	if pos.z != Grid.height(sim, state, pos.x, pos.y):
		return "허공에는 못 심는다. 지상이거나 기존 칸 바로 위여야 한다."
	if pos.z > 0:
		var below: Dictionary = state.cells[pos + Vector3i(0, 0, -1)]
		if below.get("kind", "") == "site":
			return "아래 칸이 아직 공사 중이다."
		if sim.def_of(below).get("open_sky", false):
			return "아래 칸은 하늘을 열어 둬야 하는 곳이다."
		if pos.z >= Grid.load_cap(sim, state, pos.x, pos.y):
			return "아래 자재가 더는 못 버틴다."
	if str(d.get("place", "any")) == "roof" and pos.z < 1:
		return "지붕 위(2층 이상)에만 놓을 수 있다."
	return ""


func can(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"plant":
			var id := str(args.get("facility", ""))
			var d := sim.item("facilities", id)
			if d.is_empty():
				return {"ok": false, "reason": "그런 시설은 없다."}
			if not sim.is_unlocked(state, d.get("unlock")):
				return {"ok": false, "reason": "아직 심을 수 없다 — " + str(sim.item("unlocks", str(d["unlock"])).get("hint", "때가 아니다."))}
			var why := _spot_reason(state, d, args.get("pos", Vector3i(-1, -1, -1)))
			if why != "":
				return {"ok": false, "reason": why}
			var c := _cost(state, id)
			if state.money < float(c["money"]):
				return {"ok": false, "reason": "돈이 모자란다 (₩%d 필요)." % int(c["money"])}
			if state.materials < float(c["materials"]):
				return {"ok": false, "reason": "자재가 모자란다 (%d 필요)." % int(c["materials"])}
			return {"ok": true, "reason": ""}
		"zone":
			var col: Vector2i = args.get("col", Vector2i(-1, -1))
			var z := str(args.get("zone", ""))
			if not Grid.inside(sim, col.x, col.y):
				return {"ok": false, "reason": "부지 밖이다."}
			if z != "" and not ZONES.has(z):
				return {"ok": false, "reason": "그런 구획은 없다."}
			if z == "keep" and Grid.height(sim, state, col.x, col.y) > 0:
				return {"ok": false, "reason": "이미 지어진 칸이다. 비우려면 먼저 철거해야 한다."}
			return {"ok": true, "reason": ""}
		"demolish":
			var pos: Vector3i = args.get("pos", Vector3i(-1, -1, -1))
			if not state.cells.has(pos):
				return {"ok": false, "reason": "철거할 게 없다."}
			if state.cells.has(pos + Vector3i(0, 0, 1)):
				return {"ok": false, "reason": "위에 얹힌 게 있다. 위부터 걷어내야 한다."}
			for n: Vector3i in Grid.N4:
				var q := pos + n
				if state.cells.get(q, {}).get("cantilever", false) and not state.cells.has(q + Vector3i(0, 0, -1)) and _props(state, q) <= 1:
					return {"ok": false, "reason": "옆 칸이 여기 매달려 있다. 그쪽부터 걷어내야 한다."}
			if state.money < sim.num("plots.demolish_cost", 3.0):
				return {"ok": false, "reason": "철거할 품삯이 없다 (₩%d 필요)." % int(sim.num("plots.demolish_cost", 3.0))}
			return {"ok": true, "reason": ""}
	return null


func _props(state: CityState, pos: Vector3i) -> int:
	var n := 0
	for d: Vector3i in Grid.N4:
		if state.cells.has(pos + d):
			n += 1
	return n


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"plant":
			var id := str(args["facility"])
			var pos: Vector3i = args["pos"]
			var d := sim.item("facilities", id)
			var c := _cost(state, id)
			state.money -= float(c["money"])
			state.materials -= float(c["materials"])
			var pref: Array = sim.option("material", str(state.policies.get("material", ""))).get("materials", [])
			var mat := str(d.get("material", pref.back() if not pref.is_empty() else sim.tune("plots.facility_material", "wood")))
			var biz := Ops.open_business(sim, state, id, pos, true)
			Ops.set_cell(state, pos, {"kind": "facility", "type": id, "material": mat, "owner": 0, "anchor": biz,
				"built_day": state.day, "seed": sim.rand_seed(state), "why": "%s이 직접 심었다 (%d일째)." % [state.identity.get("title", "대장"), state.day]})
			state.stats["plants"] = int(state.stats.get("plants", 0)) + 1
			if not state.flags.has("first_plant"):
				state.flags["first_plant"] = id
			sim.say(state, "%s을(를) 심었다." % d.get("name", id), "plant")
			return {"ok": true, "reason": "", "cost": c}
		"zone":
			var col: Vector2i = args["col"]
			var z := str(args.get("zone", ""))
			if z == "":
				state.zones.erase(col)
			else:
				state.zones[col] = z
			state.emit("zone_changed", {"col": col})
			return {"ok": true, "reason": ""}
		"demolish":
			var pos: Vector3i = args["pos"]
			var cell: Dictionary = state.cells[pos]
			var d := sim.def_of(cell)
			var evicted: int = (cell.get("residents", []) as Array).size()
			state.money -= sim.num("plots.demolish_cost", 3.0)
			state.materials += float(sim.item("materials", str(cell.get("material", ""))).get("cost", 0)) * sim.num("plots.salvage", 0.5)
			Ops.remove_cell(state, pos)
			state.stats["demolished"] = int(state.stats.get("demolished", 0)) + 1
			state.morale = clampf(state.morale - float(evicted) * sim.num("plots.evict_morale", 1.0), 0.0, 100.0)
			var tail := (" 살던 %d가구가 대문 앞으로 나앉았다." % evicted) if evicted > 0 else ""
			sim.say(state, "%s을(를) 헐었다.%s" % [d.get("name", "칸"), tail], "demolish")
			return {"ok": true, "reason": "", "evicted": evicted}
	return null


func query(state: CityState, name: String, args: Dictionary) -> Variant:
	if name == "facilities":
		var out: Array = []
		var defs := sim.items("facilities")
		for id: String in defs:
			var d: Dictionary = defs[id]
			var locked := not sim.is_unlocked(state, d.get("unlock"))
			var c := _cost(state, id)
			out.append({"id": id, "name": d.get("name", id), "desc": d.get("desc", ""), "cost": c, "locked": locked,
				"lock_hint": str(sim.item("unlocks", str(d.get("unlock", ""))).get("hint", "")) if locked else "",
				"free": float(c["money"]) == 0.0 and float(c["materials"]) == 0.0,
				"affordable": state.money >= float(c["money"]) and state.materials >= float(c["materials"])})
		return out
	if name == "plant_spots":
		var d := sim.item("facilities", str(args.get("facility", "")))
		var spots: Array = []
		if d.is_empty():
			return spots
		for x: int in sim.W:
			for y: int in sim.H:
				var pos := Vector3i(x, y, Grid.height(sim, state, x, y))
				if _spot_reason(state, d, pos) == "":
					spots.append(pos)
		return spots
	return null


func describe(state: CityState, pos: Vector3i, cell: Dictionary, info: Dictionary) -> void:
	var zone := str(state.zones.get(Vector2i(pos.x, pos.y), ""))
	if zone != "":
		info["lines"].append("구획: %s" % ZONES.get(zone, zone))
	if cell.is_empty():
		if zone == "keep":
			info["title"] = "비워 둔 터"
			info["lines"].append("아무도 여기에 짓지 않는다. 볕과 바람이 지나가는 자리.")
		return
	var c: Dictionary = can(state, "demolish", {"pos": pos})
	info["actions"].append({"id": "demolish", "label": "철거", "cmd": "demolish", "args": {"pos": pos},
		"ok": c["ok"], "reason": c["reason"]})
