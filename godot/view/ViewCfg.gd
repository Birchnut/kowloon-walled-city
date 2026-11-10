class_name ViewCfg
extends RefCounted
## ViewCfg — render.json / visuals.json 읽기 도우미. 모르는 id는 기본 레시피로 떨어진다.

var render: Dictionary = {}
var visuals: Dictionary = {}
var _recipe_cache: Dictionary = {}
var _mat_cache: Dictionary = {}
var _look_cache: Dictionary = {}
static var overrides: Dictionary = {}

# 파생 상수(카메라 수학)
var cell_half_px: float = 8.0
var storey_px: float = 8.0
var elev: float = deg_to_rad(30.0)
var ppu1: float = 11.3137       # 줌 ×1에서 월드 1단위 = 몇 픽셀
var floor_h: float = 0.8165      # 한 층 높이(월드 단위)
var grid: Vector3i = Vector3i(12, 12, 10)

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
	grid = Vector3i(int(Data.cfg("grid.width", 12)), int(Data.cfg("grid.height", 12)), int(Data.cfg("grid.max_floors", 10)))


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


## 간판 글자: 시뮬 데이터(buildings.json의 sign)가 있으면 그것, 없으면 visuals 레시피의 sign. 없으면 "".
func sign_text(type: String) -> String:
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
