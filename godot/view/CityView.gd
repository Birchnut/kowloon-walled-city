extends Control
## CityView — 3D 픽셀 렌더러(뷰 층). 상태를 읽고 이벤트를 듣기만 한다. 규칙 0.
## API 계약: docs/ARCHITECTURE.md "CityView". 설명·결정 기록: docs/VIEW_NOTES.md.

signal cell_tapped(info: Dictionary)
signal view_changed

const CityShader := preload("res://view/shaders/city.gdshader")
const SkyShader := preload("res://view/shaders/sky.gdshader")
const OutlineShader := preload("res://view/shaders/outline.gdshader")
const ScreenShader := preload("res://view/shaders/screen.gdshader")
const CAM_DIST := 80.0

var cfg := ViewCfg.new()
var atlas := PixelAtlas.new()
var mesher := CityMesher.new()
var grid_tex := LightGrid.new()

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _screen: TextureRect
var _sky: MeshInstance3D
var _outline: MeshInstance3D
var _floors_root: Node3D
var _ground: MeshInstance3D
var _overlay: MeshInstance3D
var _mat: ShaderMaterial
var _mat_ground: ShaderMaterial
var _sky_mat: ShaderMaterial
var _outline_mat: ShaderMaterial
var _screen_mat: ShaderMaterial
var _floor_nodes: Array = []       # [z] -> MeshInstance3D
var _floor_data: Array = []        # [z] -> {lights, emitters}
var _cut_node: MeshInstance3D
var _dirty: Dictionary = {}        # z -> true
var _lights_dirty := false
var _lights_timer := 0.0
var people: Node = null
var fx: Node = null

# 카메라 상태
var angle := 0                     # 0..3
var _yaw := 45.0                   # 도(애니메이션 값)
var _yaw_from := 45.0
var _yaw_to := 45.0
var _yaw_t := 1.0
var zoom_i := 0
var _zoom_levels: Array = [1, 2, 4]
var target := Vector3(6, 2.4, 6)   # 화면 중심이 보는 월드 점
var floor_cut := -1
var _time_override := -1.0
var _up := 2                       # 내부 1px = 실제 몇 px
var _iw := 270
var _ih := 480
var _canvas_scale := 1.0
var _frac := Vector2.ZERO
var _t := 0.0
var _tod_vals: Dictionary = {}
var _shake := Vector2.ZERO

# 연출
var _wave_r := 1000.0
var _wave_center := Vector3(6, 0, 6)
var _plane_t := -1.0
var _plane_next := 12.0
var _plane_dir := 0.6
var _last_power := -1
var _show_zones := false
var _ghost: Dictionary = {}
var _spots: Array = []
var _overlay_dirty := false
var _prev_kinds: Dictionary = {}
var _cut_emitters: Array = []
var _drops: Array = []
var _all_emitters: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	cfg.reload()
	_zoom_levels = cfg.r("pixel.zoom_levels", [1, 2, 4])
	zoom_i = clampi(int(cfg.r("pixel.default_zoom", 0)), 0, _zoom_levels.size() - 1)
	atlas.build(cfg)
	mesher.setup(cfg, atlas)
	grid_tex.setup(cfg)
	_build_tree()
	Game.register_view(self)
	Game.event.connect(_on_event)
	Game.state_replaced.connect(_on_state_replaced)
	resized.connect(_layout)
	_layout()
	_on_state_replaced()


func _exit_tree() -> void:
	if Game.view == self:
		Game.view = null


# ------------------------------------------------------------------ 씬 조립
func _build_tree() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.use_taa = false
	_vp.use_debanding = false
	_vp.positional_shadow_atlas_size = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(272, 482)
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 1.0
	_cam.far = 200.0
	_cam.current = true
	_world.add_child(_cam)

	_mat = ShaderMaterial.new()
	_mat.shader = CityShader
	_mat.set_shader_parameter("atlas", atlas.tex)
	_mat.set_shader_parameter("heightmap", grid_tex.hm_tex)
	_mat.set_shader_parameter("lightgrid", grid_tex.lg_tex)
	_mat_ground = _mat

	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_sky = MeshInstance3D.new()
	_sky.mesh = quad
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SkyShader
	_sky_mat.set_shader_parameter("skyline", SkyTex.build(7))
	_sky_mat.render_priority = -10
	_sky.material_override = _sky_mat
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cam.add_child(_sky)
	_sky.position = Vector3(0, 0, -195.0)

	_outline = MeshInstance3D.new()
	_outline.mesh = quad
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = OutlineShader
	_outline_mat.render_priority = -5
	_outline.material_override = _outline_mat
	_cam.add_child(_outline)
	_outline.position = Vector3(0, 0, -1.5)

	_ground = MeshInstance3D.new()
	_ground.material_override = _mat
	_world.add_child(_ground)
	_floors_root = Node3D.new()
	_world.add_child(_floors_root)
	_cut_node = MeshInstance3D.new()
	_cut_node.material_override = _mat
	_cut_node.visible = false
	_world.add_child(_cut_node)
	_overlay = MeshInstance3D.new()
	_world.add_child(_overlay)
	var fxn := CityFx.new()
	fxn.setup(cfg, grid_tex.lg_tex)
	_world.add_child(fxn)
	fx = fxn
	var pn := CityPeople.new()
	pn.setup(cfg, self, mesher, grid_tex.lg_tex)
	_world.add_child(pn)
	people = pn

	_screen = TextureRect.new()
	_screen.texture = _vp.get_texture()
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = ScreenShader
	_screen.material = _screen_mat
	add_child(_screen)


