class_name ViewCfg
extends RefCounted
## ViewCfg — render.json / visuals.json 읽기 도우미. 모르는 id는 기본 레시피로 떨어진다.

var render: Dictionary = {}
var visuals: Dictionary = {}
var _recipe_cache: Dictionary = {}
var _mat_cache: Dictionary = {}
var _look_cache: Dictionary = {}
static var overrides: Dictionary = {}
static var grid_override := Vector3i.ZERO

# 파생 상수(카메라 수학)
var cell_half_px: float = 8.0
var storey_px: float = 8.0
var elev: float = deg_to_rad(30.0)
var ppu1: float = 11.3137       # 줌 ×1에서 월드 1단위 = 몇 픽셀
var floor_h: float = 0.8165      # 한 층 높이(월드 단위)
var grid: Vector3i = Vector3i(16, 16, 10)

const TEX: float = 1.0 / 16.0   # 수평 텍셀 1개 = 월드 1/16


func reload() -> void:
	render = Data.file("render") if Data.file("render") is Dictionary else {}
	visuals = Data.file("visuals") if Data.file("visuals") is Dictionary else {}
	_recipe_cache.clear()
	_mat_cache.clear()
	_look_cache.clear()
	# 개발용 덮어쓰기(Sandbox의 r:경로=값 인자)
	if not overrides.is_empty():
		render = render.duplicate(true)
		for k in overrides:
			var parts: PackedStringArray = str(k).split(".")
			var cur: Dictionary = render
			for i in parts.size() - 1:
				if not (cur.get(parts[i]) is Dictionary):
					cur[parts[i]] = {}
				cur = cur[parts[i]]
			cur[parts[parts.size() - 1]] = overrides[k]
	cell_half_px = float(r("pixel.cell_half_px", 8))
	storey_px = float(r("pixel.storey_px", 8))
	elev = deg_to_rad(float(r("pixel.elevation_deg", 30.0)))
	ppu1 = cell_half_px * sqrt(2.0)
	floor_h = storey_px / (ppu1 * cos(elev))
	grid = Vector3i(int(Data.cfg("grid.width", 16)), int(Data.cfg("grid.height", 16)), int(Data.cfg("grid.max_floors", 10)))
	if grid_override != Vector3i.ZERO:
		grid = grid_override


## 격자 크기: state.flags.grid({w,h,floors}) → config → 셀이 실제로 있는 범위까지 넓힌다. 어느 값도 12를 가정하지 않는다.
func fit_grid(st: Object) -> void:
	var g := grid
	if st != null:
		var fl: Variant = st.get("flags")
		if fl is Dictionary and (fl as Dictionary).get("grid") is Dictionary:
			var gd: Dictionary = fl["grid"]
			g = Vector3i(int(gd.get("w", g.x)), int(gd.get("h", g.y)), int(gd.get("floors", g.z)))
		var cs: Variant = st.get("cells")
		if cs is Dictionary:
			for p in cs:
				if p is Vector3i:
					g = Vector3i(maxi(g.x, p.x + 1), maxi(g.y, p.y + 1), maxi(g.z, p.z + 1))
	grid = g


func r(path: String, default: Variant = null) -> Variant:
	var cur: Variant = render
	for part in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default
	return cur


static func col(v: Variant, default: Color = Color.MAGENTA) -> Color:
	if v is Color:
		return v
	if v is String and v.begins_with("#") and (v.length() == 7 or v.length() == 9):
		return Color.html(v)
	return default


func neon(name_or_hex: Variant) -> Color:
	if name_or_hex is String:
		if name_or_hex.begins_with("#"):
			return col(name_or_hex)
		var n: Dictionary = visuals.get("neon", {})
		if n.has(name_or_hex):
			return col(n[name_or_hex])
	return Color("#ffd84a")


func material_ids() -> Array:
	var out: Array = []
	var m: Dictionary = visuals.get("materials", {})
	for k in m:
		if not str(k).begins_with("_comment"):
			out.append(k)
	if not out.has("_default"):
		out.append("_default")
	return out


func material(id: String) -> Dictionary:
	if _mat_cache.has(id):
		return _mat_cache[id]
	var m: Dictionary = visuals.get("materials", {})
	var base := {"ramp": ["#e2dccf", "#c9c0bb", "#a79ead", "#7d7493"], "pattern": "concrete", "accent": "#8f8aa6", "roof": ["#cfc6bd", "#b3a9ad"]}
	var d: Variant = m.get(id, m.get("_default", base))
	if not (d is Dictionary):
		d = base
	var out: Dictionary = base.duplicate(true)
	out.merge(d, true)
	_mat_cache[id] = out
	return out


