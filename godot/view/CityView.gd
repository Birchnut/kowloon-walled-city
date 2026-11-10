extends Control
## CityView — 3D 픽셀 렌더러(뷰 층). 상태를 읽고 이벤트를 듣기만 한다. 규칙 0.
## API 계약: docs/ARCHITECTURE.md "CityView". 설명·결정 기록: docs/VIEW_NOTES.md.

signal cell_tapped(info: Dictionary)
signal cell_dragged(info: Dictionary)   # set_drag_paint(true)일 때 한 손가락 끌기 → pick_floor(작업 층) 결과
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
var markers: CityMarkers = null
var _cell_img: Image
var _cell_tex: ImageTexture
var _lens_img: Image
var _lens_tex: ImageTexture
var lens := ""
var _sigs: Dictionary = {}          # bid -> 외형 서명(바뀌면 그 층만 다시 짓는다)

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
var _inset_to := 0.0               # 아래에서 가려진 높이(이 Control 픽셀). UI의 하단 시트
var _inset := 0.0

# 연출
var _wave_r := 1000.0
var _wave_center := Vector3(6, 0, 6)
var _plane_t := -1.0
var _plane_next := 12.0
var _plane_dir := 0.6
var _last_power := false
var _grid_z := -1                  # show_floor_grid 층(-1 = 끔)
var _grid_prev_cut := -1
var _ghost_cells: Array = []
var _ghost_ok := true
var _ghost_sup: Array = []
var _cell_sets: Dictionary = {}    # style -> Array[Vector3i]
var _cue_z := -1                   # floor_unlocked 연출
var _cue_t := 0.0
var drag_paint := false
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
	markers = CityMarkers.new()
	markers.setup(cfg, self, mesher)
	_world.add_child(markers)
	_make_cell_tex()

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
	# 하단 시트가 가린 만큼의 절반을 위로 올려, 남은 화면 가운데에 도시가 오게
	cu -= _inset * 0.5 * _canvas_scale / float(_up)
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


## 화면 아래쪽이 px 만큼 가려졌다고 알린다(UI 하단 시트). 도시가 남은 영역 가운데로 미끄러진다.
func set_bottom_inset(px: float) -> void:
	_inset_to = maxf(px, 0.0)


func get_max_floor() -> int:
	return mesher.top_z + 1 if mesher != null else 0


func set_time_override(t: float) -> void:
	_time_override = t


## z층 평면 격자. 켜면 그 층을 작업 평면으로 보여 준다(위는 걷어 내고 아래층은 덩어리로). 끄면 이전 층 컷으로 돌아간다.
func show_floor_grid(z: int, on: bool) -> void:
	if on:
		if _grid_z < 0:
			_grid_prev_cut = floor_cut
		_grid_z = clampi(z, 0, cfg.grid.z - 1)
		set_floor_cut(_grid_z)
	elif _grid_z >= 0:
		_grid_z = -1
		set_floor_cut(_grid_prev_cut)
	_overlay_dirty = true


## 배치 미리보기: 칸들(초록/빨강 반투명 덩어리) + 새로 생길 골조(반투명 틀).
## 옛 호출 show_ghost(pos, id, ok)도 받아 준다.
func show_ghost(cells: Variant, ok: Variant = true, supports: Variant = []) -> void:
	if supports is bool:
		# v2: show_ghost(pos, facility_id, ok)
		ok = supports
		supports = []
	_ghost_cells = []
	if cells is Vector3i:
		_ghost_cells = [cells]
	elif cells is Array:
		for c in cells:
			if c is Vector3i:
				_ghost_cells.append(c)
	_ghost_ok = bool(ok) if ok is bool else true
	_ghost_sup = []
	for c2 in (supports if supports is Array else []):
		if c2 is Vector3i:
			_ghost_sup.append(c2)
	_overlay_dirty = true


