class_name Cover
extends RefCounted
## Cover — 배치에서만 나오는 파생 값(저장 안 함). 건물이 생기거나 없어질 때만 다시 만든다(state.layout_rev).
## v4 범위 = 사각형(체비쇼프): 발자국의 어느 칸에서든 max(|dx|,|dy|) ≤ r, 층은 시설의 가장 아래층 −down … 가장 위층 +up.
## 발자국: 시설 w×h칸, d개 층(origin = 최소 x,y,z). 주거는 1×1×1.
## 결과: {markets:{hbid:[fbid…]}, services:{hbid:{tag:[fbid…]}}, noise:{hbid:n}, served:{fbid:n},
##        warehouses:n, posts:n, teams:n, by_prio:[fbid…], houses:[주거 dict…](buildings 순서), facs:[완공 시설 dict…],
##        cls:{hbid:덮임 등급}, cls_mk/cls_sv/cls_noise:[등급별], vice:[음성 시설 bid…],
##        hz:{tag:{bid:[fbid…]}}(방재 범위 — 주거와 시설 모두, config hazards.tags), sky:[하늘이 필요한 시설 bid…],
##        v0.5: wh:[[fbid, 칸수, z]…](창고), wh_cells:n(창고 칸수 합), wh_floors:{z:true}(창고가 덮는 층), depth:{bid:위에 덮인 층 수},
##        gap:{hbid:빈 칸과 맞닿은 수(0..4)}, cls_depth/cls_gap:[등급별], org:{bid:"thirteen"|"yeonu"}(조직 시설)}
## 주의: houses/facs는 상태의 dict 참조다. 건물 dict를 통째로 바꾸는 코드는 반드시 state.layout_changed()를 부른다.


## 건물 b의 (w, h, d). 주거·옛 저장은 size로.
static func dims(b: Dictionary) -> Vector3i:
	if b.has("w"):
		return Vector3i(int(b["w"]), int(b["h"]), int(b.get("d", 1)))
	var s := int(b.get("size", 1))
	return Vector3i(s, s, 1)


static func cells_of(o: Vector3i, w: int, h: int, d: int = 1) -> Array:
	var out: Array = []
	for dz: int in d:
		for dx: int in w:
			for dy: int in h:
				out.append(Vector3i(o.x + dx, o.y + dy, o.z + dz))
	return out


## 건물이 차지하는 모든 칸.
static func bcells(b: Dictionary) -> Array:
	var k := dims(b)
	return cells_of(b["pos"], k.x, k.y, k.z)


## 옛 호환: 한 층 size×size.
static func footprint(origin: Vector3i, size: int) -> Array:
	return cells_of(origin, size, size, 1)


## 데이터의 range → {r, up, down} 또는 {}(범위 없음). 옛 정수 값은 {r, up 1, down 1}.
static func rng_of(d: Dictionary) -> Dictionary:
	var r: Variant = d.get("range", null)
	if r is Dictionary:
		return {"r": int(r.get("r", 0)), "up": int(r.get("up", 0)), "down": int(r.get("down", 0))}
	if r is float or r is int:
		return {"r": int(r), "up": 1, "down": 1}
	return {}


## 시설(o, w,h,d, 범위 rg)이 칸 p에 닿나.
static func reach(o: Vector3i, w: int, h: int, d: int, rg: Dictionary, p: Vector3i) -> bool:
	if p.z < o.z - int(rg["down"]) or p.z > o.z + d - 1 + int(rg["up"]):
		return false
	var dx := maxi(0, maxi(o.x - p.x, p.x - (o.x + w - 1)))
	var dy := maxi(0, maxi(o.y - p.y, p.y - (o.y + h - 1)))
	return maxi(dx, dy) <= int(rg["r"])


## 시설이 건물 b(여러 칸일 수 있음)의 어느 칸에든 닿나.
static func reach_b(o: Vector3i, w: int, h: int, d: int, rg: Dictionary, b: Dictionary) -> bool:
	var p: Vector3i = b["pos"]
	var k := dims(b)
	if p.z + k.z - 1 < o.z - int(rg["down"]) or p.z > o.z + d - 1 + int(rg["up"]):
		return false
	var dx := maxi(0, maxi(o.x - (p.x + k.x - 1), p.x - (o.x + w - 1)))
	var dy := maxi(0, maxi(o.y - (p.y + k.y - 1), p.y - (o.y + h - 1)))
	return maxi(dx, dy) <= int(rg["r"])


