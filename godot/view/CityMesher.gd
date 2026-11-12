class_name CityMesher
extends RefCounted
## CityMesher — CityState의 셀·골조 → 층별 메시. 규칙 없음, 상태를 읽기만 한다(cells, supports, buildings).
## 주거 외관 = 계층 × 자재 계열(visuals.json > houses). 같은 외관끼리 붙으면 한 건물처럼 이어지고, 다르면 이음매가 남는다.
## 다리·계단·발코니·옥탑·간판·빨래 등은 셀 배치와 seed에서 결정론적으로 파생한다(셀이 아니다).
## 불 켜진 창 비율·전기·가동 여부는 정점에 박지 않고 "셀 상태 텍스처"(CityView)로 넘긴다 → building_changed는 메시를 다시 짓지 않는다.

const DIR: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(-1, 0, 0), Vector3i(0, -1, 0)]
const NRM: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
const RGT: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
const RGTI: Array[Vector3i] = [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(-1, 0, 0)]
const ORG: Array[Vector3] = [Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0)]
const UP := Vector3(0, 1, 0)
const UPI := Vector3i(0, 0, 1)
const TX := 1.0 / 16.0
const EPS := 0.012

const LAUNDRY: Array[String] = ["#f4f0e6", "#ff6f6f", "#5fa8e6", "#ffd45a", "#7fd08a", "#ff9ac0", "#f4f0e6", "#b58be0", "#ff9a4a", "#6fd0d0"]
const PIPES: Array[String] = ["#b5654f", "#8fb5d0", "#d8cfc0", "#6a6486", "#7fae8a"]
const STEEL_C := Color("#6a6486")
const STEEL_T := Color("#9a94b6")
const BAMBOO_C := Color("#d8b45a")

var cfg: ViewCfg
var atlas: PixelAtlas
var state: CityState
var fh := 0.8165
var gw := 12
var gh := 12

# prepare()가 채우는 것
var solid: Dictionary = {}        # Vector3i -> true (상자형: 주거·상자 시설)
var by_floor: Array = []          # [z] -> Array[Vector3i]
var sup_floor: Array = []         # [z] -> Array[Vector3i] (셀 없는 골조 칸)
var voids: Dictionary = {}        # Vector3i -> true (셀 없는 골조 칸)
var col_h: Dictionary = {}        # Vector2i -> float (층 단위, 그림자용)
var top_z: int = 0
var bridges: Dictionary = {}      # fkey -> 상대 셀
var stairs: Dictionary = {}       # (x,y,d) 키 -> [z0, z1]
var chimney_cols: Dictionary = {} # Vector2i -> fx 종류
var signs: Dictionary = {}        # fkey(p,d) -> "big"|"blade"|"plaque"|"board" (건물당 하나)
var power_on := false

# 층 하나를 짓는 동안
var mb: MeshBuf
var lights: Array = []
var emitters: Array = []
var slots: Array = []             # 시설 안 사람 자리(FacilityBuilder.slot)
var fac := FacilityBuilder.new()


func setup(c: ViewCfg, a: PixelAtlas) -> void:
	cfg = c
	atlas = a
	fh = c.floor_h
	gw = c.grid.x
	gh = c.grid.y
	fac.setup(self)


static func fkey(p: Vector3i, d: int) -> int:
	return ((p.x + 8) * 64 + (p.y + 8)) * 64 * 4 + p.z * 4 + d


