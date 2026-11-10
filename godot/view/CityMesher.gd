class_name CityMesher
extends RefCounted
## CityMesher — CityState의 셀 → 층별 메시. 규칙 없음, 상태를 읽기만 한다.
## 다리·계단·발코니·옥탑·간판·빨래 등은 셀 배치와 seed에서 결정론적으로 파생한다(셀이 아니다).

const DIR: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(-1, 0, 0), Vector3i(0, -1, 0)]
const NRM: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
const RGT: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
const ORG: Array[Vector3] = [Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0)]
const UP := Vector3(0, 1, 0)
const UPI := Vector3i(0, 0, 1)
const TX := 1.0 / 16.0
const EPS := 0.012

const LAUNDRY: Array[String] = ["#f4f0e6", "#ff6f6f", "#5fa8e6", "#ffd45a", "#7fd08a", "#ff9ac0", "#f4f0e6", "#b58be0", "#ff9a4a", "#6fd0d0"]
const PIPES: Array[String] = ["#b5654f", "#8fb5d0", "#d8cfc0", "#6a6486", "#7fae8a"]

var cfg: ViewCfg
var atlas: PixelAtlas
var state: CityState
var fh := 0.8165
var gw := 12
var gh := 12

# prepare()가 채우는 것
var solid: Dictionary = {}        # Vector3i -> true (상자형 방)
var by_floor: Array = []          # [z] -> Array[Vector3i]
var col_h: Dictionary = {}        # Vector2i -> float (층 단위, 그림자용)
var top_z: int = 0
var bridges: Dictionary = {}      # Vector3i(pos)*4+d 키 -> 상대 셀
var stairs: Dictionary = {}       # (x,y,d) 키 -> [z0, z1]
var chimney_cols: Dictionary = {} # Vector2i -> fx 종류
var occupied: Dictionary = {}     # owner id -> true (사는 가구)
var signs: Dictionary = {}        # fkey(p,d) -> "big"|"blade"|"plaque"|"board" (사업체당 하나)

# 층 하나를 짓는 동안
var mb: MeshBuf
var lights: Array = []
var emitters: Array = []


func setup(c: ViewCfg, a: PixelAtlas) -> void:
	cfg = c
	atlas = a
	fh = c.floor_h
	gw = c.grid.x
	gh = c.grid.y


static func fkey(p: Vector3i, d: int) -> int:
	return ((p.x + 8) * 64 + (p.y + 8)) * 64 * 4 + p.z * 4 + d


func is_box(c: Dictionary) -> bool:
	if c.is_empty():
		return false
	var kind: String = str(c.get("kind", ""))
	if kind == "site":
		return false
	return str(cfg.recipe(kind, str(c.get("type", ""))).get("form", "box")) == "box"


func prepare(s: CityState) -> void:
	state = s
	solid.clear()
	col_h.clear()
	bridges.clear()
	stairs.clear()
	chimney_cols.clear()
	occupied.clear()
	by_floor.clear()
	top_z = 0
	for z in cfg.grid.z + 2:
		by_floor.append([])
	for h in s.households.values():
		if h.get("home", null) != null:
			occupied[int(h.get("id", 0))] = true
	for p in s.cells:
		var c: Dictionary = s.cells[p]
		if p.z >= by_floor.size():
			continue
		by_floor[p.z].append(p)
		top_z = maxi(top_z, p.z + 1)
		var col := Vector2i(p.x, p.y)
		var kind: String = str(c.get("kind", ""))
		var rec: Dictionary = cfg.recipe(kind, str(c.get("type", "")))
		var hh := float(p.z)
		if is_box(c):
			solid[p] = true
			hh = float(p.z + 1)
		elif kind == "site":
			hh = float(p.z) + clampf(float(c.get("progress", 0.0)), 0.0, 1.0) * 0.9
		else:
			var form: String = str(rec.get("form", "box"))
			hh = float(p.z) + (0.0 if form == "open" else 0.6)
		col_h[col] = maxf(float(col_h.get(col, 0.0)), hh)
		if rec.get("chimney", false) and is_box(c) and ViewCfg.h2(col.x * 37 + col.y, 3) % 3 != 0:
			chimney_cols[col] = str(rec.get("fx", "smoke"))
	for z in by_floor.size():
		by_floor[z].sort()
	_derive_bridges()
	_derive_stairs()
	_alloc_signs()


func height_floors(col: Vector2i) -> float:
	return float(col_h.get(col, 0.0))


func _derive_bridges() -> void:
	# 한 칸 틈을 사이에 둔 같은 층의 두 방 → 판자 다리
	var used: Dictionary = {}
	for p in solid:
		if p.z < 1:
			continue
		for d in [0, 1]:
			var mid: Vector3i = p + DIR[d]
			var far: Vector3i = p + DIR[d] * 2
			if not solid.has(far) or state.cells.has(mid):
				continue
			if float(col_h.get(Vector2i(mid.x, mid.y), 0.0)) > float(p.z) - 0.5 and state.cells.has(Vector3i(mid.x, mid.y, p.z - 1)) == false:
				pass
			var gap := Vector3i(mid.x, mid.y, d)
			var last: int = int(used.get(gap, -9))
			var hsh := ViewCfg.h3(int(state.cells[p].get("seed", 0)), int(state.cells[far].get("seed", 0)), d + 11)
			if hsh % 100 < 42 and p.z - last >= 2:
				used[gap] = p.z
				bridges[fkey(p, d)] = far
				bridges[fkey(far, (d + 2) % 4)] = p


func _derive_stairs() -> void:
	# 바깥 공기에 2층 이상 연속으로 드러난 기둥 옆면 일부에 지그재그 외벽 계단
	for x in gw:
		for y in gh:
			var h := 0
			while solid.has(Vector3i(x, y, h)):
				h += 1
			if h < 2:
				continue
			for d in 4:
				var nb := Vector2i(x + DIR[d].x, y + DIR[d].y)
				var z0 := int(ceil(float(col_h.get(nb, 0.0))))
				if state.cells.has(Vector3i(nb.x, nb.y, z0)):
					continue
				if h - z0 < 2:
					continue
				var hsh := ViewCfg.h3(x * 31 + y, d, int(state.rng_seed) + 77)
				if hsh % 100 < 13:
					var ok := true
					for z in range(z0, mini(h, z0 + 5)):
						if bridges.has(fkey(Vector3i(x, y, z), d)) or state.cells.has(Vector3i(nb.x, nb.y, z)):
							ok = false
					if ok:
						stairs[Vector3i(x, y, d)] = [z0, mini(h, z0 + 5)]


# ------------------------------------------------------------------ 좌표 도우미
func fp(p: Vector3i, d: int, u: float, v: float, w: float) -> Vector3:
	return Vector3(p.x, 0.0, p.y) + ORG[d] + RGT[d] * u + Vector3(0.0, (float(p.z) + v) * fh, 0.0) + NRM[d] * w


func tile(name: String) -> Rect2:
	return Rect2(atlas.rect(name))


