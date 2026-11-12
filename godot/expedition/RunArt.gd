extends RefCounted
## 직접 줍기 그림 — 코드로 그린 픽셀(바닥·벽·폐차·쥐·들개·압축기·더미·물건 아이콘)과
## assets/run 의 CC0 사람 그림(테두리를 덧그려 바닥에서 잘 보이게)을 만든다. 전부 처음 한 번만 만들고 캐시.

const DungeonGen = preload("res://expedition/DungeonGen.gd")
const RunCfg = preload("res://expedition/RunCfg.gd")

const OUT := Color("1a1418")
const TS := 16

static var _cache: Dictionary = {}


static func tex(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var img: Image = null
	match key:
		"rat0": img = _rat(0)
		"rat1": img = _rat(1)
		"dog0": img = _dog(0)
		"dog1": img = _dog(1)
		"dog_tele": img = _dog(2)
		"dog_lunge": img = _dog(3)
		"pile": img = _pile(false)
		"pile_empty": img = _pile(true)
		"junk": img = _junk()
		"locker": img = _locker(false)
		"locker_open": img = _locker(true)
		"can": img = _can()
		"brick": img = _brick()
		"heal": img = _heal()
		"big": img = _big()
		"exit_entrance": img = _exit_hole()
		"exit_mid": img = _manhole()
		"exit_boss": img = _gate()
		"boss_head": img = _boss_head(false)
		"boss_head_stuck": img = _boss_head(true)
		"cube": img = _cube()
		"heart": img = _heart(1)
		"heart_half": img = _heart(2)
		"heart_empty": img = _heart(0)
		"shadow": img = _shadow(12, 5)
		"shadow_big": img = _shadow(20, 7)
		_:
			if key.begins_with("good_"):
				img = _good_icon(key.substr(5))
			elif key.begins_with("char_"):
				img = _outlined((load("res://assets/run/%s.png" % key) as Texture2D).get_image())
	if img == null:
		img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func kenney() -> Texture2D:
	if not _cache.has("kenney"):
		_cache["kenney"] = load("res://assets/run/kenney_tiny_factory.png")
	return _cache["kenney"]


static func kenney_img() -> Image:
	if not _cache.has("kenney_img"):
		var ki := kenney().get_image()
		ki.convert(Image.FORMAT_RGBA8)
		_cache["kenney_img"] = ki
	return _cache["kenney_img"]


# ------------------------------------------------------------------ 바탕 도구
static func _new(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(maxi(0, y), mini(img.get_height(), y + h)):
		for xx in range(maxi(0, x), mini(img.get_width(), x + w)):
			img.set_pixel(xx, yy, c)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry - 1), int(cy + ry + 2)):
		for x in range(int(cx - rx - 1), int(cx + rx + 2)):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)


## 불투명 픽셀 둘레에 1px 어두운 테두리를 덧그린다.
static func _outline(img: Image, col: Color = OUT) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var o := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	o.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					o.set_pixel(x + 1 + d.x, y + 1 + d.y, col)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				o.set_pixel(x + 1, y + 1, c)
	return o


static func _outlined(img: Image) -> Image:
	# 16x32 칸 시트에 칸마다 테두리(칸 밖으로 나가지 않게 같은 크기 유지)
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var o := img.duplicate() as Image
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				continue
			var near := false
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				if nx / 16 != x / 16 or ny / 32 != y / 32:
					continue
				if img.get_pixel(nx, ny).a > 0.5:
					near = true
			if near:
				o.set_pixel(x, y, OUT)
	return o


static func hash01(x: int, y: int, s: int = 0) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 10000) / 10000.0