## 범위 안 칸들(미리보기용) — 부지 안, 층 0..F-1.
static func range_cells(sim: Sim, o: Vector3i, w: int, h: int, d: int, rg: Dictionary) -> Array:
	var out: Array = []
	if rg.is_empty():
		return out
	var r := int(rg["r"])
	for z: int in range(maxi(0, o.z - int(rg["down"])), mini(sim.F, o.z + d + int(rg["up"]))):
		for x: int in range(maxi(0, o.x - r), mini(sim.W, o.x + w + r)):
			for y: int in range(maxi(0, o.y - r), mini(sim.H, o.y + h + r)):
				out.append(Vector3i(x, y, z))
	return out


static func build(sim: Sim, state: CityState) -> Dictionary:
	var c := {"markets": {}, "services": {}, "noise": {}, "served": {}, "warehouses": 0, "posts": 0, "teams": 0,
		"by_prio": [], "houses": [], "facs": [], "cls": {}, "cls_mk": [], "cls_sv": [], "cls_noise": [], "cls_depth": [], "cls_gap": [], "vice": [], "wh": [], "wh_cells": 0, "wh_floors": {}, "depth": {}, "gap": {}, "org": {}, "ranged": [], "sites": [],
		"floor_houses": {}, "floor_fac_cells": {}, "hz": {}, "sky": [], "all": []}
	var ranged: Array = []      # [fbid, origin, w, h, d, rg, is_market, services(주거용), hz_tags]
	var noisy: Array = []
	var prio: Array = sim.cfg("workforce.priority", [])
	var hz_tags: Array = sim.cfg("hazards.tags", [])
	for t: String in hz_tags:
		c["hz"][t] = {}
	var buckets: Array = []
	for i: int in prio.size() + 1:
		buckets.append([])
	for bid: int in state.buildings:
		var b: Dictionary = state.buildings[bid]
		var bz: int = (b["pos"] as Vector3i).z
		if b["kind"] == "house":
			c["houses"].append(b)
			c["all"].append(b)
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
		c["all"].append(b)
		var k := dims(b)
		for dz: int in k.z:
			c["floor_fac_cells"][bz + dz] = int(c["floor_fac_cells"].get(bz + dz, 0)) + k.x * k.y
		var d := sim.bdef(str(b["type"]))
		if d.get("storage", false):
			c["warehouses"] += 1
			var sc := int(d.get("storage_cells", 2))
			c["wh"].append([bid, sc, bz])
			c["wh_cells"] += sc
			for zz: int in _wh_floors(sc, bz):
				c["wh_floors"][zz] = true
		if d.has("org"):
			c["org"][bid] = str(d["org"])
		c["posts"] += int(d.get("contract_slots", 0))
		c["teams"] += int(d.get("teams", 0))
		if d.has("vice") or "vice" in d.get("tags", []):
			c["vice"].append(bid)
		if d.get("needs_sky", false) or d.get("open_sky", false):
			c["sky"].append(bid)
		var rg := rng_of(d)
		if not rg.is_empty():
			var sv: Array = []
			var hz: Array = []
			for tg: String in d.get("services", []):
				if tg in hz_tags:
					hz.append(tg)
				else:
					sv.append(tg)
			ranged.append([bid, b["pos"], k.x, k.y, k.z, rg, d.has("market"), sv, hz])
			c["ranged"].append(b)
			c["served"][bid] = 0
		if "noise" in d.get("tags", []):
			noisy.append(b)
		var pi := prio.find(str(d.get("priority", "other")))
		buckets[pi if pi >= 0 else prio.size()].append(bid)
	for b2: Dictionary in c["all"]:
		c["depth"][int(b2["id"])] = depth_of_b(state, b2, sim.F)
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
	# 방재 범위(주거·시설 모두)
	for r: Array in ranged:
		if (r[8] as Array).is_empty():
			continue
		for b: Dictionary in c["all"]:
			if reach_b(r[1], r[2], r[3], r[4], r[5], b):
				for tg: String in r[8]:
					var m: Dictionary = c["hz"][tg]
					var bid := int(b["id"])
					if not m.has(bid):
						m[bid] = []
					m[bid].append(r[0])
	var cls_of := {}
	for h: Dictionary in c["houses"]:
		var hbid := int(h["id"])
		var pos: Vector3i = h["pos"]
		var mk: Array = []
		var sv: Dictionary = {}
		for r: Array in ranged:
			if (r[7] as Array).is_empty() and not r[6]:
				if not (r[8] as Array).is_empty() and reach(r[1], r[2], r[3], r[4], r[5], pos):
					c["served"][r[0]] += 1
				continue
			if not reach(r[1], r[2], r[3], r[4], r[5], pos):
				continue
			c["served"][r[0]] += 1
			if r[6]:
				mk.append(r[0])
			for tag: String in r[7]:
				if not sv.has(tag):
					sv[tag] = []
				sv[tag].append(r[0])
		c["markets"][hbid] = mk
		c["services"][hbid] = sv
		var n := 0
		for fb: Dictionary in noisy:
			var o: Vector3i = fb["pos"]
			var k := dims(fb)
			if pos.z >= o.z and pos.z < o.z + k.z and reach(o, k.x, k.y, 1, {"r": 1, "up": 0, "down": 0}, Vector3i(pos.x, pos.y, o.z)):
				n += 1
		c["noise"][hbid] = n
		# 같은 시장·서비스 접근 + 같은 소음 = 같은 "덮임 등급"(needs가 등급 단위로 한 번만 계산한다)
		var dep: int = c["depth"].get(hbid, 0)
		var gp := gap_count(state, pos, sim)
		c["gap"][hbid] = gp
		var key := "%s/%s/%d/%d/%d" % [str(mk), str(sv), n, dep, gp]
		var ci: int = cls_of.get(key, -1)
		if ci < 0:
			ci = (c["cls_mk"] as Array).size()
			cls_of[key] = ci
			c["cls_mk"].append(mk)
			c["cls_sv"].append(sv)
			c["cls_noise"].append(n)
			c["cls_depth"].append(dep)
			c["cls_gap"].append(gp)
		c["cls"][hbid] = ci
	return c


