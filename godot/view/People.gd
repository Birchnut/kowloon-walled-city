class_name CityPeople
extends Node3D
## 주민들(v4) — 뷰 전용 연출(규칙 영향 0). 상태에서 집·시장·일터·놀 곳을 읽어, 시간대마다 집 → 목적지 → 집을 오가게 한다.
## 걷는 곳: 비어 있는 지상 칸, 골조 아래(필로티), 기둥 꼭대기(옥상), 트인 시설 칸. 이웃 칸끼리 이어지고 한 층 차이는 사다리·계단으로 오른다.
## 길이 없으면 건물 안 복도로 들어가 사라지고(구룡성채식) 목적지 문 앞에서 다시 나온다.
## 옷 = 사는 집의 계층 팔레트. 저녁에 많고 깊은 밤엔 거의 없다. who(screen) = "굴러온 돌 · 통조림 사러 가는 중".

const ActorShader := preload("res://view/shaders/actor.gdshader")
const MAX_INST := 260
const LOD_SIZE := [Vector2(6, 12), Vector2(10, 20), Vector2(20, 40), Vector2(26, 52)]
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
const TIER_NAMES := ["굴러온 돌", "월세 전사", "박힌 돌", "깡통 귀족", "옥상 황제"]

var cfg: ViewCfg
var view: Control
var mesher: CityMesher
var agents: Array = []
var nodes: Dictionary = {}          # Vector3i(x,y,z) -> true (걸을 수 있는 칸)
var doors: Dictionary = {}          # bid -> Array[Vector3i]
var homes: Array = []               # [{bid, tier, w}] 사는 사람 수만큼 가중
var dests: Dictionary = {}          # 종류 -> Array[{bid, look, sign}]
var _street: Array = []
var _mmi: Array = []
var _mats: Array = []
var _cut := -1
var _zoom_i := 1
var _tick := 0.0
var _rs := 12345
var _gate := Vector3.ZERO
var _waiting_n := 0
var _pop := 0
var _t := 0.0
var _tier_names: Array = []


func setup(c: ViewCfg, v: Control, m: CityMesher, lg: Texture3D) -> void:
	cfg = c
	view = v
	mesher = m
	for i in 4:
		var tex := PeopleSprites.build(["S", "M", "X", "XX"][i])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mm.mesh = q
		mm.instance_count = MAX_INST
		mm.visible_instance_count = 0
		var mat := ShaderMaterial.new()
		mat.shader = ActorShader
		mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("lightgrid", lg)
		mat.set_shader_parameter("frame_px", LOD_SIZE[i])
		mat.set_shader_parameter("sheet_px", Vector2(tex.get_width(), tex.get_height()))
		mat.set_shader_parameter("depth_bias", 0.15)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.custom_aabb = AABB(Vector3(-40, -5, -40), Vector3(120, 60, 120))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mmi.append(mi)
		_mats.append(mat)
	_tier_names = TIER_NAMES.duplicate()


func set_lightgrid(lg: Texture3D) -> void:
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("lightgrid", lg)


func _rnd() -> float:
	_rs = (_rs * 1103515245 + 12345) & 0x7fffffff
	return float((_rs >> 8) % 100000) / 100000.0


func _ri(n: int) -> int:
	return int(_rnd() * n) % maxi(n, 1)


# ------------------------------------------------------------------ 지도
func _walkable(st: CityState, p: Vector3i) -> bool:
	var c: Dictionary = st.cells.get(p, {})
	if not c.is_empty():
		if str(c.get("kind", "")) != "facility":
			return false
		var form := str(mesher.recipe_of(c).get("form", "box"))
		if form != "open":
			return false
	if p.z == 0:
		return true
	return mesher.solid.has(p - Vector3i(0, 0, 1))