func _layout() -> void:
	# 실제 창 픽셀 기준 정수배 확대율을 정한다.
	var xf := get_viewport().get_screen_transform() * get_global_transform()
	_canvas_scale = maxf(xf.get_scale().x, 0.01)
	var real := size * _canvas_scale
	var tw := float(cfg.r("pixel.target_width", 270))
	_up = maxi(1, int(round(real.x / tw)))
	_iw = int(ceil(real.x / float(_up) / 2.0)) * 2
	_ih = int(ceil(real.y / float(_up) / 2.0)) * 2
	_vp.size = Vector2i(_iw + 2, _ih + 2)
	_apply_camera()


# ------------------------------------------------------------------ 카메라
func ppu() -> float:
	return cfg.ppu1 * float(_zoom_levels[zoom_i])


func _cam_basis() -> Basis:
	var e := cfg.elev
	if floor_cut >= 0:
		e = deg_to_rad(float(cfg.r("pixel.cut_elevation_deg", 30.0)))
	return Basis(Vector3.UP, deg_to_rad(_yaw)) * Basis(Vector3.RIGHT, -e)


func _apply_camera() -> void:
	if _cam == null:
		return
	var b := _cam_basis()
	var p := ppu()
	var vw := float(_iw + 2)
	var vh := float(_ih + 2)
	_cam.size = vh / p
	var cr := target.dot(b.x) * p
	# 기준점(부지 중심)이 화면 가운데보다 살짝 아래에 오도록(위 HUD·아래 버튼 띠 감안)
	var cu := target.dot(b.y) * p + (float(cfg.r("pixel.center_y", 0.56)) - 0.5) * float(_ih)
	var sx: float = floor(cr)
	var sy: float = floor(cu)
	_frac = Vector2(cr - sx, cu - sy)
	if not bool(cfg.r("pixel.subpixel_scroll", true)) or _yaw_t < 1.0:
		_frac = Vector2.ZERO
	# 0.25px 치우침: 픽셀 중심이 텍셀 경계에 걸리지 않게(줌 ×1에서 짝수 텍셀만 고르게)
	# 픽셀 중심이 텍셀 경계에 걸리지 않게 0.1텍셀만큼 어긋나게 둔다(줌마다 텍셀/픽셀 비가 달라 치우침도 달라짐)
	var bias := clampf(0.5 - 0.05 * float(_zoom_levels[zoom_i]), 0.05, 0.45)
	var pos: Vector3 = b.x * ((sx - bias + _shake.x) / p) + b.y * ((sy + bias + _shake.y) / p) + b.z * CAM_DIST
	_cam.transform = Transform3D(b, pos)
	var ext := Vector3(vw / p, vh / p, 1.0)
	_sky.scale = ext
	_outline.scale = ext
	# 화면 붙이기: 남는 소수 픽셀만큼 확대된 그림을 민다
	var k := float(_up) / _canvas_scale
	var fq := Vector2(floor(_frac.x * float(_up)) / float(_up), floor(_frac.y * float(_up)) / float(_up))
	_screen.size = Vector2(vw, vh) * k
	_screen.position = Vector2((-1.0 - fq.x) * k, (-1.0 + fq.y) * k)
	if _sky_mat:
		_sky_mat.set_shader_parameter("res", Vector2(vw, vh))
		_outline_mat.set_shader_parameter("res", Vector2(vw, vh))
		_sky_mat.set_shader_parameter("pan_px", Vector2(cr, -cu + target.y * 0.0))
		_sky_mat.set_shader_parameter("yaw_px", _yaw / 360.0 * 512.0 * 2.0)
		_sky_mat.set_shader_parameter("horizon", vh * 0.34)
		_sky_mat.set_shader_parameter("zoom", float(_zoom_levels[zoom_i]))
	if _mat:
		var fwd := -b.z
		_mat.set_shader_parameter("view_fwd", Vector3(fwd.x, 0, fwd.z).normalized())
		_mat.set_shader_parameter("view_center", Vector3(cfg.grid.x * 0.5, 0, cfg.grid.y * 0.5))
	view_changed.emit()


func _default_target() -> Vector3:
	# 덩어리의 세로 중심쯤(가장 높은 탑의 1/3 높이)을 본다
	return Vector3(cfg.grid.x * 0.5, cfg.floor_h * clampf(float(mesher.top_z) * 0.34, 0.6, 3.6), cfg.grid.y * 0.5)


# ------------------------------------------------------------------ 공개 API
func set_floor_cut(n: int) -> void:
	n = clampi(n, -1, cfg.grid.z)
	if n == floor_cut:
		return
	floor_cut = n
	_apply_cut()
	_apply_camera()


func rotate_view(dir: int) -> void:
	angle = posmod(angle + (1 if dir > 0 else -1), 4)
	_yaw_from = _yaw
	_yaw_to = _yaw_from + (90.0 if dir > 0 else -90.0)
	_yaw_t = 0.0


