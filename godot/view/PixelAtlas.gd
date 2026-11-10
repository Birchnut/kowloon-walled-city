class_name PixelAtlas
extends RefCounted
## PixelAtlas — 모든 픽셀 텍스처를 실행 시 코드로 그린다(자재 벽·지붕, 창, 소품, 바닥, 가구, 간판 글자).
## 규칙: 16×16 타일 = 벽 한 칸. "매크로 픽셀" = 2×2 텍셀. 줌 ×1에서는 짝수 열만 보이므로
##       큰 형태는 매크로 격자에, 가는 디테일(홀수 열·드문 가로줄)은 ×2 이상에서만 보이게 그린다.
## 알파 규약: 0 = 투명, 0.5 = 유리(밤에 켜질 수 있음), 0.75 = 항상 발광, 1 = 보통.

const SIZE := 512
const T := 16
const A_GLASS := 0.5
const A_EMIT := 0.75

var cfg: ViewCfg
var img: Image
var tex: ImageTexture
var tiles: Dictionary = {}       # name -> Rect2i (텍셀)
var _next := 0                   # 16×16 칸 할당 포인터 (y < 320)
var _tall_next := 0              # 16×32 칸 (320 ≤ y < 352)
var _ox := 0
var _oy := 0
var _w := 16
var _h := 16
var _rs := 1
var _sign_x := 0
var _sign_y := 352
var _signs: Dictionary = {}
var _fonts: Array = []
var dirty := false


func build(c: ViewCfg) -> void:
	cfg = c
	img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	tiles.clear()
	_signs.clear()
	_next = 0
	_tall_next = 0
	_sign_x = 0
	_sign_y = 352
	_load_fonts()
	_paint_basics()
	for m in cfg.material_ids():
		_paint_material(m)
	_paint_windows()
	_paint_props()
	_paint_ground()
	_paint_interiors()
	if tex == null:
		tex = ImageTexture.create_from_image(img)
	else:
		tex.update(img)
	dirty = false


func flush() -> void:
	if dirty:
		tex.update(img)
		dirty = false


func rect(name: String) -> Rect2i:
	return tiles.get(name, tiles.get("white", Rect2i(0, 0, 16, 16)))


func has(name: String) -> bool:
	return tiles.has(name)


# ------------------------------------------------------------------ 그리기 도우미
func _begin(name: String, seed_v: int = 0) -> void:
	_ox = (_next % 32) * T
	_oy = (_next / 32) * T
	_w = T
	_h = T
	_next += 1
	tiles[name] = Rect2i(_ox, _oy, T, T)
	_rs = (name.hash() ^ (seed_v * 7919)) & 0x7fffffff
	if _rs == 0:
		_rs = 1


func _begin_tall(name: String) -> void:
	_ox = _tall_next * T
	_oy = 320
	_w = T
	_h = 32
	_tall_next += 1
	tiles[name] = Rect2i(_ox, _oy, T, 32)
	_rs = name.hash() & 0x7fffffff


func _rnd() -> float:
	_rs = (_rs * 1103515245 + 12345) & 0x7fffffff
	return float((_rs >> 8) % 65536) / 65536.0


func _ri(n: int) -> int:
	return int(_rnd() * n) % maxi(n, 1)


func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < _w and y < _h:
		img.set_pixel(_ox + x, _oy + y, c)


func _rc(x: int, y: int, w: int, h: int, c: Color) -> void:
	var x0 := maxi(x, 0)
	var y0 := maxi(y, 0)
	var x1 := mini(x + w, _w)
	var y1 := mini(y + h, _h)
	if x1 > x0 and y1 > y0:
		img.fill_rect(Rect2i(_ox + x0, _oy + y0, x1 - x0, y1 - y0), c)


## 매크로 픽셀(2×2) 단위 사각형
func _m(x: int, y: int, w: int, h: int, c: Color) -> void:
	_rc(x * 2, y * 2, w * 2, h * 2, c)


static func mx(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), 1.0)


static func lt(a: Color, k: float) -> Color:
	return Color(minf(a.r + k, 1.0), minf(a.g + k * 0.95, 1.0), minf(a.b + k * 0.8, 1.0), 1.0)


static func dk(a: Color, k: float) -> Color:
	# 어둡게 하면서 보라 쪽으로 민다(색상 이동 그림자)
	return Color(a.r * (1.0 - k), a.g * (1.0 - k * 1.05), a.b * (1.0 - k * 0.7), 1.0)


static func glass(c: Color) -> Color:
	return Color(c.r, c.g, c.b, A_GLASS)


static func emit(c: Color) -> Color:
	return Color(c.r, c.g, c.b, A_EMIT)


# ------------------------------------------------------------------ 기본
func _paint_basics() -> void:
	_begin("white")
	_rc(0, 0, 16, 16, Color.WHITE)
	_begin("emit")
	_rc(0, 0, 16, 16, emit(Color.WHITE))
	_begin("glass")
	_rc(0, 0, 16, 16, glass(Color("#5c6f9a")))
	_begin("clear")


