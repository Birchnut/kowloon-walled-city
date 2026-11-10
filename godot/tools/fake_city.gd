class_name FakeCity
extends RefCounted
## FakeCity v3 — 시뮬 없이 계약 모양(docs/ARCHITECTURE.md)의 CityState를 만든다(아트 판정용). 순수 함수, seed 결정론.
## 쓰는 필드: cells, supports, buildings, floors_unlocked, day, hour — 그 밖은 건드리지 않는다.
## 프리셋: early, mid, late_wood, late_metal, late_concrete, late_mixed, matrix(계층×자재 표본)
## 시설 id는 data/art/visuals.json > types 의 것을 쓴다(시뮬의 buildings.json이 정해지면 같은 이름을 쓰기로).

const PRESETS := ["early", "mid", "late_wood", "late_metal", "late_concrete", "late_mixed", "matrix"]
const CAP := {1: 4, 2: 8, 3: 12, 4: 8, 5: 6}
const FAMILIES := ["wood", "metal", "concrete"]

const P := {
	"early": {
		"day": 4, "max_h": 1, "towers": 0, "fill": 0.5, "void": 0.0,
		"tiers": [1], "fam": "none",
		"f1": {"stall": 2, "rain_catcher": 3, "garden": 2, "expedition_post": 1, "shrine": 1, "warehouse": 1},
		"f2": [], "roof": {}, "sites": 2, "scaffold": 0.0, "bad": 0.15, "upg": 0.2, "off": 0.0
	},
	"mid": {
		"day": 14, "max_h": 4, "towers": 4, "fill": 0.8, "void": 0.22,
		"tiers": [1, 1, 2, 2, 2, 3, 3], "fam": "two", "fams": ["wood", "concrete"],
		"f1": {"stall": 2, "noodle_works": 1, "sewing_shop": 1, "candle_shop": 1, "teahouse": 1, "mahjong": 1, "water_tower": 1, "rain_catcher": 2, "generator": 1, "shrine": 1, "warehouse": 1, "expedition_post": 1, "trade_post": 1, "dentist": 1, "soap_shop": 1},
		"f2": ["market_basic"], "roof": {"garden": 0.15, "rain_catcher": 0.1}, "sites": 4, "scaffold": 0.08, "bad": 0.06, "upg": 0.1, "off": 0.15
	},
	"late_wood": {
		"day": 40, "max_h": 8, "towers": 5, "fill": 0.9, "void": 0.12,
		"tiers": [2, 3, 3, 4, 4, 5, 5], "fam": "one", "fams": ["wood"],
		"f1": {"teahouse": 2, "noodle_works": 1, "moonshine": 1, "tailor": 1, "candle_shop": 1, "karaoke": 2, "mahjong": 1, "gambling_den": 1, "dentist": 1, "study_hall": 1, "radio_shop": 1, "water_main": 1, "grid_power": 1, "shrine": 2, "trade_post": 1, "expedition_post": 2, "warehouse": 1},
		"f2": ["market_general", "casino", "landmark_hall", "bathhouse"], "roof": {"roof_garden": 0.14, "garden": 0.08}, "sites": 3, "scaffold": 0.05, "bad": 0.025, "upg": 0.05, "off": 0.08
	},
	"late_metal": {
		"day": 40, "max_h": 9, "towers": 5, "fill": 0.9, "void": 0.12,
		"tiers": [2, 3, 3, 4, 4, 5, 5], "fam": "one", "fams": ["metal"],
		"f1": {"radio_shop": 2, "fishball_works": 1, "call_centre": 1, "karaoke": 2, "fake_shop": 1, "tailor": 1, "dentist": 1, "study_hall": 1, "water_main": 1, "grid_power": 1, "shrine": 1, "trade_post": 1, "expedition_post": 2, "warehouse": 1, "gambling_den": 1},
		"f2": ["market_luxury", "power_plant", "assembly", "casino", "landmark_hall"], "roof": {"roof_garden": 0.1, "garden": 0.05}, "sites": 3, "scaffold": 0.05, "bad": 0.025, "upg": 0.05, "off": 0.08
	},
	"late_concrete": {
		"day": 40, "max_h": 9, "towers": 6, "fill": 0.92, "void": 0.1,
		"tiers": [2, 3, 3, 3, 4, 4, 5, 5], "fam": "one", "fams": ["concrete"],
		"f1": {"noodle_works": 1, "fishball_works": 1, "soap_shop": 1, "tailor": 1, "karaoke": 2, "mahjong": 1, "call_centre": 1, "dentist": 2, "study_hall": 1, "water_tower": 1, "grid_power": 1, "shrine": 1, "trade_post": 1, "expedition_post": 2, "warehouse": 1},
		"f2": ["market_general", "water_works", "cogen_plant", "casino", "landmark_hall"], "roof": {"roof_garden": 0.12, "garden": 0.06}, "sites": 3, "scaffold": 0.05, "bad": 0.025, "upg": 0.05, "off": 0.08
	},
	"late_mixed": {
		"day": 40, "max_h": 9, "towers": 6, "fill": 0.88, "void": 0.2,
		"tiers": [1, 2, 3, 3, 4, 4, 5], "fam": "districts", "fams": ["wood", "metal", "concrete"],
		"f1": {"teahouse": 1, "noodle_works": 1, "fishball_works": 1, "radio_shop": 1, "karaoke": 2, "call_centre": 1, "gambling_den": 1, "mahjong": 1, "dentist": 1, "study_hall": 1, "water_main": 1, "grid_power": 1, "generator": 1, "shrine": 2, "trade_post": 1, "expedition_post": 2, "warehouse": 1, "stall": 2},
		"f2": ["market_general", "casino", "power_plant", "landmark_hall"], "roof": {"roof_garden": 0.12, "garden": 0.08, "rain_catcher": 0.03}, "sites": 4, "scaffold": 0.07, "bad": 0.035, "upg": 0.06, "off": 0.1
	},
}