func sub(r: Rect2, x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(r.position.x + x, r.position.y + y, w, h)


## 벽면에 평행한 쿼드. r의 (u0..u1, v0..v1)에 해당하는 부분만 잘라 쓴다(크롭).
func fquad(p: Vector3i, d: int, u0: float, u1: float, v0: float, v1: float, w: float, r: Rect2, c: Color = MeshBuf.WHITE, rnd: float = 0.0, kind: float = 0.0, crop: bool = true) -> void:
	var rr := r
	if crop:
		rr = Rect2(r.position.x + u0 * 16.0, r.position.y + (1.0 - v1) * 16.0, (u1 - u0) * 16.0, (v1 - v0) * 16.0)
	mb.quad(fp(p, d, u0, v1, w), fp(p, d, u1, v1, w), fp(p, d, u1, v0, w), fp(p, d, u0, v0, w), NRM[d], rr, c, rnd, kind)


## 벽면 기준 상자. faces: 1=앞 2=왼 4=오른 8=위 16=아래
func fbox(p: Vector3i, d: int, u0: float, u1: float, v0: float, v1: float, w0: float, w1: float, side_r: Rect2, top_r: Rect2, c: Color = MeshBuf.WHITE, faces: int = 15, rnd: float = 0.0, kind: float = 0.0, top_c: Color = Color(-1, 0, 0)) -> void:
	var uw := minf((u1 - u0) * 16.0, side_r.size.x)
	var vh := minf((v1 - v0) * 16.0, side_r.size.y)
	var dw := minf((w1 - w0) * 16.0, side_r.size.x)
	if faces & 1:
		mb.quad(fp(p, d, u0, v1, w1), fp(p, d, u1, v1, w1), fp(p, d, u1, v0, w1), fp(p, d, u0, v0, w1), NRM[d], Rect2(side_r.position, Vector2(uw, vh)), c, rnd, kind)
	if faces & 2:
		mb.quad(fp(p, d, u0, v1, w0), fp(p, d, u0, v1, w1), fp(p, d, u0, v0, w1), fp(p, d, u0, v0, w0), -RGT[d], Rect2(side_r.position, Vector2(dw, vh)), c, rnd, kind)
	if faces & 4:
		mb.quad(fp(p, d, u1, v1, w1), fp(p, d, u1, v1, w0), fp(p, d, u1, v0, w0), fp(p, d, u1, v0, w1), RGT[d], Rect2(side_r.position, Vector2(dw, vh)), c, rnd, kind)
	var tc := c if top_c.r < 0.0 else top_c
	if faces & 8:
		mb.quad(fp(p, d, u0, v1, w0), fp(p, d, u1, v1, w0), fp(p, d, u1, v1, w1), fp(p, d, u0, v1, w1), UP, Rect2(top_r.position, Vector2(minf(uw, top_r.size.x), minf(dw, top_r.size.y))), tc, rnd, kind)
	if faces & 16:
		mb.quad(fp(p, d, u0, v0, w1), fp(p, d, u1, v0, w1), fp(p, d, u1, v0, w0), fp(p, d, u0, v0, w0), -UP, Rect2(top_r.position, Vector2(minf(uw, top_r.size.x), minf(dw, top_r.size.y))), c, rnd, kind)


func wbox(a: Vector3, b: Vector3, side: String, top: String, c: Color = MeshBuf.WHITE, faces: int = 31, rnd: float = 0.0, kind: float = 0.0, top_c: Color = Color(-1, 0, 0)) -> void:
	mb.box(a, b, tile(side), tile(top), fh, c, faces, rnd, kind, top_c)


func cellv(p: Vector3i) -> Vector3:
	return Vector3(p.x, float(p.z) * fh, p.y)


func light(pos: Vector3, c: Color, radius: float, warm: float = 0.0) -> void:
	lights.append({"pos": pos, "color": c, "r": radius, "warm": warm})


func emitter(pos: Vector3, type: String) -> void:
	emitters.append({"pos": pos, "type": type})


# ------------------------------------------------------------------ 외관: 층 하나
func build_floor(z: int) -> Dictionary:
	mb = MeshBuf.new()
	lights = []
	emitters = []
	if z < by_floor.size():
		for p in by_floor[z]:
			_build_cell(p, state.cells[p])
	return {"mesh": mb.commit(), "lights": lights, "emitters": emitters}


func _build_cell(p: Vector3i, c: Dictionary) -> void:
	var kind: String = str(c.get("kind", ""))
	var type: String = str(c.get("type", ""))
	var rec: Dictionary = cfg.recipe(kind, type)
	var seed_v: int = int(c.get("seed", 0)) + p.x * 7 + p.y * 13 + p.z * 29
	if kind == "site":
		_build_site(p, c, seed_v)
		return
	match str(rec.get("form", "box")):
		"open":
			_build_open(p, c, rec, seed_v)
		"shed":
			_build_shed(p, c, rec, seed_v)
		"tank":
			_build_tank(p, c, rec, seed_v)
		"loft":
			_build_loft(p, c, rec, seed_v)
		"shrine":
			_build_shrine(p, c, rec, seed_v)
		_:
			_build_box(p, c, rec, seed_v)


func _age_variant(c: Dictionary, seed_v: int) -> int:
	var age: int = maxi(int(state.day) - int(c.get("built_day", state.day)), 0)
	var r := ViewCfg.h2(seed_v, 5) % 100
	if age >= 14:
		return 3 if r < 35 else (2 if r < 75 else 1)
	if age >= 5:
		return 2 if r < 30 else (1 if r < 70 else 0)
	return 1 if r < 30 else 0


func _build_box(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int) -> void:
	var mat: String = cfg.material_key(str(c.get("material", "")))
	var kind: String = str(c.get("kind", ""))
	var var_i := _age_variant(c, seed_v)
	var base := cellv(p)
	# 장사 칸: 드러난 면 중 하나가 "앞"
	var front := -1
	if kind != "housing":
		var best := -1
		for k in 4:
			var d: int = (k + ViewCfg.h2(seed_v, 3)) % 4
			var nb: Vector3i = p + DIR[d]
			if not state.cells.has(nb):
				var score := 2 if not state.cells.has(nb + DIR[d]) else 1
				if score > best:
					best = score
					front = d
	for d in 4:
		if signs.has(fkey(p, d)):
			front = d   # 간판이 걸린 면이 곧 가게 앞
	for d in 4:
		var nb2: Vector3i = p + DIR[d]
		if solid.has(nb2):
			continue
		var wv := (var_i + (ViewCfg.h2(seed_v, d) % 2)) % 4 if var_i < 3 else 3
		var wr := tile("wall_%s_%d" % [mat, wv])
		mb.quad(fp(p, d, 0, 1, 0), fp(p, d, 1, 1, 0), fp(p, d, 1, 0, 0), fp(p, d, 0, 0, 0), NRM[d], wr)
		if state.cells.has(nb2):
			continue  # 옆이 열린 구조물(텃밭·좌판)이면 벽만
		_facade(p, d, c, rec, mat, seed_v, d == front)
	# 지붕
	var above: Vector3i = p + UPI
	if not solid.has(above):
		var rv := ViewCfg.h2(seed_v, 9) % 3
		var rr := tile("roof_%s_%d" % [mat, rv])
		var y := base.y + fh
		mb.quad(Vector3(base.x, y, base.z), Vector3(base.x + 1, y, base.z), Vector3(base.x + 1, y, base.z + 1), Vector3(base.x, y, base.z + 1), UP, rr)
		if not state.cells.has(above):
			_rooftop(p, c, rec, mat, seed_v)


# ------------------------------------------------------------------ 외벽 한 면
func _facade(p: Vector3i, d: int, c: Dictionary, rec: Dictionary, mat: String, seed_v: int, is_front: bool) -> void:
	var kind: String = str(c.get("kind", ""))
	var type: String = str(c.get("type", ""))
	var hs := ViewCfg.h2(seed_v, 100 + d)
	var r1 := float(hs % 1000) / 1000.0
	var r2 := float((hs / 1000) % 1000) / 1000.0
	var r3 := float(ViewCfg.h2(hs, 7) % 1000) / 1000.0
	var wrnd := float(ViewCfg.h2(hs, 21) % 997) / 997.0
	var nb: Vector3i = p + DIR[d]
	var room2: bool = not state.cells.has(nb + DIR[d])     # 앞에 두 칸 비었나
	var below_open: bool = p.z > 0 and not state.cells.has(nb - UPI) and float(col_h.get(Vector2i(nb.x, nb.y), 0.0)) < float(p.z) - 0.1
	var ground := p.z == 0
	# 창틀 색은 자재(=탑)마다 묶는다: 같은 탑은 같은 창틀 → 큰 덩어리가 깨끗하게 읽힌다
	var frames: Array = cfg.material(mat).get("frames", ["a"])
	var fk: String = str(frames[ViewCfg.h2(p.x * 5 + p.y * 3 + (p.z / 3), 31) % frames.size()]) if not frames.is_empty() else "a"
	var owner: int = int(c.get("owner", 0))
	var lived: bool = kind != "housing" or occupied.has(owner)
	var wkind := MeshBuf.K_WINDOW if kind == "housing" else MeshBuf.K_BIZ
	if not lived:
		wkind = MeshBuf.K_WINDOW_OFF
	var sk := Vector3i(p.x, p.y, d)

	# 굴뚝 배관·물 배관: 기둥 옆면 단위로 이어진다
	var ph := ViewCfg.h3(p.x * 17 + p.y, d, int(state.rng_seed) + 5)
	if ph % 100 < 38:
		var top_f := 1 + (ph / 100) % 9
		if p.z < top_f:
			var pu := 0.0625 + float((ph / 1000) % 2) * 0.8125
			var npipe := 1 + (ph / 7) % 2
			for i in npipe:
				var pc := Color(PIPES[(ph / 13 + i) % PIPES.size()])
				var uu := pu + float(i) * 0.125 * (1.0 if pu < 0.5 else -1.0)
				fbox(p, d, uu, uu + 0.0625, 0.0, 1.0, 0.0, 0.06, tile("white"), tile("white"), pc, 7)

	# 다리로 이어진 면: 문만
	if bridges.has(fkey(p, d)):
		fquad(p, d, 0, 1, 0, 1, EPS, tile("door_%d" % (hs % 4)), MeshBuf.WHITE, wrnd, wkind)
		if d < 2:
			_bridge(p, d)
		return

	# 외벽 계단
	if stairs.has(sk):
		var rg: Array = stairs[sk]
		if p.z >= rg[0] and p.z < rg[1]:
			_stair_flight(p, d, p.z - int(rg[0]))
			fquad(p, d, 0, 1, 0, 1, EPS, tile("door_%d" % (hs % 4)), MeshBuf.WHITE, wrnd, wkind)
			return

	var win: String = str(rec.get("window", "std"))

	# ── 가게·시설의 앞면 ──
	if kind != "housing":
		if is_front:
			var wt := "shop_a"
			match win:
				"shop":
					wt = ["shop_a", "shop_c", "shop_b"][hs % 3]
				"shutter":
					wt = "shutter_0" if hs % 4 != 0 else "shutter_1"
				"slit":
					wt = "win_slit"
				"none":
					wt = ""
				"small":
					wt = "win_small_" + fk
				"wide":
					wt = "win_wide_" + fk
				_:
					wt = "win_std_" + fk
			if wt != "":
				fquad(p, d, 0, 1, 0, 1, EPS, tile(wt), MeshBuf.WHITE, wrnd, wkind)
			if (win == "slit" or win == "none") and ground:
				fquad(p, d, 0, 1, 0, 1, EPS * 1.5, tile("door_%d" % (hs % 4)), MeshBuf.WHITE, wrnd, wkind)
			var aw: String = str(rec.get("awning", ""))
			if aw != "" and (ground or r1 < 0.5):
				_awning(p, d, 0.03, 0.97, 0.72, 0.16, 0.34, ViewCfg.col(aw))
			if signs.has(fkey(p, d)):
				_sign(p, d, c, rec, seed_v, str(signs[fkey(p, d)]))
			var fx: String = str(rec.get("fx", ""))
			if fx == "steam":
				emitter(fp(p, d, 0.8, 0.9, 0.12), "steam")
				fbox(p, d, 0.75, 0.875, 0.8, 0.95, 0.0, 0.12, tile("white"), tile("white"), Color("#8f8ea6"), 15)
			elif fx == "sparks":
				emitter(fp(p, d, 0.5, 0.3, 0.2), "sparks")
			var glow: String = str(rec.get("glow", ""))
			if glow != "":
				light(fp(p, d, 0.5, 0.4, 0.4), cfg.neon(glow), 1.6)
			else:
				light(fp(p, d, 0.5, 0.45, 0.35), Color(1, 1, 1), 1.2, 0.8)
		else:
			if win != "none" and r1 < 0.55:
				fquad(p, d, 0, 1, 0, 1, EPS, tile("win_small_" + fk if win != "slit" else "win_slit"), MeshBuf.WHITE, wrnd, wkind)
			if r2 < 0.3 and state.power_level > 0:
				_ac(p, d, 0.56, 0.12)
			if r3 < 0.15:
				_pipe_h(p, d, hs)
		return

	# ── 주거 ──
	var bay := false
	var bay_p := 0.26 if (mat == "wood" or mat == "scrap" or mat == "sheet") else 0.13
	if p.z >= 1 and below_open and r3 < bay_p:
		bay = true
	var w0 := 0.0
	if bay:
		# 반 칸 돌출(증축한 방): 다른 자재로 덧댄 느낌
		var bm: String = mat
		var alt := ["sheet", "wood", "scrap"]
		if hs % 3 != 0:
			bm = cfg.material_key(alt[(hs / 3) % 3])
		var depth := 0.3 + 0.0625 * float(hs % 3)
		var bu0 := 0.0625 * float((hs / 5) % 2)
		var bu1 := 1.0 - 0.0625 * float((hs / 11) % 2)
		fbox(p, d, bu0, bu1, 0.0, 1.0, 0.0, depth, tile("wall_%s_%d" % [bm, hs % 3]), tile("roof_%s_%d" % [bm, hs % 3]), MeshBuf.WHITE, 31)
		w0 = depth
	var wt2 := "win_std_" + fk
	match win:
		"small":
			wt2 = "win_small_" + fk
		"wide":
			wt2 = ("win_wide_" + fk) if r1 < 0.7 else ("win_tall_" + fk)
		"cage":
			wt2 = "win_cage"
		"none":
			wt2 = ""
		_:
			wt2 = ("win_std_" + fk) if r1 < 0.75 else ("win_wide_" + fk)
	if not lived and r2 < 0.5:
		wt2 = "win_board"
	if wt2 != "" and (r1 < 0.93 or bay):
		fquad(p, d, 0, 1, 0, 1, w0 + EPS, tile(wt2), MeshBuf.WHITE, wrnd, wkind)
		if lived:
			light(fp(p, d, 0.5, 0.5, w0 + 0.35), Color(1, 1, 1), 1.0, 0.55)
	if not lived:
		return
	# 가장자리 잡동사니
	var cage_p := 0.14
	match type:
		"cage":
			cage_p = 0.7
		"flat":
			cage_p = 0.22
		"shack":
			cage_p = 0.03
	if mat == "concrete" or mat == "brick":
		cage_p += 0.08
	var has_cage := false
	if not bay and p.z >= 1 and r2 < cage_p:
		has_cage = true
		_cage_balcony(p, d, hs)
	if r3 > 0.74 and not has_cage and p.z >= 1 and room2:
		_laundry_pole(p, d, hs, w0)
	elif r3 > 0.62 and r3 <= 0.74 and state.power_level > 0 and not has_cage:
		_ac(p, d, 0.56, 0.1, w0)
	if not has_cage and not bay and ViewCfg.h2(hs, 41) % 100 < 14:
		_awning(p, d, 0.15, 0.85, 0.82, 0.1, 0.2, Color(["#5d9a62", "#d85f5f", "#4f8fb5", "#e0a23c"][hs % 4]))
	if type == "flat" and not has_cage and ViewCfg.h2(hs, 43) % 100 < 30:
		var pr := tile("plant_%d" % (hs % 3))
		mb.quad2(fp(p, d, 0.2, 0.62, w0 + 0.06), fp(p, d, 0.7, 0.62, w0 + 0.06), fp(p, d, 0.7, 0.12, w0 + 0.06), fp(p, d, 0.2, 0.12, w0 + 0.06), NRM[d], sub(pr, 0, 0, 16, 16))


func _cage_balcony(p: Vector3i, d: int, hs: int) -> void:
	var depth := 0.1875 + 0.0625 * float(hs % 2)
	var u0 := 0.125
	var u1 := 0.875
	var v0 := 0.125
	var v1 := 0.75
	var ct := tile("cage_%d" % int(cfg.material(cfg.material_key(str(state.cells[p].get("material", "")))).get("cage", 0)))
	# 바닥판 + 지붕판
	fbox(p, d, u0, u1, v0 - 0.0625, v0, 0.0, depth, tile("white"), tile("white"), Color("#8f8aa6"), 31)
	var topc := Color(["#a9cbcb", "#c98f5e", "#8fb5d0", "#d8cfc0"][(hs / 7) % 4])
	fbox(p, d, u0 - 0.03, u1 + 0.03, v1, v1 + 0.0625, 0.0, depth + 0.04, tile("white"), tile("white"), topc, 31)
	# 창살(앞·양옆)
	fbox(p, d, u0, u1, v0, v1, 0.0, depth, ct, ct, MeshBuf.WHITE, 7)
	# 안에 걸린 빨래/화분
	var k := (hs / 17) % 4
	if k < 3:
		var cc := Color(LAUNDRY[(hs / 5) % LAUNDRY.size()])
		var cr := tile(["cloth_shirt", "cloth_towel", "cloth_pants"][k])
		mb.cloth(fp(p, d, 0.25, 0.7, depth * 0.55), fp(p, d, 0.75, 0.7, depth * 0.55), fp(p, d, 0.75, 0.2, depth * 0.55), fp(p, d, 0.25, 0.2, depth * 0.55), NRM[d], cr, cc, float(hs % 100) / 100.0)
	else:
		var pr := tile("plant_%d" % (hs % 3))
		mb.quad2(fp(p, d, 0.25, 0.62, depth * 0.5), fp(p, d, 0.75, 0.62, depth * 0.5), fp(p, d, 0.75, 0.12, depth * 0.5), fp(p, d, 0.25, 0.12, depth * 0.5), NRM[d], pr)


func _laundry_pole(p: Vector3i, d: int, hs: int, w0: float) -> void:
	var u := 0.25 + 0.0625 * float(hs % 8)
	var v := 0.72
	var len := 0.5 + 0.0625 * float((hs / 3) % 4)
	fbox(p, d, u - 0.02, u + 0.02, v, v + 0.04, w0, w0 + len, tile("white"), tile("white"), Color("#d9b45a"), 31)
	var n := 2 + (hs / 11) % 2
	var w := w0 + 0.08
	for i in n:
		var cw := 0.1875 if (hs / (i + 2)) % 3 != 0 else 0.25
		var chh := 0.3 + 0.0625 * float((hs / (i + 5)) % 4)
		var cc := Color(LAUNDRY[(hs / (i * 7 + 3)) % LAUNDRY.size()])
		var a := fp(p, d, u, v, w)
		var b := fp(p, d, u, v, w + cw)
		var a2 := fp(p, d, u, v - chh, w)
		var b2 := fp(p, d, u, v - chh, w + cw)
		mb.cloth(a, b, b2, a2, RGT[d], sub(tile("white"), 0, 0, 4, 4), cc, float((hs + i * 37) % 100) / 100.0)
		w += cw + 0.03
		if w > w0 + len:
			break


func _ac(p: Vector3i, d: int, u: float, v: float, w0: float = 0.0) -> void:
	fbox(p, d, u, u + 0.375, v, v + 0.3125, w0, w0 + 0.1875, tile("ac"), tile("white"), MeshBuf.WHITE, 15, 0.0, 0.0, Color("#f8f4e8"))


func _pipe_h(p: Vector3i, d: int, hs: int) -> void:
	var v := 0.25 + 0.0625 * float(hs % 6)
	fbox(p, d, 0.0, 1.0, v, v + 0.0625, 0.0, 0.05, tile("white"), tile("white"), Color(PIPES[hs % PIPES.size()]), 9)


func _awning(p: Vector3i, d: int, u0: float, u1: float, v_top: float, drop: float, depth: float, c: Color) -> void:
	var r := tile("awning")
	var rr := Rect2(r.position, Vector2((u1 - u0) * 16.0, 6.0))
	var n := (UP * depth + NRM[d] * drop * fh).normalized()
	mb.quad(fp(p, d, u0, v_top, 0.0), fp(p, d, u1, v_top, 0.0), fp(p, d, u1, v_top - drop, depth), fp(p, d, u0, v_top - drop, depth), n, rr, c)
	mb.quad(fp(p, d, u1, v_top, 0.0), fp(p, d, u0, v_top, 0.0), fp(p, d, u0, v_top - drop, depth), fp(p, d, u1, v_top - drop, depth), -UP, rr, c)
	# 앞 자락
	fquad(p, d, u0, u1, v_top - drop - 0.0625, v_top - drop, depth, Rect2(r.position + Vector2(0, 14), Vector2((u1 - u0) * 16.0, 1.0)), c, 0.0, 0.0, false)


# ------------------------------------------------------------------ 간판
# 간판은 "사업체 하나에 하나"(가장 트인 외벽면). prepare()의 _alloc_signs()가 자리를 정한다.
# 크기 4종: big(큰 세로 돌출, 글자 1:1) / blade(작은 돌출, 글자 1/2) / plaque(문 옆 작은 세로판) / board(문 위 작은 가로판)
func _alloc_signs() -> void:
	signs.clear()
	var groups: Dictionary = {}
	for p in state.cells:
		var c: Dictionary = state.cells[p]
		var kind: String = str(c.get("kind", ""))
		if (kind != "business" and kind != "facility") or not solid.has(p):
			continue
		var rec: Dictionary = cfg.recipe(kind, str(c.get("type", "")))
		var style: String = str(rec.get("sign_style", "none"))
		if style == "none":
			continue
		if ViewCfg.sign_text(kind, str(c.get("type", ""))) == "" and style != "lantern":
			continue
		var owner: int = int(c.get("owner", 0))
		var key: Variant = owner if (kind == "business" and owner != 0) else p
		if not groups.has(key):
			groups[key] = []
		groups[key].append(p)
	var cands: Array = []
	for key in groups:
		var best_s := -1.0
		var best_p := Vector3i.ZERO
		var best_d := 0
		var best_open := 0
		var cells_sorted: Array = groups[key]
		cells_sorted.sort()
		for p in cells_sorted:
			for d in 4:
				var nb: Vector3i = p + DIR[d]
				if state.cells.has(nb):
					continue
				var open := 1
				for k in [2, 3]:
					var q: Vector3i = p + DIR[d] * k
					if state.cells.has(q) or float(col_h.get(Vector2i(q.x, q.y), 0.0)) > float(p.z) + 0.5:
						break
					open += 1
				var sc := float(open) * 10.0 + (6.0 if p.z == 0 else 0.0) - float(p.z) * 0.4 + float(ViewCfg.h3(p.x * 9 + p.y, p.z, d) % 40) / 10.0
				if sc > best_s:
					best_s = sc
					best_p = p
					best_d = d
					best_open = open
		if best_s >= 0.0:
			var c2: Dictionary = state.cells[best_p]
			cands.append({"p": best_p, "d": best_d, "open": best_open, "score": best_s, "text": ViewCfg.sign_text(str(c2.get("kind", "")), str(c2.get("type", ""))), "seed": int(c2.get("seed", 0))})
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["score"] != y["score"]:
			return x["score"] > y["score"]
		return x["p"] < y["p"])
	var placed: Array = []
	for cd in cands:
		var p: Vector3i = cd["p"]
		var d: int = cd["d"]
		var hs := ViewCfg.h2(int(cd["seed"]), 300 + d)
		var same_near := false
		var big_near := false
		var any_near := 0
		for pl in placed:
			var q: Vector3i = pl["p"]
			var dist := absi(q.x - p.x) + absi(q.y - p.y)
			var dz := absi(q.z - p.z)
			if pl["text"] == cd["text"] and dist <= 2 and dz <= 3:
				same_near = true
			if pl["size"] == "big" and dist <= 2 and dz <= 3:
				big_near = true
			if dist <= 1 and dz <= 1 and int(pl["d"]) == d:
				any_near += 1
		var size := "plaque"
		var r := hs % 100
		if same_near:
			# 같은 글자가 바로 옆에 이미 걸려 있으면 작은 문패만(혹은 생략)
			if r < 82:
				continue
			size = "plaque"
		elif int(cd["open"]) >= 2 and r < 20 and not big_near:
			size = "big"
		elif int(cd["open"]) >= 2 and r < 50:
			size = "blade"
		elif r < 78:
			size = "plaque"
		else:
			size = "board"
		if any_near >= 2 and size != "big":
			continue
		signs[fkey(p, d)] = size
		placed.append({"p": p, "d": d, "text": cd["text"], "size": size})