func zoom_step(dir: int) -> void:
	set_zoom(zoom_i + (1 if dir > 0 else -1))


func set_zoom(level: int) -> void:
	level = clampi(level, 0, _zoom_levels.size() - 1)
	if level == zoom_i:
		return
	zoom_i = level
	_clamp_target()
	_apply_camera()


func set_time_override(t: float) -> void:
	_time_override = t


func show_zones(on: bool) -> void:
	_show_zones = on
	_overlay_dirty = true


func show_ghost(pos: Vector3i, facility_id: String, ok: bool) -> void:
	_ghost = {"pos": pos, "id": facility_id, "ok": ok}
	_overlay_dirty = true


func show_spots(cells: Array) -> void:
	_spots = cells
	_overlay_dirty = true


func clear_overlay() -> void:
	_ghost = {}
	_spots = []
	_overlay_dirty = true


## 셀 → 이 Control 좌표(말풍선 위치). 셀 윗면 중심.
func project(pos: Vector3i) -> Vector2:
	return project_world(Vector3(pos.x + 0.5, (pos.z + 1) * cfg.floor_h, pos.y + 0.5))


func project_world(w: Vector3) -> Vector2:
	var b := _cam.global_transform.basis
	var rel := w - _cam.global_transform.origin
	var p := ppu()
	var px := Vector2(rel.dot(b.x) * p + float(_iw + 2) * 0.5, float(_ih + 2) * 0.5 - rel.dot(b.y) * p)
	return _screen.position + px * (float(_up) / _canvas_scale)


func _to_internal(screen_pos: Vector2) -> Vector2:
	return (screen_pos - _screen.position) / (float(_up) / _canvas_scale)


## 화면 점 → {hit, pos, col, above, face, adjacent, in_grid}. 물리 없이 격자 DDA.
func pick(screen_pos: Vector2) -> Dictionary:
	var ip := _to_internal(screen_pos)
	var b := _cam.global_transform.basis
	var p := ppu()
	var o := _cam.global_transform.origin + b.x * ((ip.x - float(_iw + 2) * 0.5) / p) + b.y * ((float(_ih + 2) * 0.5 - ip.y) / p)
	var d := -b.z
	return _pick_ray(o, d)


func _pick_ray(o: Vector3, d: Vector3) -> Dictionary:
	var fh := cfg.floor_h
	var st: CityState = Game.state
	# 층 높이를 1로 펴서 균일 격자로 만든다
	var ro := Vector3(o.x, o.y / fh, o.z)
	var rd := Vector3(d.x, d.y / fh, d.z)
	var max_z := float(cfg.grid.z + 2)
	if floor_cut >= 0:
		max_z = float(floor_cut + 1)
	# 위쪽 경계 평면까지 전진
	if rd.y >= 0.0:
		return {"hit": false, "pos": Vector3i(-1, -1, 0), "col": Vector2i(-1, -1), "above": Vector3i(-1, -1, 0), "in_grid": false}
	var t0 := (max_z - ro.y) / rd.y
	var pnt := ro + rd * maxf(t0, 0.0)
	var cell := Vector3i(int(floor(pnt.x)), int(floor(pnt.z)), int(floor(pnt.y - 0.0001)))
	var stp := Vector3i(1 if rd.x > 0.0 else -1, 1 if rd.z > 0.0 else -1, -1)
	var inv := Vector3(1.0 / maxf(absf(rd.x), 1e-6), 1.0 / maxf(absf(rd.z), 1e-6), 1.0 / maxf(absf(rd.y), 1e-6))
	var tm := Vector3(
		((float(cell.x) + (1.0 if rd.x > 0.0 else 0.0)) - pnt.x) / (rd.x if absf(rd.x) > 1e-6 else 1e-6),
		((float(cell.y) + (1.0 if rd.z > 0.0 else 0.0)) - pnt.z) / (rd.z if absf(rd.z) > 1e-6 else 1e-6),
		(float(cell.z) - pnt.y) / rd.y)
	var face := Vector3i(0, 0, 1)
	for i in 96:
		if cell.z < 0:
			break
		if st.cells.has(cell):
			var col := Vector2i(cell.x, cell.y)
			var top := cell.z
			while st.cells.has(Vector3i(cell.x, cell.y, top)):
				top += 1
			return {"hit": true, "pos": cell, "col": col, "above": Vector3i(cell.x, cell.y, top), "face": face, "adjacent": cell + face, "in_grid": true}
		if tm.x < tm.y and tm.x < tm.z:
			cell.x += stp.x
			tm.x += inv.x
			face = Vector3i(-stp.x, 0, 0)
		elif tm.y < tm.z:
			cell.y += stp.y
			tm.y += inv.y
			face = Vector3i(0, -stp.y, 0)
		else:
			cell.z -= 1
			tm.z += inv.z
			face = Vector3i(0, 0, 1)
	# 지면
	var tg := -ro.y / rd.y
	var g := ro + rd * tg
	var gc := Vector2i(int(floor(g.x)), int(floor(g.z)))
	var inside := gc.x >= 0 and gc.y >= 0 and gc.x < cfg.grid.x and gc.y < cfg.grid.y
	return {"hit": false, "pos": Vector3i(gc.x, gc.y, 0), "col": gc, "above": Vector3i(gc.x, gc.y, 0), "face": Vector3i(0, 0, 1), "adjacent": Vector3i(gc.x, gc.y, 0), "in_grid": inside}