func rebuild(st: CityState) -> void:
	nodes.clear()
	doors.clear()
	homes.clear()
	dests = {"market": [], "food": [], "water": [], "work": [], "fun": [], "service": []}
	var gw := cfg.grid.x
	var gh := cfg.grid.y
	var top := cfg.grid.z + 1
	for x in gw:
		for y in gh:
			for z in top:
				var p := Vector3i(x, y, z)
				if _walkable(st, p):
					nodes[p] = true
	# 문: 건물 칸 옆(같은 층)의 걸을 수 있는 칸. 시설은 앞면을 좋아한다.
	_pop = 0
	for p in st.cells:
		var c: Dictionary = st.cells[p]
		var bid := int(c.get("bid", -1))
		if bid < 0:
			continue
		for d in DIRS:
			var q: Vector3i = p + d
			if nodes.has(q):
				if not doors.has(bid):
					doors[bid] = []
				if not (doors[bid] as Array).has(q):
					(doors[bid] as Array).append(q)
		var up: Vector3i = p + Vector3i(0, 0, 1)
		if nodes.has(up) and str(c.get("kind", "")) == "house" and not doors.has(bid):
			doors[bid] = [up]
	var bs: Dictionary = st.buildings
	for bid in bs:
		var b: Dictionary = bs[bid]
		if not doors.has(int(bid)):
			continue
		var kind := str(b.get("kind", ""))
		if kind == "house":
			var n := int(b.get("residents", 0))
			if n <= 0 or str(b.get("burn", "")) != "":
				continue
			_pop += n
			homes.append({"bid": int(bid), "tier": int(b.get("tier", 1)), "w": n})
		elif kind == "facility" and bool(b.get("active", true)) and str(b.get("burn", "")) == "":
			var c2: Dictionary = st.cells.get(b.get("pos", Vector3i(-9, -9, -9)), {})
			var lk := mesher.look_name(c2) if not c2.is_empty() else str(b.get("look", ""))
			var it := {"bid": int(bid), "look": lk, "sign": mesher.sign_of(c2) if not c2.is_empty() else ""}
			var cat := str(ViewCfg.LOOK_CAT.get(lk, "goods"))
			match cat:
				"market":
					dests["market"].append(it)
				"food":
					dests["food" if lk in ["noodle_stall", "burger", "sushi", "food_cans", "food_pilgrims"] else "work"].append(it)
				"water":
					dests["water"].append(it)
				"fun", "vice":
					dests["fun"].append(it)
				"service", "safety", "landmark":
					dests["service"].append(it)
				_:
					dests["work"].append(it)
			if cat in ["food", "fun", "vice", "service", "market"] and float(b.get("staff", 1.0)) > 0.0:
				dests["work"].append(it)
	# 담장 밖 보도
	_street = []
	for x in range(-2, gw + 2):
		for yy in [gh + 1, -2]:
			_street.append(Vector3(x + 0.5, 0, yy + 0.5))
	for y in range(-1, gh + 1):
		for xx in [gw + 1, -2]:
			_street.append(Vector3(xx + 0.5, 0, y + 0.5))
	_gate = Vector3(gw * 0.5, 0, gh + 1.3)
	_waiting_n = 0
	var wt: Variant = st.get("waiting")
	if wt is Dictionary:
		for k in wt:
			var w: Variant = wt[k]
			if w is Dictionary:
				_waiting_n += int(w.get("count", 0))
	_waiting_n = mini(_waiting_n, 16)
	var tn: Variant = Data.items("tiers")
	if tn is Dictionary and not (tn as Dictionary).is_empty():
		for k in tn:
			var ti: Dictionary = tn[k]
			var idx := int(ti.get("index", 0)) - 1
			if idx >= 0 and idx < 5 and str(ti.get("name", "")) != "":
				_tier_names[idx] = str(ti["name"])
	# 사라진 길 위의 사람은 없앤다
	var keep: Array = []
	for a in agents:
		if a["kind"] != "walk" or _path_ok(a):
			keep.append(a)
	agents = keep


func _path_ok(a: Dictionary) -> bool:
	for n in a.get("path", []):
		if not nodes.has(n):
			return false
	return true


func set_bridges(_list: Array) -> void:
	pass


func set_cut(n: int) -> void:
	_cut = n


func set_zoom_level(zi: int, _inner: bool) -> void:
	_zoom_i = zi