## 아틀라스에 실제로 구워진 자재 키(모르는 자재는 _default).
func material_key(id: String) -> String:
	var m: Dictionary = visuals.get("materials", {})
	return id if m.has(id) else "_default"


## kind + type → 레시피. _default_<kind> ← _cat_<buildings.json의 cat> ← types[type] 순으로 덮어쓴다.
## 모르는 id는 기본 레시피로 그려진다(뷰 코드 수정 불필요).
func recipe(kind: String, type: String) -> Dictionary:
	var key := kind + "/" + type
	if _recipe_cache.has(key):
		return _recipe_cache[key]
	var types: Dictionary = visuals.get("types", {})
	var out: Dictionary = {"form": "box", "window": "std", "sign_style": "none", "interior": "", "floor": "concrete", "busy": "day", "props": []}
	var dk: Variant = types.get("_default_" + kind, {})
	if dk is Dictionary:
		out.merge(dk, true)
	if kind == "facility":
		var cat: String = str(Data.item("buildings", type).get("cat", ""))
		var dg: Variant = types.get("_cat_" + cat, {})
		if cat != "" and dg is Dictionary:
			out.merge(dg, true)
	var dt: Variant = types.get(type, {})
	if dt is Dictionary:
		out.merge(dt, true)
	_recipe_cache[key] = out
	return out


## 시설 외형 이름표(look) → 바깥 모양 매개변수(data/art/looks.json). _default ← _cat_<분류> ← <look>.
func look_recipe(look: String, cat: String = "") -> Dictionary:
	var key := look + "|" + cat
	if _recipe_cache.has(key):
		return _recipe_cache[key]
	var root: Variant = Data.file("looks")
	var ls: Dictionary = (root as Dictionary).get("looks", {}) if root is Dictionary else {}
	var out: Dictionary = {"form": "box", "wall": "render", "front": "shop", "win": "small", "sign_style": "paint", "sign_color": "red", "floor": "concrete", "roof": [], "busy": "day"}
	var dk: Variant = ls.get("_default", {})
	if dk is Dictionary:
		out.merge(dk, true)
	var c2 := cat if cat != "" else str(LOOK_CAT.get(look, ""))
	var dc: Variant = ls.get("_cat_" + c2, {})
	if dc is Dictionary:
		out.merge(dc, true)
	var dl: Variant = ls.get(look, {})
	if dl is Dictionary:
		out.merge(dl, true)
	_recipe_cache[key] = out
	return out


func has_look(look: String) -> bool:
	var root: Variant = Data.file("looks")
	return root is Dictionary and ((root as Dictionary).get("looks", {}) as Dictionary).has(look) and not look.begins_with("_")


## 계약의 look 목록과 분류(ARCHITECTURE v4). 모르는 look은 분류별 기본 외형으로.
const LOOK_CAT := {
	"market_mat": "market", "market_alley": "market", "market_hall": "market", "market_mall": "market",
	"water_catcher": "water", "water_tank": "water", "water_pipe": "water", "water_plant": "water",
	"gen_small": "power", "power_tap": "power", "power_plant": "power", "power_waste": "power",
	"food_cans": "food", "food_pilgrims": "food", "noodle_mill": "food", "noodle_stall": "food", "rat_farm": "food", "burger": "food", "sushi": "food", "roof_garden": "food", "brewery": "food",
	"oil_collect": "goods", "candle": "goods", "soap": "goods", "rag_collect": "goods", "tailor": "goods", "suit": "goods", "radio": "goods", "assembly": "goods", "fake": "goods",
	"mahjong": "fun", "teahouse": "fun", "karaoke": "fun", "bathhouse": "service", "shrine": "service", "study": "service", "roof_park": "fun", "dentist": "service", "pharmacy": "service", "salon": "service",
	"fire_bucket": "safety", "fire_station": "safety", "trash_guild": "safety", "clinic": "safety",
	"scrapyard": "base", "warehouse": "base", "trade_post": "base", "expedition_base": "base",
	"gambling": "vice", "casino": "vice", "callcenter": "vice", "fireworks": "vice",
	"landmark_hall": "landmark", "landmark_generic": "landmark",
	"generic_workshop": "goods", "generic_shop": "market", "generic_service": "service",
}
## 분류(시뮬 buildings.json의 cat 이름이 달라도 앞 글자로 대충 맞춘다) → 기본 look
const CAT_LOOK := {"market": "generic_shop", "food": "generic_shop", "water": "water_pipe", "power": "gen_small", "goods": "generic_workshop", "industry": "generic_workshop",
	"fun": "generic_service", "service": "generic_service", "safety": "generic_service", "base": "warehouse", "vice": "gambling", "landmark": "landmark_generic", "utility": "water_pipe"}
