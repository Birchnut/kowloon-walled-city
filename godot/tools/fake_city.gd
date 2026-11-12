class_name FakeCity
extends RefCounted
## FakeCity v4 — 시뮬 없이 계약 모양(docs/ARCHITECTURE.md "v4 (PC판) 계약 변경")의 CityState를 만든다. 아트 판정·UI 촬영용. 순수 함수, seed 결정론.
## 격자 16×16×10(state.flags.grid). 시설은 `look`(외형 이름표)·발자국(w,h,d,rot)·간판(sign, 짧은 한글)을 셀에 싣는다.
## 셀: kind, bid, type, look, sign, tier, material, seed, origin, w, h, d, rot, size, burn, sick, trash (+ site: progress, becomes)
## 건물: house {residents, cap, arriving, burn, sick, …} / facility {look, w,h,d,rot, staff, eff, active, burn, build_left, repair}
## 프리셋: early mid late_wood late_metal late_concrete late_mixed hazard shapes showcase0..3 matrix

const PRESETS := ["early", "mid", "late_wood", "late_metal", "late_concrete", "late_mixed", "hazard", "shapes", "showcase0", "showcase1", "showcase2", "showcase3", "showcase4", "matrix"]
const CAP := {1: 4, 2: 8, 3: 12, 4: 8, 5: 6}
const FAMILIES := ["wood", "metal", "concrete"]

## look → [w, h, 층 수, 간판, 분류]. SIM의 실제 값과 다를 수 있다(뷰는 셀에 실린 값을 쓴다).
const LOOKS := {
	"market_mat": [1, 2, 1, "장터", "market"], "market_alley": [1, 2, 1, "골목시장", "market"], "market_hall": [2, 2, 1, "시장", "market"], "market_mall": [2, 2, 2, "면세점", "market"],
	"water_catcher": [1, 1, 1, "", "water"], "water_tank": [1, 1, 1, "물탱크", "water"], "water_pipe": [1, 2, 1, "수도국", "water"], "water_plant": [2, 2, 1, "정수장", "water"],
	"gen_small": [1, 1, 1, "발전기", "power"], "power_tap": [1, 1, 1, "", "power"], "power_plant": [2, 2, 1, "발전소", "power"], "power_waste": [2, 2, 1, "소각로", "power"],
	"food_cans": [1, 2, 1, "캔은행", "food"], "food_pilgrims": [1, 2, 1, "순례단", "food"], "noodle_mill": [1, 2, 1, "제면소", "food"], "noodle_stall": [1, 2, 1, "완탕", "food"],
	"rat_farm": [1, 2, 1, "쥐덫", "food"], "burger": [1, 2, 1, "버거", "food"], "sushi": [2, 2, 1, "스시", "food"], "roof_garden": [1, 2, 1, "", "food"], "brewery": [1, 2, 1, "양조장", "food"],
	"oil_collect": [1, 1, 1, "폐유", "goods"], "candle": [1, 2, 1, "초공방", "goods"], "soap": [1, 2, 1, "비누", "goods"], "rag_collect": [1, 2, 1, "넝마", "goods"],
	"tailor": [1, 2, 1, "봉제", "goods"], "suit": [1, 2, 1, "양복점", "goods"], "radio": [1, 2, 1, "전파사", "goods"], "assembly": [2, 2, 1, "조립소", "goods"], "fake": [1, 2, 1, "명품", "goods"],
	"mahjong": [1, 2, 1, "마작", "fun"], "teahouse": [1, 2, 1, "찻집", "fun"], "karaoke": [2, 2, 1, "노래방", "fun"], "bathhouse": [2, 2, 1, "목욕탕", "service"],
	"shrine": [1, 1, 1, "사당", "service"], "study": [1, 2, 1, "공부방", "service"], "roof_park": [2, 2, 1, "", "fun"], "dentist": [1, 2, 1, "치과", "service"],
	"pharmacy": [1, 2, 1, "약국", "service"], "salon": [1, 2, 1, "미용실", "service"],
	"fire_bucket": [1, 2, 1, "소방대", "safety"], "fire_station": [2, 2, 1, "소방서", "safety"], "trash_guild": [1, 2, 1, "넝마조합", "safety"], "clinic": [1, 2, 1, "의원", "safety"],
	"scrapyard": [2, 2, 1, "고물상", "base"], "warehouse": [1, 2, 1, "창고", "base"], "trade_post": [1, 2, 1, "무역관", "base"], "expedition_base": [1, 2, 1, "줍줍", "base"],
	"gambling": [1, 2, 1, "한판만", "vice"], "casino": [2, 2, 2, "카지노", "vice"], "callcenter": [1, 2, 1, "콜센터", "vice"], "fireworks": [1, 2, 1, "폭죽", "vice"],
	"landmark_hall": [3, 3, 1, "구청", "landmark"], "landmark_generic": [2, 2, 2, "명소", "landmark"],
	"generic_workshop": [1, 2, 1, "공방", "goods"], "generic_shop": [1, 2, 1, "가게", "market"], "generic_service": [1, 2, 1, "상담소", "service"],
}
## 위가 뚫려 있어야 하는 것(옥상·지붕 꼭대기에 둔다)
const SKY := ["water_catcher", "roof_garden", "roof_park", "power_tap", "water_tank"]