## 셀 상태 텍스처의 칸 번호(0 = 없음). 정점 UV2.x의 정수부로 들어간다.
func owner_of(p: Vector3i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= gw or p.y >= gh or p.z < 0 or p.z >= cfg.grid.z + 2:
		return 0
	return 1 + p.x + p.y * gw + p.z * gw * gh


func recipe_of(c: Dictionary) -> Dictionary:
	if str(c.get("kind", "")) == "facility":
		return cfg.look_recipe(look_name(c), cat_of(c))
	return cfg.recipe(str(c.get("kind", "")), str(c.get("type", "")))


func is_box(c: Dictionary) -> bool:
	if c.is_empty():
		return false
	var kind: String = str(c.get("kind", ""))
	if kind == "site":
		return false
	if kind == "house":
		return true
	return str(recipe_of(c).get("form", "box")) == "box"


## 건물 범위: origin, w, h, d(층 수). v4 셀 키(w,h,d)가 없으면 v3 size로.
func extent_of(c: Dictionary, p: Vector3i) -> Dictionary:
	var o: Variant = c.get("origin", p)
	if not (o is Vector3i):
		o = p
	var sz := int(c.get("size", 1))
	return {"origin": o, "w": maxi(int(c.get("w", sz)), 1), "h": maxi(int(c.get("h", sz)), 1), "d": maxi(int(c.get("d", 1)), 1)}


## 시설 외형 이름표: 셀 → 건물 → buildings.json → v3 id 표 → 분류 기본.
func look_name(c: Dictionary) -> String:
	var lk := str(c.get("look", ""))
	if lk == "":
		lk = str(bld(c).get("look", ""))
	var type := str(c.get("type", ""))
	if lk == "" and type != "":
		lk = str(Data.item("buildings", type).get("look", ""))
	if lk != "" and cfg.has_look(lk):
		return lk
	if ViewCfg.V3_LOOK.has(type):
		return ViewCfg.V3_LOOK[type]
	var cat := cat_of(c)
	for k in ViewCfg.CAT_LOOK:
		if cat.begins_with(k):
			return ViewCfg.CAT_LOOK[k]
	return "generic_shop"


func cat_of(c: Dictionary) -> String:
	var cat := str(bld(c).get("cat", ""))
	if cat == "":
		cat = str(Data.item("buildings", str(c.get("type", ""))).get("cat", ""))
	if cat == "":
		cat = str(ViewCfg.LOOK_CAT.get(str(c.get("look", "")), ""))
	return cat


## 간판 글자(짧은 한글): 셀 → 건물 → buildings.json. 한자는 걸러 낸다.
func sign_of(c: Dictionary) -> String:
	var t := str(c.get("sign", ""))
	if t == "":
		t = str(bld(c).get("sign", ""))
	if t == "":
		t = str(Data.item("buildings", str(c.get("type", ""))).get("sign", ""))
	var out := ""
	for i in t.length():
		var cp := t.unicode_at(i)
		if (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0xF900 and cp <= 0xFAFF):
			continue
		out += t[i]
	return out.substr(0, 5)


func bld(c: Dictionary) -> Dictionary:
	var b: Variant = state.buildings.get(int(c.get("bid", -1)), {}) if state.buildings is Dictionary else {}
	return b if b is Dictionary else {}


## 주거 외관 키: T1(또는 자재 없음) = common_1, 그 밖 <family>_<tier>.
func look_key(c: Dictionary) -> String:
	var t := clampi(int(c.get("tier", 1)), 1, 5)
	var m: String = str(c.get("material", ""))
	if t <= 1 or m == "" or m == "common":
		return "common_1"
	return "%s_%d" % [m, t]


func look_of(c: Dictionary) -> Dictionary:
	return cfg.house_look(look_key(c))


## 이어 그리기 판정용: 같은 키면 한 건물처럼(벽·지붕선·발코니가 이어진다).
func group_of(p: Vector3i) -> String:
	var c: Dictionary = state.cells.get(p, {})
	if c.is_empty():
		return ""
	match str(c.get("kind", "")):
		"house":
			return "h:" + look_key(c)
		"facility":
			return "f:%d" % int(c.get("bid", 0))
	return "s"


## 이 집이 전기로 불을 켜는가 — 전기 판정은 여기 한 곳(시뮬의 최종 필드가 생기면 여기만 고친다).
func electric(c: Dictionary) -> bool:
	if str(c.get("kind", "")) == "house":
		return power_on or int(c.get("tier", 1)) >= 3
	return power_on


## 도시 전력: state의 명시 필드(power_on / power_level / flags.power)가 있으면 그것, 없으면 가동 중인 전기 시설이 있는가.
static func city_power(st: CityState, c: ViewCfg) -> bool:
	if st == null:
		return false
	var v: Variant = st.get("power_on")
	if v != null:
		return bool(v)
	var fl: Variant = st.get("flags")
	if fl is Dictionary and (fl as Dictionary).has("power_on"):
		return bool(fl["power_on"])
	var lv: Variant = st.get("power_level")
	if lv != null and int(lv) > 0:
		return true
	var bs: Variant = st.get("buildings")
	if bs is Dictionary:
		for b in (bs as Dictionary).values():
			if b is Dictionary and str(b.get("kind", "")) == "facility" and bool(b.get("active", true)):
				if bool(c.recipe("facility", str(b.get("type", ""))).get("power", false)):
					return true
	return false


func prepare(s: CityState) -> void:
	state = s
	solid.clear()
	col_h.clear()
	bridges.clear()
	stairs.clear()
	chimney_cols.clear()
	voids.clear()
	by_floor.clear()
	sup_floor.clear()
	top_z = 0
	power_on = city_power(s, cfg)
	fac.reset()
	for z in cfg.grid.z + 2:
		by_floor.append([])
		sup_floor.append([])
	for p in s.cells:
		if not (p is Vector3i):
			continue
		var c: Variant = s.cells[p]
		if not (c is Dictionary):
			continue
		if p.z < 0 or p.z >= by_floor.size():
			continue
		by_floor[p.z].append(p)
		top_z = maxi(top_z, p.z + 1)
		var col := Vector2i(p.x, p.y)
		var kind: String = str(c.get("kind", ""))
		var rec: Dictionary = recipe_of(c)
		var hh := float(p.z)
		if is_box(c):
			solid[p] = true
			hh = float(p.z + 1)
		elif kind == "site":
			hh = float(p.z) + clampf(float(c.get("progress", 0.0)), 0.0, 1.0) * 0.9
		else:
			var form: String = str(rec.get("form", "box"))
			hh = float(p.z) + {"open": 0.0, "shed": 0.9, "tank": 1.15, "pole": 0.5, "shrine": 0.6}.get(form, 0.6)
		col_h[col] = maxf(float(col_h.get(col, 0.0)), hh)
	var sup: Variant = s.get("supports")
	if sup is Dictionary:
		for p in sup:
			if p is Vector3i and not s.cells.has(p) and p.z >= 0 and p.z < sup_floor.size():
				voids[p] = true
				sup_floor[p.z].append(p)
				top_z = maxi(top_z, p.z + 1)
	for z in by_floor.size():
		by_floor[z].sort()
		sup_floor[z].sort()
	_derive_bridges()
	_derive_stairs()
	_alloc_signs()


func height_floors(col: Vector2i) -> float:
	return float(col_h.get(col, 0.0))


func _derive_bridges() -> void:
	# 한 칸 틈을 사이에 둔 같은 층의 두 주거 → 판자 다리 (같은 건물끼리는 안 놓는다)
	var used: Dictionary = {}
	for p in solid:
		if p.z < 1:
			continue
		for d in [0, 1]:
			var mid: Vector3i = p + DIR[d]
			var far: Vector3i = p + DIR[d] * 2
			if not solid.has(far) or state.cells.has(mid):
				continue
			var gap := Vector3i(mid.x, mid.y, d)
			var last: int = int(used.get(gap, -9))
			var hsh := ViewCfg.h3(int(state.cells[p].get("seed", 0)), int(state.cells[far].get("seed", 0)), d + 11)
			if hsh % 100 < 42 and p.z - last >= 2:
				used[gap] = p.z
				bridges[fkey(p, d)] = far
				bridges[fkey(far, (d + 2) % 4)] = p


func _derive_stairs() -> void:
	# 바깥 공기에 2층 이상 연속으로 드러난 기둥 옆면 일부에 지그재그 외벽 계단(낮은 계층 주거 쪽에서만)
	for x in gw:
		for y in gh:
			var h := 0
			while solid.has(Vector3i(x, y, h)):
				h += 1
			if h < 2:
				continue
			var lowtier := int(state.cells.get(Vector3i(x, y, 0), {}).get("tier", 1)) <= 3
			if not lowtier:
				continue
			for d in 4:
				var nb := Vector2i(x + DIR[d].x, y + DIR[d].y)
				var z0 := int(ceil(float(col_h.get(nb, 0.0))))
				if state.cells.has(Vector3i(nb.x, nb.y, z0)):
					continue
				if h - z0 < 2:
					continue
				var hsh := ViewCfg.h3(x * 31 + y, d, 77)
				if hsh % 100 < 11:
					var ok := true
					for z in range(z0, mini(h, z0 + 5)):
						if bridges.has(fkey(Vector3i(x, y, z), d)) or state.cells.has(Vector3i(nb.x, nb.y, z)) or voids.has(Vector3i(nb.x, nb.y, z)):
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


## 단색 상자(소품용)
func cbox(a: Vector3, b: Vector3, c: Color, top_c: Color = Color(-1, 0, 0), faces: int = 31) -> void:
	mb.box(a, b, tile("white"), tile("white"), fh, c, faces, 0.0, 0.0, top_c)


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
	slots = []
	if z < by_floor.size():
		for p in by_floor[z]:
			mb.owner = owner_of(p)
			_build_cell(p, state.cells[p])
		for p in sup_floor[z]:
			mb.owner = 0
			_build_support(p)
	mb.owner = 0
	return {"mesh": mb.commit(), "lights": lights, "emitters": emitters, "slots": slots}


func _build_cell(p: Vector3i, c: Dictionary) -> void:
	var kind: String = str(c.get("kind", ""))
	var rec: Dictionary = recipe_of(c)
	var seed_v: int = int(c.get("seed", 0)) + p.x * 7 + p.y * 13 + p.z * 29
	if kind == "site":
		_build_site(p, c, seed_v)
		return
	if kind == "house":
		_build_house(p, c, seed_v)
		return
	if kind == "facility":
		fac.build_cell(p, c, false)
		return
	if int(c.get("size", 1)) >= 2:
		var o: Variant = c.get("origin", p)
		if o is Vector3i and o == p:
			mb.owner = owner_of(p)
			_build_big(p, c, rec, seed_v)
		return
	match str(rec.get("form", "box")):
		"open":
			_build_open(p, c, rec, seed_v)
		"shed":
			_build_shed(p, c, rec, seed_v)
		"tank":
			_build_tank(p, c, rec, seed_v)
		"shrine":
			_build_shrine(p, c, rec, seed_v)
		_:
			_build_fac_box(p, c, rec, seed_v, -1)
			_fac_props(p, c, rec, seed_v, _front_of(p, seed_v))


# ================================================================== 주거
func _age_variant(seed_v: int, tier: int) -> int:
	# 낮은 계층일수록 얼룩·때가 많다(자재 타일 변주 0..3)
	var r := ViewCfg.h2(seed_v, 5) % 100
	match tier:
		1:
			return 3 if r < 35 else (2 if r < 75 else 1)
		2:
			return 2 if r < 30 else (1 if r < 70 else 0)
		3:
			return 1 if r < 40 else 0
	return 0


func _build_house(p: Vector3i, c: Dictionary, seed_v: int) -> void:
	var look := look_of(c)
	var tier := clampi(int(c.get("tier", 1)), 1, 5)
	var mat: String = cfg.material_key(str(look.get("wall", "scrap")))
	var var_i := _age_variant(seed_v, tier)
	var grp := group_of(p)
	var glass_wall: bool = str(cfg.material(mat).get("pattern", "")) == "curtain"
	# 전기/촛불은 셰이더가 셀 상태(G)로 고른다 → 전기가 들어와도 메시를 다시 짓지 않는다
	var wk := MeshBuf.K_WINDOW
	for d in 4:
		var nb: Vector3i = p + DIR[d]
		if solid.has(nb):
			continue
		var wv := (var_i + (ViewCfg.h2(seed_v, d) % 2)) % 4 if var_i < 3 else 3
		if tier >= 4:
			wv = ViewCfg.h2(p.x * 3 + p.y, p.z + d) % 2   # 깨끗한 두 변주만
		var wr := tile("wall_%s_%d" % [mat, wv])
		mb.quad(fp(p, d, 0, 1, 0), fp(p, d, 1, 1, 0), fp(p, d, 1, 0, 0), fp(p, d, 0, 0, 0), NRM[d], wr, MeshBuf.WHITE, float(ViewCfg.h2(seed_v, d + 40) % 997) / 997.0, wk if glass_wall else 0.0)
		_seams(p, d, grp, look)
		if state.cells.has(nb):
			continue  # 옆이 열린 구조물(텃밭·좌판)이면 벽만
		_house_face(p, d, c, look, mat, seed_v, tier, wk)
	# 지붕
	var above: Vector3i = p + UPI
	if not solid.has(above):
		var rmat: String = cfg.material_key(str(look.get("roof", mat)))
		var rv := ViewCfg.h2(seed_v, 9) % 3
		if tier >= 4:
			rv = 0
		var rr := tile("roof_%s_%d" % [rmat, rv])
		var base := cellv(p)
		var y := base.y + fh
		mb.quad(Vector3(base.x, y, base.z), Vector3(base.x + 1, y, base.z), Vector3(base.x + 1, y, base.z + 1), Vector3(base.x, y, base.z + 1), UP, rr)
		_roof_edges(p, c, look, grp)
		if not state.cells.has(above):
			_house_rooftop(p, c, look, seed_v, tier)
	if bool(c.get("scaffold", false)):
		_scaffold_wrap(p, seed_v)


## 옆 칸이 다른 외관(다른 자재·계층)이거나 시설이면 벽 모서리에 이음매 — "선택의 역사".
func _seams(p: Vector3i, d: int, grp: String, look: Dictionary) -> void:
	var sc := ViewCfg.col(look.get("seam", "#5a4c62"), Color("#5a4c62"))
	for side in [0, 1]:
		var q: Vector3i = p - RGTI[d] if side == 0 else p + RGTI[d]
		if not solid.has(q):
			continue
		var g2 := group_of(q)
		if g2 == grp:
			continue
		var u0 := 0.0 if side == 0 else 0.9375
		# 어두운 줄눈 + 살짝 튀어나온 홈통
		fbox(p, d, u0, u0 + 0.0625, 0.0, 1.0, 0.0, 0.03, tile("white"), tile("white"), sc, 7)
	# 아래층이 다른 외관이면 수평 띠(증축 흔적)
	var below: Vector3i = p - UPI
	if solid.has(below) and group_of(below) != grp:
		fbox(p, d, 0.0, 1.0, 0.0, 0.0625, 0.0, 0.05, tile("white"), tile("white"), sc.lightened(0.25), 15)


## 지붕 가장자리: 같은 외관의 같은 높이 지붕이 옆에 있으면 비워 두고(이어진 지붕선), 아니면 난간벽·처마.
func _roof_edges(p: Vector3i, c: Dictionary, look: Dictionary, grp: String) -> void:
	var par := int(look.get("parapet", 0))
	var eave: String = str(look.get("eave", "none"))
	var rmat: String = cfg.material_key(str(look.get("roof", look.get("wall", "scrap"))))
	var wmat: String = cfg.material_key(str(look.get("wall", "scrap")))
	var ramp: Array = cfg.material(wmat).get("ramp", ["#cccccc", "#aaaaaa", "#888888", "#666666"])
	var trim := ViewCfg.col(ramp[1])
	for d in 4:
		var nb: Vector3i = p + DIR[d]
		if solid.has(nb + UPI):
			continue
		if solid.has(nb) and not solid.has(nb + UPI) and group_of(nb) == grp:
			continue   # 같은 건물의 이어진 지붕
		var pb := p + UPI   # 지붕 위 공간 기준 좌표(v=0 = 지붕 면)
		pb = Vector3i(p.x, p.y, p.z + 1)
		if par > 0:
			var hgt := float(par) * 0.0625
			fbox(pb, d, 0.0, 1.0, 0.0, hgt, -0.0625, 0.0, tile("white"), tile("white"), trim, 15, 0.0, 0.0, ViewCfg.col(ramp[0]))
		match eave:
			"wood", "wood_deep":
				var dep := 0.12 if eave == "wood" else 0.22
				var rr := tile("roof_%s_0" % rmat)
				var n := (UP * dep + NRM[d] * 0.08 * fh).normalized()
				mb.quad(fp(pb, d, -0.02, 0.06, -0.02), fp(pb, d, 1.02, 0.06, -0.02), fp(pb, d, 1.02, -0.04, dep), fp(pb, d, -0.02, -0.04, dep), n, sub(rr, 0, 0, 16, 4))
				mb.quad(fp(pb, d, 1.02, 0.06, -0.02), fp(pb, d, -0.02, 0.06, -0.02), fp(pb, d, -0.02, -0.04, dep), fp(pb, d, 1.02, -0.04, dep), -UP, sub(rr, 0, 0, 16, 4), Color(0.7, 0.62, 0.7))
				fbox(pb, d, -0.02, 1.02, -0.09, -0.04, dep - 0.03, dep, tile("white"), tile("white"), ViewCfg.col(cfg.material(rmat).get("roof", ["#a0705a", "#805a4a"])[1]), 15)
				if eave == "wood_deep":
					for u in [0.12, 0.88]:
						fbox(pb, d, u - 0.03, u + 0.03, -0.3, -0.06, 0.0, dep * 0.8, tile("white"), tile("white"), Color("#7a4e40"), 15)
			"tile":
				# 짙은 기와 처마(목조 T5): 두 단 + 끝이 들린 모서리
				var tc := Color("#3f6a5a")
				var tc2 := Color("#5a8a72")
				fbox(pb, d, -0.06, 1.06, -0.02, 0.08, -0.04, 0.26, tile("white"), tile("white"), tc, 15, 0.0, 0.0, tc2)
				fbox(pb, d, -0.04, 1.04, 0.08, 0.16, -0.06, 0.12, tile("white"), tile("white"), tc, 15, 0.0, 0.0, tc2)
				fbox(pb, d, -0.06, 1.06, -0.08, -0.02, 0.2, 0.26, tile("white"), tile("white"), Color("#e9c27a"), 15)
				for u in [-0.06, 1.0]:
					fbox(pb, d, u, u + 0.06, 0.08, 0.2, 0.2, 0.26, tile("white"), tile("white"), tc, 15, 0.0, 0.0, tc2)
			"metal":
				fbox(pb, d, -0.04, 1.04, -0.03, 0.03, -0.02, 0.18, tile("white"), tile("white"), Color("#5e7098"), 15, 0.0, 0.0, Color("#d6dee2"))
			"slab":
				fbox(pb, d, -0.1, 1.1, -0.1, 0.06, -0.02, 0.3, tile("white"), tile("white"), ViewCfg.col(ramp[1]), 15, 0.0, 0.0, ViewCfg.col(ramp[0]))


func _window_tile(style: String, fk: String) -> String:
	match style:
		"none":
			return ""
		"small", "std", "wide", "tall", "twin", "band", "full", "deep":
			return "win_%s_%s" % [style, fk]
		"lattice", "full_warm", "louvre", "cage", "slit":
			return "win_" + style
	return "win_std_" + fk


func _house_face(p: Vector3i, d: int, c: Dictionary, look: Dictionary, mat: String, seed_v: int, tier: int, wk: float) -> void:
	var hs := ViewCfg.h2(seed_v, 100 + d)
	var r1 := float(hs % 1000) / 1000.0
	var r2 := float((hs / 1000) % 1000) / 1000.0
	var r3 := float(ViewCfg.h2(hs, 7) % 1000) / 1000.0
	var wrnd := float(ViewCfg.h2(hs, 21) % 997) / 997.0
	var nb: Vector3i = p + DIR[d]
	var room2: bool = not state.cells.has(nb + DIR[d])
	var below_open: bool = p.z > 0 and not state.cells.has(nb - UPI) and float(col_h.get(Vector2i(nb.x, nb.y), 0.0)) < float(p.z) - 0.1
	var b := bld(c)
	var res := int(b.get("residents", 1))
	var lived := res > 0
	var clutter := float(look.get("clutter", 0.5))
	# 같은 건물(외관)·같은 층의 창은 같은 모양 → 이어진 건물로 읽힌다. T1만 칸마다 제멋대로.
	var wins: Array = look.get("win", ["std"])
	var frames: Array = look.get("frames", ["a"])
	var row_h := ViewCfg.h3(p.z, d % 2, look_key(c).hash()) if tier >= 2 else hs
	var style: String = str(wins[row_h % maxi(wins.size(), 1)]) if not wins.is_empty() else "std"
	var fk: String = str(frames[(row_h / 7) % maxi(frames.size(), 1)]) if not frames.is_empty() else "a"
	if tier == 1:
		style = str(wins[hs % maxi(wins.size(), 1)])
		fk = str(frames[ViewCfg.h2(p.x * 5 + p.y * 3 + (p.z / 3), 31) % maxi(frames.size(), 1)])
	var kw := wk if lived else MeshBuf.K_WINDOW_OFF
	var sk := Vector3i(p.x, p.y, d)

	# 배관(낮은 계층·철제 T3의 설비)
	var ph := ViewCfg.h3(p.x * 17 + p.y, d, 5)
	var pipe_p := 38.0 * clutter + (40.0 if look.get("equip_p", 0.0) > 0.5 else 0.0)
	if ph % 100 < int(pipe_p):
		var top_f := 1 + (ph / 100) % 9
		if p.z < top_f:
			var pu := 0.0625 + float((ph / 1000) % 2) * 0.8125
			var npipe := 1 + (ph / 7) % 2
			for i in npipe:
				var pc := Color(PIPES[(ph / 13 + i) % PIPES.size()])
				var uu := pu + float(i) * 0.125 * (1.0 if pu < 0.5 else -1.0)
				fbox(p, d, uu, uu + 0.0625, 0.0, 1.0, 0.0, 0.06, tile("white"), tile("white"), pc, 7)

	# 철제 T2·T3: 보강 프레임(모서리 기둥 + 층 보)
	if bool(look.get("frame_posts", false)):
		var fcol := Color("#4e5a7a") if tier <= 2 else Color("#3e4a6a")
		for u in [0.0, 0.9375]:
			var q: Vector3i = p - RGTI[d] if u < 0.5 else p + RGTI[d]
			if solid.has(q) and group_of(q) == group_of(p):
				continue
			fbox(p, d, u, u + 0.0625, 0.0, 1.0, 0.0, 0.07, tile("white"), tile("white"), fcol, 15, 0.0, 0.0, fcol.lightened(0.3))
		fbox(p, d, 0.0, 1.0, 0.94, 1.0, 0.0, 0.06, tile("white"), tile("white"), fcol, 15, 0.0, 0.0, fcol.lightened(0.3))

	# 층 띠(콘크리트·철제 T3+): 바닥판이 바깥으로 보인다 → 층이 또렷
	if bool(look.get("band", false)):
		var bc := ViewCfg.col(look.get("band_c", "#c9b0a8"), Color("#c9b0a8"))
		fbox(p, d, 0.0, 1.0, 0.0, 0.0625, 0.0, 0.045, tile("white"), tile("white"), bc, 15, 0.0, 0.0, bc.lightened(0.15))

	# 다리로 이어진 면: 문만
	if bridges.has(fkey(p, d)):
		fquad(p, d, 0, 1, 0, 1, EPS, tile("door_%d" % (hs % 4)), MeshBuf.WHITE, wrnd, kw)
		if d < 2:
			_bridge(p, d)
		return
	# 외벽 계단
	if stairs.has(sk):
		var rg: Array = stairs[sk]
		if p.z >= rg[0] and p.z < rg[1]:
			_stair_flight(p, d, p.z - int(rg[0]))
			fquad(p, d, 0, 1, 0, 1, EPS, tile("door_%d" % (hs % 4)), MeshBuf.WHITE, wrnd, kw)
			return
	# 지상 문(대문 쪽 면 하나)
	if p.z == 0 and room2 and hs % 3 == 0:
		fquad(p, d, 0, 1, 0, 1, EPS, tile("door_%d" % (hs % 4)), MeshBuf.WHITE, wrnd, kw)
		if tier >= 3:
			_awning(p, d, 0.15, 0.85, 0.86, 0.06, 0.18, ViewCfg.col(cfg.material(mat).get("ramp", ["#cccccc"])[0]).darkened(0.25))
		return

	# 반 칸 돌출(증축한 방): T1·T2만
	var bay := false
	var w0 := 0.0
	if p.z >= 1 and below_open and r3 < float(look.get("bay_p", 0.0)):
		bay = true
		var bms: Array = look.get("bay_mats", [mat])
		var bm: String = cfg.material_key(str(bms[(hs / 3) % maxi(bms.size(), 1)]))
		var depth := 0.3 + 0.0625 * float(hs % 3)
		var bu0 := 0.0625 * float((hs / 5) % 2)
		var bu1 := 1.0 - 0.0625 * float((hs / 11) % 2)
		fbox(p, d, bu0, bu1, 0.0, 1.0, 0.0, depth, tile("wall_%s_%d" % [bm, hs % 3]), tile("roof_%s_%d" % [bm, hs % 3]), MeshBuf.WHITE, 31)
		w0 = depth
	# 창
	var wt := _window_tile(style, fk)
	var has_win := wt != "" and (r1 < float(look.get("win_p", 1.0)) or bay)
	if not lived and tier == 1 and r2 < 0.5:
		wt = "win_board"
		has_win = true
	if has_win:
		fquad(p, d, 0, 1, 0, 1, w0 + EPS, tile(wt), MeshBuf.WHITE, wrnd, kw)
	if lived and (has_win or style == "none"):
		light(fp(p, d, 0.5, 0.5, w0 + 0.35), Color(1, 1, 1), 1.0, 0.55)
	if not lived:
		return
	# 발코니
	var bal: String = str(look.get("balcony", "none"))
	var bal_p := float(look.get("balcony_p", 0.0))
	var has_bal := false
	if not bay and p.z >= 1 and bal != "none":
		if bal == "cage":
			has_bal = r2 < bal_p
		else:
			# 이어지는 발코니: 같은 면·같은 층·같은 건물 줄 전체가 같이 정한다
			var run_k := ViewCfg.h3(p.z, d, (p.x if d % 2 == 0 else p.y) * 31 + look_key(c).hash())
			has_bal = float(run_k % 1000) / 1000.0 < bal_p
		if has_bal:
			_balcony(p, d, c, look, bal, hs)
	# 잡동사니(계층이 오를수록 줄어든다)
	if not has_bal and not bay:
		if r3 > 1.0 - 0.26 * clutter and p.z >= 1 and room2:
			_laundry_pole(p, d, hs, w0)
		elif r3 > 1.0 - 0.38 * clutter and electric(c):
			_ac(p, d, 0.56, 0.1, w0)
		if ViewCfg.h2(hs, 41) % 1000 < int(1000.0 * float(look.get("awning_p", 0.0))):
			var acs: Array = look.get("awning_c", ["#5d9a62", "#d85f5f", "#4f8fb5", "#e0a23c"])
			_awning(p, d, 0.15, 0.85, 0.82, 0.1, 0.2, ViewCfg.col(acs[hs % maxi(acs.size(), 1)]))
	if float(look.get("equip_p", 0.0)) > 0.0 and ViewCfg.h2(hs, 45) % 1000 < int(1000.0 * float(look.get("equip_p", 0.0))):
		_ac(p, d, 0.06 if hs % 2 == 0 else 0.56, 0.08, w0)
	if not has_bal and ViewCfg.h2(hs, 43) % 1000 < int(1000.0 * float(look.get("plants_p", 0.0))):
		_planter(p, d, hs, w0, tier)


func _planter(p: Vector3i, d: int, hs: int, w0: float, tier: int) -> void:
	var box_c := Color("#8a5a48") if tier < 4 else Color("#5a4a5e")
	fbox(p, d, 0.12, 0.88, 0.1, 0.22, w0, w0 + 0.14, tile("white"), tile("soil"), box_c, 15)
	var pr := tile("plant_%d" % (hs % 3))
	mb.quad2(fp(p, d, 0.14, 0.5, w0 + 0.08), fp(p, d, 0.86, 0.5, w0 + 0.08), fp(p, d, 0.86, 0.2, w0 + 0.08), fp(p, d, 0.14, 0.2, w0 + 0.08), NRM[d], sub(pr, 0, 6, 16, 10))


## 발코니 종류: cage(철망) / gallery(목조 회랑) / slab(콘크리트 공용 발코니) / deck(넓은 목조 테라스) / glass(유리 난간) / cantilever(두꺼운 내민 판)
func _balcony(p: Vector3i, d: int, c: Dictionary, look: Dictionary, bal: String, hs: int) -> void:
	if bal == "cage":
		_cage_balcony(p, d, hs)
		return
	var grp := group_of(p)
	var lcont := solid.has(p - RGTI[d]) and group_of(p - RGTI[d]) == grp and not solid.has(p - RGTI[d] + DIR[d])
	var rcont := solid.has(p + RGTI[d]) and group_of(p + RGTI[d]) == grp and not solid.has(p + RGTI[d] + DIR[d])
	var u0 := 0.0 if lcont else 0.06
	var u1 := 1.0 if rcont else 0.94
	var wmat: String = cfg.material_key(str(look.get("wall", "wood")))
	var ramp: Array = cfg.material(wmat).get("ramp", ["#cccccc", "#aaaaaa", "#888888", "#666666"])
	match bal:
		"gallery":
			var dep := 0.26
			var wood := Color("#a8704e")
			fbox(p, d, u0, u1, 0.0, 0.06, 0.0, dep, tile("plank"), tile("plank"), MeshBuf.WHITE, 31)
			fbox(p, d, u0, u1, 0.36, 0.4, dep - 0.03, dep, tile("white"), tile("white"), wood, 15)
			for u in [0.08, 0.5, 0.92]:
				if (u < 0.1 and lcont) or (u > 0.9 and rcont):
					continue
				fbox(p, d, u - 0.025, u + 0.025, 0.06, 1.0, dep - 0.05, dep, tile("white"), tile("white"), wood.darkened(0.15), 15)
			var rl := tile("rail")
			mb.quad2(fp(p, d, u0, 0.36, dep - 0.015), fp(p, d, u1, 0.36, dep - 0.015), fp(p, d, u1, 0.06, dep - 0.015), fp(p, d, u0, 0.06, dep - 0.015), NRM[d], sub(rl, 0, 6, (u1 - u0) * 16.0, 10), Color("#c08a5e"))
			if hs % 3 == 0:
				_laundry_line(p, d, hs, dep)
			# 지붕 처마(위 회랑의 바닥이 지붕 노릇) — 맨 위층이면 작은 차양
			if not solid.has(p + UPI):
				fbox(p, d, u0, u1, 0.96, 1.0, 0.0, dep + 0.04, tile("white"), tile("white"), wood.darkened(0.1), 15, 0.0, 0.0, Color("#c99466"))
		"slab":
			var dep2 := 0.24
			var sc := ViewCfg.col(ramp[1])
			fbox(p, d, u0, u1, 0.0, 0.08, 0.0, dep2, tile("white"), tile("white"), sc, 31, 0.0, 0.0, ViewCfg.col(ramp[0]))
			fbox(p, d, u0, u1, 0.08, 0.36, dep2 - 0.05, dep2, tile("wall_%s_0" % wmat), tile("white"), MeshBuf.WHITE, 15, 0.0, 0.0, ViewCfg.col(ramp[0]))
			if not lcont:
				fbox(p, d, u0, u0 + 0.05, 0.08, 0.36, 0.0, dep2, tile("white"), tile("white"), sc, 15)
			if not rcont:
				fbox(p, d, u1 - 0.05, u1, 0.08, 0.36, 0.0, dep2, tile("white"), tile("white"), sc, 15)
			if int(c.get("tier", 3)) <= 3:
				if hs % 2 == 0:
					_laundry_line(p, d, hs, dep2)
			elif hs % 2 == 0:
				var pr := tile("plant_%d" % (hs % 3))
				mb.quad2(fp(p, d, 0.15, 0.62, dep2 - 0.06), fp(p, d, 0.85, 0.62, dep2 - 0.06), fp(p, d, 0.85, 0.3, dep2 - 0.06), fp(p, d, 0.15, 0.3, dep2 - 0.06), NRM[d], sub(pr, 0, 4, 16, 12))
		"deck":
			var dep3 := 0.32
			fbox(p, d, u0, u1, 0.0, 0.07, 0.0, dep3, tile("white"), tile("plank"), Color("#7a4e40"), 31, 0.0, 0.0, MeshBuf.WHITE)
			# 가는 난간 + 화분
			fbox(p, d, u0, u1, 0.34, 0.38, dep3 - 0.025, dep3, tile("white"), tile("white"), Color("#5a3634"), 15)
			for u in [u0 + 0.03, u1 - 0.03]:
				fbox(p, d, u - 0.02, u + 0.02, 0.07, 0.36, dep3 - 0.03, dep3, tile("white"), tile("white"), Color("#5a3634"), 15)
			var pr2 := tile("plant_%d" % ((hs / 3) % 3))
			fbox(p, d, 0.1, 0.4, 0.07, 0.18, dep3 - 0.16, dep3 - 0.04, tile("white"), tile("soil"), Color("#6a4a40"), 15)
			mb.quad2(fp(p, d, 0.06, 0.58, dep3 - 0.1), fp(p, d, 0.46, 0.58, dep3 - 0.1), fp(p, d, 0.46, 0.18, dep3 - 0.1), fp(p, d, 0.06, 0.18, dep3 - 0.1), NRM[d], pr2)
			if hs % 2 == 0:
				cbox(fp(p, d, 0.62, 0.07, 0.1), fp(p, d, 0.8, 0.16, 0.22), Color("#e9e0cc"))
		"glass":
			var dep4 := 0.22
			fbox(p, d, u0, u1, 0.0, 0.05, 0.0, dep4, tile("white"), tile("white"), Color("#d6dee2"), 31, 0.0, 0.0, Color("#eef4f6"))
			mb.quad2(fp(p, d, u0, 0.34, dep4 - 0.01), fp(p, d, u1, 0.34, dep4 - 0.01), fp(p, d, u1, 0.05, dep4 - 0.01), fp(p, d, u0, 0.05, dep4 - 0.01), NRM[d], sub(tile("glass"), 0, 0, 16, 6), Color(0.85, 0.95, 1.0))
			fbox(p, d, u0, u1, 0.33, 0.36, dep4 - 0.02, dep4, tile("white"), tile("white"), Color("#eef4f6"), 15)
			if hs % 3 == 0:
				var pr3 := tile("plant_%d" % (hs % 3))
				mb.quad2(fp(p, d, 0.6, 0.5, dep4 - 0.08), fp(p, d, 0.9, 0.5, dep4 - 0.08), fp(p, d, 0.9, 0.05, dep4 - 0.08), fp(p, d, 0.6, 0.05, dep4 - 0.08), NRM[d], pr3)
		"cantilever":
			var dep5 := 0.36
			var cc := ViewCfg.col(ramp[1])
			fbox(p, d, u0, u1, -0.02, 0.12, 0.0, dep5, tile("white"), tile("white"), cc, 31, 0.0, 0.0, ViewCfg.col(ramp[0]))
			fbox(p, d, u0, u1, 0.12, 0.3, dep5 - 0.1, dep5, tile("white"), tile("soil"), cc.darkened(0.05), 15, 0.0, 0.0, MeshBuf.WHITE)
			var pr4 := tile("plant_%d" % (hs % 3))
			mb.quad2(fp(p, d, u0 + 0.04, 0.62, dep5 - 0.05), fp(p, d, u1 - 0.04, 0.62, dep5 - 0.05), fp(p, d, u1 - 0.04, 0.26, dep5 - 0.05), fp(p, d, u0 + 0.04, 0.26, dep5 - 0.05), NRM[d], sub(pr4, 0, 4, 16, 12))


func _laundry_line(p: Vector3i, d: int, hs: int, dep: float) -> void:
	var y := 0.78
	var u := 0.1
	var i := 0
	while u < 0.86:
		var cw := 0.14 + 0.06 * float((hs / (i + 3)) % 2)
		var cc := Color(LAUNDRY[(hs / (i * 5 + 1)) % LAUNDRY.size()])
		var chh := 0.24 + 0.08 * float((hs / (i + 7)) % 3)
		mb.cloth(fp(p, d, u, y, dep * 0.6), fp(p, d, u + cw, y, dep * 0.6), fp(p, d, u + cw, y - chh, dep * 0.6), fp(p, d, u, y - chh, dep * 0.6), NRM[d], sub(tile("white"), 0, 0, 4, 4), cc, float((hs + i * 31) % 100) / 100.0)
		u += cw + 0.05
		i += 1


func _house_rooftop(p: Vector3i, c: Dictionary, look: Dictionary, seed_v: int, tier: int) -> void:
	var base := cellv(p) + Vector3(0, fh, 0)
	var hs := ViewCfg.h2(seed_v, 500)
	var weights: Dictionary = look.get("roofprops", {}) if look.get("roofprops", {}) is Dictionary else {}
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	# 낮은 계층은 비어 있는 지붕도 많다, 높은 계층은 거의 늘 꾸민다
	var none_w := total * (0.55 if tier <= 2 else (0.3 if tier == 3 else 0.08)) + 0.2
	var pick := float(hs % 10000) / 10000.0 * (total + none_w)
	var what := ""
	for k in weights:
		pick -= float(weights[k])
		if pick < 0.0:
			what = str(k)
			break
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
		"garden":
			_roof_garden(base, hs, tier)
		"pergola":
			_roof_pergola(base, hs)
		"penthouse":
			_roof_penthouse(p, base, hs)
		"solar":
			_roof_solar(base, hs)
		"equipment":
			_roof_equipment(base, hs)
		"canopy":
			_roof_canopy(base, hs)
	if tier <= 2 and what != "antenna" and (hs / 13) % 100 < 5:
		_antennas(base, hs / 3, 1)


func _roof_garden(base: Vector3, hs: int, tier: int) -> void:
	# 흙판 + 덤불 + (T5) 작은 나무
	cbox(base + Vector3(0.08, 0, 0.08), base + Vector3(0.92, 0.08, 0.92), Color("#8a6a5a"), Color("#6a8a4a"))
	mb.quad(base + Vector3(0.12, 0.081, 0.12), base + Vector3(0.88, 0.081, 0.12), base + Vector3(0.88, 0.081, 0.88), base + Vector3(0.12, 0.081, 0.88), UP, sub(tile("crops_%d" % (hs % 3)), 1, 1, 12, 12))
	for i in 2 + hs % 2:
		_plantq(base + Vector3(0, 0.08, 0), 0.08 + 0.0625 * float((hs / (i + 2)) % 6), 0.18 + 0.28 * float(i), hs + i, i % 2 == 0, 0.34)
	if tier >= 5 or hs % 3 == 0:
		var tx := base.x + 0.3 + 0.0625 * float(hs % 5)
		var tz := base.z + 0.3 + 0.0625 * float((hs / 5) % 5)
		cbox(Vector3(tx, base.y + 0.08, tz), Vector3(tx + 0.07, base.y + 0.45, tz + 0.07), Color("#6a4a3e"))
		cbox(Vector3(tx - 0.16, base.y + 0.38, tz - 0.16), Vector3(tx + 0.23, base.y + 0.66, tz + 0.23), Color("#4f8a4e"), Color("#6fae5c"))
		cbox(Vector3(tx - 0.08, base.y + 0.66, tz - 0.08), Vector3(tx + 0.15, base.y + 0.8, tz + 0.15), Color("#5f9a52"), Color("#86c06a"))


func _roof_pergola(base: Vector3, hs: int) -> void:
	var wc := Color("#7a4e40")
	var top := 0.62
	cbox(base + Vector3(0.06, 0, 0.06), base + Vector3(0.94, 0.04, 0.94), Color("#a8704e"), Color("#c99466"))
	for q in [Vector3(0.1, 0, 0.1), Vector3(0.84, 0, 0.1), Vector3(0.1, 0, 0.84), Vector3(0.84, 0, 0.84)]:
		cbox(base + q, base + q + Vector3(0.06, top, 0.06), wc)
	for i in 5:
		var z := 0.1 + 0.17 * float(i)
		cbox(base + Vector3(0.06, top, z), base + Vector3(0.94, top + 0.04, z + 0.05), wc, Color("#a8704e"))
	# 넝쿨
	cbox(base + Vector3(0.1, top + 0.04, 0.1), base + Vector3(0.5, top + 0.08, 0.6), Color("#4f8a4e"), Color("#6fae5c"))
	if hs % 2 == 0:
		cbox(base + Vector3(0.4, 0.04, 0.4), base + Vector3(0.6, 0.18, 0.6), Color("#e9e0cc"))


func _roof_penthouse(p: Vector3i, base: Vector3, hs: int) -> void:
	# 뒤로 물러선 유리 상자 + 얇은 지붕판 + 작은 정원
	var x0 := 0.18
	var z0 := 0.18
	var hh := fh * 0.72
	var g := tile("wall_curtain_0") if atlas.has("wall_curtain_0") else tile("glass")
	mb.box(base + Vector3(x0, 0, z0), base + Vector3(0.82, hh, 0.82), Rect2(g.position + Vector2(0, 3), Vector2(16, 12)), tile("white"), fh, MeshBuf.WHITE, 15, float(hs % 997) / 997.0, MeshBuf.K_WINDOW)
	cbox(base + Vector3(0.1, hh, 0.1), base + Vector3(0.9, hh + 0.05, 0.9), Color("#a6b6c2"), Color("#eef4f6"))
	light(base + Vector3(0.5, hh * 0.5, 0.5), Color(1, 1, 1), 1.1, 0.6)
	_plantq(base, 0.0, 0.86, hs, true, 0.3)


func _roof_solar(base: Vector3, hs: int) -> void:
	var n := Vector3(0, 1, 0.45).normalized()
	for i in 2:
		var z := 0.12 + 0.4 * float(i)
		cbox(base + Vector3(0.12, 0, z + 0.26), base + Vector3(0.16, 0.16, z + 0.3), Color("#8a96aa"))
		cbox(base + Vector3(0.84, 0, z + 0.26), base + Vector3(0.88, 0.16, z + 0.3), Color("#8a96aa"))
		mb.quad(base + Vector3(0.1, 0.06, z), base + Vector3(0.9, 0.06, z), base + Vector3(0.9, 0.2, z + 0.3), base + Vector3(0.1, 0.2, z + 0.3), n, sub(tile("white"), 0, 0, 4, 4), Color("#3e5a9a"))
		mb.quad(base + Vector3(0.1, 0.2, z + 0.3), base + Vector3(0.9, 0.2, z + 0.3), base + Vector3(0.9, 0.06, z), base + Vector3(0.1, 0.06, z), -n, sub(tile("white"), 0, 0, 4, 4), Color("#5a6a8a"))


func _roof_equipment(base: Vector3, hs: int) -> void:
	for i in 2 + hs % 2:
		var x := 0.1 + 0.28 * float(i)
		var z := 0.15 + 0.0625 * float((hs / (i + 3)) % 6)
		wbox(base + Vector3(x, 0, z), base + Vector3(x + 0.22, 0.2, z + 0.28), "ac", "white", MeshBuf.WHITE, 31, 0.0, 0.0, Color("#e9e4d6"))
	cbox(base + Vector3(0.1, 0.02, 0.72), base + Vector3(0.9, 0.12, 0.82), Color("#8fb5d0"), Color("#a9cbea"))


func _roof_canopy(base: Vector3, hs: int) -> void:
	# 콘크리트 T5: 가는 기둥 위 얇은 판 + 그늘의 벤치
	var cc := Color("#c6baae")
	for q in [Vector3(0.12, 0, 0.12), Vector3(0.8, 0, 0.8)]:
		cbox(base + q, base + q + Vector3(0.07, fh * 0.6, 0.07), cc)
	cbox(base + Vector3(0.0, fh * 0.6, 0.0), base + Vector3(0.95, fh * 0.6 + 0.07, 0.95), cc, Color("#e0d6c6"))
	cbox(base + Vector3(0.3, 0, 0.5), base + Vector3(0.7, 0.1, 0.62), Color("#7a4e40"), Color("#a8704e"))
	_plantq(base, 0.5, 0.15, hs, true, 0.3)


func _scaffold_wrap(p: Vector3i, seed_v: int) -> void:
	# 승급 공사 중: 사람은 그대로 사는 집을 대나무 비계가 감싼다
	var sc := tile("scaffold")
	var nt := tile("net")
	var o := 0.1
	for d in 4:
		if solid.has(p + DIR[d]):
			continue
		mb.quad2(fp(p, d, -0.04, 1.1, o), fp(p, d, 1.04, 1.1, o), fp(p, d, 1.04, 0, o), fp(p, d, -0.04, 0, o), NRM[d], Rect2(sc.position, Vector2(16, 16)))
		var hsd := ViewCfg.h2(seed_v, d + 70)
		if hsd % 3 != 0:
			var u0 := 0.0 if hsd % 2 == 0 else 0.4
			mb.quad2(fp(p, d, u0, 0.7, o + 0.01), fp(p, d, u0 + 0.6, 0.7, o + 0.01), fp(p, d, u0 + 0.6, 0.1, o + 0.01), fp(p, d, u0, 0.1, o + 0.01), NRM[d], Rect2(nt.position, Vector2(9.6, 9.6)))
		cbox(fp(p, d, -0.04, 0.48, o - 0.08), fp(p, d, 1.04, 0.52, o + 0.04), BAMBOO_C)


# ================================================================== 골조(지지대)
## 셀 없는 골조 칸: 모서리 기둥 + 위 보 + 바깥면 엇갈린 가새. 속이 보이는 열린 구조.
func _build_support(p: Vector3i) -> void:
	var b := cellv(p)
	var ps := 0.13
	var h0 := b.y
	var h1 := b.y + fh
	var hs := ViewCfg.h3(p.x, p.y, p.z + 91)
	var bamboo := false
	# 골조는 콘크리트 기둥 + 철 보 + 철 가새 → 대나무 비계(공사)와 한눈에 갈린다
	var post_c := Color("#b4acbe")
	var post_t := Color("#d8d2de")
	# 모서리 기둥: 모서리를 공유하는 골조 칸 중 하나만 그린다
	for cx in [0, 1]:
		for cy in [0, 1]:
			var corner := Vector2i(p.x + cx, p.y + cy)
			var own := Vector3i(-99, 0, 0)
			for q in [Vector2i(corner.x - 1, corner.y - 1), Vector2i(corner.x, corner.y - 1), Vector2i(corner.x - 1, corner.y), Vector2i(corner.x, corner.y)]:
				if voids.has(Vector3i(q.x, q.y, p.z)):
					own = Vector3i(q.x, q.y, p.z)
					break
			if own != p:
				continue
			var x := float(corner.x) - ps * 0.5
			var z := float(corner.y) - ps * 0.5
			x = clampf(x, float(p.x) - 0.0, float(p.x + 1) - ps) if (corner.x == 0 or corner.x == gw) else x
			z = clampf(z, float(p.y) - 0.0, float(p.y + 1) - ps) if (corner.y == 0 or corner.y == gh) else z
			cbox(Vector3(x, h0, z), Vector3(x + ps, h1, z + ps), post_c, post_t, 15)
			if p.z == 0:
				cbox(Vector3(x - 0.04, h0, z - 0.04), Vector3(x + ps + 0.04, h0 + 0.06, z + ps + 0.04), Color("#a8a0b0"), Color("#c9c2cc"))
	# 위 보(가장자리마다 한 번): +x, +y 쪽은 늘, -x, -y 쪽은 이웃 골조가 없을 때만
	var beam_c := Color("#4e4a6e")
	for d in 4:
		var nb: Vector3i = p + DIR[d]
		if d >= 2 and voids.has(nb):
			continue
		fbox(p, d, 0.0, 1.0, 0.84, 1.0, -0.1, 0.0, tile("white"), tile("white"), beam_c, 15, 0.0, 0.0, Color("#7a74a0"))
		# 바깥면 가새(이웃이 골조도 셀도 아니면 = 바깥 공기에 드러난 면)
		if voids.has(nb) or state.cells.has(nb):
			continue
		var bc := Color("#5a5478") if (hs + d) % 4 != 0 else BAMBOO_C
		var flip := (hs / (d + 2)) % 2 == 0
		var w := -0.03
		var a0 := fp(p, d, 0.06, 0.0 if not flip else 0.86, w)
		var a1 := fp(p, d, 0.94, 0.86 if not flip else 0.0, w)
		_strut(a0, a1, NRM[d], bc, 0.07)
		if (hs / 7 + d) % 3 == 0:
			var c0 := fp(p, d, 0.06, 0.86 if not flip else 0.0, w - 0.01)
			var c1 := fp(p, d, 0.94, 0.0 if not flip else 0.86, w - 0.01)
			_strut(c0, c1, NRM[d], bc, 0.07)
		if p.z >= 1 and (hs / 5 + d) % 4 == 0:
			# 매달린 전선·등
			fbox(p, d, 0.48, 0.52, 0.5, 0.86, -0.06, -0.02, tile("white"), tile("white"), Color("#3a3448"), 15)
			fbox(p, d, 0.44, 0.56, 0.42, 0.5, -0.09, -0.01, tile("white"), tile("white"), Color("#ffd884"), 31)
			light(fp(p, d, 0.5, 0.45, 0.1), Color("#ffb060"), 0.8, 0.5)


## 두 점을 잇는 납작한 띠(가새). 벽면과 평행, 양면.
func _strut(a: Vector3, b: Vector3, n: Vector3, c: Color, wd: float) -> void:
	var along := (b - a).normalized()
	var side := along.cross(n).normalized() * wd * 0.5
	mb.quad(a + side, b + side, b - side, a - side, n, sub(tile("white"), 0, 0, 2, 2), c)
	mb.quad(b + side, a + side, a - side, b - side, -n, sub(tile("white"), 0, 0, 2, 2), c.darkened(0.2))


# ================================================================== 시설
func _front_of(p: Vector3i, seed_v: int) -> int:
	var best := -1
	var front := 1
	for k in 4:
		var d: int = (k + ViewCfg.h2(seed_v, 3)) % 4
		var nb: Vector3i = p + DIR[d]
		if not state.cells.has(nb):
			var score := 2 if not state.cells.has(nb + DIR[d]) else 1
			if d == 1:
				score += 1   # 대문 쪽(+y)을 조금 좋아한다
			if score > best:
				best = score
				front = d
	for d in 4:
		if signs.has(fkey(p, d)):
			front = d   # 간판이 걸린 면이 곧 가게 앞
	return front


func _fac_wall(rec: Dictionary) -> String:
	return cfg.material_key(str(rec.get("wall", "render")))


## 1×1 상자 시설(그리고 2×2의 각 칸): 벽 + 앞면(가게창·셔터·간판) + 지붕.
func _build_fac_box(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int, front: int, big: bool = false) -> void:
	var mat := _fac_wall(rec)
	var b := bld(c)
	var active := bool(b.get("active", true))
	if front < 0:
		front = _front_of(p, seed_v)
	var base := cellv(p)
	var glass_wall: bool = str(cfg.material(mat).get("pattern", "")) == "curtain"
	for d in 4:
		var nb2: Vector3i = p + DIR[d]
		if solid.has(nb2):
			continue
		var wr := tile("wall_%s_%d" % [mat, ViewCfg.h2(seed_v, d) % 2])
		mb.quad(fp(p, d, 0, 1, 0), fp(p, d, 1, 1, 0), fp(p, d, 1, 0, 0), fp(p, d, 0, 0, 0), NRM[d], wr, MeshBuf.WHITE, float(ViewCfg.h2(seed_v, d) % 991) / 991.0, MeshBuf.K_BIZ if glass_wall else 0.0)
		if state.cells.has(nb2):
			continue
		_fac_face(p, d, c, rec, mat, seed_v, d == front, big, active)
	var above: Vector3i = p + UPI
	if not solid.has(above):
		var rr := tile("roof_%s_%d" % [mat, ViewCfg.h2(seed_v, 9) % 3])
		var y := base.y + fh
		mb.quad(Vector3(base.x, y, base.z), Vector3(base.x + 1, y, base.z), Vector3(base.x + 1, y, base.z + 1), Vector3(base.x, y, base.z + 1), UP, rr)
		# 시설 지붕 테두리(건물 하나로 읽히게: 같은 시설끼리는 이어진다)
		var grp := group_of(p)
		var ramp: Array = cfg.material(mat).get("ramp", ["#cccccc", "#aaaaaa"])
		for d in 4:
			var nb: Vector3i = p + DIR[d]
			if solid.has(nb + UPI) or (solid.has(nb) and group_of(nb) == grp):
				continue
			fbox(Vector3i(p.x, p.y, p.z + 1), d, 0.0, 1.0, 0.0, 0.09, -0.0625, 0.0, tile("white"), tile("white"), ViewCfg.col(ramp[1]), 15, 0.0, 0.0, ViewCfg.col(ramp[0]))
		if not state.cells.has(above) and chimney_cols.has(Vector2i(p.x, p.y)):
			_rooftop_chimney(p, seed_v, active)


func _fac_face(p: Vector3i, d: int, c: Dictionary, rec: Dictionary, mat: String, seed_v: int, is_front: bool, big: bool, active: bool) -> void:
	var hs := ViewCfg.h2(seed_v, 100 + d)
	var r1 := float(hs % 1000) / 1000.0
	var wrnd := float(ViewCfg.h2(hs, 21) % 997) / 997.0
	var ground := p.z == 0
	var win: String = str(rec.get("window", "shop"))
	var frames: Array = cfg.material(mat).get("frames", ["a"])
	var fk: String = str(frames[hs % maxi(frames.size(), 1)]) if not frames.is_empty() else "a"
	var wkind := MeshBuf.K_BIZ
	if is_front:
		var wt := "shop_a"
		match win:
			"shop":
				wt = ["shop_a", "shop_c", "shop_b"][hs % 3]
			"shutter":
				wt = "shutter_0" if active else "shutter_1"
			"slit":
				wt = "win_slit"
			"none":
				wt = ""
			"full":
				wt = "win_full_e"
			"small", "wide", "std":
				wt = "win_%s_%s" % [win, fk]
		if wt != "":
			fquad(p, d, 0, 1, 0, 1, EPS, tile(wt), MeshBuf.WHITE, wrnd, wkind)
		if (win == "slit" or win == "none" or win == "wide" or win == "std") and ground:
			fquad(p, d, 0, 1, 0, 1, EPS * 1.5, tile("door_%d" % (hs % 4)), MeshBuf.WHITE, wrnd, wkind)
		var aw: String = str(rec.get("awning", ""))
		if aw != "" and (ground or r1 < 0.5):
			_awning(p, d, 0.03, 0.97, 0.72, 0.16, 0.34, ViewCfg.col(aw))
		if not big and signs.has(fkey(p, d)):
			_sign(p, d, c, rec, seed_v, str(signs[fkey(p, d)]))
		var fx: String = str(rec.get("fx", ""))
		if fx == "steam" and active:
			emitter(fp(p, d, 0.8, 0.9, 0.12), "steam")
			fbox(p, d, 0.75, 0.875, 0.8, 0.95, 0.0, 0.12, tile("white"), tile("white"), Color("#8f8ea6"), 15)
		elif fx == "sparks" and active:
			emitter(fp(p, d, 0.5, 0.3, 0.2), "sparks")
		if active:
			var glow: String = str(rec.get("glow", ""))
			if glow != "":
				light(fp(p, d, 0.5, 0.4, 0.4), cfg.neon(glow), 1.6)
			else:
				light(fp(p, d, 0.5, 0.45, 0.35), Color(1, 1, 1), 1.2, 0.8)
	else:
		if win != "none" and r1 < 0.55:
			var t2 := "win_slit" if win == "slit" else ("win_small_" + fk)
			fquad(p, d, 0, 1, 0, 1, EPS, tile(t2), MeshBuf.WHITE, wrnd, wkind)
		if r1 > 0.8 and power_on:
			_ac(p, d, 0.56, 0.12)


func _rooftop_chimney(p: Vector3i, seed_v: int, active: bool) -> void:
	var base := cellv(p) + Vector3(0, fh, 0)
	var hs := ViewCfg.h2(seed_v, 500)
	var cx := base.x + 0.125 + 0.5 * float(hs % 2)
	var cz := base.z + 0.125 + 0.5 * float((hs / 2) % 2)
	var chh := fh * (0.8 + 0.2 * float(hs % 3))
	wbox(Vector3(cx, base.y, cz), Vector3(cx + 0.25, base.y + chh, cz + 0.25), "wall_brick_1" if atlas.has("wall_brick_1") else "white", "white", MeshBuf.WHITE, 31, 0.0, 0.0, Color("#4a4160"))
	cbox(Vector3(cx - 0.03, base.y + chh, cz - 0.03), Vector3(cx + 0.28, base.y + chh + 0.06, cz + 0.28), Color("#8f8aa6"))
	if active:
		emitter(Vector3(cx + 0.125, base.y + chh + 0.1, cz + 0.125), str(chimney_cols.get(Vector2i(p.x, p.y), "smoke")))


## 시설 소품: 지붕(위가 비었을 때)과 앞(디딜 바닥이 있을 때). 레시피의 props 목록.
func _fac_props(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int, front: int) -> void:
	var props: Array = rec.get("props", []) if rec.get("props", []) is Array else []
	if props.is_empty():
		return
	var b := bld(c)
	var active := bool(b.get("active", true))
	var hs := ViewCfg.h2(seed_v, 650)
	var roof_free := not state.cells.has(p + UPI) and not voids.has(p + UPI)
	var top := cellv(p) + Vector3(0, fh, 0)
	var nb: Vector3i = p + DIR[front]
	var front_ok := not state.cells.has(nb) and not voids.has(nb) and (p.z == 0 or solid.has(nb - UPI))
	for pr in props:
		match str(pr):
			"tanks":
				if roof_free:
					_roof_tank(top, hs)
			"mast":
				if roof_free:
					_mast(top + Vector3(0.5, 0, 0.5), hs, active)
			"antennas":
				if roof_free:
					_antennas(top, hs, 3)
			"racks":
				if roof_free:
					_racks(top, hs)
			"dish":
				if roof_free:
					_dish(top + Vector3(0.3, 0, 0.3))
			"pipes":
				var d2 := (front + 1) % 4
				if not solid.has(p + DIR[d2]):
					for i in 2:
						fbox(p, d2, 0.2 + 0.2 * float(i), 0.3 + 0.2 * float(i), 0.0, 1.0, 0.0, 0.1, tile("white"), tile("white"), Color(PIPES[(hs + i) % PIPES.size()]), 7)
					fbox(p, d2, 0.1, 0.9, 0.7, 0.8, 0.0, 0.1, tile("white"), tile("white"), Color("#8fb5d0"), 15)
			"transformer":
				if front_ok:
					var a := fp(p, front, 0.62, 0.0, 0.06)
					cbox(a + Vector3(-0.15, 0, -0.15), a + Vector3(0.15, 0.36, 0.15), Color("#7a8a6a"), Color("#9aaa8a"))
					cbox(a + Vector3(-0.04, 0.36, -0.04), a + Vector3(0.04, 0.5, 0.04), Color("#e9e0cc"))
					if active:
						light(a + Vector3(0, 0.3, 0), cfg.neon("yellow"), 0.8)
				elif roof_free:
					cbox(top + Vector3(0.3, 0, 0.3), top + Vector3(0.7, 0.36, 0.7), Color("#7a8a6a"), Color("#9aaa8a"))
			"vats":
				if front_ok:
					var a2 := fp(p, front, 0.75, 0.0, 0.25)
					wbox(a2 + Vector3(-0.14, 0, -0.14), a2 + Vector3(0.14, 0.26, 0.14), "steel_side", "vat")
					if active:
						emitter(a2 + Vector3(0, 0.3, 0), "steam")
			"jars":
				if front_ok:
					for i in 3:
						var a3 := fp(p, front, 0.2 + 0.22 * float(i), 0.0, 0.16)
						cbox(a3 + Vector3(-0.07, 0, -0.07), a3 + Vector3(0.07, 0.16, 0.07), Color("#8a5a3e"), Color("#3a2a2e"))
			"bolts":
				if front_ok:
					var a4 := fp(p, front, 0.7, 0.0, 0.14)
					cbox(a4 + Vector3(-0.16, 0, -0.08), a4 + Vector3(0.16, 0.05, 0.08), Color("#7a4e40"))
					var bc := ["#d85f5f", "#5f86c4", "#e0a23c", "#5fae7a", "#f4f0e6"]
					for i in 4:
						var x := -0.15 + 0.08 * float(i)
						cbox(a4 + Vector3(x, 0.05, -0.06), a4 + Vector3(x + 0.07, 0.3 + 0.04 * float(i % 2), 0.06), Color(bc[(hs + i) % bc.size()]))
			"crates":
				if front_ok:
					var a5 := fp(p, front, 0.2 if hs % 2 == 0 else 0.8, 0.0, 0.15)
					wbox(a5 + Vector3(-0.13, 0, -0.1), a5 + Vector3(0.13, 0.22, 0.14), "crate", "crate")
					wbox(a5 + Vector3(-0.1, 0.22, -0.07), a5 + Vector3(0.08, 0.38, 0.1), "crate", "crate")
				elif roof_free:
					_roof_junk(top, hs)
			"lanterns":
				var lr := tile("lantern")
				mb.quad2(fp(p, front, 0.05, 0.98, 0.3), fp(p, front, 0.95, 0.98, 0.3), fp(p, front, 0.95, 0.66, 0.3), fp(p, front, 0.05, 0.66, 0.3), NRM[front], sub(lr, 0, 0, 16, 8))
				if active:
					light(fp(p, front, 0.5, 0.8, 0.4), Color("#ff6a4a"), 1.3)
			"stack":
				pass   # chimney_cols가 처리
			"planters":
				if front_ok:
					_planter(p, front, hs, 0.0, 5)


func _mast(a: Vector3, hs: int, active: bool) -> void:
	# 탐험 거점: 무전 안테나 탑(격자) + 깃발
	var hgt := fh * 1.6
	var w := 0.12
	for q in [Vector3(-w, 0, -w), Vector3(w - 0.03, 0, -w), Vector3(-w, 0, w - 0.03), Vector3(w - 0.03, 0, w - 0.03)]:
		var t: Vector3 = q * 0.35
		mb.quad2(a + q + Vector3(0, 0, 0), a + q + Vector3(0.03, 0, 0), a + t + Vector3(0.03, hgt, 0), a + t + Vector3(0, hgt, 0), Vector3(0, 0, 1), sub(tile("white"), 0, 0, 2, 2), Color("#c2463c"))
	for i in 4:
		var y := hgt * (0.2 + 0.2 * float(i))
		var k := 1.0 - 0.65 * float(i + 1) / 5.0
		cbox(a + Vector3(-w * k, y, -w * k), a + Vector3(w * k, y + 0.025, w * k), Color("#e9e0cc"))
	mb.quad2(a + Vector3(0, hgt, 0), a + Vector3(0.3, hgt - 0.05, 0), a + Vector3(0.3, hgt - 0.2, 0), a + Vector3(0, hgt - 0.15, 0), Vector3(0, 0, 1), sub(tile("white"), 0, 0, 2, 2), Color("#5fae7a"))
	if active:
		light(a + Vector3(0, hgt, 0), cfg.neon("red"), 0.7)


func _racks(base: Vector3, hs: int) -> void:
	# 국수·초 말리는 시렁: 기둥 두 개 + 가로대 + 늘어진 가닥
	for x in [0.15, 0.8]:
		cbox(base + Vector3(x, 0, 0.2), base + Vector3(x + 0.05, 0.55, 0.25), Color("#a8704e"))
		cbox(base + Vector3(x, 0, 0.7), base + Vector3(x + 0.05, 0.55, 0.75), Color("#a8704e"))
	for z in [0.22, 0.72]:
		cbox(base + Vector3(0.15, 0.5, z), base + Vector3(0.85, 0.54, z + 0.03), Color("#a8704e"))
		var i := 0
		var x2 := 0.2
		while x2 < 0.8:
			mb.cloth(base + Vector3(x2, 0.5, z + 0.015), base + Vector3(x2 + 0.05, 0.5, z + 0.015), base + Vector3(x2 + 0.05, 0.22, z + 0.015), base + Vector3(x2, 0.22, z + 0.015), Vector3(0, 0, 1), sub(tile("white"), 0, 0, 2, 4), Color("#f6e6b8"), float((hs + i * 17) % 100) / 100.0)
			x2 += 0.08
			i += 1


func _dish(a: Vector3) -> void:
	cbox(a, a + Vector3(0.05, 0.25, 0.05), Color("#8a96aa"))
	var n := Vector3(0.5, 0.4, 0.5).normalized()
	mb.quad2(a + Vector3(-0.15, 0.45, 0.1), a + Vector3(0.1, 0.45, -0.15), a + Vector3(0.15, 0.15, -0.05), a + Vector3(-0.05, 0.15, 0.15), n, sub(tile("white"), 0, 0, 4, 4), Color("#e9edf2"))


# ------------------------------------------------------------------ 2×2 시설
func _build_big(o: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int) -> void:
	var cells: Array[Vector3i] = [o, o + Vector3i(1, 0, 0), o + Vector3i(0, 1, 0), o + Vector3i(1, 1, 0)]
	var b := bld(c)
	var active := bool(b.get("active", true))
	# 앞면: 트인 칸이 가장 많은 변(대문 쪽 우선)
	var best := -1
	var front := 1
	for d in [1, 0, 2, 3]:
		var open := 0
		for q in cells:
			var nb: Vector3i = q + DIR[d]
			if not cells.has(nb) and not state.cells.has(nb):
				open += 2 if not state.cells.has(nb + DIR[d]) else 1
		if open > best:
			best = open
			front = d
	var fcells: Array = []
	for q in cells:
		var nbq: Vector3i = q + DIR[front]
		if not cells.has(nbq):
			fcells.append(q)
	for q in cells:
		mb.owner = owner_of(o)
		_build_fac_box(q, c, rec, seed_v + q.x * 3 + q.y * 5, front if fcells.has(q) else (front + 2) % 4, true)
	# 앞 두 칸: 왼쪽(u=0 쪽) 칸 찾기
	var lft: Vector3i = fcells[0]
	if fcells.size() > 1:
		var q1: Vector3i = fcells[1]
		if (q1 - lft) == -RGTI[front]:
			lft = q1
	var kind: String = str(rec.get("big", "block"))
	var roof_free := true
	for q in cells:
		if state.cells.has(q + UPI) or voids.has(q + UPI):
			roof_free = false
	var top := cellv(o) + Vector3(0, fh, 0)
	match kind:
		"market":
			# 긴 차양 + 앞의 좌판 줄
			var ac := ViewCfg.col(rec.get("awning", "#d85f5f"), Color("#d85f5f"))
			var r := tile("awning")
			for i in 2:
				var q2: Vector3i = lft + RGTI[front] * i
				_awning(q2, front, 0.0, 1.0, 0.7, 0.2, 0.45, ac)
			if o.z == 0 or solid.has(lft + DIR[front] - UPI):
				for i in 3:
					var a := fp(lft, front, 0.25 + 0.75 * float(i), 0.0, 0.3)
					wbox(a + Vector3(-0.16, 0, -0.1), a + Vector3(0.16, 0.24, 0.1), "crate", ["crops_0", "noodles", "mj_table"][(seed_v + i) % 3])
			if roof_free:
				_roof_tank(top + Vector3(0.9, 0, 0.9), seed_v)
		"plant", "works", "bath":
			if roof_free:
				var nst := 2 if kind == "plant" else 1
				for i in nst:
					var sx := top.x + 0.35 + 0.9 * float(i)
					var sz := top.z + 0.5 + 0.6 * float(i)
					var shh := fh * (1.7 if kind == "plant" else 1.0)
					wbox(Vector3(sx, top.y, sz), Vector3(sx + 0.36, top.y + shh, sz + 0.36), "wall_brick_1" if atlas.has("wall_brick_1") else "white", "white", MeshBuf.WHITE, 31, 0.0, 0.0, Color("#3a3448"))
					cbox(Vector3(sx - 0.03, top.y + shh * 0.8, sz - 0.03), Vector3(sx + 0.39, top.y + shh * 0.85, sz + 0.39), Color("#e9e0cc"))
					cbox(Vector3(sx - 0.03, top.y + shh * 0.6, sz - 0.03), Vector3(sx + 0.39, top.y + shh * 0.65, sz + 0.39), Color("#c2463c"))
					if active:
						emitter(Vector3(sx + 0.18, top.y + shh + 0.1, sz + 0.18), str(rec.get("fx", "smoke")))
				if kind != "plant" or (rec.get("props", []) as Array).has("tanks"):
					_roof_tank(top + Vector3(1.1, 0, 0.1), seed_v)
				# 배관 다발
				cbox(top + Vector3(0.1, 0.05, 1.7), top + Vector3(1.9, 0.15, 1.8), Color("#8fb5d0"), Color("#a9cbea"))
				cbox(top + Vector3(0.1, 0.05, 1.52), top + Vector3(1.9, 0.12, 1.6), Color("#b5654f"), Color("#d08060"))
		"casino":
			# 앞면 테두리 네온 관 + 등롱
			for i in 2:
				var q3: Vector3i = lft + RGTI[front] * i
				fbox(q3, front, 0.0, 1.0, 0.96, 1.0, 0.0, 0.05, tile("white"), tile("white"), cfg.neon("magenta"), 15, float(seed_v % 97) / 97.0, MeshBuf.K_NEON)
				fbox(q3, front, 0.0, 1.0, 0.0, 0.04, 0.0, 0.05, tile("white"), tile("white"), cfg.neon("yellow"), 15, float(seed_v % 89) / 89.0, MeshBuf.K_NEON)
			if roof_free:
				_roof_equipment(top, seed_v)
				_roof_equipment(top + Vector3(1, 0, 1), seed_v / 3)
		"hall":
			if roof_free:
				_hall_roof(o, top, front, seed_v)
			# 붉은 기둥 두 쌍(앞)
			for i in 2:
				var q4: Vector3i = lft + RGTI[front] * i
				for u in [0.12, 0.88]:
					fbox(q4, front, u - 0.05, u + 0.05, 0.0, 1.0, 0.0, 0.3, tile("white"), tile("white"), Color("#b0303a"), 15, 0.0, 0.0, Color("#d04a4a"))
			light(fp(lft, front, 1.0, 0.5, 0.5), Color("#ff8a4a"), 2.2)
		_:
			if roof_free:
				_roof_equipment(top + Vector3(0.5, 0, 0.5), seed_v)
	if kind != "hall" or true:
		_big_sign(lft, front, c, rec, seed_v, kind)
	if roof_free and kind != "hall" and kind != "plant":
		pass


## 2×2 건물의 큰 간판 하나: 앞면 두 칸에 걸친 가로판(글자 1:1).
func _big_sign(lft: Vector3i, d: int, c: Dictionary, rec: Dictionary, seed_v: int, kind: String) -> void:
	var text := cfg.sign_text(str(c.get("type", "")))
	if text == "":
		return
	var style: String = str(rec.get("sign_style", "paint"))
	var col := cfg.neon(rec.get("sign_color", "yellow"))
	var tr := Rect2(atlas.sign_rect(text, false))
	if tr.size.x <= 0.0:
		return
	var neon_style := style == "neon"
	var gw_t := tr.size.x
	var gh_t := tr.size.y
	var bw := (gw_t + 6.0) / 16.0
	var bh := (gh_t + 4.0) / 16.0
	var u0 := 1.0 - bw * 0.5    # 두 칸 폭(0..2)의 가운데
	var v0 := 1.0 - bh - 0.02
	if kind == "hall":
		v0 = 0.5 - bh * 0.5   # 회관: 붉은 기둥 사이, 처마 아래 가운데
	var board := Color("#3a2a3e") if neon_style else (Color("#b0303a") if kind == "hall" else Color("#f4ecd8"))
	var tcol := col if neon_style else (Color("#f2d27a") if kind == "hall" else Color("#c2463c"))
	var tk := MeshBuf.K_NEON if neon_style else MeshBuf.K_PLAIN
	var rnd := float(seed_v % 991) / 991.0
	# 판(조금 내밀어 단다)
	var wo := 0.0 if kind != "hall" else 0.0
	fbox(lft, d, u0, u0 + bw, v0, v0 + bh, wo, wo + 0.08, tile("white"), tile("white"), board, 31)
	if neon_style:
		fbox(lft, d, u0 - 0.03, u0 + bw + 0.03, v0 - 0.03, v0, 0.0, 0.09, tile("white"), tile("white"), col, 15, rnd, MeshBuf.K_NEON)
		fbox(lft, d, u0 - 0.03, u0 + bw + 0.03, v0 + bh, v0 + bh + 0.03, 0.0, 0.09, tile("white"), tile("white"), col, 15, rnd, MeshBuf.K_NEON)
	var tu0 := u0 + 3.0 / 16.0
	var tv0 := v0 + 2.0 / 16.0
	mb.quad(fp(lft, d, tu0, tv0 + gh_t / 16.0, 0.085), fp(lft, d, tu0 + gw_t / 16.0, tv0 + gh_t / 16.0, 0.085), fp(lft, d, tu0 + gw_t / 16.0, tv0, 0.085), fp(lft, d, tu0, tv0, 0.085), NRM[d], tr, tcol, rnd, tk)
	if neon_style:
		light(fp(lft, d, 1.0, v0 + bh * 0.5, 0.4), col, 2.4)


func _hall_roof(o: Vector3i, top: Vector3, front: int, seed_v: int, sx: float = 2.0, sz: float = 2.0) -> void:
	# 성채 회관: 두 겹 처마 지붕 + 금빛 용마루(발자국 크기에 맞춘다)
	var tc := Color("#3f6a5a")
	var tc2 := Color("#5a8a72")
	var gold := Color("#f2d27a")
	var e := Vector3(sx, 0, sz)
	cbox(top + Vector3(-0.15, 0, -0.15), top + e + Vector3(0.15, 0.1, 0.15), tc, tc2)
	cbox(top + Vector3(0.1, 0.1, 0.1), top + e + Vector3(-0.1, fh * 0.5, -0.1), Color("#b0303a"), Color("#d04a4a"))
	cbox(top + Vector3(-0.05, fh * 0.5, -0.05), top + e + Vector3(0.05, fh * 0.5 + 0.1, 0.05), tc, tc2)
	cbox(top + Vector3(0.25, fh * 0.5 + 0.1, 0.25), top + e + Vector3(-0.25, fh * 0.5 + 0.22, -0.25), tc, tc2)
	cbox(top + Vector3(0.5, fh * 0.5 + 0.22, 0.5), top + e + Vector3(-0.5, fh * 0.5 + 0.34, -0.5), tc, tc2)
	if sx >= sz:
		cbox(top + Vector3(0.45, fh * 0.5 + 0.34, sz * 0.5 - 0.05), top + Vector3(sx - 0.45, fh * 0.5 + 0.42, sz * 0.5 + 0.05), gold)
	else:
		cbox(top + Vector3(sx * 0.5 - 0.05, fh * 0.5 + 0.34, 0.45), top + Vector3(sx * 0.5 + 0.05, fh * 0.5 + 0.42, sz - 0.45), gold)
	for q in [Vector3(-0.15, 0.1, -0.15), Vector3(sx + 0.05, 0.1, -0.15), Vector3(-0.15, 0.1, sz + 0.05), Vector3(sx + 0.05, 0.1, sz + 0.05)]:
		cbox(top + q, top + q + Vector3(0.1, 0.1, 0.1), gold)
	var lr := tile("lantern")
	var n := int(sx * 1.5)
	for i in n:
		var x := 0.2 + (sx - 0.6) * float(i) / float(maxi(n - 1, 1))
		mb.quad2(top + Vector3(x, -0.02, sz + 0.16), top + Vector3(x + 0.3, -0.02, sz + 0.16), top + Vector3(x + 0.3, -0.25, sz + 0.16), top + Vector3(x, -0.25, sz + 0.16), Vector3(0, 0, 1), sub(lr, 0, 0, 16, 8))
	var n2 := int(sz * 1.5)
	for i in n2:
		var x2 := 0.2 + (sz - 0.6) * float(i) / float(maxi(n2 - 1, 1))
		mb.quad2(top + Vector3(sx + 0.16, -0.02, x2 + 0.3), top + Vector3(sx + 0.16, -0.02, x2), top + Vector3(sx + 0.16, -0.25, x2), top + Vector3(sx + 0.16, -0.25, x2 + 0.3), Vector3(1, 0, 0), sub(lr, 0, 0, 16, 8))
	light(top + Vector3(sx * 0.5, 0.2, sz + 0.1), Color("#ff6a4a"), 1.8)
	light(top + Vector3(sx * 0.5, fh * 0.4, sz * 0.5), Color("#ffb060"), 1.6)


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




# ------------------------------------------------------------------ 간판(1×1 시설)
# 간판은 "건물 하나에 하나"(가장 트인 외벽면). 2×2는 _big_sign이 따로 단다.
# 크기 4종: big(큰 세로 돌출) / blade(작은 돌출) / plaque(문 옆 작은 세로판) / board(문 위 작은 가로판)
func _alloc_signs() -> void:
	signs.clear()
	var cands: Array = []
	for p in state.cells:
		var c: Dictionary = state.cells[p]
		if true:
			continue   # v4: 시설 간판은 FacilityBuilder가 건물마다 하나 단다
		var rec: Dictionary = recipe_of(c)
		var style: String = str(rec.get("sign_style", "none"))
		if style == "none":
			continue
		var text := cfg.sign_text(str(c.get("type", "")))
		if text == "" and style != "lantern":
			continue
		var best_s := -1.0
		var best_d := 0
		var best_open := 0
		for d in 4:
			var nb: Vector3i = p + DIR[d]
			if state.cells.has(nb) or voids.has(nb):
				continue
			var open := 1
			for k in [2, 3]:
				var q: Vector3i = p + DIR[d] * k
				if state.cells.has(q) or float(col_h.get(Vector2i(q.x, q.y), 0.0)) > float(p.z) + 0.5:
					break
				open += 1
			var sc := float(open) * 10.0 + (6.0 if p.z == 0 else 0.0) + (3.0 if d == 1 else 0.0) + float(ViewCfg.h3(p.x * 9 + p.y, p.z, d) % 40) / 10.0
			if sc > best_s:
				best_s = sc
				best_d = d
				best_open = open
		if best_s >= 0.0:
			cands.append({"p": p, "d": best_d, "open": best_open, "score": best_s, "text": text, "seed": int(c.get("seed", 0))})
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["score"] != y["score"]:
			return x["score"] > y["score"]
		return x["p"] < y["p"])
	var placed: Array = []
	for cd in cands:
		var p: Vector3i = cd["p"]
		var d: int = cd["d"]
		var hs := ViewCfg.h2(int(cd["seed"]), 300 + d)
		var big_near := false
		for pl in placed:
			var q: Vector3i = pl["p"]
			if pl["size"] == "big" and absi(q.x - p.x) + absi(q.y - p.y) <= 2 and absi(q.z - p.z) <= 3:
				big_near = true
		var size := "plaque"
		var r := hs % 100
		if int(cd["open"]) >= 2 and r < 35 and not big_near:
			size = "big"
		elif int(cd["open"]) >= 2 and r < 70:
			size = "blade"
		elif r < 88:
			size = "board"
		signs[fkey(p, d)] = size
		placed.append({"p": p, "d": d, "text": cd["text"], "size": size})