## v3 시설 id → look(옛 저장·옛 데이터 호환)
const V3_LOOK := {"stall": "market_mat", "market_basic": "market_alley", "market_general": "market_hall", "market_luxury": "market_mall", "rain_catcher": "water_catcher",
	"water_tower": "water_tank", "water_main": "water_pipe", "water_works": "water_plant", "generator": "gen_small", "grid_power": "power_tap", "power_plant": "power_plant",
	"cogen_plant": "power_waste", "rooftop_farm": "roof_garden", "garden": "roof_garden", "roof_garden": "roof_park", "noodle_works": "noodle_mill", "fishball_works": "noodle_stall",
	"moonshine": "brewery", "candle_shop": "candle", "sewing_shop": "tailor", "soap_shop": "soap", "tailor": "suit", "radio_shop": "radio", "assembly": "assembly", "fake_shop": "fake",
	"shrine": "shrine", "teahouse": "teahouse", "mahjong": "mahjong", "dentist": "dentist", "bathhouse": "bathhouse", "study_hall": "study", "karaoke": "karaoke",
	"gambling_den": "gambling", "call_centre": "callcenter", "casino": "casino", "fireworks": "fireworks", "scrapyard": "scrapyard", "warehouse": "warehouse",
	"trade_post": "trade_post", "expedition_post": "expedition_base", "landmark_hall": "landmark_hall"}


## 주거 외관(계층 × 자재). 없는 키는 같은 자재의 가까운 계층 → common_1 → 내장 기본값.
func house_look(key: String) -> Dictionary:
	if _look_cache.has(key):
		return _look_cache[key]
	var hs: Dictionary = visuals.get("houses", {}) if visuals.get("houses", {}) is Dictionary else {}
	var out: Dictionary = {"wall": "scrap", "roof": "sheet", "win": ["std"], "frames": ["a"], "win_p": 0.9, "clutter": 0.5, "balcony": "none", "eave": "none", "parapet": 0, "roofprops": {"antenna": 1}}
	var found: Variant = hs.get(key, null)
	if found == null:
		var parts := key.split("_")
		if parts.size() == 2 and parts[1].is_valid_int():
			var t := int(parts[1])
			for dt in [-1, 1, -2, 2, -3, 3]:
				var k2 := "%s_%d" % [parts[0], t + dt]
				if hs.has(k2):
					found = hs[k2]
					break
		if found == null:
			found = hs.get("common_1", {})
	if found is Dictionary:
		out.merge(found, true)
	_look_cache[key] = out
	return out


## 간판 글자(세계 안): art/signs.json의 sign_script가 "mixed"면 시설별 한자 간판(hanja 표)이 먼저,
## 없는 시설은 시뮬 데이터(buildings.json의 sign) → visuals 레시피의 sign 순. "hangul"이면 한자를 쓰지 않는다.
func sign_text(type: String) -> String:
	var sg: Variant = Data.file("signs")
	if sg is Dictionary and str((sg as Dictionary).get("sign_script", "hangul")) == "mixed":
		var hj: Variant = (sg as Dictionary).get("hanja", {})
		if hj is Dictionary and (hj as Dictionary).has(type):
			return str((hj as Dictionary)[type])
	var s := str(Data.item("buildings", type).get("sign", ""))
	if s == "":
		s = str(recipe("facility", type).get("sign", ""))
	return s


func tier_color(tier: int, i: int) -> Color:
	var tc: Dictionary = visuals.get("tier_colors", {}) if visuals.get("tier_colors", {}) is Dictionary else {}
	var a: Variant = tc.get(str(clampi(tier, 1, 5)), [])
	if a is Array and not (a as Array).is_empty():
		return col((a as Array)[i % (a as Array).size()], Color("#c9c2b4"))
	return Color("#c9c2b4")


func vis(path: String, default: Variant = null) -> Variant:
	var cur: Variant = visuals
	for part in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default
	return cur


# ------------------------------------------------------------------ 해시(결정론)
static func h2(a: int, b: int) -> int:
	var x: int = (a * 374761393 + b * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return (x ^ (x >> 16)) & 0x7fffffff


static func h3(a: int, b: int, c: int) -> int:
	return h2(h2(a, b), c)


static func hf(a: int, b: int) -> float:
	return float(h2(a, b) % 100000) / 100000.0