# ------------------------------------------------------------------ 자재
func _paint_material(id: String) -> void:
	var m: Dictionary = cfg.material(id)
	var ramp: Array = m.get("ramp", [])
	var c0 := ViewCfg.col(ramp[0] if ramp.size() > 0 else "#e2dccf")
	var c1 := ViewCfg.col(ramp[1] if ramp.size() > 1 else "#c9c0bb")
	var c2 := ViewCfg.col(ramp[2] if ramp.size() > 2 else "#a79ead")
	var c3 := ViewCfg.col(ramp[3] if ramp.size() > 3 else "#7d7493")
	var acc := ViewCfg.col(m.get("accent", "#8f8aa6"))
	var pat: String = str(m.get("pattern", "concrete"))
	for v in 4:
		_begin("wall_%s_%d" % [id, v], v)
		_wall(pat, v, c0, c1, c2, c3, acc)
	var rf: Array = m.get("roof", [])
	var r0 := ViewCfg.col(rf[0] if rf.size() > 0 else "#cfc6bd")
	var r1 := ViewCfg.col(rf[1] if rf.size() > 1 else "#b3a9ad")
	for v in 3:
		_begin("roof_%s_%d" % [id, v], v)
		_roof(pat, v, r0, r1, c2, acc)
	# 돌출부 옆면/밑면용 단색에 가까운 타일
	_begin("trim_%s" % id)
	_rc(0, 0, 16, 16, c1)
	_rc(0, 0, 16, 2, lt(c0, 0.06))
	_rc(0, 14, 16, 2, c2)


func _wall(pat: String, v: int, c0: Color, c1: Color, c2: Color, c3: Color, acc: Color) -> void:
	match pat:
		"planks":
			for p in 4:
				var tone: Color = [c0, c0, mx(c0, c1, 0.5), c1][_ri(4)]
				_rc(p * 4, 0, 4, 16, tone)
				_rc(p * 4 + 3, 0, 1, 16, mx(tone, c2, 0.55))
				if _rnd() < 0.6:
					_rc(p * 4, 3 + _ri(5) * 2, 3, 1, mx(tone, c2, 0.45))
				if _rnd() < 0.5:
					_px(p * 4 + 1, 2 + _ri(12), mx(tone, c3, 0.5))
			if v >= 2:
				for x in 8:
					var hgt := 1 + _ri(3)
					_rc(x * 2, 16 - hgt * 2, 2, hgt * 2, mx(c1, c2, 0.55))
			if v == 3:
				_m(1 + _ri(4), 2 + _ri(2), 3, 2, mx(c0, acc, 0.6))
			_rc(0, 0, 16, 2, c2)
		"corrugated":
			var cols := [lt(c0, 0.05), c0, c1, mx(c1, c2, 0.45)]
			for x in 16:
				_rc(x, 0, 1, 16, cols[x % 4])
			_rc(0, 9, 16, 1, mx(c1, c2, 0.7))
			if v == 1:
				_m(4, 0, 4, 4, lt(c0, 0.08))
				_rc(8, 0, 1, 8, mx(c1, c2, 0.4))
			if v >= 2:
				for x in 8:
					if _rnd() < 0.6:
						var hgt2 := 1 + _ri(4)
						_rc(x * 2, 16 - hgt2 * 2, 2, hgt2 * 2, mx(acc, c1, 0.25 + 0.3 * _rnd()))
			if v == 3:
				var px0 := _ri(5)
				_m(px0, 1, 3, 3, mx(acc, c2, 0.3))
				_rc(px0 * 2, 2, 6, 1, dk(acc, 0.25))
			_rc(0, 0, 16, 2, mx(c1, c2, 0.5))
		"brick":
			for row in 8:
				var off := (row % 2) * 2
				for b in range(-1, 5):
					var x0 := b * 4 + off - 2
					var tone2: Color = [c0, c0, c1, mx(c0, c1, 0.5), c0, mx(c1, c2, 0.4)][_ri(6)]
					_rc(x0, row * 2, 4, 2, tone2)
					_rc(x0 + 3, row * 2, 1, 2, mx(tone2, c2, 0.4))
			if v >= 2:
				var bx := _ri(4)
				var by := 2 + _ri(3)
				_m(bx, by, 3 + _ri(2), 2 + _ri(2), mx(acc, c0, 0.25))
			if v == 3:
				for x in 8:
					if _rnd() < 0.5:
						_rc(x * 2, 14 - _ri(2) * 2, 2, 4, mx(c2, c3, 0.4))
			_rc(0, 0, 16, 2, lt(mx(acc, c0, 0.3), 0.02))
			_rc(0, 2, 16, 1, mx(c1, c2, 0.6))
		"patch":
			_rc(0, 0, 16, 16, c0)
			var pal := [c0, c1, acc, Color("#c97a55"), Color("#e6cc98"), Color("#6f8fc0"), mx(c1, c2, 0.5), lt(c0, 0.06)]
			var n := 6 + _ri(3)
			for i in n:
				var w := 2 + _ri(3)
				var h := 2 + _ri(4)
				var x1 := _ri(8)
				var y1 := _ri(8)
				var pc: Color = pal[_ri(pal.size())]
				if v == 0 and _rnd() < 0.5:
					pc = [c0, c1][_ri(2)]
				_m(x1, y1, w, h, pc)
				_rc(x1 * 2 + w * 2 - 1, y1 * 2, 1, h * 2, dk(pc, 0.22))
				_rc(x1 * 2, y1 * 2 + h * 2 - 1, w * 2 - 1, 1, dk(pc, 0.15))
			if v >= 2:
				for x in 8:
					if _rnd() < 0.5:
						_rc(x * 2, 14 - _ri(2) * 2, 2, 4, mx(c2, c3, 0.3))
			_rc(0, 0, 16, 2, c2)
		_:
			_rc(0, 0, 16, 16, c0)
			for i in 3 + _ri(3):
				_m(_ri(7), 1 + _ri(6), 2 + _ri(3), 1 + _ri(2), mx(c0, c1, 0.3 + 0.3 * _rnd()))
			if v >= 1:
				for i in 1 + _ri(2) + (2 if v == 3 else 0):
					var dx := _ri(8) * 2
					var len := 4 + _ri(8)
					_rc(dx, 3, 2, len, mx(c0, c2, 0.4))
					_px(dx, 3 + len, mx(c0, c2, 0.4))
			if v >= 2:
				_m(_ri(5), 4 + _ri(3), 3, 2, mx(c1, acc, 0.5))
			if v == 3:
				var cx := 2 + _ri(8)
				for i in 6:
					_px(cx + i, 6 + i + _ri(2), mx(c2, c3, 0.5))
			_rc(0, 0, 16, 2, lt(c0, 0.07))
			_rc(0, 2, 16, 1, c1)


