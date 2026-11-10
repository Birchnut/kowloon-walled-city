class_name GrowthUpgrade
extends RefCounted
## GrowthUpgrade — 성장 시스템의 도우미(순수 함수): 자재 고르기, 고쳐 짓기, 쪽방 쪼개기.
##  · material(): 자재 정책(policies.json material의 materials 순서)대로, 재고(+materials_reserve)가 되면 그걸로, 안 되면 폐자재.
##    "되는대로"면 옆 칸이 쓰는 자재를 따라가고, 이웃이 없으면 재고가 넉넉할 때(any_rich) 벽돌, 아니면 any_default 중 하나.
##    콘크리트는 전기가 들어와야 쓴다(concrete_needs_power).
##  · one(): 고쳐 짓기 1건 — 판잣집 다시 짓기 / 단칸방→살림집(볕 flat_min_sun 이상, flat_cost) / 기둥을 막는 약한 칸 보강.
##  · densify(): 방 하나를 쪽방으로 쪼갠다(볕이 제일 안 드는 방부터).
## 수치: data/economy.json "growth".


static func _cost(sim: Sim, mat: String) -> float:
	return float(sim.item("materials", mat).get("cost", 0.0))


static func _can(sim: Sim, state: CityState, mat: String) -> bool:
	if mat == "concrete" and sim.tune("growth.concrete_needs_power", true) and state.power_level < 1:
		return false
	return state.materials >= _cost(sim, mat) + sim.num("growth.materials_reserve", 4.0)


static func material(sim: Sim, state: CityState, pos: Vector3i, _group: String) -> String:
	var pref: Array = sim.option("material", str(state.policies.get("material", ""))).get("materials", [])
	for mat: String in pref:
		if _can(sim, state, mat):
			return mat
	if not pref.is_empty():
		return "scrap"
	var votes := {}
	for d: Vector3i in Grid.N6:
		var c: Dictionary = state.cells.get(pos + d, {})
		if not c.is_empty():
			var mat := str(c.get("material", ""))
			votes[mat] = int(votes.get(mat, 0)) + (2 if d.z == -1 else 1)
	var best := ""
	var top := 0
	for mat: String in votes:
		if mat != "scrap" and int(votes[mat]) > top:
			top = votes[mat]
			best = mat
	if best != "" and _can(sim, state, best) and sim.roll(state) < sim.num("growth.any_follow", 0.75):
		return best
	if state.materials >= sim.num("growth.any_rich", 40.0) and _can(sim, state, "brick"):
		return "brick"
	var defaults: Array = sim.tune("growth.any_default", ["wood", "sheet"])
	var pick := str(defaults[sim.roll_range(state, 0, defaults.size() - 1)])
	return pick if _can(sim, state, pick) else "scrap"


## 지금 자재보다 센 것(정책 선호 먼저, 아니면 등급표 순서).
static func _stronger(sim: Sim, state: CityState, cur: String) -> String:
	var tier := int(sim.item("materials", cur).get("tier", 0))
	var order: Array = sim.option("material", str(state.policies.get("material", ""))).get("materials", []).duplicate()
	order.append_array(sim.tune("growth.reinforce_order", ["concrete", "brick", "sheet", "wood"]))
	for mat: String in order:
		if int(sim.item("materials", mat).get("tier", 0)) > tier and _can(sim, state, mat):
			return mat
	return ""


