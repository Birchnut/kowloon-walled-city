class_name FacilityBuilder
extends RefCounted
## FacilityBuilder — 시설 한 채(발자국 w×h, d개 층, 회전)를 층 단위 조각으로 짓는다(v4).
## 바깥: data/art/looks.json(벽 자재·앞면·간판·차양·지붕 소품). 안: look마다 소품 배치 + 사람 자리(slots) — 이 파일의 _interior().
## 좌표: 건물 앞면 기준 지역 좌표 (U = 앞면을 따라 0..Wf, V = 앞에서 안쪽으로 0..Df, 높이 = 층 비율 0..1).
## 시설 외벽은 정점 종류에 +16(인형의 집 표시)을 달아, 가까운 확대에서 카메라 쪽 벽을 셰이더가 걷어 낸다(재메시 없음).

const KI := MeshBuf.K_INTERIOR
const DOLL := 16.0
const WOOD := Color("#b98562")
const WOOD_T := Color("#d9a878")
const DARK := Color("#3e3a54")
const STEEL := Color("#9aa0b4")
const STEEL_T := Color("#c4c8d4")
const CLOTH := ["#d85f5f", "#5f86c4", "#e0a23c", "#5fae7a", "#f4f0e6", "#b58be0", "#ff9ac0"]
const GOODS := ["#e6b45a", "#8fc0b8", "#d85f5f", "#f4ead2", "#9b62c9", "#7fd08a", "#ff9a4a"]

var m: CityMesher
var fronts: Dictionary = {}       # bid -> 앞면 방향

# 지금 짓는 조각
var F := 1
var Wf := 1
var Df := 1
var C := Vector3.ZERO
var RU := Vector3.ZERO
var RV := Vector3.ZERO
var fh := 0.8165
var look := ""
var rec: Dictionary = {}
var bid := -1
var bd: Dictionary = {}
var active := true
var o := Vector3i.ZERO
var w := 1
var h := 1
var d := 1
var z := 0
var zi := 0                       # 건물 안에서 몇 번째 층(0 = 가장 아래)
var seed_v := 0
var cut := false
var kprop := KI
var slice: Dictionary = {}        # 이 층 조각의 칸들
var _hs := 1


func setup(mesher: CityMesher) -> void:
	m = mesher
	fh = mesher.fh


func reset() -> void:
	fronts.clear()


func _rnd() -> float:
	_hs = (_hs * 1103515245 + 12345) & 0x7fffffff
	return float((_hs >> 8) % 65536) / 65536.0


func _ri(n: int) -> int:
	return int(_rnd() * n) % maxi(n, 1)


# ================================================================== 진입점
## 시설 칸 하나를 받는다. 그 층 조각의 기준 칸(가장 작은 x,y)일 때만 조각 전체를 짓는다.
func build_cell(p: Vector3i, c: Dictionary, cut_mode: bool) -> void:
	var ext := m.extent_of(c, p)
	o = ext["origin"]
	w = ext["w"]
	h = ext["h"]
	d = ext["d"]
	bid = int(c.get("bid", -1))
	z = p.z
	zi = z - o.z
	slice = {}
	for x in range(o.x, o.x + w):
		for y in range(o.y, o.y + h):
			var q := Vector3i(x, y, z)
			var cq: Dictionary = m.state.cells.get(q, {})
			if not cq.is_empty() and int(cq.get("bid", -2)) == bid:
				slice[q] = true
	if slice.is_empty():
		slice[p] = true
	var keys: Array = slice.keys()
	keys.sort()
	if keys[0] != p:
		return
	cut = cut_mode
	bd = m.bld(c)
	active = bool(bd.get("active", true)) and str(c.get("burn", bd.get("burn", ""))) != "burnt"
	look = m.look_name(c)
	rec = m.cfg.look_recipe(look, m.cat_of(c))
	seed_v = int(c.get("seed", bid * 977))
	_hs = (seed_v * 31 + z * 7 + 1) & 0x7fffffff
	if _hs == 0:
		_hs = 1
	F = _front()
	_frame()
	m.mb.owner = m.owner_of(Vector3i(o.x, o.y, z))
	var form: String = str(rec.get("form", "box"))
	kprop = KI
	match form:
		"open":
			kprop = MeshBuf.K_PLAIN
			_open_ground()
		"shed":
			_shed()
		"tank":
			_tank()
			return
		"pole":
			_pole()
			return
		"shrine":
			_shrine()
			return
		_:
			_shell()
	_interior()
	if zi == d - 1 and form != "open":
		_sign_main()
	if not cut and zi == d - 1:
		if form == "box":
			m.mb.kind_add = 32.0
		_roof_props()
		m.mb.kind_add = 0.0
	_exterior_fx()


# ================================================================== 틀
func _front() -> int:
	if fronts.has(bid):
		return fronts[bid]
	var best := -1.0
	var front := 1
	for dd in [1, 0, 2, 3]:
		var sc := 0.0
		var n := 0
		for x in range(o.x, o.x + w):
			for y in range(o.y, o.y + h):
				var q := Vector3i(x, y, o.z)
				var nb: Vector3i = q + CityMesher.DIR[dd]
				if nb.x >= o.x and nb.x < o.x + w and nb.y >= o.y and nb.y < o.y + h:
					continue
				n += 1
				if not m.state.cells.has(nb) and not m.voids.has(nb):
					sc += 2.0
					if not m.state.cells.has(nb + CityMesher.DIR[dd]):
						sc += 1.0
					if o.z > 0 and not m.solid.has(nb - CityMesher.UPI):
						sc -= 1.5   # 디딜 바닥이 없는 허공 쪽
		sc += float(n) * 0.6        # 긴 변을 좋아한다(간판·가게 앞)
		if dd == 1:
			sc += 0.3
		if sc > best:
			best = sc
			front = dd
	fronts[bid] = front
	return front


func _frame() -> void:
	var along_x := F == 1 or F == 3
	Wf = w if along_x else h
	Df = h if along_x else w
	var cen := Vector3(float(o.x) + float(w) * 0.5, float(z) * fh, float(o.y) + float(h) * 0.5)
	RU = CityMesher.RGT[F]
	RV = -CityMesher.NRM[F]
	C = cen + CityMesher.NRM[F] * (float(Df) * 0.5) - RU * (float(Wf) * 0.5)


## 지역 좌표 → 월드. hf = 층 비율.
func P(u: float, v: float, hf: float = 0.0) -> Vector3:
	return C + RU * u + RV * v + Vector3(0, hf * fh, 0)


## 지역 칸(iu, iv)의 월드 칸
func cell_at(iu: int, iv: int) -> Vector3i:
	var pw := P(float(iu) + 0.5, float(iv) + 0.5)
	return Vector3i(int(floor(pw.x)), int(floor(pw.z)), z)


func dirv(face: String) -> Vector3:
	match face:
		"f":
			return -RV
		"b":
			return RV
		"l":
			return -RU
		"r":
			return RU
	return -RV


## 지역 상자(색). 높이는 층 비율.
func bx(u0: float, v0: float, u1: float, v1: float, h0: float, h1: float, col: Color, top: Color = Color(-1, 0, 0), side_t: String = "white", top_t: String = "white", kind: float = -1.0) -> void:
	var a := P(u0, v0, h0)
	var b := P(u1, v1, h1)
	var mn := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var mx := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	m.mb.box(mn, mx, m.tile(side_t), m.tile(top_t), fh, col, 31, _rnd(), kprop if kind < 0.0 else kind, top)


## 지역 수직 쿼드(앞을 향함 = -RV 방향). 벽에 붙는 화면·거울·칠판.
func vq(u0: float, u1: float, v: float, h0: float, h1: float, t: String, col: Color = MeshBuf.WHITE, kind: float = -1.0, face_back: bool = false) -> void:
	var r := m.tile(t)
	var rr := Rect2(r.position, Vector2(minf((u1 - u0) * 16.0, r.size.x), minf((h1 - h0) * 16.0, r.size.y)))
	if face_back:
		m.mb.quad(P(u1, v, h1), P(u0, v, h1), P(u0, v, h0), P(u1, v, h0), RV, rr, col, _rnd(), kprop if kind < 0.0 else kind)
	else:
		m.mb.quad(P(u0, v, h1), P(u1, v, h1), P(u1, v, h0), P(u0, v, h0), -RV, rr, col, _rnd(), kprop if kind < 0.0 else kind)


func light_at(u: float, v: float, hf: float, col: Color, r: float, warm: float = 0.0) -> void:
	if active:
		m.light(P(u, v, hf), col, r, warm)


func emit_at(u: float, v: float, hf: float, type: String) -> void:
	if active:
		m.emitter(P(u, v, hf), type)


## 사람 자리. role = staff(일손 비율만큼 보임) | guest(영업 중·시간대) | idle(늘). face = f/b/l/r(앞면 기준).
func slot(u: float, v: float, pose: String, face: String, role: String = "staff", hf: float = 0.0, extra: Dictionary = {}) -> void:
	var sl := {"bid": bid, "pos": P(u, v, hf), "dir": dirv(face), "pose": pose, "role": role, "z": z, "look": look,
		"out": str(rec.get("form", "box")) in ["open", "shed"], "i": m.slots.size()}
	var fc := cell_at(clampi(int(u), 0, Wf - 1), 0) + CityMesher.DIR[F]
	if str(rec.get("form", "box")) == "box" and not m.state.cells.has(fc) and not m.voids.has(fc) and (z == 0 or m.solid.has(fc - CityMesher.UPI)):
		# 문밖 자리(담배 쉬는 시간): 앞면 바깥 0.35칸
		sl["door"] = P(clampf(u, 0.3, float(Wf) - 0.3), -0.35, 0.0)
	sl.merge(extra)
	m.slots.append(sl)


# ================================================================== 껍데기(box)
func _shell() -> void:
	var mat := m.cfg.material_key(str(rec.get("wall", "render")))
	var front_kind: String = str(rec.get("front", "shop"))
	var paper := ViewCfg.col(rec.get("paper", "#d8ccb8"), Color("#d8ccb8"))
	var fl := "f_" + str(rec.get("floor", "concrete"))
	if not m.atlas.has(fl):
		fl = "f_concrete"
	var glass_wall: bool = str(m.cfg.material(mat).get("pattern", "")) == "curtain"
	for q in slice:
		var base := m.cellv(q)
		# 바닥
		m.mb.quad(Vector3(base.x, base.y + 0.004, base.z), Vector3(base.x + 1, base.y + 0.004, base.z), Vector3(base.x + 1, base.y + 0.004, base.z + 1), Vector3(base.x, base.y + 0.004, base.z + 1), Vector3.UP, m.tile(fl), MeshBuf.WHITE if active else Color(0.75, 0.75, 0.8), 0.0, KI)
		for dd in 4:
			var nb: Vector3i = q + CityMesher.DIR[dd]
			if slice.has(nb) or (m.state.cells.has(nb) and int(m.state.cells[nb].get("bid", -1)) == bid):
				continue
			var exposed := not m.solid.has(nb)
			var is_front := dd == F
			if cut:
				_cut_wall(q, dd, mat, exposed, is_front and front_kind in ["open", "hall"])
				continue
			if exposed:
				if is_front and front_kind in ["open", "hall"]:
					_open_front(q, dd, mat)
				else:
					var wv := ViewCfg.h2(seed_v + q.x * 3 + q.y, dd) % 2
					m.fquad(q, dd, 0, 1, 0, 1, 0.0, m.tile("wall_%s_%d" % [mat, wv]), MeshBuf.WHITE, float(ViewCfg.h2(seed_v, dd) % 991) / 991.0, DOLL + (MeshBuf.K_BIZ if glass_wall else 0.0))
					_facade(q, dd, mat, is_front, front_kind)
			# 안벽(안에서 보이는 면)
			m.mb.quad(m.fp(q, dd, 1, 1, -0.012), m.fp(q, dd, 0, 1, -0.012), m.fp(q, dd, 0, 0, -0.012), m.fp(q, dd, 1, 0, -0.012), -CityMesher.NRM[dd], m.tile("white"), paper.darkened(0.06 * float(dd % 2)), 0.0, KI)
			# 걸레받이
			m.mb.quad(m.fp(q, dd, 1, 0.08, -0.016), m.fp(q, dd, 0, 0.08, -0.016), m.fp(q, dd, 0, 0, -0.016), m.fp(q, dd, 1, 0, -0.016), -CityMesher.NRM[dd], m.tile("white"), paper.darkened(0.35), 0.0, KI)
			# 벽 꾸밈: 벽보·달력·시계·선반(안에서 보이는 면, 칸마다 다르게)
			var dh := ViewCfg.h3(seed_v + q.x * 13, q.y * 7 + q.z, dd) % 100
			if dh < 55:
				var pu := 0.18 + 0.5 * float(dh % 7) / 7.0
				var pc := Color(["#d85f5f", "#e0a23c", "#5f86c4", "#5fae7a", "#f4ecd8", "#b58be0"][dh % 6])
				m.mb.quad(m.fp(q, dd, pu + 0.22, 0.78, -0.02), m.fp(q, dd, pu, 0.78, -0.02), m.fp(q, dd, pu, 0.5, -0.02), m.fp(q, dd, pu + 0.22, 0.5, -0.02), -CityMesher.NRM[dd], m.tile("white"), pc, 0.0, KI)
				m.mb.quad(m.fp(q, dd, pu + 0.18, 0.74, -0.022), m.fp(q, dd, pu + 0.04, 0.74, -0.022), m.fp(q, dd, pu + 0.04, 0.64, -0.022), m.fp(q, dd, pu + 0.18, 0.64, -0.022), -CityMesher.NRM[dd], m.tile("white"), pc.lightened(0.45), 0.0, KI)
			elif dh < 70:
				m.fbox(q, dd, 0.15, 0.85, 0.62, 0.66, -0.12, 0.0, m.tile("white"), m.tile("white"), WOOD, 31, 0.0, KI, WOOD_T)
				for k in 4:
					m.fbox(q, dd, 0.2 + 0.16 * float(k), 0.3 + 0.16 * float(k), 0.66, 0.74 + 0.03 * float(k % 2), -0.1, -0.02, m.tile("white"), m.tile("white"), Color(GOODS[(k + dh) % GOODS.size()]), 31, 0.0, KI)
			elif dh < 78:
				m.fbox(q, dd, 0.44, 0.56, 0.7, 0.82, -0.03, 0.0, m.tile("white"), m.tile("white"), Color("#f4f0e6"), 31, 0.0, KI)
	if not cut and zi == d - 1:
		m.mb.kind_add = 32.0
		_roof(mat)
		m.mb.kind_add = 0.0