func _roof(pat: String, v: int, r0: Color, r1: Color, c2: Color, acc: Color) -> void:
	_rc(0, 0, 16, 16, r0)
	match pat:
		"planks":
			for p in 4:
				var tone: Color = [r0, mx(r0, r1, 0.5), r1, r0][_ri(4)]
				_rc(0, p * 4, 16, 4, tone)
				_rc(0, p * 4 + 3, 16, 1, mx(tone, c2, 0.4))
		"corrugated":
			for y in 16:
				_rc(0, y, 16, 1, [lt(r0, 0.05), r0, r1, mx(r1, c2, 0.35)][y % 4])
			if v == 1:
				_m(1 + _ri(3), 1 + _ri(3), 3, 3, mx(acc, r1, 0.4))
			if v == 2:
				_m(4, 0, 4, 8, lt(r0, 0.06))
		"patch":
			var pal := [r0, r1, Color("#5f86c4"), Color("#c97a55"), Color("#e6cc98"), mx(r1, c2, 0.5)]
			for i in 5:
				var pc: Color = pal[_ri(pal.size())]
				var x1 := _ri(7)
				var y1 := _ri(7)
				var w := 2 + _ri(4)
				var h := 2 + _ri(4)
				_m(x1, y1, w, h, pc)
				_rc(x1 * 2, y1 * 2 + h * 2 - 1, w * 2, 1, dk(pc, 0.18))
		_:
			for i in 2 + _ri(3):
				_m(_ri(7), _ri(7), 1 + _ri(3), 1 + _ri(2), mx(r0, r1, 0.5 + 0.4 * _rnd()))
			if v == 1:
				_m(2 + _ri(3), 2 + _ri(3), 3, 2, mx(r1, c2, 0.5))
			if v == 2:
				_rc(0, 7, 16, 1, mx(r0, r1, 0.8))
				_rc(8, 0, 1, 16, mx(r0, r1, 0.8))


# ------------------------------------------------------------------ 창·문
const FRAMES := {"a": "#f6ecd4", "b": "#73b5a6", "c": "#c2604f", "d": "#5c4c72"}
const GLASS_DAY := "#566a98"
const GLASS_HI := "#8ea6ca"


func _frame(fc: Color, x: int, y: int, w: int, h: int) -> void:
	# 매크로 단위 창틀(테두리 1매크로) + 유리
	_m(x, y, w, h, fc)
	var g := glass(Color(GLASS_DAY))
	_m(x + 1, y + 1, w - 2, h - 2, g)
	# 창틀 아래 그림자, 창턱
	_rc(x * 2, (y + h) * 2, w * 2, 1, Color(0.25, 0.2, 0.4, 1.0).lerp(fc, 0.35))
	# 유리 반사(×2에서만: 홀수 열)
	_px((x + 1) * 2 + 1, (y + 1) * 2, glass(Color(GLASS_HI)))


func _paint_windows() -> void:
	for k in FRAMES:
		var fc := Color(FRAMES[k])
		_begin("win_std_" + k)
		_frame(fc, 2, 2, 4, 4)
		_rc(3, 12, 10, 1, lt(fc, 0.05))
		_begin("win_wide_" + k)
		_frame(fc, 1, 2, 6, 4)
		_rc(7, 6, 1, 4, fc)
		_begin("win_small_" + k)
		_frame(fc, 3, 2, 3, 3)
		_begin("win_tall_" + k)   # 발코니 문
		_frame(fc, 2, 2, 4, 6)
		_rc(7, 6, 1, 8, fc)
		_rc(6, 10, 4, 1, glass(Color(GLASS_HI)))
	# 쪽방 창: 창살
	_begin("win_cage")
	_frame(Color("#6a7f72"), 1, 2, 6, 4)
	for x in [5, 9]:
		_rc(x, 6, 1, 4, Color("#4a5c5a"))
	_rc(4, 8, 8, 1, Color("#4a5c5a"))
	# 슬릿 창(음성·목욕탕)
	_begin("win_slit")
	_m(1, 2, 6, 1, glass(Color(GLASS_DAY)))
	_rc(2, 3, 12, 1, Color("#3e3a5c"))
	_rc(2, 6, 12, 1, Color(0.2, 0.18, 0.35, 1))
	# 가게 앞(문 + 진열창): 바닥까지
	for k in ["a", "c", "b"]:
		var fc2 := Color(FRAMES[k])
		_begin("shop_" + k)
		_m(1, 2, 6, 6, fc2)
		_m(2, 3, 2, 3, glass(Color(GLASS_DAY)))       # 진열창
		_m(5, 3, 1, 5, glass(Color("#3b3558")))        # 열린 문(어두운 안쪽)
		_m(2, 6, 2, 2, dk(fc2, 0.18))
		_px(5, 6, glass(Color(GLASS_HI)))
		_rc(9, 6, 1, 10, dk(fc2, 0.2))
	# 셔터(공장·작업장): 반쯤 열림
	_begin("shutter_0")
	_m(1, 2, 6, 6, Color("#9aa3b8"))
	for y in [4, 8]:
		_rc(2, y, 12, 1, Color("#7a8298"))
	_m(1, 5, 6, 3, glass(Color("#40385e")))
	_rc(2, 10, 12, 1, Color("#676c88"))
	_begin("shutter_1")   # 닫힘
	_m(1, 2, 6, 6, Color("#a8b0c2"))
	for y in [4, 7, 10, 13]:
		_rc(2, y, 12, 1, Color("#80889e"))
	_rc(7, 14, 2, 1, Color("#5a5f7a"))
	# 문
	var doors := {"0": "#8a6a5a", "1": "#5f8f8a", "2": "#b0584c", "3": "#6b6a8e"}
	for k in doors:
		var dc := Color(doors[k])
		_begin("door_" + k)
		_m(3, 3, 3, 5, dc)
		_rc(6, 6, 6, 1, lt(dc, 0.1))
		_rc(11, 6, 1, 10, dk(dc, 0.25))
		_rc(7, 8, 2, 2, glass(Color(GLASS_DAY)))
		_px(10, 11, Color("#f2d27a"))
	# 판자로 막은 창
	_begin("win_board")
	_m(2, 2, 4, 4, Color("#4a4160"))
	_rc(4, 6, 8, 2, Color("#c9a070"))
	_rc(4, 9, 8, 2, Color("#b88d62"))
	_rc(5, 5, 1, 7, Color("#a37a58"))
	# 창 불빛만(창틀 없이) — 내부 광원 표현용
	_begin("win_glow")
	_m(2, 2, 4, 4, glass(Color(GLASS_DAY)))