const P := {
	"early": {
		"day": 3, "max_h": 1, "towers": 0, "fill": 0.42, "void": 0.0, "tiers": [1], "fam": "none",
		"facs": ["market_mat", "water_catcher", "water_catcher", "mahjong", "shrine", "expedition_base", "food_cans"],
		"sites": 2, "fac_sites": 1, "scaffold": 0.0, "bad": 0.15, "upg": 0.2, "off": 0.0, "sick": 0.0, "fire": 0, "burnt": 0
	},
	"mid": {
		"day": 14, "max_h": 4, "towers": 5, "fill": 0.8, "void": 0.22, "tiers": [1, 1, 2, 2, 2, 3, 3], "fam": "two", "fams": ["wood", "concrete"],
		"facs": ["market_alley", "market_mat", "water_catcher", "water_catcher", "water_tank", "gen_small", "mahjong", "teahouse", "noodle_stall", "food_cans", "tailor", "candle",
			"fire_bucket", "shrine", "warehouse", "expedition_base", "trade_post", "noodle_mill", "brewery", "rag_collect", "market_hall", "roof_garden", "power_tap"],
		"pockets": 3, "sites": 4, "fac_sites": 1, "scaffold": 0.08, "bad": 0.06, "upg": 0.1, "off": 0.12, "sick": 0.0, "fire": 0, "burnt": 0
	},
	"late_wood": {
		"day": 40, "max_h": 9, "towers": 6, "fill": 0.9, "void": 0.12, "tiers": [2, 3, 3, 4, 4, 5, 5], "fam": "one", "fams": ["wood"],
		"facs": ["market_hall", "casino", "landmark_hall", "bathhouse", "teahouse", "teahouse", "noodle_stall", "brewery", "tailor", "candle", "karaoke", "mahjong", "gambling", "dentist",
			"study", "radio", "water_pipe", "power_tap", "shrine", "shrine", "trade_post", "expedition_base", "warehouse", "fire_bucket", "fire_station", "clinic", "trash_guild", "salon",
			"pharmacy", "sushi", "roof_garden", "roof_park", "water_catcher", "suit"],
		"pockets": 2, "sites": 3, "fac_sites": 1, "scaffold": 0.05, "bad": 0.025, "upg": 0.05, "off": 0.08, "sick": 0.0, "fire": 0, "burnt": 0
	},
	"late_metal": {
		"day": 40, "max_h": 9, "towers": 6, "fill": 0.9, "void": 0.12, "tiers": [2, 3, 3, 4, 4, 5, 5], "fam": "one", "fams": ["metal"],
		"facs": ["market_mall", "power_plant", "assembly", "casino", "landmark_generic", "radio", "radio", "burger", "callcenter", "karaoke", "karaoke", "fake", "tailor", "dentist", "study",
			"water_plant", "shrine", "trade_post", "expedition_base", "warehouse", "gambling", "fire_station", "clinic", "trash_guild", "pharmacy", "salon", "fireworks", "roof_garden", "roof_park"],
		"pockets": 2, "sites": 3, "fac_sites": 1, "scaffold": 0.05, "bad": 0.025, "upg": 0.05, "off": 0.08, "sick": 0.0, "fire": 0, "burnt": 0
	},
	"late_concrete": {
		"day": 40, "max_h": 9, "towers": 7, "fill": 0.92, "void": 0.1, "tiers": [2, 3, 3, 3, 4, 4, 5, 5], "fam": "one", "fams": ["concrete"],
		"facs": ["market_hall", "water_plant", "power_waste", "casino", "landmark_hall", "noodle_mill", "noodle_stall", "soap", "tailor", "karaoke", "mahjong", "callcenter", "dentist", "dentist",
			"study", "water_tank", "shrine", "trade_post", "expedition_base", "warehouse", "fire_station", "clinic", "trash_guild", "bathhouse", "sushi", "salon", "roof_garden", "roof_park"],
		"pockets": 2, "sites": 3, "fac_sites": 1, "scaffold": 0.05, "bad": 0.025, "upg": 0.05, "off": 0.08, "sick": 0.0, "fire": 0, "burnt": 0
	},
	"late_mixed": {
		"day": 40, "max_h": 9, "towers": 7, "fill": 0.88, "void": 0.2, "tiers": [1, 2, 3, 3, 4, 4, 5], "fam": "districts", "fams": ["wood", "metal", "concrete"],
		"facs": ["market_hall", "casino", "power_plant", "landmark_hall", "teahouse", "noodle_stall", "burger", "radio", "karaoke", "karaoke", "callcenter", "gambling", "mahjong", "dentist",
			"study", "water_pipe", "gen_small", "shrine", "shrine", "trade_post", "expedition_base", "warehouse", "market_alley", "market_mat", "fire_bucket", "fire_station", "clinic",
			"trash_guild", "bathhouse", "salon", "pharmacy", "sushi", "brewery", "tailor", "roof_garden", "roof_park", "water_catcher", "rat_farm"],
		"pockets": 4, "sites": 4, "fac_sites": 2, "scaffold": 0.07, "bad": 0.035, "upg": 0.06, "off": 0.1, "sick": 0.0, "fire": 0, "burnt": 0
	},
	"hazard": {
		"day": 22, "max_h": 6, "towers": 6, "fill": 0.86, "void": 0.16, "tiers": [1, 1, 2, 2, 3], "fam": "two", "fams": ["wood", "metal"],
		"facs": ["market_alley", "market_mat", "water_catcher", "water_tank", "gen_small", "mahjong", "teahouse", "noodle_stall", "food_cans", "tailor", "fire_bucket", "shrine",
			"warehouse", "expedition_base", "clinic", "trash_guild", "rag_collect", "brewery"],
		"pockets": 2, "sites": 2, "fac_sites": 1, "scaffold": 0.03, "bad": 0.05, "upg": 0.04, "off": 0.12, "sick": 0.22, "fire": 3, "burnt": 4
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


static func build(preset: String, seed_v: int = 1, grid: Vector3i = Vector3i(16, 16, 10)) -> CityState:
	var s := CityState.new()
	s.cells = {}
	s.supports = {}
	s.buildings = {}
	s.flags = {"grid": {"w": grid.x, "h": grid.y, "floors": grid.z}}
	if preset.begins_with("matrix"):
		_matrix(s, grid, preset.substr(7) if preset.length() > 7 else "")
		return s
	if preset.begins_with("showcase"):
		_showcase(s, grid, int(preset.substr(8)) if preset.length() > 8 else 0, seed_v)
		return s
	if preset == "shapes":
		_shapes(s, grid, seed_v)
		return s
	if not P.has(preset):
		preset = "mid"
	var cfg: Dictionary = P[preset]
	var r := Rng.new(seed_v * 31 + preset.hash())
	s.day = int(cfg["day"])
	s.hour = 10.0
	s.econ_days = float(s.day - 1) + s.hour / 24.0
	var gw := grid.x
	var gh := grid.y
	var max_h: int = mini(int(cfg["max_h"]), grid.z)
	# ── 1. 기둥 높이: 탑 몇 개 + 잡음. 대문 앞 마당과 골목 두 줄은 지상을 비운다
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
					h = maxf(h, tw.z - d * 1.05)
				h += (r.f() - 0.5) * 1.6
				h = maxf(h, 1.0 if r.f() < float(cfg["fill"]) else 0.0)
				var edge := mini(mini(x, gw - 1 - x), mini(y, gh - 1 - y))
				if edge == 0:
					h = minf(h, float(max_h) * 0.6)
			hmap[Vector2i(x, y)] = clampi(int(round(h)), 0, max_h)
	var gx := gw / 2 - 1
	for x in [gx, gx + 1]:
		for y in [gh - 1, gh - 2]:
			hmap[Vector2i(x, y)] = 0
	var alley_y := 3 + r.i(gh - 7)
	var alley_x := 2 + r.i(gw - 5)
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
				var a := 0 if x < gw / 2 + (ViewCfg.h2(y, seed_v) % 3 - 1) else 1
				var b := 0 if y < gh / 2 + (ViewCfg.h2(x + 50, seed_v) % 3 - 1) else 1
				return str(fams[[0, 1, 2, 0][a + b * 2]])
	# ── 2. 셀 후보(빈 칸 = 골조로 받친 빈틈)
	var occ := {}
	for col in hmap:
		var h: int = hmap[col]
		for z in h:
			var p := Vector3i(col.x, col.y, z)
			var is_void := false
			if z < h - 1:
				var edge2 := mini(mini(col.x, gw - 1 - col.x), mini(col.y, gh - 1 - col.y))
				if z == 0 and (col.y == alley_y or col.x == alley_x):
					is_void = r.f() < 0.75
				elif z <= 1 and edge2 == 0 and r.f() < float(cfg["void"]) * 2.2:
					is_void = true
				elif r.f() < float(cfg["void"]) * (1.4 if z > 0 else 0.6):
					is_void = true
			occ[p] = "void" if is_void else "cell"
	for k in int(cfg.get("pockets", 0)):
		for attempt in 30:
			var along_x := r.f() < 0.5
			var c0 := Vector2i(1 + r.i(gw - 3), gh - 1) if along_x else Vector2i(gw - 1, 1 + r.i(gh - 3))
			var c1 := c0 + (Vector2i(1, 0) if along_x else Vector2i(0, 1))
			if int(hmap.get(c0, 0)) < 2 or int(hmap.get(c1, 0)) < 2:
				continue
			for cc in [c0, c1]:
				for z in mini(2, int(hmap[cc]) - 1):
					occ[Vector3i(cc.x, cc.y, z)] = "void"
			break
	var ctx := {"bid": 1, "seed": seed_v}
	var off_p := float(cfg["off"])
	# ── 3. 시설(큰 것부터). 위가 뚫려야 하는 것은 기둥 꼭대기, 나머지는 바깥쪽 낮은 층을 좋아한다
	var facs: Array = (cfg["facs"] as Array).duplicate()
	facs.sort_custom(func(a: String, b: String) -> bool: return _area(a) > _area(b))
	for look in facs:
		var spec: Array = LOOKS.get(look, [1, 2, 1, "", "goods"])
		for attempt in 120:
			var rot := r.i(2) if int(spec[0]) != int(spec[1]) else 0
			var w: int = int(spec[1]) if rot == 1 else int(spec[0])
			var hh: int = int(spec[0]) if rot == 1 else int(spec[1])
			var dd: int = int(spec[2])
			var ox := r.i(gw - w + 1)
			var oy := r.i(gh - hh + 1)
			if attempt < 70 and r.f() < 0.75:
				match r.i(4):
					0:
						ox = 0
					1:
						ox = gw - w
					2:
						oy = 0
					_:
						oy = gh - hh
			var o := Vector3i(ox, oy, 0)
			var ok := true
			if look in SKY or look == "landmark_hall":
				# 발자국 기둥들의 꼭대기가 같은 높이여야
				var top := int(hmap[Vector2i(ox, oy)])
				for dx in w:
					for dy in hh:
						if int(hmap[Vector2i(ox + dx, oy + dy)]) != top:
							ok = false
				if look in SKY and top < 1 and look != "water_catcher" and look != "water_tank":
					ok = false
				if top + dd > grid.z:
					ok = false
				o = Vector3i(ox, oy, top)
				if ok:
					for dx in w:
						for dy in hh:
							if top > 0:
								var below: Dictionary = s.cells.get(Vector3i(ox + dx, oy + dy, top - 1), {})
								if str(occ.get(Vector3i(ox + dx, oy + dy, top - 1), "")) != "cell" or str(below.get("kind", "house")) == "facility":
									ok = false
				if ok:
					for dx in w:
						for dy in hh:
							for z in dd:
								occ[Vector3i(ox + dx, oy + dy, top + z)] = "cell"
							hmap[Vector2i(ox + dx, oy + dy)] = top + dd
			else:
				var oz := 0 if r.f() < 0.7 else r.i(3)
				o = Vector3i(ox, oy, oz)
				for dx in w:
					for dy in hh:
						for z in dd:
							var q := Vector3i(ox + dx, oy + dy, oz + z)
							if str(occ.get(q, "")) != "cell" or s.cells.has(q):
								ok = false
			if not ok:
				continue
			for dx in w:
				for dy in hh:
					for z in dd:
						if s.cells.has(o + Vector3i(dx, dy, z)):
							ok = false
			if not ok:
				continue
			_place_fac(s, ctx, look, o, w, hh, dd, rot, r, off_p)
			break
	# ── 4. 주거
	for p in occ:
		if occ[p] != "cell" or s.cells.has(p):
			continue
		var fam: String = fam_of.call(p.x, p.y)
		var blk := ViewCfg.h3(p.x / 2 + (p.z / 3) * 7, p.y / 3, seed_v + 11)
		var tiers: Array = cfg["tiers"]
		var tier: int = int(tiers[blk % tiers.size()])
		if p.z >= 4 and tier < 5 and blk % 3 == 0:
			tier += 1
		if p.z == 0 and tier > 1 and blk % 4 == 0:
			tier -= 1
		if fam == "common":
			tier = 1
		_place_house(s, ctx, p, tier, "common" if tier <= 1 else fam, r, cfg)
	# ── 5. 공사장: 주거 몇 칸 + 시설 하나(발자국 전체)
	var tops: Array = []
	for col in hmap:
		var h2: int = hmap[col]
		if h2 < max_h and h2 >= 1 and not s.cells.has(Vector3i(col.x, col.y, h2)):
			tops.append(Vector3i(col.x, col.y, h2))
	tops.sort()
	for k in int(cfg["sites"]):
		if tops.is_empty():
			break
		var q3: Vector3i = tops[r.i(tops.size())]
		tops.erase(q3)
		if s.cells.has(q3):
			continue
		_place_site(s, ctx, q3, 1, 1, 1, 0, "", 0.15 + 0.7 * r.f())
	for k in int(cfg.get("fac_sites", 0)):
		for attempt in 60:
			var q4: Vector3i = Vector3i(r.i(gw - 1), r.i(gh - 1), 0)
			var top2 := int(hmap.get(Vector2i(q4.x, q4.y), 0))
			q4.z = top2
			var ok2 := top2 + 1 <= max_h
			for dx in 2:
				if int(hmap.get(Vector2i(q4.x + dx, q4.y), -1)) != top2 or s.cells.has(Vector3i(q4.x + dx, q4.y, top2)):
					ok2 = false
				if top2 > 0 and str(s.cells.get(Vector3i(q4.x + dx, q4.y, top2 - 1), {}).get("kind", "")) != "house":
					ok2 = false
			if not ok2:
				continue
			_place_site(s, ctx, q4, 2, 1, 1, 1, ["karaoke", "teahouse", "radio", "clinic"][r.i(4)], 0.2 + 0.6 * r.f())
			for dx in 2:
				hmap[Vector2i(q4.x + dx, q4.y)] = top2 + 1
			break
	# ── 6. 불·병·쓰레기(hazard)
	_hazards(s, cfg, r)
	_derive_supports(s)
	var topz := 0
	for p2 in s.cells:
		topz = maxi(topz, p2.z + 1)
	s.floors_unlocked = clampi(topz + (1 if preset != "early" else 0), 1, grid.z)
	return s


static func _area(look: String) -> int:
	var sp: Array = LOOKS.get(look, [1, 1, 1])
	return int(sp[0]) * int(sp[1]) * int(sp[2]) * (10 if look in SKY else 1)


static func _place_fac(s: CityState, ctx: Dictionary, look: String, o: Vector3i, w: int, h: int, d: int, rot: int, r: Rng, off_p: float) -> int:
	var bid: int = ctx["bid"]
	ctx["bid"] = bid + 1
	var spec: Array = LOOKS.get(look, [1, 2, 1, "", "goods"])
	var sd := ViewCfg.h2(bid, int(ctx["seed"]))
	for dx in w:
		for dy in h:
			for z in d:
				var q := o + Vector3i(dx, dy, z)
				s.cells[q] = {"kind": "facility", "bid": bid, "type": "v4_" + look, "look": look, "sign": str(spec[3]), "tier": 0, "material": "", "seed": sd,
					"origin": o, "w": w, "h": h, "d": d, "rot": rot, "size": maxi(w, h), "burn": "", "sick": false, "trash": 0.0}
	var active := r.f() >= off_p
	var staff := 1.0 if active else 0.0
	if active and r.f() < 0.35:
		staff = [0.34, 0.5, 0.67, 0.75][r.i(4)]
	var cause: String = "" if active else ["staff", "input", "power", "water"][r.i(4)]
	s.buildings[bid] = {"id": bid, "kind": "facility", "type": "v4_" + look, "look": look, "cat": str(spec[4]), "sign": str(spec[3]), "pos": o, "w": w, "h": h, "d": d, "rot": rot,
		"size": maxi(w, h), "active": active, "paused": false, "staff": staff, "eff": staff if active else 0.0, "cause": cause, "burn": "", "build_left": 0.0, "repair": null}
	return bid


static func _place_house(s: CityState, ctx: Dictionary, p: Vector3i, tier: int, mat: String, r: Rng, cfg: Dictionary) -> int:
	var bid: int = ctx["bid"]
	ctx["bid"] = bid + 1
	var cap: int = CAP[tier]
	var fill := 0.35 + 0.65 * r.f()
	if r.f() < 0.15:
		fill = 1.0
	var res := int(round(cap * fill))
	var cell := {"kind": "house", "bid": bid, "type": "house", "tier": tier, "material": mat, "seed": ViewCfg.h2(bid, int(ctx["seed"]) + 5),
		"origin": p, "w": 1, "h": 1, "d": 1, "rot": 0, "size": 1, "burn": "", "sick": false, "trash": 0.0}
	var need := "ok"
	var x := r.f()
	if x < float(cfg.get("bad", 0.05)):
		need = "bad"
	elif x < float(cfg.get("bad", 0.05)) * 2.2:
		need = "warn"
	var upg := tier < 5 and res >= cap and r.f() < float(cfg.get("upg", 0.05))
	if tier < 5 and r.f() < float(cfg.get("scaffold", 0.0)):
		cell["scaffold"] = true
	s.cells[p] = cell
	s.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": tier, "material": mat, "residents": res, "cap": cap,
		"arriving": (0.3 + 0.6 * r.f()) if res < cap and r.f() < 0.3 else 0.0,
		"happiness": clampf(40.0 + 50.0 * r.f() - (30.0 if need == "bad" else 0.0), 0.0, 100.0),
		"need_state": need, "upgradable": upg, "burn": "", "sick": false, "repair": null,
		"upgrading": ({"to": tier + 1, "material": mat if mat != "common" else "wood", "done_at": 99.0} if cell.get("scaffold", false) else null), "needs": {}}
	return bid


static func _place_site(s: CityState, ctx: Dictionary, o: Vector3i, w: int, h: int, d: int, rot: int, look: String, prog: float) -> int:
	var bid: int = ctx["bid"]
	ctx["bid"] = bid + 1
	var bec := {"kind": "house", "type": "house", "tier": 1, "material": "common", "w": w, "h": h, "d": d, "rot": rot}
	if look != "":
		bec = {"kind": "facility", "type": "v4_" + look, "look": look, "w": w, "h": h, "d": d, "rot": rot}
	for dx in w:
		for dy in h:
			for z in d:
				s.cells[o + Vector3i(dx, dy, z)] = {"kind": "site", "bid": bid, "type": str(bec["type"]), "look": look, "tier": 0, "material": "", "seed": ViewCfg.h2(bid, int(ctx["seed"])),
					"origin": o, "w": w, "h": h, "d": d, "rot": rot, "size": maxi(w, h), "progress": prog, "becomes": bec}
	s.buildings[bid] = {"id": bid, "kind": "site", "pos": o, "w": w, "h": h, "d": d, "rot": rot, "progress": prog, "build_left": (1.0 - prog) * 0.4}
	return bid


static func _set_house_state(s: CityState, p: Vector3i, key: String, val: Variant) -> void:
	var c: Dictionary = s.cells.get(p, {})
	if c.is_empty():
		return
	c[key] = val
	var b: Dictionary = s.buildings.get(int(c.get("bid", -1)), {})
	if not b.is_empty():
		b[key] = val


## 불: 이웃한 주거 몇 칸이 타고, 몇 칸은 타 버린 뒤(일부는 수리 중). 병: 한 구역의 주거 + 그 둘레 쓰레기.
static func _hazards(s: CityState, cfg: Dictionary, r: Rng) -> void:
	var houses: Array = []
	for p in s.cells:
		if str(s.cells[p].get("kind", "")) == "house":
			houses.append(p)
	houses.sort()
	if houses.is_empty():
		return
	# 타는 중: 보이는(위가 빈) 집 하나와 그 옆·위
	var n_fire := int(cfg.get("fire", 0))
	if n_fire > 0:
		var seeds: Array = houses.filter(func(q: Vector3i) -> bool: return not s.cells.has(q + Vector3i(0, 0, 1)) and q.z >= 1)
		if not seeds.is_empty():
			var f0: Vector3i = seeds[r.i(seeds.size())]
			var burning := [f0]
			for dv in [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0)]:
				if burning.size() < n_fire and str(s.cells.get(f0 + dv, {}).get("kind", "")) == "house":
					burning.append(f0 + dv)
			for q in burning:
				_set_house_state(s, q, "burn", "burning")
	var n_burnt := int(cfg.get("burnt", 0))
	var placed := 0
	for attempt in 40:
		if placed >= n_burnt:
			break
		var q2: Vector3i = houses[r.i(houses.size())]
		if str(s.cells[q2].get("burn", "")) != "":
			continue
		_set_house_state(s, q2, "burn", "burnt")
		var b2: Dictionary = s.buildings.get(int(s.cells[q2]["bid"]), {})
		b2["residents"] = 0
		if placed % 2 == 0:
			b2["repair"] = {"money": 120, "goods": {"scrap": 4}, "days": 0.3, "active": true, "progress": 0.4}
		placed += 1
	var sick_p := float(cfg.get("sick", 0.0))
	if sick_p > 0.0:
		var c0: Vector3i = houses[r.i(houses.size())]
		for q3 in houses:
			var dd := Vector2(q3.x - c0.x, q3.y - c0.y).length()
			if dd < 3.2 and absi(q3.z - c0.z) <= 2 and str(s.cells[q3].get("burn", "")) == "":
				_set_house_state(s, q3, "sick", r.f() < 0.75)
				s.cells[q3]["trash"] = clampf(1.0 - dd / 3.5 + 0.2 * r.f(), 0.0, 1.0)
			elif r.f() < sick_p * 0.3:
				s.cells[q3]["trash"] = 0.25 + 0.4 * r.f()