# ------------------------------------------------------------------ 지도 조각
## 타일 배열에서 (cx,cy) 조각(32x32 타일)을 그린 이미지. 비어 있으면 null.
static func map_chunk(tiles: PackedByteArray, w: int, h: int, cx: int, cy: int, size: int = 32) -> Image:
	var img := Image.create(size * TS, size * TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var any := false
	for ty in range(cy * size, mini(h, (cy + 1) * size)):
		for tx in range(cx * size, mini(w, (cx + 1) * size)):
			var code := tiles[ty * w + tx]
			if code == DungeonGen.VOID:
				continue
			any = true
			_tile(img, tiles, w, h, tx, ty, (tx - cx * size) * TS, (ty - cy * size) * TS)
	return img if any else null


static func _t(tiles: PackedByteArray, w: int, h: int, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return DungeonGen.VOID
	return tiles[y * w + x]


static func _floor(img: Image, tx: int, ty: int, ox: int, oy: int, base: Color, var_amt: float) -> void:
	for y in TS:
		for x in TS:
			var r := hash01(tx * 16 + x, ty * 16 + y)
			var c := base
			if r < 0.12:
				c = base.darkened(var_amt)
			elif r > 0.94:
				c = base.lightened(var_amt * 0.8)
			img.set_pixel(ox + x, oy + y, c)
	# 바닥 장식(드물게): 잡초, 나사, 신문지, 바퀴 자국
	var deco := hash01(tx, ty, 70)
	if deco < 0.035:
		for g in 4:
			_rect(img, ox + 5 + g * 2, oy + 9 - (g % 2) * 2, 1, 3 + (g % 2) * 2, Color("5f6e3c"))
	elif deco < 0.11:
		for x in range(0, 16, 3):
			_rect(img, ox + x, oy + 6, 2, 1, base.darkened(0.25))
			_rect(img, ox + x + 1, oy + 11, 2, 1, base.darkened(0.25))
	# 자갈·얼룩
	var k := hash01(tx, ty, 7)
	if k < 0.18:
		var px := int(hash01(tx, ty, 8) * 12) + 2
		var py := int(hash01(tx, ty, 9) * 12) + 2
		_rect(img, ox + px, oy + py, 2, 1, base.lightened(0.18))
		_px(img, ox + px, oy + py + 1, base.darkened(0.3))
	elif k > 0.93:
		_rect(img, ox + 3, oy + 7, 5, 1, base.darkened(0.2))
		_rect(img, ox + 5, oy + 8, 4, 1, base.darkened(0.15))


static func _tile(img: Image, tiles: PackedByteArray, w: int, h: int, tx: int, ty: int, ox: int, oy: int) -> void:
	var code := tiles[ty * w + tx]
	var dirt := Color("6a5846")
	match code:
		DungeonGen.FLOOR, DungeonGen.JUNK, DungeonGen.RUBBLE:
			_floor(img, tx, ty, ox, oy, dirt, 0.12)
			if code == DungeonGen.RUBBLE:
				for k in 7:
					_rect(img, ox + int(hash01(tx, k, 3) * 13), oy + int(hash01(ty, k, 4) * 13), 3, 2, Color("8a7a6a").darkened(hash01(k, tx) * 0.4))
		DungeonGen.GRAVEL:
			_floor(img, tx, ty, ox, oy, Color("6f685e"), 0.18)
		DungeonGen.OIL:
			_floor(img, tx, ty, ox, oy, dirt, 0.12)
			for y in range(2, 14):
				for x in range(1, 15):
					var dx := (x - 7.5) / 7.0
					var dy := (y - 7.5) / 5.5
					if dx * dx + dy * dy < 1.0:
						img.set_pixel(ox + x, oy + y, Color("2b2630") if hash01(tx * 16 + x, ty * 16 + y, 2) > 0.1 else Color("4b4566"))
		DungeonGen.HALL, DungeonGen.DOOR:
			_floor(img, tx, ty, ox, oy, Color("5a5550"), 0.1)
			if hash01(tx, ty, 5) < 0.3:
				_rect(img, ox + 2, oy + int(hash01(tx, ty, 6) * 14), 11, 1, Color("4a4540"))
			if code == DungeonGen.DOOR:
				for x in range(0, 16, 4):
					_rect(img, ox + x, oy, 2, 16, Color("4d4740"))
		DungeonGen.WIRE:
			_floor(img, tx, ty, ox, oy, dirt, 0.12)
			for y in TS:
				for x in TS:
					var e := 0
					for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						if _t(tiles, w, h, tx + d.x, ty + d.y) != DungeonGen.WIRE:
							if (d.x == -1 and x < 2) or (d.x == 1 and x > 13) or (d.y == -1 and y < 2) or (d.y == 1 and y > 13):
								e += 1
					if e == 0:
						img.set_pixel(ox + x, oy + y, Color("23324a") if hash01(tx * 16 + x, ty * 16 + y, 4) > 0.07 else Color("4f78a8"))
			# 늘어진 전선
			if hash01(tx, ty, 11) < 0.35:
				for x in range(1, 15):
					_px(img, ox + x, oy + 6 + int(sin(x * 0.5 + tx) * 2.0), Color("151515"))
		DungeonGen.WALL:
			var below := _t(tiles, w, h, tx, ty + 1)
			var front := not DungeonGen.is_solid_code(below)
			if front:
				# 녹슨 골함석 담 앞면
				var rust := Color("7d4430") if hash01(tx, ty, 1) < 0.5 else Color("6a5040")
				if hash01(tx, ty, 2) < 0.2:
					rust = Color("4f5a5e")
				for y in TS:
					for x in TS:
						var c := rust
						if x % 4 == 0:
							c = rust.darkened(0.3)
						elif x % 4 == 1:
							c = rust.lightened(0.15)
						if hash01(tx * 16 + x, ty * 16 + y, 3) < 0.08:
							c = Color("a0582c")
						if y >= 14:
							c = Color("2a2020")
						img.set_pixel(ox + x, oy + y, c)
				_rect(img, ox, oy, 16, 2, Color("3a2e2a"))
			else:
				# 담 윗면 / 쌓인 고철
				for y in TS:
					for x in TS:
						var r := hash01(tx * 16 + x, ty * 16 + y, 5)
						var c := Color("3b322f")
						if r < 0.15:
							c = Color("2d2624")
						elif r > 0.9:
							c = Color("554641")
						img.set_pixel(ox + x, oy + y, c)
				if hash01(tx, ty, 12) < 0.4:
					var jc := [Color("6d4a3a"), Color("566068"), Color("5f6b4a"), Color("7a6a50")][int(hash01(tx, ty, 13) * 4) % 4] as Color
					_rect(img, ox + int(hash01(tx, ty, 14) * 9), oy + int(hash01(tx, ty, 15) * 10), 5, 3, jc)
		DungeonGen.CAR:
			_floor(img, tx, ty, ox, oy, dirt, 0.12)
			_car_cell(img, tiles, w, h, tx, ty, ox, oy)
		DungeonGen.TIRE:
			_floor(img, tx, ty, ox, oy, dirt, 0.12)
			_ellipse(img, ox + 8, oy + 9, 8, 7, OUT)
			_ellipse(img, ox + 8, oy + 9, 7, 6, Color("2c2729"))
			_ellipse(img, ox + 8, oy + 8, 7, 5.5, Color("373133"))
			_ellipse(img, ox + 8, oy + 8, 3, 2.5, Color("1c181a"))
			_rect(img, ox + 3, oy + 7, 2, 1, Color("4a4446"))
		DungeonGen.BOX:
			_floor(img, tx, ty, ox, oy, dirt, 0.12)
			var choice := int(hash01(tx, ty, 21) * 3)
			var src: Vector2i = [Vector2i(1, 6), Vector2i(2, 6), Vector2i(0, 8)][choice]
			var kimg := kenney_img()
			img.blend_rect(kimg, Rect2i(src * 16, Vector2i(16, 16)), Vector2i(ox, oy))
		DungeonGen.PRESS:
			_floor(img, tx, ty, ox, oy, dirt, 0.12)
			_press_cell(img, tiles, w, h, tx, ty, ox, oy)


static func _car_cell(img: Image, tiles: PackedByteArray, w: int, h: int, tx: int, ty: int, ox: int, oy: int) -> void:
	# 같은 덩어리의 왼쪽 위 칸을 찾아 덩어리 크기를 잰다
	var x0 := tx
	while _t(tiles, w, h, x0 - 1, ty) == DungeonGen.CAR:
		x0 -= 1
	var y0 := ty
	while _t(tiles, w, h, tx, y0 - 1) == DungeonGen.CAR:
		y0 -= 1
	var x1 := tx
	while _t(tiles, w, h, x1 + 1, ty) == DungeonGen.CAR:
		x1 += 1
	var y1 := ty
	while _t(tiles, w, h, tx, y1 + 1) == DungeonGen.CAR:
		y1 += 1
	var cw := (x1 - x0 + 1) * TS
	var ch := (y1 - y0 + 1) * TS
	var lx := (tx - x0) * TS
	var ly := (ty - y0) * TS
	var bodies := [Color("8a3a36"), Color("3a5a86"), Color("6a7838"), Color("a08a4e"), Color("6e6e74")]
	var body: Color = bodies[int(hash01(x0, y0, 31) * bodies.size()) % bodies.size()]
	var horiz := cw >= ch
	for y in TS:
		for x in TS:
			var X := lx + x
			var Y := ly + y
			# 둥근 모서리 몸체
			var inset := 1
			var corner := 3
			var inside := X >= inset and Y >= inset + 1 and X < cw - inset and Y < ch - inset
			if inside:
				var cxd := mini(X - inset, cw - inset - 1 - X)
				var cyd := mini(Y - inset - 1, ch - inset - 1 - Y)
				if cxd < corner and cyd < corner and (corner - cxd) + (corner - cyd) > corner + 1:
					inside = false
			if not inside:
				continue
			var edge := X == inset or Y == inset + 1 or X == cw - inset - 1 or Y == ch - inset - 1
			var c := body
			if edge:
				c = OUT
			else:
				# 지붕/유리
				var roof := false
				var glass := false
				if horiz:
					roof = X > cw * 0.3 and X < cw * 0.72 and Y > 3 and Y < ch - 4
					glass = roof and (X < cw * 0.36 or X > cw * 0.66)
				else:
					roof = Y > ch * 0.3 and Y < ch * 0.72 and X > 3 and X < cw - 4
					glass = roof and (Y < ch * 0.36 or Y > ch * 0.66)
				if glass:
					c = Color("26323c") if hash01(X + x0 * 16, Y + y0 * 16, 33) > 0.15 else Color("5f7a8a")
				elif roof:
					c = body.lightened(0.12)
				elif Y < ch * 0.3 and not horiz:
					c = body.darkened(0.05)
				if hash01(X + x0 * 16, Y + y0 * 16, 34) < 0.07:
					c = Color("8a4a26")
				if Y == ch - inset - 2:
					c = body.darkened(0.35)
			img.set_pixel(ox + x, oy + y, c)


static func _press_cell(img: Image, tiles: PackedByteArray, w: int, h: int, tx: int, ty: int, ox: int, oy: int) -> void:
	var x0 := tx
	while _t(tiles, w, h, x0 - 1, ty) == DungeonGen.PRESS:
		x0 -= 1
	var y0 := ty
	while _t(tiles, w, h, tx, y0 - 1) == DungeonGen.PRESS:
		y0 -= 1
	var x1 := tx
	while _t(tiles, w, h, x1 + 1, ty) == DungeonGen.PRESS:
		x1 += 1
	var y1 := ty
	while _t(tiles, w, h, tx, y1 + 1) == DungeonGen.PRESS:
		y1 += 1
	var cw := (x1 - x0 + 1) * TS
	var ch := (y1 - y0 + 1) * TS
	for y in TS:
		for x in TS:
			var X := (tx - x0) * TS + x
			var Y := (ty - y0) * TS + y
			var c := Color("56606a")
			if X == 0 or Y == 0 or X == cw - 1 or Y == ch - 1:
				c = OUT
			elif Y > ch - 8:
				# 아가리 위 경고 줄무늬
				c = Color("e0b020") if ((X + Y) / 4) % 2 == 0 else Color("201c1c")
				if Y > ch - 3:
					c = Color("15110f")
			elif Y < 5:
				c = Color("6c7884")
			elif X % 12 == 0:
				c = Color("3e464e")
			if X > cw / 2 - 10 and X < cw / 2 + 10 and Y > 6 and Y < ch - 10:
				c = Color("2a2a30") if (Y % 3 != 0) else Color("44444c")
			img.set_pixel(ox + x, oy + y, c)


# ------------------------------------------------------------------ 생물
static func _rat(frame: int) -> Image:
	var img := _new(12, 8)
	var body := Color("75685e")
	_ellipse(img, 6, 4.5, 4.2, 2.6, body)
	_ellipse(img, 6.5, 3.8, 3.0, 1.4, body.lightened(0.12))
	_rect(img, 9, 3, 2, 2, body)          # 머리
	_px(img, 11, 4, Color("e8a0a0"))      # 코
	_px(img, 9, 2, Color("e0a0a0"))       # 귀
	_px(img, 10, 3, Color("101010"))      # 눈
	# 꼬리
	for x in 3:
		_px(img, 1 - x + 1, 4 + (x % 2 if frame == 0 else (x + 1) % 2), Color("d89090"))
	_px(img, 0, 5 if frame == 0 else 3, Color("d89090"))
	# 다리
	_px(img, 4 + frame, 7, Color("3a3030"))
	_px(img, 8 - frame, 7, Color("3a3030"))
	return _outline(img)


static func _dog(frame: int) -> Image:
	var img := _new(20, 13)
	var fur := Color("9a6a3a")
	var dark := Color("6a4626")
	var body_y := 6.0
	var head := Vector2(16, 4)
	if frame == 2:   # 으르렁: 몸 낮추고 머리 앞으로
		body_y = 7.0
		head = Vector2(17, 6)
	elif frame == 3: # 덮침: 길게
		head = Vector2(18, 5)
	_ellipse(img, 9, body_y, 6.5 if frame != 3 else 7.5, 3.2, fur)
	_ellipse(img, 8, body_y - 1, 4, 1.5, fur.lightened(0.1))
	_rect(img, 5, int(body_y) - 2, 4, 2, dark)        # 얼룩
	_ellipse(img, head.x, head.y, 3, 2.6, fur)
	_rect(img, int(head.x) + 1, int(head.y), 3, 2, fur.lightened(0.1))   # 주둥이
	_px(img, int(head.x) + 3, int(head.y), Color("151010"))              # 코
	_px(img, int(head.x), int(head.y) - 1, Color("101010") if frame != 2 else Color("ff3030"))  # 눈
	_rect(img, int(head.x) - 2, int(head.y) - 3, 2, 2, dark)             # 귀
	if frame == 2:
		_rect(img, int(head.x) + 1, int(head.y) + 2, 3, 1, Color("f0f0f0"))  # 이빨
	# 꼬리
	_rect(img, 1, int(body_y) - 3 + (frame % 2), 3, 1, fur)
	# 다리
	var lg: int = [0, 1, 0, 2][frame]
	_rect(img, 5 - lg, int(body_y) + 2, 1, 3, dark)
	_rect(img, 7 + lg, int(body_y) + 2, 1, 3, dark)
	_rect(img, 11 - lg, int(body_y) + 2, 1, 3, dark)
	_rect(img, 13 + lg, int(body_y) + 2, 1, 3, dark)
	return _outline(img)


# ------------------------------------------------------------------ 물건
static func _pile(empty: bool) -> Image:
	var img := _new(22, 15)
	if empty:
		# 다 털린 더미: 납작하게 흩어진 부스러기(구멍처럼 보이지 않게 밝은 흙빛)
		_ellipse(img, 11, 10, 9.5, 3.5, Color("7a6650"))
		for k in 9:
			_rect(img, 3 + int(hash01(k, 5, 44) * 15), 7 + int(hash01(k, 6, 45) * 5), 2, 1, [Color("5f5348"), Color("8a7a66"), Color("6f7d88")][k % 3])
		return _outline(img, Color("3a2e26"))
	var base := Color("5a4c3c")
	_ellipse(img, 11, 10, 10.5, 4.5, base.darkened(0.2))
	_ellipse(img, 11, 8.5, 9, 5, base)
	var cols := [Color("8a4a30"), Color("6f7d88"), Color("a58a52"), Color("5f7048"), Color("b0b0a8"), Color("3c5a8a")]
	for k in 14:
		var x := 3 + int(hash01(k, 1, 40) * 15)
		var y := 4 + int(hash01(k, 2, 41) * 8)
		_rect(img, x, y, 2 + int(hash01(k, 3, 42) * 3), 1 + int(hash01(k, 4, 43) * 2), cols[k % cols.size()])
	_rect(img, 9, 2, 1, 5, Color("888888"))   # 삐죽 나온 파이프
	_rect(img, 14, 3, 3, 1, Color("c09050"))
	return _outline(img)


static func _junk() -> Image:
	# 위태롭게 쌓인 고철 탑: 타이어·상자·세탁기·차문·파이프
	var img := _new(22, 28)
	# 맨 아래 타이어 두 개
	_ellipse(img, 6, 24, 5.5, 3.2, Color("2a2628"))
	_ellipse(img, 6, 23.5, 2, 1.2, Color("141012"))
	_ellipse(img, 16, 24, 5.5, 3.2, Color("2a2628"))
	_ellipse(img, 16, 23.5, 2, 1.2, Color("141012"))
	# 나무 상자
	_rect(img, 3, 15, 9, 7, Color("8a6038"))
	_rect(img, 3, 15, 9, 1, Color("a87a48"))
	_rect(img, 7, 15, 1, 7, Color("5a3c20"))
	# 세탁기
	_rect(img, 11, 12, 9, 10, Color("c8c8c0"))
	_rect(img, 11, 12, 9, 2, Color("a0a098"))
	_ellipse(img, 15.5, 17.5, 3, 3, Color("4a5058"))
	_ellipse(img, 15.5, 17.5, 1.6, 1.6, Color("7a8a98"))
	# 비스듬한 차문(빨강)
	for k in 9:
		_rect(img, 4 + k, 10 - k / 2, 2, 4, Color("9a3a32"))
	_rect(img, 7, 7, 4, 2, Color("26323c"))
	# 꼭대기 양동이·파이프
	_rect(img, 9, 2, 5, 4, Color("6a7a84"))
	_rect(img, 9, 2, 5, 1, Color("8a9aa4"))
	_rect(img, 15, 1, 1, 9, Color("8a8a8a"))
	_rect(img, 14, 1, 3, 1, Color("8a8a8a"))
	return _outline(img)


static func _locker(open: bool) -> Image:
	# 넘어진 철제 사물함(자물쇠) — 더미보다 반듯하고 차가운 색
	var img := _new(20, 15)
	_rect(img, 1, 3, 18, 11, Color("4f6470"))
	_rect(img, 1, 3, 18, 3, Color("6d8794"))
	for x in range(3, 18, 4):
		_rect(img, x, 7, 2, 1, Color("2e3c44"))
	_rect(img, 1, 13, 18, 1, Color("2a343a"))
	if open:
		_rect(img, 3, 1, 14, 3, Color("6d8794"))
		_rect(img, 3, 6, 14, 6, Color("1c2226"))
	else:
		_rect(img, 8, 8, 4, 4, Color("e0b020"))
		_rect(img, 9, 6, 2, 2, Color("a08020"))
		_px(img, 10, 10, Color("3a2a10"))
	return _outline(img)


static func _can() -> Image:
	var img := _new(5, 6)
	_rect(img, 0, 0, 5, 6, Color("b8bcc0"))
	_rect(img, 0, 2, 5, 2, Color("d8574a"))
	_rect(img, 1, 0, 3, 1, Color("e8ecf0"))
	return _outline(img)


static func _brick() -> Image:
	var img := _new(7, 4)
	_rect(img, 0, 0, 7, 4, Color("a0503a"))
	_rect(img, 0, 0, 7, 1, Color("c0684a"))
	_px(img, 2, 2, Color("7a3a2a"))
	return _outline(img)


static func _heal() -> Image:
	var img := _new(9, 6)
	_rect(img, 0, 1, 9, 4, Color("e8c8a8"))
	_rect(img, 3, 0, 3, 6, Color("f0d8c0"))
	_rect(img, 4, 2, 1, 2, Color("e04050"))
	_rect(img, 3, 3, 3, 0, Color("e04050"))
	return _outline(img)


static func _big() -> Image:
	var img := _new(16, 14)
	_rect(img, 1, 3, 14, 10, Color("6a5a40"))
	_rect(img, 2, 4, 12, 3, Color("8a7650"))
	_rect(img, 7, 3, 2, 10, Color("3a3020"))
	_rect(img, 1, 7, 14, 1, Color("3a3020"))
	_rect(img, 11, 0, 4, 4, Color("f0c040"))   # 노란 꼬리표
	_px(img, 12, 1, Color("6a5010"))
	return _outline(img)


static func _cube() -> Image:
	var img := _new(16, 14)
	_rect(img, 0, 3, 16, 11, Color("6a6064"))
	_rect(img, 0, 0, 16, 4, Color("8a8288"))
	var cols := [Color("8a3a36"), Color("3a5a86"), Color("a08a4e"), Color("5a6a3a")]
	for k in 8:
		_rect(img, int(hash01(k, 1, 60) * 13), 4 + int(hash01(k, 2, 61) * 8), 3, 1, cols[k % 4])
	return _outline(img)


static func _good_icon(g: String) -> Image:
	var img := _new(10, 10)
	var c := RunCfg.good_color(g)
	match g:
		"scrap":
			_rect(img, 1, 5, 4, 3, c); _rect(img, 4, 2, 4, 4, c.darkened(0.2)); _rect(img, 6, 6, 3, 3, Color("8a5a3a")); _px(img, 2, 4, Color("c0a080"))
		"metal":
			_rect(img, 0, 3, 10, 2, c.lightened(0.15)); _rect(img, 0, 5, 10, 2, c); _rect(img, 1, 1, 8, 1, c.darkened(0.2)); _rect(img, 0, 7, 10, 1, c.darkened(0.3))
		"wood":
			_rect(img, 0, 2, 10, 3, c); _rect(img, 1, 5, 9, 3, c.darkened(0.15)); _px(img, 3, 3, c.darkened(0.4)); _px(img, 7, 6, c.darkened(0.4))
		"concrete":
			_rect(img, 1, 2, 8, 7, c); _rect(img, 1, 2, 8, 2, c.lightened(0.15)); _px(img, 3, 5, c.darkened(0.3)); _px(img, 6, 7, c.darkened(0.3))
		"canned":
			_rect(img, 2, 1, 6, 8, Color("b8bcc0")); _rect(img, 2, 3, 6, 4, c); _rect(img, 3, 1, 4, 1, Color("e8ecf0"))
		"elec":
			_rect(img, 0, 1, 10, 8, Color("2f7a4a")); _rect(img, 2, 3, 3, 2, Color("202020")); _rect(img, 6, 5, 2, 2, Color("c0a040")); _rect(img, 1, 7, 7, 1, Color("d0c060"))
		"parts":
			_ellipse(img, 5, 5, 4.5, 4.5, c); _ellipse(img, 5, 5, 1.6, 1.6, Color("6a5010"))
			for d in [Vector2i(5, 0), Vector2i(0, 5), Vector2i(9, 5), Vector2i(5, 9)]:
				_px(img, d.x, d.y, c.darkened(0.2))
		_:
			_rect(img, 1, 1, 8, 8, c)
	return _outline(img)


static func _exit_hole() -> Image:
	var img := _new(18, 18)
	_ellipse(img, 9, 10, 8, 6, Color("15110f"))
	_ellipse(img, 9, 9, 6, 4, Color("0a0808"))
	for x in range(1, 17, 3):
		_rect(img, x, 2, 1, 4, Color("8a8070"))   # 찢어진 철망
	_rect(img, 1, 2, 16, 1, Color("8a8070"))
	return _outline(img)


static func _manhole() -> Image:
	var img := _new(16, 16)
	_ellipse(img, 8, 8, 7.5, 7, Color("3a3a40"))
	_ellipse(img, 8, 8, 5.5, 5, Color("0c0c10"))
	_rect(img, 5, 4, 1, 8, Color("8a8a90"))
	_rect(img, 10, 4, 1, 8, Color("8a8a90"))
	for y in range(5, 12, 2):
		_rect(img, 5, y, 6, 1, Color("8a8a90"))
	return _outline(img)


static func _gate() -> Image:
	var img := _new(20, 16)
	_rect(img, 0, 0, 20, 16, Color("20201c"))
	for x in range(1, 20, 4):
		_rect(img, x, 0, 2, 16, Color("5a5a52"))
	_rect(img, 0, 0, 20, 2, Color("e0b020"))
	return _outline(img)


static func _boss_head(stuck: bool) -> Image:
	var img := _new(44, 38)
	var steel := Color("5e6873")
	_rect(img, 2, 2, 40, 32, steel)
	_rect(img, 2, 2, 40, 5, Color("7a8692"))
	for x in range(2, 42):
		var c := Color("e0b020") if ((x / 4) % 2 == 0) else Color("1c1a1a")
		_rect(img, x, 29, 1, 5, c)
	_rect(img, 6, 10, 32, 15, Color("454d56"))
	# 눈(경고등)
	_rect(img, 10, 13, 6, 4, Color("ff4030") if not stuck else Color("602018"))
	_rect(img, 28, 13, 6, 4, Color("ff4030") if not stuck else Color("602018"))
	# 유압 호스
	_rect(img, 0, 8, 3, 18, Color("2a2a2a"))
	_rect(img, 41, 8, 3, 18, Color("2a2a2a"))
	if stuck:
		# 드러난 약점: 빛나는 유압 실린더
		_rect(img, 16, 18, 12, 9, Color("ffb030"))
		_rect(img, 18, 20, 8, 5, Color("fff0a0"))
	else:
		_rect(img, 16, 19, 12, 6, Color("30343a"))
	return _outline(img)


static func _shadow(rx: int, ry: int) -> Image:
	var img := _new(rx * 2, ry * 2)
	_ellipse(img, rx, ry, rx, ry, Color(0, 0, 0, 0.35))
	return img


static func _heart(kind: int) -> Image:
	var rows := [
		".XX.XX.",
		"XooXooX",
		"XoooooX",
		"XoooooX",
		".XoooX.",
		"..XoX..",
		"...X...",
	]
	var img := _new(7, 7)
	for y in 7:
		for x in 7:
			var ch: String = rows[y][x]
			if ch == "X":
				img.set_pixel(x, y, OUT)
			elif ch == "o":
				var full := kind == 1 or (kind == 2 and x < 4)
				img.set_pixel(x, y, Color("e8384a") if full else Color("4a3438"))
				if full and y == 1 and x in [1, 4]:
					img.set_pixel(x, y, Color("ff9aa0"))
	return img