func _sign(p: Vector3i, d: int, c: Dictionary, rec: Dictionary, seed_v: int, size: String) -> void:
	var kind: String = str(c.get("kind", ""))
	var type: String = str(c.get("type", ""))
	var style: String = str(rec.get("sign_style", "none"))
	var text := ViewCfg.sign_text(kind, type)
	var col := cfg.neon(rec.get("sign_color", "yellow"))
	var hs := ViewCfg.h2(int(c.get("seed", 0)), 300 + d)
	if style == "none":
		return
	if style == "lantern":
		for i in 2:
			var u := 0.2 + 0.6 * float(i)
			var lr := tile("lantern")
			mb.quad2(fp(p, d, u - 0.25, 0.95, 0.2), fp(p, d, u + 0.25, 0.95, 0.2), fp(p, d, u + 0.25, 0.45, 0.2), fp(p, d, u - 0.25, 0.45, 0.2), NRM[d], sub(lr, 0, 0, 16, 8))
		light(fp(p, d, 0.5, 0.6, 0.3), Color("#ff6a4a"), 1.4)
	if text == "":
		return
	var neon_style := style == "neon"
	var horizontal := size == "board"
	var tr := Rect2(atlas.sign_rect(text, not horizontal))
	if tr.size.x <= 0.0:
		return
	var sc := 1.0 if size == "big" else 0.5
	var board := _neon_board(col, hs) if neon_style else Color(["#f4ecd8", "#c2463c", "#3f8f6a", "#f4ecd8"][hs % 4])
	var tcol := col
	if not neon_style:
		tcol = Color("#c2463c") if board.r > 0.9 else Color("#fff6e0")
		if board.r > 0.9 and hs % 3 == 0:
			tcol = Color("#3b3558")
	var tk := MeshBuf.K_NEON if neon_style else MeshBuf.K_PLAIN
	var rnd := float(hs % 991) / 991.0
	var gw_t := tr.size.x * sc          # 글자 영역(텍셀)
	var gh_t := tr.size.y * sc
	if size == "big" or size == "blade":
		# 벽에 수직으로 내민 세로 간판(양면)
		var bw := (gw_t + 2.0) * TX
		var bh := (gh_t + 3.0) / 16.0
		var u := 0.0625 if hs % 2 == 0 else 0.9375
		var v0 := (0.35 if p.z == 0 else (0.1 - float(hs % 3) * 0.1)) if size == "big" else (0.42 + 0.0625 * float(hs % 3))
		var w0 := 0.09
		var th := 0.03
		fbox(p, d, u - th, u + th, v0, v0 + bh, w0, w0 + bw, tile("white"), tile("white"), board, 31)
		fbox(p, d, u - 0.02, u + 0.02, v0 + bh - 0.08, v0 + bh - 0.03, 0.0, w0, tile("white"), tile("white"), Color("#5a5674"), 31)
		var ty1 := v0 + bh - 1.5 / 16.0
		var ty0 := ty1 - gh_t / 16.0
		var tw0 := w0 + TX
		var tw1 := tw0 + gw_t * TX
		mb.quad(fp(p, d, u + th + 0.014, ty1, tw1), fp(p, d, u + th + 0.014, ty1, tw0), fp(p, d, u + th + 0.014, ty0, tw0), fp(p, d, u + th + 0.014, ty0, tw1), RGT[d], tr, tcol, rnd, tk)
		mb.quad(fp(p, d, u - th - 0.014, ty1, tw0), fp(p, d, u - th - 0.014, ty1, tw1), fp(p, d, u - th - 0.014, ty0, tw1), fp(p, d, u - th - 0.014, ty0, tw0), -RGT[d], tr, tcol, rnd, tk)
		if neon_style and size == "big":
			# 네온 테두리 관(위·아래)
			for sgn in [-1.0, 1.0]:
				var uu: float = u + sgn * (th + 0.014)
				var nn: Vector3 = RGT[d] * sgn
				var es := sub(tile("white"), 0, 0, 2, 2)
				for q in [[v0 + bh - 0.03, v0 + bh], [v0, v0 + 0.03]]:
					var wa := w0 if sgn < 0.0 else w0 + bw
					var wb := w0 + bw if sgn < 0.0 else w0
					mb.quad(fp(p, d, uu, q[1], wa), fp(p, d, uu, q[1], wb), fp(p, d, uu, q[0], wb), fp(p, d, uu, q[0], wa), nn, es, col, rnd, MeshBuf.K_NEON)
		if neon_style:
			light(fp(p, d, u, v0 + bh * 0.5, w0 + bw * 0.5), col, 2.0 if size == "big" else 1.3)
	else:
		# 벽에 붙인 작은 판: plaque = 문 옆 세로, board = 문 위 가로
		var bw2 := (gw_t + 2.0) / 16.0
		var bh2 := (gh_t + 2.0) / 16.0
		var u0 := 0.0625 if hs % 2 == 0 else 1.0 - 0.0625 - bw2
		var v0b := 0.3 + 0.0625 * float(hs % 3)
		if horizontal:
			u0 = clampf(0.5 - bw2 * 0.5, 0.0, 1.0 - bw2)
			v0b = 1.0 - bh2 - 0.03
		fbox(p, d, u0, u0 + bw2, v0b, v0b + bh2, 0.0, 0.05, tile("white"), tile("white"), board, 15)
		fquad(p, d, u0 + TX, u0 + TX + gw_t / 16.0, v0b + TX, v0b + TX + gh_t / 16.0, 0.066, tr, tcol, rnd, tk, false)
		if neon_style:
			light(fp(p, d, u0 + bw2 * 0.5, v0b + bh2 * 0.5, 0.3), col, 1.2)