## 창고 칸수 → 덮는 층: 1칸 = 그 층, 2칸 = 그 층 + 위층, 4칸 = 위·아래 층까지.
static func _wh_floors(cells: int, z: int) -> Array:
	if cells >= 4:
		return [z - 1, z, z + 1]
	if cells >= 2:
		return [z, z + 1]
	return [z]


## 칸 하나 위에 덮인 층 수(v0.5): 같은 (x,y) 기둥에서 위쪽 층 중 건물 칸이나 골조가 있는 층의 수.
static func depth_of(state: CityState, p: Vector3i, floors: int) -> int:
	var n := 0
	for z: int in range(p.z + 1, floors):
		var q := Vector3i(p.x, p.y, z)
		if state.cells.has(q) or state.supports.has(q):
			n += 1
	return n


## 건물(여러 칸)의 덮인 층 수 = 발자국 칸 중 가장 큰 값(맨 위층 기준).
static func depth_of_b(state: CityState, b: Dictionary, floors: int) -> int:
	var k := dims(b)
	var top := (b["pos"] as Vector3i).z + k.z - 1
	var best := 0
	for dx: int in k.x:
		for dy: int in k.y:
			best = maxi(best, depth_of(state, Vector3i(b["pos"].x + dx, b["pos"].y + dy, top), floors))
	return best


## 주거 칸과 맞닿은(가로·세로 4방향) 같은 층의 빈 칸 수. 부지 밖은 세지 않는다.
static func gap_count(state: CityState, p: Vector3i, sim: Sim) -> int:
	var n := 0
	for dv: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var x := p.x + dv.x
		var y := p.y + dv.y
		if x < 0 or y < 0 or x >= sim.W or y >= sim.H:
			continue
		if not state.cells.has(Vector3i(x, y, p.z)):
			n += 1
	return n


## 쓰이는 칸 수(z층): 주민 1명 이상인 주거 + 완공 시설 칸(그 층에 걸친 칸). 빈 판잣집·공사장·골조만 있는 칸 = 0.
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
		if b["kind"] == "house":
			if p.z == z and int(b.get("residents", 0)) >= 1:
				n += 1
		elif b["kind"] == "facility":
			var k := dims(b)
			if z >= p.z and z < p.z + k.z:
				n += k.x * k.y
	return n


## 층 하나에서 다음 층을 여는 데 필요한 쓰이는 칸 수 = ceil(threshold × 부지 칸). eligible_cells가 0이면 W×H.
static func floor_need(sim: Sim) -> int:
	var cells := int(sim.cfg("floors.eligible_cells", 0))
	if cells <= 0:
		cells = sim.W * sim.H
	return int(ceilf(float(sim.cfg("floors.threshold", 0.8)) * float(cells) - 1e-6))


## "가로·세로 4칸, 위아래 1층" 같은 범위 문장.
static func range_text(rg: Dictionary) -> String:
	if rg.is_empty():
		return "범위 없음"
	var up := int(rg["up"])
	var dn := int(rg["down"])
	var z := ""
	if up == dn:
		z = "위아래 %d층" % up if up > 0 else "같은 층만"
	else:
		z = "위 %d층·아래 %d층" % [up, dn]
	return "가로·세로 %d칸, %s" % [int(rg["r"]), z]