## 칸 표시: style = "range"(서비스·시장 범위) | "valid" | "select" | "warn". 같은 style을 다시 부르면 바꿔 끼운다. 빈 배열 = 그 style 지우기.
func show_cells(cells: Array, style: String = "select") -> void:
	var list: Array = []
	for c in cells:
		if c is Vector3i:
			list.append(c)
	if list.is_empty():
		_cell_sets.erase(style)
	else:
		_cell_sets[style] = list
	_overlay_dirty = true


## 고스트와 칸 표시를 지운다(격자·렌즈는 각자의 함수로 끈다).
func clear_overlay() -> void:
	_ghost_cells = []
	_ghost_sup = []
	_cell_sets.clear()
	_overlay_dirty = true


## 렌즈: "" | "needs" | "tier" | "happiness". 주거를 건물 데이터 색으로 물들이고 나머지는 가라앉힌다.
func set_lens(name: String) -> void:
	if name not in ["", "needs", "tier", "happiness"]:
		name = ""
	lens = name
	if markers != null:
		markers.show_warn = name == "needs"
	_cells_dirty = true


## 켜면 한 손가락 끌기가 팬이 아니라 cell_dragged(pick_floor 결과)를 낸다. 두 손가락은 그대로 줌·팬.
func set_drag_paint(on: bool) -> void:
	drag_paint = on


## 화면 점 → z층 수평면 위의 칸(비어 있어도). {ok, pos, in_grid, world}
func pick_floor(screen_pos: Vector2, z: int) -> Dictionary:
	var ip := _to_internal(screen_pos)
	var b := _cam.global_transform.basis
	var p := ppu()
	var o := _cam.global_transform.origin + b.x * ((ip.x - float(_iw + 2) * 0.5) / p) + b.y * ((float(_ih + 2) * 0.5 - ip.y) / p)
	var d := -b.z
	if absf(d.y) < 1e-5:
		return {"ok": false, "pos": Vector3i(-1, -1, z), "in_grid": false}
	var y := float(z) * cfg.floor_h
	var t := (y - o.y) / d.y
	var w := o + d * t
	var pos := Vector3i(int(floor(w.x)), int(floor(w.z)), z)
	var inside := pos.x >= 0 and pos.y >= 0 and pos.x < cfg.grid.x and pos.y < cfg.grid.y
	return {"ok": inside, "pos": pos, "in_grid": inside, "world": w}


## 옛 이름(v2 UI 호환): 심을 자리 표시 = show_cells(cells, "valid"). 구획 표시는 v3에서 없어졌다.
func show_spots(cells: Array) -> void:
	show_cells(cells, "valid")


func show_zones(_on: bool) -> void:
	pass


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
	_wave_r = 1000.0
	_prev_kinds.clear()
	for p in Game.state.cells:
		_prev_kinds[p] = str(Game.state.cells[p].get("kind", ""))
	mesher.prepare(Game.state)
	_last_power = mesher.power_on
	_sigs.clear()
	for bid in _buildings():
		_sigs[bid] = _sig(bid)
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
	_update_cell_tex()
	_refresh_lights()
	_apply_cut()
	_cells_dirty = true
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
	_cells_dirty = true
	if people != null:
		people.call("set_cut", floor_cut)