## 네온 간판의 판 색: 낮에도 색이 보이는 어두운 중간톤(글자색과 보색에 가깝게).
func _neon_board(col: Color, hs: int) -> Color:
	var opts: Array[String] = ["#9a4a6e", "#3a8580", "#4f62a8", "#a8484a", "#62549a"]
	var best := Color(opts[hs % opts.size()])
	if absf(best.h - col.h) < 0.12:
		best = Color(opts[(hs + 2) % opts.size()])
	return best


# ------------------------------------------------------------------ 다리·계단
func _bridge(p: Vector3i, d: int) -> void:
	var pk := tile("plank")
	fbox(p, d, 0.3125, 0.6875, -0.0625, 0.0, 0.0, 1.0, pk, pk, MeshBuf.WHITE, 30)
	var rl := tile("rail")
	for u in [0.3125, 0.6875]:
		mb.quad2(fp(p, d, u, 0.5, 0.0), fp(p, d, u, 0.5, 1.0), fp(p, d, u, 0.0, 1.0), fp(p, d, u, 0.0, 0.0), -RGT[d], sub(rl, 0, 6, 16, 10))
	emitter(fp(p, d, 0.5, 0.02, 0.5), "walk_bridge:%d" % d)


func _stair_flight(p: Vector3i, d: int, i: int) -> void:
	var pk := tile("plank")
	var w0 := 0.02
	var w1 := 0.3
	var ua := 0.08
	var ub := 0.92
	if i % 2 == 1:
		ua = 0.92
		ub = 0.08
	var a0 := fp(p, d, ua, 0.0, w0)
	var a1 := fp(p, d, ua, 0.0, w1)
	var b0 := fp(p, d, ub, 0.88, w0)
	var b1 := fp(p, d, ub, 0.88, w1)
	var n := UP
	var sr := sub(pk, 0, 0, 16, 5)
	if i % 2 == 0:
		mb.quad(a0, b0, b1, a1, n, sr)
		mb.quad(b0, a0, a1, b1, -UP, sr, Color(0.7, 0.66, 0.74))
	else:
		mb.quad(b0, a0, a1, b1, n, sr)
		mb.quad(a0, b0, b1, a1, -UP, sr, Color(0.7, 0.66, 0.74))
	# 옆판(바깥쪽) — 계단 실루엣
	var c := Color("#8f6f5a")
	var o := Vector3(0, 0.12 * fh, 0)
	if i % 2 == 0:
		mb.quad(a1 + o, b1 + o, b1, a1, NRM[d], sub(tile("white"), 0, 0, 4, 2), c)
	else:
		mb.quad(b1 + o, a1 + o, a1, b1, NRM[d], sub(tile("white"), 0, 0, 4, 2), c)
	# 층참
	var lu0 := minf(ub, ub + (0.16 if ub < 0.5 else -0.16))
	fbox(p, d, lu0, lu0 + 0.16, 0.86, 0.9, 0.0, w1, pk, pk, MeshBuf.WHITE, 31)


# ------------------------------------------------------------------ 옥상
func _rooftop(p: Vector3i, c: Dictionary, rec: Dictionary, mat: String, seed_v: int) -> void:
	var base := cellv(p) + Vector3(0, fh, 0)
	var hs := ViewCfg.h2(seed_v, 500)
	var col2 := Vector2i(p.x, p.y)
	if chimney_cols.has(col2):
		var cx := base.x + 0.125 + 0.5 * float(hs % 2)
		var cz := base.z + 0.125 + 0.5 * float((hs / 2) % 2)
		var chh := fh * (0.8 + 0.2 * float(hs % 3))
		wbox(Vector3(cx, base.y, cz), Vector3(cx + 0.25, base.y + chh, cz + 0.25), "wall_brick_1" if atlas.has("wall_brick_1") else "white", "white", MeshBuf.WHITE, 31, 0.0, 0.0, Color("#4a4160"))
		wbox(Vector3(cx - 0.03, base.y + chh, cz - 0.03), Vector3(cx + 0.28, base.y + chh + 0.06, cz + 0.28), "white", "white", Color("#8f8aa6"))
		emitter(Vector3(cx + 0.125, base.y + chh + 0.1, cz + 0.125), str(chimney_cols[col2]))
		return
	var weights: Dictionary = rec.get("roof", {})
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var none_w := total * 0.55 + 0.5
	var pick := float(hs % 10000) / 10000.0 * (total + none_w)
	var what := ""
	for k in weights:
		pick -= float(weights[k])
		if pick < 0.0:
			what = str(k)
			break
	# 높은 꼭대기일수록 안테나
	if what == "" and p.z >= 4 and (hs / 7) % 100 < 20:
		what = "antenna"
	match what:
		"antenna":
			_antennas(base, hs)
		"tank":
			_roof_tank(base, hs)
		"shack":
			_roof_shack(p, base, hs)
		"laundry":
			_roof_laundry(base, hs)
		"plants":
			_roof_plants(base, hs)
		"junk":
			_roof_junk(base, hs)
		"chimney":
			var cx2 := base.x + 0.375
			var cz2 := base.z + 0.375
			wbox(Vector3(cx2, base.y, cz2), Vector3(cx2 + 0.1875, base.y + fh * 0.7, cz2 + 0.1875), "white", "white", Color("#9aa3b8"), 31, 0.0, 0.0, Color("#4a4160"))
	if what != "antenna" and (hs / 13) % 100 < 12:
		_antennas(base, hs / 3, 1)


func _antennas(base: Vector3, hs: int, max_n: int = 3) -> void:
	var n := 1 + hs % max_n
	for i in n:
		var k := (hs / (3 + i)) % 3
		var r := tile("antenna_%d" % k)
		var hh := 32.0 - float(k * 3)
		var rr := sub(r, 0, 32.0 - hh, 16, hh)
		var wy := hh / 16.0 * fh
		var ox := 0.0625 * float((hs / (5 + i * 3)) % 9)
		var oz := 0.125 + 0.0625 * float((hs / (7 + i * 5)) % 13)
		if (hs / (2 + i)) % 2 == 0:
			var a := base + Vector3(ox - 0.25, 0, oz)
			mb.quad2(a + Vector3(0, wy, 0), a + Vector3(1, wy, 0), a + Vector3(1, 0, 0), a, Vector3(0, 0, 1), rr)
		else:
			var a2 := base + Vector3(oz, 0, ox - 0.25 + 1.0)
			mb.quad2(a2 + Vector3(0, wy, 0), a2 + Vector3(0, wy, -1), a2 + Vector3(0, 0, -1), a2, Vector3(1, 0, 0), rr)


func _roof_tank(base: Vector3, hs: int) -> void:
	var x := base.x + 0.125 + 0.0625 * float(hs % 5)
	var z := base.z + 0.125 + 0.0625 * float((hs / 5) % 5)
	var steel := (hs / 3) % 3 == 0
	var s := 0.5
	var legs := 0.12
	for lx in [0.0, s - 0.0625]:
		for lz in [0.0, s - 0.0625]:
			wbox(Vector3(x + lx, base.y, z + lz), Vector3(x + lx + 0.0625, base.y + legs, z + lz + 0.0625), "white", "white", Color("#5a5674"), 15)
	wbox(Vector3(x, base.y + legs, z), Vector3(x + s, base.y + legs + fh * 0.62, z + s), "steel_side" if steel else "tank_side", "white" if steel else "tank_top", MeshBuf.WHITE, 31, 0.0, 0.0, Color("#d6d8de") if steel else MeshBuf.WHITE)
	if hs % 4 == 0:
		emitter(Vector3(x + s * 0.5, base.y + 0.02, z + s + 0.06), "drip")


