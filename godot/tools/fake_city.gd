class_name FakeCity
extends RefCounted
## FakeCity — 시뮬 없이 "그럴듯한" CityState를 만든다(아트 판정용). 순수 함수, seed 결정론.
## 프리셋: day1, day7, day30_mixed, day30_wood_farm, day30_neon_vice, day30_factory
## 셀 계약은 docs/ARCHITECTURE.md 그대로. 콘텐츠 id는 data/*.json 카탈로그의 것만 쓴다.

const PRESETS := ["day1", "day7", "day30_mixed", "day30_wood_farm", "day30_neon_vice", "day30_factory"]

const P := {
	"day7": {
		"day": 7, "max_h": 3, "towers": 3, "peak": [2, 3], "slope": 1.1, "noise": 1.0, "cut": 0.45, "power": 0,
		"mats": {"scrap": 6, "wood": 3, "sheet": 2}, "old": "scrap",
		"housing": {"shack": 6, "room": 3},
		"ground_biz": 0.3, "upper_biz": 0.05,
		"biz": {"noodle_shop": 2, "tailor": 1, "repair_shop": 1, "herb_shop": 1, "teahouse": 1},
		"ground_fac": {"well": 1, "kitchen": 1, "stall": 1, "garden": 2, "scrapyard": 1},
		"roof": {"rooftop_farm": 0.1}, "sites": 4, "waiting": 5, "alleys": 0, "courts": 1,
		"people": {"laborer": 4, "farmer": 2, "merchant": 2, "dependent": 2, "artisan": 1},
		"title": "대장", "epithet": "판자와 솥단지의 마당"
	},
	"day30_mixed": {
		"day": 30, "max_h": 10, "towers": 6, "peak": [5, 10], "slope": 1.5, "noise": 1.6, "cut": 0.12, "power": 1,
		"mats": {"concrete": 4, "brick": 3, "sheet": 2, "wood": 2, "scrap": 1}, "old": "wood",
		"housing": {"room": 5, "flat": 3, "cage": 2, "shack": 1},
		"ground_biz": 0.6, "upper_biz": 0.16,
		"biz": {"noodle_shop": 3, "teahouse": 2, "mahjong": 2, "dentist": 3, "tailor": 2, "fishball": 2, "noodle_works": 1, "repair_shop": 2, "herb_shop": 1, "karaoke": 1, "bathhouse": 1, "loan_office": 1, "metal_shop": 1},
		"ground_fac": {"well": 1, "kitchen": 1, "stall": 1, "generator": 1, "shrine": 1, "garden": 1, "night_stall": 2, "clinic": 1, "hall": 1},
		"roof": {"rooftop_farm": 0.12, "pigeon_loft": 0.05, "water_tank": 0.08, "fish_tank": 0.03}, "sites": 5, "waiting": 6, "alleys": 1, "courts": 2,
		"people": {"laborer": 4, "farmer": 1, "merchant": 3, "dependent": 2, "artisan": 2, "hustler": 1},
		"title": "따거", "epithet": "천 개의 창과 어묵 냄새"
	},
	"day30_wood_farm": {
		"day": 30, "max_h": 7, "towers": 5, "peak": [3, 7], "slope": 1.25, "noise": 1.5, "cut": 0.3, "power": 0,
		"mats": {"wood": 8, "scrap": 2, "brick": 1}, "old": "wood",
		"housing": {"room": 4, "flat": 4, "shack": 3},
		"ground_biz": 0.3, "upper_biz": 0.07,
		"biz": {"herb_shop": 3, "teahouse": 3, "mushroom_room": 2, "noodle_shop": 2, "tailor": 1},
		"ground_fac": {"garden": 9, "well": 2, "kitchen": 2, "shrine": 2, "hall": 1, "stall": 1},
		"roof": {"rooftop_farm": 0.42, "pigeon_loft": 0.12, "fish_tank": 0.06, "water_tank": 0.04}, "sites": 4, "waiting": 4, "alleys": 0, "courts": 3,
		"people": {"farmer": 6, "laborer": 2, "dependent": 3, "artisan": 1, "merchant": 1},
		"title": "촌장", "epithet": "비둘기와 상추의 옥상"
	},
	"day30_neon_vice": {
		"day": 30, "max_h": 10, "towers": 7, "peak": [7, 10], "slope": 1.2, "noise": 1.8, "cut": 0.06, "power": 2,
		"mats": {"concrete": 7, "brick": 3, "sheet": 1}, "old": "brick",
		"housing": {"room": 4, "cage": 4, "flat": 2},
		"ground_biz": 0.85, "upper_biz": 0.3,
		"biz": {"dentist": 6, "mahjong": 4, "karaoke": 4, "casino": 3, "loan_office": 2, "gambling_den": 2, "phishing_center": 3, "noodle_shop": 2, "bathhouse": 1, "night_stall": 0, "fireworks": 1, "repair_shop": 1},
		"ground_fac": {"night_stall": 4, "generator": 1, "watch_post": 1, "well": 1, "shrine": 1, "stall": 2, "clinic": 1},
		"roof": {"water_tank": 0.12, "pigeon_loft": 0.02}, "sites": 5, "waiting": 8, "alleys": 2, "courts": 1,
		"people": {"hustler": 5, "merchant": 4, "laborer": 3, "dependent": 2, "artisan": 1},
		"title": "회장", "epithet": "천 개의 치과와 잠들지 않는 마작"
	},
	"day30_factory": {
		"day": 30, "max_h": 8, "towers": 5, "peak": [5, 8], "slope": 0.9, "noise": 1.3, "cut": 0.1, "power": 1,
		"mats": {"sheet": 7, "concrete": 2, "brick": 2, "scrap": 1}, "old": "sheet",
		"housing": {"cage": 6, "room": 3, "shack": 2},
		"ground_biz": 0.75, "upper_biz": 0.22,
		"biz": {"fishball": 6, "noodle_works": 5, "metal_shop": 4, "plastic_works": 3, "tailor": 3, "repair_shop": 1, "noodle_shop": 1},
		"ground_fac": {"scrapyard": 3, "generator": 2, "well": 1, "kitchen": 2, "watch_post": 1},
		"roof": {"water_tank": 0.2, "rooftop_farm": 0.03}, "sites": 6, "waiting": 7, "alleys": 1, "courts": 1,
		"people": {"laborer": 7, "artisan": 3, "dependent": 2, "merchant": 1},
		"title": "공장장", "epithet": "어묵 냄새 나는 함석 미궁"
	}
}