func _on_event(ev: String, payload: Dictionary) -> void:
	match ev:
		"cell_changed", "support_changed":
			var pos: Variant = payload.get("pos", Vector3i.ZERO)
			if not (pos is Vector3i):
				return
			_mark_dirty(pos)
			var c: Dictionary = Game.state.cells.get(pos, {})
			# 2×2: 네 칸 모두 같은 층이지만 이웃 층의 벽 가림도 바뀐다
			if int(c.get("size", 1)) >= 2:
				_mark_dirty(pos + Vector3i(1, 1, 0))
			# 공사 끝: 비계가 떨어져 나가고 먼지가 인다
			var now_kind := str(c.get("kind", ""))
			if str(_prev_kinds.get(pos, "")) == "site" and now_kind != "site" and now_kind != "":
				_drop_scaffold(pos)
			if now_kind == "":
				_prev_kinds.erase(pos)
			else:
				_prev_kinds[pos] = now_kind
			var bid := int(c.get("bid", -1))
			if bid >= 0:
				_sigs[bid] = _sig(bid)
		"building_changed":
			_on_building_changed(int(payload.get("bid", -1)))
		"house_upgraded":
			var bid2 := int(payload.get("bid", -1))
			var b2: Dictionary = _buildings().get(bid2, {})
			var p2: Variant = b2.get("pos", null)
			if p2 is Vector3i:
				_mark_dirty(p2)
				_drop_scaffold(p2)
			_sigs[bid2] = _sig(bid2)
			_cells_dirty = true
		"floor_unlocked":
			_cue_z = int(payload.get("z", -1))
			_cue_t = 0.0
			_overlay_dirty = true
		"power_changed":
			var on := bool(payload.get("on", payload.get("level", 0) != 0))
			if on and not _last_power:
				_start_power_wave()
			_last_power = on
			mesher.power_on = CityMesher.city_power(Game.state, cfg) or on
			_cells_dirty = true
		"expedition_done", "expedition_claimed":
			if people != null and people.has_method("expedition"):
				people.call("expedition", ev == "expedition_claimed")


var _cells_dirty := false


func _mark_dirty(pos: Vector3i) -> void:
	for z in [pos.z - 1, pos.z, pos.z + 1]:
		if z >= 0 and z < cfg.grid.z + 2:
			_dirty[z] = true


func _buildings() -> Dictionary:
	var bs: Variant = Game.state.get("buildings") if Game.state != null else null
	return bs if bs is Dictionary else {}


## 외형에 영향을 주는 값만 묶은 서명. 같으면 메시는 그대로 두고 상태 텍스처·표시만 갱신.
func _sig(bid: int) -> String:
	var b: Dictionary = _buildings().get(bid, {})
	if b.is_empty():
		return ""
	var pos: Variant = b.get("pos", null)
	var c: Dictionary = Game.state.cells.get(pos, {}) if pos is Vector3i else {}
	if str(b.get("kind", "")) == "house":
		return "h%d|%s|%s|%d" % [int(c.get("tier", b.get("tier", 1))), str(c.get("material", "")), str(c.get("scaffold", false)), 1 if int(b.get("residents", 0)) > 0 else 0]
	return "f%s" % str(b.get("active", true))


func _on_building_changed(bid: int) -> void:
	var sg := _sig(bid)
	if sg != str(_sigs.get(bid, sg)):
		var b: Dictionary = _buildings().get(bid, {})
		var p: Variant = b.get("pos", null)
		if p is Vector3i:
			_mark_dirty(p)
	_sigs[bid] = sg
	_cells_dirty = true


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
		var c: Dictionary = Game.state.cells[p]
		if str(c.get("kind", "")) == "facility" and bool(cfg.recipe("facility", str(c.get("type", ""))).get("power", false)):
			_wave_center = Vector3(p.x + 0.5, p.z * cfg.floor_h, p.y + 0.5)
			break


# ------------------------------------------------------------------ 지면·부지
func _build_ground() -> void:
	var mb := MeshBuf.new()
	var st: CityState = Game.state
	var gw := cfg.grid.x
	var gh := cfg.grid.y
	var sd := int(st.get("rng_seed")) if st.get("rng_seed") != null else 0
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
	_mat.set_shader_parameter("grid_wh", Vector2(cfg.grid.x, cfg.grid.y))
	_mat.set_shader_parameter("lens_on", 1.0 if lens != "" else 0.0)
	_mat.set_shader_parameter("lens_dim", float(cfg.vis("lens.dim_other", 0.45)))
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
	if not is_equal_approx(_inset, _inset_to):
		_inset = move_toward(lerpf(_inset, _inset_to, minf(delta * 12.0, 1.0)), _inset_to, 0.5)
		cam_dirty = true
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
		_cells_dirty = true
	if _lights_dirty:
		_lights_timer -= delta
		if _lights_timer <= 0.0:
			_refresh_lights()
	if _cells_dirty:
		_cells_dirty = false
		_update_cell_tex()
		if markers != null:
			markers.refresh(Game.state)
	if _cue_z >= 0:
		_cue_t += delta
		_overlay_dirty = true
		if _cue_t > 2.6:
			_cue_z = -1
	if _overlay_dirty:
		_rebuild_overlay()
	if markers != null:
		markers.set_frame(ppu(), maxf(1.0, floor(float(_zoom_levels[zoom_i]) * 0.75)), _t)
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