## 아래가 빈 셀마다 땅(또는 다른 셀)까지 골조.
static func _derive_supports(s: CityState) -> void:
	for p in s.cells:
		var z: int = p.z - 1
		while z >= 0 and not s.cells.has(Vector3i(p.x, p.y, z)):
			s.supports[Vector3i(p.x, p.y, z)] = true
			z -= 1


## 모양 시험: 1×1, 1×2(두 방향), 2×2, 2×2×2층, 3×3 + 공사장(발자국 전체) + 위층 시설과 골조.
static func _shapes(s: CityState, grid: Vector3i, seed_v: int) -> void:
	s.day = 12
	s.hour = 11.0
	var r := Rng.new(seed_v)
	var ctx := {"bid": 1, "seed": seed_v}
	_place_fac(s, ctx, "shrine", Vector3i(1, 1, 0), 1, 1, 1, 0, r, 0.0)
	_place_fac(s, ctx, "mahjong", Vector3i(3, 1, 0), 1, 2, 1, 0, r, 0.0)
	_place_fac(s, ctx, "noodle_stall", Vector3i(5, 1, 0), 2, 1, 1, 1, r, 0.0)
	_place_fac(s, ctx, "karaoke", Vector3i(8, 1, 0), 2, 2, 1, 0, r, 0.0)
	_place_fac(s, ctx, "casino", Vector3i(11, 1, 0), 2, 2, 2, 0, r, 0.0)
	_place_fac(s, ctx, "landmark_hall", Vector3i(1, 5, 0), 3, 3, 1, 0, r, 0.0)
	_place_site(s, ctx, Vector3i(6, 5, 0), 2, 2, 1, 0, "bathhouse", 0.35)
	_place_site(s, ctx, Vector3i(10, 5, 0), 1, 2, 1, 0, "teahouse", 0.75)
	_place_site(s, ctx, Vector3i(13, 5, 0), 2, 2, 2, 0, "market_mall", 0.55)
	# 위층 시설: 판잣집 두 줄 위에 1×2 시설(아래 칸 하나는 비어 골조)
	for x in range(2, 6):
		for y in range(11, 13):
			if not (x == 5 and y == 12):
				_place_house(s, ctx, Vector3i(x, y, 0), 2, "wood", r, {})
	_place_fac(s, ctx, "tailor", Vector3i(4, 11, 1), 2, 1, 1, 1, r, 0.0)
	_place_fac(s, ctx, "dentist", Vector3i(4, 12, 1), 2, 1, 1, 1, r, 0.0)
	_place_house(s, ctx, Vector3i(2, 11, 1), 3, "concrete", r, {})
	for x in range(9, 13):
		for y in range(10, 14):
			_place_house(s, ctx, Vector3i(x, y, 0), [1, 2, 3, 4][(x + y) % 4], ["common", "wood", "metal", "concrete"][(x + y) % 4], r, {})
	_place_fac(s, ctx, "teahouse", Vector3i(9, 10, 1), 1, 2, 1, 0, r, 0.0)
	_place_fac(s, ctx, "roof_garden", Vector3i(11, 12, 1), 2, 1, 1, 1, r, 0.0)
	_derive_supports(s)
	s.floors_unlocked = 4


