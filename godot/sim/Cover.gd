class_name Cover
extends RefCounted
## Cover — 배치에서만 나오는 파생 값(저장 안 함). 건물이 생기거나 없어질 때만 다시 만든다(state.layout_rev).
## 거리 = |dx| + |dy| + vertical_weight×|dz|, |dz| ≤ max_floor_delta. 2×2는 네 칸 중 가장 가까운 칸.
## 결과: {markets:{hbid:[fbid…]}, services:{hbid:{tag:[fbid…]}}, noise:{hbid:n}, served:{fbid:n},
##        warehouses:n, posts:n, teams:n, by_prio:[fbid…], houses:[주거 dict…](buildings 순서), facs:[완공 시설 dict…],
##        cls:{hbid:덮임 등급}, cls_mk/cls_sv/cls_noise:[등급별], vice:[음성 시설 bid…]}
## 주의: houses/facs는 상태의 dict 참조다. 건물 dict를 통째로 바꾸는 코드는 반드시 state.layout_changed()를 부른다.


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
		"by_prio": [], "houses": [], "facs": [], "cls": {}, "cls_mk": [], "cls_sv": [], "cls_noise": [], "vice": [], "ranged": [], "sites": [], "floor_houses": {}, "floor_fac_cells": {}}
	var ranged: Array = []      # [fbid, def, origin, size, range, is_market, services]
	var noisy: Array = []
	var prio: Array = sim.cfg("workforce.priority", [])
	var buckets: Array = []
	for i: int in prio.size() + 1:
		buckets.append([])
	var vw := int(sim.cfg("distance.vertical_weight", 2))
	var md := int(sim.cfg("distance.max_floor_delta", 2))
	for bid: int in state.buildings:
		var b: Dictionary = state.buildings[bid]
		var bz: int = (b["pos"] as Vector3i).z
		if b["kind"] == "house":
			c["houses"].append(b)
			if not c["floor_houses"].has(bz):
				c["floor_houses"][bz] = []
			c["floor_houses"][bz].append(b)
			continue
		if b["kind"] == "site":
			c["sites"].append(bid)
			continue
		if b["kind"] != "facility":
			continue
		c["facs"].append(b)
		c["floor_fac_cells"][bz] = int(c["floor_fac_cells"].get(bz, 0)) + int(b["size"]) * int(b["size"])
		var d := sim.bdef(str(b["type"]))
		if d.get("storage", false):
			c["warehouses"] += 1
		c["posts"] += int(d.get("contract_slots", 0))
		c["teams"] += int(d.get("teams", 0))
		if d.has("vice") or "vice" in d.get("tags", []):
			c["vice"].append(bid)
		if d.has("range"):
			ranged.append([bid, d, b["pos"], int(b.get("size", 1)), int(d["range"]), d.has("market"), d.get("services", [])])
			c["ranged"].append(b)
			c["served"][bid] = 0
		if "noise" in d.get("tags", []):
			noisy.append(b)
		var pi := prio.find(str(d.get("priority", "other")))
		buckets[pi if pi >= 0 else prio.size()].append(bid)
	for bk: Array in buckets:
		c["by_prio"].append_array(bk)
	# 우선순위 묶음(같은 순위끼리, 순위 순서): [[순위 이름, [시설 정보…]]…]
	# 시설 정보 = [b, 물 공급, 전기 공급, 물 사용, 전기 사용, [[계층, 인원]…], 유지비]
	var gi := {}
	c["groups"] = []
	for bid: int in c["by_prio"]:
		var b: Dictionary = state.buildings[bid]
		var d := sim.bdef(str(b["type"]))
		var p := str(d.get("priority", "other"))
		if not gi.has(p):
			gi[p] = (c["groups"] as Array).size()
			c["groups"].append([p, []])
		var wf: Array = []
		for tk: String in d.get("workforce", {}):
			wf.append([int(tk.substr(1)), float(d["workforce"][tk])])
		var sup: Dictionary = d.get("supply", {})
		c["groups"][gi[p]][1].append([b, float(sup.get("water", 0.0)), float(sup.get("power", 0.0)), float(d.get("water", 0.0)),
			float(d.get("power", 0.0)), wf, float(d.get("upkeep", 0.0))])
	var cls_of := {}
	for h: Dictionary in c["houses"]:
		var hbid := int(h["id"])
		var pos: Vector3i = h["pos"]
		var mk: Array = []
		var sv: Dictionary = {}
		for r: Array in ranged:
			var o: Vector3i = r[2]
			var dz := absi(pos.z - o.z)
			if dz > md:
				continue
			var sz: int = r[3]
			var dx := maxi(0, maxi(o.x - pos.x, pos.x - (o.x + sz - 1)))
			var dy := maxi(0, maxi(o.y - pos.y, pos.y - (o.y + sz - 1)))
			if dx + dy + vw * dz > int(r[4]):
				continue
			c["served"][r[0]] += 1
			if r[5]:
				mk.append(r[0])
			for tag: String in r[6]:
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
		# 같은 시장·서비스 접근 + 같은 소음 = 같은 "덮임 등급"(needs가 등급 단위로 한 번만 계산한다)
		var key := "%s/%s/%d" % [str(mk), str(sv), n]
		var ci: int = cls_of.get(key, -1)
		if ci < 0:
			ci = (c["cls_mk"] as Array).size()
			cls_of[key] = ci
			c["cls_mk"].append(mk)
			c["cls_sv"].append(sv)
			c["cls_noise"].append(n)
		c["cls"][hbid] = ci
	return c


## 쓰이는 칸 수(z층): 주민 1명 이상인 주거 + 완공 시설 칸(2×2 = 4). 빈 판잣집·공사장·골조만 있는 칸 = 0.
static func used_cells_fast(sim: Sim, state: CityState, z: int) -> int:
	var c := sim.cover(state)
	var n: int = c["floor_fac_cells"].get(z, 0)
	for b: Dictionary in c["floor_houses"].get(z, []):
		if int(b["residents"]) >= 1:
			n += 1
	return n


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
