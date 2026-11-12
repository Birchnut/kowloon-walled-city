class_name PeopleSprites
extends RefCounted
## PeopleSprites — 사람 스프라이트 시트를 코드로 그린다(에셋 없음). 큰 머리의 짧은 몸(치비) 픽셀 인형.
## 크기: S 6×12(먼 확대) · M 10×20 · L 16×32 · X 20×40(확대 3단) · XX 26×52(가장 가까이: 한 층 64px에 사람 ≈44px).
## 텍셀 = "부위 번호"(R = 부위/16). 셰이더(actor.gdshader)가 인스턴스마다 피부·머리·옷·바지·소품 색을 입힌다.
## 배치: 열 = 자세×4(프레임 0..3), 행 = 방향(0 앞, 1 옆(오른쪽을 봄), 2 뒤).
## 4프레임: 걷기 = 왼발·모음·오른발·모음(모음에서 1px 들림), 손일 = 손 높이 0·1·2·1, 그 밖 = 0·0·1·1(느린 번갈음).

enum Part { NONE, OUTLINE, SKIN, HAIR, SHIRT, PANTS, SHOES, EYE, ACC, PROP, WHITE, CRATE, SHIRT_D, SKIN_D }
const POSES := ["stand", "walk", "sit", "work", "swork", "cheer", "sing", "carry", "bucket", "lie", "squat", "bow", "bathe", "sit_eat", "can", "sack", "taichi", "pass", "scratch", "look", "smoke", "hammer", "cook", "run"]
const SIZES := {"S": Vector2i(6, 12), "M": Vector2i(10, 20), "L": Vector2i(16, 32), "X": Vector2i(20, 40), "XX": Vector2i(26, 52)}
const FRAMES := 4

var img: Image
var fw := 16
var fh := 32
var _ox := 0
var _oy := 0
var _sz := "L"
var big := true     # L 이상: 테두리·눈·목 같은 잔디테일을 그린다
var k := 1.0        # L(32) 대비 배율


static func pose_index(name: String) -> int:
	var i := POSES.find(name)
	return i if i >= 0 else 0


static var _cache: Dictionary = {}


## 시트는 크기마다 한 번만 그린다(주민·시설 안 사람이 같은 텍스처를 쓴다).
static func build(size: String) -> ImageTexture:
	if _cache.has(size):
		return _cache[size]
	var ps := PeopleSprites.new()
	var t := ImageTexture.create_from_image(ps._sheet(size))
	_cache[size] = t
	return t


func _sheet(size: String) -> Image:
	_sz = size
	var fs: Vector2i = SIZES[size]
	fw = fs.x
	fh = fs.y
	big = fh >= 32
	k = float(fh) / 32.0
	var W := fw * POSES.size() * FRAMES
	var H := fh * 3
	var data := PackedByteArray()
	data.resize(W * H * 4)
	data.fill(0)
	for pi in POSES.size():
		for f in FRAMES:
			for dr in 3:
				_buf = PackedByteArray()
				_buf.resize(fw * fh)
				_buf.fill(0)
				_figure(POSES[pi], f, dr)
				_outline()
				var ox := (pi * FRAMES + f) * fw
				var oy := dr * fh
				for y in fh:
					for x in fw:
						var pt := _buf[y * fw + x]
						if pt != 0:
							var i := ((oy + y) * W + ox + x) * 4
							data[i] = int((float(pt) / 16.0 + 0.01) * 255.0)
							data[i + 3] = 255
	img = Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, data)
	return img


var _buf := PackedByteArray()


func _put(x: int, y: int, part: int) -> void:
	if x < 0 or y < 0 or x >= fw or y >= fh:
		return
	_buf[y * fw + x] = part


