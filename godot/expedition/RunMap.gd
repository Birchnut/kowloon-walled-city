extends RefCounted
## 지도 조각 그리기(2차): 햇빛 받은 녹슨 주황·청록 골함석·밝은 콘크리트 바닥, 왼쪽 위에서 오는 햇빛의 긴 그림자.
## 장애물 4종을 한눈에 구분: 찌그러진 차 더미(C) · 컨테이너 벽(방 안쪽 #) · 타이어 더미(T) · 기름통(B), 그리고 버스 잔해(U)·경비 초소(H)·판잣집(사무실 틀의 안쪽 #).
## 방 틀마다 바닥 결(dirt/concrete/oily)이 달라 방이 바뀐 것이 보인다.

const DungeonGen = preload("res://expedition/DungeonGen.gd")
const RunCfg = preload("res://expedition/RunCfg.gd")

const TS := 16
const OUT := Color("1a1418")
const SHADE := 0.58          # 그림자 진하기(곱)
const TALL := [DungeonGen.WALL, DungeonGen.CAR, DungeonGen.BOX, DungeonGen.TIRE, DungeonGen.PRESS, DungeonGen.BUS, DungeonGen.BOOTH]

static var _tiles: PackedByteArray
static var _w := 0
static var _h := 0
static var _rooms: Array = []


static func h01(x: int, y: int, s: int = 0) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 10000) / 10000.0