func _sign(p: Vector3i, d: int, c: Dictionary, rec: Dictionary, seed_v: int, size: String) -> void:
	var type: String = str(c.get("type", ""))
	var style: String = str(rec.get("sign_style", "none"))
	var text := cfg.sign_text(type)
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
	if text.length() >= 3 and size == "big":
		sc = 0.75 if text.length() <= 4 else 0.5
	var board := _neon_board(col, hs) if neon_style else Color(["#f4ecd8", "#c2463c", "#3f8f6a", "#f4ecd8"][hs % 4])
	var tcol := col
	if not neon_style:
		tcol = Color("#c2463c") if board.r > 0.9 else Color("#fff6e0")
		if board.r > 0.9 and hs % 3 == 0:
			tcol = Color("#3b3558")
	var tk := MeshBuf.K_NEON if neon_style else MeshBuf.K_PLAIN
	var rnd := float(hs % 991) / 991.0
	var gw_t := tr.size.x * sc
	var gh_t := tr.size.y * sc
	if size == "big" or size == "blade":
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


# ------------------------------------------------------------------ 옥상 소품
func _antennas(base: Vector3, hs: int, max_n: int = 2) -> void:
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
		"rain":
			# 빗물받이: 깔때기 천막 + 물통 + 홈통
			_topquad(b, 0, 0, 1, 1, 0.012, tile("g_slab"))
			for q in [Vector3(0.1, 0, 0.1), Vector3(0.84, 0, 0.1), Vector3(0.1, 0, 0.84), Vector3(0.84, 0, 0.84)]:
				cbox(b + q, b + q + Vector3(0.06, 0.62, 0.06), Color("#8a7a6a"))
			var tc := Color("#5f86c4") if hs % 2 == 0 else Color("#4fae9c")
			var cn := b + Vector3(0.5, 0.36, 0.5)
			var cs := [b + Vector3(0.06, 0.66, 0.06), b + Vector3(0.94, 0.66, 0.06), b + Vector3(0.94, 0.66, 0.94), b + Vector3(0.06, 0.66, 0.94)]
			for i in 4:
				var p0: Vector3 = cs[i]
				var p1: Vector3 = cs[(i + 1) % 4]
				var nn := (p1 - p0).cross(cn - p0).normalized()
				if nn.y < 0.0:
					nn = -nn
				mb.quad(p0, p1, cn, cn, nn, sub(tile("white"), 0, 0, 4, 4), tc.lightened(0.1 * float(i % 2)))
				mb.quad(p1, p0, cn, cn, -nn, sub(tile("white"), 0, 0, 4, 4), tc.darkened(0.3))
			wbox(b + Vector3(0.36, 0, 0.36), b + Vector3(0.64, 0.3, 0.64), "tank_side", "water", MeshBuf.WHITE, 31)
			wbox(b + Vector3(0.68, 0, 0.12), b + Vector3(0.88, 0.2, 0.32), "tank_side", "water", MeshBuf.WHITE, 31)
			emitter(b + Vector3(0.5, 0.33, 0.5), "drip")
		"flowers":
			# 옥상 정원: 판석 길 + 화단 + 작은 나무 + 벤치
			_topquad(b, 0, 0, 1, 1, 0.012, tile("g_slab"))
			cbox(b + Vector3(0.06, 0, 0.06), b + Vector3(0.94, 0.12, 0.4), Color("#8a6a5a"), Color("#6a8a4a"))
			_topquad(b, 0.08, 0.08, 0.92, 0.38, 0.121, sub(tile("crops_%d" % (hs % 3)), 1, 1, 14, 6))
			for i in 3:
				var fx := 0.12 + 0.26 * float(i)
				cbox(b + Vector3(fx, 0.12, 0.16), b + Vector3(fx + 0.1, 0.2, 0.26), Color(["#ff6f8f", "#ffd45a", "#b58be0"][(hs + i) % 3]))
			cbox(b + Vector3(0.66, 0, 0.6), b + Vector3(0.72, 0.42, 0.66), Color("#6a4a3e"))
			cbox(b + Vector3(0.52, 0.36, 0.46), b + Vector3(0.86, 0.66, 0.8), Color("#4f8a4e"), Color("#6fae5c"))
			cbox(b + Vector3(0.12, 0, 0.66), b + Vector3(0.44, 0.1, 0.78), Color("#a8704e"), Color("#c99466"))
		_:
			_kerb(p, Color("#9aa3b8"), 0.06)


