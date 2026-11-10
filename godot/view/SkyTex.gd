class_name SkyTex
extends RefCounted
## 배경 스카이라인 텍스처(512×192, 64px 띠 3개)를 코드로 그린다.
## R = 실루엣, G = 창(밤에 켜짐), B = 밝은 면(왼쪽 모서리).
## 띠 0 = 사자산(獅子山) 능선, 1 = 먼 "합법 도시", 2 = 가까운 도시.

const W := 512
const BAND := 64


static func build(seed_v: int) -> ImageTexture:
	var img := Image.create(W, BAND * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var rs := [(seed_v * 2654435761 + 12345) & 0x7fffffff]
	# ── 0: 능선 ──
	for x in W:
		var a := float(x) / float(W) * TAU
		var h := 20.0 + 7.0 * sin(a * 2.0 + 1.0) + 4.0 * sin(a * 5.0 + 0.3) + 2.0 * sin(a * 11.0)
		# 사자 머리(한 곳만 불쑥)
		var dx := float(x - 150)
		h += 15.0 * exp(-dx * dx / 260.0) + 6.0 * exp(-(dx - 26.0) * (dx - 26.0) / 500.0)
		var dx2 := float(x - 400)
		h += 9.0 * exp(-dx2 * dx2 / 900.0)
		var hi := int(h)
		for y in range(BAND - hi, BAND):
			img.set_pixel(x, y, Color(1, 0, 0, 1))
	# ── 1: 먼 도시 ──
	var x := 0
	while x < W:
		var bw := 5 + _ri(rs, 9)
		var bh := 10 + _ri(rs, 26)
		if _ri(rs, 9) == 0:
			bh += 14
		_tower(img, BAND, x, bw, bh, rs, 3, 4, 0.35)
		x += bw + _ri(rs, 3)
	# ── 2: 가까운 도시 ──
	x = 0
	while x < W:
		var bw2 := 10 + _ri(rs, 16)
		var bh2 := 12 + _ri(rs, 30)
		if _ri(rs, 7) == 0:
			bh2 += 16
		_tower(img, BAND * 2, x, bw2, bh2, rs, 3, 3, 0.45)
		x += bw2 + _ri(rs, 4)
	return ImageTexture.create_from_image(img)


static func _ri(rs: Array, n: int) -> int:
	rs[0] = (int(rs[0]) * 1103515245 + 12345) & 0x7fffffff
	return (int(rs[0]) >> 8) % maxi(n, 1)


static func _tower(img: Image, y_off: int, x0: int, bw: int, bh: int, rs: Array, wx: int, wy: int, wp: float) -> void:
	var top := BAND - bh
	var step_top := _ri(rs, 3) == 0
	for xx in bw:
		var x := (x0 + xx) % W
		var t := top
		if step_top and (xx < bw / 4 or xx >= bw - bw / 4):
			t += 4
		for y in range(maxi(t, 0), BAND):
			var g := 0.0
			var b := 1.0 if xx == 0 else 0.0
			if xx > 0 and xx < bw - 1 and (xx % wx) == 1 and ((y - top) % wy) == 2 and y < BAND - 3 and y > t + 1:
				g = 1.0
			img.set_pixel(x, y_off + y, Color(1, g, b, 1))
	# 옥상: 안테나 / 물탱크
	var k := _ri(rs, 5)
	if k == 0 and top > 8:
		var ax := (x0 + bw / 2) % W
		for y in range(top - 7, top):
			img.set_pixel(ax, y_off + y, Color(1, 0, 0, 1))
	elif k == 1 and top > 5 and bw > 7:
		for xx in range(2, 6):
			for y in range(top - 3, top):
				img.set_pixel((x0 + xx) % W, y_off + y, Color(1, 0, 0, 1))