func _roof_shack(p: Vector3i, base: Vector3, hs: int) -> void:
	var m: String = cfg.material_key(["sheet", "scrap", "wood", "sheet"][hs % 4])
	var x := base.x + 0.125 + 0.0625 * float(hs % 3)
	var z := base.z + 0.125 + 0.0625 * float((hs / 3) % 3)
	var sx := 0.625
	var sz := 0.625
	var hh := fh * 0.75
	var wr := tile("wall_%s_%d" % [m, hs % 4])
	var wr2 := Rect2(wr.position + Vector2(0, 4), Vector2(10, 12))
	mb.box(Vector3(x, base.y, z), Vector3(x + sx, base.y + hh, z + sz), wr2, tile("roof_%s_%d" % [m, hs % 3]), fh, MeshBuf.WHITE, 15)
	# 기운 지붕(살짝 내밀기)
	var rr := tile("roof_%s_%d" % [cfg.material_key("sheet"), hs % 3])
	var o := 0.06
	var y0 := base.y + hh
	var y1 := base.y + hh + 0.14
	var n := Vector3(0.2, 1, 0).normalized()
	mb.quad(Vector3(x - o, y1, z - o), Vector3(x + sx + o, y0, z - o), Vector3(x + sx + o, y0, z + sz + o), Vector3(x - o, y1, z + sz + o), n, sub(rr, 0, 0, 12, 12))
	mb.quad(Vector3(x - o, y1, z + sz + o), Vector3(x + sx + o, y0, z + sz + o), Vector3(x + sx + o, y0 - 0.02, z + sz + o), Vector3(x - o, y0 - 0.02, z + sz + o), Vector3(0, 0, 1), sub(tile("white"), 0, 0, 2, 2), Color("#7c8fa2"))
	mb.quad(Vector3(x - o, y1, z - o), Vector3(x - o, y1, z + sz + o), Vector3(x - o, y0 - 0.02, z + sz + o), Vector3(x - o, y0 - 0.02, z - o), Vector3(-1, 0, 0), sub(tile("white"), 0, 0, 2, 2), Color("#7c8fa2"))
	# 창 하나(두 면)
	var wn := tile("win_glow")
	var rnd := float(hs % 997) / 997.0
	mb.quad(Vector3(x + sx + EPS, base.y + hh * 0.8, z + sz * 0.75), Vector3(x + sx + EPS, base.y + hh * 0.8, z + sz * 0.3), Vector3(x + sx + EPS, base.y + hh * 0.35, z + sz * 0.3), Vector3(x + sx + EPS, base.y + hh * 0.35, z + sz * 0.75), Vector3(1, 0, 0), sub(wn, 4, 4, 6, 6), MeshBuf.WHITE, rnd, MeshBuf.K_WINDOW)
	mb.quad(Vector3(x + sx * 0.25, base.y + hh * 0.8, z + sz + EPS), Vector3(x + sx * 0.7, base.y + hh * 0.8, z + sz + EPS), Vector3(x + sx * 0.7, base.y + hh * 0.35, z + sz + EPS), Vector3(x + sx * 0.25, base.y + hh * 0.35, z + sz + EPS), Vector3(0, 0, 1), sub(wn, 4, 4, 6, 6), MeshBuf.WHITE, rnd, MeshBuf.K_WINDOW)
	light(Vector3(x + sx * 0.5, base.y + hh * 0.5, z + sz + 0.3), Color(1, 1, 1), 0.9, 0.5)


func _roof_laundry(base: Vector3, hs: int) -> void:
	var along_x := hs % 2 == 0
	var y := base.y + fh * 0.62
	var pc := Color("#d9b45a")
	var a := base + Vector3(0.125, 0, 0.5) if along_x else base + Vector3(0.5, 0, 0.125)
	var b := base + Vector3(0.875, 0, 0.5) if along_x else base + Vector3(0.5, 0, 0.875)
	for q in [a, b]:
		wbox(q - Vector3(0.03, 0, 0.03), Vector3(q.x + 0.03, y + 0.04, q.z + 0.03), "white", "white", pc, 15)
	var n := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var t := 0.14
	var i := 0
	while t < 0.8:
		var cw := 0.125 + 0.0625 * float((hs / (i + 3)) % 2)
		var chh := fh * (0.3 + 0.08 * float((hs / (i + 7)) % 3))
		var cc := Color(LAUNDRY[(hs / (i * 5 + 1)) % LAUNDRY.size()])
		var p0 := a.lerp(b, (t - 0.125) / 0.75)
		var p1 := a.lerp(b, (t + cw - 0.125) / 0.75)
		p0.y = y
		p1.y = y
		mb.cloth(p0, p1, p1 - Vector3(0, chh, 0), p0 - Vector3(0, chh, 0), n, sub(tile("white"), 0, 0, 4, 4), cc, float((hs + i * 31) % 100) / 100.0)
		t += cw + 0.04
		i += 1
	# 줄
	var la := Vector3(a.x, y, a.z)
	var lb := Vector3(b.x, y, b.z)
	mb.quad2(la + Vector3(0, 0.03, 0), lb + Vector3(0, 0.03, 0), lb, la, n, sub(tile("white"), 0, 0, 2, 1), Color("#5a5674"))


func _roof_plants(base: Vector3, hs: int) -> void:
	var n := 2 + hs % 3
	for i in n:
		var px := base.x + 0.0625 * float((hs / (3 + i)) % 11)
		var pz := base.z + 0.125 + 0.0625 * float((hs / (5 + i * 2)) % 12)
		var pr := tile("plant_%d" % ((hs / (i + 1)) % 3))
		var hh := fh * 0.62
		mb.quad2(Vector3(px, base.y + hh, pz), Vector3(px + 0.5, base.y + hh, pz), Vector3(px + 0.5, base.y, pz), Vector3(px, base.y, pz), Vector3(0, 0, 1), sub(pr, 0, 0, 16, 16))
	if hs % 3 == 0:
		var bx := base.x + 0.125
		var bz := base.z + 0.0625
		wbox(Vector3(bx, base.y, bz), Vector3(bx + 0.75, base.y + 0.07, bz + 0.3125), "crate", "crops_%d" % (hs % 3), MeshBuf.WHITE, 31)


func _roof_junk(base: Vector3, hs: int) -> void:
	var n := 1 + hs % 3
	for i in n:
		var x := base.x + 0.0625 * float((hs / (2 + i)) % 9)
		var z := base.z + 0.0625 * float((hs / (4 + i)) % 9)
		var s := 0.25 + 0.0625 * float((hs / (6 + i)) % 3)
		var t := "crate" if (hs / (i + 1)) % 2 == 0 else "junk"
		wbox(Vector3(x, base.y, z), Vector3(x + s, base.y + s * 0.8, z + s), t, t, MeshBuf.WHITE, 31)
	if hs % 2 == 0:
		# 파란 방수포
		var x2 := base.x + 0.375
		var z2 := base.z + 0.5
		wbox(Vector3(x2, base.y, z2), Vector3(x2 + 0.5, base.y + 0.16, z2 + 0.4), "white", "white", Color("#5f86c4"), 31, 0.0, 0.0, Color("#7fa3d8"))


# ------------------------------------------------------------------ 상자가 아닌 것들
func _kerb(p: Vector3i, c: Color, h: float = 0.08) -> void:
	var b := cellv(p)
	var t := 0.0625
	wbox(Vector3(b.x, b.y, b.z), Vector3(b.x + 1, b.y + h, b.z + t), "white", "white", c, 31)
	wbox(Vector3(b.x, b.y, b.z + 1 - t), Vector3(b.x + 1, b.y + h, b.z + 1), "white", "white", c, 31)
	wbox(Vector3(b.x, b.y, b.z + t), Vector3(b.x + t, b.y + h, b.z + 1 - t), "white", "white", c, 31)
	wbox(Vector3(b.x + 1 - t, b.y, b.z + t), Vector3(b.x + 1, b.y + h, b.z + 1 - t), "white", "white", c, 31)


func _topquad(b: Vector3, x0: float, z0: float, x1: float, z1: float, y: float, r: Rect2, c: Color = MeshBuf.WHITE, kind: float = 0.0) -> void:
	mb.quad(Vector3(b.x + x0, b.y + y, b.z + z0), Vector3(b.x + x1, b.y + y, b.z + z0), Vector3(b.x + x1, b.y + y, b.z + z1), Vector3(b.x + x0, b.y + y, b.z + z1), UP, Rect2(r.position, Vector2((x1 - x0) * 16.0, (z1 - z0) * 16.0)), c, 0.0, kind)


func _plantq(b: Vector3, x: float, z: float, k: int, along_x: bool, hh: float = 0.5) -> void:
	var pr := tile("plant_%d" % (k % 3))
	var rr := sub(pr, 2, 2, 12, 8)
	if along_x:
		mb.quad2(Vector3(b.x + x, b.y + hh, b.z + z), Vector3(b.x + x + 0.5, b.y + hh, b.z + z), Vector3(b.x + x + 0.5, b.y, b.z + z), Vector3(b.x + x, b.y, b.z + z), Vector3(0, 0, 1), rr)
	else:
		mb.quad2(Vector3(b.x + x, b.y + hh, b.z + z + 0.5), Vector3(b.x + x, b.y + hh, b.z + z), Vector3(b.x + x, b.y, b.z + z), Vector3(b.x + x, b.y, b.z + z + 0.5), Vector3(1, 0, 0), rr)


func _build_open(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int) -> void:
	var b := cellv(p)
	var hs := ViewCfg.h2(seed_v, 700)
	var plot: String = str(rec.get("plot", "crops"))
	match plot:
		"crops":
			_kerb(p, Color("#b98452"), 0.1)
			_topquad(b, 0.0625, 0.0625, 0.9375, 0.9375, 0.07, sub(tile("crops_%d" % (hs % 3)), 1, 1, 14, 14))
			for i in 2 + hs % 2:
				_plantq(b, 0.0625 * float((hs / (i + 2)) % 8), 0.2 + 0.3 * float(i), hs + i, true, 0.3 + 0.06 * float((hs / (i + 3)) % 3))
			if hs % 5 == 0:
				# 허수아비 대신 물뿌리개 통
				wbox(b + Vector3(0.7, 0.07, 0.1), b + Vector3(0.85, 0.3, 0.25), "tank_side", "tank_top", MeshBuf.WHITE, 31)
		"tanks":
			_kerb(p, Color("#9aa3b8"), 0.06)
			wbox(b + Vector3(0.0625, 0, 0.0625), b + Vector3(0.9375, 0.3, 0.44), "steel_side", "water_fish", MeshBuf.WHITE, 31)
			wbox(b + Vector3(0.0625, 0, 0.56), b + Vector3(0.9375, 0.3, 0.9375), "steel_side", "water_fish", MeshBuf.WHITE, 31)
			light(b + Vector3(0.5, 0.5, 0.5), cfg.neon("cyan"), 1.0)
		"junk":
			_topquad(b, 0, 0, 1, 1, 0.012, tile("g_dirt_3"))
			for i in 3 + hs % 2:
				var x := 0.0625 * float((hs / (2 + i)) % 10)
				var z := 0.0625 * float((hs / (5 + i)) % 10)
				var s := 0.25 + 0.0625 * float((hs / (7 + i)) % 3)
				wbox(b + Vector3(x, 0, z), b + Vector3(x + s, s * (0.6 + 0.3 * float(i % 2)), z + s), "junk" if i % 2 == 0 else "crate", "junk" if i % 2 == 0 else "crate", MeshBuf.WHITE, 31)
			wbox(b + Vector3(0.1, 0, 0.72), b + Vector3(0.6, 0.28, 0.92), "white", "plank", Color("#8f6f5a"), 31, 0.0, 0.0, MeshBuf.WHITE)
			_small_sign(p, c, rec, seed_v, b + Vector3(0.75, 0, 0.8))
		"well":
			_topquad(b, 0, 0, 1, 1, 0.012, tile("g_slab"))
			wbox(b + Vector3(0.28, 0, 0.28), b + Vector3(0.72, 0.26, 0.72), "stone", "water", MeshBuf.WHITE, 31)
			for q in [Vector3(0.24, 0, 0.24), Vector3(0.7, 0, 0.7)]:
				wbox(b + q, b + q + Vector3(0.06, 0.75, 0.06), "white", "white", Color("#8f6f5a"), 15)
			var rr := tile("roof_%s_0" % cfg.material_key("wood"))
			var n := Vector3(0, 1, 0.25).normalized()
			mb.quad(b + Vector3(0.15, 0.86, 0.15), b + Vector3(0.85, 0.86, 0.15), b + Vector3(0.85, 0.72, 0.85), b + Vector3(0.15, 0.72, 0.85), n, sub(rr, 0, 0, 12, 12))
			mb.quad(b + Vector3(0.15, 0.72, 0.85), b + Vector3(0.85, 0.72, 0.85), b + Vector3(0.85, 0.86, 0.15), b + Vector3(0.15, 0.86, 0.15), -UP, sub(rr, 0, 0, 12, 12))
			wbox(b + Vector3(0.78, 0, 0.3), b + Vector3(0.92, 0.16, 0.44), "tank_side", "water", MeshBuf.WHITE, 31)
			emitter(b + Vector3(0.5, 0.3, 0.5), "drip")
		_:
			_kerb(p, Color("#9aa3b8"), 0.06)