func _cut_wall(q: Vector3i, dd: int, mat: String, exposed: bool, open_front: bool) -> void:
	var cap := m.tile("cutcap")
	if open_front:
		m._edge_box(q, dd, 0.0, 0.08, CityMesher.CUT_T, CityMesher.CUT_WALL, m.tile("wall_%s_0" % mat), cap)
		m._edge_box(q, dd, 0.92, 1.0, CityMesher.CUT_T, CityMesher.CUT_WALL, m.tile("wall_%s_0" % mat), cap)
		return
	if exposed:
		var door := q.z == 0 and dd == F
		if door:
			m._edge_box(q, dd, 0.0, 0.3125, CityMesher.CUT_T, CityMesher.CUT_WALL, m.tile("wall_%s_0" % mat), cap)
			m._edge_box(q, dd, 0.6875, 1.0, CityMesher.CUT_T, CityMesher.CUT_WALL, m.tile("wall_%s_0" % mat), cap)
		else:
			m._edge_box(q, dd, 0.0, 1.0, CityMesher.CUT_T, CityMesher.CUT_WALL, m.tile("wall_%s_0" % mat), cap)
	else:
		m._edge_box(q, dd, 0.0, 1.0, CityMesher.CUT_TP, CityMesher.CUT_WALL, m.tile("white"), cap, Color("#e9dfcf"))


## 앞이 트인 가게(찻집·시장·소방대): 기둥과 인방만.
func _open_front(q: Vector3i, dd: int, mat: String) -> void:
	var post := ViewCfg.col((m.cfg.material(mat).get("ramp", ["#cccccc", "#aaaaaa", "#888888"]) as Array)[2], Color("#8a7a8a"))
	if str(rec.get("front", "")) == "hall":
		post = Color("#b0303a")
	m.fbox(q, dd, 0.0, 0.07, 0.0, 1.0, 0.0, 0.07, m.tile("white"), m.tile("white"), post, 15)
	m.fbox(q, dd, 0.93, 1.0, 0.0, 1.0, 0.0, 0.07, m.tile("white"), m.tile("white"), post, 15)
	m.fquad(q, dd, 0, 1, 0.84, 1.0, 0.0, m.tile("wall_%s_0" % mat), MeshBuf.WHITE, 0.0, 0.0)
	m.fbox(q, dd, 0.0, 1.0, 0.82, 0.86, 0.0, 0.05, m.tile("white"), m.tile("white"), post.darkened(0.2), 15)


## 바깥 면 꾸밈: 앞면 = 가게창/셔터/유리/문 + 차양, 옆면 = 작은 창·실외기.
func _facade(q: Vector3i, dd: int, mat: String, is_front: bool, front_kind: String) -> void:
	var hs := ViewCfg.h2(seed_v + q.x * 5 + q.y * 11, 100 + dd)
	var wrnd := float(hs % 997) / 997.0
	var frames: Array = m.cfg.material(mat).get("frames", ["a"])
	var fk: String = str(frames[hs % maxi(frames.size(), 1)]) if not frames.is_empty() else "a"
	var biz := MeshBuf.K_BIZ + DOLL
	if is_front:
		var t := ""
		match front_kind:
			"shop":
				t = ["shop_a", "shop_c", "shop_b"][hs % 3]
			"shutter":
				t = "shutter_0" if active else "shutter_1"
			"glass":
				t = "win_full_e"
			"door":
				t = "win_small_" + fk
		if t != "":
			m.fquad(q, dd, 0, 1, 0, 1, CityMesher.EPS, m.tile(t), MeshBuf.WHITE, wrnd, biz)
		if front_kind == "door" and (q.z == 0 or m.solid.has(q + CityMesher.DIR[dd] - CityMesher.UPI)):
			m.fquad(q, dd, 0, 1, 0, 1, CityMesher.EPS * 1.5, m.tile("door_%d" % (hs % 4)), MeshBuf.WHITE, wrnd, biz)
		var aw: String = str(rec.get("awning", ""))
		if aw != "":
			m._awning(q, dd, 0.03, 0.97, 0.74, 0.16, 0.34, ViewCfg.col(aw))
		if active:
			var gl: String = str(rec.get("glow", ""))
			m.light(m.fp(q, dd, 0.5, 0.4, 0.4), m.cfg.neon(gl) if gl != "" else Color(1, 1, 1), 1.5 if gl != "" else 1.1, 0.0 if gl != "" else 0.8)
	else:
		var win: String = str(rec.get("win", "small"))
		if win != "none" and hs % 100 < 60:
			m.fquad(q, dd, 0, 1, 0, 1, CityMesher.EPS, m.tile("win_slit" if win == "slit" else "win_%s_%s" % [win if win in ["small", "std", "wide"] else "small", fk]), MeshBuf.WHITE, wrnd, biz)
		elif hs % 100 > 86 and m.power_on:
			m._ac(q, dd, 0.56, 0.14)


## 지붕: 위가 빈 칸만. 테두리(난간)는 같은 건물끼리 이어진다.
func _roof(mat: String) -> void:
	var ramp: Array = m.cfg.material(mat).get("ramp", ["#cccccc", "#aaaaaa"])
	for q in slice:
		var above: Vector3i = q + CityMesher.UPI
		if m.solid.has(above):
			continue
		var base := m.cellv(q)
		var y := base.y + fh
		m.mb.quad(Vector3(base.x, y, base.z), Vector3(base.x + 1, y, base.z), Vector3(base.x + 1, y, base.z + 1), Vector3(base.x, y, base.z + 1), Vector3.UP, m.tile("roof_%s_%d" % [mat, ViewCfg.h2(seed_v, q.x + q.y) % 3]))
		for dd in 4:
			var nb: Vector3i = q + CityMesher.DIR[dd]
			if slice.has(nb) or m.solid.has(nb + CityMesher.UPI):
				continue
			m.fbox(above, dd, 0.0, 1.0, 0.0, 0.09, -0.0625, 0.0, m.tile("white"), m.tile("white"), ViewCfg.col(ramp[1]), 15, 0.0, 0.0, ViewCfg.col(ramp[0]))


func _roof_free() -> bool:
	for q in slice:
		if m.state.cells.has(q + CityMesher.UPI) or m.voids.has(q + CityMesher.UPI):
			return false
	return true


# ================================================================== 트인 꼴(open) · 차양 꼴(shed)
func _open_ground() -> void:
	var g: String = str(rec.get("ground", "mat"))
	var t: String = str({"mat": "f_mat", "soil": "f_soil", "park": "f_tile", "roof": "f_concrete"}.get(g, "f_concrete"))
	for q in slice:
		var b := m.cellv(q)
		var y := b.y + 0.01
		m.mb.quad(Vector3(b.x + 0.04, y, b.z + 0.04), Vector3(b.x + 0.96, y, b.z + 0.04), Vector3(b.x + 0.96, y, b.z + 0.96), Vector3(b.x + 0.04, y, b.z + 0.96), Vector3.UP, m.tile(t))
		if g == "soil" or g == "park":
			for dd in 4:
				if not slice.has(q + CityMesher.DIR[dd]):
					m.fbox(q, dd, 0.0, 1.0, 0.0, 0.12, -0.08, 0.0, m.tile("white"), m.tile("white"), Color("#a89a90"), 15, 0.0, 0.0, Color("#c9bdb0"))


func _shed() -> void:
	var rm := m.cfg.material_key(str(rec.get("roofmat", "sheet")))
	var post := Color("#8a7a6a")
	var hh := 0.86
	var corners := [Vector2(0.05, 0.05), Vector2(float(Wf) - 0.12, 0.05), Vector2(0.05, float(Df) - 0.12), Vector2(float(Wf) - 0.12, float(Df) - 0.12)]
	for cpt in corners:
		bx(cpt.x, cpt.y, cpt.x + 0.07, cpt.y + 0.07, 0.0, hh, post, Color(-1, 0, 0), "white", "white", MeshBuf.K_PLAIN)
	if not cut:
		# 지붕판: 앞으로 살짝 내려온 함석
		var a := P(-0.08, -0.12, hh + 0.02)
		var b := P(float(Wf) + 0.08, -0.12, hh - 0.06)
		var c2 := P(float(Wf) + 0.08, float(Df) + 0.02, hh + 0.12)
		var d2 := P(-0.08, float(Df) + 0.02, hh + 0.12)
		var r := m.tile("roof_%s_0" % rm)
		m.mb.quad2(d2, c2, b, a, Vector3.UP, Rect2(r.position, Vector2(16, 16)), MeshBuf.WHITE)
		var aw: String = str(rec.get("awning", ""))
		if aw != "":
			# 앞 자락(천)
			var ac := ViewCfg.col(aw)
			m.mb.quad2(P(-0.08, -0.12, hh - 0.06), P(float(Wf) + 0.08, -0.12, hh - 0.06), P(float(Wf) + 0.08, -0.12, hh - 0.2), P(-0.08, -0.12, hh - 0.2), -RV, Rect2(m.tile("awning").position, Vector2(16, 4)), ac)
	# 뒷벽(낮은 판자)
	bx(0.0, float(Df) - 0.06, float(Wf), float(Df), 0.0, 0.45, Color("#a8866a"), Color(-1, 0, 0), "wall_timber_1" if m.atlas.has("wall_timber_1") else "white", "white", MeshBuf.K_PLAIN)
	# 바닥판
	for q in slice:
		var bb := m.cellv(q)
		m.mb.quad(Vector3(bb.x, bb.y + 0.006, bb.z), Vector3(bb.x + 1, bb.y + 0.006, bb.z), Vector3(bb.x + 1, bb.y + 0.006, bb.z + 1), Vector3(bb.x, bb.y + 0.006, bb.z + 1), Vector3.UP, m.tile("f_concrete"), Color(0.92, 0.9, 0.88))
	light_at(float(Wf) * 0.5, 0.4, 0.8, Color("#ffc46a"), 1.4, 0.0)


func _tank() -> void:
	var base := m.cellv(Vector3i(o.x, o.y, z))
	for q in slice:
		var b := m.cellv(q)
		for lg in [Vector2(0.15, 0.15), Vector2(0.78, 0.15), Vector2(0.15, 0.78), Vector2(0.78, 0.78)]:
			m.cbox(b + Vector3(lg.x, 0, lg.y), b + Vector3(lg.x + 0.07, fh * 0.4, lg.y + 0.07), Color("#6a6486"))
		m.wbox(b + Vector3(0.1, fh * 0.4, 0.1), b + Vector3(0.9, fh * 1.15, 0.9), "tank_side" if m.atlas.has("tank_side") else "steel_side", "tank_top" if m.atlas.has("tank_top") else "white", MeshBuf.WHITE)
		m.cbox(b + Vector3(0.45, fh * 1.15, 0.45), b + Vector3(0.6, fh * 1.25, 0.6), Color("#8a96aa"))
		m.mb.owner = m.owner_of(q)
	slot(0.3, -0.25, "swork", "b", "staff")
	_sign_small(base + Vector3(0.5, fh * 0.6, 0.95))


func _pole() -> void:
	var b := m.cellv(Vector3i(o.x, o.y, z))
	var c0 := b + Vector3(0.5, 0, 0.5)
	m.cbox(c0 + Vector3(-0.05, 0, -0.05), c0 + Vector3(0.05, fh * 1.9, 0.05), Color("#7a6a5a"))
	m.cbox(c0 + Vector3(-0.35, fh * 1.7, -0.03), c0 + Vector3(0.35, fh * 1.75, 0.03), Color("#5a4a4a"))
	m.cbox(c0 + Vector3(-0.03, fh * 1.45, -0.3), c0 + Vector3(0.03, fh * 1.5, 0.3), Color("#5a4a4a"))
	m.cbox(c0 + Vector3(-0.12, fh * 0.5, 0.06), c0 + Vector3(0.12, fh * 0.85, 0.16), Color("#7a8a6a"), Color("#9aaa8a"))
	# 문어발 전선: 사방 칸으로 늘어진 줄
	var wc := Color("#2e2a3a")
	var i := 0
	for tgt in [Vector3(-2.5, -0.6, 0.3), Vector3(2.2, -0.9, -0.4), Vector3(0.4, -1.1, 2.4), Vector3(-0.3, -0.5, -2.6), Vector3(1.8, -0.4, 1.9), Vector3(-1.9, -1.0, -1.6)]:
		var top := c0 + Vector3(0, fh * (1.72 if i % 2 == 0 else 1.47), 0)
		var end: Vector3 = top + tgt
		var mid := (top + end) * 0.5 + Vector3(0, -0.25, 0)
		for seg in [[top, mid], [mid, end]]:
			var a: Vector3 = seg[0]
			var bq: Vector3 = seg[1]
			m.mb.quad2(a, bq, bq + Vector3(0, -0.025, 0), a + Vector3(0, -0.025, 0), Vector3(0, 0, 1), m.sub(m.tile("white"), 0, 0, 1, 1), wc)
		i += 1
	if active:
		m.light(c0 + Vector3(0, fh * 0.7, 0.2), m.cfg.neon("yellow"), 0.9)
		m.emitter(c0 + Vector3(0, fh * 1.7, 0), "sparks")
	slot(-0.2, -0.2, "swork", "b", "staff", 0.0, {"pos": c0 + Vector3(0.18, 0, 0.32)})