# ------------------------------------------------------------------ 입력(팬·핀치줌·휠·탭)
var _touches: Dictionary = {}      # index -> 위치
var _press_pos := Vector2.ZERO
var _press_t := 0.0
var _dragging := false
var _mouse_down := false
var _touch_mode_t := -10.0
var _pinch_d0 := 0.0
var _pinch_a0 := 0.0
const TAP_SLOP := 10.0
var _paint_last := Vector3i(-99, -99, -99)


func work_floor() -> int:
	return _grid_z if _grid_z >= 0 else maxi(floor_cut, 0)


## 칠하기 모드: 칸이 바뀔 때만 낸다(같은 칸 위의 떨림은 무시).
func _paint_at(pos: Vector2, first: bool) -> void:
	var info := pick_floor(pos, work_floor())
	if first:
		_paint_last = Vector3i(-99, -99, -99)
		_dragging = true   # 칠하기 모드의 누름은 탭이 아니다
	var p: Vector3i = info["pos"]
	if p == _paint_last:
		return
	_paint_last = p
	info["first"] = first
	cell_dragged.emit(info)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		_touch_mode_t = _t
		if ev.pressed:
			_touches[ev.index] = ev.position
			if _touches.size() == 1:
				_press_pos = ev.position
				_press_t = _t
				_dragging = false
				if drag_paint:
					_paint_at(ev.position, true)
			elif _touches.size() == 2:
				_dragging = true
				var k: Array = _touches.values()
				_pinch_d0 = (k[0] as Vector2).distance_to(k[1])
				_pinch_a0 = ((k[1] as Vector2) - (k[0] as Vector2)).angle()
		else:
			_touches.erase(ev.index)
			if _touches.is_empty() and not _dragging and _t - _press_t < 0.5:
				cell_tapped.emit(pick(ev.position))
		accept_event()
	elif ev is InputEventScreenDrag:
		_touch_mode_t = _t
		_touches[ev.index] = ev.position
		if _touches.size() == 1:
			if drag_paint:
				_paint_at(ev.position, false)
			else:
				if not _dragging and ev.position.distance_to(_press_pos) > TAP_SLOP:
					_dragging = true
				if _dragging:
					pan_by(ev.relative)
		elif _touches.size() >= 2:
			var k2: Array = _touches.values()
			# 두 손가락: 가운데가 움직인 만큼 팬(칠하기 모드에서도)
			pan_by(ev.relative * 0.5)
			var dist := (k2[0] as Vector2).distance_to(k2[1])
			var ang := ((k2[1] as Vector2) - (k2[0] as Vector2)).angle()
			if _pinch_d0 > 1.0:
				if dist > _pinch_d0 * 1.35:
					zoom_step(1)
					_pinch_d0 = dist
				elif dist < _pinch_d0 * 0.72:
					zoom_step(-1)
					_pinch_d0 = dist
			var da := wrapf(ang - _pinch_a0, -PI, PI)
			if absf(da) > 0.6:
				rotate_view(1 if da < 0.0 else -1)
				_pinch_a0 = ang
		accept_event()
	elif _t - _touch_mode_t > 0.6:
		# 마우스(터치가 흉내 낸 마우스 이벤트는 위에서 이미 처리했으므로 무시)
		if ev is InputEventMouseButton:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.pressed:
					_mouse_down = true
					_press_pos = ev.position
					_press_t = _t
					_dragging = false
					if drag_paint:
						_paint_at(ev.position, true)
				else:
					if _mouse_down and not _dragging:
						cell_tapped.emit(pick(ev.position))
					_mouse_down = false
				accept_event()
			elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_step(1)
				accept_event()
			elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_step(-1)
				accept_event()
		elif ev is InputEventMouseMotion and _mouse_down:
			if drag_paint:
				_paint_at(ev.position, false)
			else:
				if not _dragging and ev.position.distance_to(_press_pos) > TAP_SLOP:
					_dragging = true
				if _dragging:
					pan_by(ev.relative)
			accept_event()
		elif ev is InputEventMagnifyGesture:
			if ev.factor > 1.15:
				zoom_step(1)
			elif ev.factor < 0.87:
				zoom_step(-1)