static func one(sim: Sim, state: CityState) -> bool:
	var floor_cap: int = mini(sim.F, int(state.flags.get("floor_cap", sim.F)))
	var cands: Array = []
	var w: Array = []
	var pressure := 1.0
	for h: Dictionary in state.households.values():
		if h.get("home") == null:
			pressure = 2.0
			break
	for x: int in sim.W:
		for y: int in sim.H:
			var h := Grid.height(sim, state, x, y)
			if h == 0 or h >= floor_cap or h < Grid.load_cap(sim, state, x, y):
				continue
			if sim.def_of(state.cells.get(Vector3i(x, y, h - 1), {})).get("open_sky", false):
				continue
			var weak := Vector3i(x, y, 0)
			var low := 999
			for z: int in h:
				var c: Dictionary = state.cells.get(Vector3i(x, y, z), {})
				var v := z + 1 + int(sim.item("materials", str(c.get("material", ""))).get("load", 99))
				if not c.is_empty() and c.get("kind", "") != "site" and v < low:
					low = v
					weak = Vector3i(x, y, z)
			if low < 999:
				cands.append({"pos": weak, "how": "reinforce"})
				w.append(sim.num("growth.reinforce_weight", 2.0) * pressure)
	for pos: Vector3i in state.cells:
		var c: Dictionary = state.cells[pos]
		if c.get("kind", "") != "housing" or (c.get("residents", []) as Array).is_empty():
			continue
		var d := sim.item("housing", str(c["type"]))
		if not d.has("upgrade_to") or state.day - int(c.get("built_day", 0)) < int(d.get("upgrade_days", 3)):
			continue
		if str(c["material"]) == "scrap":
			cands.append({"pos": pos, "how": "rebuild"})
			w.append(1.0)
		elif str(c["material"]) in d.get("upgrade_materials", []) and Grid.sunlight(sim, state, pos) >= sim.num("growth.flat_min_sun", 0.25):
			cands.append({"pos": pos, "how": "flat"})
			w.append(1.0)
	var i := sim.pick(state, w)
	if i < 0:
		return false
	var pos: Vector3i = cands[i]["pos"]
	var cell: Dictionary = state.cells[pos]
	var how := str(cands[i]["how"])
	if how == "flat":
		if state.materials < sim.num("growth.flat_cost", 2.0):
			return false
		state.materials -= sim.num("growth.flat_cost", 2.0)
		cell["type"] = str(sim.item("housing", str(cell["type"])).get("upgrade_to", "flat"))
	else:
		var mat := _stronger(sim, state, str(cell["material"]))
		if mat == "":
			return false
		state.materials -= _cost(sim, mat)
		cell["material"] = mat
		if cell["kind"] == "housing" and str(cell["type"]) == str(sim.tune("growth.housing_scrap", "shack")):
			cell["type"] = str(sim.tune("growth.housing_new", "room"))
		cell["renovated"] = state.day
	state.stats["upgrades"] = int(state.stats.get("upgrades", 0)) + 1
	state.emit("cell_changed", {"pos": pos})
	return true


static func cage_wanted(sim: Sim, state: CityState, need: int) -> bool:
	if state.flags.get("no_cage", false) or need < int(sim.num("growth.cage.pressure", 5)):
		return false
	if state.flags.get("cage_ok", false) or str(state.policies.get("intake", "")) == "workers":
		return true
	return state.notoriety >= sim.num("growth.cage.notoriety", 25.0) and str(state.policies.get("permit.vice", "ban")) != "ban"


static func densify(sim: Sim, state: CityState) -> bool:
	var best := Vector3i(-1, -1, -1)
	var dark := 2.0
	for pos: Vector3i in state.cells:
		var c: Dictionary = state.cells[pos]
		if c.get("kind", "") != "housing" or str(c["type"]) in ["cage", "flat"] or (c.get("residents", []) as Array).is_empty():
			continue
		var s := Grid.sunlight(sim, state, pos) + 0.2 * sim.roll(state)
		if s < dark:
			dark = s
			best = pos
	if best.x < 0:
		return false
	var cell: Dictionary = state.cells[best]
	cell["type"] = "cage"
	cell["why"] = str(sim.tune("growth.why.cage", "줄이 길어지자 집주인이 방을 철망으로 쪼갰다."))
	state.stats["cages"] = int(state.stats.get("cages", 0)) + 1
	state.emit("cell_changed", {"pos": best})
	if not state.flags.has("first_cage"):
		state.flags["first_cage"] = state.day
		sim.say(state, "대문 앞 줄이 길어지자 누군가 방 하나를 철망으로 넷으로 쪼갰다. 쪽방이 생겼다.", "bad")
	return true