## 가까운 길(BFS). 한 층 차이 이웃은 사다리로 잇는다. 찾지 못하면 [].
func _path(from: Vector3i, goals: Array, limit: int = 1500) -> Array:
	if goals.is_empty() or not nodes.has(from):
		return []
	var goal_set: Dictionary = {}
	for g in goals:
		goal_set[g] = true
	var prev: Dictionary = {from: from}
	var queue: Array = [from]
	var head := 0
	while head < queue.size() and head < limit:
		var cur: Vector3i = queue[head]
		head += 1
		if goal_set.has(cur):
			var out: Array = [cur]
			while cur != from:
				cur = prev[cur]
				out.push_front(cur)
			return out
		for d in DIRS:
			for dz in [0, 1, -1]:
				var nx: Vector3i = cur + d + Vector3i(0, 0, dz)
				if nodes.has(nx) and not prev.has(nx):
					prev[nx] = cur
					queue.append(nx)
					break
	return []


# ------------------------------------------------------------------ 하루
func _targets(hr: float) -> Dictionary:
	var budget: int = [55, 80, 110, 140, 160][clampi(_zoom_i, 0, 4)]
	var base := clampf(float(_pop) * 0.09, 4.0, float(budget))
	var k := 0.05
	if hr >= 6.0 and hr < 9.0:
		k = 0.7
	elif hr >= 9.0 and hr < 17.0:
		k = 0.6
	elif hr >= 17.0 and hr < 21.5:
		k = 1.0
	elif hr >= 21.5 and hr < 23.5:
		k = 0.45
	elif hr >= 23.5 or hr < 2.0:
		k = 0.15
	return {"walk": int(base * k), "street": int(clampf(base * 0.1 * k, 0.0, 10.0)), "gate": _waiting_n}


func _pick_home() -> Dictionary:
	var tot := 0
	for h in homes:
		tot += int(h["w"])
	var x := _ri(maxi(tot, 1))
	for h in homes:
		x -= int(h["w"])
		if x < 0:
			return h
	return homes[0] if not homes.is_empty() else {}


func _pick_errand(hr: float, tier: int) -> Dictionary:
	var w: Dictionary = {}
	if hr >= 5.5 and hr < 10.0:
		w = {"work": 5, "market": 2, "food": 2, "water": 2}
	elif hr >= 10.0 and hr < 17.0:
		w = {"market": 4, "food": 2, "work": 3, "service": 2, "fun": 1, "water": 1}
	elif hr >= 17.0 and hr < 22.0:
		w = {"food": 3, "fun": 4, "market": 2, "service": 1}
	else:
		w = {"fun": 3, "food": 1}
	var tot := 0
	for k in w:
		if not (dests.get(k, []) as Array).is_empty():
			tot += int(w[k])
	if tot == 0:
		return {}
	var x := _ri(tot)
	for k in w:
		if (dests.get(k, []) as Array).is_empty():
			continue
		x -= int(w[k])
		if x < 0:
			var list: Array = dests[k]
			var it: Dictionary = list[_ri(list.size())]
			return {"kind": k, "bid": it["bid"], "look": it["look"], "sign": it["sign"]}
	return {}


func _going_text(e: Dictionary) -> String:
	var lk := str(e.get("look", ""))
	var sg := str(e.get("sign", ""))
	match str(e.get("kind", "")):
		"water":
			return "물 길으러 가는 중"
		"market":
			return "장 보러 가는 중"
		"work":
			return ("%s에 일하러 가는 중" % sg) if sg != "" else "일하러 가는 중"
	match lk:
		"food_cans":
			return "통조림 사러 가는 중"
		"food_pilgrims":
			return "마감 세일 줄 서러 가는 중"
		"noodle_stall":
			return "완탕면 먹으러 가는 중"
		"burger":
			return "출처 묻지 마 버거 먹으러 가는 중"
		"sushi":
			return "어제 잡은 스시 먹으러 가는 중"
		"mahjong":
			return "마작 한 판 하러 가는 중"
		"teahouse":
			return "차 한 잔 하러 가는 중"
		"karaoke":
			return "노래 부르러 가는 중"
		"bathhouse":
			return "때 밀러 가는 중"
		"shrine":
			return "향 피우러 가는 중"
		"dentist":
			return "이 뽑으러 가는 중"
		"clinic":
			return "진료 받으러 가는 중"
		"pharmacy":
			return "약 비슷한 것 사러 가는 중"
		"salon":
			return "머리 하러 가는 중"
		"study":
			return "족보 공부하러 가는 중"
		"gambling", "casino":
			return "딱 한 판만 하러 가는 중"
		"roof_park":
			return "바람 쐬러 가는 중"
	return ("%s에 가는 중" % sg) if sg != "" else "볼일 보러 가는 중"