# ------------------------------------------------------------------ 소품
func _paint_props() -> void:
	# 철망(쪽방 발코니): 투명 바탕 + 창살
	for k in ["0", "1"]:
		var bc := Color("#5f7f72") if k == "0" else Color("#a8644c")
		_begin("cage_" + k)
		_rc(0, 0, 16, 2, bc)
		_rc(0, 14, 16, 2, dk(bc, 0.15))
		for x in [0, 4, 8, 12]:
			_rc(x, 0, 1, 16, bc)
		_rc(15, 0, 1, 16, dk(bc, 0.1))
		_rc(0, 7, 16, 1, bc)
	# 난간
	_begin("rail")
	_rc(0, 6, 16, 2, Color("#6a6486"))
	for x in [0, 4, 8, 12]:
		_rc(x, 8, 1, 8, Color("#6a6486"))
	_rc(0, 14, 16, 2, Color("#575174"))
	# 차양(흰/회 줄무늬 → 정점색으로 물들임)
	_begin("awning")
	for x in 16:
		_rc(x, 0, 1, 16, Color.WHITE if (x / 4) % 2 == 0 else Color(0.74, 0.72, 0.78, 1))
	_rc(0, 14, 16, 2, Color(0.62, 0.6, 0.7, 1))
	# 에어컨
	_begin("ac")
	_rc(0, 0, 16, 16, Color("#e9e4d6"))
	_rc(0, 0, 16, 2, Color("#f8f4e8"))
	_rc(2, 4, 12, 8, Color("#c9c4c4"))
	for y in [5, 8, 11]:
		_rc(2, y, 12, 1, Color("#8f8aa0"))
	_rc(0, 14, 16, 2, Color("#b5aeb8"))
	# 사다리(투명 바탕)
	_begin("ladder")
	_rc(4, 0, 2, 16, Color("#8a7a6a"))
	_rc(10, 0, 2, 16, Color("#8a7a6a"))
	for y in [1, 5, 9, 13]:
		_rc(4, y, 8, 1, Color("#a8957c"))
	# 대나무 비계 격자(투명 바탕)
	_begin("scaffold")
	var b0 := Color("#e3c268")
	var b1 := Color("#bd963f")
	_rc(0, 0, 2, 16, b0)
	_rc(8, 0, 2, 16, b0)
	_rc(1, 0, 1, 16, b1)
	_rc(9, 0, 1, 16, b1)
	_rc(0, 2, 16, 2, b0)
	_rc(0, 3, 16, 1, b1)
	_rc(0, 10, 16, 2, b0)
	_rc(0, 11, 16, 1, b1)
	for i in 6:
		_px(2 + i, 9 - i, b1)
	# 초록 안전망
	_begin("net")
	_rc(0, 0, 16, 16, Color("#4fae7c"))
	for i in 10:
		_m(_ri(8), _ri(8), 1 + _ri(2), 1, Color("#3f9a70"))
	for i in 5:
		_m(_ri(8), _ri(8), 1, 1 + _ri(2), Color("#62c08c"))
	for i in 3:
		_m(_ri(8), _ri(8), 1, 1, Color(0, 0, 0, 0))
	_rc(0, 0, 16, 1, Color("#2f7a5c"))
	# 물탱크 옆/위
	_begin("tank_side")
	_rc(0, 0, 16, 16, Color("#7fa9d4"))
	for x in [0, 8]:
		_rc(x, 0, 2, 16, Color("#93bbe0"))
	_rc(7, 0, 1, 16, Color("#5f86b8"))
	_rc(15, 0, 1, 16, Color("#5f86b8"))
	_rc(0, 0, 16, 2, Color("#a9cbea"))
	_rc(0, 8, 16, 1, Color("#5f86b8"))
	_begin("tank_top")
	_rc(0, 0, 16, 16, Color("#a9cbea"))
	_m(1, 1, 6, 6, Color("#93bbe0"))
	_m(3, 3, 2, 2, Color("#5f86b8"))
	_begin("steel_side")
	_rc(0, 0, 16, 16, Color("#b9bcc8"))
	_rc(0, 0, 16, 2, Color("#d6d8de"))
	for y in [5, 10]:
		_rc(0, y, 16, 1, Color("#8d90a6"))
	for i in 5:
		_m(_ri(8), 3 + _ri(5), 1, 1 + _ri(2), Color("#c58a62"))
	# 흙·작물
	_begin("soil")
	_rc(0, 0, 16, 16, Color("#8a6650"))
	for i in 10:
		_m(_ri(8), _ri(8), 1, 1, Color("#7a5848") if _rnd() < 0.5 else Color("#9a765a"))
	for k in 3:
		_begin("crops_%d" % k)
		_rc(0, 0, 16, 16, Color("#86624e"))
		var g0: Color = [Color("#7fc35a"), Color("#a6d85e"), Color("#5fae62")][k]
		for row in 4:
			_rc(0, row * 4, 16, 2, g0 if _rnd() < 0.85 else Color("#86624e"))
			for i in 4:
				_m(_ri(8), row * 2, 1, 1, lt(g0, 0.12) if _rnd() < 0.6 else dk(g0, 0.2))
			if k == 2 and _rnd() < 0.7:
				_m(_ri(8), row * 2, 1, 1, Color("#f0d24a"))
	# 화분(투명 바탕, 세로 쿼드)
	for k in 3:
		_begin("plant_%d" % k)
		var gc: Color = [Color("#6fb85a"), Color("#4f9f62"), Color("#9acb52")][k]
		_m(3, 6, 2, 2, Color("#c0714f"))
		_m(2, 3 - k % 2, 4, 3 + k % 2, gc)
		_m(3, 2 - k % 2, 2, 1, lt(gc, 0.1))
		_m(2 + _ri(4), 3, 1, 1, dk(gc, 0.2))
		if k == 2:
			_m(4, 3, 1, 1, Color("#ff8fb0"))
	# 빨래(흰 실루엣 → 정점색)
	_begin("cloth_shirt")
	_m(1, 1, 6, 2, Color.WHITE)
	_m(2, 3, 4, 4, Color.WHITE)
	_rc(4, 14, 8, 1, Color(0.8, 0.8, 0.86, 1))
	_begin("cloth_pants")
	_m(2, 1, 4, 3, Color.WHITE)
	_m(2, 4, 1, 4, Color.WHITE)
	_m(5, 4, 1, 4, Color.WHITE)
	_begin("cloth_sheet")
	_m(1, 1, 6, 6, Color.WHITE)
	_rc(2, 6, 12, 1, Color(0.82, 0.82, 0.88, 1))
	_rc(2, 13, 12, 1, Color(0.8, 0.8, 0.86, 1))
	_begin("cloth_towel")
	_m(2, 1, 3, 5, Color.WHITE)
	_rc(4, 8, 6, 1, Color(0.8, 0.8, 0.86, 1))
	# 상자·드럼
	_begin("crate")
	_rc(0, 0, 16, 16, Color("#d2a468"))
	_rc(0, 0, 16, 2, Color("#e6bd80"))
	_rc(0, 14, 16, 2, Color("#a67c54"))
	_rc(0, 7, 16, 1, Color("#a67c54"))
	_rc(7, 0, 1, 16, Color("#b88e5e"))
	# 등롱(발광)
	_begin("lantern")
	_m(3, 0, 2, 1, Color("#f2d27a"))
	_m(2, 1, 4, 4, emit(Color("#ff5a4a")))
	_m(3, 1, 2, 4, emit(Color("#ff8a5a")))
	_m(3, 5, 2, 1, Color("#f2d27a"))
	_px(7, 12, Color("#f2d27a"))
	_px(7, 13, Color("#f2d27a"))
	# 판자(다리·발판)
	_begin("plank")
	for p in 4:
		var tone: Color = [Color("#d9a56c"), Color("#c8935c"), Color("#b98452")][_ri(3)]
		_rc(0, p * 4, 16, 4, tone)
		_rc(0, p * 4 + 3, 16, 1, Color("#8f6248"))
	# 고물 더미
	_begin("junk")
	_rc(0, 0, 16, 16, Color("#8f8a9a"))
	for i in 14:
		_m(_ri(8), _ri(8), 1 + _ri(2), 1, [Color("#c97a55"), Color("#b9bcc8"), Color("#6f8fc0"), Color("#d2a468"), Color("#5c566e")][_ri(5)])
	# 안테나(16×32, 투명 바탕): 기둥은 2텍셀(×1에서 1px)
	for k in 3:
		_begin_tall("antenna_%d" % k)
		var ac := Color("#4a4664")
		var ah := Color("#7d7a98")
		_rc(8, 4 + k * 3, 2, 28 - k * 3, ac)
		if k == 0:
			for y in [6, 10, 14]:
				_rc(2, y, 12, 1, ah)
			_rc(4, 18, 10, 1, ah)
		elif k == 1:
			for y in [9, 12]:
				_rc(3, y, 12, 1, ah)
			_rc(2, 8, 1, 6, ah)
			_rc(14, 8, 1, 6, ah)
			_rc(6, 17, 8, 1, ah)
		else:
			for i in 5:
				_rc(5 - i / 2, 11 + i * 2, 8 + i, 1, ah)
	# 비둘기(작은 점 새, 투명) — fx에서 사용
	_begin("bird")
	_m(0, 0, 1, 1, Color("#e9e4f0"))
	_m(1, 1, 2, 1, Color("#cfc9dc"))
	_m(3, 0, 1, 1, Color("#e9e4f0"))
	_m(5, 1, 3, 1, Color("#cfc9dc"))
	_m(6, 0, 1, 1, Color("#e9e4f0"))