func _small_sign(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int, at: Vector3) -> void:
	# 같은 좌판이 줄지어 있으면 줄의 첫 칸(과 드문드문)에만 팻말 → 벽지처럼 도배되지 않게
	var ty: String = str(c.get("type", ""))
	for nb in [p + Vector3i(-1, 0, 0), p + Vector3i(0, -1, 0)]:
		if str(state.cells.get(nb, {}).get("type", "")) == ty and ViewCfg.h2(p.x * 11 + p.y * 7, p.z + 3) % 4 != 0:
			return
	var text := cfg.sign_text(str(c.get("type", "")))
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
	var mat := "scrap"
	if str(bec.get("kind", "house")) == "house" and str(bec.get("type", "house")) == "house":
		mat = cfg.material_key(str(look_of(bec).get("wall", "scrap")))
	else:
		var lk := str(bec.get("look", c.get("look", "")))
		mat = cfg.material_key(str(cfg.look_recipe(lk if cfg.has_look(lk) else "generic_shop").get("wall", "render")))
	var bid := int(c.get("bid", -1))
	var ext := extent_of(c, p)
	var o: Vector3i = ext["origin"]
	var dd := int(ext["d"])
	# 여러 층짜리 공사: 아래층부터 차오른다(층마다 진행을 나눠 가진다)
	var zi := p.z - o.z
	var lp := clampf(prog * float(dd) - float(zi), 0.0, 1.0)
	var same := func(q: Vector3i) -> bool:
		var cq: Dictionary = state.cells.get(q, {})
		return not cq.is_empty() and int(cq.get("bid", -2)) == bid
	# 올라가는 벽(같은 공사장 칸 사이에는 벽이 없다)
	var wh := lp * 0.9
	if wh > 0.05:
		var wr := tile("wall_%s_0" % mat)
		for d in 4:
			if solid.has(p + DIR[d]) or same.call(p + DIR[d]):
				continue
			fquad(p, d, 0, 1, 0, wh, 0.0, wr)
		var y := b.y + wh * fh
		if not same.call(p + UPI) or lp < 1.0:
			mb.quad(Vector3(b.x, y, b.z), Vector3(b.x + 1, y, b.z), Vector3(b.x + 1, y, b.z + 1), Vector3(b.x, y, b.z + 1), UP, tile("cutcap"), Color(2.2, 2.0, 2.0))
	# 대나무 비계 + 초록 그물(발자국 바깥 둘레만)
	var sc := tile("scaffold")
	var nt := tile("net")
	var o2 := 0.07
	var sh := 1.0 + (0.2 if not same.call(p + UPI) else 0.0)
	for d in 4:
		if solid.has(p + DIR[d]) or same.call(p + DIR[d]):
			continue
		var u0s := -o2 if not same.call(p - RGTI[d]) else 0.0
		var u1s := 1.0 + o2 if not same.call(p + RGTI[d]) else 1.0
		mb.quad2(fp(p, d, u0s, sh, o2), fp(p, d, u1s, sh, o2), fp(p, d, u1s, 0, o2), fp(p, d, u0s, 0, o2), NRM[d], Rect2(sc.position, Vector2(16, 16)))
		var nh := clampf(0.25 + lp * 0.75, 0.0, 1.0)
		var hsd := ViewCfg.h2(seed_v, d)
		if hsd % 4 != 0:
			var u0 := 0.0 if hsd % 3 != 0 else 0.5
			var u1 := 1.0 if hsd % 5 != 0 else 0.5
			if u1 > u0:
				mb.quad2(fp(p, d, u0, nh, o2 + 0.01), fp(p, d, u1, nh, o2 + 0.01), fp(p, d, u1, 0.06, o2 + 0.01), fp(p, d, u0, 0.06, o2 + 0.01), NRM[d], Rect2(nt.position, Vector2((u1 - u0) * 16.0, nh * 16.0)))
	if lp > 0.0 and lp < 1.0:
		emitter(b + Vector3(0.5, (lp * 0.9 + 0.1) * fh, 0.5), "site")
	# 공사판(기준 칸 하나): 진행 막대 — 바깥에서 보이는 면에
	if p == Vector3i(o.x, o.y, o.z):
		var best := -1
		for d in [1, 0, 2, 3]:
			if not state.cells.has(p + DIR[d]) and not solid.has(p + DIR[d]):
				best = d
				break
		if best >= 0:
			var bw := 0.6
			fbox(p, best, 0.2, 0.2 + bw, 0.25, 0.5, 0.1, 0.14, tile("white"), tile("white"), Color("#f2d27a"), 31)
			fbox(p, best, 0.25, 0.25 + (bw - 0.1) * prog, 0.3, 0.38, 0.14, 0.16, tile("white"), tile("white"), Color("#c2463c"), 31)
			fbox(p, best, 0.25 + (bw - 0.1) * prog, 0.25 + (bw - 0.1), 0.3, 0.38, 0.14, 0.155, tile("white"), tile("white"), Color("#5a5674"), 31)
			fbox(p, best, 0.22, 0.25, 0.0, 0.25, 0.1, 0.13, tile("white"), tile("white"), Color("#8a7a6a"), 31)
			fbox(p, best, 0.75, 0.78, 0.0, 0.25, 0.1, 0.13, tile("white"), tile("white"), Color("#8a7a6a"), 31)


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
	slots = []
	if z >= 0 and z < by_floor.size():
		for p in by_floor[z]:
			var c: Dictionary = state.cells[p]
			mb.owner = owner_of(p)
			if str(c.get("kind", "")) == "facility":
				fac.build_cell(p, c, true)
			elif is_box(c):
				_cut_cell(p, c)
			else:
				_build_cell(p, c)
		for p in sup_floor[z]:
			mb.owner = 0
			_build_support(p)
	mb.owner = 0
	return {"mesh": mb.commit(), "lights": lights, "emitters": emitters, "slots": slots}