# ------------------------------------------------------------------ 오버레이(격자·고스트·칸 표시·층 열림)
func _ocol(key: String, def: String) -> Color:
	var v: Variant = cfg.vis("overlay." + key, def)
	return ViewCfg.col(v, Color(def))


func _rebuild_overlay() -> void:
	_overlay_dirty = false
	var st: CityState = Game.state
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var fh := cfg.floor_h
	var add_quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		for v in [a, b, c, a, c, d]:
			verts.append(v)
			cols.append(col)
	var flat := func(x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
		add_quad.call(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), col)
	var shell := func(a0: Vector3, a1: Vector3, col: Color) -> void:
		var top_c := col
		var side := Color(col.r * 0.82, col.g * 0.82, col.b * 0.82, col.a * 0.85)
		add_quad.call(Vector3(a0.x, a1.y, a0.z), Vector3(a1.x, a1.y, a0.z), Vector3(a1.x, a1.y, a1.z), Vector3(a0.x, a1.y, a1.z), top_c)
		add_quad.call(Vector3(a0.x, a1.y, a1.z), Vector3(a1.x, a1.y, a1.z), Vector3(a1.x, a0.y, a1.z), Vector3(a0.x, a0.y, a1.z), side)
		add_quad.call(Vector3(a1.x, a1.y, a1.z), Vector3(a1.x, a1.y, a0.z), Vector3(a1.x, a0.y, a0.z), Vector3(a1.x, a0.y, a1.z), side)
		add_quad.call(Vector3(a1.x, a1.y, a0.z), Vector3(a0.x, a1.y, a0.z), Vector3(a0.x, a0.y, a0.z), Vector3(a1.x, a0.y, a0.z), side)
		add_quad.call(Vector3(a0.x, a1.y, a0.z), Vector3(a0.x, a1.y, a1.z), Vector3(a0.x, a0.y, a1.z), Vector3(a0.x, a0.y, a0.z), side)
	var gw := cfg.grid.x
	var gh := cfg.grid.y
	var unlocked := int(st.get("floors_unlocked")) if st.get("floors_unlocked") != null else cfg.grid.z
	# ── 층 격자 ──
	if _grid_z >= 0:
		var z := _grid_z
		var y := float(z) * fh + 0.02
		var locked := z >= unlocked
		var c_free := _ocol("grid_free", "#fff6dc40")
		var c_used := _ocol("grid_used", "#ff7a5a50")
		var c_lock := _ocol("grid_locked", "#8a8aa830")
		var c_edge := _ocol("grid_edge", "#fff6dcc0")
		var g := 0.05
		for x in gw:
			for yy in gh:
				var p := Vector3i(x, yy, z)
				var col := c_lock if locked else (c_used if st.cells.has(p) else c_free)
				if st.cells.has(p) and str(st.cells[p].get("kind", "")) == "site":
					col = c_used
				flat.call(x + g, yy + g, x + 1 - g, yy + 1 - g, y, col)
		# 둘레(두꺼운 테) + 4칸마다 옅은 눈금
		var e := 0.07
		flat.call(-e, -e, gw + e, 0.0, y + 0.002, c_edge)
		flat.call(-e, gh, gw + e, gh + e, y + 0.002, c_edge)
		flat.call(-e, 0.0, 0.0, gh, y + 0.002, c_edge)
		flat.call(gw, 0.0, gw + e, gh, y + 0.002, c_edge)
		var c_mid := Color(c_edge.r, c_edge.g, c_edge.b, c_edge.a * 0.35)
		for i in range(4, gw, 4):
			flat.call(float(i) - 0.02, 0.0, float(i) + 0.02, gh, y + 0.003, c_mid)
		for i in range(4, gh, 4):
			flat.call(0.0, float(i) - 0.02, gw, float(i) + 0.02, y + 0.003, c_mid)
	# ── 칸 표시 ──
	for style in _cell_sets:
		var sc := _ocol(style, "#ffd84a90")
		for p in _cell_sets[style]:
			var a0 := Vector3(p.x, p.z * fh, p.y)
			var buried: bool = floor_cut >= 0 and p.z > floor_cut
			if buried:
				continue
			if mesher.solid.has(p) and not (floor_cut >= 0 and p.z == floor_cut):
				shell.call(a0 + Vector3(-0.03, 0.0, -0.03), a0 + Vector3(1.03, fh + 0.02, 1.03), sc)
			else:
				var ins := 0.04 if style != "range" else 0.0
				flat.call(p.x + ins, p.y + ins, p.x + 1 - ins, p.y + 1 - ins, p.z * fh + 0.035, sc)
				if style == "select":
					# 선택은 테두리도
					var e2 := 0.06
					var sy: float = p.z * fh + 0.04
					flat.call(p.x, p.y, p.x + 1, p.y + e2, sy, Color(sc.r, sc.g, sc.b, 1.0))
					flat.call(p.x, p.y + 1 - e2, p.x + 1, p.y + 1, sy, Color(sc.r, sc.g, sc.b, 1.0))
					flat.call(p.x, p.y, p.x + e2, p.y + 1, sy, Color(sc.r, sc.g, sc.b, 1.0))
					flat.call(p.x + 1 - e2, p.y, p.x + 1, p.y + 1, sy, Color(sc.r, sc.g, sc.b, 1.0))
	# ── 고스트 ──
	if not _ghost_cells.is_empty():
		var gc := _ocol("ghost_ok", "#5dff9a80") if _ghost_ok else _ocol("ghost_bad", "#ff5a4a80")
		for p in _ghost_cells:
			var a1 := Vector3(p.x, p.z * fh, p.y)
			shell.call(a1 + Vector3(0.04, 0.01, 0.04), a1 + Vector3(0.96, fh * 0.96, 0.96), gc)
	if not _ghost_sup.is_empty():
		var sc2 := _ocol("ghost_support", "#fff2d8b0")
		for p in _ghost_sup:
			var a2 := Vector3(p.x, p.z * fh, p.y)
			for q in [Vector3(0.02, 0, 0.02), Vector3(0.9, 0, 0.02), Vector3(0.02, 0, 0.9), Vector3(0.9, 0, 0.9)]:
				shell.call(a2 + q, a2 + q + Vector3(0.08, fh, 0.08), sc2)
			shell.call(a2 + Vector3(0.0, fh - 0.08, 0.0), a2 + Vector3(1.0, fh, 0.08), sc2)
			shell.call(a2 + Vector3(0.0, fh - 0.08, 0.92), a2 + Vector3(1.0, fh, 1.0), sc2)
			shell.call(a2 + Vector3(0.0, fh - 0.08, 0.08), a2 + Vector3(0.08, fh, 0.92), sc2)
			shell.call(a2 + Vector3(0.92, fh - 0.08, 0.08), a2 + Vector3(1.0, fh, 0.92), sc2)
	# ── 새 층 열림: 평면을 따라 퍼지는 빛 고리 ──
	if _cue_z >= 0:
		var k := clampf(_cue_t / 2.6, 0.0, 1.0)
		var r := k * 10.0
		var cy := float(_cue_z) * fh + 0.03
		var cc := Color(1.0, 0.95, 0.7, 0.55 * (1.0 - k))
		for x in gw:
			for yy in gh:
				var dd := Vector2(x + 0.5 - gw * 0.5, yy + 0.5 - gh * 0.5).length()
				if absf(dd - r) < 1.2:
					flat.call(x + 0.06, yy + 0.06, x + 0.94, yy + 0.94, cy, cc)
				elif dd < r:
					flat.call(x + 0.42, yy + 0.42, x + 0.58, yy + 0.58, cy, Color(cc.r, cc.g, cc.b, cc.a * 0.6))
	if verts.is_empty():
		_overlay.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_overlay.mesh = m
	if _overlay.material_override == null:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.vertex_color_use_as_albedo = true
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.no_depth_test = false
		sm.render_priority = 10
		_overlay.material_override = sm


