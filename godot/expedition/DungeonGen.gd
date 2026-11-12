extends RefCounted
## 던전 생성 — 씨앗 하나로 방 틀(data/run/run_rooms.json)을 갈래길로 이어 붙인다.
## 결과는 순수 데이터(타일 배열 + 방 목록 + 물건 목록). 그리기·시뮬레이션은 RunWorld가 한다.
##
## 1) 격자 위 무작위 걷기로 본길(입구→두목) 5~6방, 2) 본길 중간에 곁방 1~2개,
## 3) 깊이 = 입구에서 문 몇 개 거리, 4) 깊이에 맞는 틀을 골라 좌우·상하로 뒤집어 넣고,
## 5) 문·통로를 뚫고, 6) 깊이·위험도 예산으로 적을 켜고, 재고(stock)를 더미에 나눠 담는다.

const RunCfg = preload("res://expedition/RunCfg.gd")

const RW := 26
const RH := 16
const PITCH_X := 30
const PITCH_Y := 20
const MARGIN := 2

enum { VOID, FLOOR, WALL, CAR, BOX, TIRE, PRESS, JUNK, WIRE, HALL, GRAVEL, OIL, DOOR, RUBBLE }
const SOLID := [VOID, WALL, CAR, BOX, TIRE, PRESS, JUNK]

var rng := RandomNumberGenerator.new()
var w := 0
var h := 0
var tiles := PackedByteArray()
var rooms: Array = []        # {id, tmpl, name, g:Vector2i, origin:Vector2i, depth, main, links:[int], kind}
var objects: Array = []      # {type, cell:Vector2i, room:int, ...}
var stock_left: Dictionary = {}
var reserved_big: Dictionary = {}
var log_lines: Array[String] = []


static func is_solid_code(c: int) -> bool:
	return c in SOLID


func generate(seed_value: int, stock: Dictionary, danger: int) -> Dictionary:
	rng.seed = seed_value
	stock_left = stock.duplicate()
	for attempt in 50:
		if _layout():
			break
	_depths()
	_pick_templates()
	_build_tiles()
	_carve_links()
	_reachability()
	_reserve_big()
	_populate(danger)
	return {
		"w": w, "h": h, "tiles": tiles, "rooms": rooms, "objects": objects,
		"stock_left": stock_left, "big": reserved_big, "seed": seed_value,
	}


# ------------------------------------------------------------------ 배치
func _layout() -> bool:
	rooms.clear()
	var main_len := rng.randi_range(RunCfg.i("main_min", 6), RunCfg.i("main_max", 7))
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var dirs := [Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT]
	var weights := [3.0, 1.4, 1.4, 0.4]
	while cells.size() < main_len:
		var cur: Vector2i = cells[-1]
		var opts: Array = []
		var ws: Array = []
		for k in 4:
			var n: Vector2i = cur + dirs[k]
			if n in cells:
				continue
			opts.append(n)
			ws.append(weights[k])
		if opts.is_empty():
			return false
		cells.append(opts[_pick_w(ws)])
	for k in cells.size():
		rooms.append({"id": k, "g": cells[k], "links": [], "main": true, "kind": "normal"})
	for k in range(1, cells.size()):
		_link(k - 1, k)
	rooms[0]["kind"] = "entrance"
	rooms[cells.size() - 1]["kind"] = "boss"
	var total := mini(8, main_len + rng.randi_range(1, 2))
	var tries := 0
	while rooms.size() < total and tries < 40:
		tries += 1
		var host := rng.randi_range(1, main_len - 2)
		var hg: Vector2i = rooms[host]["g"]
		var d: Vector2i = dirs[rng.randi_range(0, 3)]
		var n := hg + d
		if _room_at(n) >= 0:
			continue
		# 두목 방 옆에 붙이지 않는다(곁방에서 두목 방으로 새는 길이 없게 — 연결은 link로만 하지만 보기에도)
		var id := rooms.size()
		rooms.append({"id": id, "g": n, "links": [], "main": false, "kind": "normal"})
		_link(host, id)
	return rooms.size() >= 6