const COLLECT_FAC := ["well", "kitchen", "stall", "generator", "shrine", "hall", "garden", "scrapyard", "night_stall", "clinic"]
const OPEN_FAC := ["garden", "scrapyard", "stall", "well", "generator", "shrine", "night_stall"]
const MULTI := {"casino": 3, "fishball": 2, "phishing_center": 2, "noodle_works": 2, "bathhouse": 2, "metal_shop": 2}


class Rng:
	var s: int
	func _init(seed_v: int) -> void:
		s = (seed_v * 2654435761 + 97) & 0x7fffffff
		if s == 0:
			s = 1
	func f() -> float:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		return float((s >> 8) % 1000000) / 1000000.0
	func i(n: int) -> int:
		return int(f() * n) % maxi(n, 1)
	func pick(w: Dictionary) -> String:
		var tot := 0.0
		for k in w:
			tot += float(w[k])
		var r := f() * tot
		for k in w:
			r -= float(w[k])
			if r < 0.0:
				return str(k)
		return str(w.keys()[0]) if not w.is_empty() else ""


static func build(preset: String, seed_v: int = 1, grid: Vector3i = Vector3i(12, 12, 10)) -> CityState:
	var s := CityState.new()
	s.rng_seed = seed_v
	s.rng_state = seed_v
	s.hour = 9.0
	s.money = 300.0
	s.food = 40.0
	s.materials = 25.0
	s.policies = {}
	var r := Rng.new(seed_v * 31 + preset.hash() % 9973)
	if preset == "day1" or not P.has(preset):
		_day1(s, r, grid)
		return s
	var p: Dictionary = P[preset]
	s.day = int(p["day"])
	s.power_level = int(p["power"])
	s.water_cap = 400
	s.prestige = 30.0
	s.notoriety = 60.0 if preset == "day30_neon_vice" else 15.0
	s.identity = {"title": p["title"], "epithet": p["epithet"], "tags": []}
	var gw := grid.x
	var gh := grid.y
	var max_h: int = mini(int(p["max_h"]), grid.z)

	# ── 1. 높이장 ──
	var towers: Array = []
	for i in int(p["towers"]):
		var pk: Array = p["peak"]
		towers.append([1.0 + r.f() * float(gw - 2), 1.0 + r.f() * float(gh - 2), float(pk[0]) + r.f() * float(int(pk[1]) - int(pk[0]) + 1), float(p["slope"]) * (0.7 + 0.6 * r.f())])
	towers[0][2] = float(max_h) + 0.9
	var hmap: Dictionary = {}
	var tower_of: Dictionary = {}
	for x in gw:
		for y in gh:
			var best := -9.0
			var bi := 0
			for i in towers.size():
				var t: Array = towers[i]
				var dd := absf(float(x) + 0.5 - float(t[0])) + absf(float(y) + 0.5 - float(t[1])) * 0.9
				var hv := float(t[2]) - dd * float(t[3])
				if hv > best:
					best = hv
					bi = i
			var n := (r.f() - 0.5) * 2.0 * float(p["noise"])
			var hh := int(round(best + n))
			if r.f() < float(p["cut"]):
				hh = 0
			hmap[Vector2i(x, y)] = clampi(hh, 0, max_h)
			tower_of[Vector2i(x, y)] = bi
	# 골목(1칸 틈) — 다리가 걸릴 자리
	for i in int(p["alleys"]):
		if r.i(2) == 0:
			var ax := 2 + r.i(gw - 4)
			for y in gh:
				if r.f() < 0.85:
					hmap[Vector2i(ax, y)] = 0
		else:
			var ay := 2 + r.i(gh - 4)
			for x in gw:
				if r.f() < 0.85:
					hmap[Vector2i(x, ay)] = 0
	# 마당(비움)
	for i in int(p["courts"]):
		var cx := 1 + r.i(gw - 3)
		var cy := 1 + r.i(gh - 3)
		var cw := 1 + r.i(2)
		var ch := 1 + r.i(2)
		for x in range(cx, cx + cw + 1):
			for y in range(cy, cy + ch + 1):
				hmap[Vector2i(x, y)] = 0
				if r.f() < 0.7:
					s.zones[Vector2i(x, y)] = "keep"
	# 대문 앞은 비워 둔다
	for x in range(gw / 2 - 1, gw / 2 + 1):
		hmap[Vector2i(x, gh - 1)] = 0
	# 최고층 하나는 보장
	if int(p["day"]) >= 30:
		var tc := Vector2i(clampi(int(towers[0][0]), 0, gw - 1), clampi(int(towers[0][1]), 0, gh - 2))
		hmap[tc] = max_h
		for d in [Vector2i(1, 0), Vector2i(0, -1)]:
			var q: Vector2i = tc + d
			if q.x >= 0 and q.y >= 0 and q.x < gw and q.y < gh - 1 and int(hmap[q]) < max_h - 2:
				hmap[q] = max_h - 1 - r.i(2)

	# ── 2. 탑마다 자재 ──
	var tmat: Array = []
	for i in towers.size():
		tmat.append(r.pick(p["mats"]))

	# ── 3. 셀 채우기 ──
	var biz_at: Dictionary = {}     # Vector3i -> biz id
	for x in gw:
		for y in gh:
			var col := Vector2i(x, y)
			var h: int = int(hmap[col])
			var roof_extra := ""
			if h > 0 and h < grid.z:
				var rw: Dictionary = p["roof"]
				for k in rw:
					if r.f() < float(rw[k]):
						roof_extra = str(k)
						break
			for z in h:
				var pos := Vector3i(x, y, z)
				var mat: String = tmat[int(tower_of[col])]
				if z < 2 and r.f() < 0.55:
					mat = str(p["old"])
				elif r.f() < 0.14:
					mat = r.pick(p["mats"])
				var built := maxi(1, int(p["day"]) - int(float(h - z) * 2.6 + r.f() * 5.0) - 1)
				var cell := {"material": mat, "built_day": built, "seed": r.i(1000000)}
				var bp: float = float(p["ground_biz"]) if z == 0 else float(p["upper_biz"])
				if biz_at.has(pos):
					var bid: int = int(biz_at[pos])
					cell["kind"] = "business"
					cell["type"] = s.businesses[bid]["type"]
					cell["owner"] = bid
					s.businesses[bid]["cells"].append(pos)
				elif r.f() < bp:
					var bt := r.pick(p["biz"])
					if z >= 1 and bt in ["casino", "bathhouse", "fishball", "noodle_works", "metal_shop", "noodle_shop"] and r.f() < 0.75:
						bt = r.pick(p["biz"])
					var bid2 := s.new_id()
					var grp := "fun"
					s.businesses[bid2] = {"id": bid2, "type": bt, "group": _group(bt), "cells": [pos], "workers": [], "opened_day": built}
					cell["kind"] = "business"
					cell["type"] = bt
					cell["owner"] = bid2
					# 여러 칸짜리 사업체: 옆 칸 예약
					var want: int = int(MULTI.get(bt, 1)) - 1
					for d in [Vector3i(1, 0, 0), Vector3i(0, 1, 0)]:
						if want <= 0:
							break
						var q2: Vector3i = pos + d
						if q2.x < gw and q2.y < gh and int(hmap.get(Vector2i(q2.x, q2.y), 0)) > z and not biz_at.has(q2):
							biz_at[q2] = bid2
							want -= 1
				else:
					cell["kind"] = "housing"
					cell["type"] = r.pick(p["housing"])
					if z == 0 and cell["type"] == "flat":
						cell["type"] = "room"
					if r.f() < 0.07:
						cell["owner"] = 0
					else:
						var hid := s.new_id()
						var ht := r.pick(p["people"])
						s.households[hid] = {"id": hid, "type": ht, "size": 1 + r.i(5), "home": pos, "job": 0, "named": "", "arrived_day": built}
						cell["owner"] = hid
				s.cells[pos] = cell
			if roof_extra != "":
				var rp := Vector3i(x, y, h)
				var kind := "facility" if roof_extra == "water_tank" else "business"
				var owner := 0
				if kind == "business":
					owner = s.new_id()
					s.businesses[owner] = {"id": owner, "type": roof_extra, "group": "farm", "cells": [rp], "workers": [], "opened_day": int(p["day"]) - r.i(10)}
				s.cells[rp] = {"kind": kind, "type": roof_extra, "material": tmat[int(tower_of[col])], "owner": owner, "built_day": int(p["day"]) - r.i(10), "seed": r.i(1000000)}

	# ── 4. 지상 시설(빈 땅에) ──
	var empties: Array = []
	for x in gw:
		for y in gh:
			if int(hmap[Vector2i(x, y)]) == 0 and not s.cells.has(Vector3i(x, y, 0)):
				empties.append(Vector2i(x, y))
	_shuffle(empties, r)
	var gf: Dictionary = p["ground_fac"]
	var placed := 0
	for k in gf:
		for i in int(gf[k]):
			var spot := Vector2i(-1, -1)
			for e_i in empties.size():
				var e: Vector2i = empties[e_i]
				if e.y == gh - 1 and absi(e.x - gw / 2) <= 1:
					continue
				if s.zones.get(e, "") == "keep" and r.f() < 0.8:
					continue
				var near := _has_neighbor(s, e)
				if str(k) in OPEN_FAC:
					if not near and r.f() < 0.5 and str(k) != "garden":
						continue
				elif not near:
					continue
				spot = e
				empties.remove_at(e_i)
				break
			if spot.x < 0:
				continue
			var fp := Vector3i(spot.x, spot.y, 0)
			var fmat := str(p["old"])
			if str(k) == "night_stall":
				var nb_id := s.new_id()
				s.businesses[nb_id] = {"id": nb_id, "type": "night_stall", "group": "fun", "cells": [fp], "workers": [], "opened_day": int(p["day"]) - 3}
				s.cells[fp] = {"kind": "business", "type": "night_stall", "material": fmat, "owner": nb_id, "built_day": int(p["day"]) - 3, "seed": r.i(1000000)}
			else:
				s.cells[fp] = {"kind": "facility", "type": str(k), "material": fmat, "owner": 0, "built_day": maxi(1, int(p["day"]) - 10 - r.i(15)), "seed": r.i(1000000)}
			placed += 1
	# 건물 안 시설(상자형)도 수금 지점이 된다
	var cid := 1
	for pos in s.cells:
		var c: Dictionary = s.cells[pos]
		if c["kind"] == "facility" and str(c["type"]) in COLLECT_FAC:
			var cap := 60.0 + float(r.i(8)) * 20.0
			var amt := cap * r.f()
			if r.f() < 0.3:
				amt = cap
			s.collect_points[cid] = {"id": cid, "pos": pos, "amount": amt, "cap": cap, "skimmed": cap * 0.2 * r.f()}
			cid += 1

	# ── 5. 공사 중 ──
	var cols: Array = hmap.keys()
	_shuffle(cols, r)
	var ns := 0
	for col in cols:
		if ns >= int(p["sites"]):
			break
		var h2: int = int(hmap[col])
		var sp := Vector3i(col.x, col.y, h2)
		if s.cells.has(sp) or h2 >= max_h:
			continue
		if h2 == 0 and (not _has_neighbor(s, col) or s.zones.has(col)):
			continue
		if col.y == gh - 1 and absi(col.x - gw / 2) <= 1:
			continue
		var bm := r.pick(p["mats"])
		s.cells[sp] = {"kind": "site", "type": "", "material": bm, "owner": 0, "built_day": int(p["day"]), "seed": r.i(1000000),
			"progress": 0.15 + 0.8 * r.f(), "becomes": {"kind": "housing", "type": r.pick(p["housing"]), "material": bm, "owner": 0}}
		ns += 1

	# ── 6. 일자리·대기 가구·구획 ──
	var bids: Array = s.businesses.keys()
	for hid in s.households:
		if not bids.is_empty() and r.f() < 0.6:
			var b: int = bids[r.i(bids.size())]
			s.households[hid]["job"] = b
			s.businesses[b]["workers"].append(hid)
	for i in int(p["waiting"]):
		var wid := s.new_id()
		s.households[wid] = {"id": wid, "type": r.pick(p["people"]), "size": 1 + r.i(5), "home": null, "job": 0, "named": "", "arrived_day": int(p["day"])}
	for i in 5:
		var zc := Vector2i(r.i(gw), r.i(gh))
		if not s.zones.has(zc):
			s.zones[zc] = "housing" if r.i(2) == 0 else "work"
	s.alley_fund = 120.0 * r.f()
	return s