# ------------------------------------------------------------------ 상태 반영
func _on_state_replaced() -> void:
	cfg.reload()
	mesher.setup(cfg, atlas)
	_last_power = int(Game.state.power_level)
	_wave_r = 1000.0
	_prev_kinds.clear()
	for p in Game.state.cells:
		_prev_kinds[p] = str(Game.state.cells[p].get("kind", ""))
	mesher.prepare(Game.state)
	target = _default_target()
	rebuild_all()


func rebuild_all() -> void:
	var st: CityState = Game.state
	mesher.prepare(st)
	grid_tex.update_heights(mesher.col_h)
	_build_ground()
	var nz := cfg.grid.z + 2
	while _floor_nodes.size() < nz:
		var mi := MeshInstance3D.new()
		mi.material_override = _mat
		_floors_root.add_child(mi)
		_floor_nodes.append(mi)
		_floor_data.append({"lights": [], "emitters": []})
	for z in nz:
		_rebuild_floor(z)
	_dirty.clear()
	atlas.flush()
	_refresh_lights()
	_apply_cut()
	_overlay_dirty = true
	_apply_camera()


func _rebuild_floor(z: int) -> void:
	var out: Dictionary = mesher.build_floor(z)
	(_floor_nodes[z] as MeshInstance3D).mesh = out["mesh"]
	_floor_data[z] = {"lights": out["lights"], "emitters": out["emitters"]}


func _refresh_lights() -> void:
	var all: Array = []
	var em: Array = []
	for z in _floor_data.size():
		all.append_array(_floor_data[z]["lights"])
		em.append_array(_floor_data[z]["emitters"])
	grid_tex.update_lights(all, float(cfg.r("light.radius_scale", 0.62)))
	_all_emitters = em
	_push_emitters()
	_lights_dirty = false
	if people != null:
		var br: Array = []
		for e in em:
			var ty: String = str(e["type"])
			if ty.begins_with("walk_bridge:"):
				var d := int(ty.get_slice(":", 1))
				var dv := Vector3(CityMesher.NRM[d]) * 0.55
				br.append({"a": (e["pos"] as Vector3) - dv, "b": (e["pos"] as Vector3) + dv})
		people.call("set_bridges", br)
		people.call("rebuild", Game.state)


func _push_emitters() -> void:
	if fx == null:
		return
	var em: Array = []
	for z in _floor_data.size():
		if floor_cut < 0 or z < floor_cut:
			em.append_array(_floor_data[z]["emitters"])
	em.append_array(_cut_emitters)
	fx.call("set_emitters", em)


func _apply_cut() -> void:
	for z in _floor_nodes.size():
		(_floor_nodes[z] as MeshInstance3D).visible = floor_cut < 0 or z < floor_cut
	_cut_node.visible = floor_cut >= 0
	if floor_cut >= 0:
		var out: Dictionary = mesher.build_cut(floor_cut)
		_cut_node.mesh = out["mesh"]
		_cut_emitters = out["emitters"]
		atlas.flush()
	else:
		_cut_emitters = []
	_mat.set_shader_parameter("hm_clamp", 99.0 if floor_cut < 0 else float(floor_cut) + 0.3)
	_push_emitters()
	if people != null:
		people.call("set_cut", floor_cut)


func _on_event(ev: String, payload: Dictionary) -> void:
	match ev:
		"cell_changed":
			var pos: Vector3i = payload.get("pos", Vector3i.ZERO)
			for z in [pos.z - 1, pos.z, pos.z + 1]:
				if z >= 0 and z < cfg.grid.z + 2:
					_dirty[z] = true
			# 공사 끝: 비계가 떨어져 나가고 먼지가 인다
			var now_kind := str(Game.state.cells.get(pos, {}).get("kind", ""))
			if str(_prev_kinds.get(pos, "")) == "site" and now_kind != "site" and now_kind != "":
				_drop_scaffold(pos)
			if now_kind == "":
				_prev_kinds.erase(pos)
			else:
				_prev_kinds[pos] = now_kind
		"power_changed":
			var lv: int = int(payload.get("level", Game.state.power_level))
			if _last_power <= 0 and lv > 0:
				_start_power_wave()
			_last_power = lv
		"zone_changed":
			_overlay_dirty = true


func _drop_scaffold(pos: Vector3i) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesher.build_scaffold(pos)
	mi.material_override = _mat
	_world.add_child(mi)
	_drops.append({"node": mi, "t": 0.0})
	if fx != null:
		fx.call("add_dust", Vector3(pos.x + 0.5, pos.z * cfg.floor_h + 0.1, pos.y + 0.5), _t)


func _start_power_wave() -> void:
	_wave_r = 0.0
	_wave_center = Vector3(cfg.grid.x * 0.5, 0, cfg.grid.y * 0.5)
	for p in Game.state.cells:
		if str(Game.state.cells[p].get("type", "")) == "generator":
			_wave_center = Vector3(p.x + 0.5, p.z * cfg.floor_h, p.y + 0.5)
			break