## 진열장: look을 한 쪽에 12개씩, 4×4 칸 구획마다 하나(지상, 사방이 트임). 0..4쪽.
static func _showcase(s: CityState, grid: Vector3i, page: int, seed_v: int) -> void:
	s.day = 20
	s.hour = 11.0
	var keys: Array = LOOKS.keys()
	var r := Rng.new(seed_v + page)
	var ctx := {"bid": 1, "seed": seed_v}
	var per := 12
	var i0 := page * per
	var slots: Array = []
	for by in 3:
		for bx in 4:
			slots.append(Vector2i(bx * 4, by * 5))
	for k in per:
		var idx := i0 + k
		if idx >= keys.size():
			break
		var look: String = keys[idx]
		var sp: Array = LOOKS[look]
		var w: int = int(sp[0])
		var h: int = int(sp[1])
		var sl: Vector2i = slots[k]
		var o := Vector3i(sl.x + (3 - w) / 2 + (1 if w < 3 else 0), sl.y + (4 - h) / 2, 0)
		if look in SKY and look != "water_catcher":
			# 옥상 것: 판잣집 한 층 위에
			for dx in w:
				for dy in h:
					_place_house(s, ctx, o + Vector3i(dx, dy, 0), 2, "concrete", r, {})
			o.z = 1
		_place_fac(s, ctx, look, o, w, h, int(sp[2]), 0, r, 0.0)
	_derive_supports(s)
	s.floors_unlocked = 3