func _coming_text(e: Dictionary) -> Array:
	# [글, 자세]
	match str(e.get("kind", "")):
		"water":
			return ["물통 들고 집에 가는 중", "bucket"]
		"market":
			return ["장 본 것 메고 집에 가는 중", "sack"]
		"work":
			return ["일 끝나고 집에 가는 중", "walk"]
	if str(e.get("look", "")) == "food_cans":
		return ["통조림 들고 집에 가는 중", "can"]
	return ["집에 가는 중", "walk"]


func _spawn_walker(hr: float) -> void:
	if homes.is_empty():
		return
	var h := _pick_home()
	var hd: Array = doors.get(int(h.get("bid", -1)), [])
	if hd.is_empty():
		return
	var e := _pick_errand(hr, int(h["tier"]))
	if e.is_empty():
		return
	var ed: Array = doors.get(int(e["bid"]), [])
	if ed.is_empty():
		return
	var outbound := _rnd() < (0.7 if hr < 16.0 else 0.45)
	var from: Vector3i = hd[_ri(hd.size())] if outbound else ed[_ri(ed.size())]
	var goals: Array = ed if outbound else hd
	var path := _path(from, goals)
	var text := ""
	var pose := "walk"
	if outbound:
		text = _going_text(e)
	else:
		var ct := _coming_text(e)
		text = ct[0]
		pose = ct[1]
	if path.size() < 2:
		# 길이 끊김: 문 앞에서 잠깐 서성이다 안으로(복도로) 들어간다
		path = [from]
		var nb: Vector3i = from
		for i in 2 + _ri(3):
			var opts: Array = []
			for d in DIRS:
				if nodes.has(nb + d):
					opts.append(nb + d)
			if opts.is_empty():
				break
			nb = opts[_ri(opts.size())]
			path.append(nb)
		if path.size() < 2:
			return
		text = text.replace("가는 중", "가는 길(지름길 복도로)")
	var tier: int = int(h["tier"])
	var hs := _ri(1 << 20)
	var seat := -1
	if outbound and str(e.get("kind", "")) in ["fun", "food", "service"] and path.size() >= 2 and goals.has(path[-1]):
		seat = int(e["bid"])   # 도착하면 그 시설 손님 자리에 앉는다
	agents.append({"kind": "walk", "seat": seat, "look": str(e.get("look", "")), "path": path, "i": 0, "pos": _node_pos(path[0], hs), "to": _node_pos(path[1], hs + 1), "hs": hs,
		"pose": pose, "tier": tier, "text": text, "speed": 0.42 + 0.25 * _rnd(), "wait": 0.0, "dir": Vector3(1, 0, 0),
		"shirt": cfg.tier_color(tier, hs % 5), "pal": (hs % 6) + ((hs / 6) % 8) * 8 + ((hs / 48) % 8) * 64 + ([0, 1, 2][hs % 3] if pose != "walk" else 0) * 512})
	if pose == "bucket":
		agents[-1]["pal"] = (hs % 6) + ((hs / 6) % 8) * 8 + ((hs / 48) % 8) * 64
	elif pose == "can":
		agents[-1]["pal"] = (hs % 6) + ((hs / 6) % 8) * 8 + ((hs / 48) % 8) * 64 + 512