# ------------------------------------------------------------------ 지면
func _paint_ground() -> void:
	var d0 := Color("#cdb89c")
	var d1 := Color("#bfa78e")
	var d2 := Color("#a8907f")
	for v in 4:
		_begin("g_dirt_%d" % v, v)
		_rc(0, 0, 16, 16, d0)
		for i in 5 + v * 2:
			_m(_ri(8), _ri(8), 1 + _ri(2), 1, d1)
		for i in 2 + v:
			_m(_ri(8), _ri(8), 1, 1, d2)
		if v == 3:
			for i in 4:
				_m(_ri(7), _ri(7), 2, 1, Color("#b9bcc8"))
				_m(_ri(8), _ri(8), 1, 1, Color("#d98b74"))
	_begin("g_weeds")
	_rc(0, 0, 16, 16, d0)
	for i in 9:
		_m(_ri(8), _ri(8), 1, 1, Color("#8fb86a") if _rnd() < 0.6 else Color("#6f9f5c"))
	for i in 4:
		_m(_ri(8), _ri(8), 1, 1, d1)
	_begin("g_puddle")
	_rc(0, 0, 16, 16, d0)
	_m(2, 3, 5, 3, glass(Color("#7f9cc0")))
	_m(1, 4, 6, 1, glass(Color("#7f9cc0")))
	_m(3, 2, 2, 1, glass(Color("#7f9cc0")))
	_m(4, 6, 2, 1, glass(Color("#7f9cc0")))
	_m(3, 4, 2, 1, glass(Color("#a9c2dc")))
	for i in 3:
		_m(_ri(8), _ri(2), 1, 1, d1)
	_begin("g_slab")    # 옛 기초 콘크리트 판
	_rc(0, 0, 16, 16, Color("#d2c8c0"))
	_rc(0, 0, 16, 1, Color("#b5aab0"))
	_rc(0, 0, 1, 16, Color("#b5aab0"))
	for i in 4:
		_m(_ri(8), _ri(8), 2, 1, Color("#c4b9b6"))
	for i in 5:
		_px(4 + i, 5 + i + _ri(2), Color("#978ca0"))
	var a0 := Color("#8f8ea6")
	var a1 := Color("#85849e")
	for v in 2:
		_begin("g_asphalt_%d" % v, v)
		_rc(0, 0, 16, 16, a0)
		for i in 6:
			_m(_ri(8), _ri(8), 1 + _ri(2), 1, a1)
		if v == 1:
			_m(_ri(6), _ri(6), 2, 2, Color("#7a7994"))
	_begin("g_line")
	_rc(0, 0, 16, 16, a0)
	_rc(0, 6, 10, 4, Color("#e9e2c8"))
	_begin("g_walk")
	_rc(0, 0, 16, 16, Color("#cfc7c2"))
	_rc(0, 0, 16, 1, Color("#b3aab0"))
	_rc(0, 0, 1, 16, Color("#b3aab0"))
	_rc(8, 0, 1, 16, Color("#bdb4b8"))
	_rc(0, 8, 16, 1, Color("#bdb4b8"))
	_begin("g_far")
	_rc(0, 0, 16, 16, Color("#bdb4b4"))
	for i in 5:
		_m(_ri(8), _ri(8), 2, 1, Color("#b0a7ac"))
	# 담장
	_begin("lotwall")
	for row in 4:
		var off := (row % 2) * 4
		for b in range(-1, 3):
			var tone: Color = [Color("#c9b2a4"), Color("#bda294"), Color("#d4bfae")][_ri(3)]
			_rc(b * 8 + off, row * 4, 8, 4, tone)
			_rc(b * 8 + off + 7, row * 4, 1, 3, Color("#9b8388"))
		_rc(0, row * 4 + 3, 16, 1, Color("#a48c8c"))
	for i in 3:
		_m(_ri(8), 5 + _ri(3), 1 + _ri(2), 1, Color("#7fa06c"))
	_begin("lotwall_top")
	_rc(0, 0, 16, 16, Color("#dccbb8"))
	for i in 4:
		_m(_ri(8), _ri(8), 1, 1, Color("#c4b0a2"))
	_begin("stone")
	_rc(0, 0, 16, 16, Color("#b9b4c0"))
	_rc(0, 0, 16, 2, Color("#d2cdd6"))
	for i in 5:
		_m(_ri(8), _ri(8), 1, 1, Color("#a39eb0"))
	for i in 3:
		_m(_ri(8), 5 + _ri(3), 1, 1, Color("#8fae7a"))


