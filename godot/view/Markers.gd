class_name CityMarkers
extends Node3D
## 건물 표시(뷰 전용): 수요 부족 "!" · 승급 가능 "▲"(통통 튄다) · 멈춘 시설 "z".
## buildings[bid]만 읽는다. building_changed마다 refresh() — 메시는 다시 짓지 않는다.
## 깊이 검사 없이 맨 위에 그리되, 완전히 파묻힌 칸(드러난 면이 없는 칸)은 건너뛴다.

const MAX_INST := 256
const ICON := 7          # 아이콘 칸 크기(텍셀)
const KINDS := {"bad": 0, "up": 1, "off": 2, "warn": 3}

var cfg: ViewCfg
var view: Control
var mesher: CityMesher
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _items: Array = []   # [{pos: Vector3, kind: int, seed: float}]
var show_warn := false   # needs 렌즈가 켜지면 주의(노랑)도 보인다


func setup(c: ViewCfg, v: Control, m: CityMesher) -> void:
	cfg = c
	view = v
	mesher = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = MAX_INST
	mm.visible_instance_count = 0
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://view/shaders/marker.gdshader")
	var tex := _make_icons()
	_mat.set_shader_parameter("tex", tex)
	_mat.set_shader_parameter("frame_px", Vector2(ICON, ICON))
	_mat.set_shader_parameter("sheet_px", Vector2(tex.get_width(), tex.get_height()))
	_mat.render_priority = 20
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = _mat
	_mmi.custom_aabb = AABB(Vector3(-30, -5, -30), Vector3(80, 40, 80))
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


func _make_icons() -> ImageTexture:
	# 7×7 아이콘 4개: 0 "!"(빨강) 1 "▲"(초록, 테두리) 2 "z"(회색) 3 "!"(노랑)
	var img := Image.create(ICON * 4, ICON, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color("#2a2238")
	_badge(img, 0, Color("#ff4a4a"), ink)
	for y in [1, 2, 3]:
		img.set_pixel(3, y, Color.WHITE)
	img.set_pixel(3, 5, Color.WHITE)
	var g := Color("#5dff9a")
	var arrow := ["...#...", "..###..", ".#####.", "#######", "..###..", "..###..", "......."]
	for y in 7:
		for x in 7:
			if arrow[y][x] == "#":
				img.set_pixel(ICON + x, y, g)
	img.set_pixel(ICON + 3, 0, Color("#e8fff0"))
	for y in [4, 5]:
		img.set_pixel(ICON + 2, y, g.darkened(0.35))
	_badge(img, ICON * 2, Color("#8a84a6"), ink)
	for x in [2, 3, 4]:
		img.set_pixel(ICON * 2 + x, 2, Color.WHITE)
		img.set_pixel(ICON * 2 + x, 4, Color.WHITE)
	img.set_pixel(ICON * 2 + 3, 3, Color.WHITE)
	_badge(img, ICON * 3, Color("#ffb43c"), ink)
	for y in [1, 2, 3]:
		img.set_pixel(ICON * 3 + 3, y, ink)
	img.set_pixel(ICON * 3 + 3, 5, ink)
	return ImageTexture.create_from_image(img)


func _badge(img: Image, ox: int, c: Color, ink: Color) -> void:
	for y in 7:
		for x in 7:
			var dx := absi(x - 3)
			var dy := absi(y - 3)
			if dx + dy <= 4:
				img.set_pixel(ox + x, y, ink)
			if dx + dy <= 3 and dx <= 2 and dy <= 2:
				img.set_pixel(ox + x, y, c)


## 상태에서 표시 목록을 다시 만든다(가볍다: 건물 수만큼).
func refresh(st: CityState) -> void:
	_items.clear()
	if st == null:
		return
	var bs: Variant = st.get("buildings")
	if not (bs is Dictionary):
		_push()
		return
	var cut: int = int(view.floor_cut)
	var fh := cfg.floor_h
	for bid in bs:
		var b: Variant = bs[bid]
		if not (b is Dictionary):
			continue
		var kind := -1
		var bk: String = str(b.get("kind", ""))
		if bk == "house":
			var ns: String = str(b.get("need_state", "ok"))
			if ns == "bad":
				kind = KINDS["bad"]
			elif bool(b.get("upgradable", false)):
				kind = KINDS["up"]
			elif ns == "warn" and show_warn:
				kind = KINDS["warn"]
		elif bk == "facility":
			if not bool(b.get("active", true)):
				kind = KINDS["off"]
		if kind < 0:
			continue
		var pos: Variant = b.get("pos", null)
		if not (pos is Vector3i):
			continue
		var p: Vector3i = pos
		if cut >= 0 and p.z > cut:
			continue
		var size := int(b.get("size", 1))
		if size <= 1 and not _exposed(p, cut):
			continue
		var c := Vector3(p.x + 0.5 * float(size), (p.z + 1) * fh + 0.05, p.y + 0.5 * float(size))
		if cut >= 0 and p.z == cut:
			c.y = p.z * fh + 0.45
		_items.append({"pos": c, "kind": kind, "seed": float(int(bid) % 17) / 17.0})
		if _items.size() >= MAX_INST:
			break
	_push()


func _exposed(p: Vector3i, cut: int) -> bool:
	if cut >= 0 and p.z == cut:
		return true
	if not mesher.solid.has(p + Vector3i(0, 0, 1)):
		return true
	for d in CityMesher.DIR:
		if not mesher.solid.has(p + d):
			return true
	return false


func _push() -> void:
	var mm := _mmi.multimesh
	var n := mini(_items.size(), MAX_INST)
	for i in n:
		var it: Dictionary = _items[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, it["pos"]))
		mm.set_instance_custom_data(i, Color(float(it["kind"]), 1.0 if it["kind"] == KINDS["up"] else 0.0, float(it["seed"]), 0.0))
	mm.visible_instance_count = n


func set_frame(ppu: float, px_scale: float, t: float) -> void:
	_mat.set_shader_parameter("ppu", ppu)
	_mat.set_shader_parameter("px_scale", px_scale)
	_mat.set_shader_parameter("time_s", t)


func count() -> int:
	return _items.size()