## 작은 장면: 완탕 배달꾼(노점 → 아무 집, 뛰어감), 골목에서 공 쫓는 아이들(지상 빈 칸을 오가며 뜀).
func _spawn_special(hr: float) -> void:
	var stalls: Array = (dests.get("food", []) as Array).filter(func(it: Dictionary) -> bool: return str(it["look"]) in ["noodle_stall", "burger"])
	if not stalls.is_empty() and hr >= 10.0 and hr < 22.5 and _rnd() < 0.6 and not homes.is_empty():
		var st: Dictionary = stalls[_ri(stalls.size())]
		var h: Dictionary = homes[_ri(homes.size())]
		var path := _path((doors.get(int(st["bid"]), [Vector3i(-9, -9, -9)]) as Array)[0], doors.get(int(h["bid"]), []))
		if path.size() >= 3:
			var hs := _ri(1 << 20)
			agents.append({"kind": "walk", "seat": -1, "look": "", "path": path, "i": 0, "pos": _node_pos(path[0], hs), "to": _node_pos(path[1], hs + 1), "hs": hs,
				"pose": "carry", "tier": 2, "text": "완탕 배달 중(국물 안 흘리게)", "speed": 0.95, "wait": 0.0, "dir": Vector3(1, 0, 0),
				"shirt": Color("#f4f0e6"), "pal": (hs % 6) + ((hs / 6) % 8) * 8 + 64})
		return
	if hr < 8.0 or hr > 19.5:
		return
	# 아이들: 지상(또는 옥상) 빈 칸 하나를 골라 그 둘레를 뛰어다닌다
	var keys: Array = nodes.keys()
	if keys.is_empty():
		return
	var c0: Vector3i = keys[_ri(keys.size())]
	for k in 2 + _ri(2):
		var path2: Array = [c0]
		var nb: Vector3i = c0
		for i in 10:
			var opts: Array = []
			for d in DIRS:
				if nodes.has(nb + d):
					opts.append(nb + d)
			if opts.is_empty():
				break
			nb = opts[_ri(opts.size())]
			path2.append(nb)
		if path2.size() < 3:
			return
		var hs2 := _ri(1 << 20)
		agents.append({"kind": "walk", "seat": -1, "look": "", "path": path2, "i": 0, "pos": _node_pos(path2[0], hs2), "to": _node_pos(path2[1], hs2 + 1), "hs": hs2,
			"pose": "run", "tier": 1 + hs2 % 3, "text": "공 쫓아 뛰는 아이", "speed": 0.9 + 0.3 * _rnd(), "wait": 0.0, "dir": Vector3(1, 0, 0),
			"shirt": Color(["#ff9a4a", "#5fa8e6", "#ffd45a", "#ff6f6f"][hs2 % 4]), "pal": (hs2 % 6) + 3 * 8 + 7 * 64})


## 시설에서 놀다 나온 사람: 그 시설 문에서 같은 계층의 집으로(같은 옷).
func _spawn_return(lv: Dictionary) -> void:
	var ed: Array = doors.get(int(lv.get("bid", -1)), [])
	if ed.is_empty() or homes.is_empty() or agents.size() >= MAX_INST:
		return
	var cands: Array = homes.filter(func(hh: Dictionary) -> bool: return int(hh["tier"]) == int(lv.get("tier", 1)))
	if cands.is_empty():
		cands = homes
	var h: Dictionary = cands[_ri(cands.size())]
	var from: Vector3i = ed[_ri(ed.size())]
	var path := _path(from, doors.get(int(h["bid"]), []))
	if path.size() < 2:
		return
	var hs := int(lv.get("hs", _ri(1 << 20)))
	var lk := str(lv.get("look", ""))
	var txt := "실컷 놀고 집에 가는 중"
	if lk in ["noodle_stall", "burger", "sushi", "teahouse"]:
		txt = "배부르게 먹고 집에 가는 중"
	elif lk in ["mahjong", "gambling", "casino"]:
		txt = "돈 잃고 집에 가는 중" if hs % 3 != 0 else "한 판 따고 집에 가는 중"
	elif lk == "karaoke":
		txt = "목이 쉰 채 집에 가는 중"
	agents.append({"kind": "walk", "seat": -1, "look": lk, "path": path, "i": 0, "pos": _node_pos(path[0], hs), "to": _node_pos(path[1], hs + 1), "hs": hs,
		"pose": "walk", "tier": int(lv.get("tier", 1)), "text": txt, "speed": 0.4 + 0.2 * _rnd(), "wait": 0.0, "dir": Vector3(1, 0, 0),
		"shirt": lv.get("shirt", Color.WHITE), "pal": int(lv.get("pal", 0))})


