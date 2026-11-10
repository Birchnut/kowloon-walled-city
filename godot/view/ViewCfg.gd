class_name ViewCfg
extends RefCounted
## ViewCfg — render.json / visuals.json 읽기 도우미. 모르는 id는 기본 레시피로 떨어진다.

var render: Dictionary = {}
var visuals: Dictionary = {}
var _recipe_cache: Dictionary = {}
var _mat_cache: Dictionary = {}

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


func household_color(type: String) -> Color:
	var m: Dictionary = visuals.get("household_colors", {})
	return col(m.get(type, m.get("_default", "#c9c2b4")), Color("#c9c2b4"))


## kind + type → 레시피. _default_<kind> ← _group_<group> ← types[type] 순으로 덮어쓴다.
func recipe(kind: String, type: String) -> Dictionary:
	var key := kind + "/" + type
	if _recipe_cache.has(key):
		return _recipe_cache[key]
	var types: Dictionary = visuals.get("types", {})
	var out: Dictionary = {"form": "box", "window": "std", "sign_style": "none", "interior": "", "floor": "concrete", "busy": "day", "roof": {"antenna": 1}}
	var dk: Variant = types.get("_default_" + kind, {})
	if dk is Dictionary:
		out.merge(dk, true)
	if kind == "business":
		var grp: String = str(Data.item("businesses", type).get("group", ""))
		var dg: Variant = types.get("_group_" + grp, {})
		if dg is Dictionary:
			out.merge(dg, true)
	var dt: Variant = types.get(type, {})
	if dt is Dictionary:
		out.merge(dt, true)
	_recipe_cache[key] = out
	return out


## 간판 글자(데이터의 sign). 없으면 "".
static func sign_text(kind: String, type: String) -> String:
	var file := "businesses" if kind == "business" else ("facilities" if kind == "facility" else "")
	if file == "":
		return ""
	return str(Data.item(file, type).get("sign", ""))


# ------------------------------------------------------------------ 해시(결정론)
static func h2(a: int, b: int) -> int:
	var x: int = (a * 374761393 + b * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return (x ^ (x >> 16)) & 0x7fffffff


static func h3(a: int, b: int, c: int) -> int:
	return h2(h2(a, b), c)


static func hf(a: int, b: int) -> float:
	return float(h2(a, b) % 100000) / 100000.0