# ------------------------------------------------------------------ 지면·부지
func _build_ground() -> void:
	var mb := MeshBuf.new()
	var st: CityState = Game.state
	var gw := cfg.grid.x
	var gh := cfg.grid.y
	var sd := int(st.rng_seed)
	var K := MeshBuf.K_GROUND
	for x in range(-9, gw + 9):
		for z in range(-9, gh + 9):
			var inside := x >= 0 and z >= 0 and x < gw and z < gh
			var ring := maxi(maxi(-x, x - (gw - 1)), maxi(-z, z - (gh - 1)))
			var h := ViewCfg.h3(x + 50, z + 50, sd)
			var name := "g_far"
			if inside:
				var k := h % 100
				name = "g_dirt_%d" % (h % 3)
				if k < 7:
					name = "g_puddle"
				elif k < 16:
					name = "g_weeds"
				elif k < 24:
					name = "g_slab"
				elif k < 34:
					name = "g_dirt_3"
			elif ring == 1:
				name = "g_dirt_%d" % (h % 4) if h % 5 != 0 else "g_weeds"
			elif ring == 2:
				name = "g_walk"
			elif ring == 3 or ring == 4:
				name = "g_asphalt_%d" % (h % 2)
				if ring == 4 and (x + z) % 2 == 0 and h % 9 != 0:
					name = "g_asphalt_0"
			elif ring == 5:
				name = "g_walk"
			var r := Rect2(atlas.rect(name))
			var y := 0.0
			mb.quad(Vector3(x, y, z), Vector3(x + 1, y, z), Vector3(x + 1, y, z + 1), Vector3(x, y, z + 1), Vector3.UP, r, Color.WHITE, 0.0, K)
	# 차선(길 가운데)
	var ln := Rect2(atlas.rect("white"))
	for i in range(-8, gw + 8, 2):
		for side in 4:
			var a := Vector3.ZERO
			var bq := Vector3.ZERO
			var off := 4.0
			match side:
				0:
					a = Vector3(i, 0.004, -off + 0.44)
					bq = Vector3(i + 1, 0.004, -off + 0.56)
				1:
					a = Vector3(i, 0.004, gh + off - 0.56)
					bq = Vector3(i + 1, 0.004, gh + off - 0.44)
				2:
					a = Vector3(-off + 0.44, 0.004, i)
					bq = Vector3(-off + 0.56, 0.004, i + 1)
				_:
					a = Vector3(gw + off - 0.56, 0.004, i)
					bq = Vector3(gw + off - 0.44, 0.004, i + 1)
			if a.x < -3.5 and (a.z < -3.5 or a.z > gh + 3.4):
				continue
			mb.quad(Vector3(a.x, a.y, a.z), Vector3(bq.x, a.y, a.z), Vector3(bq.x, a.y, bq.z), Vector3(a.x, a.y, bq.z), Vector3.UP, Rect2(ln.position, Vector2(2, 2)), Color("#e9e2c8"), 0.0, K)
	_build_lot_wall(mb, gw, gh, sd)
	_ground.mesh = mb.commit()