## 계층×자재 표본: 세 줄(목재·철제·콘크리트) × T1..T5, 덩어리 2칸 폭 × 3층.
static func _matrix(s: CityState, grid: Vector3i, only: String = "") -> void:
	s.day = 30
	s.hour = 11.0
	var bid := 1
	var rows := {"wood": 1, "metal": 6, "concrete": 11}
	if only != "":
		rows = {only: 6}
	for fam in rows:
		var y0: int = rows[fam]
		for t in range(1, 6):
			var x0 := (t - 1) * 3 + 1
			for dx in 2:
				for dy in 2:
					for z in 3:
						var p := Vector3i(x0 + dx, y0 + dy, z)
						var cap: int = CAP[t]
						s.cells[p] = {"kind": "house", "bid": bid, "type": "house", "tier": t, "material": "common" if t == 1 else fam, "seed": ViewCfg.h2(bid, 77), "origin": p, "w": 1, "h": 1, "d": 1, "rot": 0, "size": 1}
						s.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": t, "material": "common" if t == 1 else fam, "residents": int(cap * (0.6 + 0.4 * float((bid * 7) % 5) / 4.0)), "cap": cap, "happiness": 60.0, "need_state": "ok", "upgradable": false, "upgrading": null, "needs": {}}
						bid += 1
	_derive_supports(s)
	s.floors_unlocked = 4