func _rect(x: int, y: int, w: int, h: int, part: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_put(xx, yy, part)


func _part_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= fw or y >= fh:
		return 0
	return _buf[y * fw + x]


func _outline() -> void:
	if _sz == "S":
		return
	var pts: Array = []
	for y in fh:
		for x in fw:
			if _part_at(x, y) != 0:
				continue
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p2: int = _part_at(x + dv.x, y + dv.y)
				if p2 != 0 and p2 != Part.OUTLINE:
					pts.append(Vector2i(x, y))
					break
	for p in pts:
		_put(p.x, p.y, Part.OUTLINE)


func _n(v: float) -> int:
	return maxi(int(round(v * k)), 1)


func _dims() -> Dictionary:
	match _sz:
		"S":
			return {"hw": 4, "hh": 4, "bw": 4, "bh": 3, "lh": 3, "sh": 1, "aw": 1, "ah": 2, "lw": 1}
		"M":
			return {"hw": 6, "hh": 6, "bw": 4, "bh": 4, "lh": 3, "sh": 1, "aw": 1, "ah": 3, "lw": 2}
	# L 기준 치수를 배율로(짝수 폭을 지켜 가운데가 맞게)
	var hw := _n(10.0)
	hw += hw % 2
	var bw := _n(8.0)
	bw += bw % 2
	return {"hw": hw, "hh": _n(9.0), "bw": bw, "bh": _n(6.0), "lh": _n(5.0), "sh": _n(2.0), "aw": _n(2.0), "ah": _n(5.0), "lw": _n(3.0)}


func _figure(pose: String, f: int, dr: int) -> void:
	var D := _dims()
	var hw: int = D["hw"]
	var hh: int = D["hh"]
	var bw: int = D["bw"]
	var bh: int = D["bh"]
	var lh: int = D["lh"]
	var sh: int = D["sh"]
	var aw: int = D["aw"]
	var ah: int = D["ah"]
	var lw: int = D["lw"]
	var cx := fw / 2
	var side := dr == 1
	var back := dr == 2
	var f2 := 0 if f < 2 else 1          # 느린 번갈음
	if side:
		bw = maxi(bw - (_n(2.0) if big else 1), 2)
		hw = maxi(hw - (_n(1.0) if big else 0), 3)
	var foot := fh - 1
	var leg := lh
	var sit := pose in ["sit", "work", "sit_eat"]
	var squat := pose == "squat"
	if sit:
		leg = maxi(lh / 2, 1)
	if squat:
		leg = maxi(lh / 3, 1)
	if pose == "lie":
		_lie(D, f2)
		return
	if pose == "bathe":
		_bathe(D, f2)
		return
	var walking := pose in ["walk", "carry", "bucket", "can", "sack", "run"]
	var lift := 1 if (walking and (f == 1 or f == 3) and big) else 0
	if pose == "cook" and big and f == 2:
		lift = 1
	var shoe_y := foot - sh + 1
	var leg_y := shoe_y - leg
	var body_y := leg_y - bh - lift
	var head_y := body_y - hh + (1 if _sz != "S" else 0)
	if pose == "bow" and f2 == 1:
		head_y += maxi(hh / 3, 1)
	if pose == "hammer" and f == 2:
		head_y += 1
	var bx := cx - bw / 2
	var hx := cx - hw / 2
	if side:
		hx = cx - hw / 2 + (1 if big else 0)
	# ── 다리
	if sit:
		if side:
			_rect(bx, leg_y, bw + lw + 1, leg, Part.PANTS)
			_rect(bx + bw + lw - 1, leg_y + leg, maxi(lw, 1) + 1, sh, Part.SHOES)
		else:
			_rect(bx, leg_y, bw, leg, Part.PANTS)
			if not back:
				_rect(bx, leg_y + leg, lw, sh, Part.SHOES)
				_rect(bx + bw - lw, leg_y + leg, lw, sh, Part.SHOES)
	elif squat:
		_rect(bx - 1, leg_y, bw + 2, leg + 1, Part.PANTS)
		_rect(bx - 1, shoe_y, lw + 1, sh, Part.SHOES)
		_rect(bx + bw - lw, shoe_y, lw + 1, sh, Part.SHOES)
	else:
		var gap := maxi(bw - lw * 2, 0)
		var l1 := bx
		var l2 := bx + lw + gap
		var up1 := 0
		var up2 := 0
		var done := false
		if walking:
			var stride := (2 if pose == "run" else 1) * (_n(2.0) if big else (1 if _sz == "M" else 0))
			if side:
				# 옆: 왼발 앞 · 모음 · 오른발 앞 · 모음
				var off: int = [stride + 1, 0, -stride - 1, 0][f]
				var a: int = cx - lw / 2 + off - (1 if f % 2 == 1 else 0)
				var b: int = cx - lw / 2 - off
				_rect(a, leg_y, lw, leg - lift, Part.PANTS)
				_rect(a, shoe_y - lift, lw + 1, sh, Part.SHOES)
				_rect(b, leg_y, lw, leg - lift, Part.PANTS)
				_rect(b, shoe_y - lift, lw + 1, sh, Part.SHOES)
				done = true
			else:
				up1 = maxi(stride, 1) if f == 0 else 0
				up2 = maxi(stride, 1) if f == 2 else 0
		if not done:
			if side:
				_rect(cx - lw / 2 - 1, leg_y - lift, lw + 1, leg, Part.PANTS)
				_rect(cx - lw / 2 - 1, shoe_y - lift, lw + 2, sh, Part.SHOES)
			else:
				_rect(l1, leg_y - lift, lw, leg - up1, Part.PANTS)
				_rect(l1, shoe_y - up1 - lift, lw, sh, Part.SHOES)
				_rect(l2, leg_y - lift, lw, leg - up2, Part.PANTS)
				_rect(l2, shoe_y - up2 - lift, lw, sh, Part.SHOES)
	# ── 몸
	_rect(bx, body_y, bw, bh, Part.SHIRT)
	if big:
		_rect(bx, body_y + bh - 1, bw, 1, Part.SHIRT_D)
		# 그늘진 쪽(오른쪽)과 단추줄 — 큰 크기에서 몸통이 덩어리로 읽히게
		_rect(bx + bw - maxi(_n(1.5), 1), body_y + 1, maxi(_n(1.5), 1), bh - 1, Part.SHIRT_D)
		if not side and not back and k > 1.1:
			for yy in range(body_y + 2, body_y + bh - 1, 2):
				_put(cx, yy, Part.SHIRT_D)
		if not back and not side:
			_rect(cx - _n(1.0) / 2, body_y, maxi(_n(1.0), 1), 1, Part.SKIN)
		if pose == "cook" and not back:
			# 앞치마
			_rect(bx + 1, body_y + 1, bw - 2, bh - 1, Part.WHITE)
	_arms(pose, f, dr, bx, bw, body_y, aw, ah, hx, hw, head_y, hh)
	_head(hx, head_y, hw, hh, dr, f, pose)
	_props(pose, f, dr, bx, bw, body_y, bh, head_y, cx, aw, ah, hx, hw, hh)


func _arms(pose: String, f: int, dr: int, bx: int, bw: int, by: int, aw: int, ah: int, hx: int, hw: int, hy: int, hh: int) -> void:
	var lx := bx - aw
	var rx := bx + bw
	var side := dr == 1
	var f2 := 0 if f < 2 else 1
	var sleeve := maxi(ah / 2, 1)
	var hand := maxi(_n(1.0), 1) if big else 1
	var arm := func(x: int, y: int, h: int, hand_top: bool = false) -> void:
		if hand_top:
			_rect(x, y, aw, hand, Part.SKIN)
			_rect(x, y + hand, aw, maxi(h - hand, 0), Part.SHIRT)
		else:
			_rect(x, y, aw, mini(sleeve, h), Part.SHIRT)
			if h > sleeve:
				_rect(x, y + sleeve, aw, h - sleeve, Part.SKIN)
	var hy4: int = [0, 1, 2, 1][f]      # 손일 4단
	match pose:
		"walk", "can", "sack", "run":
			var sw: int = [1, 0, -1, 0][f] * (2 if pose == "run" else 1)
			if side:
				arm.call(bx + bw / 2 - aw / 2 + sw, by + 1, ah)
			else:
				arm.call(lx, by + maxi(sw, 0), ah)
				arm.call(rx, by + maxi(-sw, 0), ah)
		"work", "swork", "pass", "cook":
			# 손을 앞으로, 위아래 4단(재봉·패 섞기·칼질·건네기)
			var hand_y := by + ah / 2 + hy4 - 1
			if side:
				_rect(bx + bw - 1, by + 1, aw + 2, hand, Part.SHIRT)
				_rect(bx + bw + aw, hand_y - 1, hand, hand, Part.SKIN)
			elif dr == 0:
				arm.call(lx, by, maxi(ah - 2, 1))
				arm.call(rx, by, maxi(ah - 2, 1))
				_rect(bx + 1, hand_y, aw, hand, Part.SKIN)
				_rect(bx + bw - 1 - aw, by + ah / 2 + (2 - hy4) - 1, aw, hand, Part.SKIN)
			else:
				arm.call(lx, by, maxi(ah - 2, 1))
				arm.call(rx, by, maxi(ah - 2, 1))
		"hammer":
			# 망치를 들었다(0) 내리친다(2)
			var up := f == 0 or f == 1
			if side:
				arm.call(bx + bw / 2, hy if up else by + 1, ah, up)
			else:
				arm.call(lx, by, ah)
				arm.call(rx, hy + (0 if up else hh), ah, up)
		"cheer", "taichi":
			var upc := pose == "cheer"
			if side:
				arm.call(bx + bw / 2, hy if upc else by, ah, upc)
			elif upc:
				if f2 == 0:
					arm.call(lx, by - ah + 1, ah, true)
					arm.call(rx, by, ah)
				else:
					arm.call(lx, by, ah)
					arm.call(rx, by - ah + 1, ah, true)
			else:
				if f2 == 0:
					_rect(lx - aw, by + 1, aw * 2, hand, Part.SHIRT)
					_rect(rx, by + 1, aw * 2, hand, Part.SHIRT)
					_rect(lx - aw - hand, by + 1, hand, hand, Part.SKIN)
					_rect(rx + aw * 2, by + 1, hand, hand, Part.SKIN)
				else:
					arm.call(lx, by - ah + 2, ah, true)
					arm.call(rx, by - ah + 2, ah, true)
		"sing":
			if dr == 2:
				arm.call(lx, by, ah)
				arm.call(rx, by, ah)
			else:
				_rect(rx - (1 if side else 0), by - 1, aw, 2, Part.SHIRT)
				_rect(rx - (1 if side else 0), hy + hh - 2, aw, hand + 1, Part.SKIN)
				_put(rx - (1 if side else 0) - 1, hy + hh - 2, Part.PROP)
				if not side:
					arm.call(lx - (1 if f2 == 1 else 0), by + (0 if f2 == 0 else -1), ah)
		"carry":
			if not side:
				arm.call(lx, by - ah + 1 + (1 if f % 2 == 1 else 0), ah, true)
				arm.call(rx, by - ah + 1 + (1 if f % 2 == 1 else 0), ah, true)
			else:
				arm.call(bx + bw / 2, by - ah + 1, ah, true)
		"bucket":
			if side:
				arm.call(bx + bw / 2, by + 1, ah)
			else:
				arm.call(lx, by + (1 if f == 0 else 0), ah)
				arm.call(rx, by, ah + 1)
		"sit_eat":
			var up2 := f == 1 or f == 2
			if dr == 0:
				_rect(bx, by + ah / 2, bw, 1, Part.SKIN)
				arm.call(lx, by, maxi(ah - 2, 1))
				arm.call(rx, by - (1 if up2 else 0), maxi(ah - 2, 1))
				_rect(rx, by - (2 if up2 else 1), hand, hand, Part.SKIN)
			elif side:
				_rect(bx + bw - 1, by + 1, aw + 2, 1, Part.SHIRT)
				_rect(bx + bw + aw, by + (0 if up2 else 1), hand, hand, Part.SKIN)
			else:
				arm.call(lx, by, ah - 1)
				arm.call(rx, by, ah - 1)
		"bow":
			if side:
				arm.call(bx + bw / 2, by + 1, ah)
			else:
				_rect(bx + 1, by + ah / 2, bw - 2, 1, Part.SKIN)
				arm.call(lx, by, ah - 1)
				arm.call(rx, by, ah - 1)
		"scratch":
			# 머리를 긁는다(손이 머리 위를 오간다)
			if side:
				arm.call(bx + bw / 2, hy + (f % 2), ah, true)
			else:
				arm.call(lx, by, ah)
				arm.call(rx + (1 if f % 2 == 1 else 0) - 1, hy + 1 - (1 if f % 2 == 1 else 0), ah, true)
		"smoke":
			# 담배: 손이 입으로(1·2) 내려오기(0·3)
			var up3 := f == 1 or f == 2
			if side:
				arm.call(bx + bw / 2 + 1, hy + hh - 2 if up3 else by + 1, ah, up3)
			else:
				arm.call(lx, by, ah)
				if up3:
					_rect(rx - 1, by - 1, aw, 2, Part.SHIRT)
					_rect(rx - 2, hy + hh - 2, hand, hand, Part.SKIN)
				else:
					arm.call(rx, by, ah)
		_:
			if side:
				arm.call(bx + bw / 2 - aw / 2, by + 1, ah)
			else:
				arm.call(lx, by, ah)
				arm.call(rx, by, ah)


func _head(hx: int, hy: int, hw: int, hh: int, dr: int, f: int, pose: String) -> void:
	_rect(hx, hy, hw, hh, Part.SKIN)
	var hair_h := maxi(hh / 3, 1)
	var px := maxi(_n(1.0), 1) if big else 1
	if dr == 2:
		_rect(hx, hy, hw, hh - (1 if _sz != "S" else 0), Part.HAIR)
	elif dr == 1:
		_rect(hx, hy, hw, hair_h + (1 if big else 0), Part.HAIR)
		_rect(hx, hy, maxi(hw / 2 - 1, 1), hh - hh / 3, Part.HAIR)
		if _sz != "S":
			var ey := hy + hh / 2 + (1 if big else 0)
			_rect(hx + hw - 1 - px, ey, px, px, Part.EYE)
			if big:
				_rect(hx + hw - 1 - px, ey - px, px, px, Part.EYE)
				_put(hx + hw - 1, ey + 2 * px, Part.SKIN_D)
	else:
		_rect(hx, hy, hw, hair_h + (1 if big else 0), Part.HAIR)
		if big:
			# 앞머리: 들쭉날쭉한 끝
			var hs := hx * 7 + hw
			for xx in range(hx, hx + hw, maxi(px, 1)):
				if (xx + hs) % 3 == 0:
					_rect(xx, hy + hair_h + 1, px, px, Part.HAIR)
			_rect(hx, hy + hair_h, px, hh / 2, Part.HAIR)
			_rect(hx + hw - px, hy + hair_h, px, hh / 2, Part.HAIR)
			_rect(hx + 2 * px, hy + hair_h + 1, px, px, Part.HAIR)
		if _sz != "S":
			var ey2 := hy + hh / 2 + (1 if big else 0)
			var blink := pose in ["stand", "sit", "look", "smoke"] and f == 3
			var look := 0
			if pose == "look":
				look = [-1, 0, 1, 0][f] * px
			var ex1 := hx + (2 * px if big else 1) + look
			var ex2 := hx + hw - (2 * px + 1 if big else 2) + look
			var part := Part.SKIN_D if blink else Part.EYE
			_rect(ex1, ey2, px, px if blink else (2 * px if big else 1), part)
			_rect(ex2, ey2, px, px if blink else (2 * px if big else 1), part)
			if big:
				_rect(hx + px, ey2 + 2 * px, px, px, Part.SKIN_D)
				_rect(hx + hw - 2 * px, ey2 + 2 * px, px, px, Part.SKIN_D)
				if pose in ["sing", "cheer"]:
					_rect(hx + hw / 2 - px, ey2 + 2 * px + 1, 2 * px, px, Part.OUTLINE)


func _props(pose: String, f: int, dr: int, bx: int, bw: int, by: int, bh: int, hy: int, cx: int, aw: int, ah: int, hx: int, hw: int, hh: int) -> void:
	var s1 := maxi(_n(1.0), 1) if big else 1
	match pose:
		"carry":
			var w2 := bw + 2
			var h2 := _n(4.0) if big else 2
			_rect(cx - w2 / 2, hy - h2 + (0 if big else 1) + (1 if f % 2 == 1 else 0), w2, h2, Part.CRATE)
		"bucket", "pass":
			var bxp := bx + bw + (aw if dr != 1 else -1)
			var byp: int = by + ah - (0 if pose == "bucket" else int([2, 3, 4, 3][f]))
			var s := _n(4.0) if big else 2
			_rect(bxp - (1 if big else 0), byp, s, s, Part.PROP)
			if big:
				_rect(bxp - 1, byp, s, s1, Part.WHITE)
		"can":
			_rect(bx + bw + (aw if dr != 1 else 0), by + ah - 1, s1 * 2, s1 * 2 + 1, Part.PROP)
		"sack":
			var s3 := _n(5.0) if big else 3
			_rect(bx - (2 if big else 1), by - s3 + 2, s3 + 2, s3, Part.CRATE)
		"sit_eat":
			if dr == 0:
				_rect(cx - 2 * s1, by + ah / 2 - 1, 4 * s1, 2 * s1, Part.WHITE)
		"hammer":
			if dr != 2 and big:
				var up := f == 0 or f == 1
				var hxp := bx + bw + aw - 1
				var hyp := hy - s1 if up else hy + hh + s1
				_rect(hxp, hyp, 3 * s1, 2 * s1, Part.PROP)
		"smoke":
			if dr != 2 and (f == 1 or f == 2):
				_rect(bx + bw - 2 - s1, hy + hh - 2, s1, s1, Part.WHITE)
				_put(bx + bw - 3 - s1, hy + hh - 2, Part.ACC)
		"cook":
			if dr == 0 and big:
				# 국자/칼: 손에 들린 긴 막대
				_rect(bx + 1, by + ah / 2 + [0, 1, 2, 1][f] - 1 - 2 * s1, s1, 2 * s1, Part.PROP)


func _lie(D: Dictionary, f2: int) -> void:
	var y0 := fh - (_n(8.0) if big else (5 if _sz == "M" else 3))
	var hs := _n(7.0) if big else (4 if _sz == "M" else 2)
	_rect(1, y0 + f2, hs, hs, Part.SKIN)
	_rect(1, y0 + f2, hs, maxi(hs / 3, 1), Part.HAIR)
	if big:
		_rect(1 + hs / 2 - 1, y0 + f2 + hs / 2, maxi(_n(1.0), 1), 1, Part.SKIN_D)
	_rect(1 + hs, y0 + 1, fw - hs - 2, hs - 1, Part.SHIRT)
	_rect(1 + hs, y0 + 1 + (f2 if big else 0), fw - hs - 2, 1, Part.SHIRT_D)


func _bathe(D: Dictionary, f2: int) -> void:
	var hw: int = D["hw"]
	var hh: int = D["hh"]
	var cx := fw / 2
	var y := fh - hh - (_n(3.0) if big else 1) + f2
	_rect(cx - hw / 2, y, hw, hh, Part.SKIN)
	_rect(cx - hw / 2, y, hw, maxi(hh / 3, 1), Part.WHITE)
	if _sz != "S":
		var px := maxi(_n(1.0), 1) if big else 1
		_rect(cx - hw / 2 + 2 * px, y + hh / 2 + 1, px, px, Part.EYE)
		_rect(cx + hw / 2 - 3 * px, y + hh / 2 + 1, px, px, Part.EYE)
	_rect(cx - hw / 2 - 1, y + hh, hw + 2, fh - y - hh, Part.SKIN)