static func t(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return DungeonGen.VOID
	return _tiles[y * _w + x]


static func room_at(x: int, y: int) -> Dictionary:
	for r in _rooms:
		if (r["rect"] as Rect2i).has_point(Vector2i(x, y)):
			return r
	return {}


static func chunk(tiles: PackedByteArray, w: int, h: int, rooms: Array, cx: int, cy: int, size: int = 32) -> Image:
	_tiles = tiles
	_w = w
	_h = h
	_rooms = rooms
	var img := Image.create(size * TS, size * TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var any := false
	for ty in range(cy * size, mini(h, (cy + 1) * size)):
		for tx in range(cx * size, mini(w, (cx + 1) * size)):
			if t(tx, ty) == DungeonGen.VOID:
				continue
			any = true
			_tile(img, tx, ty, (tx - cx * size) * TS, (ty - cy * size) * TS)
	return img if any else null


# ------------------------------------------------------------------ 바닥
static func _floor_style(tx: int, ty: int) -> String:
	var r := room_at(tx, ty)
	if r.is_empty():
		return "hall"
	return str(RunCfg.rooms().get(r["tmpl"], {}).get("floor", "dirt"))


static func _ground(img: Image, tx: int, ty: int, ox: int, oy: int, style: String) -> void:
	var base := Color("c2a77f")     # 햇빛 받은 흙
	var lo := Color("a88d68")
	var hi := Color("d6bf98")
	var sg: Array = RunCfg.skin().get("ground", [])
	if sg.size() >= 3 and style != "hall":
		base = Color(str(sg[0]))
		lo = Color(str(sg[1]))
		hi = Color(str(sg[2]))
		style = "trash"
	elif style == "concrete" or style == "hall":
		base = Color("bdb8ac")
		lo = Color("a39d90")
		hi = Color("d2cdc2")
	elif style == "oily":
		base = Color("ad9878")
		lo = Color("8a7860")
		hi = Color("c4b090")
	for y in TS:
		for x in TS:
			var r := h01(tx * 16 + x, ty * 16 + y)
			var c := base
			if r < 0.10:
				c = lo
			elif r > 0.95:
				c = hi
			img.set_pixel(ox + x, oy + y, c)
	if style == "concrete" or style == "hall":
		# 판 이음매(2칸마다) + 가끔 금
		if tx % 2 == 0:
			for y in TS:
				img.set_pixel(ox, oy + y, Color("958f83"))
		if ty % 2 == 0:
			for x in TS:
				img.set_pixel(ox + x, oy, Color("958f83"))
		if h01(tx, ty, 3) < 0.12:
			var y0 := 3 + int(h01(tx, ty, 4) * 9)
			for x in range(2, 14):
				_px(img, ox + x, oy + y0 + int(sin(x * 0.9 + tx) * 1.5), Color("8f897d"))
	elif style == "trash":
		# 매립지: 비닐 조각·병뚜껑·종이가 흩어진 흙
		var k2 := h01(tx, ty, 7)
		if k2 < 0.35:
			var cc := [Color("e74c3c"), Color("3498db"), Color("ecf0f1"), Color("27ae60"), Color("f39c12")][int(h01(tx, ty, 17) * 5) % 5] as Color
			_rect(img, ox + 2 + int(h01(tx, ty, 8) * 11), oy + 2 + int(h01(tx, ty, 9) * 11), 3, 2, cc)
		if k2 > 0.96:
			_rect(img, ox + 4, oy + 7, 5, 2, Color("e8e2d0"))
	else:
		# 자갈·잡초·바퀴 자국
		var k := h01(tx, ty, 7)
		if k < 0.16:
			_rect(img, ox + 3 + int(h01(tx, ty, 8) * 9), oy + 3 + int(h01(tx, ty, 9) * 9), 2, 2, hi)
			_px(img, ox + 4 + int(h01(tx, ty, 8) * 9), oy + 5 + int(h01(tx, ty, 9) * 9), lo.darkened(0.2))
		elif k < 0.2:
			for g in 4:
				_rect(img, ox + 5 + g * 2, oy + 9 - (g % 2) * 2, 1, 3 + (g % 2) * 2, Color("7c9248"))
	if style == "oily" and h01(tx, ty, 21) < 0.07:
		# 기름 얼룩: 드물게, 납작하고 갈색 섞인 검정(구멍처럼 보이지 않게 가장자리를 흐리게)
		for y in range(5, 12):
			for x in range(1, 15):
				var dx := (x - 7.5) / 7.0
				var dy := (y - 8.0) / 3.2
				var dd := dx * dx + dy * dy
				if dd < 1.0:
					var c0 := img.get_pixel(ox + x, oy + y)
					img.set_pixel(ox + x, oy + y, c0.lerp(Color("3d3229"), 0.55 if dd < 0.6 else 0.3))


## 왼쪽 위에서 비치는 햇빛: 북쪽·서쪽 이웃이 높은 것이면 이 칸 위·왼쪽에 그림자.
static func _cast(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	var n := t(tx, ty - 1) in TALL
	var wv := t(tx - 1, ty) in TALL
	var nw := t(tx - 1, ty - 1) in TALL
	for y in TS:
		for x in TS:
			var sh := false
			if n and y < 7:
				sh = true
			if wv and x < 5:
				sh = true
			if nw and x < 5 and y < 7:
				sh = true
			if n and not wv and x < 5 and y < 7 and t(tx - 1, ty - 1) in TALL:
				sh = true
			if sh:
				var c := img.get_pixel(ox + x, oy + y)
				img.set_pixel(ox + x, oy + y, Color(c.r * SHADE, c.g * SHADE, c.b * SHADE * 1.06, c.a))


# ------------------------------------------------------------------ 칸 하나
static func _tile(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	var code := t(tx, ty)
	match code:
		DungeonGen.SOFT:
			_soft(img, tx, ty, ox, oy)
			_cast(img, tx, ty, ox, oy)
		DungeonGen.FLOOR, DungeonGen.JUNK, DungeonGen.RUBBLE, DungeonGen.GRAVEL:
			_ground(img, tx, ty, ox, oy, _floor_style(tx, ty))
			_cast(img, tx, ty, ox, oy)
		DungeonGen.OIL:
			_ground(img, tx, ty, ox, oy, "oily")
			_cast(img, tx, ty, ox, oy)
		DungeonGen.HALL, DungeonGen.DOOR:
			_ground(img, tx, ty, ox, oy, "hall")
			if code == DungeonGen.DOOR:
				for x in range(0, 16, 4):
					_rect(img, ox + x, oy, 2, 16, Color("e0b020") if (x / 4) % 2 == 0 else Color("2a2622"))
			_cast(img, tx, ty, ox, oy)
		DungeonGen.WIRE:
			_ground(img, tx, ty, ox, oy, "oily")
			_cast(img, tx, ty, ox, oy)
			_puddle(img, tx, ty, ox, oy)
		DungeonGen.WALL:
			var r := room_at(tx, ty)
			var inner := false
			if not r.is_empty():
				var o: Vector2i = r["origin"]
				var lx := tx - o.x
				var ly := ty - o.y
				inner = lx > 0 and ly > 0 and lx < DungeonGen.RW - 1 and ly < DungeonGen.RH - 1
			if inner:
				if RunCfg.rooms().get(r["tmpl"], {}).get("shack", false):
					_shack(img, tx, ty, ox, oy)
				else:
					_container(img, tx, ty, ox, oy)
			else:
				_fence(img, tx, ty, ox, oy)
		DungeonGen.CAR:
			_ground(img, tx, ty, ox, oy, _floor_style(tx, ty))
			_cast(img, tx, ty, ox, oy)
			_car_stack(img, tx, ty, ox, oy)
		DungeonGen.BUS:
			_ground(img, tx, ty, ox, oy, _floor_style(tx, ty))
			_cast(img, tx, ty, ox, oy)
			_bus(img, tx, ty, ox, oy)
		DungeonGen.TIRE:
			_ground(img, tx, ty, ox, oy, _floor_style(tx, ty))
			_cast(img, tx, ty, ox, oy)
			_tyres(img, tx, ty, ox, oy)
		DungeonGen.BOX:
			_ground(img, tx, ty, ox, oy, _floor_style(tx, ty))
			_cast(img, tx, ty, ox, oy)
			_drums(img, tx, ty, ox, oy)
		DungeonGen.BOOTH:
			_ground(img, tx, ty, ox, oy, "concrete")
			_booth(img, tx, ty, ox, oy)
		DungeonGen.PRESS:
			_ground(img, tx, ty, ox, oy, "concrete")
			_press(img, tx, ty, ox, oy)


## 같은 종류로 이어진 덩어리의 칸 범위(x0,y0,x1,y1)
static func _cluster(tx: int, ty: int, code: int) -> Rect2i:
	var x0 := tx
	while t(x0 - 1, ty) == code:
		x0 -= 1
	var x1 := tx
	while t(x1 + 1, ty) == code:
		x1 += 1
	var y0 := ty
	while t(tx, y0 - 1) == code:
		y0 -= 1
	var y1 := ty
	while t(tx, y1 + 1) == code:
		y1 += 1
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


# ------------------------------------------------------------------ 담·컨테이너·판잣집
static func _fence(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	var below := t(tx, ty + 1)
	var front := not DungeonGen.is_solid_code(below)
	if front:
		# 청록 골함석 담(녹 줄기)
		var teal := Color(str(RunCfg.skin().get("fence", "3f9590")))
		if h01(tx, ty, 2) < 0.25:
			teal = Color(str(RunCfg.skin().get("fence2", "c56a30")))   # 군데군데 다른 판
		for y in TS:
			for x in TS:
				var c := teal
				match x % 4:
					0: c = teal.darkened(0.32)
					1: c = teal.lightened(0.22)
					3: c = teal.darkened(0.1)
				# 위에서 흘러내린 녹
				var col_rust := h01(tx * 16 + x, 0, 9) < 0.18
				if col_rust and y < int(4 + h01(tx * 16 + x, 1, 9) * 10):
					c = c.lerp(Color("a8522a"), 0.6)
				if y >= 14:
					c = Color("2a2522")
				img.set_pixel(ox + x, oy + y, c)
		_rect(img, ox, oy, 16, 2, Color("264a48") if teal.g > teal.r else Color("6a3418"))
		if h01(tx, ty, 5) < 0.3:
			_px(img, ox + 3, oy + 4, Color("e0e0d0"))   # 리벳
			_px(img, ox + 11, oy + 4, Color("e0e0d0"))
	else:
		# 담 너머로 보이는 고철 무더기(어둡지 않게 따뜻한 갈색)
		for y in TS:
			for x in TS:
				var r := h01(tx * 16 + x, ty * 16 + y, 5)
				var c := Color("6e5a48")
				if r < 0.18:
					c = Color("5a4838")
				elif r > 0.88:
					c = Color("8a7458")
				img.set_pixel(ox + x, oy + y, c)
		if h01(tx, ty, 12) < 0.5:
			var jc := [Color("c56a30"), Color("3f9590"), Color("d8c050"), Color("8a8a90"), Color("a03a30")][int(h01(tx, ty, 13) * 5) % 5] as Color
			_rect(img, ox + int(h01(tx, ty, 14) * 9), oy + int(h01(tx, ty, 15) * 10), 6, 3, jc)
			_rect(img, ox + int(h01(tx, ty, 14) * 9), oy + int(h01(tx, ty, 15) * 10) + 3, 6, 1, jc.darkened(0.4))


static func _container(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	if RunCfg.skin().has("heap"):
		_bag_heap(img, tx, ty, ox, oy)
		return
	var cl := _cluster(tx, ty, DungeonGen.WALL)
	var cols := [Color("d0662a"), Color("2f8c88"), Color("3a68b0"), Color("9a3a34"), Color("c8a030")]
	var body: Color = cols[int(h01(cl.position.x, cl.position.y, 31) * cols.size()) % cols.size()]
	var lx := (tx - cl.position.x) * TS
	var ly := (ty - cl.position.y) * TS
	var cw := cl.size.x * TS
	var ch := cl.size.y * TS
	var horiz := cw >= ch
	for y in TS:
		for x in TS:
			var X := lx + x
			var Y := ly + y
			var c := body
			if X == 0 or Y == 0 or X == cw - 1 or Y == ch - 1:
				c = OUT
			elif Y < 4:
				c = body.lightened(0.28)            # 햇빛 받는 지붕
			elif Y >= ch - 3:
				c = body.darkened(0.45)
			else:
				var rib := (X % 3 == 0) if horiz else (Y % 3 == 0)
				c = body.darkened(0.25) if rib else body
				if h01(X + cl.position.x * 16, Y, 33) < 0.04:
					c = Color("8a4a26")
			# 문짝(한쪽 끝)
			if horiz and X > cw - 9 and X < cw - 2 and Y > 5 and Y < ch - 4:
				c = body.darkened(0.15) if X != cw - 5 else OUT
			img.set_pixel(ox + x, oy + y, c)


## 매립지의 안쪽 벽: 쓰레기 봉투 더미(둥근 봉투들, 묶은 매듭)
static func _bag_heap(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	var cols: Array = RunCfg.skin().get("heap", ["4f6a2e"])
	_rect(img, ox, oy, 16, 16, Color(str(cols[0])).darkened(0.35))
	for k in 3:
		var c := Color(str(cols[int(h01(tx * 3 + k, ty, 71) * cols.size()) % cols.size()]))
		var cx := 4.0 + h01(tx, ty * 3 + k, 72) * 8.0
		var cy := 4.0 + k * 4.5
		_ellipse(img, ox + cx, oy + cy, 5.0, 3.6, OUT)
		_ellipse(img, ox + cx, oy + cy, 4.2, 2.9, c)
		_rect(img, ox + int(cx) - 1, oy + int(cy) - 2, 2, 1, c.lightened(0.35))
		_px(img, ox + int(cx), oy + int(cy) - 4, OUT)


static func _soft(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	for y in TS:
		for x in TS:
			var r := h01(tx * 16 + x, ty * 16 + y, 81)
			var c := Color("7a6a48")
			if r < 0.15:
				c = Color("5e5034")
			elif r > 0.9:
				c = Color("9a8a5e")
			img.set_pixel(ox + x, oy + y, c)
	if h01(tx, ty, 82) < 0.5:
		_rect(img, ox + 3 + int(h01(tx, ty, 83) * 9), oy + 4 + int(h01(tx, ty, 84) * 8), 4, 2, Color("cfd8dc"))   # 젖은 비닐
	if h01(tx, ty, 85) < 0.3:
		_ellipse(img, ox + 9, oy + 9, 3, 1.5, Color("4a3e28"))   # 고인 물


static func _shack(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	var front := not DungeonGen.is_solid_code(t(tx, ty + 1))
	for y in TS:
		for x in TS:
			var c := Color("a87444")
			if y % 4 == 0:
				c = Color("6e4626")
			elif h01(tx * 16 + x, ty * 16 + y, 41) < 0.06:
				c = Color("c08a54")
			if not front:
				c = Color("8a8a84") if (x + y) % 7 != 0 else Color("6a6a66")   # 함석 지붕
			img.set_pixel(ox + x, oy + y, c)
	if front and h01(tx, ty, 42) < 0.4:
		_rect(img, ox + 4, oy + 4, 8, 6, Color("2a3a48"))      # 창
		_rect(img, ox + 4, oy + 4, 8, 1, Color("6a8aa0"))
		_rect(img, ox + 7, oy + 4, 1, 6, Color("6e4626"))
	_rect(img, ox, oy + 15, 16, 1, Color("3a2a1a"))


# ------------------------------------------------------------------ 차 더미·버스
static func _car_stack(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	# 찌그러진 차 두세 대를 겹쳐 쌓은 옆모습: 색 띠 + 창 띠 + 바퀴 자국
	var cl := _cluster(tx, ty, DungeonGen.CAR)
	var lx := (tx - cl.position.x) * TS
	var ly := (ty - cl.position.y) * TS
	var cw := cl.size.x * TS
	var ch := cl.size.y * TS
	var bodies := [Color("c0392b"), Color("2e86c1"), Color("d4ac0d"), Color("7d8c8c"), Color("27ae60"), Color("e67e22")]
	var layer_h := 9
	for y in TS:
		for x in TS:
			var X := lx + x
			var Y := ly + y
			var layer := Y / layer_h
			var inset := 1 + (layer % 2)
			if X < inset or X >= cw - inset:
				continue
			var c: Color = bodies[int(h01(cl.position.x + layer, cl.position.y, 51) * bodies.size()) % bodies.size()]
			var yy := Y % layer_h
			if yy == 0:
				c = OUT
			elif yy == 1:
				c = c.lightened(0.3)
			elif yy == 4 or yy == 5:
				c = Color("2c3e50") if (X / 6) % 3 != 2 else c.darkened(0.2)   # 창 띠
				if yy == 4 and (X / 6) % 3 != 2:
					c = Color("5d8aa8")
			elif yy == layer_h - 1:
				c = c.darkened(0.45)
			if h01(X + cl.position.x * 16, Y, 52) < 0.06:
				c = Color("8e4a22")
			if X == inset or X == cw - inset - 1:
				c = OUT
			img.set_pixel(ox + x, oy + y, c)
	# 아래 그늘 줄
	if ty == cl.end.y - 1:
		_rect(img, ox, oy + 14, 16, 2, Color("2a221c"))


static func _bus(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	var cl := _cluster(tx, ty, DungeonGen.BUS)
	var lx := (tx - cl.position.x) * TS
	var ly := (ty - cl.position.y) * TS
	var cw := cl.size.x * TS
	var ch := cl.size.y * TS
	for y in TS:
		for x in TS:
			var X := lx + x
			var Y := ly + y
			if Y < 2 or Y >= ch - 1 or X >= cw - 1:
				continue
			var c := Color("f1c40f")
			if X == 0 or Y == 2 or X == cw - 2 or Y == ch - 2:
				c = OUT
			elif Y < 6:
				c = Color("f7dc6f")                   # 지붕
			elif Y < 13:
				c = Color("2c3e50") if (X % 10) > 1 else Color("d4ac0d")   # 창문 줄
				if Y == 7 and (X % 10) > 1:
					c = Color("85a5b8")
			elif Y > ch - 7 and ((X > 12 and X < 22) or (X > cw - 26 and X < cw - 16)):
				c = Color("1c1c1c")                   # 바퀴(바람 빠짐)
			elif Y == 15:
				c = Color("1a1a1a")                   # 검은 띠
			if h01(X, Y + cl.position.y, 55) < 0.05 and c == Color("f1c40f"):
				c = Color("b9770e")
			img.set_pixel(ox + x, oy + y, c)


# ------------------------------------------------------------------ 타이어·기름통·초소·압축기
static func _tyres(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	# 칸마다 위로 쌓인 타이어 4개(옆에서 비스듬히)
	for k in 4:
		var y := 12 - k * 3
		_ellipse(img, ox + 8, oy + y, 7.5, 3.6, OUT)
		_ellipse(img, ox + 8, oy + y, 6.5, 2.8, Color("2b2a2c"))
		_rect(img, ox + 3, oy + y - 2, 10, 1, Color("4a484c"))
	_ellipse(img, ox + 8, oy + 3, 3.0, 1.3, Color("141214"))
	_rect(img, ox + 3, oy + 2, 2, 1, Color("6a686c"))


static func _drums(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	var cols := [Color("2e6fb5"), Color("c0392b"), Color("d4ac0d"), Color("27ae60")]
	var c: Color = cols[int(h01(tx, ty, 61) * cols.size()) % cols.size()]
	for k in 2:
		var cx := 5 + k * 7
		var cy := 9 - k
		_rect(img, ox + cx - 4, oy + cy - 4, 8, 10, OUT)
		_rect(img, ox + cx - 3, oy + cy - 3, 6, 8, c)
		_rect(img, ox + cx - 3, oy + cy - 1, 6, 1, c.darkened(0.35))
		_rect(img, ox + cx - 3, oy + cy + 2, 6, 1, c.darkened(0.35))
		_rect(img, ox + cx - 1, oy + cy - 3, 2, 8, c.lightened(0.25))
		_ellipse(img, ox + cx, oy + cy - 4, 3.5, 1.6, c.lightened(0.35))
		_px(img, ox + cx + 1, oy + cy - 4, OUT)
	if h01(tx, ty, 62) < 0.5:
		_rect(img, ox + 2, oy + 14, 12, 1, Color("2a2a30"))   # 흘린 기름


static func _booth(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	var cl := _cluster(tx, ty, DungeonGen.BOOTH)
	var lx := (tx - cl.position.x) * TS
	var ly := (ty - cl.position.y) * TS
	var cw := cl.size.x * TS
	var ch := cl.size.y * TS
	for y in TS:
		for x in TS:
			var X := lx + x
			var Y := ly + y
			var c := Color("ecf0f1")
			if X == 0 or Y == 0 or X == cw - 1 or Y == ch - 1:
				c = OUT
			elif Y < 7:
				c = Color("2e86c1") if (X / 3) % 2 == 0 else Color("2471a3")   # 파란 지붕
			elif Y < 9:
				c = Color("1b4f72")
			elif Y > 11 and Y < 20 and X % 14 > 3 and X % 14 < 11:
				c = Color("85c1e9")   # 창
			elif Y >= ch - 3:
				c = Color("aab7b8")
			img.set_pixel(ox + x, oy + y, c)


static func _press(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	if RunCfg.skin().has("heap"):
		_bag_heap(img, tx, ty, ox, oy)   # 들개 왕의 쓰레기 왕좌
		if (tx + ty) % 3 == 0:
			_rect(img, ox + 5, oy + 2, 6, 3, Color("f1c40f"))
		return
	var cl := _cluster(tx, ty, DungeonGen.PRESS)
	var cw := cl.size.x * TS
	var ch := cl.size.y * TS
	for y in TS:
		for x in TS:
			var X := (tx - cl.position.x) * TS + x
			var Y := (ty - cl.position.y) * TS + y
			var c := Color("7f8c99")
			if X == 0 or Y == 0 or X == cw - 1 or Y == ch - 1:
				c = OUT
			elif Y > ch - 8:
				c = Color("f1c40f") if ((X + Y) / 4) % 2 == 0 else Color("1c1a1a")
				if Y > ch - 3:
					c = Color("15110f")
			elif Y < 5:
				c = Color("aab7c4")
			elif X % 12 == 0:
				c = Color("5d6d7e")
			if X > cw / 2 - 10 and X < cw / 2 + 10 and Y > 6 and Y < ch - 10:
				c = Color("2a2a30") if (Y % 3 != 0) else Color("4a4a54")
			img.set_pixel(ox + x, oy + y, c)


static func _puddle(img: Image, tx: int, ty: int, ox: int, oy: int) -> void:
	for y in TS:
		for x in TS:
			var edge := 0
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if t(tx + d.x, ty + d.y) != DungeonGen.WIRE:
					if (d.x == -1 and x < 2) or (d.x == 1 and x > 13) or (d.y == -1 and y < 2) or (d.y == 1 and y > 13):
						edge += 1
			if edge == 0:
				var r := h01(tx * 16 + x, ty * 16 + y, 4)
				img.set_pixel(ox + x, oy + y, Color("2c5a8a") if r > 0.12 else Color("8ec5f0"))
	if h01(tx, ty, 11) < 0.4:
		for x in range(1, 15):
			_px(img, ox + x, oy + 6 + int(sin(x * 0.5 + tx) * 2.0), Color("1c1c1c"))


# ------------------------------------------------------------------ 도구
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