func _build_lot_wall(mb: MeshBuf, gw: int, gh: int, sd: int) -> void:
	# 무너진 담장: 부지 둘레 0.7칸 밖. 군데군데 빠지고 낮아진다. 대문은 +z(기본 시점의 앞 왼쪽) 가운데.
	var fh := cfg.floor_h
	var wr := Rect2(atlas.rect("lotwall"))
	var tr := Rect2(atlas.rect("lotwall_top"))
	var o := 0.7
	var th := 0.1875
	var gate_x := float(gw) * 0.5
	for side in 4:
		var n := (gw if side % 2 == 1 else gh) + 2
		for i in range(-1, n - 1):
			var h := ViewCfg.h3(side * 100 + i, 9, sd)
			var hh := fh * 0.56
			if h % 100 < 14:
				continue
			if h % 100 < 34:
				hh = fh * (0.2 + 0.1 * float(h % 3))
			var a := Vector3.ZERO
			var b := Vector3.ZERO
			var t0 := float(i)
			var t1 := float(i + 1)
			if i == -1:
				t0 = -o - th
			if i == n - 2:
				t1 = float(n - 2) + o + th
			match side:
				1:   # +z
					if absf(float(i) + 0.5 - gate_x) < 1.0:
						continue
					a = Vector3(t0, 0, gh + o)
					b = Vector3(t1, hh, gh + o + th)
				3:   # -z
					a = Vector3(t0, 0, -o - th)
					b = Vector3(t1, hh, -o)
				0:   # +x
					if i == -1 or i == n - 2:
						continue
					a = Vector3(gw + o, 0, t0)
					b = Vector3(gw + o + th, hh, t1)
				_:
					if i == -1 or i == n - 2:
						continue
					a = Vector3(-o - th, 0, t0)
					b = Vector3(-o, hh, t1)
			mb.box(a, b, wr, tr, fh, Color.WHITE, 31)
	# 대문 기둥 + 기운 문짝 + 표석
	var gz := float(gh) + o
	var stone_r := Rect2(atlas.rect("stone"))
	for gx in [gate_x - 1.0 - 0.25, gate_x + 1.0]:
		mb.box(Vector3(gx, 0, gz - 0.03), Vector3(gx + 0.25, fh * 0.95, gz + th + 0.03), stone_r, stone_r, fh, Color.WHITE, 31)
		mb.box(Vector3(gx - 0.04, fh * 0.95, gz - 0.07), Vector3(gx + 0.29, fh * 1.03, gz + th + 0.07), stone_r, stone_r, fh, Color("#e6e0ea"), 31)
	var rail := Rect2(atlas.rect("rail"))
	var gp0 := Vector3(gate_x - 1.0, 0, gz + 0.1)
	var gp1 := Vector3(gate_x - 0.25, 0, gz + 0.62)
	mb.quad2(gp0 + Vector3(0, fh * 0.7, 0), gp1 + Vector3(0, fh * 0.62, 0), gp1, gp0, Vector3(0.5, 0, 0.8).normalized(), Rect2(rail.position + Vector2(0, 6), Vector2(16, 10)), Color("#9a6f6a"))
	# 표석(寨城)
	var sx := gate_x + 1.55
	mb.box(Vector3(sx, 0, gz + 0.5), Vector3(sx + 0.5, 0.1, gz + 0.9), stone_r, stone_r, fh, Color("#c9c4d0"), 31)
	mb.box(Vector3(sx + 0.06, 0.1, gz + 0.58), Vector3(sx + 0.44, fh * 1.0, gz + 0.8), stone_r, stone_r, fh, Color.WHITE, 31)
	var tr2 := Rect2(atlas.sign_rect("寨城", true))
	if tr2.size.x > 0.0:
		var x0 := sx + 0.06
		var top := fh * 0.96
		var hgt := tr2.size.y / 16.0 * fh * 0.5
		mb.quad(Vector3(x0, top, gz + 0.804), Vector3(x0 + 0.375, top, gz + 0.804), Vector3(x0 + 0.375, top - hgt, gz + 0.804), Vector3(x0, top - hgt, gz + 0.804), Vector3(0, 0, 1), tr2, Color("#c2463c"))
	# 잔해 더미
	for i in 9:
		var h2 := ViewCfg.h3(i, 77, sd)
		var rx := -0.5 + float(h2 % 130) / 10.0
		var rz := -0.5 + float((h2 / 130) % 130) / 10.0
		if Game.state.cells.has(Vector3i(int(floor(rx)), int(floor(rz)), 0)) or Game.state.cells.has(Vector3i(int(floor(rx + 0.3)), int(floor(rz + 0.3)), 0)):
			continue
		var s := 0.18 + 0.06 * float(h2 % 3)
		mb.box(Vector3(rx, 0, rz), Vector3(rx + s, s * 0.5, rz + s), stone_r, stone_r, fh, Color("#d9cdbf") if h2 % 2 == 0 else Color("#d98b74"), 31)


# ------------------------------------------------------------------ 시간대
func tod() -> float:
	if _time_override >= 0.0:
		return fposmod(_time_override, 1.0)
	return Game.time_of_day()


func _eval_tod(t: float) -> Dictionary:
	var keys: Array = cfg.r("tod.keys", [])
	if keys.is_empty():
		return {}
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[keys.size() - 1]
	for i in keys.size() - 1:
		if t >= float(keys[i]["t"]) and t <= float(keys[i + 1]["t"]):
			a = keys[i]
			b = keys[i + 1]
			break
	var span := maxf(float(b["t"]) - float(a["t"]), 0.0001)
	var k := clampf((t - float(a["t"])) / span, 0.0, 1.0)
	var out := {}
	for key in a:
		if key == "t":
			continue
		var va: Variant = a[key]
		var vb: Variant = b.get(key, va)
		if va is String:
			out[key] = ViewCfg.col(va).lerp(ViewCfg.col(vb), k)
		else:
			out[key] = lerpf(float(va), float(vb), k)
	return out


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _sun_dir(t: float) -> Vector3:
	# 낮: 아침(왼쪽 벽) → 저녁(오른쪽 벽)으로 돈다. 밤: 달은 고정.
	var day_a := 0.235
	var day_b := 0.775
	if t > day_a and t < day_b:
		var k := (t - day_a) / (day_b - day_a)
		var az := deg_to_rad(lerpf(float(cfg.r("sun.azimuth_morning_deg", -58.0)), float(cfg.r("sun.azimuth_dusk_deg", 118.0)), k))
		var el := deg_to_rad(maxf(float(cfg.r("sun.min_elevation_deg", 14.0)), float(cfg.r("sun.noon_elevation_deg", 52.0)) * sin(k * PI)))
		return Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
	var maz := deg_to_rad(float(cfg.r("sun.moon_azimuth_deg", -35.0)))
	var mel := deg_to_rad(float(cfg.r("sun.moon_elevation_deg", 48.0)))
	return Vector3(sin(maz) * cos(mel), sin(mel), cos(maz) * cos(mel)).normalized()