func _node_pos(n: Vector3i, hs: int) -> Vector3:
	var ox := float(ViewCfg.h2(hs, n.x * 7 + n.y) % 100) / 100.0 * 0.5 - 0.25
	var oz := float(ViewCfg.h2(hs + 3, n.y * 5 + n.x) % 100) / 100.0 * 0.5 - 0.25
	return Vector3(n.x + 0.5 + ox, n.z * cfg.floor_h, n.y + 0.5 + oz)


func _spawn_ambient(kind: String) -> void:
	var hs := _ri(1 << 20)
	var tier := 1 + hs % 3
	var a := {"kind": kind, "hs": hs, "pose": "walk", "tier": tier, "speed": 0.5 + 0.3 * _rnd(), "wait": _rnd() * 2.0, "dir": Vector3(1, 0, 0),
		"shirt": cfg.tier_color(tier, hs % 5), "pal": (hs % 6) + ((hs / 6) % 8) * 8 + ((hs / 48) % 8) * 64}
	if kind == "gate":
		a["pos"] = _gate + Vector3((_rnd() - 0.5) * 2.6, 0, _rnd() * 1.1)
		a["home"] = a["pos"]
		a["pose"] = "stand"
		a["text"] = "성채에 들어갈 자리를 기다리는 중"
	else:
		if _street.is_empty():
			return
		a["pos"] = _street[_ri(_street.size())]
		a["text"] = "담장 밖을 지나가는 행인"
	a["to"] = a["pos"]
	agents.append(a)


func step(delta: float, t: float) -> void:
	var st: CityState = Game.state
	if st == null:
		return
	_t += delta
	var hr := t * 24.0
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.2
		var want := _targets(hr)
		var have := {}
		for a in agents:
			have[a["kind"]] = int(have.get(a["kind"], 0)) + 1
		for kind in want:
			var n: int = int(have.get(kind, 0))
			if n < int(want[kind]) and agents.size() < MAX_INST:
				for i in mini(int(want[kind]) - n, 3):
					if kind == "walk":
						if _rnd() < 0.06:
							_spawn_special(hr)
						else:
							_spawn_walker(hr)
					else:
						_spawn_ambient(kind)
	if view.actors != null:
		for lv in view.actors.pop_leavers():
			_spawn_return(lv)
	var keep: Array = []
	for a in agents:
		if _advance(a, delta):
			keep.append(a)
	agents = keep
	_render()


## 한 사람을 움직인다. false면 사라진다(목적지 문으로 들어감).
func _advance(a: Dictionary, delta: float) -> bool:
	if float(a["wait"]) > 0.0:
		a["wait"] = float(a["wait"]) - delta
		return true
	var to: Vector3 = a["to"]
	var pos: Vector3 = a["pos"]
	var d := to - pos
	var hd := Vector2(d.x, d.z)
	var dist := hd.length()
	var stepd: float = float(a["speed"]) * delta
	if dist > 0.001:
		a["dir"] = Vector3(d.x, 0, d.z) / dist
	if dist <= stepd:
		a["pos"] = to
		match str(a["kind"]):
			"walk":
				var i := int(a["i"]) + 1
				var path: Array = a["path"]
				if i >= path.size() - 1:
					if int(a.get("seat", -1)) >= 0 and view.actors != null:
						view.actors.occupy(int(a["seat"]), {"tier": a["tier"], "shirt": a["shirt"], "pal": int(a["pal"]) % 512, "hs": a["hs"], "look": a.get("look", "")}, 25.0 + 35.0 * _rnd())
					return false
				a["i"] = i
				a["to"] = _node_pos(path[i + 1], int(a["hs"]) + i + 1)
				if _rnd() < 0.04:
					a["wait"] = 0.6 + _rnd() * 1.5   # 잠깐 멈춰 두리번
			"gate":
				var home: Vector3 = a["home"]
				a["to"] = home + Vector3((_rnd() - 0.5) * 0.4, 0, (_rnd() - 0.5) * 0.4)
				a["wait"] = 1.0 + _rnd() * 3.0
			_:
				a["to"] = _street[_ri(_street.size())] if _rnd() < 0.2 else pos + Vector3(_rnd() - 0.5, 0, _rnd() - 0.5) * 2.0
				if _rnd() < 0.15:
					return false
	else:
		# 층이 바뀌는 칸에서는 위아래로(사다리) 먼저
		var np := pos + d / maxf(d.length(), 0.0001) * stepd
		if absf(d.y) > 0.05 and dist < 0.6:
			np = Vector3(pos.x + d.x * 0.1, move_toward(pos.y, to.y, stepd * 1.2), pos.z + d.z * 0.1)
		a["pos"] = np
	return true