func _shrine() -> void:
	m._build_shrine(Vector3i(o.x, o.y, z), {"kind": "facility", "bid": bid, "seed": seed_v, "type": ""}, rec, seed_v)
	slot(0.5, -0.3, "bow", "b", "guest")


## 탱크·작은 것의 작은 간판
func _sign_small(at: Vector3) -> void:
	var text := m.sign_of(m.state.cells.get(Vector3i(o.x, o.y, z), {}))
	if text == "":
		return
	var tr := Rect2(m.atlas.sign_rect(text, false))
	if tr.size.x <= 0.0:
		return
	var sw := tr.size.x / 32.0
	var sh := tr.size.y / 32.0
	m.cbox(at + Vector3(-sw * 0.5 - 0.03, -0.03, 0.0), at + Vector3(sw * 0.5 + 0.03, sh + 0.03, 0.03), Color("#f4ecd8"))
	m.mb.quad(at + Vector3(-sw * 0.5, sh, 0.035), at + Vector3(sw * 0.5, sh, 0.035), at + Vector3(sw * 0.5, 0, 0.035), at + Vector3(-sw * 0.5, 0, 0.035), Vector3(0, 0, 1), tr, Color("#3f8fbf"))


# ================================================================== 간판
## 건물에 하나: 앞면이 2칸 이상이면 가로판(앞면 가운데 위), 1칸이면 세로 돌출 간판. 글자는 1/32 텍셀(벽의 두 배 세밀).
func _sign_main() -> void:
	if cut:
		return
	var style: String = str(rec.get("sign_style", "paint"))
	if style == "none":
		return
	var text := m.sign_of(m.state.cells.get(Vector3i(o.x, o.y, o.z), {}))
	var col := m.cfg.neon(rec.get("sign_color", "yellow"))
	var neon := style == "neon"
	var rnd := float(seed_v % 991) / 991.0
	if style == "lantern":
		for i in mini(Wf * 2, 4):
			var u := (float(i) + 0.5) * float(Wf) / float(mini(Wf * 2, 4))
			bx(u - 0.08, -0.22, u + 0.08, -0.12, 0.58, 0.78, Color("#e8443a"), Color("#f2d27a"), "white", "white", MeshBuf.K_NEON)
			bx(u - 0.01, -0.18, u + 0.01, -0.16, 0.78, 0.98, DARK, Color(-1, 0, 0), "white", "white", MeshBuf.K_PLAIN)
		light_at(float(Wf) * 0.5, -0.3, 0.65, Color("#ff6a4a"), 1.6)
	if text == "":
		return
	var big := Wf >= 2 or w * h >= 4
	var vertical := Wf < 2
	var tr := Rect2(m.atlas.sign_rect(text, vertical, big and not vertical))
	if tr.size.x <= 0.0:
		return
	var tw := tr.size.x / 32.0
	var th := tr.size.y / 32.0
	var board := _board_col(col, style)
	var tcol := col if neon else (Color("#c2463c") if board.v > 0.8 else Color("#fff6e0"))
	if style == "board":
		tcol = Color("#3b3558") if board.v > 0.8 else Color("#ffe9a8")
	var tk := MeshBuf.K_NEON if neon else MeshBuf.K_PLAIN
	if not vertical:
		# 가로 간판은 가까운 확대(인형의 집)에서 걷힌다 — 방을 가리지 않게
		if str(rec.get("form", "box")) == "box":
			m.mb.kind_add = 32.0
		var pad := 0.08
		var bw := tw + pad * 2.0
		var bh := th + pad * 1.5
		var u0 := float(Wf) * 0.5 - bw * 0.5
		var top := 0.985
		var h1 := top
		var h0 := top - bh / fh
		bx(u0, -0.1, u0 + bw, -0.02, h0, h1, board, board.lightened(0.15), "white", "white", MeshBuf.K_PLAIN)
		if neon:
			bx(u0 - 0.03, -0.11, u0 + bw + 0.03, -0.02, h1, h1 + 0.03 / fh, col, col, "white", "white", MeshBuf.K_NEON)
			bx(u0 - 0.03, -0.11, u0 + bw + 0.03, -0.02, h0 - 0.03 / fh, h0, col, col, "white", "white", MeshBuf.K_NEON)
		var tu := float(Wf) * 0.5 - tw * 0.5
		var a := P(tu, -0.104, h1 - (pad * 0.75) / fh)
		var bb := P(tu + tw, -0.104, h1 - (pad * 0.75) / fh)
		var dy := Vector3(0, -th, 0)
		m.mb.quad(a, bb, bb + dy, a + dy, -RV, tr, tcol, rnd, tk)
		m.mb.kind_add = 0.0
		if neon:
			light_at(float(Wf) * 0.5, -0.5, h0, col, 2.4)
	else:
		# 세로 돌출 간판: 앞면 오른쪽 모서리에서 앞으로 튀어나온다(양면)
		var pad2 := 0.06
		var bw2 := tw + pad2 * 2.0
		var bh2 := th + pad2 * 2.0
		var u := float(Wf) - 0.1
		var h1b := 0.98 if o.z == z else 0.98
		var h0b := h1b - bh2 / fh
		var v0 := -0.08 - bw2
		bx(u - 0.03, v0, u + 0.03, -0.08, h0b, h1b, board, board.lightened(0.15), "white", "white", MeshBuf.K_PLAIN)
		bx(u - 0.015, -0.1, u + 0.015, 0.0, h1b - 0.12, h1b - 0.06, DARK, Color(-1, 0, 0), "white", "white", MeshBuf.K_PLAIN)
		for sgn in [-1.0, 1.0]:
			var uu: float = u + sgn * 0.034
			var y1 := h1b - pad2 / fh
			var a2 := P(uu, v0 + pad2 + (tw if sgn > 0.0 else 0.0), y1)
			var b2 := P(uu, v0 + pad2 + (0.0 if sgn > 0.0 else tw), y1)
			var dy2 := Vector3(0, -th, 0)
			m.mb.quad(a2, b2, b2 + dy2, a2 + dy2, RU * sgn, tr, tcol, rnd, tk)
		if neon:
			light_at(u, v0, h0b + bh2 * 0.5 / fh, col, 1.8)
		if h0b < 0.0 and z > 0:
			pass


func _board_col(col: Color, style: String) -> Color:
	match style:
		"neon":
			var opts: Array[String] = ["#3a2a3e", "#2a3446", "#3e2a2e", "#2e3a36"]
			return Color(opts[seed_v % opts.size()])
		"board":
			return Color(["#f2d27a", "#f4ecd8", "#c2463c"][seed_v % 3])
	return Color(["#f4ecd8", "#c2463c", "#3f8f6a", "#f4ecd8", "#2e5f9a"][seed_v % 5])


# ================================================================== 지붕 소품
func _roof_props() -> void:
	if not _roof_free():
		return
	var roof: Array = rec.get("roof", []) if rec.get("roof", []) is Array else []
	if roof.is_empty():
		return
	var top := 1.0
	var i := 0
	for rp in roof:
		var u := float(Wf) * (0.28 + 0.44 * float(i % 2))
		var v := float(Df) * (0.3 + 0.4 * float((i / 2) % 2))
		match str(rp):
			"chimney", "chimney2":
				var n := 2 if str(rp) == "chimney2" else 1
				for k in n:
					var cu := u + 0.6 * float(k) - 0.15
					var hh := 1.3 if n == 2 else 0.9
					bx(cu, v, cu + 0.3, v + 0.3, top, top + hh, Color("#b06a5a"), Color("#3a3448"), "wall_brick_1" if m.atlas.has("wall_brick_1") else "white", "white", MeshBuf.K_PLAIN)
					bx(cu - 0.03, v - 0.03, cu + 0.33, v + 0.33, top + hh * 0.8, top + hh * 0.85, Color("#e9e0cc"), Color(-1, 0, 0), "white", "white", MeshBuf.K_PLAIN)
					emit_at(cu + 0.15, v + 0.15, top + hh + 0.1, str(rec.get("fx", "smoke")) if str(rec.get("fx", "")) in ["smoke", "steam"] else "smoke")
			"tanks":
				m._roof_tank(P(u - 0.5, v - 0.5, top), seed_v + i)
			"ac":
				bx(u - 0.18, v - 0.12, u + 0.18, v + 0.12, top, top + 0.26, Color("#e8e4d8"), Color("#f8f4e8"), "ac", "white", MeshBuf.K_PLAIN)
			"vent":
				bx(u - 0.2, v - 0.2, u + 0.2, v + 0.2, top, top + 0.2, STEEL, STEEL_T, "white", "white", MeshBuf.K_PLAIN)
				bx(u - 0.12, v - 0.12, u + 0.12, v + 0.12, top + 0.2, top + 0.32, Color("#6a6486"), Color("#3a3448"), "white", "white", MeshBuf.K_PLAIN)
			"antenna":
				m._antennas(P(u - 0.5, v - 0.5, top), seed_v + i, 2)
			"dish":
				m._dish(P(u, v, top))
			"mast":
				m._mast(P(u, v, top), seed_v, active)
			"racks":
				m._racks(P(u - 0.5, v - 0.5, top), seed_v)
			"junk":
				m._roof_junk(P(u - 0.5, v - 0.5, top), seed_v)
			"laundry":
				m._roof_laundry(P(u - 0.5, v - 0.5, top), seed_v)
			"lanterns":
				for k in 3:
					bx(u - 0.4 + 0.4 * float(k), v, u - 0.3 + 0.4 * float(k), v + 0.1, top + 0.3, top + 0.45, Color("#e8443a"), Color("#f2d27a"), "white", "white", MeshBuf.K_NEON)
			"bell":
				bx(u - 0.04, v - 0.04, u + 0.04, v + 0.04, top, top + 0.7, Color("#7a5a4a"), Color(-1, 0, 0), "white", "white", MeshBuf.K_PLAIN)
				bx(u - 0.3, v - 0.04, u + 0.3, v + 0.04, top + 0.7, top + 0.76, Color("#7a5a4a"), Color(-1, 0, 0), "white", "white", MeshBuf.K_PLAIN)
				bx(u - 0.1, v - 0.1, u + 0.1, v + 0.1, top + 0.42, top + 0.66, Color("#d0a040"), Color("#f2d27a"), "white", "white", MeshBuf.K_PLAIN)
			"siren":
				bx(u - 0.1, v - 0.1, u + 0.1, v + 0.1, top, top + 0.22, Color("#d84a3a"), Color("#ff6a4a"), "white", "white", MeshBuf.K_NEON)
				light_at(u, v, top + 0.3, Color("#ff3a2a"), 1.2)
			"neon_roof":
				_roof_neon(top)
			"hall":
				m._hall_roof(Vector3i(o.x, o.y, z), m.cellv(Vector3i(o.x, o.y, z + 1)), F, seed_v, float(w), float(h))
		i += 1


## 옥상 네온 틀(지붕 위 간판대 + 글자)
func _roof_neon(top: float) -> void:
	var text := m.sign_of(m.state.cells.get(Vector3i(o.x, o.y, o.z), {}))
	if text == "":
		return
	var tr := Rect2(m.atlas.sign_rect(text, false, true))
	if tr.size.x <= 0.0:
		return
	# 글자 텍셀 1/16(크게)이 지붕보다 넓으면 1/32
	var sc := 16.0 if tr.size.x / 16.0 <= float(Wf) - 0.3 else 32.0
	var tw := tr.size.x / sc
	var th := tr.size.y / sc
	var col := m.cfg.neon(rec.get("glow", rec.get("sign_color", "magenta")))
	var u0 := float(Wf) * 0.5 - tw * 0.5
	var v := 0.35
	for uu in [u0 + 0.1, u0 + tw - 0.14]:
		bx(uu, v, uu + 0.04, v + 0.04, top, top + 0.25 + th / fh, DARK, Color(-1, 0, 0), "white", "white", MeshBuf.K_PLAIN)
	var hb := top + 0.25
	var a := P(u0, v - 0.01, hb + th / fh)
	var b := P(u0 + tw, v - 0.01, hb + th / fh)
	var dy := Vector3(0, -th, 0)
	m.mb.quad(a, b, b + dy, a + dy, -RV, tr, col, float(seed_v % 97) / 97.0, MeshBuf.K_NEON)
	m.mb.quad(b, a, a + dy, b + dy, RV, Rect2(tr.position + Vector2(tr.size.x, 0), Vector2(-tr.size.x, tr.size.y)), col, float(seed_v % 97) / 97.0, MeshBuf.K_NEON)
	light_at(float(Wf) * 0.5, v, hb, col, 2.6)


func _exterior_fx() -> void:
	if cut or not active:
		return
	var fx: String = str(rec.get("fx", ""))
	match fx:
		"steam":
			emit_at(float(Wf) * 0.75, -0.1, 0.9, "steam")
		"sparks":
			emit_at(float(Wf) * 0.4, 0.3, 0.3, "sparks")
		"drip":
			emit_at(0.2, -0.05, 0.4, "drip")
		"smoke_thin":
			emit_at(float(Wf) * 0.5, float(Df) * 0.5, 0.6, "incense")