func _small_sign(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int, at: Vector3) -> void:
	# 같은 좌판이 줄지어 있으면 줄의 첫 칸(과 드문드문)에만 팻말 → 벽지처럼 도배되지 않게
	var ty: String = str(c.get("type", ""))
	for nb in [p + Vector3i(-1, 0, 0), p + Vector3i(0, -1, 0)]:
		if str(state.cells.get(nb, {}).get("type", "")) == ty and ViewCfg.h2(p.x * 11 + p.y * 7, p.z + 3) % 4 != 0:
			return
	var text := ViewCfg.sign_text(str(c.get("kind", "")), str(c.get("type", "")))
	if text == "" or str(rec.get("sign_style", "none")) == "none":
		return
	var tr := Rect2(atlas.sign_rect(text, true))
	if tr.size.x <= 0.0:
		return
	var bh := (tr.size.y + 2.0) / 16.0 * fh
	var bw := (tr.size.x + 2.0) * TX
	var col := cfg.neon(rec.get("sign_color", "red"))
	var y0 := 0.3
	wbox(at + Vector3(bw * 0.5 - 0.03, 0, -0.03), at + Vector3(bw * 0.5 + 0.03, y0, 0.03), "white", "white", Color("#8f6f5a"), 15)
	wbox(at + Vector3(0, y0, -0.03), at + Vector3(bw, y0 + bh, 0.03), "white", "white", Color("#f4ecd8"), 31)
	var a := at + Vector3(TX, y0 + bh - TX * fh, 0.034)
	mb.quad(a, a + Vector3(tr.size.x * TX, 0, 0), a + Vector3(tr.size.x * TX, -tr.size.y / 16.0 * fh, 0), a + Vector3(0, -tr.size.y / 16.0 * fh, 0), Vector3(0, 0, 1), tr, col.darkened(0.25))
	var a2 := at + Vector3(bw - TX, y0 + bh - TX * fh, -0.034)
	mb.quad(a2, a2 - Vector3(tr.size.x * TX, 0, 0), a2 + Vector3(-tr.size.x * TX, -tr.size.y / 16.0 * fh, 0), a2 + Vector3(0, -tr.size.y / 16.0 * fh, 0), Vector3(0, 0, -1), tr, col.darkened(0.25))


func _build_shed(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int) -> void:
	var b := cellv(p)
	var hs := ViewCfg.h2(seed_v, 800)
	var plot: String = str(rec.get("plot", "stall"))
	var ac := ViewCfg.col(rec.get("awning", "#d85f5f"), Color("#d85f5f"))
	var hh := fh * 0.78
	if plot == "generator":
		_topquad(b, 0, 0, 1, 1, 0.012, tile("g_slab"))
		wbox(b + Vector3(0.2, 0.02, 0.25), b + Vector3(0.8, 0.42, 0.7), "machine", "machine", MeshBuf.WHITE, 31, 0.0, MeshBuf.K_SHAKE)
		wbox(b + Vector3(0.68, 0.42, 0.3), b + Vector3(0.76, 0.8, 0.38), "white", "white", Color("#5a5674"), 15, 0.0, MeshBuf.K_SHAKE)
		wbox(b + Vector3(0.08, 0, 0.72), b + Vector3(0.3, 0.3, 0.94), "white", "white", Color("#c2463c"), 31, 0.0, 0.0, Color("#d8695f"))
		emitter(b + Vector3(0.72, 0.85, 0.34), "smoke")
		_small_sign(p, c, rec, seed_v, b + Vector3(0.05, 0, 0.1))
		light(b + Vector3(0.5, 0.5, 0.8), cfg.neon("yellow"), 1.4)
		# 양철 지붕
		for q in [Vector3(0.03, 0, 0.03), Vector3(0.91, 0, 0.03), Vector3(0.03, 0, 0.91), Vector3(0.91, 0, 0.91)]:
			wbox(b + q, b + q + Vector3(0.06, hh, 0.06), "white", "white", Color("#6a6486"), 15)
		var rr := tile("roof_%s_1" % cfg.material_key("sheet"))
		wbox(b + Vector3(-0.03, hh, -0.03), b + Vector3(1.03, hh + 0.05, 1.03), "white", "roof_%s_1" % cfg.material_key("sheet"), Color("#7c8fa2"), 63, 0.0, 0.0, MeshBuf.WHITE)
		return
	# 좌판: 기둥 4 + 줄무늬 천막 + 좌판대
	_topquad(b, 0, 0, 1, 1, 0.012, tile("g_dirt_1"))
	for q in [Vector3(0.05, 0, 0.05), Vector3(0.89, 0, 0.05), Vector3(0.05, 0, 0.89), Vector3(0.89, 0, 0.89)]:
		wbox(b + q, b + q + Vector3(0.06, hh, 0.06), "white", "white", Color("#d9b45a"), 15)
	var ar := tile("awning")
	var n := Vector3(0, 1, 0.2).normalized()
	var y1 := hh + 0.12
	var y0 := hh - 0.04
	mb.quad(b + Vector3(-0.06, y1, -0.06), b + Vector3(1.06, y1, -0.06), b + Vector3(1.06, y0, 1.06), b + Vector3(-0.06, y0, 1.06), n, ar, ac)
	mb.quad(b + Vector3(-0.06, y0, 1.06), b + Vector3(1.06, y0, 1.06), b + Vector3(1.06, y1, -0.06), b + Vector3(-0.06, y1, -0.06), -UP, ar, ac)
	mb.quad(b + Vector3(-0.06, y0, 1.06), b + Vector3(1.06, y0, 1.06), b + Vector3(1.06, y0 - 0.08, 1.06), b + Vector3(-0.06, y0 - 0.08, 1.06), Vector3(0, 0, 1), sub(ar, 0, 13, 16, 2), ac)
	mb.quad(b + Vector3(1.06, y1, -0.06), b + Vector3(1.06, y1, -0.06), b + Vector3(1.06, y0 - 0.08, 1.06), b + Vector3(1.06, y0, 1.06), Vector3(1, 0, 0), sub(ar, 0, 13, 16, 2), ac)
	# 좌판대와 물건
	wbox(b + Vector3(0.15, 0, 0.3), b + Vector3(0.85, 0.3, 0.62), "crate", "mj_table" if str(c.get("type", "")) == "stall" else "noodles", MeshBuf.WHITE, 31)
	wbox(b + Vector3(0.2, 0, 0.72), b + Vector3(0.36, 0.16, 0.88), "white", "white", Color("#c2463c"), 31)
	wbox(b + Vector3(0.62, 0, 0.72), b + Vector3(0.78, 0.16, 0.88), "white", "white", Color("#5f86c4"), 31)
	var lr := tile("lantern")
	mb.quad2(b + Vector3(0.1, y0, 1.0), b + Vector3(0.6, y0, 1.0), b + Vector3(0.6, y0 - 0.4, 1.0), b + Vector3(0.1, y0 - 0.4, 1.0), Vector3(0, 0, 1), sub(lr, 0, 0, 16, 8))
	light(b + Vector3(0.5, 0.4, 0.9), Color("#ff8a4a"), 1.6)
	light(b + Vector3(0.5, 0.4, 0.5), Color(1, 1, 1), 1.2, 0.9)
	if str(rec.get("fx", "")) == "steam":
		emitter(b + Vector3(0.5, 0.4, 0.45), "steam")
	_small_sign(p, c, rec, seed_v, b + Vector3(0.0, hh * 0.2, 1.08))


func _build_tank(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int) -> void:
	var b := cellv(p)
	for q in [Vector3(0.1, 0, 0.1), Vector3(0.82, 0, 0.1), Vector3(0.1, 0, 0.82), Vector3(0.82, 0, 0.82)]:
		wbox(b + q, b + q + Vector3(0.08, 0.2, 0.08), "white", "white", Color("#5a5674"), 15)
	wbox(b + Vector3(0.06, 0.2, 0.06), b + Vector3(0.94, 0.2 + fh * 0.85, 0.94), "tank_side", "tank_top", MeshBuf.WHITE, 63)
	wbox(b + Vector3(0.9, 0, 0.44), b + Vector3(0.98, 0.5, 0.52), "white", "white", Color("#8fb5d0"), 15)
	emitter(b + Vector3(0.5, 0.02, 1.02), "drip")


func _build_loft(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int) -> void:
	var b := cellv(p)
	var hs := ViewCfg.h2(seed_v, 900)
	for q in [Vector3(0.12, 0, 0.2), Vector3(0.82, 0, 0.2), Vector3(0.12, 0, 0.74), Vector3(0.82, 0, 0.74)]:
		wbox(b + q, b + q + Vector3(0.06, 0.16, 0.06), "white", "white", Color("#8f6f5a"), 15)
	var ct := tile("cage_1")
	wbox(b + Vector3(0.1, 0.16, 0.18), b + Vector3(0.9, 0.16 + fh * 0.55, 0.82), "white", "white", Color("#e6dcc4"), 63)
	mb.box(b + Vector3(0.09, 0.16, 0.17), b + Vector3(0.91, 0.16 + fh * 0.55, 0.83), sub(ct, 0, 0, 16, 9), ct, fh, MeshBuf.WHITE, 15)
	var rr := "roof_%s_%d" % [cfg.material_key("wood"), hs % 3]
	wbox(b + Vector3(0.04, 0.16 + fh * 0.55, 0.12), b + Vector3(0.96, 0.2 + fh * 0.55, 0.88), "white", rr, Color("#a26a4c"), 63, 0.0, 0.0, MeshBuf.WHITE)
	emitter(b + Vector3(0.5, 0.2 + fh * 0.6, 0.5), "pigeons")