func _render() -> void:
	var lod := CityActors.lod_for(_zoom_i)
	for i in 4:
		(_mmi[i] as MultiMeshInstance3D).visible = i == lod
	var mm: MultiMesh = (_mmi[lod] as MultiMeshInstance3D).multimesh
	var mat: ShaderMaterial = _mats[lod]
	mat.set_shader_parameter("ppu", view.ppu())
	var basis: Basis = view._cam.global_transform.basis
	var cut_y := 1000.0 if _cut < 0 else float(_cut) * cfg.floor_h + 0.05
	var n := mini(agents.size(), MAX_INST)
	for i in n:
		var a: Dictionary = agents[i]
		var pos: Vector3 = a["pos"]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		var sh: Color = a["shirt"]
		mm.set_instance_color(i, Color(sh.r, sh.g, sh.b, 0.0))
		var dir: Vector3 = a["dir"]
		var sx := dir.dot(basis.x)
		var sy := dir.dot(basis.y)
		var row := 0
		var flip := 0.0
		if absf(sx) > absf(sy) * 1.15:
			row = 1
			flip = 1.0 if sx < 0.0 else 0.0
		elif sy > 0.0:
			row = 2
		var moving: bool = float(a["wait"]) <= 0.0 and (a["to"] as Vector3).distance_to(pos) > 0.01
		var pose: String = str(a["pose"])
		if not moving and pose == "walk":
			pose = "stand"
		var fr := int(floor(_t * 7.0 * float(a["speed"]) / 0.5 + float(int(a["hs"]) % 100) * 0.07)) % 4 if moving else 0
		if not moving and pose == "stand" and fposmod(_t * 0.3 + float(int(a["hs"]) % 97) * 0.1, 1.0) < 0.25:
			pose = "look"
			fr = int(floor(_t * 0.8)) % 4
		var hide := 2.0 if pos.y > cut_y else 0.0
		mm.set_instance_custom_data(i, Color(float(PeopleSprites.pose_index(pose) * PeopleSprites.FRAMES + fr), float(row), flip + hide, float(a["pal"])))
	mm.visible_instance_count = n


func set_light(amb: Vector3, night: float, neon_gain: float, lg_origin: Vector3, lg_inv: Vector3) -> void:
	for m in _mats:
		var mat: ShaderMaterial = m
		mat.set_shader_parameter("amb", amb)
		mat.set_shader_parameter("night", night)
		mat.set_shader_parameter("neon_gain", neon_gain)
		mat.set_shader_parameter("lg_origin", lg_origin)
		mat.set_shader_parameter("lg_inv_size", lg_inv)


## 화면 점(이 Control 좌표) 근처의 주민 한 줄.
func who(screen_pos: Vector2) -> Dictionary:
	var best := -1
	var bd := 1e9
	var hpx: float = (LOD_SIZE[CityActors.lod_for(_zoom_i)] as Vector2).y * float(view._up) / maxf(view._canvas_scale, 0.01)
	var cut_y := 1000.0 if _cut < 0 else float(_cut) * cfg.floor_h + 0.05
	for i in agents.size():
		var a: Dictionary = agents[i]
		var pos: Vector3 = a["pos"]
		if pos.y > cut_y:
			continue
		var sp: Vector2 = view.project_world(pos)
		var c := sp - Vector2(0, hpx * 0.45)
		var dd := c.distance_to(screen_pos)
		if dd < maxf(hpx * 0.6, 10.0) and dd < bd:
			bd = dd
			best = i
	if best < 0:
		return {"ok": false, "text": ""}
	var ag: Dictionary = agents[best]
	var tn: String = _tier_names[clampi(int(ag.get("tier", 1)), 1, 5) - 1]
	return {"ok": true, "text": "%s · %s" % [tn, str(ag.get("text", "산책하는 중"))], "tier": int(ag.get("tier", 1)), "pos": ag["pos"]}


func expedition(_claimed: bool) -> void:
	pass