# ================================================================== 소품 도서관(지역 좌표)
func table(u: float, v: float, su: float, sv: float, ht: float = 0.26, col: Color = WOOD, topc: Color = WOOD_T, top_t: String = "white") -> void:
	bx(u - su * 0.5, v - sv * 0.5, u + su * 0.5, v + sv * 0.5, ht - 0.05, ht, col, topc if top_t == "white" else MeshBuf.WHITE, "white", top_t)
	bx(u - 0.04, v - 0.04, u + 0.04, v + 0.04, 0.0, ht - 0.05, col.darkened(0.3))


func stool(u: float, v: float, col: Color = Color("#c2604f")) -> void:
	bx(u - 0.05, v - 0.05, u + 0.05, v + 0.05, 0.0, 0.13, col.darkened(0.2), col)


## 바라보는 쪽(face)의 반대편 = 등 쪽 지역 방향
func back_of(face: String) -> Vector2:
	match face:
		"f":
			return Vector2(0, 1)
		"b":
			return Vector2(0, -1)
		"l":
			return Vector2(1, 0)
		"r":
			return Vector2(-1, 0)
	return Vector2(0, 1)


func chair(u: float, v: float, face: String, col: Color = Color("#5f86c4")) -> void:
	bx(u - 0.07, v - 0.07, u + 0.07, v + 0.07, 0.0, 0.14, col.darkened(0.2), col)
	var bk := back_of(face)
	if bk.y != 0.0:
		bx(u - 0.07, v + bk.y * 0.055 - 0.015, u + 0.07, v + bk.y * 0.055 + 0.015, 0.14, 0.34, col.darkened(0.3))
	else:
		bx(u + bk.x * 0.055 - 0.015, v - 0.07, u + bk.x * 0.055 + 0.015, v + 0.07, 0.14, 0.34, col.darkened(0.3))


func counter(u0: float, v0: float, u1: float, v1: float, col: Color = WOOD, topc: Color = WOOD_T, ht: float = 0.36) -> void:
	bx(u0, v0, u1, v1, 0.0, ht, col, topc)


func shelf_back(u0: float, u1: float, v: float, ht: float = 0.8, t: String = "shelf") -> void:
	bx(u0, v - 0.14, u1, v, 0.0, ht, MeshBuf.WHITE, Color("#7a5848"), t, "white")


func crate(u: float, v: float, s: float = 0.22, stack: bool = false) -> void:
	bx(u - s * 0.5, v - s * 0.5, u + s * 0.5, v + s * 0.5, 0.0, s * 1.1, MeshBuf.WHITE, Color(-1, 0, 0), "crate", "crate")
	if stack:
		bx(u - s * 0.4, v - s * 0.4, u + s * 0.38, v + s * 0.38, s * 1.1, s * 2.0, MeshBuf.WHITE, Color(-1, 0, 0), "crate", "crate")


func drum(u: float, v: float, col: Color = Color("#4f7aa8")) -> void:
	bx(u - 0.09, v - 0.09, u + 0.09, v + 0.09, 0.0, 0.32, col, col.darkened(0.45))
	bx(u - 0.095, v - 0.095, u + 0.095, v + 0.095, 0.14, 0.17, col.lightened(0.2))


func sack(u: float, v: float, col: Color = Color("#c9b48a")) -> void:
	bx(u - 0.1, v - 0.08, u + 0.1, v + 0.08, 0.0, 0.16, col, col.lightened(0.1))
	bx(u - 0.04, v - 0.03, u + 0.04, v + 0.03, 0.16, 0.22, col.darkened(0.15))


func pot(u: float, v: float, steam: bool = true) -> void:
	bx(u - 0.1, v - 0.1, u + 0.1, v + 0.1, 0.0, 0.22, Color("#5a5674"), Color(-1, 0, 0), "white", "stove")
	bx(u - 0.08, v - 0.08, u + 0.08, v + 0.08, 0.22, 0.36, Color("#b9bcc8"), Color("#f4ead2"))
	if steam:
		emit_at(u, v, 0.45, "steam")


func vat(u: float, v: float, r: float = 0.16, ht: float = 0.5) -> void:
	bx(u - r, v - r, u + r, v + r, 0.0, ht, MeshBuf.WHITE, MeshBuf.WHITE, "steel_side", "vat")
	bx(u - r - 0.01, v - r - 0.01, u + r + 0.01, v + r + 0.01, ht * 0.5, ht * 0.5 + 0.04, Color("#7a7e94"))
	emit_at(u, v, ht + 0.1, "bubble")


func machine(u: float, v: float, su: float = 0.3, sv: float = 0.24, ht: float = 0.42) -> void:
	bx(u - su * 0.5, v - sv * 0.5, u + su * 0.5, v + sv * 0.5, 0.0, ht, MeshBuf.WHITE, MeshBuf.WHITE, "machine", "machine")


func bed(u: float, v: float, along_v: bool = true, t: String = "bed") -> void:
	var su := 0.26 if along_v else 0.5
	var sv := 0.5 if along_v else 0.26
	bx(u - su * 0.5, v - sv * 0.5, u + su * 0.5, v + sv * 0.5, 0.0, 0.16, Color("#8a6a5a"), MeshBuf.WHITE, "white", t)


func lamp(u: float, v: float, hf: float = 0.95, col: Color = Color("#fff2c8")) -> void:
	bx(u - 0.005, v - 0.005, u + 0.005, v + 0.005, hf, 1.0, DARK)
	bx(u - 0.05, v - 0.05, u + 0.05, v + 0.05, hf - 0.06, hf, col, col, "white", "white", MeshBuf.K_NEON)


func plant(u: float, v: float) -> void:
	bx(u - 0.06, v - 0.06, u + 0.06, v + 0.06, 0.0, 0.12, Color("#c0714f"), Color("#5a3a2e"))
	bx(u - 0.1, v - 0.1, u + 0.1, v + 0.1, 0.12, 0.32, Color("#4f9a5a"), Color("#6fc07a"))


func hang_row(u0: float, u1: float, v: float, h1: float, colors: Array, len_hf: float = 0.25, step: float = 0.09) -> void:
	bx(u0, v - 0.015, u1, v + 0.015, h1, h1 + 0.03, Color("#6a5a4a"))
	var u := u0 + 0.04
	var i := 0
	while u < u1 - 0.03:
		var cc := Color(colors[(i + seed_v) % colors.size()])
		m.mb.cloth(P(u, v, h1), P(u + step * 0.6, v, h1), P(u + step * 0.6, v, h1 - len_hf), P(u, v, h1 - len_hf), -RV, m.sub(m.tile("white"), 0, 0, 2, 4), cc, float((i * 17 + seed_v) % 100) / 100.0)
		u += step
		i += 1


func junk(u: float, v: float, s: float = 0.3) -> void:
	bx(u - s * 0.5, v - s * 0.4, u + s * 0.5, v + s * 0.4, 0.0, s * 0.45, MeshBuf.WHITE, MeshBuf.WHITE, "crate", "junk")
	bx(u - s * 0.3, v - s * 0.2, u + s * 0.2, v + s * 0.3, s * 0.45, s * 0.8, Color("#8a96aa"), Color("#a9b4c4"))


func mat_goods(u: float, v: float, su: float, sv: float, n: int = 6) -> void:
	bx(u - su * 0.5, v - sv * 0.5, u + su * 0.5, v + sv * 0.5, 0.0, 0.02, Color("#cdbf7c"), MeshBuf.WHITE, "white", "mat")
	for i in n:
		var gu := u - su * 0.4 + su * 0.8 * _rnd()
		var gv := v - sv * 0.35 + sv * 0.7 * _rnd()
		var gc := Color(GOODS[_ri(GOODS.size())])
		bx(gu - 0.04, gv - 0.035, gu + 0.04, gv + 0.035, 0.02, 0.06 + 0.05 * _rnd(), gc.darkened(0.15), gc)


func umbrella(u: float, v: float, col: Color) -> void:
	bx(u - 0.01, v - 0.01, u + 0.01, v + 0.01, 0.0, 0.7, DARK)
	bx(u - 0.3, v - 0.3, u + 0.3, v + 0.3, 0.68, 0.74, col.darkened(0.15), col)
	bx(u - 0.18, v - 0.18, u + 0.18, v + 0.18, 0.74, 0.79, col.lightened(0.1), col.lightened(0.15))


func sofa(u0: float, v0: float, u1: float, v1: float, col: Color, face: String = "f") -> void:
	bx(u0, v0, u1, v1, 0.0, 0.15, col.darkened(0.15), col)
	var bk := back_of(face)
	if bk.y > 0.0:
		bx(u0, v1 - 0.06, u1, v1, 0.15, 0.34, col.darkened(0.25))
	elif bk.y < 0.0:
		bx(u0, v0, u1, v0 + 0.06, 0.15, 0.34, col.darkened(0.25))
	elif bk.x > 0.0:
		bx(u1 - 0.06, v0, u1, v1, 0.15, 0.34, col.darkened(0.25))
	else:
		bx(u0, v0, u0 + 0.06, v1, 0.15, 0.34, col.darkened(0.25))


func screen(u0: float, u1: float, v: float, h0: float, h1: float) -> void:
	bx(u0 - 0.02, v - 0.04, u1 + 0.02, v, h0 - 0.02, h1 + 0.02, DARK)
	vq(u0, u1, v - 0.045, h0, h1, "tv", MeshBuf.WHITE)


func tub(u0: float, v0: float, u1: float, v1: float) -> void:
	bx(u0, v0, u1, v1, 0.0, 0.18, Color("#e6e2d6"), Color("#f4f0ea"))
	bx(u0 + 0.05, v0 + 0.05, u1 - 0.05, v1 - 0.05, 0.18, 0.185, MeshBuf.WHITE, MeshBuf.WHITE, "white", "water")


func cage(u: float, v: float, s: float = 0.22, hf: float = 0.0) -> void:
	bx(u - s * 0.5, v - s * 0.5, u + s * 0.5, v + s * 0.5, hf, hf + s * 1.2, MeshBuf.WHITE, MeshBuf.WHITE, "bunk", "bunk")


func plant_rows(u0: float, v0: float, u1: float, v1: float) -> void:
	var v := v0 + 0.1
	var k := 0
	while v < v1 - 0.05:
		bx(u0 + 0.05, v, u1 - 0.05, v + 0.14, 0.0, 0.08, Color("#8a6650"), Color("#7a5848"))
		var u := u0 + 0.1
		while u < u1 - 0.1:
			var gc := Color(["#5fae5a", "#7fc06a", "#9ad06a", "#d8c050"][(k + int(u * 7.0)) % 4])
			bx(u - 0.04, v + 0.02, u + 0.04, v + 0.12, 0.08, 0.16 + 0.06 * _rnd(), gc.darkened(0.2), gc)
			u += 0.13
		v += 0.24
		k += 1


const REPEATERS := ["assembly", "power_plant", "power_waste", "water_plant", "scrapyard", "trash_guild", "soap", "brewery", "rag_collect", "fireworks",
	"callcenter", "gambling", "market_hall", "clinic", "tailor", "food_pilgrims", "fake", "candle", "rat_farm"]


## 큰 방의 대표 칸: 반장 책상(장부·전화·주전자)·달력·의자 + 장부 쓰는 반장
func _foreman_corner(cc: Vector2i) -> void:
	var u := float(cc.x) + 0.5
	var v := float(cc.y) + 0.5
	bx(u - 0.3, v - 0.05, u + 0.25, v + 0.2, 0.0, 0.28, WOOD, MeshBuf.WHITE, "white", "desk")
	bx(u + 0.1, v, u + 0.2, v + 0.08, 0.28, 0.36, Color("#3a3448"))
	bx(u - 0.25, v + 0.02, u - 0.15, v + 0.12, 0.28, 0.4, Color("#b9bcc8"), Color("#5a5674"))
	emit_at(u - 0.2, v + 0.07, 0.45, "steam")
	chair(u - 0.02, v - 0.22, "b", Color("#7a5a4a"))
	slot(u - 0.02, v - 0.22, "work", "b", "staff", 0.0, {"anim": "write"})
	bx(u + 0.3, v - 0.3, u + 0.42, v - 0.18, 0.0, 0.5, Color("#6a7a96"), Color("#8a9ab6"))


## 큰 방의 쌓아 둔 칸: 상자·자루·통 더미 + 나르는 사람
func _storage_corner(cc: Vector2i) -> void:
	var u := float(cc.x) + 0.5
	var v := float(cc.y) + 0.5
	crate(u - 0.25, v - 0.2, 0.26, true)
	crate(u + 0.05, v - 0.22, 0.22)
	sack(u + 0.25, v + 0.2)
	sack(u + 0.05, v + 0.28, Color("#e6dcc4"))
	drum(u - 0.28, v + 0.25, Color("#5f86c4"))
	slot(u + 0.1, v + 0.05, "carry", "l", "staff")