func _link(a: int, b: int) -> void:
	rooms[a]["links"].append(b)
	rooms[b]["links"].append(a)


func _room_at(g: Vector2i) -> int:
	for r in rooms:
		if r["g"] == g:
			return r["id"]
	return -1


func _pick_w(ws: Array) -> int:
	var tot := 0.0
	for x in ws:
		tot += float(x)
	var t := rng.randf() * tot
	for k in ws.size():
		t -= float(ws[k])
		if t <= 0.0:
			return k
	return ws.size() - 1


func _depths() -> void:
	for r in rooms:
		r["depth"] = -1
	rooms[0]["depth"] = 0
	var q := [0]
	while not q.is_empty():
		var a: int = q.pop_front()
		for b in rooms[a]["links"]:
			if rooms[b]["depth"] < 0:
				rooms[b]["depth"] = rooms[a]["depth"] + 1
				q.append(b)


func _pick_templates() -> void:
	var all := RunCfg.rooms()
	var bag: Array = []
	for r in rooms:
		if r["kind"] == "entrance":
			r["tmpl"] = "entrance"
		elif r["kind"] == "boss":
			r["tmpl"] = "boss"
		else:
			var cands: Array = []
			for k in all:
				if k in ["entrance", "boss"]:
					continue
				if int(all[k]["min_depth"]) <= int(r["depth"]) and not (k in bag):
					cands.append(k)
			if cands.is_empty():
				for k in all:
					if not (k in ["entrance", "boss"]) and int(all[k]["min_depth"]) <= int(r["depth"]):
						cands.append(k)
			cands.sort()
			var pick: String = cands[rng.randi_range(0, cands.size() - 1)]
			bag.append(pick)
			r["tmpl"] = pick
		r["name"] = str(all[r["tmpl"]]["name"])
		r["flip_h"] = r["kind"] == "normal" and rng.randf() < 0.5
		r["flip_v"] = r["kind"] == "normal" and rng.randf() < 0.5


# ------------------------------------------------------------------ 타일
func _build_tiles() -> void:
	var minx := 999
	var miny := 999
	var maxx := -999
	var maxy := -999
	for r in rooms:
		var g: Vector2i = r["g"]
		minx = mini(minx, g.x); miny = mini(miny, g.y)
		maxx = maxi(maxx, g.x); maxy = maxi(maxy, g.y)
	w = (maxx - minx + 1) * PITCH_X + MARGIN * 2
	h = (maxy - miny + 1) * PITCH_Y + MARGIN * 2
	tiles.resize(w * h)
	tiles.fill(VOID)
	var all := RunCfg.rooms()
	objects.clear()
	for r in rooms:
		var g: Vector2i = r["g"] - Vector2i(minx, miny)
		r["g"] = g
		var o := Vector2i(MARGIN + g.x * PITCH_X, MARGIN + g.y * PITCH_Y)
		r["origin"] = o
		r["rect"] = Rect2i(o, Vector2i(RW, RH))
		var rows: Array = all[r["tmpl"]]["rows"]
		var waypoints := {}
		for y in RH:
			for x in RW:
				var sx := (RW - 1 - x) if r["flip_h"] else x
				var sy := (RH - 1 - y) if r["flip_v"] else y
				var ch: String = str(rows[sy])[sx]
				var c := Vector2i(o.x + x, o.y + y)
				var code := FLOOR
				match ch:
					"#": code = WALL
					",": code = GRAVEL
					"~": code = OIL
					"C": code = CAR
					"B": code = BOX
					"T": code = TIRE
					"K": code = PRESS
					"j": code = JUNK
					"w": code = WIRE
				set_t(c, code)
				match ch:
					"P": _obj("pile", c, r)
					"t": _obj("throwable", c, r)
					"r": _obj("m_rat", c, r)
					"d": _obj("m_dog", c, r)
					"g": _obj("m_guard", c, r)
					"s": _obj("m_rival", c, r)
					"j": _obj("junk", c, r)
					"E": _obj("m_exit", c, r)
					"X": _obj("exit", c, r, {"exit": "entrance"})
					"@": _obj("start", c, r)
					"1", "2", "3", "4": waypoints[int(ch)] = c
		if not waypoints.is_empty():
			var keys := waypoints.keys()
			keys.sort()
			var pts: Array = []
			for k in keys:
				pts.append(waypoints[k])
			r["patrol"] = pts
		# 누전 웅덩이 묶음
		var seen := {}
		for y in RH:
			for x in RW:
				var c := Vector2i(o.x + x, o.y + y)
				if get_t(c) == WIRE and not seen.has(c):
					var cells: Array = []
					var st := [c]
					seen[c] = true
					while not st.is_empty():
						var p: Vector2i = st.pop_back()
						cells.append(p)
						for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
							var n: Vector2i = p + d
							if get_t(n) == WIRE and not seen.has(n):
								seen[n] = true
								st.append(n)
					_obj("wire", c, r, {"cells": cells, "phase": rng.randf() * 3.0})


