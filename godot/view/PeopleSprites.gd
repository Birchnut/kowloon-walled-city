class_name PeopleSprites
extends RefCounted
## PeopleSprites — 사람 스프라이트 시트를 코드로 그린다(에셋 없음). 큰 머리의 짧은 몸(치비) 픽셀 인형.
## 세 크기: S 6×12(먼 확대) · M 10×20(중간) · L 16×32(가까이). 같은 자세 목록, 같은 배치.
## 텍셀은 색이 아니라 "부위 번호"를 R에 담는다(R = 부위/16). 셰이더(actor.gdshader)가 인스턴스마다 피부·머리·옷·바지·소품 색으로 바꾼다.
## 배치: 열 = 자세×2(프레임 0/1), 행 = 방향(0 앞, 1 옆(오른쪽을 봄), 2 뒤).

enum Part { NONE, OUTLINE, SKIN, HAIR, SHIRT, PANTS, SHOES, EYE, ACC, PROP, WHITE, CRATE, SHIRT_D, SKIN_D }
const POSES := ["stand", "walk", "sit", "work", "swork", "cheer", "sing", "carry", "bucket", "lie", "squat", "bow", "bathe", "sit_eat", "can", "sack", "taichi", "pass"]
const SIZES := {"S": Vector2i(6, 12), "M": Vector2i(10, 20), "L": Vector2i(16, 32)}

var img: Image
var fw := 16
var fh := 32
var _ox := 0
var _oy := 0
var _sz := "L"


static func pose_index(name: String) -> int:
	var i := POSES.find(name)
	return i if i >= 0 else 0


static func build(size: String) -> ImageTexture:
	var ps := PeopleSprites.new()
	return ImageTexture.create_from_image(ps._sheet(size))


