class_name LightGrid
extends RefCounted
## LightGrid — 셰이더가 읽는 두 장의 데이터 텍스처.
##  heightmap: 기둥 높이(1/16층) → 격자 DDA 그림자·맞닿음 음영.
##  lightgrid: 복셀 빛(RGB=네온, A=창 불빛) → 네온이 벽·바닥에 실제로 번진다. 실시간 광원 0개.

const HM := 32
const HM_ORG := -10

const LX := 32      # 반 칸 해상도(x,z)
const LZ := 32
const LY := 14      # 층당 1복셀
const L_ORG := Vector3(-2.0, 0.0, -2.0)

var cfg: ViewCfg
var hm_img: Image
var hm_tex: ImageTexture
var lg_tex: ImageTexture3D
var _acc := PackedFloat32Array()


func setup(c: ViewCfg) -> void:
	cfg = c
	hm_img = Image.create(HM, HM, false, Image.FORMAT_R8)
	hm_tex = ImageTexture.create_from_image(hm_img)
	var slices: Array[Image] = []
	for i in LY:
		var im := Image.create(LX, LZ, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		slices.append(im)
	lg_tex = ImageTexture3D.new()
	lg_tex.create(Image.FORMAT_RGBA8, LX, LZ, LY, false, slices)


func origin() -> Vector3:
	return L_ORG


func inv_size() -> Vector3:
	# 셰이더는 (x, z, y) 순서로 샘플한다
	return Vector3(1.0 / (LX * 0.5), 1.0 / (LY * cfg.floor_h), 1.0 / (LZ * 0.5))


func update_heights(col_h: Dictionary) -> void:
	hm_img.fill(Color(0, 0, 0, 1))
	for c in col_h:
		var x: int = c.x - HM_ORG
		var y: int = c.y - HM_ORG
		if x >= 0 and y >= 0 and x < HM and y < HM:
			hm_img.set_pixel(x, y, Color(clampf(float(col_h[c]) * 16.0 / 255.0, 0.0, 1.0), 0, 0, 1))
	hm_tex.update(hm_img)


func update_lights(lights: Array) -> void:
	var n := LX * LZ * LY * 4
	if _acc.size() != n:
		_acc.resize(n)
	_acc.fill(0.0)
	var fh := cfg.floor_h
	for l in lights:
		var pos: Vector3 = l["pos"]
		var r: float = float(l["r"])
		var warm: float = float(l.get("warm", 0.0))
		var c: Color = l["color"]
		var cr := c.r
		var cg := c.g
		var cb := c.b
		if warm > 0.0:
			cr = 0.0
			cg = 0.0
			cb = 0.0
		var gx := (pos.x - L_ORG.x) * 2.0 - 0.5
		var gz := (pos.z - L_ORG.z) * 2.0 - 0.5
		var gy := pos.y / fh - 0.5
		var rx := r * 2.0
		var ry := r / fh
		var x0 := maxi(int(floor(gx - rx)), 0)
		var x1 := mini(int(ceil(gx + rx)), LX - 1)
		var z0 := maxi(int(floor(gz - rx)), 0)
		var z1 := mini(int(ceil(gz + rx)), LZ - 1)
		var y0 := maxi(int(floor(gy - ry)), 0)
		var y1 := mini(int(ceil(gy + ry)), LY - 1)
		var inv_r := 1.0 / r
		for y in range(y0, y1 + 1):
			var dy := (float(y) - gy) * fh
			for z in range(z0, z1 + 1):
				var dz := (float(z) - gz) * 0.5
				var base := ((y * LZ + z) * LX) * 4
				for x in range(x0, x1 + 1):
					var dx := (float(x) - gx) * 0.5
					var dd := sqrt(dx * dx + dy * dy + dz * dz) * inv_r
					if dd >= 1.0:
						continue
					var f := (1.0 - dd)
					f = f * f
					var i := base + x * 4
					if warm > 0.0:
						_acc[i + 3] += f * warm
					else:
						_acc[i] += cr * f
						_acc[i + 1] += cg * f
						_acc[i + 2] += cb * f
	var slices: Array[Image] = []
	var bytes := PackedByteArray()
	bytes.resize(LX * LZ * 4)
	for y in LY:
		var off := y * LZ * LX * 4
		for i in LX * LZ * 4:
			var v := _acc[off + i]
			bytes[i] = int(clampf(v, 0.0, 1.0) * 255.0)
		slices.append(Image.create_from_data(LX, LZ, false, Image.FORMAT_RGBA8, bytes))
	lg_tex.update(slices)