func _obj(type: String, c: Vector2i, r: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var o := {"type": type, "cell": c, "room": r["id"]}
	o.merge(extra)
	objects.append(o)
	return o


func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func get_t(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return VOID
	return tiles[c.y * w + c.x]


func set_t(c: Vector2i, code: int) -> void:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return
	tiles[c.y * w + c.x] = code


func _carve_links() -> void:
	for a in rooms:
		for bi in a["links"]:
			var b: Dictionary = rooms[bi]
			if b["id"] < a["id"]:
				continue
			var ga: Vector2i = a["g"]
			var gb: Vector2i = b["g"]
			var L: Dictionary = a if (ga.x + ga.y) < (gb.x + gb.y) else b   # 왼쪽/위
			var R: Dictionary = b if L == a else a
			var lo: Vector2i = L["origin"]
			var ro: Vector2i = R["origin"]
			if ga.y == gb.y:
				for y in [7, 8]:
					for x in range(lo.x + RW - 1, ro.x + 1):
						set_t(Vector2i(x, lo.y + y), DOOR if (x == lo.x + RW - 1 or x == ro.x) else HALL)
				for x in range(lo.x + RW, ro.x):
					set_t(Vector2i(x, lo.y + 6), WALL)
					set_t(Vector2i(x, lo.y + 9), WALL)
				_clear(Rect2i(lo.x + RW - 4, lo.y + 6, 3, 4))
				_clear(Rect2i(ro.x + 1, ro.y + 6, 3, 4))
				L.get_or_add("doors", []).append({"to": R["id"], "cell": Vector2i(lo.x + RW - 1, lo.y + 7), "side": "R"})
				R.get_or_add("doors", []).append({"to": L["id"], "cell": Vector2i(ro.x, ro.y + 7), "side": "L"})
			else:
				for x in [12, 13]:
					for y in range(lo.y + RH - 1, ro.y + 1):
						set_t(Vector2i(lo.x + x, y), DOOR if (y == lo.y + RH - 1 or y == ro.y) else HALL)
				for y in range(lo.y + RH, ro.y):
					set_t(Vector2i(lo.x + 11, y), WALL)
					set_t(Vector2i(lo.x + 14, y), WALL)
				_clear(Rect2i(lo.x + 11, lo.y + RH - 4, 4, 3))
				_clear(Rect2i(ro.x + 11, ro.y + 1, 4, 3))
				L.get_or_add("doors", []).append({"to": R["id"], "cell": Vector2i(lo.x + 12, lo.y + RH - 1), "side": "D"})
				R.get_or_add("doors", []).append({"to": L["id"], "cell": Vector2i(ro.x + 12, ro.y), "side": "U"})


func _clear(rc: Rect2i) -> void:
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var c := Vector2i(x, y)
			if is_solid_code(get_t(c)) or get_t(c) == WIRE:
				set_t(c, FLOOR)
			for o in objects.duplicate():
				if o["cell"] == c and o["type"] in ["pile", "junk", "m_exit"]:
					objects.erase(o)


func _reachability() -> void:
	var start := Vector2i.ZERO
	for o in objects:
		if o["type"] == "start":
			start = o["cell"]
	var seen := {start: true}
	var st := [start]
	while not st.is_empty():
		var p: Vector2i = st.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = p + d
			if seen.has(n):
				continue
			var t := get_t(n)
			if is_solid_code(t) and t != JUNK:
				continue
			seen[n] = true
			if t != JUNK:
				st.append(n)
	# 더미는 단단하지 않게 다루므로 더미 칸 자체가 닿으면 된다. 닿지 않는 칸의 물건은 지운다.
	var keep: Array = []
	for o in objects:
		var c: Vector2i = o["cell"]
		if seen.has(c) or o["type"] == "wire":
			keep.append(o)
		else:
			log_lines.append("닿지 않는 %s 제거 %s" % [o["type"], c])
	objects = keep


# ------------------------------------------------------------------ 채우기
func _reserve_big() -> void:
	var big: Dictionary = RunCfg.file("run_goods").get("big", {}).get("goods", {})
	reserved_big = {}
	for g in big:
		var n := mini(int(big[g]), int(stock_left.get(g, 0)))
		if n > 0:
			reserved_big[g] = n
			stock_left[g] = int(stock_left.get(g, 0)) - n


func _populate(danger: int) -> void:
	var goods := RunCfg.goods()
	var max_depth := 1
	for r in rooms:
		max_depth = maxi(max_depth, int(r["depth"]))
	var rival_used := false
	var mid_room := -1
	# 중간 출구: 본길에서 깊이 2~3인 방
	var mains: Array = []
	for r in rooms:
		if r["main"] and r["kind"] == "normal":
			mains.append(r)
	mains.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] < b["depth"])
	if not mains.is_empty():
		mid_room = mains[clampi(int(mains.size() / 2.0) - (1 if mains.size() >= 4 else 0), 0, mains.size() - 1)]["id"]
	var new_objs: Array = []
	for r in rooms:
		var rid: int = r["id"]
		var depth: int = r["depth"]
		var budget := 0.0
		if r["kind"] == "normal":
			budget = RunCfg.f("budget_base") + depth * RunCfg.f("budget_depth") + danger * RunCfg.f("budget_danger")
		var markers: Array = []
		for o in objects:
			if o["room"] != rid:
				continue
			if str(o["type"]).begins_with("m_"):
				markers.append(o)
		_shuffle(markers)
		var cost := {"m_rat": 1.0, "m_dog": 2.0, "m_guard": 3.5, "m_rival": 1.0}
		var placed := 0
		for m in markers:
			var t: String = m["type"]
			if t == "m_exit":
				continue
			if t == "m_rival":
				if rival_used or rng.randf() < 0.4 or r["kind"] != "normal":
					continue
				rival_used = true
				new_objs.append({"type": "rival", "cell": m["cell"], "room": rid})
				continue
			var c: float = cost.get(t, 1.0)
			if c <= budget or (placed == 0 and r["kind"] == "normal"):
				budget -= c
				placed += 1
				var e := {"type": t.substr(2), "cell": m["cell"], "room": rid}
				if t == "m_guard" and r.has("patrol"):
					e["patrol"] = r["patrol"]
				new_objs.append(e)
		# 출구
		if rid == mid_room:
			var cell := Vector2i(-1, -1)
			for o in objects:
				if o["room"] == rid and o["type"] == "m_exit":
					cell = o["cell"]
			if cell.x < 0:
				cell = _nearest_floor(r["origin"] + Vector2i(RW / 2, RH / 2 - 1))
			# 더미와 두 칸 이상 떨어뜨린다
			for o in objects:
				if o["type"] == "pile" and (o["cell"] as Vector2i).distance_to(cell) < 2.5:
					o["type"] = "junked"
			new_objs.append({"type": "exit", "cell": cell, "room": rid, "exit": "mid"})
			r["has_exit"] = true
		if r["kind"] == "entrance":
			r["has_exit"] = true
		if r["kind"] == "boss":
			new_objs.append({"type": "boss", "cell": r["origin"] + Vector2i(RW / 2, 6), "room": rid})
	# 지금 objects에서 표지(m_*)를 빼고 새로 켠 것을 더한다
	var keep: Array = []
	for o in objects:
		if not str(o["type"]).begins_with("m_"):
			keep.append(o)
	keep.append_array(new_objs)
	objects = keep
	# 더미에 재고 나눠 담기 — 깊은 방부터(좋은 것이 깊은 데로 가게), 같은 깊이는 무작위
	var piles: Array = []
	for o in objects:
		if o["type"] == "pile":
			piles.append(o)
	_shuffle(piles)
	piles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return rooms[a["room"]]["depth"] > rooms[b["room"]]["depth"])
	for p in piles:
		var depth: int = rooms[p["room"]]["depth"]
		# 깊은 방의 더미 일부는 잠긴 사물함: 따는 데 오래 걸리고 시끄럽지만 좋은 것이 든다
		p["locker"] = depth >= 2 and rng.randf() < RunCfg.f("locker_chance", 0.25)
		# 얕은 더미는 자주 비어 있고(앞사람들이 털었다) 깊을수록 묶음이 많다
		var n := 1
		var empty_p := RunCfg.f("pile_empty_d0", 0.4) - depth * RunCfg.f("pile_empty_step", 0.1)
		if rng.randf() < maxf(0.05, empty_p):
			n = 0
		else:
			if rng.randf() < RunCfg.f("pile_more_per_depth", 0.22) * depth:
				n += 1
			if rng.randf() < RunCfg.f("pile_more_per_depth", 0.22) * depth * 0.5:
				n += 1
		n = mini(n, RunCfg.i("pile_bundles_max", 3))
		if p["locker"]:
			n = maxi(n, 2)
		var bundles: Array = []
		for k in n:
			var g := _roll_good(goods, depth + (2 if p["locker"] else 0), max_depth)
			if g == "":
				break
			var units: int = mini(int(goods[g]["bundle"]), int(stock_left[g]))
			stock_left[g] = int(stock_left[g]) - units
			bundles.append({"good": g, "units": units})
		p["bundles"] = bundles
		p["heal"] = rng.randf() < RunCfg.f("heal_chance")
	# 깡통
	for o in objects:
		if o["type"] == "throwable":
			o["kind"] = "can" if rng.randf() < 0.6 else "brick"


func _roll_good(goods: Dictionary, depth: int, max_depth: int) -> String:
	var ids: Array = goods.keys()
	ids.sort()
	var ws: Array = []
	var t := clampf(float(depth) / maxf(3.0, float(max_depth)), 0.0, 1.0)
	var any := false
	for g in ids:
		var gd: Dictionary = goods[g]
		var wgt := lerpf(float(gd["w_shallow"]), float(gd["w_deep"]), t)
		if depth < int(gd["min_depth"]) or int(stock_left.get(g, 0)) <= 0:
			wgt = 0.0
		if wgt > 0.0:
			any = true
		ws.append(wgt)
	if not any:
		return ""
	return ids[_pick_w(ws)]


func _nearest_floor(c: Vector2i) -> Vector2i:
	for rad in 8:
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var n := c + Vector2i(dx, dy)
				if get_t(n) in [FLOOR, GRAVEL, OIL]:
					var busy := false
					for o in objects:
						if o["cell"] == n:
							busy = true
					if not busy:
						return n
	return c


func _shuffle(a: Array) -> void:
	for k in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp: Variant = a[k]
		a[k] = a[j]
		a[j] = tmp