func _same_unit(a: Dictionary, b: Dictionary) -> bool:
	return a.has("bid") and int(a.get("bid", 0)) == int(b.get("bid", -1))


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
	var mat: String = cfg.material_key(str(look_of(c).get("wall", "scrap"))) if kind == "house" else _fac_wall(rec)
	var seed_v: int = int(c.get("seed", 0)) + p.x * 7 + p.y * 13 + p.z * 29
	var b := cellv(p)
	# 바닥
	var fname := "f_" + str(rec.get("floor", "concrete"))
	if not atlas.has(fname):
		fname = "f_concrete"
	var fr := tile(fname)
	var y := b.y + 0.004
	var lived: bool = kind != "house" or int(bld(c).get("residents", 1)) > 0
	if kind == "house":
		var tier := int(c.get("tier", 1))
		rec = rec.duplicate()
		rec["interior"] = ["mat", "mat", "bed", "flat", "flat", "flat"][clampi(tier, 0, 5)]
		rec["floor"] = ["dirt", "dirt", "wood", "wood", "carpet", "wood"][clampi(tier, 0, 5)]
		fname = "f_" + str(rec["floor"])
		fr = tile(fname)
	mb.quad(Vector3(b.x, y, b.z), Vector3(b.x + 1, y, b.z), Vector3(b.x + 1, y, b.z + 1), Vector3(b.x, y, b.z + 1), UP, fr, MeshBuf.WHITE if lived else Color(0.8, 0.8, 0.86), 0.0, KI)
	# 벽
	var wr := tile("wall_%s_%d" % [mat, _age_variant(seed_v, int(c.get("tier", 2))) % 3])
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
			var gdoor := p.z == 0 and kind != "house" and not state.cells.has(nb) and ViewCfg.h2(seed_v, 3 + d) % 2 == 0
			if door or gdoor:
				_edge_box(p, d, 0.0, 0.3125, CUT_T, CUT_WALL, wr, cap)
				_edge_box(p, d, 0.6875, 1.0, CUT_T, CUT_WALL, wr, cap)
			else:
				_edge_box(p, d, 0.0, 1.0, CUT_T, CUT_WALL, wr, cap)
			# 외벽 바깥면은 아래층 벽과 이어지게 그대로 둔다(상자 바깥면이 그 역할)
	if lived:
		_furnish(p, c, rec, seed_v)
		light(b + Vector3(0.5, 0.4, 0.5), Color(1, 1, 1), 1.1, 0.9)
		if kind == "house":
			_resident_slots(p, c, rec, seed_v)


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