func _update_uniforms() -> void:
	var t := tod()
	var v := _eval_tod(t)
	_tod_vals = v
	if v.is_empty():
		return
	var st: CityState = Game.state
	var sun := _sun_dir(t)
	_mat.set_shader_parameter("sun_dir", sun)
	_mat.set_shader_parameter("lit_top", _v3(v["lit_top"]))
	_mat.set_shader_parameter("lit_side", _v3(v["lit_side"]))
	_mat.set_shader_parameter("shade", _v3(v["shade"]))
	_mat.set_shader_parameter("haze_col", _v3(v["haze"]))
	_mat.set_shader_parameter("sky_col", _v3(v["sky_mid"]))
	_mat.set_shader_parameter("night", float(v["night"]))
	_mat.set_shader_parameter("win_level", float(v["win"]))
	_mat.set_shader_parameter("power", float(st.power_level))
	_mat.set_shader_parameter("time_s", _t)
	_mat.set_shader_parameter("floor_h", cfg.floor_h)
	_mat.set_shader_parameter("lot_center", Vector3(cfg.grid.x * 0.5, 0, cfg.grid.y * 0.5))
	_mat.set_shader_parameter("lot_half", float(cfg.grid.x) * 0.5)
	_mat.set_shader_parameter("lg_origin", grid_tex.origin())
	_mat.set_shader_parameter("lg_inv_size", grid_tex.inv_size())
	_mat.set_shader_parameter("hm_origin", Vector2(LightGrid.HM_ORG, LightGrid.HM_ORG))
	_mat.set_shader_parameter("hm_size", float(LightGrid.HM))
	_mat.set_shader_parameter("depth_haze", float(cfg.r("shade.depth_haze", 0.035)))
	_mat.set_shader_parameter("ao_strength", float(cfg.r("shade.ao_strength", 0.22)))
	_mat.set_shader_parameter("floor_grime", float(cfg.r("shade.floor_grime", 0.1)))
	_mat.set_shader_parameter("neon_gain", float(cfg.r("shade.neon_gain", 1.25)))
	_mat.set_shader_parameter("bands", float(cfg.r("shade.light_bands", 3.0)))
	_mat.set_shader_parameter("light_dither", float(cfg.r("shade.light_dither", 0.0)))
	_mat.set_shader_parameter("window_spill", float(cfg.r("light.window_spill", 0.55)))
	_mat.set_shader_parameter("warm_col", _v3(ViewCfg.col(cfg.r("light.window_warm", "#ffc46a"))))
	_mat.set_shader_parameter("tv_col", _v3(ViewCfg.col(cfg.r("light.window_tv", "#8fd0ff"))))
	_mat.set_shader_parameter("candle_col", _v3(ViewCfg.col(cfg.r("light.candle", "#ff9a4a"))))
	_mat.set_shader_parameter("wave_center", _wave_center)
	_mat.set_shader_parameter("wave_radius", _wave_r)
	# 비행기 그림자
	var pw := 0.0
	var pp := Vector2.ZERO
	if _plane_t >= 0.0:
		var k := _plane_t
		var dirv := Vector2(cos(_plane_dir), sin(_plane_dir))
		var c := Vector2(cfg.grid.x * 0.5, cfg.grid.y * 0.5)
		pp = c + dirv * lerpf(-16.0, 16.0, k)
		pw = (1.0 - float(v["night"]) * 0.7) * smoothstep(0.0, 0.08, k) * (1.0 - smoothstep(0.92, 1.0, k))
	_mat.set_shader_parameter("plane", Vector4(pp.x, pp.y, _plane_dir, pw))

	_sky_mat.set_shader_parameter("sky_top", _v3(v["sky_top"]))
	_sky_mat.set_shader_parameter("sky_mid", _v3(v["sky_mid"]))
	_sky_mat.set_shader_parameter("sky_low", _v3(v["sky_low"]))
	_sky_mat.set_shader_parameter("haze", _v3(v["haze"]))
	_sky_mat.set_shader_parameter("sil_far", _v3(v["sil_far"]))
	_sky_mat.set_shader_parameter("sil_near", _v3(v["sil_near"]))
	_sky_mat.set_shader_parameter("night", float(v["night"]))
	_sky_mat.set_shader_parameter("stars", float(v["stars"]))
	_sky_mat.set_shader_parameter("time_s", _t)
	# 해·달 원반(화면 공간)
	var vw := float(_iw + 2)
	var hz := float(_ih + 2) * 0.34
	var sunv := Vector3.ZERO
	var moonv := Vector3.ZERO
	if t > 0.235 and t < 0.775:
		var k2 := (t - 0.235) / 0.54
		sunv = Vector3(vw * (0.12 + 0.76 * k2), hz - 6.0 - sin(k2 * PI) * hz * 0.72, 7.0)
	else:
		var tn := fposmod(t - 0.775, 1.0) / 0.46
		moonv = Vector3(vw * (0.2 + 0.6 * tn), hz - 10.0 - sin(tn * PI) * hz * 0.6, 5.0)
	_sky_mat.set_shader_parameter("sun", sunv)
	_sky_mat.set_shader_parameter("moon", moonv)
	_sky_mat.set_shader_parameter("sun_col", _v3((v["lit_top"] as Color).lerp(Color(1, 0.95, 0.8), 0.5)))
	_outline_mat.set_shader_parameter("strength", float(cfg.r("outline.strength", 0.38)) if bool(cfg.r("outline.enabled", true)) else 0.0)
	_outline_mat.set_shader_parameter("threshold", float(cfg.r("outline.depth_threshold", 0.7)) / float(_zoom_levels[zoom_i]))
	_screen_mat.set_shader_parameter("quantize", bool(cfg.r("post.quantize", false)))
	_screen_mat.set_shader_parameter("levels", float(cfg.r("post.levels", 24.0)))