# ------------------------------------------------------------------ 실내(층 컷)
func _paint_interiors() -> void:
	_begin("f_wood")
	for p in 4:
		var tone: Color = [Color("#e0b684"), Color("#d6a874"), Color("#cc9c6a")][_ri(3)]
		_rc(0, p * 4, 16, 4, tone)
		_rc(0, p * 4 + 3, 16, 1, Color("#b3835c"))
		_rc(_ri(8) * 2, p * 4, 1, 3, Color("#b3835c"))
	_begin("f_tile")
	_rc(0, 0, 16, 16, Color("#e6e2d6"))
	for i in 4:
		_rc(i * 4 + 3, 0, 1, 16, Color("#c4c0c0"))
		_rc(0, i * 4 + 3, 16, 1, Color("#c4c0c0"))
	_begin("f_checker")
	for y in 4:
		for x in 4:
			_rc(x * 4, y * 4, 4, 4, Color("#eef0ea") if (x + y) % 2 == 0 else Color("#8fc0b8"))
	_begin("f_concrete")
	_rc(0, 0, 16, 16, Color("#c9c4c4"))
	for i in 5:
		_m(_ri(8), _ri(8), 1 + _ri(2), 1, Color("#bcb6ba"))
	_begin("f_mat")
	_rc(0, 0, 16, 16, Color("#d9cf8e"))
	for y in [3, 7, 11, 15]:
		_rc(0, y, 16, 1, Color("#bdb274"))
	_rc(7, 0, 1, 16, Color("#9aa05c"))
	_begin("f_carpet")
	_rc(0, 0, 16, 16, Color("#b8485a"))
	_m(1, 1, 6, 6, Color("#c95a66"))
	_m(3, 3, 2, 2, Color("#e6b45a"))
	_begin("f_dirt")
	_rc(0, 0, 16, 16, Color("#b89e86"))
	for i in 6:
		_m(_ri(8), _ri(8), 1 + _ri(2), 1, Color("#a88e7a"))
	_begin("f_soil")
	_rc(0, 0, 16, 16, Color("#8a6650"))
	for i in 8:
		_m(_ri(8), _ri(8), 1, 1, Color("#7a5848"))
	_begin("cutcap")
	_rc(0, 0, 16, 16, Color("#3a3454"))
	# 가구 윗면
	_begin("bed")
	_rc(0, 0, 16, 16, Color("#e9e2d2"))
	_rc(0, 0, 16, 4, Color("#f8f4ea"))
	_m(1, 0, 3, 2, Color("#c9d4ea"))
	_rc(0, 6, 16, 10, Color("#7f9ad0"))
	_rc(0, 6, 16, 1, Color("#a9bce0"))
	_begin("bed_red")
	_rc(0, 0, 16, 16, Color("#e9e2d2"))
	_m(1, 0, 3, 2, Color("#f4ead2"))
	_rc(0, 6, 16, 10, Color("#d0705f"))
	_rc(0, 6, 16, 1, Color("#e69a84"))
	_begin("mat")
	_rc(0, 0, 16, 16, Color("#cdbf7c"))
	for y in [3, 7, 11]:
		_rc(0, y, 16, 1, Color("#b0a468"))
	_m(0, 0, 3, 2, Color("#e6dcc4"))
	_begin("stove")
	_rc(0, 0, 16, 16, Color("#8f8ea6"))
	_m(1, 1, 3, 3, Color("#3e3a54"))
	_m(5, 1, 2, 3, Color("#3e3a54"))
	_m(2, 2, 1, 1, emit(Color("#ff8a3d")))
	_m(1, 5, 4, 2, Color("#d6d8de"))
	_m(2, 5, 2, 2, Color("#f4ead2"))
	_begin("mj_table")
	_rc(0, 0, 16, 16, Color("#4f9a6a"))
	_rc(0, 0, 16, 2, Color("#8a6a5a"))
	_rc(0, 14, 16, 2, Color("#8a6a5a"))
	_rc(0, 0, 2, 16, Color("#8a6a5a"))
	_rc(14, 0, 2, 16, Color("#8a6a5a"))
	for i in 7:
		_m(1 + _ri(6), 1 + _ri(6), 1, 1, Color("#f8f4ea"))
	_begin("desk")
	_rc(0, 0, 16, 16, Color("#c8a47c"))
	_m(1, 1, 3, 2, Color("#3e3a54"))
	_m(2, 1, 1, 1, emit(Color("#8fd0ff")))
	_m(5, 2, 2, 1, Color("#f8f4ea"))
	_m(1, 5, 2, 2, Color("#d85f5f"))
	_begin("sewing")
	_rc(0, 0, 16, 16, Color("#c8a47c"))
	_m(2, 2, 4, 2, Color("#3e3a54"))
	_m(5, 2, 1, 3, Color("#3e3a54"))
	_m(1, 5, 5, 2, Color("#e8a0b8"))
	_begin("vat")
	_rc(0, 0, 16, 16, Color("#b9bcc8"))
	_m(1, 1, 6, 6, Color("#e9d8a6"))
	for i in 8:
		_m(1 + _ri(6), 1 + _ri(6), 1, 1, Color("#fffaf0"))
	_begin("noodles")
	_rc(0, 0, 16, 16, Color("#c8a47c"))
	for x in [1, 3, 5, 7]:
		_rc(x * 2 - 1, 1, 2, 14, Color("#f6e7b0"))
	_begin("chair_dentist")
	_rc(0, 0, 16, 16, Color("#eef0ea"))
	_m(1, 1, 6, 6, Color("#7fc0c8"))
	_m(2, 1, 4, 2, Color("#a9dce0"))
	_m(6, 0, 2, 2, Color("#d6d8de"))
	_begin("bunk")
	_rc(0, 0, 16, 16, Color("#7f8a8a"))
	for y in [0, 5, 10, 15]:
		_rc(0, y, 16, 1, Color("#5a6466"))
	for x in [0, 5, 10, 15]:
		_rc(x, 0, 1, 16, Color("#5a6466"))
	_m(1, 1, 2, 1, Color("#e9e2d2"))
	_m(4, 4, 2, 1, Color("#d0705f"))
	_begin("shelf")
	_rc(0, 0, 16, 16, Color("#a67c54"))
	for y in [0, 5, 10]:
		_rc(0, y, 16, 1, Color("#7a5848"))
		for i in 5:
			_m(_ri(8), y / 2 + 1, 1, 1, [Color("#e6b45a"), Color("#8fc0b8"), Color("#d85f5f"), Color("#f4ead2"), Color("#9b62c9")][_ri(5)])
	_begin("slot")
	_rc(0, 0, 16, 16, Color("#b0306a"))
	_m(1, 1, 6, 3, emit(Color("#ffd84a")))
	_m(2, 2, 1, 1, emit(Color("#ff5a4a")))
	_m(4, 2, 1, 1, emit(Color("#4fe3ff")))
	_m(1, 5, 6, 2, Color("#5c2a56"))
	_begin("altar")
	_rc(0, 0, 16, 16, Color("#c2463c"))
	_m(1, 1, 6, 2, Color("#f2d27a"))
	_m(3, 4, 2, 2, emit(Color("#ffb04a")))
	_m(1, 6, 6, 1, Color("#8a2f34"))
	_begin("water")
	_rc(0, 0, 16, 16, Color("#6fb4d8"))
	for i in 5:
		_m(_ri(7), _ri(8), 2, 1, Color("#a9dcee"))
	_begin("water_fish")
	_rc(0, 0, 16, 16, Color("#5fa6c8"))
	for i in 4:
		_m(_ri(7), _ri(8), 2, 1, Color("#8fcbe0"))
	for i in 4:
		_m(_ri(7), _ri(8), 2, 1, Color("#ff9a4a"))
	_begin("machine")
	_rc(0, 0, 16, 16, Color("#7f8fae"))
	_rc(0, 0, 16, 2, Color("#a3b1c8"))
	_m(1, 2, 3, 3, Color("#566a98"))
	_m(5, 2, 2, 2, Color("#e6b45a"))
	_m(5, 5, 2, 1, emit(Color("#ff5a4a")))
	_begin("tv")
	_rc(0, 0, 16, 16, Color("#4a4664"))
	_m(1, 1, 6, 5, emit(Color("#8fd0ff")))
	_m(2, 2, 2, 1, emit(Color("#d6f0ff")))


