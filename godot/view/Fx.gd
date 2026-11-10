class_name CityFx
extends Node3D
## 연출 입자(김·연기·향·불꽃·물방울·비둘기·먼지) + 카이탁 비행기. 전부 셰이더가 시간으로 움직인다.

const FxShader := preload("res://view/shaders/fx.gdshader")
const KINDS := {"steam": 0, "smoke": 1, "incense": 2, "sparks": 3, "drip": 4, "pigeons": 5, "dust": 6, "mote": 7}
const COUNT := {"steam": 4, "smoke": 5, "incense": 3, "sparks": 5, "drip": 1, "pigeons": 6, "mote": 2}

var cfg: ViewCfg
var _mm: MultiMesh
var _mat: ShaderMaterial
var _mi: MultiMeshInstance3D
var _emitters: Array = []
var _dust: Array = []          # [{pos, t0}]
var _plane: MeshInstance3D
var _plane_mat: ShaderMaterial
var _motes: Array = []


func setup(c: ViewCfg, lg: Texture3D) -> void:
	cfg = c
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_mm.mesh = q
	_mm.instance_count = 0
	_mat = ShaderMaterial.new()
	_mat.shader = FxShader
	_mat.set_shader_parameter("lightgrid", lg)
	_mi = MultiMeshInstance3D.new()
	_mi.multimesh = _mm
	_mi.material_override = _mat
	_mi.custom_aabb = AABB(Vector3(-30, -5, -30), Vector3(80, 40, 80))
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	_make_plane()


func set_emitters(list: Array) -> void:
	_emitters = list
	_rebuild()


func set_motes(lights: Array) -> void:
	_motes = []
	var i := 0
	for l in lights:
		if float(l.get("warm", 0.0)) <= 0.0 and float(l.get("r", 0.0)) >= 2.0:
			i += 1
			if i % 2 == 0:
				_motes.append({"pos": l["pos"], "type": "mote"})
	_rebuild()


func add_dust(pos: Vector3, now: float) -> void:
	_dust.append({"pos": pos, "t0": now})
	_rebuild()


func prune(now: float) -> void:
	if _dust.is_empty():
		return
	var keep: Array = []
	for d in _dust:
		if now - float(d["t0"]) < 2.0:
			keep.append(d)
	if keep.size() != _dust.size():
		_dust = keep
		_rebuild()


func _rebuild() -> void:
	var inst: Array = []
	var k := 0
	for src in [_emitters, _motes]:
		for e in src:
			var type: String = str(e["type"])
			if not KINDS.has(type):
				continue
			var n: int = int(COUNT.get(type, 1))
			for i in n:
				k += 1
				var seed_f := fposmod(float(k) * 0.6180339 + float(i) * 0.137, 1.0)
				inst.append([e["pos"], Color(seed_f, float(KINDS[type]), 0.0, 1.0)])
	for d in _dust:
		for i in 8:
			inst.append([d["pos"], Color(float(i) / 8.0 + 0.03, 6.0, float(d["t0"]), 1.0)])
	_mm.instance_count = inst.size()
	for i in inst.size():
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, inst[i][0]))
		_mm.set_instance_custom_data(i, inst[i][1])


func set_frame(ppu: float, zoom: float, time_s: float, night: float, work: float, amb: Vector3, neon_gain: float, lg_origin: Vector3, lg_inv: Vector3, cut_y: float) -> void:
	_mat.set_shader_parameter("ppu", ppu)
	_mat.set_shader_parameter("zoom", zoom)
	_mat.set_shader_parameter("time_s", time_s)
	_mat.set_shader_parameter("night", night)
	_mat.set_shader_parameter("work", work)
	_mat.set_shader_parameter("amb", amb)
	_mat.set_shader_parameter("neon_gain", neon_gain)
	_mat.set_shader_parameter("lg_origin", lg_origin)
	_mat.set_shader_parameter("lg_inv_size", lg_inv)
	_mat.set_shader_parameter("cut_y", cut_y)
	_plane_mat.set_shader_parameter("amb", amb)
	_plane_mat.set_shader_parameter("night", night)
	_plane_mat.set_shader_parameter("time_s", time_s)


# ------------------------------------------------------------------ 비행기
func _make_plane() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color("#f2f2f6")
	var wing := Color("#d2d4de")
	var dark := Color("#9a9cb0")
	var stripe := Color("#3f8f6a")
	# 날개(뒤로 젖힌 사다리꼴)
	for y in range(3, 61):
		var dy := absf(float(y) - 31.5)
		var x0 := int(30.0 - dy * 0.45)
		var w := int(9.0 - dy * 0.17)
		for x in range(x0, x0 + maxi(w, 3)):
			img.set_pixel(x, y, wing if x < x0 + maxi(w, 3) - 1 else dark)
	# 꼬리날개
	for y in range(21, 43):
		var dy2 := absf(float(y) - 31.5)
		var x1 := int(8.0 - dy2 * 0.35)
		for x in range(x1, x1 + 5):
			if x >= 0:
				img.set_pixel(x, y, wing)
	# 동체
	for x in range(3, 61):
		var hw := 3
		if x > 55:
			hw = maxi(1, 3 - (x - 55) / 2)
		if x < 8:
			hw = 2
		for y in range(32 - hw, 32 + hw):
			img.set_pixel(x, y, body)
		img.set_pixel(x, 32 + hw - 1, dark)
	for x in range(8, 54):
		img.set_pixel(x, 30, stripe)
	# 엔진
	for e in [[30, 18], [30, 45], [27, 10], [27, 53]]:
		for x in range(e[0], e[0] + 5):
			img.set_pixel(x, e[1], dark)
			img.set_pixel(x, e[1] + 1, dark)
	# 날개 끝 항법등(알파 0.75 = 깜빡이는 발광)
	img.set_pixel(18, 3, Color(1.0, 0.3, 0.3, 0.75))
	img.set_pixel(18, 60, Color(0.3, 1.0, 0.4, 0.75))
	img.set_pixel(60, 31, Color(1, 1, 1, 0.75))
	var tex := ImageTexture.create_from_image(img)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : filter_nearest, repeat_disable;
uniform vec3 amb = vec3(1.0);
uniform float night = 0.0;
uniform float time_s = 0.0;
void fragment() {
	vec4 t = texture(tex, UV);
	if (t.a < 0.25) { discard; }
	vec3 c = t.rgb * mix(amb, vec3(1.0), 0.35) * mix(1.0, 0.55, night);
	if (t.a < 0.9) { c = t.rgb * step(0.5, fract(time_s * 1.5)); if (c.r + c.g + c.b < 0.1) { c = vec3(0.2); } }
	ALBEDO = c;
}"""
	_plane_mat = ShaderMaterial.new()
	_plane_mat.shader = sh
	_plane_mat.set_shader_parameter("tex", tex)
	var q := PlaneMesh.new()
	q.size = Vector2(7.0, 7.0)
	_plane = MeshInstance3D.new()
	_plane.mesh = q
	_plane.material_override = _plane_mat
	_plane.visible = false
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plane)


## ground = 그림자가 지면에 떨어지는 점(xz), heading = 진행 각(rad), sun = 해 방향.
func set_plane(on: bool, ground: Vector2, heading: float, sun: Vector3, alt: float) -> void:
	_plane.visible = on
	if not on:
		return
	var off := Vector3(sun.x, 0, sun.z) / maxf(sun.y, 0.2) * alt * 0.35
	_plane.position = Vector3(ground.x, alt, ground.y) + off
	_plane.rotation = Vector3(0, -heading, 0)