class Rng:
	var s: int
	func _init(seed_v: int) -> void:
		s = (seed_v * 2654435761 + 1013904223) & 0x7fffffff
		if s == 0:
			s = 1
	func f() -> float:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		return float((s >> 4) % 1000000) / 1000000.0
	func i(n: int) -> int:
		return int(f() * float(n)) % maxi(n, 1)
	func pick(w: Dictionary) -> String:
		var tot := 0.0
		for k in w:
			tot += float(w[k])
		var x := f() * tot
		for k in w:
			x -= float(w[k])
			if x < 0.0:
				return str(k)
		return str(w.keys()[0]) if not w.is_empty() else ""


static func build(preset: String, seed_v: int = 1, grid: Vector3i = Vector3i(12, 12, 10)) -> CityState:
	var s := CityState.new()
	s.cells = {}
	s.supports = {}
	s.buildings = {}
	if preset.begins_with("matrix"):
		_matrix(s, grid, preset.substr(7) if preset.length() > 7 else "")
		return s
	if not P.has(preset):
		preset = "mid"
	var cfg: Dictionary = P[preset]
	var r := Rng.new(seed_v * 31 + preset.hash())
	s.day = int(cfg["day"])
	s.hour = 10.0
	var gw := grid.x
	var gh := grid.y
	var max_h: int = mini(int(cfg["max_h"]), grid.z)
	# ── 1. 기둥 높이: 탑 몇 개 + 잡음. 대문 길(x=5..6, y 끝)과 골목 한 줄은 지상을 비운다
	var hmap := {}
	var towers: Array = []
	for t in int(cfg["towers"]):
		towers.append(Vector3(1.5 + r.f() * (gw - 3), 1.5 + r.f() * (gh - 3), (0.6 + 0.4 * r.f()) * float(max_h)))
	for x in gw:
		for y in gh:
			var h := 0.0
			if towers.is_empty():
				h = 1.0 if r.f() < float(cfg["fill"]) else 0.0
			else:
				for tw in towers:
					var d := Vector2(x + 0.5 - tw.x, y + 0.5 - tw.y).length()
					h = maxf(h, tw.z - d * 1.15)
				h += (r.f() - 0.5) * 1.6
				h = maxf(h, 1.0 if r.f() < float(cfg["fill"]) else 0.0)
				# 부지 가장자리는 조금 낮게
				var edge := mini(mini(x, gw - 1 - x), mini(y, gh - 1 - y))
				if edge == 0:
					h = minf(h, float(max_h) * 0.6)
			hmap[Vector2i(x, y)] = clampi(int(round(h)), 0, max_h)
	# 대문 앞 마당(비운다)
	for x in [5, 6]:
		for y in [gh - 1, gh - 2]:
			hmap[Vector2i(x, y)] = 0
	var alley_y := 3 + r.i(gh - 7)
	var alley_x := 2 + r.i(gw - 5)
	# ── 2. 가족(자재) 구역
	var fam_of := func(x: int, y: int) -> String:
		var fams: Array = cfg.get("fams", ["wood"])
		match str(cfg["fam"]):
			"none":
				return "common"
			"one":
				return str(fams[0]) if ViewCfg.h3(x / 2, y / 2, seed_v) % 100 >= 12 else str(FAMILIES[ViewCfg.h3(x, y, seed_v + 3) % 3])
			"two":
				return str(fams[0]) if x + (y / 3) < gw / 2 + ViewCfg.h3(y, 1, seed_v) % 3 else str(fams[1])
			_:
				# 세 구역: 사분면 + 가운데 경계 흔들림
				var a := 0 if x < gw / 2 + (ViewCfg.h2(y, seed_v) % 3 - 1) else 1
				var b := 0 if y < gh / 2 + (ViewCfg.h2(x + 50, seed_v) % 3 - 1) else 1
				return str(fams[[0, 1, 2, 0][a + b * 2]])
	# ── 3. 셀 후보(빈 칸 = 골조로 받친 빈틈)
	var occ := {}     # Vector3i -> "void" | "cell"
	for col in hmap:
		var h: int = hmap[col]
		for z in h:
			var p := Vector3i(col.x, col.y, z)
			var is_void := false
			if z < h - 1:
				if z == 0 and (col.y == alley_y or col.x == alley_x):
					is_void = r.f() < 0.75       # 지상 골목: 위가 이어진 필로티
				elif r.f() < float(cfg["void"]) * (1.4 if z > 0 else 0.6):
					is_void = true
			occ[p] = "void" if is_void else "cell"
	var bid := 1
	var tiers: Array = cfg["tiers"]
	# ── 4. 2×2 시설
	for ty in cfg["f2"]:
		for attempt in 80:
			# 바깥쪽(앞면이 보이는 자리)을 먼저 찾는다
			var ox := 1 + r.i(gw - 3)
			var oy := 1 + r.i(gh - 3)
			if attempt < 50:
				match r.i(4):
					0:
						ox = 0
					1:
						ox = gw - 2
					2:
						oy = 0
					_:
						oy = gh - 2
			var oz := 0 if r.f() < 0.75 else 1
			var ok := true
			for dx in 2:
				for dy in 2:
					var q := Vector3i(ox + dx, oy + dy, oz)
					if str(occ.get(q, "")) != "cell" or s.cells.has(q):
						ok = false
			if not ok:
				continue
			var o := Vector3i(ox, oy, oz)
			if ty == "landmark_hall":
				# 회관은 꼭대기: 위를 비운다(지붕이 보이게)
				for dx in 2:
					for dy in 2:
						for z2 in range(oz + 1, max_h + 1):
							occ.erase(Vector3i(ox + dx, oy + dy, z2))
						hmap[Vector2i(ox + dx, oy + dy)] = oz + 1
			for dx in 2:
				for dy in 2:
					var q2 := Vector3i(ox + dx, oy + dy, oz)
					s.cells[q2] = {"kind": "facility", "bid": bid, "type": ty, "tier": 0, "material": "", "seed": ViewCfg.h2(bid, seed_v), "origin": o, "size": 2}
			s.buildings[bid] = _fac(bid, ty, o, 2, r, float(cfg["off"]))
			bid += 1
			break
	# ── 5. 1×1 시설: 지상(앞쪽 우선) 또는 낮은 층
	var f1: Dictionary = cfg["f1"]
	for ty in f1:
		for k in int(f1[ty]):
			for attempt in 40:
				var x := r.i(gw)
				var y := r.i(gh)
				if attempt < 25 and r.f() < 0.7:
					if r.f() < 0.5:
						x = [0, gw - 1][r.i(2)]
					else:
						y = [0, gh - 1][r.i(2)]
				var z := 0 if r.f() < 0.7 else r.i(maxi(int(hmap[Vector2i(x, y)]), 1))
				var q := Vector3i(x, y, z)
				var form := ""
				if ty in ["rain_catcher", "garden", "stall", "generator", "water_tower", "shrine", "scrapyard"]:
					# 열린 것들은 기둥 꼭대기에(위에 아무것도 없게)
					z = int(hmap[Vector2i(x, y)])
					if z >= max_h:
						continue
					var below: Dictionary = s.cells.get(Vector3i(x, y, z - 1), {})
					if z > 0 and (str(occ.get(Vector3i(x, y, z - 1), "")) != "cell" or str(below.get("kind", "house")) == "facility"):
						continue
					q = Vector3i(x, y, z)
					form = "top"
				elif str(occ.get(q, "")) != "cell":
					continue
				if s.cells.has(q):
					continue
				s.cells[q] = {"kind": "facility", "bid": bid, "type": ty, "tier": 0, "material": "", "seed": ViewCfg.h2(bid, seed_v), "origin": q, "size": 1}
				if form == "top":
					occ[q] = "cell"
					hmap[Vector2i(x, y)] = z + 1
				s.buildings[bid] = _fac(bid, ty, q, 1, r, float(cfg["off"]))
				bid += 1
				break
	# ── 6. 주거: 같은 구역·같은 층 띠는 같은 계층 → 이어진 건물로 읽힌다
	for p in occ:
		if occ[p] != "cell" or s.cells.has(p):
			continue
		var fam: String = fam_of.call(p.x, p.y)
		var blk := ViewCfg.h3(p.x / 2 + (p.z / 3) * 7, p.y / 3, seed_v + 11)
		var tier: int = int(tiers[blk % tiers.size()])
		# 위로 갈수록 한 단계 높게(전망), 지상은 한 단계 낮게
		if p.z >= 4 and tier < 5 and blk % 3 == 0:
			tier += 1
		if p.z == 0 and tier > 1 and blk % 4 == 0:
			tier -= 1
		if fam == "common":
			tier = 1
		var mat := "common" if tier <= 1 else fam
		var cap: int = CAP[tier]
		var fill := 0.35 + 0.65 * r.f()
		if r.f() < 0.15:
			fill = 1.0
		var res := int(round(cap * fill))
		var cell := {"kind": "house", "bid": bid, "type": "house", "tier": tier, "material": mat, "seed": ViewCfg.h2(bid, seed_v + 5), "origin": p, "size": 1}
		var need := "ok"
		var x := r.f()
		if x < float(cfg["bad"]):
			need = "bad"
		elif x < float(cfg["bad"]) * 2.2:
			need = "warn"
		var upg := tier < 5 and res >= cap and r.f() < float(cfg["upg"])
		if tier < 5 and r.f() < float(cfg["scaffold"]):
			cell["scaffold"] = true
		s.cells[p] = cell
		s.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": tier, "material": mat, "residents": res, "cap": cap,
			"happiness": clampf(40.0 + 50.0 * r.f() - (30.0 if need == "bad" else 0.0), 0.0, 100.0),
			"need_state": need, "upgradable": upg, "upgrading": ({"to": tier + 1, "material": fam if fam != "common" else "wood", "done_at": 99.0} if cell.get("scaffold", false) else null), "needs": {}}
		bid += 1
	# ── 7. 공사장: 꼭대기 몇 칸
	var tops: Array = []
	for col in hmap:
		var h2: int = hmap[col]
		if h2 < max_h and h2 >= 1:
			tops.append(Vector3i(col.x, col.y, h2))
	tops.sort()
	for k in int(cfg["sites"]):
		if tops.is_empty():
			break
		var q3: Vector3i = tops[r.i(tops.size())]
		tops.erase(q3)
		if s.cells.has(q3):
			continue
		var fam2: String = fam_of.call(q3.x, q3.y)
		s.cells[q3] = {"kind": "site", "bid": bid, "type": "house", "tier": 0, "material": "", "seed": ViewCfg.h2(bid, seed_v), "origin": q3, "size": 1,
			"progress": 0.15 + 0.7 * r.f(), "becomes": {"kind": "house", "type": "house", "tier": 1, "material": "common" if fam2 == "common" else "common"}}
		s.buildings[bid] = {"id": bid, "kind": "site", "pos": q3}
		bid += 1
	# early: 지상 판잣집 몇 개 더 비우기는 fill로 충분
	_derive_supports(s)
	var top := 0
	for p2 in s.cells:
		top = maxi(top, p2.z + 1)
	s.floors_unlocked = clampi(top + (1 if preset != "early" else 0), 1, grid.z)
	return s