# ------------------------------------------------------------------ 매 프레임
func _process(delta: float) -> void:
	_t += delta
	var cam_dirty := false
	if _yaw_t < 1.0:
		_yaw_t = minf(_yaw_t + delta / 0.28, 1.0)
		var e := _yaw_t * _yaw_t * (3.0 - 2.0 * _yaw_t)
		_yaw = lerpf(_yaw_from, _yaw_to, e)
		if _yaw_t >= 1.0:
			_yaw = 45.0 + 90.0 * float(angle)
			_yaw_from = _yaw
			_yaw_to = _yaw
		cam_dirty = true
	# 첫 전기의 밤: 불이 발전기에서부터 물결처럼 켜진다
	if _wave_r < 999.0:
		_wave_r += delta * 26.0 / maxf(float(cfg.r("fx.power_wave_s", 4.5)), 0.1)
		if _wave_r > 30.0:
			_wave_r = 1000.0
	# 비행기
	var period := float(cfg.r("fx.plane_period_s", 55.0))
	if _plane_t < 0.0:
		_plane_next -= delta
		if _plane_next <= 0.0:
			_plane_t = 0.0
			_plane_dir = 0.35 + 0.5 * sin(_t * 0.37)
	else:
		_plane_t += delta / 3.2
		var sh := float(cfg.r("fx.plane_shake_px", 1.0))
		var mid := 1.0 - absf(_plane_t - 0.5) * 2.0
		var want := Vector2.ZERO
		if mid > 0.55 and sh > 0.0:
			want = Vector2(0, sh if int(_t * 14.0) % 2 == 0 else 0.0)
		if want != _shake:
			_shake = want
			cam_dirty = true
		if _plane_t >= 1.0:
			_plane_t = -1.0
			_plane_next = period * (0.7 + 0.6 * fposmod(_t * 0.618, 1.0))
			_shake = Vector2.ZERO
			cam_dirty = true
	# 떨어지는 비계
	if not _drops.is_empty():
		var keep: Array = []
		for dr in _drops:
			dr["t"] = float(dr["t"]) + delta
			var tt: float = dr["t"]
			var node: MeshInstance3D = dr["node"]
			node.position.y = -floor(tt * tt * 5.0 * 16.0) / 16.0
			if tt > 0.75:
				node.queue_free()
			else:
				keep.append(dr)
		_drops = keep
	# 바뀐 층만 다시 짓는다
	if not _dirty.is_empty():
		var st: CityState = Game.state
		mesher.prepare(st)
		grid_tex.update_heights(mesher.col_h)
		for z in _dirty.keys():
			_rebuild_floor(z)
		_dirty.clear()
		atlas.flush()
		_lights_dirty = true
		_lights_timer = 0.25
		if floor_cut >= 0:
			_apply_cut()
		_overlay_dirty = true
	if _lights_dirty:
		_lights_timer -= delta
		if _lights_timer <= 0.0:
			_refresh_lights()
	if cam_dirty:
		_apply_camera()
	_update_uniforms()
	if not _tod_vals.is_empty():
		var lit: Color = _tod_vals["lit_side"]
		var shd: Color = _tod_vals["shade"]
		var ambc := lit.lerp(shd, 0.35)
		var amb := Vector3(ambc.r, ambc.g, ambc.b)
		var night := float(_tod_vals["night"])
		var ng := float(cfg.r("shade.neon_gain", 1.25))
		var hr := tod() * 24.0
		var work := 1.0 if (hr > 7.0 and hr < 21.0) else 0.15
		if people != null:
			people.call("set_light", amb, night, ng, grid_tex.origin(), grid_tex.inv_size())
			people.call("step", delta, tod())
		if fx != null:
			var cut_y := 1000.0 if floor_cut < 0 else float(floor_cut) * cfg.floor_h + 0.6
			fx.call("set_frame", ppu(), maxf(floor(float(_zoom_levels[zoom_i])), 1.0), _t, night, work, amb, ng, grid_tex.origin(), grid_tex.inv_size(), cut_y)
			fx.call("prune", _t)
			var pl: Vector4 = _mat.get_shader_parameter("plane")
			fx.call("set_plane", _plane_t >= 0.0, Vector2(pl.x, pl.y), _plane_dir, _sun_dir(tod()), 13.0)


func _clamp_target() -> void:
	var m := 5.0
	target.x = clampf(target.x, -m, cfg.grid.x + m)
	target.z = clampf(target.z, -m, cfg.grid.y + m)
	target.y = clampf(target.y, -1.0, cfg.grid.z * cfg.floor_h + 1.0)


## 화면 픽셀(이 Control 좌표)만큼 끌었을 때 카메라를 옮긴다.
func pan_by(delta_screen: Vector2) -> void:
	var b := _cam_basis()
	var k := (float(_up) / _canvas_scale) * ppu()
	target += -b.x * (delta_screen.x / k) + b.y * (delta_screen.y / k)
	# 화면 위아래 이동은 지면을 따라 미끄러지는 대신 그대로 카메라 평면 이동으로 둔다
	_apply_camera()