## 층 컷의 집: 낮엔 식탁·의자에, 밤엔 잠자리에 한두 사람(사는 사람 수만큼).
func _resident_slots(p: Vector3i, c: Dictionary, rec: Dictionary, seed_v: int) -> void:
	var b := bld(c)
	var res := int(b.get("residents", 1))
	if res <= 0:
		return
	var cap := maxi(int(b.get("cap", 4)), 1)
	var n := 2 if res * 2 > cap else 1
	var hs := ViewCfg.h2(seed_v, 600)
	var k := hs % 4
	var tier := int(c.get("tier", 1))
	var what: String = str(rec.get("interior", ""))
	var bed_at := Vector2(0.33, 0.5)
	var day_at: Array = [Vector2(0.66, 0.36), Vector2(0.66, 0.78)] if what == "flat" else [Vector2(0.62, 0.45), Vector2(0.45, 0.8)]
	var dirs: Array = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	for i in n:
		var dp: Vector2 = day_at[i]
		var pose := "sit" if (what == "flat" or i == 0) else "stand"
		if tier <= 1 and i == 0:
			pose = "squat"
		slots.append({"bid": int(c.get("bid", -1)), "pos": _ipos(p, k, dp.x, dp.y, 0.0), "dir": dirs[(hs + i) % 4], "pose": pose, "role": "resident", "when": "day", "z": p.z, "tier": tier, "look": "", "out": false, "i": slots.size()})
		var bp := bed_at + Vector2(0.0, (0.18 if i == 1 else 0.0))
		slots.append({"bid": int(c.get("bid", -1)), "pos": _ipos(p, k, bp.x, bp.y, 0.1), "dir": dirs[(k + 1) % 4], "pose": "lie", "role": "resident", "when": "night", "z": p.z, "tier": tier, "look": "", "out": false, "i": slots.size()})


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