# ------------------------------------------------------------------ 셀 상태·렌즈 텍스처
func _make_cell_tex() -> void:
	var w := cfg.grid.x
	var h := cfg.grid.y * (cfg.grid.z + 2)
	_cell_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_cell_img.fill(Color(1, 1, 1, 0))
	_cell_tex = ImageTexture.create_from_image(_cell_img)
	_lens_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_lens_img.fill(Color(0, 0, 0, 0))
	_lens_tex = ImageTexture.create_from_image(_lens_img)
	_mat.set_shader_parameter("cellstate", _cell_tex)
	_mat.set_shader_parameter("lenstex", _lens_tex)


## buildings → 칸마다 (불 켜진 비율, 전기, 가동, 점유) + 렌즈 색. 칸 수만큼만 돈다(가볍다).
func _update_cell_tex() -> void:
	if _cell_img == null:
		return
	var st: CityState = Game.state
	var gw := cfg.grid.x
	var gh := cfg.grid.y
	var nz := cfg.grid.z + 2
	if _cell_img.get_width() != gw or _cell_img.get_height() != gh * nz:
		_make_cell_tex()
	_cell_img.fill(Color(1, 1, 1, 0))
	_lens_img.fill(Color(0, 0, 0, 0))
	var bs := _buildings()
	var lstr := float(cfg.vis("lens.strength", 0.62))
	for p in st.cells:
		if not (p is Vector3i) or p.x < 0 or p.y < 0 or p.x >= gw or p.y >= gh or p.z < 0 or p.z >= nz:
			continue
		var c: Dictionary = st.cells[p]
		var kind := str(c.get("kind", ""))
		var b: Dictionary = bs.get(int(c.get("bid", -1)), {})
		var lit := 1.0
		var elec := 1.0 if mesher.electric(c) else 0.0
		var active := 1.0
		if kind == "house":
			var cap := maxf(float(b.get("cap", 1)), 1.0)
			lit = clampf(float(b.get("residents", cap)) / cap, 0.0, 1.0)
		elif kind == "facility":
			active = 1.0 if bool(b.get("active", true)) else 0.0
			lit = active
		var ty: int = p.y + p.z * gh
		_cell_img.set_pixel(p.x, ty, Color(lit, elec, active, 1.0))
		if lens != "" and kind == "house":
			var lc := _lens_color(c, b)
			_lens_img.set_pixel(p.x, ty, Color(lc.r, lc.g, lc.b, lstr))
	_cell_tex.update(_cell_img)
	_lens_tex.update(_lens_img)


func _lens_color(c: Dictionary, b: Dictionary) -> Color:
	match lens:
		"needs":
			var ns := str(b.get("need_state", "ok"))
			return ViewCfg.col(cfg.vis("lens." + ns, "#6a6486"), Color("#6a6486"))
		"tier":
			var t := clampi(int(c.get("tier", b.get("tier", 1))), 1, 5)
			return ViewCfg.col(cfg.vis("tier_colors.lens.%d" % t, "#cccccc"), Color("#cccccc"))
		"happiness":
			var h := clampf(float(b.get("happiness", 50.0)) / 100.0, 0.0, 1.0)
			var lo := ViewCfg.col(cfg.vis("lens.happy_lo", "#ff4a4a"))
			var mid := ViewCfg.col(cfg.vis("lens.happy_mid", "#ffd84a"))
			var hi := ViewCfg.col(cfg.vis("lens.happy_hi", "#5fd07a"))
			return lo.lerp(mid, h * 2.0) if h < 0.5 else mid.lerp(hi, (h - 0.5) * 2.0)
	return Color.WHITE