# ------------------------------------------------------------------ 간판 글자
func _load_fonts() -> void:
	_fonts.clear()
	for spec in [["res://assets/view/fonts/FusionPixel12-zh_hk.ttf", 12], ["res://assets/fonts/Galmuri11.ttf", 11]]:
		if ResourceLoader.exists(spec[0]):
			var f: Variant = load(spec[0])
			if f is FontFile:
				_fonts.append([f, spec[1]])


## 글자열을 아틀라스에 굽고 텍셀 사각형을 돌려준다. vertical=true면 세로쓰기.
func sign_rect(text: String, vertical: bool) -> Rect2i:
	var key := ("v:" if vertical else "h:") + text
	if _signs.has(key):
		return _signs[key]
	var glyphs: Array = []
	for i in text.length():
		var g: Variant = _glyph(text.unicode_at(i))
		if g != null:
			glyphs.append(g)
	if glyphs.is_empty():
		_signs[key] = Rect2i(0, 0, 0, 0)
		return _signs[key]
	var cell := 12
	var w := 0
	var h := 0
	if vertical:
		w = cell
		h = cell * glyphs.size() + (glyphs.size() - 1)
	else:
		for g in glyphs:
			w += int(g["adv"]) + 1
		w -= 1
		h = cell
	if _sign_x + w + 1 > SIZE:
		_sign_x = 0
		_sign_y += 40
	if _sign_y + h > SIZE:
		_signs[key] = Rect2i(0, 0, 0, 0)
		return _signs[key]
	var ox := _sign_x
	var oy := _sign_y
	var cx := 0
	var cy := 0
	for g in glyphs:
		var gi: Image = g["img"]
		var src: Rect2i = g["src"]
		var off: Vector2i = g["off"]
		var adv: int = int(g["adv"])
		var bx := ox + cx + (((cell - adv) / 2) if vertical else 0)
		var by := oy + cy
		for yy in src.size.y:
			for xx in src.size.x:
				if gi.get_pixel(src.position.x + xx, src.position.y + yy).a > 0.5:
					var tx := bx + off.x + xx
					var ty := by + off.y + yy
					if tx >= ox and ty >= oy and tx < ox + w and ty < oy + h:
						img.set_pixel(tx, ty, Color.WHITE)
		if vertical:
			cy += cell + 1
		else:
			cx += adv + 1
	_sign_x += w + 2
	var r := Rect2i(ox, oy, w, h)
	_signs[key] = r
	dirty = true
	return r