static func _group(bt: String) -> String:
	if bt in ["rooftop_farm", "pigeon_loft", "fish_tank", "mushroom_room", "herb_shop"]:
		return "farm"
	if bt in ["fishball", "noodle_works", "tailor", "metal_shop", "plastic_works", "repair_shop"]:
		return "make"
	if bt in ["dentist", "loan_office", "gambling_den", "phishing_center", "casino", "fireworks"]:
		return "vice"
	return "fun"


static func _has_neighbor(s: CityState, c: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if s.cells.has(Vector3i(c.x + d.x, c.y + d.y, 0)):
			return true
	return false


static func _shuffle(a: Array, r: Rng) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := r.i(i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


static func _day1(s: CityState, r: Rng, grid: Vector3i) -> void:
	s.day = 1
	s.hour = 8.0
	s.power_level = 0
	s.water_cap = 10
	s.identity = {"title": "대장", "epithet": "", "tags": []}
	var cx := grid.x / 2 - 1
	var cy := grid.y / 2
	var hid := s.new_id()
	var home := Vector3i(cx, cy, 0)
	s.households[hid] = {"id": hid, "type": "laborer", "size": 3, "home": home, "job": 0, "named": "", "arrived_day": 1}
	s.cells[home] = {"kind": "housing", "type": "shack", "material": "scrap", "owner": hid, "built_day": 1, "seed": r.i(1000000)}
	var first: String = ["garden", "scrapyard", "stall"][r.i(3)]
	var fp := Vector3i(cx + 1, cy + 1, 0)
	s.cells[fp] = {"kind": "facility", "type": first, "material": "scrap", "owner": 0, "built_day": 1, "seed": r.i(1000000)}
	s.collect_points[1] = {"id": 1, "pos": fp, "amount": 12.0, "cap": 40.0, "skimmed": 0.0}
	var sp := Vector3i(cx - 1, cy, 0)
	s.cells[sp] = {"kind": "site", "type": "", "material": "scrap", "owner": 0, "built_day": 1, "seed": r.i(1000000), "progress": 0.4,
		"becomes": {"kind": "housing", "type": "shack", "material": "scrap", "owner": 0}}
	for i in 2:
		var wid := s.new_id()
		s.households[wid] = {"id": wid, "type": ["farmer", "merchant", "dependent"][r.i(3)], "size": 1 + r.i(4), "home": null, "job": 0, "named": "", "arrived_day": 1}