func _build_shrine(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int) -> void:
	var b := cellv(p)
	_topquad(b, 0, 0, 1, 1, 0.012, tile("g_slab"))
	wbox(b + Vector3(0.14, 0, 0.14), b + Vector3(0.86, 0.1, 0.86), "stone", "stone", MeshBuf.WHITE, 31)
	wbox(b + Vector3(0.22, 0.1, 0.22), b + Vector3(0.78, 0.1 + fh * 0.6, 0.78), "white", "white", Color("#c2463c"), 31)
	# 열린 정면(어두운 안쪽 + 금빛 제단)
	for d in 4:
		var q := Vector3i(p.x, p.y, p.z)
		fquad(q, d, 0.34, 0.66, 0.16, 0.6, -0.215, sub(tile("altar"), 0, 0, 5, 7), MeshBuf.WHITE, 0.0, 0.0, false)
	# 겹지붕
	var y := 0.1 + fh * 0.6
	wbox(b + Vector3(0.08, y, 0.08), b + Vector3(0.92, y + 0.07, 0.92), "white", "white", Color("#3f8f6a"), 63, 0.0, 0.0, Color("#4fa57c"))
	wbox(b + Vector3(0.22, y + 0.07, 0.22), b + Vector3(0.78, y + 0.14, 0.78), "white", "white", Color("#3f8f6a"), 31, 0.0, 0.0, Color("#4fa57c"))
	wbox(b + Vector3(0.4, y + 0.14, 0.4), b + Vector3(0.6, y + 0.24, 0.6), "white", "white", Color("#f2d27a"), 31)
	var lr := tile("lantern")
	mb.quad2(b + Vector3(0.0, y, 0.95), b + Vector3(0.5, y, 0.95), b + Vector3(0.5, y - 0.4, 0.95), b + Vector3(0.0, y - 0.4, 0.95), Vector3(0, 0, 1), sub(lr, 0, 0, 16, 8))
	mb.quad2(b + Vector3(0.95, y, 0.5), b + Vector3(0.95, y, 0.0), b + Vector3(0.95, y - 0.4, 0.0), b + Vector3(0.95, y - 0.4, 0.5), Vector3(1, 0, 0), sub(lr, 0, 0, 16, 8))
	light(b + Vector3(0.5, 0.4, 0.5), Color("#ff6a4a"), 1.8)
	emitter(b + Vector3(0.5, 0.3, 0.88), "incense")
	_small_sign(p, c, rec, seed_v, b + Vector3(0.02, 0.0, 0.04))


func _build_site(p: Vector3i, c: Dictionary, seed_v: int) -> void:
	var b := cellv(p)
	var prog := clampf(float(c.get("progress", 0.0)), 0.0, 1.0)
	var bec: Dictionary = c.get("becomes", {}) if c.get("becomes", {}) is Dictionary else {}
	var mat: String = cfg.material_key(str(bec.get("material", c.get("material", ""))))
	# 올라가는 벽
	var wh := prog * 0.9
	if wh > 0.05:
		var wr := tile("wall_%s_0" % mat)
		for d in 4:
			if solid.has(p + DIR[d]):
				continue
			fquad(p, d, 0, 1, 0, wh, 0.0, wr)
		var y := b.y + wh * fh
		mb.quad(Vector3(b.x, y, b.z), Vector3(b.x + 1, y, b.z), Vector3(b.x + 1, y, b.z + 1), Vector3(b.x, y, b.z + 1), UP, tile("cutcap"), Color(2.2, 2.0, 2.0))
	# 대나무 비계 + 초록 그물
	var sc := tile("scaffold")
	var nt := tile("net")
	var o := 0.07
	var sh := 1.0 + 0.2
	for d in 4:
		if solid.has(p + DIR[d]):
			continue
		mb.quad2(fp(p, d, -o, sh, o), fp(p, d, 1 + o, sh, o), fp(p, d, 1 + o, 0, o), fp(p, d, -o, 0, o), NRM[d], Rect2(sc.position, Vector2(16, 16)))
		var nh := clampf(0.25 + prog * 0.75, 0.0, 1.0)
		var hsd := ViewCfg.h2(seed_v, d)
		if hsd % 4 != 0:
			var u0 := 0.0 if hsd % 3 != 0 else 0.5
			var u1 := 1.0 if hsd % 5 != 0 else 0.5
			if u1 > u0:
				mb.quad2(fp(p, d, u0, nh, o + 0.01), fp(p, d, u1, nh, o + 0.01), fp(p, d, u1, 0.06, o + 0.01), fp(p, d, u0, 0.06, o + 0.01), NRM[d], Rect2(nt.position, Vector2((u1 - u0) * 16.0, nh * 16.0)))
	emitter(b + Vector3(0.5, 0.5 * fh, 0.5), "site")


# ================================================================== 층 컷(심즈식 단면)
# set_floor_cut(n): n층의 천장을 걷어 방 안을 내려다본다. 낮은 벽 + 바닥재 + 가구.
const CUT_WALL := 0.3125      # 낮춘 벽 높이(층 단위, 5텍셀)
const CUT_T := 0.125          # 외벽 두께
const CUT_TP := 0.0625        # 칸막이 반쪽 두께
const KI := MeshBuf.K_INTERIOR

func build_cut(z: int) -> Dictionary:
	mb = MeshBuf.new()
	lights = []
	emitters = []
	if z >= 0 and z < by_floor.size():
		for p in by_floor[z]:
			var c: Dictionary = state.cells[p]
			if is_box(c):
				_cut_cell(p, c)
			else:
				_build_cell(p, c)
	return {"mesh": mb.commit(), "lights": lights, "emitters": emitters}


func _same_unit(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("owner", 0)) != 0 and int(a.get("owner", 0)) == int(b.get("owner", -1)) and str(a.get("kind", "")) == str(b.get("kind", ""))


## 칸 가장자리 d를 따라 [s0,s1] 구간에 벽 상자 하나. inward 두께 t.
func _edge_box(p: Vector3i, d: int, s0: float, s1: float, t: float, h: float, side: Rect2, top: Rect2, c: Color = MeshBuf.WHITE) -> void:
	var y0 := float(p.z) * fh
	var y1 := y0 + h * fh
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	match d:
		0:
			a = Vector3(p.x + 1 - t, y0, p.y + s0)
			b = Vector3(p.x + 1, y1, p.y + s1)
		1:
			a = Vector3(p.x + s0, y0, p.y + 1 - t)
			b = Vector3(p.x + s1, y1, p.y + 1)
		2:
			a = Vector3(p.x, y0, p.y + s0)
			b = Vector3(p.x + t, y1, p.y + s1)
		_:
			a = Vector3(p.x + s0, y0, p.y)
			b = Vector3(p.x + s1, y1, p.y + t)
	var sr := Rect2(side.position + Vector2(0, 16.0 - h * 16.0), Vector2(side.size.x, h * 16.0))
	mb.box(a, b, sr, top, fh, c, 31, 0.0, 0.0, MeshBuf.WHITE)


func _cut_cell(p: Vector3i, c: Dictionary) -> void:
	var kind: String = str(c.get("kind", ""))
	var type: String = str(c.get("type", ""))
	var rec: Dictionary = cfg.recipe(kind, type)
	var mat: String = cfg.material_key(str(c.get("material", "")))
	var seed_v: int = int(c.get("seed", 0)) + p.x * 7 + p.y * 13 + p.z * 29
	var b := cellv(p)
	# 바닥
	var fname := "f_" + str(rec.get("floor", "concrete"))
	if not atlas.has(fname):
		fname = "f_concrete"
	var fr := tile(fname)
	var y := b.y + 0.004
	var owner: int = int(c.get("owner", 0))
	var lived: bool = kind != "housing" or occupied.has(owner)
	mb.quad(Vector3(b.x, y, b.z), Vector3(b.x + 1, y, b.z), Vector3(b.x + 1, y, b.z + 1), Vector3(b.x, y, b.z + 1), UP, fr, MeshBuf.WHITE if lived else Color(0.8, 0.8, 0.86), 0.0, KI)
	# 벽
	var wr := tile("wall_%s_%d" % [mat, _age_variant(c, seed_v) % 3])
	var cap := tile("cutcap")
	var plaster := tile("white")
	for d in 4:
		var nb: Vector3i = p + DIR[d]
		if solid.has(nb):
			var nc: Dictionary = state.cells[nb]
			if _same_unit(c, nc):
				continue
			# 칸막이: 문틈은 두 칸이 같은 자리에 뚫도록 공유 해시로
			var lo: Vector3i = p if (d == 0 or d == 1) else nb
			var g := 0.125 + 0.0625 * float(ViewCfg.h3(lo.x * 13 + lo.y, lo.z * 5 + (d % 2), 99) % 8)
			var has_door := ViewCfg.h3(lo.x * 7 + lo.y * 3, lo.z + (d % 2) * 11, 55) % 100 < 55
			if has_door:
				_edge_box(p, d, 0.0, g, CUT_TP, CUT_WALL, plaster, cap, Color("#e9dfcf"))
				_edge_box(p, d, g + 0.3125, 1.0, CUT_TP, CUT_WALL, plaster, cap, Color("#e9dfcf"))
			else:
				_edge_box(p, d, 0.0, 1.0, CUT_TP, CUT_WALL, plaster, cap, Color("#e9dfcf"))
		else:
			# 외벽(다리·계단 문이 있으면 틈)
			var door := bridges.has(fkey(p, d)) or (stairs.has(Vector3i(p.x, p.y, d)) and p.z >= int(stairs[Vector3i(p.x, p.y, d)][0]) and p.z < int(stairs[Vector3i(p.x, p.y, d)][1]))
			var gdoor := p.z == 0 and kind != "housing" and not state.cells.has(nb) and ViewCfg.h2(seed_v, 3 + d) % 2 == 0
			if door or gdoor:
				_edge_box(p, d, 0.0, 0.3125, CUT_T, CUT_WALL, wr, cap)
				_edge_box(p, d, 0.6875, 1.0, CUT_T, CUT_WALL, wr, cap)
			else:
				_edge_box(p, d, 0.0, 1.0, CUT_T, CUT_WALL, wr, cap)
			# 외벽 바깥면은 아래층 벽과 이어지게 그대로 둔다(상자 바깥면이 그 역할)
	if lived:
		_furnish(p, c, rec, seed_v)
		light(b + Vector3(0.5, 0.4, 0.5), Color(1, 1, 1), 1.1, 0.9)


## 칸 안 좌표(0..1)를 k×90° 돌린 상자. h0/h1은 월드 단위 높이.
func _ib(p: Vector3i, k: int, x0: float, z0: float, x1: float, z1: float, h0: float, h1: float, side: String, top: String, c: Color = MeshBuf.WHITE, tc: Color = Color(-1, 0, 0), kind: float = KI) -> void:
	var a := Vector2(x0, z0)
	var b := Vector2(x1, z1)
	for i in k % 4:
		a = Vector2(1.0 - a.y, a.x)
		b = Vector2(1.0 - b.y, b.x)
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var o := cellv(p)
	mb.box(Vector3(o.x + mn.x, o.y + h0, o.z + mn.y), Vector3(o.x + mx.x, o.y + h1, o.z + mx.y), tile(side), tile(top), fh, c, 31, 0.0, kind, tc)


func _ipos(p: Vector3i, k: int, x: float, z: float, h: float) -> Vector3:
	var a := Vector2(x, z)
	for i in k % 4:
		a = Vector2(1.0 - a.y, a.x)
	var o := cellv(p)
	return Vector3(o.x + a.x, o.y + h, o.z + a.y)


const WOODC := Color("#b98562")
const WOODT := Color("#d9a878")
const STEEL := Color("#b9bcc8")

func _stool(p: Vector3i, k: int, x: float, z: float, c: Color = Color("#c2604f")) -> void:
	_ib(p, k, x, z, x + 0.1, z + 0.1, 0.0, 0.1, "white", "white", c.darkened(0.2), c)