func _glyph(code: int) -> Variant:
	for fs in _fonts:
		var f: FontFile = fs[0]
		var px: int = fs[1]
		if not f.has_char(code):
			continue
		var size := Vector2i(px, 0)
		var gidx := f.get_glyph_index(px, code, 0)
		if gidx == 0:
			continue
		f.render_glyph(0, size, gidx)
		var ti := f.get_glyph_texture_idx(0, size, gidx)
		if ti < 0:
			# 공백 등
			return {"img": Image.create(1, 1, false, Image.FORMAT_RGBA8), "src": Rect2i(0, 0, 0, 0), "off": Vector2i.ZERO, "adv": 4}
		var gimg := f.get_texture_image(0, size, ti)
		if gimg == null:
			continue
		if gimg.get_format() != Image.FORMAT_RGBA8:
			gimg = gimg.duplicate()
			gimg.convert(Image.FORMAT_RGBA8)
		var uv := f.get_glyph_uv_rect(0, size, gidx)
		var off := f.get_glyph_offset(0, size, gidx)
		var adv := f.get_glyph_advance(0, px, gidx)
		var asc := f.get_cache_ascent(0, px)
		return {"img": gimg, "src": Rect2i(uv), "off": Vector2i(int(round(off.x)), int(round(asc + off.y))), "adv": maxi(int(round(adv.x)), int(uv.size.x))}
	return null