func _sheet(size: String) -> Image:
	_sz = size
	var fs: Vector2i = SIZES[size]
	fw = fs.x
	fh = fs.y
	img = Image.create(fw * POSES.size() * 2, fh * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for pi in POSES.size():
		for f in 2:
			for dr in 3:
				_ox = (pi * 2 + f) * fw
				_oy = dr * fh
				_figure(POSES[pi], f, dr)
				_outline()
	return img


func _put(x: int, y: int, part: int) -> void:
	if x < 0 or y < 0 or x >= fw or y >= fh:
		return
	img.set_pixel(_ox + x, _oy + y, Color(float(part) / 16.0 + 0.01, 0, 0, 1))


func _rect(x: int, y: int, w: int, h: int, part: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_put(xx, yy, part)


func _part_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= fw or y >= fh:
		return 0
	var c := img.get_pixel(_ox + x, _oy + y)
	if c.a < 0.5:
		return 0
	return int(c.r * 16.0)


## 비어 있는 칸 중 그림과 맞닿은 칸에 테두리(대각선은 안 친다 → 작아도 뭉개지지 않는다)
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


# ------------------------------------------------------------------ 인형
## 크기별 기본 치수(발 = 맨 아래 줄)
func _dims() -> Dictionary:
	match _sz:
		"S":
			return {"hw": 4, "hh": 4, "bw": 4, "bh": 3, "lh": 3, "sh": 1, "aw": 1, "ah": 2, "lw": 1}
		"M":
			return {"hw": 6, "hh": 6, "bw": 4, "bh": 4, "lh": 3, "sh": 1, "aw": 1, "ah": 3, "lw": 2}
	return {"hw": 10, "hh": 9, "bw": 8, "bh": 6, "lh": 5, "sh": 2, "aw": 2, "ah": 5, "lw": 3}


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
	if side:
		bw = maxi(bw - (2 if _sz == "L" else 1), 2)
		hw = maxi(hw - (1 if _sz == "L" else 0), 3)
	# 자세별 다리·몸 높이
	var foot := fh - 1
	var leg := lh
	var sit := pose in ["sit", "work", "sit_eat"]
	var squat := pose == "squat"
	if sit:
		leg = maxi(lh / 2, 1)
	if squat:
		leg = maxi(lh / 3, 1)
	if pose == "lie":
		_lie(D)
		return
	if pose == "bathe":
		_bathe(D, f)
		return
	var shoe_y := foot - sh + 1
	var leg_y := shoe_y - leg
	var body_y := leg_y - bh
	var head_y := body_y - hh + (1 if _sz != "S" else 0)
	if pose == "bow" and f == 1:
		head_y += maxi(hh / 3, 1)
	var bx := cx - bw / 2
	var hx := cx - hw / 2
	if side:
		hx = cx - hw / 2 + (1 if _sz == "L" else 0)
	# ── 다리
	var walking := pose in ["walk", "carry", "bucket", "can", "sack"]
	if sit:
		# 앉음: 앞에선 무릎 덩어리, 옆에선 앞으로 뻗은 허벅지
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
		if walking:
			if side:
				# 옆: 두 다리가 앞뒤로 벌어진다
				var st := 1 if _sz != "S" else 0
				var a := cx - lw + (st + 1 if f == 0 else -st - 1) - 1
				var b := cx - lw + (-st - 1 if f == 0 else st + 1)
				_rect(a, leg_y, lw, leg, Part.PANTS)
				_rect(a, shoe_y, lw + 1, sh, Part.SHOES)
				_rect(b, leg_y, lw, leg, Part.PANTS)
				_rect(b, shoe_y, lw + 1, sh, Part.SHOES)
				l1 = -99
			else:
				up1 = 1 if f == 0 else 0
				up2 = 0 if f == 0 else 1
		if l1 > -99:
			if side:
				_rect(cx - lw / 2 - 1, leg_y, lw + 1, leg, Part.PANTS)
				_rect(cx - lw / 2 - 1, shoe_y, lw + 2, sh, Part.SHOES)
			else:
				_rect(l1, leg_y, lw, leg - up1, Part.PANTS)
				_rect(l1, shoe_y - up1, lw, sh, Part.SHOES)
				_rect(l2, leg_y, lw, leg - up2, Part.PANTS)
				_rect(l2, shoe_y - up2, lw, sh, Part.SHOES)
	# ── 몸
	_rect(bx, body_y, bw, bh, Part.SHIRT)
	if _sz == "L":
		_rect(bx, body_y + bh - 1, bw, 1, Part.SHIRT_D)
		if not back and not side:
			_put(cx, body_y, Part.SKIN)   # 목
	# ── 팔
	_arms(pose, f, dr, bx, bw, body_y, aw, ah, hx, hw, head_y, hh)
	# ── 머리
	_head(hx, head_y, hw, hh, dr, f, pose)
	# ── 들고 있는 것
	_props(pose, f, dr, bx, bw, body_y, bh, head_y, cx, aw, ah)


func _arms(pose: String, f: int, dr: int, bx: int, bw: int, by: int, aw: int, ah: int, hx: int, hw: int, hy: int, hh: int) -> void:
	var lx := bx - aw
	var rx := bx + bw
	var side := dr == 1
	var sleeve := maxi(ah / 2, 1)
	var arm := func(x: int, y: int, h: int, hand_top: bool = false) -> void:
		if hand_top:
			_rect(x, y, aw, 1, Part.SKIN)
			_rect(x, y + 1, aw, maxi(h - 1, 0), Part.SHIRT)
		else:
			_rect(x, y, aw, mini(sleeve, h), Part.SHIRT)
			if h > sleeve:
				_rect(x, y + sleeve, aw, h - sleeve, Part.SKIN)
	match pose:
		"walk", "can", "sack":
			if side:
				arm.call(bx + bw / 2 - aw / 2 + (1 if f == 0 else -1), by + 1, ah)
			else:
				arm.call(lx, by + (1 if f == 0 else 0), ah)
				arm.call(rx, by + (0 if f == 0 else 1), ah)
		"work", "swork", "pass":
			# 팔을 앞으로(위아래로 번갈아 움직임) — 손이 몸 가운데 앞에
			var hand_y := by + ah / 2 + (1 if f == 1 else 0)
			if side:
				_rect(bx + bw - 1, by + 1, aw + 2, 1 if _sz != "L" else 2, Part.SHIRT)
				_rect(bx + bw + aw, hand_y - (1 if f == 0 else 0), 1 if _sz != "L" else 2, 1 if _sz != "L" else 2, Part.SKIN)
			elif dr == 0:
				arm.call(lx, by, maxi(ah - 2, 1))
				arm.call(rx, by, maxi(ah - 2, 1))
				_rect(bx + 1, hand_y, aw, 1 if _sz != "L" else 2, Part.SKIN)
				_rect(bx + bw - 1 - aw, hand_y + (1 if f == 0 else -1), aw, 1 if _sz != "L" else 2, Part.SKIN)
			else:
				arm.call(lx, by, maxi(ah - 2, 1))
				arm.call(rx, by, maxi(ah - 2, 1))
		"cheer", "taichi":
			var up := pose == "cheer"
			if side:
				arm.call(bx + bw / 2, hy if up else by, ah, up)
			else:
				if up:
					if f == 0:
						arm.call(lx, by - ah + 1, ah, true)
						arm.call(rx, by, ah)
					else:
						arm.call(lx, by, ah)
						arm.call(rx, by - ah + 1, ah, true)
				else:
					# 태극권: 팔을 옆으로 뻗음 / 앞으로 모음
					if f == 0:
						_rect(lx - aw, by + 1, aw * 2, 1 if _sz != "L" else 2, Part.SHIRT)
						_rect(rx, by + 1, aw * 2, 1 if _sz != "L" else 2, Part.SHIRT)
						_put(lx - aw - 1, by + 1, Part.SKIN)
						_put(rx + aw * 2, by + 1, Part.SKIN)
					else:
						arm.call(lx, by - ah + 2, ah, true)
						arm.call(rx, by - ah + 2, ah, true)
		"sing":
			if dr == 2:
				arm.call(lx, by, ah)
				arm.call(rx, by, ah)
			else:
				# 마이크를 입가에
				_rect(rx - (1 if side else 0), by - 1, aw, 2, Part.SHIRT)
				_rect(rx - (1 if side else 0), hy + hh - 2, aw, 2, Part.SKIN)
				_put(rx - (1 if side else 0) - 1, hy + hh - 2, Part.PROP)
				if not side:
					arm.call(lx - (1 if f == 1 else 0), by + (0 if f == 0 else -1), ah)
		"carry":
			# 상자를 머리 위로
			if not side:
				arm.call(lx, by - ah + 1, ah, true)
				arm.call(rx, by - ah + 1, ah, true)
			else:
				arm.call(bx + bw / 2, by - ah + 1, ah, true)
		"bucket":
			if side:
				arm.call(bx + bw / 2, by + 1, ah)
			else:
				arm.call(lx, by + (1 if f == 0 else 0), ah)
				arm.call(rx, by, ah + 1)
		"sit_eat":
			if dr == 0:
				_rect(bx, by + ah / 2, bw, 1, Part.SKIN)
				arm.call(lx, by, maxi(ah - 2, 1))
				arm.call(rx, by - (1 if f == 0 else 0), maxi(ah - 2, 1))
				_put(rx, by - (2 if f == 0 else 1), Part.SKIN)
			elif side:
				_rect(bx + bw - 1, by + 1, aw + 2, 1, Part.SHIRT)
				_put(bx + bw + aw, by + (0 if f == 0 else 1), Part.SKIN)
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
		_:
			if side:
				arm.call(bx + bw / 2 - aw / 2, by + 1, ah)
			else:
				arm.call(lx, by, ah)
				arm.call(rx, by, ah)


func _head(hx: int, hy: int, hw: int, hh: int, dr: int, f: int, pose: String) -> void:
	_rect(hx, hy, hw, hh, Part.SKIN)
	var hair_h := maxi(hh / 3, 1)
	if dr == 2:
		_rect(hx, hy, hw, hh - (1 if _sz != "S" else 0), Part.HAIR)
	elif dr == 1:
		_rect(hx, hy, hw, hair_h + (1 if _sz == "L" else 0), Part.HAIR)
		_rect(hx, hy, maxi(hw / 2 - 1, 1), hh - hh / 3, Part.HAIR)
		if _sz != "S":
			var ey := hy + hh / 2 + (1 if _sz == "L" else 0)
			_put(hx + hw - 2, ey, Part.EYE)
			if _sz == "L":
				_put(hx + hw - 2, ey - 1, Part.EYE)
				_put(hx + hw - 1, ey + 2, Part.SKIN_D)
	else:
		_rect(hx, hy, hw, hair_h + (1 if _sz == "L" else 0), Part.HAIR)
		if _sz == "L":
			_rect(hx, hy + hair_h, 1, hh / 2, Part.HAIR)
			_rect(hx + hw - 1, hy + hair_h, 1, hh / 2, Part.HAIR)
			_put(hx + 2, hy + hair_h + 1, Part.HAIR)
		if _sz != "S":
			var ey2 := hy + hh / 2 + (1 if _sz == "L" else 0)
			var blink := pose in ["stand", "sit"] and f == 1
			var ex1 := hx + (2 if _sz == "L" else 1)
			var ex2 := hx + hw - (3 if _sz == "L" else 2)
			if blink:
				_put(ex1, ey2, Part.SKIN_D)
				_put(ex2, ey2, Part.SKIN_D)
			else:
				_put(ex1, ey2, Part.EYE)
				_put(ex2, ey2, Part.EYE)
				if _sz == "L":
					_put(ex1, ey2 - 1, Part.EYE)
					_put(ex2, ey2 - 1, Part.EYE)
			if _sz == "L":
				_put(hx + 1, ey2 + 1, Part.ACC if false else Part.SKIN_D)
				_put(hx + hw - 2, ey2 + 1, Part.SKIN_D)
				if pose in ["sing", "cheer"]:
					_rect(hx + hw / 2 - 1, ey2 + 2, 2, 1, Part.OUTLINE)


func _props(pose: String, f: int, dr: int, bx: int, bw: int, by: int, bh: int, hy: int, cx: int, aw: int, ah: int) -> void:
	var L := _sz == "L"
	match pose:
		"carry":
			var w2 := bw + (2 if L else 2)
			var h2 := 4 if L else 2
			_rect(cx - w2 / 2, hy - h2 + (0 if L else 1), w2, h2, Part.CRATE)
		"bucket", "pass":
			var bxp := bx + bw + (aw if dr != 1 else -1)
			var byp := by + ah - (0 if pose == "bucket" else (2 if f == 0 else 3))
			var s := 4 if L else 2
			_rect(bxp - (1 if L else 0), byp, s, s, Part.PROP)
			if L:
				_rect(bxp - 1, byp, s, 1, Part.WHITE)
		"can":
			var s2 := 2 if L else 1
			_rect(bx + bw + (aw if dr != 1 else 0), by + ah - 1, s2, s2 + 1, Part.PROP)
		"sack":
			var s3 := 5 if L else 3
			_rect(bx - (2 if L else 1), by - s3 + 2, s3 + 2, s3, Part.CRATE)
		"sit_eat":
			if dr == 0:
				_rect(cx - (2 if L else 1), by + ah / 2 - 1, 4 if L else 2, 2 if L else 1, Part.WHITE)
		"work", "swork":
			pass


func _lie(D: Dictionary) -> void:
	# 누운 사람: 베개 위 머리 + 이불 덩어리(침대·의자 위)
	var L := _sz == "L"
	var y0 := fh - (8 if L else (5 if _sz == "M" else 3))
	var hs := 7 if L else (4 if _sz == "M" else 2)
	_rect(1, y0, hs, hs, Part.SKIN)
	_rect(1, y0, hs, maxi(hs / 3, 1), Part.HAIR)
	if L:
		_put(4, y0 + 4, Part.EYE)
		_put(6, y0 + 4, Part.EYE)
	_rect(1 + hs, y0 + 1, fw - hs - 2, hs - 1, Part.SHIRT)
	_rect(1 + hs, y0 + 1, fw - hs - 2, 1, Part.SHIRT_D)


func _bathe(D: Dictionary, f: int) -> void:
	# 탕 속: 머리와 어깨만(물이 아래를 가린다)
	var hw: int = D["hw"]
	var hh: int = D["hh"]
	var cx := fw / 2
	var y := fh - hh - (3 if _sz == "L" else 1) + (1 if f == 1 else 0)
	_rect(cx - hw / 2, y, hw, hh, Part.SKIN)
	_rect(cx - hw / 2, y, hw, maxi(hh / 3, 1), Part.WHITE)   # 수건
	if _sz != "S":
		_put(cx - hw / 2 + 2, y + hh / 2 + 1, Part.EYE)
		_put(cx + hw / 2 - 3, y + hh / 2 + 1, Part.EYE)
	_rect(cx - hw / 2 - 1, y + hh, hw + 2, fh - y - hh, Part.SKIN)
