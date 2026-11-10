class_name Cover
extends RefCounted
## Cover — 배치에서만 나오는 파생 값(저장 안 함). 건물이 생기거나 없어질 때만 다시 만든다(state.layout_rev).
## 거리 = |dx| + |dy| + vertical_weight×|dz|, |dz| ≤ max_floor_delta. 2×2는 네 칸 중 가장 가까운 칸.
## 결과: {markets:{hbid:[fbid…]}, services:{hbid:{tag:[fbid…]}}, noise:{hbid:n}, served:{fbid:n},
##        warehouses:n, posts:n, teams:n, facilities_by_prio:[fbid…]}


static func dist(sim: Sim, a: Vector3i, origin: Vector3i, size: int) -> int:
	var dz := absi(a.z - origin.z)
	if dz > int(sim.cfg("distance.max_floor_delta", 2)):
		return 1 << 20
	var best := 1 << 20
	for dx: int in size:
		for dy: int in size:
			best = mini(best, absi(a.x - origin.x - dx) + absi(a.y - origin.y - dy))
	return best + int(sim.cfg("distance.vertical_weight", 2)) * dz


static func footprint(origin: Vector3i, size: int) -> Array:
	var out: Array = []
	for dx: int in size:
		for dy: int in size:
			out.append(Vector3i(origin.x + dx, origin.y + dy, origin.z))
	return out


## 범위 안 칸들(미리보기용).
static func range_cells(sim: Sim, origin: Vector3i, size: int, rng: int) -> Array:
	var out: Array = []
	var md := int(sim.cfg("distance.max_floor_delta", 2))
	for z: int in range(maxi(0, origin.z - md), mini(sim.F, origin.z + md + 1)):
		for x: int in sim.W:
			for y: int in sim.H:
				var p := Vector3i(x, y, z)
				if dist(sim, p, origin, size) <= rng:
					out.append(p)
	return out


static func build(sim: Sim, state: CityState) -> Dictionary:
	var c := {"markets": {}, "services": {}, "noise": {}, "served": {}, "warehouses": 0, "posts": 0, "teams": 0,
		"by_prio": []}
	var ranged: Array = []      # [fbid, def]
	var noisy: Array = []
	var prio: Array = sim.cfg("workforce.priority", [])
	var buckets: Array = []
	for i: int in prio.size() + 1:
		buckets.append([])
	for bid: int in state.buildings:
		var b: Dictionary = state.buildings[bid]
		if b["kind"] != "facility":
			continue
		var d := sim.bdef(str(b["type"]))
		if d.get("storage", false):
			c["warehouses"] += 1
		c["posts"] += int(d.get("contract_slots", 0))
		c["teams"] += int(d.get("teams", 0))
		if d.has("range"):
			ranged.append([bid, d])
			c["served"][bid] = 0
		if "noise" in d.get("tags", []):
			noisy.append(b)
		var pi := prio.find(str(d.get("priority", "other")))
		buckets[pi if pi >= 0 else prio.size()].append(bid)
	for bk: Array in buckets:
		c["by_prio"].append_array(bk)
	for hbid: int in state.buildings:
		var h: Dictionary = state.buildings[hbid]
		if h["kind"] != "house":
			continue
		var pos: Vector3i = h["pos"]
		var mk: Array = []
		var sv: Dictionary = {}
		for r: Array in ranged:
			var fb: Dictionary = state.buildings[r[0]]
			var d: Dictionary = r[1]
			if dist(sim, pos, fb["pos"], int(fb.get("size", 1))) > int(d["range"]):
				continue
			c["served"][r[0]] += 1
			if d.has("market"):
				mk.append(r[0])
			for tag: String in d.get("services", []):
				if not sv.has(tag):
					sv[tag] = []
				sv[tag].append(r[0])
		c["markets"][hbid] = mk
		c["services"][hbid] = sv
		var n := 0
		for fb: Dictionary in noisy:
			var o: Vector3i = fb["pos"]
			if o.z == pos.z and dist(sim, pos, o, int(fb.get("size", 1))) <= 1:
				n += 1
		c["noise"][hbid] = n
	return c


## 쓰이는 칸 수(z층): 주민 1명 이상인 주거 + 완공 시설 칸(2×2 = 4). 빈 판잣집·공사장·골조만 있는 칸 = 0.
static func used_cells(state: CityState, z: int) -> int:
	var n := 0
	for b: Dictionary in state.buildings.values():
		var p: Vector3i = b["pos"]
		if p.z != z:
			continue
		if b["kind"] == "house" and int(b.get("residents", 0)) >= 1:
			n += 1
		elif b["kind"] == "facility":
			n += int(b["size"]) * int(b["size"])
	return n