# ================================================================== 안 모양(look마다)
## 칸 순회: 지역 칸 (iu, iv). 앞줄 iv = 0.
func _interior() -> void:
	var cells: Array = []
	for iv in Df:
		for iu in Wf:
			if slice.has(cell_at(iu, iv)):
				cells.append(Vector2i(iu, iv))
	var top := zi == d - 1
	var upper := zi > 0
	var lk := look
	# 큰 방(4칸 이상)은 칸마다 같은 배치를 되풀이하지 않게: 대표 칸 하나는 반장 자리(책상·달력·주전자), 하나는 쌓아 둔 곳
	var special: Array = []
	if cells.size() >= 4 and lk in REPEATERS:
		var hsel := ViewCfg.h2(seed_v, z)
		var fcell: Vector2i = cells[hsel % cells.size()]
		var scell: Vector2i = cells[(hsel / 7 + 1 + cells.find(fcell)) % cells.size()]
		if scell == fcell:
			scell = cells[(cells.find(fcell) + 1) % cells.size()]
		cells.erase(fcell)
		cells.erase(scell)
		special = [fcell, scell]
	if upper and lk in ["market_mall", "casino", "landmark_generic"]:
		lk = lk + "_up"
	match lk:
		# ── 시장 ──
		"market_mat":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				mat_goods(u, v - 0.12, 0.7, 0.4, 7)
				if (cc.x + cc.y) % 2 == 0:
					umbrella(u + 0.28, v + 0.15, Color(CLOTH[(cc.x + cc.y + seed_v) % CLOTH.size()]))
				slot(u, v + 0.18, "squat", "f", "staff")
				slot(u - 0.2, v - 0.5, "stand", "b", "guest")
		"market_alley":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y)
				counter(u - 0.4, v + 0.18, u + 0.4, v + 0.4, WOOD, WOOD_T, 0.3)
				for k in 4:
					var gc := Color(GOODS[(k + cc.x + seed_v) % GOODS.size()])
					bx(u - 0.36 + 0.19 * float(k), v + 0.22, u - 0.22 + 0.19 * float(k), v + 0.36, 0.3, 0.36, gc.darkened(0.1), gc)
				crate(u - 0.3, v + 0.75, 0.2, true)
				sack(u + 0.25, v + 0.78)
				lamp(u, v + 0.3, 0.8, Color("#ffd88a"))
				slot(u, v + 0.6, "swork", "f", "staff")
				slot(u + 0.1, v - 0.12, "stand", "b", "guest")
		"market_hall":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				counter(u - 0.38, v - 0.22, u + 0.38, v + 0.02, Color("#9a9aa6"), Color("#d6d8de"), 0.32)
				if (cc.x + cc.y) % 2 == 0:
					bx(u - 0.3, v - 0.2, u + 0.3, v, 0.32, 0.35, MeshBuf.WHITE, MeshBuf.WHITE, "white", "water_fish")
				else:
					hang_row(u - 0.35, u + 0.35, v + 0.05, 0.85, ["#d85f5f", "#c0504a", "#e07a6a"], 0.22, 0.12)
					for k in 3:
						bx(u - 0.3 + 0.2 * float(k), v - 0.18, u - 0.16 + 0.2 * float(k), v - 0.06, 0.32, 0.38, Color("#d85f5f"), Color("#e6857a"))
				lamp(u, v - 0.1, 0.9)
				slot(u, v + 0.22, "swork", "f", "staff")
				slot(u - 0.2, v - 0.42, "stand", "b", "guest")
				slot(u + 0.25, v - 0.48, "carry", "l", "guest")
		"market_mall":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				if cc.y == Df - 1:
					shelf_back(u - 0.45, u + 0.45, v + 0.48, 0.85)
				else:
					bx(u - 0.12, v - 0.12, u + 0.12, v + 0.12, 0.0, 0.3, Color("#eef0ea"), Color("#ffffff"))
					bx(u - 0.05, v - 0.05, u + 0.05, v + 0.05, 0.3, 0.66, Color("#e8a0b8"))
					bx(u - 0.04, v - 0.04, u + 0.04, v + 0.04, 0.66, 0.78, Color("#f2c9a2"))
				lamp(u, v, 0.92, Color("#e0f4ff"))
				slot(u + 0.25, v - 0.1, "stand", "l", "guest")
			slot(0.4, 0.3, "stand", "f", "staff")
		"market_mall_up", "casino_up", "landmark_generic_up":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				if look == "casino":
					bx(u - 0.25, v - 0.15, u + 0.25, v + 0.15, 0.0, 0.26, Color("#2e6a4a"), MeshBuf.WHITE, "white", "mj_table")
					slot(u, v + 0.3, "sit", "b", "guest")
					slot(u, v - 0.3, "swork", "f", "staff")
				elif look == "market_mall":
					shelf_back(u - 0.4, u + 0.4, v + 0.45, 0.8)
					hang_row(u - 0.35, u + 0.35, v - 0.1, 0.8, CLOTH, 0.35, 0.1)
					slot(u, v + 0.15, "stand", "b", "guest")
				else:
					bx(u - 0.2, v - 0.2, u + 0.2, v + 0.2, 0.0, 0.4, Color("#b07bff"), Color("#d0a8ff"), "white", "white", MeshBuf.K_NEON)
					slot(u + 0.35, v, "stand", "l", "guest")
				lamp(u, v, 0.92, Color("#ffd88a"))
		# ── 물·전기 ──
		"water_catcher":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				# 방수포 깔때기(네 귀가 높은 천) + 물통
				var tc := Color("#5f86c4")
				m.mb.quad2(P(u - 0.42, v - 0.42, 0.75), P(u + 0.42, v - 0.42, 0.75), P(u + 0.06, v - 0.06, 0.35), P(u - 0.06, v - 0.06, 0.35), Vector3.UP, m.sub(m.tile("white"), 0, 0, 2, 2), tc)
				m.mb.quad2(P(u + 0.42, v - 0.42, 0.75), P(u + 0.42, v + 0.42, 0.75), P(u + 0.06, v + 0.06, 0.35), P(u + 0.06, v - 0.06, 0.35), Vector3.UP, m.sub(m.tile("white"), 0, 0, 2, 2), tc.darkened(0.1))
				m.mb.quad2(P(u + 0.42, v + 0.42, 0.75), P(u - 0.42, v + 0.42, 0.75), P(u - 0.06, v + 0.06, 0.35), P(u + 0.06, v + 0.06, 0.35), Vector3.UP, m.sub(m.tile("white"), 0, 0, 2, 2), tc.lightened(0.1))
				m.mb.quad2(P(u - 0.42, v + 0.42, 0.75), P(u - 0.42, v - 0.42, 0.75), P(u - 0.06, v - 0.06, 0.35), P(u - 0.06, v + 0.06, 0.35), Vector3.UP, m.sub(m.tile("white"), 0, 0, 2, 2), tc.darkened(0.2))
				for k in 4:
					var a := Vector2([-0.42, 0.42, 0.42, -0.42][k], [-0.42, -0.42, 0.42, 0.42][k])
					bx(u + a.x - 0.02, v + a.y - 0.02, u + a.x + 0.02, v + a.y + 0.02, 0.0, 0.76, Color("#8a7a6a"))
				drum(u, v, Color("#4f7aa8"))
				drum(u + 0.3, v + 0.32, Color("#5fa6c8"))
				emit_at(u, v, 0.34, "drip")
			slot(float(Wf) - 0.1, float(Df) - 0.15, "swork", "l", "idle")
		"water_pipe":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				bx(u - 0.45, v + 0.1, u + 0.45, v + 0.2, 0.2, 0.3, Color("#8fb5d0"), Color("#a9cbea"))
				bx(u - 0.45, v + 0.28, u + 0.45, v + 0.38, 0.45, 0.55, Color("#b5654f"), Color("#d08060"))
				bx(u - 0.08, v - 0.1, u + 0.08, v + 0.1, 0.0, 0.5, Color("#6a7a96"), Color("#8a9ab6"))
				bx(u - 0.14, v - 0.02, u + 0.14, v + 0.02, 0.5, 0.54, Color("#c2463c"))
				slot(u + 0.2, v - 0.25, "swork", "b", "staff")
		"water_plant":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				vat(u, v, 0.3, 0.55)
				bx(u - 0.45, v + 0.38, u + 0.45, v + 0.45, 0.3, 0.38, Color("#8fb5d0"))
			slot(0.5, 0.15, "swork", "b", "staff")
			slot(float(Wf) - 0.5, float(Df) - 0.2, "stand", "f", "staff")
		"gen_small":
			var gu := float(Wf) * 0.5
			bx(gu - 0.28, 0.25, gu + 0.28, 0.65, 0.0, 0.38, Color("#c9a04a"), MeshBuf.WHITE, "white", "machine", MeshBuf.K_SHAKE)
			bx(gu - 0.08, 0.35, gu + 0.08, 0.5, 0.38, 0.5, Color("#5a5674"), Color(-1, 0, 0), "white", "white", MeshBuf.K_SHAKE)
			drum(gu + 0.35, 0.7, Color("#c2463c"))
			drum(gu - 0.38, 0.75, Color("#c2463c"))
			emit_at(gu, 0.42, 0.6, "smoke")
			light_at(gu, 0.2, 0.5, m.cfg.neon("yellow"), 1.0)
			slot(gu - 0.3, 0.15, "squat", "r", "staff")
		"power_plant", "power_waste":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				if look == "power_waste" and cc.y == Df - 1:
					bx(u - 0.4, v - 0.3, u + 0.4, v + 0.4, 0.0, 0.7, Color("#6a5a5a"), Color("#3a3448"), "wall_brick_1" if m.atlas.has("wall_brick_1") else "white")
					vq(u - 0.2, u + 0.2, v - 0.31, 0.05, 0.3, "emit", Color("#ff8a3d"))
					light_at(u, v - 0.5, 0.2, Color("#ff7a2a"), 1.8)
					emit_at(u, v - 0.4, 0.3, "sparks")
				else:
					bx(u - 0.32, v - 0.2, u + 0.32, v + 0.25, 0.0, 0.48, MeshBuf.WHITE, MeshBuf.WHITE, "machine", "machine", MeshBuf.K_SHAKE if active else KI)
					bx(u - 0.1, v - 0.32, u + 0.1, v - 0.2, 0.1, 0.3, Color("#e6b45a"))
				lamp(u, v - 0.3, 0.92, Color("#fff2a8"))
			slot(0.4, 0.2, "swork", "b", "staff")
			slot(float(Wf) - 0.4, 0.3, "carry", "l", "staff")
			slot(float(Wf) * 0.5, float(Df) - 0.3, "swork", "f", "staff")
		# ── 먹을 것 ──
		"food_cans":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y)
				if cc.y == Df - 1:
					shelf_back(u - 0.46, u + 0.46, v + 0.95, 0.85, "cans" if m.atlas.has("cans") else "shelf")
				if cc.y == 0:
					counter(u - 0.42, v + 0.2, u + 0.42, v + 0.38, Color("#8a7a6a"), Color("#a89a8a"), 0.32)
					for k in 5:
						bx(u - 0.38 + 0.16 * float(k), v + 0.24, u - 0.28 + 0.16 * float(k), v + 0.34, 0.32, 0.42, Color("#b9bcc8"), Color("#e6b45a"))
			crate(0.25, float(Df) - 0.6, 0.24, true)
			slot(float(Wf) * 0.5, 0.6, "swork", "f", "staff")
			slot(float(Wf) * 0.5 - 0.3, -0.1, "stand", "b", "guest")
			slot(float(Wf) * 0.5 + 0.35, -0.15, "carry", "b", "guest")
		"food_pilgrims":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				table(u, v, 0.6, 0.36, 0.26, WOOD, WOOD_T)
				for k in 4:
					sack(u - 0.22 + 0.15 * float(k), v + 0.32, Color(["#c9b48a", "#e6dcc4", "#b0a468"][k % 3]))
				bx(u - 0.25, v - 0.12, u - 0.1, v, 0.26, 0.34, Color("#f4ead2"))
				bx(u + 0.05, v - 0.1, u + 0.22, v + 0.05, 0.26, 0.31, Color("#e8443a"))
				slot(u - 0.1, v - 0.3, "swork", "b", "staff")
			slot(0.3, -0.2, "carry", "b", "guest")
		"noodle_mill":
			var mu := float(Wf) * 0.5
			machine(0.4, 0.5, 0.36, 0.3, 0.45)
			bx(0.6, 0.4, 0.95, 0.6, 0.3, 0.33, MeshBuf.WHITE, MeshBuf.WHITE, "white", "noodles")
			for cc in cells:
				if cc.y > 0 or Wf > 1:
					hang_row(float(cc.x) + 0.1, float(cc.x) + 0.9, float(cc.y) + 0.75, 0.8, ["#f6e7b0", "#f2dc98", "#fff0c0"], 0.35, 0.06)
			sack(mu + 0.3, float(Df) - 0.2, Color("#f4ead2"))
			sack(mu + 0.5, float(Df) - 0.25, Color("#f4ead2"))
			slot(0.45, 0.85, "swork", "f", "staff")
			slot(mu + 0.4, 0.4, "swork", "l", "staff")
		"noodle_stall":
			var nu := float(Wf) * 0.5
			counter(0.1, 0.12, float(Wf) - 0.1, 0.32, Color("#c2604f"), Color("#e6dcc4"), 0.34)
			pot(0.35, 0.55)
			pot(0.75, 0.55)
			bx(1.05, 0.45, 1.4, 0.7, 0.0, 0.3, Color("#8f8ea6"), MeshBuf.WHITE, "white", "noodles")
			for k in mini(Wf * 2, 4):
				stool(0.3 + 0.45 * float(k), -0.12, Color(["#c2604f", "#5f86c4", "#e0a23c"][k % 3]))
			lamp(nu, 0.4, 0.82, Color("#ffd88a"))
			slot(0.55, 0.72, "swork", "f", "staff")
			for k in mini(Wf * 2, 4):
				slot(0.3 + 0.45 * float(k), -0.12, "sit_eat", "b", "guest")
		"rat_farm":
			# 쥐덫 조합: 벽을 따라 쌓은 철망 우리(쥐가 보인다) + 먹이 통 + 덫 고치는 작업대 + 말리는 덫 줄
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y)
				if cc.y == Df - 1:
					for k in 3:
						cage(u - 0.3 + 0.3 * float(k), v + 0.82, 0.24)
						cage(u - 0.3 + 0.3 * float(k), v + 0.82, 0.22, 0.32)
						for r in 2:
							bx(u - 0.33 + 0.3 * float(k) + 0.06 * float(r), v + 0.78, u - 0.29 + 0.3 * float(k) + 0.06 * float(r), v + 0.84, 0.02 + 0.32 * float(r), 0.06 + 0.32 * float(r), Color("#4a3a3a"))
				else:
					bx(u - 0.35, v + 0.35, u + 0.05, v + 0.55, 0.0, 0.26, WOOD, WOOD_T)
					for k in 3:
						bx(u - 0.3 + 0.1 * float(k), v + 0.4, u - 0.24 + 0.1 * float(k), v + 0.5, 0.26, 0.29, Color("#8a96aa"))
					bx(u + 0.15, v + 0.3, u + 0.42, v + 0.45, 0.0, 0.08, Color("#7a6a5a"), Color("#c9b48a"))
			hang_row(0.1, float(Wf) - 0.1, 0.25, 0.85, ["#8a96aa", "#6a7488", "#a0a8b8"], 0.15, 0.12)
			slot(0.35, 0.72, "swork", "b", "staff", 0.0, {"anim": "hammer"})
			slot(float(Wf) - 0.35, float(Df) - 0.45, "squat", "b", "staff")
			slot(float(Wf) * 0.5, 0.15, "carry", "l", "staff", 0.0, {"prop": "sack"})
		"burger":
			counter(0.1, 0.2, float(Wf) - 0.1, 0.38, Color("#d85f5f"), Color("#f4ead2"), 0.34)
			bx(0.15, 0.6, 0.6, 0.85, 0.0, 0.32, Color("#5a5674"), MeshBuf.WHITE, "white", "stove")
			bx(0.7, 0.62, 0.95, 0.85, 0.0, 0.38, Color("#b9bcc8"), Color("#e6b45a"))
			emit_at(0.38, 0.72, 0.45, "smoke")
			screen(0.2, 0.8, float(Df) - 0.02, 0.62, 0.82)
			if Wf >= 2:
				table(1.5, 1.0, 0.3, 0.3)
				stool(1.3, 1.0)
				stool(1.7, 1.0)
				slot(1.3, 1.0, "sit_eat", "r", "guest")
				slot(1.7, 1.0, "sit_eat", "l", "guest")
			slot(0.45, 0.52, "swork", "b", "staff")
			slot(0.9, 0.45, "swork", "f", "staff")
			slot(0.6, -0.05, "stand", "b", "guest")
		"sushi":
			counter(0.15, 0.55, float(Wf) - 0.15, 0.78, WOOD, Color("#f0e0c0"), 0.34)
			for k in Wf * 3:
				var uu := 0.3 + 0.3 * float(k)
				if uu > float(Wf) - 0.2:
					break
				bx(uu - 0.05, 0.6, uu + 0.05, 0.7, 0.34, 0.38, Color(["#ff8a6a", "#f4f0e6", "#e8443a"][k % 3]), Color(["#ff9a7a", "#ffffff", "#ff6a5a"][k % 3]))
				stool(uu, 0.4, Color("#3e4a7a"))
				slot(uu, 0.4, "sit_eat", "b", "guest")
			bx(0.2, float(Df) - 0.3, float(Wf) - 0.2, float(Df) - 0.05, 0.0, 0.3, Color("#b9bcc8"), MeshBuf.WHITE, "white", "water_fish")
			lamp(float(Wf) * 0.3, 0.65, 0.9)
			lamp(float(Wf) * 0.7, 0.65, 0.9)
			slot(float(Wf) * 0.5, 0.95, "swork", "f", "staff")
			slot(float(Wf) * 0.5 - 0.6, 1.0, "swork", "f", "staff")
		"roof_garden":
			plant_rows(0.0, 0.0, float(Wf), float(Df))
			drum(float(Wf) - 0.2, 0.15, Color("#5fa6c8"))
			slot(float(Wf) * 0.5, 0.45, "squat", "f", "staff")
			slot(0.3, float(Df) - 0.3, "swork", "r", "staff", 0.0, {"prop": "can"})
		"brewery":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				vat(u - 0.15, v + 0.05, 0.22, 0.52)
				for k in 3:
					bx(u + 0.25, v - 0.35 + 0.22 * float(k), u + 0.4, v - 0.2 + 0.22 * float(k), 0.0, 0.2, Color("#8a5a3e"), Color("#3a2a2e"))
			slot(0.55, 0.3, "swork", "b", "staff", 0.0, {"prop": "stir"})
			slot(float(Wf) - 0.3, float(Df) - 0.3, "carry", "f", "staff")
		# ── 생활 ──
		"oil_collect":
			# 폐식용유 수거: 깔때기 꽂은 드럼 + 기름통 줄 + 바닥 기름 얼룩 + 붓는 사람
			drum(0.3, 0.45, Color("#3a3448"))
			bx(0.22, 0.37, 0.38, 0.53, 0.32, 0.4, Color("#8a8a96"), Color("#2a2430"))
			bx(0.27, 0.42, 0.33, 0.48, 0.4, 0.5, Color("#8a8a96"))
			for k in 4:
				bx(0.55 + 0.1 * float(k % 2), 0.15 + 0.12 * float(k), 0.63 + 0.1 * float(k % 2), 0.24 + 0.12 * float(k), 0.0, 0.16, Color(["#e0a23c", "#c9a04a", "#d8823a"][k % 3]), Color("#3a3448"))
			drum(0.42, 0.78, Color("#5a4a3a"))
			bx(0.1, 0.6, 0.35, 0.8, 0.0, 0.004, Color("#2e2a24"))
			emit_at(0.3, 0.45, 0.55, "drip")
			slot(0.3, 0.2, "swork", "b", "staff", 0.0, {"anim": "pour"})
			slot(0.75, 0.7, "carry", "l", "staff")
		"candle":
			counter(0.1, 0.2, float(Wf) - 0.1, 0.36, WOOD, WOOD_T, 0.32)
			for k in 6:
				bx(0.2 + 0.13 * float(k), 0.24, 0.26 + 0.13 * float(k), 0.3, 0.32, 0.44, Color("#f4ecd8"), Color("#ffd84a"), "white", "white", MeshBuf.K_NEON)
			pot(0.4, 0.75, false)
			for cc in cells:
				hang_row(float(cc.x) + 0.15, float(cc.x) + 0.85, float(cc.y) + 0.6, 0.85, ["#f4ecd8", "#f2d27a", "#e8a0b8"], 0.2, 0.07)
			light_at(0.5, 0.4, 0.5, Color("#ffb04a"), 1.4)
			slot(0.45, 0.55, "swork", "f", "staff")
			slot(0.6, -0.08, "stand", "b", "guest")
		"soap":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				table(u, v, 0.6, 0.35, 0.28, Color("#8fc0b8"), Color("#cfe8e2"))
				for k in 5:
					bx(u - 0.25 + 0.11 * float(k), v - 0.1, u - 0.17 + 0.11 * float(k), v, 0.28, 0.33, Color(GOODS[k % GOODS.size()]).lightened(0.3))
				vat(u + 0.3, v + 0.35, 0.12, 0.35)
				slot(u - 0.1, v + 0.3, "swork", "b", "staff")
			slot(0.5, -0.1, "stand", "b", "guest")
		"rag_collect":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				for k in 3:
					var rc := Color(CLOTH[(k + cc.y + seed_v) % CLOTH.size()]).darkened(0.25)
					bx(u - 0.4 + 0.27 * float(k), v - 0.1, u - 0.18 + 0.27 * float(k), v + 0.35, 0.0, 0.18 + 0.1 * float(k % 2), rc, rc.lightened(0.15))
				sack(u, v - 0.3, Color("#b0a090"))
			slot(0.5, 0.5, "squat", "f", "staff")
			slot(0.8, float(Df) - 0.3, "swork", "l", "staff")
		"tailor":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y)
				for k in 2:
					var vv := v + 0.3 + 0.38 * float(k)
					bx(u - 0.35, vv - 0.1, u + 0.05, vv + 0.1, 0.0, 0.26, WOOD, MeshBuf.WHITE, "white", "sewing")
					bx(u - 0.2, vv - 0.05, u - 0.05, vv + 0.05, 0.26, 0.36, DARK)
					stool(u + 0.15, vv)
					slot(u + 0.15, vv, "work", "l", "staff", 0.0, {"anim": "sew"})
				hang_row(u - 0.4, u + 0.4, v + 0.92, 0.85, CLOTH, 0.3, 0.1)
			bx(float(Wf) - 0.35, 0.15, float(Wf) - 0.1, 0.45, 0.0, 0.14, Color("#e8a0b8"), Color("#f4b8cc"))
		"suit":
			table(0.5, 0.55, 0.6, 0.3, 0.3, WOOD, Color("#e6dcc4"))
			for k in mini(Wf * 2, 3):
				var uu := 0.3 + 0.55 * float(k)
				bx(uu - 0.05, 0.12, uu + 0.05, 0.22, 0.0, 0.05, DARK)
				bx(uu - 0.07, 0.13, uu + 0.07, 0.21, 0.3, 0.6, Color(["#3e4a7a", "#2e2a3a", "#7a2e3a"][k % 3]))
				bx(uu - 0.04, 0.14, uu + 0.04, 0.2, 0.6, 0.7, Color("#e6dcc4"))
				bx(uu - 0.015, 0.155, uu + 0.015, 0.185, 0.05, 0.3, DARK)
			shelf_back(0.1, float(Wf) - 0.1, float(Df) - 0.02, 0.8)
			slot(0.5, 0.85, "swork", "f", "staff")
			slot(float(Wf) - 0.5, 0.6, "stand", "l", "guest")
		"radio":
			counter(0.1, 0.2, float(Wf) - 0.1, 0.4, Color("#5f86c4"), Color("#8fb5d0"), 0.32)
			shelf_back(0.1, float(Wf) - 0.1, float(Df) - 0.02, 0.9, "radios" if m.atlas.has("radios") else "shelf")
			for k in 3:
				bx(0.2 + 0.25 * float(k), 0.24, 0.38 + 0.25 * float(k), 0.36, 0.32, 0.46, Color(["#8a5a3e", "#4a4664", "#c9a04a"][k]), MeshBuf.WHITE, "white", "tv" if k == 1 else "white")
			bx(float(Wf) - 0.55, float(Df) - 0.5, float(Wf) - 0.15, float(Df) - 0.25, 0.0, 0.3, WOOD, Color("#5a5674"))
			emit_at(float(Wf) - 0.35, float(Df) - 0.38, 0.35, "sparks")
			slot(0.5, 0.62, "swork", "f", "staff")
			slot(float(Wf) - 0.35, float(Df) - 0.7, "work", "b", "staff", 0.0, {"anim": "solder"})
			slot(0.6, -0.08, "stand", "b", "guest")
		"assembly":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				bx(u - 0.48, v - 0.08, u + 0.48, v + 0.08, 0.2, 0.28, Color("#4a4a5a"), Color("#6a6a7a"))
				for k in 3:
					bx(u - 0.4 + 0.3 * float(k), v - 0.05, u - 0.3 + 0.3 * float(k), v + 0.05, 0.28, 0.34, Color(GOODS[(k + cc.x) % GOODS.size()]))
				slot(u - 0.15, v - 0.25, "swork", "b", "staff")
				slot(u + 0.2, v + 0.25, "swork", "f", "staff")
				lamp(u, v, 0.92, Color("#e0f4ff"))
			emit_at(0.6, 0.5, 0.35, "sparks")
		"fake":
			# 거의 명품 공방: 칸마다 다른 일 — 도장대(금박 찍기) / 재봉 / 완성품 진열 + 거울과 손님
			var ci := 0
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				match ci % 3:
					0:
						table(u, v, 0.6, 0.35, 0.28)
						for k in 3:
							var bc := Color(["#8a5a3e", "#c9a04a", "#2e2a3a"][k])
							bx(u - 0.22 + 0.17 * float(k), v - 0.06, u - 0.1 + 0.17 * float(k), v + 0.06, 0.28, 0.4, bc, bc.lightened(0.2))
							bx(u - 0.19 + 0.17 * float(k), v - 0.01, u - 0.13 + 0.17 * float(k), v + 0.01, 0.4, 0.44, Color("#f2d27a"))
						bx(u + 0.2, v + 0.05, u + 0.3, v + 0.15, 0.28, 0.45, Color("#5a5674"))
						slot(u, v + 0.3, "work", "b", "staff", 0.0, {"anim": "stamp"})
					1:
						bx(u - 0.3, v - 0.1, u + 0.1, v + 0.1, 0.0, 0.26, WOOD, MeshBuf.WHITE, "white", "sewing")
						stool(u + 0.2, v)
						slot(u + 0.2, v, "work", "l", "staff", 0.0, {"anim": "sew"})
						hang_row(u - 0.4, u + 0.4, v + 0.4, 0.8, ["#8a5a3e", "#c9a04a", "#2e2a3a"], 0.2, 0.12)
					_:
						shelf_back(u - 0.45, u + 0.45, v + 0.48, 0.8)
						for k in 4:
							bx(u - 0.4 + 0.2 * float(k), v + 0.36, u - 0.28 + 0.2 * float(k), v + 0.46, 0.3, 0.42, Color(["#c2463c", "#8a5a3e", "#2e2a3a", "#c9a04a"][k]), Color("#f2d27a"))
						vq(u - 0.42, u - 0.22, v + 0.3, 0.3, 0.75, "white", Color("#cfe8ff"))
						slot(u, v - 0.1, "look", "b", "guest")
				ci += 1
		"mahjong":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				bx(u - 0.2, v - 0.2, u + 0.2, v + 0.2, 0.22, 0.27, Color("#8a6a5a"), MeshBuf.WHITE, "white", "mj_table")
				bx(u - 0.05, v - 0.05, u + 0.05, v + 0.05, 0.0, 0.22, Color("#5a4a4a"))
				for k in 4:
					var off := [Vector2(0, -0.32), Vector2(0, 0.32), Vector2(-0.32, 0), Vector2(0.32, 0)][k] as Vector2
					stool(u + off.x, v + off.y, Color(["#c2604f", "#5f86c4", "#e0a23c", "#5fae7a"][k]))
					slot(u + off.x, v + off.y, "work", ["b", "f", "r", "l"][k], "guest" if k > 0 else "staff", 0.0, {"anim": "shuffle"})
				lamp(u, v, 0.86, Color("#c8ffd8"))
				emit_at(u, v, 0.6, "incense")
		"teahouse":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				table(u, v, 0.32, 0.32, 0.26)
				bx(u - 0.04, v - 0.04, u + 0.04, v + 0.04, 0.26, 0.33, Color("#e6dcc4"), Color("#5fae7a"))
				stool(u - 0.25, v)
				stool(u + 0.25, v)
				slot(u - 0.25, v, "sit_eat", "r", "guest")
				slot(u + 0.25, v, "sit", "l", "guest")
				# 새장
				bx(u - 0.01, v - 0.01, u + 0.01, v + 0.01, 0.8, 1.0, DARK)
				cage(u, v, 0.14, 0.62)
			pot(float(Wf) - 0.25, float(Df) - 0.25)
			slot(float(Wf) - 0.5, float(Df) - 0.3, "carry", "l", "staff", 0.0, {"prop": "tray"})
		"karaoke":
			var ku := float(Wf) * 0.5
			bx(0.15, float(Df) - 0.6, float(Wf) - 0.15, float(Df) - 0.05, 0.0, 0.1, Color("#5c2a56"), Color("#9b3a6e"))
			screen(ku - 0.45, ku + 0.45, float(Df) - 0.03, 0.4, 0.85)
			sofa(0.15, 0.15, float(Wf) - 0.15, 0.4, Color("#9b3a6e"), "b")
			table(ku, 0.7, 0.5, 0.2, 0.18, Color("#3e3a54"), Color("#5c566e"))
			for k in 3:
				bx(ku - 0.2 + 0.15 * float(k), 0.66, ku - 0.16 + 0.15 * float(k), 0.7, 0.18, 0.26, Color("#e0a23c"))
			lamp(ku - 0.6, float(Df) * 0.5, 0.9, m.cfg.neon("magenta"))
			lamp(ku + 0.6, float(Df) * 0.5, 0.9, m.cfg.neon("cyan"))
			light_at(ku, float(Df) - 0.4, 0.5, m.cfg.neon("magenta"), 2.2)
			slot(ku, float(Df) - 0.35, "sing", "f", "guest")
			slot(ku - 0.5, 0.3, "sit", "b", "guest")
			slot(ku + 0.1, 0.3, "cheer", "b", "guest")
			slot(ku + 0.6, 0.3, "sit", "b", "guest")
			slot(float(Wf) - 0.25, 0.8, "carry", "l", "staff", 0.0, {"prop": "tray"})
		"bathhouse":
			tub(0.15, 0.4, float(Wf) - 0.15, float(Df) - 0.15)
			emit_at(float(Wf) * 0.3, float(Df) * 0.6, 0.3, "steam")
			emit_at(float(Wf) * 0.7, float(Df) * 0.5, 0.3, "steam")
			for k in mini(Wf * 2, 4):
				var uu := 0.4 + 0.4 * float(k)
				slot(uu, 0.65 + 0.25 * float(k % 2), "bathe", "f", "guest", 0.12)
			bx(0.1, 0.05, float(Wf) - 0.1, 0.22, 0.0, 0.1, WOOD, WOOD_T)
			for k in 3:
				bx(0.3 + 0.3 * float(k), 0.08, 0.42 + 0.3 * float(k), 0.18, 0.1, 0.16, Color("#f4ead2"))
			slot(float(Wf) - 0.3, 0.15, "swork", "r", "staff", 0.0, {"prop": "bucket"})
		"study":
			vq(0.15, float(Wf) - 0.15, float(Df) - 0.02, 0.4, 0.82, "blackboard" if m.atlas.has("blackboard") else "white", Color("#3a5a4a") if not m.atlas.has("blackboard") else MeshBuf.WHITE)
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y)
				if cc.y == Df - 1 and Df > 1:
					continue
				for k in 2:
					var uu := u - 0.22 + 0.44 * float(k)
					bx(uu - 0.14, v + 0.3, uu + 0.14, v + 0.46, 0.0, 0.24, WOOD, MeshBuf.WHITE, "white", "desk")
					stool(uu, v + 0.18)
					slot(uu, v + 0.18, "work", "b", "guest", 0.0, {"anim": "write"})
			slot(float(Wf) * 0.5, float(Df) - 0.25, "cheer", "f", "staff")
		"roof_park":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				if (cc.x + cc.y) % 2 == 0:
					bx(u - 0.2, v - 0.2, u + 0.2, v + 0.2, 0.0, 0.14, Color("#8a6650"), Color("#6fc07a"))
					bx(u - 0.04, v - 0.04, u + 0.04, v + 0.04, 0.14, 0.5, Color("#7a5a4a"))
					bx(u - 0.26, v - 0.26, u + 0.26, v + 0.26, 0.5, 0.85, Color("#4f9a5a"), Color("#7fd08a"))
				else:
					bx(u - 0.3, v - 0.08, u + 0.3, v + 0.08, 0.0, 0.14, WOOD, WOOD_T)
					slot(u - 0.12, v, "sit", "f", "guest")
					slot(u + 0.15, v, "sit", "f", "guest")
			slot(float(Wf) * 0.5, float(Df) * 0.5, "taichi", "f", "guest")
		"dentist":
			bx(0.3, 0.35, 0.56, 0.78, 0.0, 0.22, Color("#d6d8de"), MeshBuf.WHITE, "white", "chair_dentist")
			bx(0.6, 0.4, 0.64, 0.44, 0.0, 0.62, Color("#b9bcc8"))
			bx(0.48, 0.38, 0.66, 0.5, 0.62, 0.66, Color("#fff2d8"), Color("#fff2d8"), "white", "white", MeshBuf.K_NEON)
			bx(0.75, 0.15, 0.95, 0.4, 0.0, 0.32, Color("#eef0ea"), Color("#ffffff"))
			slot(0.43, 0.55, "lie", "b", "guest", 0.2)
			slot(0.72, 0.6, "swork", "l", "staff", 0.0, {"anim": "drill"})
			if Wf >= 2:
				sofa(1.15, 0.15, 1.85, 0.35, Color("#7fc0c8"), "b")
				slot(1.4, 0.25, "sit", "b", "guest")
				slot(1.65, 0.25, "sit", "b", "guest")
		"pharmacy":
			counter(0.1, 0.35, float(Wf) - 0.1, 0.52, Color("#eef0ea"), Color("#ffffff"), 0.34)
			shelf_back(0.1, float(Wf) - 0.1, float(Df) - 0.02, 0.9, "jars" if m.atlas.has("jars") else "shelf")
			for k in 4:
				bx(0.2 + 0.2 * float(k), 0.4, 0.28 + 0.2 * float(k), 0.48, 0.34, 0.44, Color(["#8a5a3e", "#5fae7a", "#e8a0b8", "#f4ead2"][k]))
			slot(float(Wf) * 0.5, 0.75, "swork", "f", "staff")
			slot(float(Wf) * 0.5 - 0.2, 0.1, "stand", "b", "guest")
		"salon":
			for k in mini(Wf * 2, 3):
				var uu := 0.3 + 0.55 * float(k)
				vq(uu - 0.15, uu + 0.15, float(Df) - 0.02, 0.35, 0.75, "mirror" if m.atlas.has("mirror") else "white", Color("#cfe8ff") if not m.atlas.has("mirror") else MeshBuf.WHITE)
				chair(uu, float(Df) - 0.35, "b", Color("#e8a0b8"))
				slot(uu, float(Df) - 0.35, "sit", "b", "guest")
				slot(uu - 0.2, float(Df) - 0.55, "swork", "r", "staff", 0.0, {"anim": "cut"})
			sofa(0.15, 0.1, 0.7, 0.28, Color("#8fc0b8"), "b")
			slot(0.4, 0.2, "sit", "b", "guest")
		# ── 방재 ──
		"fire_bucket", "fire_station":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				if cc.y == Df - 1:
					bx(u - 0.45, v + 0.32, u + 0.45, v + 0.48, 0.5, 0.54, Color("#7a5848"))
					for k in 5:
						bx(u - 0.4 + 0.18 * float(k), v + 0.34, u - 0.3 + 0.18 * float(k), v + 0.46, 0.34, 0.5, Color("#c2463c"), Color("#3a3448"))
				drum(u - 0.3, v - 0.1, Color("#5f86c4"))
				if look == "fire_station" and cc == Vector2i(0, 0):
					bx(u - 0.1, v - 0.3, u + 0.8, v + 0.15, 0.08, 0.34, Color("#c2463c"), Color("#d8695f"))
					bx(u, v - 0.35, u + 0.12, v + 0.2, 0.0, 0.12, DARK)
					bx(u + 0.6, v - 0.35, u + 0.72, v + 0.2, 0.0, 0.12, DARK)
			slot(0.3, 0.3, "sit", "f", "staff")
			slot(0.7, 0.35, "squat", "f", "staff")
			if look == "fire_station":
				slot(1.5, 0.6, "stand", "f", "staff")
				slot(1.2, 1.4, "swork", "b", "staff")
		"trash_guild":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				junk(u - 0.15, v + 0.1, 0.36)
				bx(u + 0.15, v - 0.35, u + 0.45, v - 0.05, 0.0, 0.2, Color("#5fae7a"), Color("#3a3448"))
			bx(0.1, 0.1, 0.5, 0.35, 0.06, 0.26, Color("#8a7a6a"), Color("#6a5a4a"))
			bx(0.12, 0.08, 0.22, 0.38, 0.0, 0.1, DARK)
			slot(0.6, 0.6, "squat", "b", "staff")
			slot(0.3, 0.55, "carry", "f", "staff", 0.0, {"prop": "sack"})
		"clinic":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				bed(u - 0.18, v + 0.05, true)
				bx(u + 0.12, v - 0.25, u + 0.16, v - 0.21, 0.0, 0.7, Color("#b9bcc8"))
				bx(u + 0.08, v - 0.26, u + 0.2, v - 0.2, 0.62, 0.74, Color("#cfe8ff"))
				slot(u - 0.18, v + 0.05, "lie", "b", "guest", 0.2)
			bx(float(Wf) - 0.45, 0.15, float(Wf) - 0.1, 0.4, 0.0, 0.3, Color("#eef0ea"), Color("#ffffff"))
			slot(float(Wf) * 0.5 + 0.1, 0.35, "swork", "b", "staff")
		# ── 기반 ──
		"scrapyard":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				junk(u - 0.1, v + 0.1, 0.5)
				if (cc.x + cc.y) % 2 == 1:
					bx(u - 0.3, v - 0.35, u + 0.1, v - 0.15, 0.0, 0.14, Color("#8a96aa"), Color("#c4ccd8"))
			emit_at(float(Wf) * 0.5, 0.4, 0.3, "sparks")
			slot(float(Wf) * 0.5, 0.25, "swork", "b", "staff", 0.0, {"anim": "hammer"})
			slot(0.4, float(Df) - 0.3, "carry", "f", "staff")
		"warehouse":
			# 창고: 뒷벽 선반 줄 + 바닥 상자 더미(칸마다 다르게) + 손수레 미는 사람 + 장부 든 관리인
			var ci2 := 0
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y)
				if cc.y == Df - 1:
					bx(u - 0.46, v + 0.72, u + 0.46, v + 0.96, 0.0, 0.85, Color("#6a5a4a"), Color("#8a7a6a"))
					for lv in 3:
						for k in 3:
							var cc2 := Color(["#c9a46a", "#b08050", "#d8c08a"][(k + lv + ci2) % 3])
							bx(u - 0.42 + 0.29 * float(k), v + 0.74, u - 0.17 + 0.29 * float(k), v + 0.94, 0.02 + 0.28 * float(lv), 0.22 + 0.28 * float(lv), cc2, cc2.lightened(0.15))
				if ci2 % 2 == 0:
					crate(u - 0.22, v + 0.4, 0.26, true)
					sack(u + 0.2, v + 0.45)
				else:
					bx(u - 0.2, v + 0.3, u + 0.15, v + 0.5, 0.06, 0.12, Color("#c9a04a"))
					bx(u - 0.22, v + 0.28, u - 0.18, v + 0.52, 0.0, 0.32, Color("#5a5674"))
					crate(u - 0.03, v + 0.4, 0.18)
				ci2 += 1
			slot(0.45, 0.25, "carry", "r", "staff")
			slot(float(Wf) - 0.3, 0.3, "look", "l", "staff")
		"trade_post":
			counter(0.1, 0.25, float(Wf) - 0.1, 0.42, WOOD, WOOD_T, 0.34)
			bx(0.25, 0.3, 0.45, 0.38, 0.34, 0.5, Color("#c9a04a"), Color("#f2d27a"))
			crate(0.3, float(Df) - 0.3, 0.26, true)
			crate(float(Wf) - 0.35, float(Df) - 0.3, 0.24)
			slot(float(Wf) * 0.5, 0.65, "swork", "f", "staff")
			slot(float(Wf) * 0.5 + 0.2, 0.05, "stand", "b", "guest")
		"expedition_base":
			# 줍줍 본부: 핀 꽂힌 지도 탁자 + 무전기 책상(무전수) + 배낭·밧줄 걸이 + 사물함
			var mu := float(Wf) * 0.5
			table(mu, 0.55, 0.7, 0.42, 0.28, WOOD, Color("#e6dcc4"))
			bx(mu - 0.3, 0.38, mu + 0.3, 0.72, 0.28, 0.285, Color("#d8c89a"), Color("#e8d8aa"))
			for k in 5:
				bx(mu - 0.25 + 0.12 * float(k), 0.42 + 0.06 * float(k % 3), mu - 0.23 + 0.12 * float(k), 0.44 + 0.06 * float(k % 3), 0.285, 0.33, Color(["#c2463c", "#5f86c4", "#e0a23c"][k % 3]))
			bx(0.1, float(Df) - 0.35, 0.45, float(Df) - 0.1, 0.0, 0.26, WOOD, WOOD_T)
			bx(0.15, float(Df) - 0.3, 0.35, float(Df) - 0.15, 0.26, 0.38, Color("#5a6a5a"), Color("#3a4a3a"))
			bx(0.3, float(Df) - 0.25, 0.32, float(Df) - 0.23, 0.38, 0.55, DARK)
			stool(0.28, float(Df) - 0.5)
			for k in 3:
				bx(float(Wf) - 0.6 + 0.16 * float(k), float(Df) - 0.18, float(Wf) - 0.48 + 0.16 * float(k), float(Df) - 0.06, 0.3, 0.56, Color(["#5a7a4a", "#8a5a3e", "#4f7aa8"][k]), Color(-1, 0, 0))
			bx(float(Wf) - 0.7, float(Df) - 0.1, float(Wf) - 0.1, float(Df) - 0.04, 0.6, 0.64, Color("#6a5a4a"))
			bx(float(Wf) - 0.25, 0.2, float(Wf) - 0.08, 0.4, 0.0, 0.08, Color("#c9b48a"), Color("#a8946a"))
			slot(mu - 0.4, 0.55, "look", "r", "staff")
			slot(mu + 0.4, 0.55, "swork", "l", "staff")
			slot(0.28, float(Df) - 0.5, "work", "b", "staff", 0.0, {"anim": "phone"})
		"gambling":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				bx(u - 0.3, v - 0.18, u + 0.3, v + 0.18, 0.22, 0.27, Color("#2e5a3a"), MeshBuf.WHITE, "white", "mj_table")
				bx(u - 0.04, v - 0.04, u + 0.04, v + 0.04, 0.0, 0.22, DARK)
				for k in 3:
					slot(u - 0.22 + 0.22 * float(k), v + 0.32, "cheer" if k == 1 else "stand", "b", "guest")
				slot(u, v - 0.3, "swork", "f", "staff", 0.0, {"anim": "dice"})
				lamp(u, v, 0.8, Color("#ffd88a"))
		"casino":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				if cc.y == Df - 1:
					for k in 3:
						bx(u - 0.4 + 0.28 * float(k), v + 0.25, u - 0.2 + 0.28 * float(k), v + 0.45, 0.0, 0.5, MeshBuf.WHITE, Color("#b0306a"), "slot", "white")
						slot(u - 0.3 + 0.28 * float(k), v + 0.1, "stand", "b", "guest")
				else:
					bx(u - 0.25, v - 0.25, u + 0.25, v + 0.25, 0.22, 0.27, Color("#2e5a3a"), MeshBuf.WHITE, "white", "roulette" if m.atlas.has("roulette") else "mj_table")
					bx(u - 0.05, v - 0.05, u + 0.05, v + 0.05, 0.0, 0.22, DARK)
					slot(u, v + 0.38, "cheer", "b", "guest")
					slot(u - 0.36, v, "stand", "r", "guest")
					slot(u, v - 0.36, "swork", "f", "staff")
				lamp(u, v, 0.9, Color("#ffd84a"))
		"callcenter":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y)
				for k in 2:
					var uu := u - 0.22 + 0.44 * float(k)
					bx(uu - 0.16, v + 0.35, uu + 0.16, v + 0.55, 0.0, 0.26, WOOD, MeshBuf.WHITE, "white", "desk")
					bx(uu - 0.16, v + 0.53, uu + 0.16, v + 0.56, 0.26, 0.5, Color("#8fb5d0"))
					chair(uu, v + 0.2, "b")
					slot(uu, v + 0.2, "work", "b", "staff", 0.0, {"anim": "phone"})
			lamp(float(Wf) * 0.5, float(Df) * 0.5, 0.92, Color("#e0f4ff"))
		"fireworks":
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				table(u, v, 0.6, 0.35, 0.26)
				for k in 6:
					bx(u - 0.25 + 0.09 * float(k), v - 0.08, u - 0.19 + 0.09 * float(k), v - 0.02, 0.26, 0.4 + 0.04 * float(k % 2), Color(["#c2463c", "#e0a23c", "#5f86c4"][k % 3]))
				crate(u + 0.3, v + 0.35, 0.2)
				slot(u - 0.1, v + 0.3, "work", "b", "staff", 0.0, {"anim": "roll"})
			emit_at(0.5, 0.5, 0.4, "sparks")
		# ── 명소 ──
		"landmark_hall":
			var cu := float(Wf) * 0.5
			bx(cu - 0.6, float(Df) - 0.8, cu + 0.6, float(Df) - 0.45, 0.0, 0.34, Color("#8a2f34"), Color("#c2463c"))
			bx(cu - 0.1, float(Df) - 0.3, cu + 0.1, float(Df) - 0.1, 0.0, 0.5, Color("#b0303a"))
			bx(cu - 0.25, float(Df) - 0.22, cu + 0.25, float(Df) - 0.18, 0.5, 0.8, Color("#f2d27a"), Color("#f2d27a"))
			vq(cu - 0.8, cu + 0.8, float(Df) - 0.02, 0.45, 0.95, "white", Color("#c2463c"))
			slot(cu, float(Df) - 0.3, "sit", "f", "staff")
			slot(cu - 0.45, float(Df) - 0.3, "swork", "f", "staff", 0.0, {"anim": "stamp"})
			for k in 5:
				slot(cu - 0.2 + 0.05 * float(k % 2), float(Df) - 1.15 + 0.32 * float(-k) + 0.0, "stand", "b", "guest")
			for k in 4:
				var ru := 0.35 + (float(Wf) - 0.7) * float(k % 2)
				var rv := 0.5 + 0.9 * float(k / 2)
				bx(ru - 0.05, rv - 0.05, ru + 0.05, rv + 0.05, 0.0, 0.98, Color("#b0303a"))
			lamp(cu, float(Df) * 0.5, 0.9, Color("#ff8a4a"))
			lamp(cu - 1.0, float(Df) * 0.5, 0.9, Color("#ff8a4a"))
			lamp(cu + 1.0, float(Df) * 0.5, 0.9, Color("#ff8a4a"))
		"landmark_generic":
			# 명소(전시관): 가운데 조각상(대표 칸) + 칸마다 다른 진열장·의자, 조명, 안내원·구경꾼
			var feat: Vector2i = cells[0] if not cells.is_empty() else Vector2i.ZERO
			for cc in cells:
				if cc.x + cc.y > feat.x + feat.y:
					feat = cc
			var ci3 := 0
			for cc in cells:
				var u := float(cc.x) + 0.5
				var v := float(cc.y) + 0.5
				if cc == feat:
					bx(u - 0.25, v - 0.25, u + 0.25, v + 0.25, 0.0, 0.12, Color("#eef0ea"), Color("#ffffff"))
					bx(u - 0.08, v - 0.08, u + 0.08, v + 0.08, 0.12, 0.62, Color("#c9a04a"), Color("#f2d27a"))
					bx(u - 0.14, v - 0.06, u + 0.14, v + 0.06, 0.48, 0.56, Color("#c9a04a"))
					bx(u - 0.06, v - 0.06, u + 0.06, v + 0.06, 0.62, 0.74, Color("#e0b85a"))
					light_at(u, v, 0.9, Color("#ffe8a8"), 1.6)
					slot(u + 0.36, v, "look", "l", "guest")
					slot(u, v + 0.38, "cheer", "b", "guest")
				elif ci3 % 2 == 0:
					bx(u - 0.3, v - 0.12, u + 0.3, v + 0.12, 0.0, 0.3, Color("#5a4a3e"), Color("#a9cbea"))
					for k in 3:
						bx(u - 0.22 + 0.17 * float(k), v - 0.04, u - 0.14 + 0.17 * float(k), v + 0.04, 0.3, 0.38, Color(GOODS[(k + ci3) % GOODS.size()]))
					slot(u, v - 0.3, "look", "f", "guest")
				else:
					bx(u - 0.3, v - 0.07, u + 0.3, v + 0.07, 0.0, 0.14, WOOD, WOOD_T)
					slot(u - 0.1, v, "sit", "f", "guest")
					vq(u - 0.3, u + 0.3, v + 0.45, 0.35, 0.8, "white", Color(["#c2463c", "#3e4a7a"][ci3 % 2]))
				ci3 += 1
				lamp(u, v, 0.92, Color("#fff2c8"))
			slot(0.3, 0.2, "stand", "f", "staff")
		"generic_service":
			# 상담소: 책상과 상담원 + 대기 의자 줄 + 번호표 화면
			table(float(Wf) * 0.5, 0.6, 0.6, 0.3)
			chair(float(Wf) * 0.5, 0.85, "f")
			chair(float(Wf) * 0.5, 0.32, "b")
			slot(float(Wf) * 0.5, 0.85, "work", "f", "staff", 0.0, {"anim": "write"})
			slot(float(Wf) * 0.5, 0.32, "sit", "b", "guest")
			for k in mini(Wf * 2, 3):
				chair(0.25 + 0.3 * float(k), float(Df) - 0.25, "f", Color("#8fc0b8"))
				slot(0.25 + 0.3 * float(k), float(Df) - 0.25, "sit", "f", "guest")
			screen(float(Wf) - 0.45, float(Wf) - 0.15, float(Df) - 0.02, 0.6, 0.78)
		"generic_shop":
			counter(0.1, 0.22, float(Wf) - 0.1, 0.4, WOOD, WOOD_T, 0.34)
			shelf_back(0.1, float(Wf) - 0.1, float(Df) - 0.02, 0.85)
			for k in 4:
				bx(0.2 + 0.2 * float(k), 0.26, 0.3 + 0.2 * float(k), 0.36, 0.34, 0.42, Color(GOODS[k % GOODS.size()]))
			bx(float(Wf) - 0.4, 0.26, float(Wf) - 0.2, 0.36, 0.34, 0.44, Color("#5a5674"), Color("#e0a23c"))
			slot(float(Wf) * 0.5, 0.62, "swork", "f", "staff")
			slot(float(Wf) * 0.5 - 0.2, 0.05, "stand", "b", "guest")
			slot(float(Wf) * 0.5 + 0.25, -0.05, "look", "b", "guest")
		"generic_workshop":
			# 공방: 바이스 달린 작업대(망치질) + 공구 벽 + 재료 더미
			bx(0.1, 0.5, float(Wf) - 0.1, 0.72, 0.0, 0.3, WOOD, WOOD_T)
			bx(0.25, 0.55, 0.38, 0.65, 0.3, 0.4, Color("#5a5674"))
			vq(0.15, float(Wf) - 0.15, float(Df) - 0.02, 0.45, 0.8, "white", Color("#8a7a6a"))
			for k in 5:
				bx(0.25 + 0.16 * float(k), float(Df) - 0.06, 0.28 + 0.16 * float(k), float(Df) - 0.03, 0.5, 0.72 - 0.04 * float(k % 2), Color(["#8a96aa", "#c2463c", "#5a5674"][k % 3]))
			crate(float(Wf) - 0.3, 0.25, 0.22, true)
			junk(0.3, 0.2, 0.26)
			emit_at(0.32, 0.6, 0.45, "sparks")
			slot(0.35, 0.35, "hammer", "b", "staff", 0.0, {"anim": "hammer"})
			slot(float(Wf) - 0.4, 0.45, "carry", "l", "staff")
		_:
			table(float(Wf) * 0.5, 0.5, 0.6, 0.3)
			shelf_back(0.1, float(Wf) - 0.1, float(Df) - 0.02, 0.8)
			slot(float(Wf) * 0.5, 0.75, "swork", "f", "staff")
	if special.size() == 2:
		_foreman_corner(special[0])
		_storage_corner(special[1])
		cells.append_array(special)
	if str(rec.get("form", "box")) == "box" and not lk.begins_with("landmark") and lk not in ["karaoke", "bathhouse", "study", "salon", "mahjong", "power_waste"]:
		# 천장 등(한 칸에 하나)
		for cc in cells:
			if (cc.x + cc.y) % 2 == 0:
				light_at(float(cc.x) + 0.5, float(cc.y) + 0.5, 0.7, Color(1, 1, 1), 0.9, 0.8)