static func _fac(id: int, ty: String, o: Vector3i, size: int, r: Rng, off_p: float) -> Dictionary:
	var active := r.f() >= off_p
	var cause: String = "" if active else ["staff", "input", "power", "water"][r.i(4)]
	return {"id": id, "kind": "facility", "type": ty, "pos": o, "size": size, "active": active, "paused": false, "staff": 1.0 if active else 0.3, "eff": 1.0 if active else 0.0, "cause": cause}


## 아래가 빈 셀마다 땅(또는 다른 셀)까지 골조. 계약대로 셀이 있는 칸의 골조도 몇 개 남겨 둔다(그려지지 않아야 함).
static func _derive_supports(s: CityState) -> void:
	for p in s.cells:
		var z: int = p.z - 1
		while z >= 0 and not s.cells.has(Vector3i(p.x, p.y, z)):
			s.supports[Vector3i(p.x, p.y, z)] = true
			z -= 1
	var n := 0
	for p in s.cells:
		if p.z == 0 and ViewCfg.h2(p.x * 13 + p.y, 7) % 11 == 0 and n < 4:
			s.supports[p] = true
			n += 1


## 계층×자재 표본: 세 줄(목재·철제·콘크리트) × T1..T5, 덩어리 2칸 폭 × 3층. 맨 앞줄은 이어 붙여 이음매를 본다.
static func _matrix(s: CityState, grid: Vector3i, only: String = "") -> void:
	s.day = 30
	s.hour = 11.0
	var bid := 1
	var rows := {"wood": 1, "metal": 5, "concrete": 9}
	if only != "":
		rows = {only: 5}
	for fam in rows:
		var y0: int = rows[fam]
		for t in range(1, 6):
			var x0 := (t - 1) * 2 + 1
			for dx in 2:
				for dy in 2:
					for z in 3:
						var p := Vector3i(x0 + dx, y0 + dy, z)
						var cap: int = CAP[t]
						s.cells[p] = {"kind": "house", "bid": bid, "type": "house", "tier": t, "material": "common" if t == 1 else fam, "seed": ViewCfg.h2(bid, 77), "origin": p, "size": 1}
						s.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": t, "material": "common" if t == 1 else fam, "residents": int(cap * (0.6 + 0.4 * float((bid * 7) % 5) / 4.0)), "cap": cap, "happiness": 60.0, "need_state": "ok", "upgradable": false, "upgrading": null, "needs": {}}
						bid += 1
	_derive_supports(s)
	s.floors_unlocked = 4