func _furnish(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int) -> void:
	var hs := ViewCfg.h2(seed_v, 600)
	var k := hs % 4
	var what: String = str(rec.get("interior", ""))
	match what:
		"bed":
			_ib(p, k, 0.16, 0.16, 0.5, 0.8, 0.0, 0.14, "white", "bed" if hs % 2 == 0 else "bed_red", Color("#8a6a5a"), MeshBuf.WHITE)
			_ib(p, k, 0.6, 0.16, 0.84, 0.36, 0.0, 0.2, "white", "white", WOODC, WOODT)
			_ib(p, k, 0.62, 0.62, 0.84, 0.84, 0.0, 0.18, "white", "tv", Color("#4a4664"), MeshBuf.WHITE)
			if hs % 3 == 0:
				_stool(p, k, 0.62, 0.42)
		"mat":
			_ib(p, k, 0.16, 0.2, 0.52, 0.8, 0.0, 0.03, "white", "mat", Color("#b0a468"), MeshBuf.WHITE)
			_ib(p, k, 0.62, 0.16, 0.82, 0.34, 0.0, 0.16, "crate", "crate")
			_ib(p, k, 0.64, 0.6, 0.82, 0.78, 0.0, 0.1, "white", "stove", Color("#5a5674"), MeshBuf.WHITE)
		"flat":
			_ib(p, k, 0.16, 0.16, 0.52, 0.7, 0.0, 0.14, "white", "bed_red", Color("#8a6a5a"), MeshBuf.WHITE)
			_ib(p, k, 0.6, 0.5, 0.84, 0.74, 0.0, 0.18, "white", "white", WOODC, WOODT)
			_stool(p, k, 0.66, 0.36)
			_stool(p, k, 0.66, 0.78, Color("#5f86c4"))
			_ib(p, k, 0.62, 0.16, 0.84, 0.3, 0.0, 0.2, "white", "tv", Color("#4a4664"), MeshBuf.WHITE)
			_ib(p, k, 0.16, 0.76, 0.3, 0.86, 0.0, 0.22, "white", "white", Color("#c0714f"), Color("#6fb85a"))
		"cages":
			for i in 2:
				for j in 2:
					_ib(p, k, 0.16 + 0.4 * float(i), 0.16 + 0.38 * float(j), 0.44 + 0.4 * float(i), 0.44 + 0.38 * float(j), 0.0, 0.34, "bunk", "bunk")
		"stove":
			_ib(p, k, 0.16, 0.16, 0.84, 0.36, 0.0, 0.2, "white", "stove", Color("#8f8ea6"), MeshBuf.WHITE)
			_ib(p, k, 0.2, 0.5, 0.42, 0.72, 0.0, 0.24, "steel_side", "vat")
			_ib(p, k, 0.56, 0.52, 0.82, 0.8, 0.0, 0.18, "white", "white", WOODC, WOODT)
			emitter(_ipos(p, k, 0.31, 0.61, 0.3), "steam")
		"tables":
			_ib(p, k, 0.16, 0.16, 0.84, 0.32, 0.0, 0.2, "white", "stove", Color("#8f8ea6"), MeshBuf.WHITE)
			for i in 2:
				var tx := 0.2 + 0.36 * float(i)
				_ib(p, k, tx, 0.52, tx + 0.22, 0.74, 0.0, 0.16, "white", "white", WOODC, WOODT)
				_stool(p, k, tx + 0.06, 0.4)
				_stool(p, k, tx + 0.06, 0.77)
			emitter(_ipos(p, k, 0.3, 0.24, 0.3), "steam")
		"sewing":
			for i in 3:
				_ib(p, k, 0.16, 0.16 + 0.24 * float(i), 0.5, 0.32 + 0.24 * float(i), 0.0, 0.18, "white", "sewing", WOODC, MeshBuf.WHITE)
				_stool(p, k, 0.54, 0.2 + 0.24 * float(i), Color("#5f86c4"))
			_ib(p, k, 0.68, 0.2, 0.86, 0.5, 0.0, 0.14, "white", "white", Color("#e8a0b8"), Color("#f4b8cc"))
			_ib(p, k, 0.68, 0.56, 0.86, 0.8, 0.0, 0.2, "white", "white", Color("#6fb4d8"), Color("#8fcbe0"))
		"mahjong":
			_ib(p, k, 0.3, 0.3, 0.7, 0.7, 0.0, 0.2, "white", "mj_table", Color("#8a6a5a"), MeshBuf.WHITE)
			_stool(p, k, 0.45, 0.16)
			_stool(p, k, 0.45, 0.74)
			_stool(p, k, 0.16, 0.45)
			_stool(p, k, 0.74, 0.45)
		"dentist":
			_ib(p, k, 0.3, 0.3, 0.56, 0.72, 0.0, 0.2, "white", "chair_dentist", Color("#d6d8de"), MeshBuf.WHITE)
			_ib(p, k, 0.64, 0.16, 0.84, 0.4, 0.0, 0.3, "white", "white", Color("#eef0ea"), Color("#ffffff"))
			_ib(p, k, 0.6, 0.48, 0.66, 0.54, 0.0, 0.42, "white", "emit", Color("#b9bcc8"), Color("#fff2d8"))
			_ib(p, k, 0.16, 0.16, 0.26, 0.5, 0.0, 0.12, "white", "white", WOODC, WOODT)
		"desks":
			for i in 2:
				for j in 3:
					_ib(p, k, 0.16 + 0.36 * float(i), 0.16 + 0.24 * float(j), 0.42 + 0.36 * float(i), 0.3 + 0.24 * float(j), 0.0, 0.18, "white", "desk", WOODC, MeshBuf.WHITE)
		"vats":
			_ib(p, k, 0.16, 0.16, 0.5, 0.5, 0.0, 0.28, "steel_side", "vat")
			_ib(p, k, 0.54, 0.4, 0.84, 0.7, 0.0, 0.28, "steel_side", "vat")
			_ib(p, k, 0.16, 0.62, 0.4, 0.84, 0.0, 0.16, "crate", "crate")
			emitter(_ipos(p, k, 0.33, 0.33, 0.36), "steam")
			emitter(_ipos(p, k, 0.7, 0.55, 0.36), "steam")
		"noodles":
			_ib(p, k, 0.16, 0.16, 0.5, 0.84, 0.0, 0.26, "white", "noodles", WOODC, MeshBuf.WHITE)
			_ib(p, k, 0.6, 0.16, 0.84, 0.4, 0.0, 0.24, "machine", "machine")
			_ib(p, k, 0.62, 0.52, 0.82, 0.68, 0.0, 0.14, "white", "white", Color("#e6dcc4"), Color("#f4ecd8"))
			_ib(p, k, 0.64, 0.7, 0.84, 0.84, 0.0, 0.1, "white", "white", Color("#e6dcc4"), Color("#f4ecd8"))
		"machine":
			_ib(p, k, 0.16, 0.16, 0.56, 0.44, 0.0, 0.3, "machine", "machine")
			_ib(p, k, 0.16, 0.56, 0.44, 0.84, 0.0, 0.2, "white", "white", STEEL, Color("#d6d8de"))
			_ib(p, k, 0.62, 0.56, 0.84, 0.84, 0.0, 0.16, "crate", "junk")
			emitter(_ipos(p, k, 0.3, 0.7, 0.26), "sparks")
		"shelves":
			_ib(p, k, 0.14, 0.14, 0.86, 0.26, 0.0, 0.36, "shelf", "white", MeshBuf.WHITE, Color("#7a5848"))
			_ib(p, k, 0.14, 0.4, 0.26, 0.86, 0.0, 0.3, "shelf", "white", MeshBuf.WHITE, Color("#7a5848"))
			_ib(p, k, 0.46, 0.56, 0.8, 0.72, 0.0, 0.2, "white", "white", WOODC, WOODT)
		"karaoke":
			_ib(p, k, 0.14, 0.14, 0.86, 0.3, 0.0, 0.16, "white", "white", Color("#9b3a6e"), Color("#c95a8e"))
			_ib(p, k, 0.14, 0.3, 0.3, 0.7, 0.0, 0.16, "white", "white", Color("#9b3a6e"), Color("#c95a8e"))
			_ib(p, k, 0.44, 0.44, 0.68, 0.6, 0.0, 0.12, "white", "white", Color("#3e3a54"), Color("#5c566e"))
			_ib(p, k, 0.4, 0.78, 0.74, 0.86, 0.0, 0.3, "tv", "white", MeshBuf.WHITE, Color("#3e3a54"))
		"tub":
			_ib(p, k, 0.14, 0.14, 0.86, 0.6, 0.0, 0.16, "white", "water", Color("#e6e2d6"), MeshBuf.WHITE)
			_ib(p, k, 0.16, 0.7, 0.3, 0.84, 0.0, 0.1, "white", "white", WOODC, WOODT)
			_ib(p, k, 0.5, 0.72, 0.84, 0.84, 0.0, 0.1, "white", "white", WOODC, WOODT)
			emitter(_ipos(p, k, 0.5, 0.37, 0.25), "steam")
		"slots":
			for i in 3:
				_ib(p, k, 0.16 + 0.24 * float(i), 0.14, 0.34 + 0.24 * float(i), 0.3, 0.0, 0.4, "slot", "white", MeshBuf.WHITE, Color("#b0306a"))
			_ib(p, k, 0.3, 0.5, 0.7, 0.76, 0.0, 0.2, "white", "mj_table", Color("#8a6a5a"), MeshBuf.WHITE)
		"crates":
			_ib(p, k, 0.16, 0.16, 0.44, 0.44, 0.0, 0.26, "crate", "crate")
			_ib(p, k, 0.2, 0.2, 0.4, 0.4, 0.26, 0.46, "crate", "crate")
			_ib(p, k, 0.5, 0.16, 0.76, 0.42, 0.0, 0.24, "crate", "crate")
			_ib(p, k, 0.6, 0.6, 0.8, 0.8, 0.0, 0.3, "white", "white", Color("#c2463c"), Color("#d8695f"))
		"clinic":
			_ib(p, k, 0.16, 0.16, 0.46, 0.7, 0.0, 0.16, "white", "bed", Color("#d6d8de"), MeshBuf.WHITE)
			_ib(p, k, 0.62, 0.16, 0.84, 0.36, 0.0, 0.3, "white", "white", Color("#eef0ea"), Color("#ffffff"))
			_ib(p, k, 0.6, 0.6, 0.84, 0.78, 0.0, 0.18, "white", "desk", WOODC, MeshBuf.WHITE)
		"hall":
			_ib(p, k, 0.3, 0.2, 0.7, 0.8, 0.0, 0.18, "white", "white", WOODC, WOODT)
			for i in 3:
				_stool(p, k, 0.16, 0.25 + 0.2 * float(i))
				_stool(p, k, 0.74, 0.25 + 0.2 * float(i))
		"altar":
			_ib(p, k, 0.3, 0.14, 0.7, 0.34, 0.0, 0.3, "altar", "white", MeshBuf.WHITE, Color("#c2463c"))
		_:
			_ib(p, k, 0.16, 0.16, 0.84, 0.3, 0.0, 0.2, "white", "white", WOODC, WOODT)
			_ib(p, k, 0.16, 0.7, 0.34, 0.86, 0.0, 0.3, "shelf", "white", MeshBuf.WHITE, Color("#7a5848"))


## 공사가 끝날 때 떨어져 나갈 비계만 따로(연출용).
func build_scaffold(p: Vector3i) -> ArrayMesh:
	var keep := mb
	mb = MeshBuf.new()
	var sc := tile("scaffold")
	var nt := tile("net")
	var o := 0.07
	for d in 4:
		mb.quad2(fp(p, d, -o, 1.2, o), fp(p, d, 1 + o, 1.2, o), fp(p, d, 1 + o, 0, o), fp(p, d, -o, 0, o), NRM[d], Rect2(sc.position, Vector2(16, 16)))
		if d % 2 == 0:
			mb.quad2(fp(p, d, 0, 0.9, o + 0.01), fp(p, d, 1, 0.9, o + 0.01), fp(p, d, 1, 0.06, o + 0.01), fp(p, d, 0, 0.06, o + 0.01), NRM[d], Rect2(nt.position, Vector2(16, 14)))
	var m := mb.commit()
	mb = keep
	return m
