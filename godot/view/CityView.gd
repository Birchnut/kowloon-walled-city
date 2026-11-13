extends Control
## CityView — 3D 픽셀 렌더러(뷰 층). 상태를 읽고 이벤트를 듣기만 한다. 규칙 0.
## API 계약: docs/ARCHITECTURE.md "CityView". 설명·결정 기록: docs/VIEW_NOTES.md.

signal cell_tapped(info: Dictionary)
signal cell_dragged(info: Dictionary)   # set_drag_paint(true)일 때 한 손가락 끌기 → pick_floor(작업 층) 결과
signal view_changed
signal cell_hovered(info: Dictionary)   # 마우스 아래 칸/건물이 바뀔 때(PC)

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
var _overlay_top: MeshInstance3D
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
var actors: CityActors = null
var fx: Node = null
var markers: CityMarkers = null
var _cell_img: Image
var _cell_tex: ImageTexture
var _lens_img: Image
var _lens_tex: ImageTexture
var _haz_img: Image                # 칸마다 (불: 0/0.5 타는 중/1 탄 뒤, 병, 쓰레기, 수리 중)
var _haz_tex: ImageTexture
var _cover_img: Image             # 칸마다 R = 덮인 정도(0..1) — 위에 쌓인 층 수 / cover.full_depth
var _cover_tex: ImageTexture
## 고요시간(규칙 쪽 사건 quiet_start / quiet_end): 화면이 살짝 어두워졌다 돌아온다. 실제 시간 기준(배속과 무관)
var _quiet := false
var _quiet_dim := 0.0
var lens := ""
var _sigs: Dictionary = {}          # bid -> 외형 서명(바뀌면 그 층만 다시 짓는다)

# 카메라 상태
var angle := 0                     # 0..3
var _yaw := 45.0                   # 도(애니메이션 값)
var _yaw_from := 45.0
var _yaw_to := 45.0
var _yaw_t := 1.0
var zoom_i := 0
var _zoom_levels: Array = [1, 1.5, 2, 3, 4]
var _zf := 1.0                     # 지금 확대율(애니메이션 값). 끝나면 _zoom_levels[zoom_i]와 같다
var _zanchor_on := false           # 휠 확대: 커서 아래 점을 붙잡는다
var _zanchor_rel := Vector2.ZERO   # 화면 중심에서 커서까지(내부 px)
var _zanchor_w := Vector3.ZERO     # 커서 아래의 카메라 평면 점
var _insets := Vector4.ZERO        # 왼·위·오른·아래로 UI가 가린 픽셀(이 Control 좌표)
var _insets_cur := Vector4.ZERO
var input_enabled := true
var _focus_on := false
var _focus_to := Vector3.ZERO
var _hover: Dictionary = {}
var _hover_key := ""
var _hover_node: MeshInstance3D
var _mouse_pos := Vector2(-1, -1)
var _pan_btn := 0                  # 끌기 중인 버튼(가운데·오른쪽)
var _pan_moved := false
var _zone_cells: Array = []
var _zone_ok: Array = []
var _cov_covered: Array = []
var _cov_uncovered: Array = []
var _ghost_floors := 1
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
var _cut_slots: Array = []
var _slots_dirty := true
var _drops: Array = []
var _all_emitters: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	cfg.reload()
	if Game.state != null:
		cfg.fit_grid(Game.state)
	_zoom_levels = cfg.r("pixel.zoom_levels", [1, 1.5, 2, 3, 4])
	zoom_i = clampi(int(cfg.r("pixel.default_zoom", 1)), 0, _zoom_levels.size() - 1)
	_zf = float(_zoom_levels[zoom_i])
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
	_overlay_top = MeshInstance3D.new()
	_world.add_child(_overlay_top)
	var fxn := CityFx.new()
	fxn.setup(cfg, grid_tex.lg_tex)
	_world.add_child(fxn)
	fx = fxn
	var pn := CityPeople.new()
	pn.setup(cfg, self, mesher, grid_tex.lg_tex)
	_world.add_child(pn)
	people = pn
	var an := CityActors.new()
	an.setup(cfg, self, grid_tex.lg_tex)
	_world.add_child(an)
	actors = an
	markers = CityMarkers.new()
	markers.setup(cfg, self, mesher)
	_world.add_child(markers)
	_make_cell_tex()
	_hover_node = MeshInstance3D.new()
	_world.add_child(_hover_node)
	_haz_node = MeshInstance3D.new()
	_haz_node.material_override = _mat
	_world.add_child(_haz_node)

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
	# 실제 창 픽셀 기준 정수배 확대율을 정한다(PC: 높이 기준 — 720→×1, 1080→×2, 1440→×3, 2160→×4).
	var xf := get_viewport().get_screen_transform() * get_global_transform()
	_canvas_scale = maxf(xf.get_scale().x, 0.01)
	var real := size * _canvas_scale
	var th := float(cfg.r("pixel.target_height", 540))
	_up = maxi(1, int(round(real.y / th)))
	var minw := float(cfg.r("pixel.min_width", 480))
	while _up > 1 and real.x / float(_up) < minw:
		_up -= 1
	_iw = int(ceil(real.x / float(_up) / 2.0)) * 2
	_ih = int(ceil(real.y / float(_up) / 2.0)) * 2
	_zmul = maxf(1.0, float(_ih) / th) if bool(cfg.r("pixel.fill_small_windows", true)) else 1.0
	_vp.size = Vector2i(_iw + 2, _ih + 2)
	_apply_camera()


# ------------------------------------------------------------------ 카메라
func ppu() -> float:
	return cfg.ppu1 * _zf * _zmul


## 창 높이에 따른 확대 사다리 배율: 정수배로 나눈 내부 높이가 540보다 크면(720p ×1 = 720) 그만큼 올려
## 가장 먼 확대에서도 1080p처럼 도시가 화면을 채운다(720p ×1.33). 1080p·1440p·2160p는 1.
var _zmul := 1.0


## 지금 확대 단계의 배율(애니메이션 끝 값).
func zoom_factor() -> float:
	return float(_zoom_levels[zoom_i])


## 시설 안(인형의 집)과 일하는 사람이 보이는 확대인가 — 가장 가까운 두 단계.
func interior_zoom() -> bool:
	return zoom_i >= _zoom_levels.size() - int(cfg.r("pixel.interior_levels", 2))


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
	var cu := target.dot(b.y) * p + (float(cfg.r("pixel.center_y", 0.5)) - 0.5) * float(_ih)
	# UI 패널이 가린 만큼 중심을 옮겨, 남은 화면 가운데에 기준점이 오게
	var kk := _canvas_scale / float(_up)
	cr -= (_insets_cur.x - _insets_cur.z) * 0.5 * kk
	cu += (_insets_cur.y - _insets_cur.w) * 0.5 * kk
	var sx: float = floor(cr)
	var sy: float = floor(cu)
	_frac = Vector2(cr - sx, cu - sy)
	if not bool(cfg.r("pixel.subpixel_scroll", true)) or _yaw_t < 1.0 or not is_equal_approx(_zf, float(_zoom_levels[zoom_i])):
		_frac = Vector2.ZERO
	# 0.25px 치우침: 픽셀 중심이 텍셀 경계에 걸리지 않게(줌 ×1에서 짝수 텍셀만 고르게)
	# 픽셀 중심이 텍셀 경계에 걸리지 않게 0.1텍셀만큼 어긋나게 둔다(줌마다 텍셀/픽셀 비가 달라 치우침도 달라짐)
	var bias := clampf(0.5 - 0.05 * _zf, 0.05, 0.45)
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
		_sky_mat.set_shader_parameter("zoom", _zf)
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


## 확대 단계(0 = 도시 전체 … 4 = 시설 안). 부드럽게 바뀌고 끝나면 픽셀에 맞춘다.
func set_zoom(level: int) -> void:
	level = clampi(level, 0, _zoom_levels.size() - 1)
	if level == zoom_i:
		return
	zoom_i = level
	_on_zoom_level_changed()


## 화면 점(이 Control 좌표)을 붙잡고 확대한다 — 휠.
func zoom_at(screen_pos: Vector2, dir: int) -> void:
	var lv := clampi(zoom_i + (1 if dir > 0 else -1), 0, _zoom_levels.size() - 1)
	if lv == zoom_i:
		return
	var b := _cam_basis()
	var rel := _to_internal(screen_pos) - _view_center_px()
	_zanchor_rel = rel
	_zanchor_w = target + b.x * (rel.x / ppu()) - b.y * (rel.y / ppu())
	_zanchor_on = true
	zoom_i = lv
	_on_zoom_level_changed()


func _on_zoom_level_changed() -> void:
	_overlay_dirty = true
	_cells_dirty = true
	_hover_key = "~"
	if people != null and people.has_method("set_zoom_level"):
		people.call("set_zoom_level", zoom_i, interior_zoom())
	if not bool(cfg.r("pixel.smooth_zoom", true)):
		_zf = float(_zoom_levels[zoom_i])
		_zanchor_on = false
		_clamp_target()
		_apply_camera()


## 화면 가운데(UI가 가린 부분을 뺀 남은 영역의 가운데) — 내부 픽셀.
func _view_center_px() -> Vector2:
	var kk := _canvas_scale / float(_up)
	return Vector2(float(_iw + 2) * 0.5 + (_insets_cur.x - _insets_cur.z) * 0.5 * kk, float(_ih + 2) * 0.5 + (_insets_cur.y - _insets_cur.w) * 0.5 * kk)


## v3 호환: 아래만 가려짐.
func set_bottom_inset(px: float) -> void:
	set_insets(_insets.x, _insets.y, _insets.z, px)


## UI 패널이 가리는 픽셀(이 Control 좌표). 도시가 남은 영역 가운데로 미끄러진다.
func set_insets(left: float, top: float, right: float, bottom: float) -> void:
	_insets = Vector4(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0))


## 카메라를 그 칸으로(부드럽게). zoom ≥ 0이면 그 단계로. 칸이 위층에 묻혀 있으면 층 자르기를 그 층에 맞춘다.
func focus(pos: Vector3i, zoom: int = -1) -> void:
	_focus_to = Vector3(pos.x + 0.5, (float(pos.z) + 0.5) * cfg.floor_h, pos.y + 0.5)
	_focus_on = true
	_zanchor_on = false
	if zoom >= 0:
		set_zoom(zoom)
	var buried := false
	if Game.state != null:
		for z in range(pos.z + 1, cfg.grid.z + 1):
			if Game.state.cells.has(Vector3i(pos.x, pos.y, z)):
				buried = true
				break
	if buried:
		set_floor_cut(pos.z)
	elif floor_cut >= 0 and pos.z >= floor_cut:
		set_floor_cut(-1 if _grid_z < 0 else pos.z)


## 창이 떠 있을 때 UI가 끈다: 카메라 입력·호버·탭이 모두 멈춘다.
func set_input_enabled(on: bool) -> void:
	input_enabled = on
	if not on:
		_pan_btn = 0
		_mouse_down = false
		_set_hover({})


## 화면 점 → pick과 같은 모양 + 건물(bid, kind, origin, w, h, d). 호버 강조는 뷰가 매 프레임 마우스 위치로 한다.
func hover(screen_pos: Vector2) -> Dictionary:
	var info := pick(screen_pos)
	if Game.state == null:
		return info
	var c: Dictionary = Game.state.cells.get(info.get("pos", Vector3i(-1, -1, -1)), {}) if info.get("hit", false) else {}
	if not c.is_empty():
		info["bid"] = int(c.get("bid", -1))
		info["kind"] = str(c.get("kind", ""))
		var ext := mesher.extent_of(c, info["pos"])
		info["origin"] = ext["origin"]
		info["w"] = ext["w"]
		info["h"] = ext["h"]
		info["d"] = ext["d"]
	return info


## 주거 칠하기 미리보기: 바닥 하이라이트만(입체 상자 없음). ok[i] = 그 칸을 칠할 수 있는가.
func set_zone_preview(cells: Array, ok: Array = []) -> void:
	_zone_cells = []
	_zone_ok = []
	for i in cells.size():
		if cells[i] is Vector3i:
			_zone_cells.append(cells[i])
			_zone_ok.append(bool(ok[i]) if i < ok.size() else true)
	_overlay_dirty = true


## 범위 렌즈(coverage)의 칸: 닿는 칸(옅은 초록) / 쓰이는데 닿지 않는 칸(빨강). set_lens("coverage")와 함께.
func set_coverage(covered: Array, uncovered: Array) -> void:
	_cov_covered = covered.filter(func(v: Variant) -> bool: return v is Vector3i)
	_cov_uncovered = uncovered.filter(func(v: Variant) -> bool: return v is Vector3i)
	_cells_dirty = true
	_overlay_dirty = true


## 마우스 아래 주민 한 줄("굴러온 돌 · 통조림 사러 가는 중").
func who(screen_pos: Vector2) -> Dictionary:
	if people != null and people.has_method("who"):
		return people.call("who", screen_pos)
	return {"ok": false, "text": ""}


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
func show_ghost(cells: Variant, ok: Variant = true, supports: Variant = [], floors: int = 1) -> void:
	_ghost_floors = maxi(floors, 1)
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
	if style == "range":
		_cells_dirty = true


## 고스트와 칸 표시를 지운다(격자·렌즈는 각자의 함수로 끈다).
func clear_overlay() -> void:
	_ghost_cells = []
	_ghost_sup = []
	_ghost_floors = 1
	if _cell_sets.has("range"):
		_cells_dirty = true
	_cell_sets.clear()
	_zone_cells = []
	_zone_ok = []
	_overlay_dirty = true


## 렌즈: "" | "needs" | "tier" | "happiness". 주거를 건물 데이터 색으로 물들이고 나머지는 가라앉힌다.
func set_lens(name: String) -> void:
	if name not in ["", "needs", "tier", "happiness", "coverage"]:
		name = ""
	lens = name
	if markers != null:
		markers.show_warn = name == "needs"
	_cells_dirty = true
	_overlay_dirty = true


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
	var old_grid := cfg.grid
	cfg.reload()
	cfg.fit_grid(Game.state)
	if cfg.grid != old_grid:
		_regrid()
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


## 격자 크기가 바뀌면(12→16 등) 높이맵·빛 격자·셀 상태 텍스처를 새 크기로 다시 만든다.
func _regrid() -> void:
	grid_tex.setup(cfg)
	_mat.set_shader_parameter("heightmap", grid_tex.hm_tex)
	_mat.set_shader_parameter("lightgrid", grid_tex.lg_tex)
	if fx != null and fx.has_method("set_lightgrid"):
		fx.call("set_lightgrid", grid_tex.lg_tex)
	if people != null and people.has_method("set_lightgrid"):
		people.call("set_lightgrid", grid_tex.lg_tex)
	if actors != null:
		actors.set_lightgrid(grid_tex.lg_tex)
	_make_cell_tex()


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
		_floor_data.append({"lights": [], "emitters": [], "slots": []})
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
	_floor_data[z] = {"lights": out["lights"], "emitters": out["emitters"], "slots": out.get("slots", [])}
	_slots_dirty = true


func _refresh_lights() -> void:
	var all: Array = []
	var em: Array = []
	for z in _floor_data.size():
		all.append_array(_floor_data[z]["lights"])
		em.append_array(_floor_data[z]["emitters"])
	all.append_array(_haz_lights)
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


func _push_slots() -> void:
	_slots_dirty = false
	var all: Array = []
	for z in _floor_data.size():
		if floor_cut < 0 or z < floor_cut:
			all.append_array(_floor_data[z].get("slots", []))
	all.append_array(_cut_slots)
	actors.set_slots(all)


func _push_emitters() -> void:
	if fx == null:
		return
	var em: Array = []
	for z in _floor_data.size():
		if floor_cut < 0 or z < floor_cut:
			em.append_array(_floor_data[z]["emitters"])
	em.append_array(_cut_emitters)
	em.append_array(_haz_emitters)
	fx.call("set_emitters", em)


func _apply_cut() -> void:
	for z in _floor_nodes.size():
		(_floor_nodes[z] as MeshInstance3D).visible = floor_cut < 0 or z < floor_cut
	_cut_node.visible = floor_cut >= 0
	if floor_cut >= 0:
		var out: Dictionary = mesher.build_cut(floor_cut)
		_cut_node.mesh = out["mesh"]
		_cut_emitters = out["emitters"]
		_cut_slots = out.get("slots", [])
		atlas.flush()
	else:
		_cut_emitters = []
		_cut_slots = []
	_slots_dirty = true
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
		"quiet_start":
			debug_quiet(true)
		"quiet_end":
			debug_quiet(false)
		"expedition_done", "expedition_claimed":
			if people != null and people.has_method("expedition"):
				people.call("expedition", ev == "expedition_claimed")


var _cells_dirty := false


## 고요시간 켜기/끄기. 규칙 쪽 사건(quiet_start/quiet_end)이 부르고, 시험에서는 직접 부를 수 있다.
func debug_quiet(on: bool) -> void:
	_quiet = on
	if people != null:
		people.set("quiet", on)


func _update_quiet(delta: float) -> void:
	var target_dim := float(cfg.r("quiet.dim", 0.14)) if _quiet else 0.0
	if not is_equal_approx(_quiet_dim, target_dim):
		# 들어갈 때 약 1.5초, 나올 때 약 2.5초(실제 시간)
		var secs := float(cfg.r("quiet.fade_in_s", 1.5)) if _quiet else float(cfg.r("quiet.fade_out_s", 2.5))
		var full := maxf(float(cfg.r("quiet.dim", 0.14)), 0.001)
		_quiet_dim = move_toward(_quiet_dim, target_dim, delta / maxf(secs, 0.05) * full)
		if _screen_mat != null:
			_screen_mat.set_shader_parameter("dim", _quiet_dim)


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
	# 표석(구룡 — v4: 한자 없음)
	var sx := gate_x + 1.55
	mb.box(Vector3(sx, 0, gz + 0.5), Vector3(sx + 0.5, 0.1, gz + 0.9), stone_r, stone_r, fh, Color("#c9c4d0"), 31)
	mb.box(Vector3(sx + 0.06, 0.1, gz + 0.58), Vector3(sx + 0.44, fh * 1.0, gz + 0.8), stone_r, stone_r, fh, Color.WHITE, 31)
	var tr2 := Rect2(atlas.sign_rect("구룡", true))
	if tr2.size.x > 0.0:
		var x0 := sx + 0.06
		var top := fh * 0.96
		var hgt := tr2.size.y / 32.0
		var wd := tr2.size.x / 32.0
		mb.quad(Vector3(x0 + 0.19 - wd * 0.5, top, gz + 0.804), Vector3(x0 + 0.19 + wd * 0.5, top, gz + 0.804), Vector3(x0 + 0.19 + wd * 0.5, top - hgt, gz + 0.804), Vector3(x0 + 0.19 - wd * 0.5, top - hgt, gz + 0.804), Vector3(0, 0, 1), tr2, Color("#c2463c"))
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
	_mat.set_shader_parameter("lens_on", 1.0 if (lens != "" or _range_tint) else 0.0)
	_mat.set_shader_parameter("lens_dim", float(cfg.vis("lens.dim_other", 0.45)) * (0.4 if lens == "" else 1.0))
	_mat.set_shader_parameter("doll", 1.0 if (interior_zoom() and bool(cfg.r("interior.dollhouse", true))) else 0.0)
	_mat.set_shader_parameter("time_s", _t)
	_mat.set_shader_parameter("floor_h", cfg.floor_h)
	_mat.set_shader_parameter("lot_center", Vector3(cfg.grid.x * 0.5, 0, cfg.grid.y * 0.5))
	_mat.set_shader_parameter("lot_half", float(cfg.grid.x) * 0.5)
	_mat.set_shader_parameter("lg_origin", grid_tex.origin())
	_mat.set_shader_parameter("lg_inv_size", grid_tex.inv_size())
	_mat.set_shader_parameter("hm_origin", Vector2(LightGrid.HM_ORG, LightGrid.HM_ORG))
	_mat.set_shader_parameter("hm_size", float(grid_tex.HM))
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
	_outline_mat.set_shader_parameter("threshold", float(cfg.r("outline.depth_threshold", 0.7)) / _zf)
	_screen_mat.set_shader_parameter("quantize", bool(cfg.r("post.quantize", false)))
	_screen_mat.set_shader_parameter("levels", float(cfg.r("post.levels", 24.0)))


# ------------------------------------------------------------------ 매 프레임
var prof: Dictionary = {}
var prof_on := false


func _pt(key: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	if prof_on:
		prof[key] = float(prof.get(key, 0.0)) * 0.9 + float(t1 - t0) * 0.1
	return t1


func _process(delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_t += delta
	_update_quiet(delta)
	var cam_dirty := false
	if not _insets_cur.is_equal_approx(_insets):
		var nv := _insets_cur.lerp(_insets, minf(delta * 12.0, 1.0))
		for i in 4:
			nv[i] = move_toward(nv[i], _insets[i], 0.5)
		_insets_cur = nv
		cam_dirty = true
	# 확대 애니메이션(0.14초). 휠이면 커서 아래 점이 그 자리에 머문다
	var zt := float(_zoom_levels[zoom_i])
	if not is_equal_approx(_zf, zt):
		var k := 1.0 - exp(-delta / 0.05)
		_zf = lerpf(_zf, zt, k)
		if absf(_zf - zt) < 0.01 * zt:
			_zf = zt
			_overlay_dirty = true
			_hover_key = "~"
		if _zanchor_on:
			var b0 := _cam_basis()
			target = _zanchor_w - b0.x * (_zanchor_rel.x / ppu()) + b0.y * (_zanchor_rel.y / ppu())
		_clamp_target()
		cam_dirty = true
	elif _zanchor_on:
		_zanchor_on = false
	if _focus_on:
		target = target.lerp(_focus_to, minf(delta * 7.0, 1.0))
		if target.distance_to(_focus_to) < 0.01:
			target = _focus_to
			_focus_on = false
		_clamp_target()
		cam_dirty = true
	if _key_pan(delta):
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
		_update_hazards()
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
		markers.set_frame(ppu(), maxf(1.0, floor(_zf * 0.5)), _t)
	_p0 = _pt("pre", _p0)
	if cam_dirty:
		_apply_camera()
	_update_hover(cam_dirty)
	_update_uniforms()
	_p0 = _pt("cam_uniforms", _p0)
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
		_p0 = _pt("people", _p0)
		if actors != null:
			if _slots_dirty:
				_push_slots()
			actors.set_view_state(floor_cut, zoom_i, interior_zoom())
			var wc := ViewCfg.col(cfg.r("light.window_warm", "#ffc46a"))
			actors.set_light(amb, night, ng, grid_tex.origin(), grid_tex.inv_size(), Vector3(wc.r, wc.g, wc.b))
			actors.step(delta, tod() * 24.0)
		_p0 = _pt("actors", _p0)
		if fx != null:
			var cut_y := 1000.0 if floor_cut < 0 else float(floor_cut) * cfg.floor_h + 0.6
			fx.call("set_frame", ppu(), maxf(floor(_zf), 1.0), _t, night, work, amb, ng, grid_tex.origin(), grid_tex.inv_size(), cut_y)
			fx.call("prune", _t)
			var plv: Variant = _mat.get_shader_parameter("plane")
			var pl: Vector4 = plv if plv is Vector4 else Vector4.ZERO
			fx.call("set_plane", _plane_t >= 0.0, Vector2(pl.x, pl.y), _plane_dir, _sun_dir(tod()), 13.0)


func _clamp_target() -> void:
	var m := 5.0
	target.x = clampf(target.x, -m, cfg.grid.x + m)
	target.z = clampf(target.z, -m, cfg.grid.y + m)
	# 통합: 위로는 지금 가장 높은 층 조금 위까지만(빈 성채에서 끌다 보면 하늘만 보이게 됐다)
	target.y = clampf(target.y, -1.0, (float(maxi(mesher.top_z, 0)) + 2.0) * cfg.floor_h)


## 화면 픽셀(이 Control 좌표)만큼 끌었을 때 카메라를 옮긴다.
func pan_by(delta_screen: Vector2, cancel_focus: bool = true) -> void:
	if cancel_focus:
		_focus_on = false
	var b := _cam_basis()
	var k := (float(_up) / _canvas_scale) * ppu()
	target += -b.x * (delta_screen.x / k) + b.y * (delta_screen.y / k)
	# 화면 위아래 이동은 지면을 따라 미끄러지는 대신 그대로 카메라 평면 이동으로 둔다
	_clamp_target()     # 통합: 끌기에도 한계(전에는 확대 때만 걸어 두 손가락·끌기로 도시 밖 하늘까지 나갔다)
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
var _pinch_c0 := Vector2.ZERO     # 두 손가락을 댄 순간의 가운데
var _pinch_armed := false          # 시작 떨림을 넘긴 뒤에만 줌한다
var _pinch_last_t := -10.0         # 마지막 줌 단계 시각
const PINCH_STEP := 1.25           # 마지막 단계 때 거리의 1.25배(0.8배)마다 한 단계
const PINCH_MIN_DT := 0.15         # 단계 사이 최소 0.15초
const PINCH_DEAD_PX := 24.0        # 시작 떨림: 거리 변화가 이만큼 + 가운데 이동보다 커야 줌으로 본다
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
	if not input_enabled:
		return
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
				_pinch_c0 = ((k[0] as Vector2) + (k[1] as Vector2)) * 0.5
				_pinch_armed = false
		else:
			var seen := _touches.has(ev.index)
			_touches.erase(ev.index)
			if seen and _touches.is_empty() and not _dragging and _t - _press_t < 0.5:
				_emit_tap(ev.position, 1)
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
			pan_by(ev.relative * 0.5)
			var dist := (k2[0] as Vector2).distance_to(k2[1])
			if _pinch_d0 > 1.0:
				if not _pinch_armed:
					var cen := ((k2[0] as Vector2) + (k2[1] as Vector2)) * 0.5
					var dd := absf(dist - _pinch_d0)
					if dd > PINCH_DEAD_PX and dd > cen.distance_to(_pinch_c0) * 0.5:
						_pinch_armed = true
				if _pinch_armed and _t - _pinch_last_t >= PINCH_MIN_DT:
					if dist > _pinch_d0 * PINCH_STEP:
						zoom_step(1)
						_pinch_d0 = dist
						_pinch_last_t = _t
					elif dist < _pinch_d0 / PINCH_STEP:
						zoom_step(-1)
						_pinch_d0 = dist
						_pinch_last_t = _t
		accept_event()
	elif _t - _touch_mode_t > 0.6 and ev.device != InputEvent.DEVICE_ID_EMULATION:
		# PC 마우스: 왼쪽 = UI의 선택·배치(탭/칠하기), 가운데·오른쪽 끌기 = 이동, 오른쪽 짧게 = 탭(button 2), 휠 = 커서 쪽 확대
		if ev is InputEventMouseButton:
			_mouse_pos = ev.position
			match ev.button_index:
				MOUSE_BUTTON_LEFT:
					if ev.pressed:
						_mouse_down = true
						_press_pos = ev.position
						_press_t = _t
						_dragging = false
						if drag_paint:
							_paint_at(ev.position, true)
					else:
						if _mouse_down and not _dragging:
							_emit_tap(ev.position, 1)
						_mouse_down = false
					accept_event()
				MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
					if ev.pressed:
						_pan_btn = ev.button_index
						_pan_moved = false
						_press_pos = ev.position
					elif _pan_btn == ev.button_index:
						if not _pan_moved and ev.button_index == MOUSE_BUTTON_RIGHT:
							_emit_tap(ev.position, 2)
						_pan_btn = 0
					accept_event()
				MOUSE_BUTTON_WHEEL_UP:
					if ev.pressed:
						zoom_at(ev.position, 1)
					accept_event()
				MOUSE_BUTTON_WHEEL_DOWN:
					if ev.pressed:
						zoom_at(ev.position, -1)
					accept_event()
		elif ev is InputEventMouseMotion:
			_mouse_pos = ev.position
			if _pan_btn != 0:
				if not _pan_moved and ev.position.distance_to(_press_pos) > TAP_SLOP * 0.5:
					_pan_moved = true
				if _pan_moved:
					pan_by(ev.relative)
				accept_event()
			elif _mouse_down:
				if drag_paint:
					_paint_at(ev.position, false)
				elif not _dragging and ev.position.distance_to(_press_pos) > TAP_SLOP:
					_dragging = true
				accept_event()
		elif ev is InputEventMagnifyGesture:
			if ev.factor > 1.15:
				zoom_at(ev.position, 1)
			elif ev.factor < 0.87:
				zoom_at(ev.position, -1)
		elif ev is InputEventPanGesture:
			pan_by(-ev.delta * 8.0)


func _emit_tap(pos: Vector2, button: int) -> void:
	var info := hover(pos)
	info["button"] = button
	cell_tapped.emit(info)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse_pos = Vector2(-1, -1)


## 키보드: Q/E 회전, PageUp/PageDown·[ ] 층 자르기. 그 밖의 키는 UI 몫(소비하지 않는다).
func _unhandled_key_input(ev: InputEvent) -> void:
	if not input_enabled or not is_visible_in_tree():
		return
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	if _text_focus():
		return
	match k.physical_keycode:
		KEY_Q:
			if not k.echo:
				rotate_view(-1)
			get_viewport().set_input_as_handled()
		KEY_E:
			if not k.echo:
				rotate_view(1)
			get_viewport().set_input_as_handled()
		KEY_PAGEUP, KEY_BRACKETRIGHT:
			cut_step(1)
			get_viewport().set_input_as_handled()
		KEY_PAGEDOWN, KEY_BRACKETLEFT:
			cut_step(-1)
			get_viewport().set_input_as_handled()


## 층 자르기 한 단계: 전체(-1) ↓ 가장 높은 층 ↓ … ↓ 0층. 위로 올라가 꼭대기를 넘으면 전체.
func cut_step(dir: int) -> void:
	var top := maxi(get_max_floor() - 1, 0)
	var c := floor_cut
	if dir < 0:
		c = top if c < 0 else maxi(c - 1, 0)
	else:
		c = -1 if (c < 0 or c >= top) else c + 1
	if _grid_z >= 0:
		show_floor_grid(maxi(c, 0), true)
	else:
		set_floor_cut(c)


func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and (f is LineEdit or f is TextEdit)


## WASD·방향키 이동(누르는 동안). 화면 기준 초당 ~900px(창 크기와 상관없이 같은 느낌).
func _key_pan(delta: float) -> bool:
	if not input_enabled or not is_visible_in_tree() or _text_focus():
		return false
	if not bool(cfg.r("input.keyboard_pan", true)):
		return false
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if v == Vector2.ZERO:
		return false
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_META):
		return false
	var spd := float(cfg.r("input.key_pan_px", 900.0)) * (2.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	_focus_on = false
	pan_by(-v.normalized() * spd * delta / maxf(_canvas_scale, 0.01), false)
	return true


# ------------------------------------------------------------------ 호버
func _update_hover(cam_moved: bool) -> void:
	if not input_enabled or _mouse_pos.x < 0.0 or not Rect2(Vector2.ZERO, size).has_point(_mouse_pos) or _pan_btn != 0:
		_set_hover({})
		return
	if not cam_moved and _t - _hover_t < 0.05:
		return
	_hover_t = _t
	var info: Dictionary
	if drag_paint or _grid_z >= 0:
		info = pick_floor(_mouse_pos, work_floor())
		info["floor"] = true
	else:
		info = hover(_mouse_pos)
	_set_hover(info)


var _hover_t := -1.0


func _set_hover(info: Dictionary) -> void:
	var key := ""
	if not info.is_empty():
		if info.get("floor", false):
			key = "f%s" % str(info.get("pos"))
		elif info.get("hit", false):
			key = "b%d" % int(info.get("bid", -1)) if int(info.get("bid", -1)) >= 0 else "c%s" % str(info.get("pos"))
		elif info.get("in_grid", false):
			key = "g%s" % str(info.get("pos"))
	if key == _hover_key:
		return
	_hover_key = key
	_hover = info
	_rebuild_hover()
	if not info.is_empty():
		cell_hovered.emit(info)


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
	var tverts := PackedVector3Array()
	var tcols := PackedColorArray()
	var top_quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		for v in [a, b, c, a, c, d]:
			tverts.append(v)
			tcols.append(col)
	var top_flat := func(x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
		top_quad.call(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), col)
	var top_line := top_quad
	var gw := cfg.grid.x
	var gh := cfg.grid.y
	var unlocked := int(st.get("floors_unlocked")) if st.get("floors_unlocked") != null else cfg.grid.z
	# ── 층 격자(PC): 그 층에 지을 수 있는 칸만, 칸에 맞춘 옅은 선 ──
	# 받쳐진 칸(지상·아래가 찬 칸) = 밝은 선 + 옅은 칠, 골조를 세워야 하는 칸 = 더 옅은 선, 찬 칸·잠긴 층 = 없음
	if _grid_z >= 0:
		var z := _grid_z
		var y := float(z) * fh + 0.02
		var locked := z >= unlocked
		var c_edge := _ocol("grid_edge", "#fff6dcc0")
		var c_ok := Color(c_edge.r, c_edge.g, c_edge.b, 0.55)
		var c_frame := Color(c_edge.r, c_edge.g, c_edge.b, 0.28)
		var lw := 1.0
		if not locked:
			for x in gw:
				for yy in gh:
					var p := Vector3i(x, yy, z)
					if st.cells.has(p):
						continue
					var supported := z == 0 or mesher.solid.has(p - Vector3i(0, 0, 1))
					var col := c_ok if supported else c_frame
					if supported:
						flat.call(x + 0.04, yy + 0.04, x + 0.96, yy + 0.96, y, Color(c_edge.r, c_edge.g, c_edge.b, 0.07))
					# 칸 테두리: 겹치지 않게 아래·왼쪽 변은 이웃이 그리지 않을 때만
					var a0 := Vector3(x, y, yy)
					_line3(a0, a0 + Vector3(1, 0, 0), col, lw, add_quad)
					_line3(a0, a0 + Vector3(0, 0, 1), col, lw, add_quad)
					if x == gw - 1 or st.cells.has(p + Vector3i(1, 0, 0)):
						_line3(a0 + Vector3(1, 0, 0), a0 + Vector3(1, 0, 1), col, lw, add_quad)
					if yy == gh - 1 or st.cells.has(p + Vector3i(0, 1, 0)):
						_line3(a0 + Vector3(0, 0, 1), a0 + Vector3(1, 0, 1), col, lw, add_quad)
		# 부지 둘레(얇게) — 잠긴 층이면 회색
		var ec := _ocol("grid_locked", "#8a8aa860") if locked else Color(c_edge.r, c_edge.g, c_edge.b, 0.8)
		_line3(Vector3(0, y, 0), Vector3(gw, y, 0), ec, 1.5, add_quad)
		_line3(Vector3(0, y, gh), Vector3(gw, y, gh), ec, 1.5, add_quad)
		_line3(Vector3(0, y, 0), Vector3(0, y, gh), ec, 1.5, add_quad)
		_line3(Vector3(gw, y, 0), Vector3(gw, y, gh), ec, 1.5, add_quad)
	# ── 칸 표시(사각 범위·고르기·경고) ──
	for style in _cell_sets:
		var sc := _ocol(style, "#ffd84a90")
		var set_d: Dictionary = {}
		for p in _cell_sets[style]:
			set_d[p] = true
		if style == "select":
			_outline_set(set_d, Color(sc.r, sc.g, sc.b, 1.0), 2.0, top_line)
			continue
		for p in _cell_sets[style]:
			if floor_cut >= 0 and p.z > floor_cut:
				continue
			var y0: float = p.z * fh + 0.03
			if style == "range" and floor_cut < 0 and mesher.solid.has(p):
				continue   # 건물 속 칸은 렌즈 텍스처가 물들인다(범위 기둥이 건물 면에 보인다)
			var ins := 0.0 if style == "range" else 0.05
			flat.call(p.x + ins, p.y + ins, p.x + 1 - ins, p.y + 1 - ins, y0, Color(sc.r, sc.g, sc.b, sc.a * (0.55 if style == "range" else 1.0)))
		if style == "range":
			# 층마다 사각 테두리(칸 경계에 맞춤, 깊이 무시 → 건물 뒤에서도 범위 모양이 읽힌다)
			_perimeter_by_floor(set_d, Color(sc.r, sc.g, sc.b, 0.95), 1.5, top_line)
	# ── 주거 칠하기 미리보기: 바닥 하이라이트만 ──
	if not _zone_cells.is_empty():
		var zc_ok := _ocol("zone_ok", "#6dff9a70")
		var zc_bad := _ocol("zone_bad", "#ff5a4a70")
		for i in _zone_cells.size():
			var p2: Vector3i = _zone_cells[i]
			var okc: Color = zc_ok if bool(_zone_ok[i]) else zc_bad
			var y2: float = p2.z * fh + 0.025
			flat.call(p2.x + 0.04, p2.y + 0.04, p2.x + 0.96, p2.y + 0.96, y2, okc)
			var e2 := 0.07
			var bc := Color(okc.r, okc.g, okc.b, 0.95)
			top_flat.call(p2.x + 0.04, p2.y + 0.04, p2.x + 0.96, p2.y + 0.04 + e2, y2, bc)
			top_flat.call(p2.x + 0.04, p2.y + 0.96 - e2, p2.x + 0.96, p2.y + 0.96, y2, bc)
			top_flat.call(p2.x + 0.04, p2.y + 0.04 + e2, p2.x + 0.04 + e2, p2.y + 0.96 - e2, y2, bc)
			top_flat.call(p2.x + 0.96 - e2, p2.y + 0.04 + e2, p2.x + 0.96, p2.y + 0.96 - e2, y2, bc)
	# ── 고스트: 발자국 전체를 한 덩어리로(층 수만큼), 테두리는 깊이 무시 ──
	if not _ghost_cells.is_empty():
		var gc := _ocol("ghost_ok", "#5dff9a70") if _ghost_ok else _ocol("ghost_bad", "#ff5a4a70")
		var gset: Dictionary = {}
		for p in _ghost_cells:
			gset[p] = true
			for dz in range(1, _ghost_floors):
				gset[p + Vector3i(0, 0, dz)] = true
		for p in gset:
			var a1 := Vector3(p.x, p.z * fh, p.y)
			# 같은 덩어리 안쪽 면은 그리지 않는다
			_shell_faces(a1 + Vector3(0.02, 0.01, 0.02), a1 + Vector3(0.98, fh * 0.98, 0.98), gc, gset, p, add_quad)
		_outline_set(gset, Color(gc.r, gc.g, gc.b, 1.0), 1.5, top_line)
	if not _ghost_sup.is_empty():
		var sc2 := _ocol("ghost_support", "#fff2d8c0")
		for p in _ghost_sup:
			var a2 := Vector3(p.x, p.z * fh, p.y)
			for q in [Vector3(0.02, 0, 0.02), Vector3(0.9, 0, 0.02), Vector3(0.02, 0, 0.9), Vector3(0.9, 0, 0.9)]:
				shell.call(a2 + q, a2 + q + Vector3(0.08, fh, 0.08), sc2)
			shell.call(a2 + Vector3(0.0, fh - 0.08, 0.0), a2 + Vector3(1.0, fh, 0.08), sc2)
			shell.call(a2 + Vector3(0.0, fh - 0.08, 0.92), a2 + Vector3(1.0, fh, 1.0), sc2)
			shell.call(a2 + Vector3(0.0, fh - 0.08, 0.08), a2 + Vector3(0.08, fh, 0.92), sc2)
			shell.call(a2 + Vector3(0.92, fh - 0.08, 0.08), a2 + Vector3(1.0, fh, 0.92), sc2)
			# 대각 가새 한 줄(골조로 읽히게)
			_line3(a2 + Vector3(0.05, 0.02, 0.97), a2 + Vector3(0.95, fh - 0.06, 0.97), sc2, 1.2, top_line)
	# ── 새 층 열림: 평면 테두리가 빛나고, 가운데서 빛 고리가 퍼진다 ──
	if _cue_z >= 0:
		var k := clampf(_cue_t / 2.6, 0.0, 1.0)
		var r := k * 10.0
		var cy := float(_cue_z) * fh + 0.03
		var fade := 1.0 - k * k
		var cc := Color(1.0, 0.95, 0.6, 0.85 * fade)
		var e3 := 0.12
		flat.call(-e3, -e3, gw + e3, 0.0, cy, cc)
		flat.call(-e3, gh, gw + e3, gh + e3, cy, cc)
		flat.call(-e3, 0.0, 0.0, gh, cy, cc)
		flat.call(gw, 0.0, gw + e3, gh, cy, cc)
		for x in gw:
			for yy in gh:
				var dd := Vector2(x + 0.5 - gw * 0.5, yy + 0.5 - gh * 0.5).length()
				if absf(dd - r) < 1.0:
					flat.call(x + 0.06, yy + 0.06, x + 0.94, yy + 0.94, cy, Color(cc.r, cc.g, cc.b, 0.6 * fade))
				elif dd < r:
					flat.call(x + 0.06, yy + 0.06, x + 0.94, yy + 0.94, cy, Color(cc.r, cc.g, cc.b, 0.16 * fade))
	_overlay.mesh = _tri_mesh(verts, cols)
	_overlay_top.mesh = _tri_mesh(tverts, tcols)
	if _overlay.material_override == null:
		_overlay.material_override = _vc_material(false, 10)
		_overlay_top.material_override = _vc_material(true, 11)


static func _tri_mesh(verts: PackedVector3Array, cols: PackedColorArray) -> ArrayMesh:
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _vc_material(no_depth: bool, prio: int) -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.no_depth_test = no_depth
	sm.render_priority = prio
	return sm


## 상자의 면 중 같은 덩어리(set)와 맞닿지 않는 면만.
func _shell_faces(a0: Vector3, a1: Vector3, col: Color, set_d: Dictionary, p: Vector3i, add_quad: Callable) -> void:
	var side := Color(col.r * 0.82, col.g * 0.82, col.b * 0.82, col.a * 0.85)
	if not set_d.has(p + Vector3i(0, 0, 1)):
		add_quad.call(Vector3(a0.x, a1.y, a0.z), Vector3(a1.x, a1.y, a0.z), Vector3(a1.x, a1.y, a1.z), Vector3(a0.x, a1.y, a1.z), col)
	if not set_d.has(p + Vector3i(0, 1, 0)):
		add_quad.call(Vector3(a0.x, a1.y, a1.z), Vector3(a1.x, a1.y, a1.z), Vector3(a1.x, a0.y, a1.z), Vector3(a0.x, a0.y, a1.z), side)
	if not set_d.has(p + Vector3i(1, 0, 0)):
		add_quad.call(Vector3(a1.x, a1.y, a1.z), Vector3(a1.x, a1.y, a0.z), Vector3(a1.x, a0.y, a0.z), Vector3(a1.x, a0.y, a1.z), side)
	if not set_d.has(p + Vector3i(0, -1, 0)):
		add_quad.call(Vector3(a1.x, a1.y, a0.z), Vector3(a0.x, a1.y, a0.z), Vector3(a0.x, a0.y, a0.z), Vector3(a1.x, a0.y, a0.z), side)
	if not set_d.has(p + Vector3i(-1, 0, 0)):
		add_quad.call(Vector3(a0.x, a1.y, a0.z), Vector3(a0.x, a1.y, a1.z), Vector3(a0.x, a0.y, a1.z), Vector3(a0.x, a0.y, a0.z), side)


## 화면에 늘 같은 굵기로 보이는 3D 선(카메라를 향한 얇은 띠).
func _line3(a: Vector3, b: Vector3, col: Color, px_w: float, add_quad: Callable) -> void:
	var cb := _cam_basis()
	var d := b - a
	if d.length() < 1e-5:
		return
	var n := d.cross(cb.z).normalized() * (px_w * 0.5 / maxf(ppu(), 1.0))
	add_quad.call(a - n, b - n, b + n, a + n, col)


## 칸 묶음의 바깥 테두리(층마다 위·아래 모서리 + 볼록 모서리 세로선).
func _outline_set(set_d: Dictionary, col: Color, w: float, add_quad: Callable) -> void:
	var fh := cfg.floor_h
	for p in set_d:
		var base := Vector3(p.x, p.z * fh, p.y)
		var up_in: bool = set_d.has(p + Vector3i(0, 0, 1))
		var dn_in: bool = set_d.has(p + Vector3i(0, 0, -1))
		var corners := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
		var nb := [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(-1, 0, 0)]
		for i in 4:
			if set_d.has(p + nb[i]):
				continue
			var c0: Vector3 = base + corners[i]
			var c1: Vector3 = base + corners[(i + 1) % 4]
			if not dn_in:
				_line3(c0, c1, col, w, add_quad)
			if not up_in:
				_line3(c0 + Vector3(0, fh, 0), c1 + Vector3(0, fh, 0), col, w, add_quad)
			# 이 변의 끝 모서리가 볼록하면 세로선
			var nxt: Vector3i = nb[(i + 1) % 4]
			if not set_d.has(p + nxt):
				_line3(c1, c1 + Vector3(0, fh, 0), col, w, add_quad)


## 층마다 칸 묶음의 테두리(바닥 높이 평면).
func _perimeter_by_floor(set_d: Dictionary, col: Color, w: float, add_quad: Callable) -> void:
	var fh := cfg.floor_h
	var nb := [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(-1, 0, 0)]
	var corners := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
	for p in set_d:
		if floor_cut >= 0 and p.z > floor_cut:
			continue
		var base := Vector3(p.x, p.z * fh + 0.03, p.y)
		for i in 4:
			if set_d.has(p + nb[i]):
				continue
			_line3(base + corners[i], base + corners[(i + 1) % 4], col, w, add_quad)


## 호버 강조: 건물 전체(여러 칸·여러 층)의 테두리, 또는 작업 층의 바닥 칸.
func _rebuild_hover() -> void:
	if _hover.is_empty() or _hover_key == "":
		_hover_node.mesh = null
		return
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var add_quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		for v in [a, b, c, a, c, d]:
			verts.append(v)
			cols.append(col)
	var hc := _ocol("hover", "#fff6dcd0")
	var set_d: Dictionary = {}
	if _hover.get("floor", false) or not _hover.get("hit", false):
		var p: Vector3i = _hover.get("pos", Vector3i(-1, -1, 0))
		if not _hover.get("in_grid", _hover.get("ok", false)):
			_hover_node.mesh = null
			return
		var y := p.z * cfg.floor_h + 0.03
		add_quad.call(Vector3(p.x + 0.06, y, p.y + 0.06), Vector3(p.x + 0.94, y, p.y + 0.06), Vector3(p.x + 0.94, y, p.y + 0.94), Vector3(p.x + 0.06, y, p.y + 0.94), Color(hc.r, hc.g, hc.b, 0.22))
		set_d[Vector3i(p.x, p.y, p.z)] = true
		_perimeter_by_floor(set_d, hc, 1.5, add_quad)
	else:
		var o: Vector3i = _hover.get("origin", _hover.get("pos"))
		var w := int(_hover.get("w", 1))
		var h := int(_hover.get("h", 1))
		var d := int(_hover.get("d", 1))
		for x in w:
			for yy in h:
				for z in d:
					set_d[o + Vector3i(x, yy, z)] = true
		_outline_set(set_d, hc, 1.5, add_quad)
	_hover_node.mesh = _tri_mesh(verts, cols)
	if _hover_node.material_override == null:
		_hover_node.material_override = _vc_material(true, 12)


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
	_haz_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_haz_img.fill(Color(0, 0, 0, 0))
	_haz_tex = ImageTexture.create_from_image(_haz_img)
	_mat.set_shader_parameter("cellstate", _cell_tex)
	_mat.set_shader_parameter("lenstex", _lens_tex)
	_cover_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_cover_img.fill(Color(0, 0, 0, 0))
	_cover_tex = ImageTexture.create_from_image(_cover_img)
	_mat.set_shader_parameter("hazstate", _haz_tex)
	_mat.set_shader_parameter("coverstate", _cover_tex)
	_mat.set_shader_parameter("cover_dark", float(cfg.r("cover.max_dark", 0.3)))


## 칸마다 "위에 쌓인 층 수". 규칙 쪽이 covered_depth 질의를 내주면(render.json cover.source = "sim") 그것을 쓰고,
## 아니면 지금 있는 셀로 직접 센다. 바꿔 끼울 곳은 이 함수 하나다.
func _covered_depth(p: Vector3i, cols: Dictionary) -> int:
	if str(cfg.r("cover.source", "local")) == "sim":
		var q: Variant = Game.query("covered_depth", {"pos": p, "cell": p})
		if q is int or q is float:
			return int(q)
	var zs: Variant = cols.get(Vector2i(p.x, p.y), null)
	if zs == null:
		return 0
	var n := 0
	for z in zs:
		if int(z) > p.z:
			n += 1
	return n


func _cover_columns(st: CityState) -> Dictionary:
	var cols: Dictionary = {}
	for p in st.cells:
		if p is Vector3i:
			var k := Vector2i(p.x, p.y)
			if not cols.has(k):
				cols[k] = []
			(cols[k] as Array).append(p.z)
	return cols


## buildings → 칸마다 (불 켜진 비율, 전기, 가동, 점유) + 렌즈 색 + 재난 상태. 칸 수만큼만 돈다(가볍다).
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
	_haz_img.fill(Color(0, 0, 0, 0))
	_cover_img.fill(Color(0, 0, 0, 0))
	var cover_cols := _cover_columns(st)
	var cover_full := maxf(float(cfg.r("cover.full_depth", 4)), 1.0)
	var bs := _buildings()
	var lstr := float(cfg.vis("lens.strength", 0.62))
	var lens_mode := lens
	var range_set: Array = _cell_sets.get("range", []) if lens == "" else []
	var cov: Dictionary = {}
	if lens == "coverage":
		for p in _cov_covered:
			cov[p] = 1
		for p in _cov_uncovered:
			cov[p] = 2
	for p in st.cells:
		if not (p is Vector3i) or p.x < 0 or p.y < 0 or p.x >= gw or p.y >= gh or p.z < 0 or p.z >= nz:
			continue
		var c: Dictionary = st.cells[p]
		var kind := str(c.get("kind", ""))
		var b: Dictionary = bs.get(int(c.get("bid", -1)), {})
		var lit := 1.0
		var elec := 1.0 if mesher.electric(c) else 0.0
		var active := 1.0
		var burn := str(c.get("burn", b.get("burn", "")))
		if kind == "house":
			var cap := maxf(float(b.get("cap", 1)), 1.0)
			lit = clampf(float(b.get("residents", cap)) / cap, 0.0, 1.0)
		elif kind == "facility":
			active = 1.0 if bool(b.get("active", true)) else 0.0
			lit = active
		if burn == "burnt":
			lit = 0.0
			active = 0.0
		var ty: int = p.y + p.z * gh
		_cell_img.set_pixel(p.x, ty, Color(lit, elec, active, 1.0))
		var hz := Color(0, 0, 0, 0)
		hz.r = 0.5 if burn == "burning" else (1.0 if burn == "burnt" else 0.0)
		hz.g = 1.0 if bool(c.get("sick", b.get("sick", false))) else 0.0
		hz.b = clampf(float(c.get("trash", 0.0)), 0.0, 1.0)
		var rp: Variant = b.get("repair", null)
		hz.a = 1.0 if (rp is Dictionary and burn == "burnt" and bool((rp as Dictionary).get("active", true))) else 0.0
		_haz_img.set_pixel(p.x, ty, hz)
		var cd := _covered_depth(p, cover_cols)
		if cd > 0:
			_cover_img.set_pixel(p.x, ty, Color(clampf(float(cd) / cover_full, 0.0, 1.0), 0, 0, 1))
		if lens_mode == "coverage":
			var cv := int(cov.get(p, 0))
			if cv > 0:
				var cc := ViewCfg.col(cfg.vis("lens.cov_in" if cv == 1 else "lens.cov_out", "#6ad08a" if cv == 1 else "#ff4a3a"))
				_lens_img.set_pixel(p.x, ty, Color(cc.r, cc.g, cc.b, lstr * (0.6 if cv == 1 else 1.0)))
		elif lens_mode != "" and kind == "house":
			var lc := _lens_color(c, b)
			var a := lstr
			if lens_mode == "needs" and str(b.get("need_state", "ok")) == "ok":
				a = lstr * 0.55   # 괜찮은 집은 옅게 → 주의·부족이 튄다
			_lens_img.set_pixel(p.x, ty, Color(lc.r, lc.g, lc.b, a))
	# 범위 표시가 켜져 있으면(렌즈 없음) 범위 안 건물 칸을 노랗게 물들인다
	var rc := ViewCfg.col(cfg.vis("overlay.range", "#ffd84a90"))
	for p in range_set:
		if p is Vector3i and p.x >= 0 and p.y >= 0 and p.x < gw and p.y < gh and p.z >= 0 and p.z < nz and st.cells.has(p):
			_lens_img.set_pixel(p.x, p.y + p.z * gh, Color(rc.r, rc.g, rc.b, 0.5))
	_range_tint = not range_set.is_empty()
	_cell_tex.update(_cell_img)
	_lens_tex.update(_lens_img)
	_haz_tex.update(_haz_img)
	_cover_tex.update(_cover_img)


var _range_tint := false
var _haz_node: MeshInstance3D
var _haz_sig := ""
var _haz_emitters: Array = []
var _haz_lights: Array = []


## 재난 층(불·쓰레기·파리·수리 비계·양동이 줄). 상태가 바뀐 때만 다시 만든다(서명 비교).
func _update_hazards() -> void:
	var st: CityState = Game.state
	if st == null:
		return
	var burning: Array = []
	var repairs: Array = []
	var trash: Array = []
	var sig := PackedStringArray()
	for p in st.cells:
		var c: Dictionary = st.cells[p]
		var b: Dictionary = _buildings().get(int(c.get("bid", -1)), {})
		var burn := str(c.get("burn", b.get("burn", "")))
		if burn == "burning":
			burning.append(p)
			sig.append("f%s" % str(p))
		elif burn == "burnt" and b.get("repair", null) is Dictionary:
			repairs.append(p)
			sig.append("r%s" % str(p))
		var t := float(c.get("trash", 0.0))
		if t > 0.12:
			trash.append([p, t])
			sig.append("t%s%d" % [str(p), int(t * 4.0)])
	sig.sort()
	var s2 := ",".join(sig) + "|%d" % floor_cut
	if s2 == _haz_sig:
		return
	_haz_sig = s2
	var keep := mesher.mb
	mesher.mb = MeshBuf.new()
	_haz_emitters = []
	_haz_lights = []
	var fh := cfg.floor_h
	# 쓰레기 더미: 그 칸 옆의 디딜 곳(같은 층 빈 바닥) 또는 지붕 위
	for it in trash:
		var p: Vector3i = it[0]
		if floor_cut >= 0 and p.z > floor_cut:
			continue
		var t: float = it[1]
		var spot := Vector3(-1, -1, -1)
		for d in 4:
			var nb: Vector3i = p + CityMesher.DIR[d]
			if st.cells.has(nb) or mesher.voids.has(nb):
				continue
			if p.z == 0 or mesher.solid.has(nb - CityMesher.UPI):
				var hs := ViewCfg.h2(p.x * 7 + p.y, p.z + d)
				spot = Vector3(p.x + 0.5, p.z * fh, p.y + 0.5) + Vector3(CityMesher.NRM[d]) * 0.72 + Vector3(CityMesher.RGT[d]) * (float(hs % 5) * 0.1 - 0.2)
				break
		if spot.x < 0.0 and not st.cells.has(p + CityMesher.UPI) and not mesher.voids.has(p + CityMesher.UPI):
			spot = Vector3(p.x + 0.3, (p.z + 1) * fh, p.y + 0.6)
		if spot.x < 0.0:
			continue
		mesher.mb.owner = 0
		var sz := 0.12 + 0.2 * t
		var hs2 := ViewCfg.h2(p.x * 3 + p.y * 5, p.z)
		mesher.wbox(spot + Vector3(-sz, 0, -sz * 0.8), spot + Vector3(sz, sz * 0.7, sz * 0.8), "junk", "junk", Color(0.8, 0.78, 0.7), 31)
		mesher.cbox(spot + Vector3(-sz * 0.6, sz * 0.7, -sz * 0.4), spot + Vector3(sz * 0.3, sz * 1.1, sz * 0.5), Color("#3a3a46") if hs2 % 2 == 0 else Color("#5f7a4a"))
		if t > 0.5:
			mesher.cbox(spot + Vector3(sz * 0.4, 0, sz * 0.2), spot + Vector3(sz * 0.4 + 0.12, 0.1, sz * 0.2 + 0.1), Color("#c9b48a"))
			mesher.cbox(spot + Vector3(-sz - 0.1, 0, -0.05), spot + Vector3(-sz + 0.02, 0.07, 0.07), Color("#8fb5d0"))
		if t > 0.35:
			_haz_emitters.append({"pos": spot + Vector3(0, sz * 0.5, 0), "type": "flies"})
	# 수리 비계
	for p in repairs:
		if floor_cut >= 0 and p.z >= floor_cut:
			continue
		mesher.mb.owner = mesher.owner_of(p)
		mesher._scaffold_wrap(p, p.x * 31 + p.y * 7 + p.z)
		_haz_emitters.append({"pos": Vector3(p.x + 0.5, p.z * fh + 0.5, p.y + 0.5), "type": "site"})
	# 불: 드러난 면마다 불꽃 + 위로 검은 연기 + 주황 빛
	for p in burning:
		if floor_cut >= 0 and p.z > floor_cut:
			continue
		var base := Vector3(p.x + 0.5, p.z * fh, p.y + 0.5)
		for d in 4:
			if not mesher.solid.has(p + CityMesher.DIR[d]):
				_haz_emitters.append({"pos": base + Vector3(CityMesher.NRM[d]) * 0.42 + Vector3(0, 0.15, 0), "type": "fire"})
		if not mesher.solid.has(p + CityMesher.UPI):
			_haz_emitters.append({"pos": base + Vector3(0, fh * 0.95, 0), "type": "fire"})
			_haz_emitters.append({"pos": base + Vector3(0, fh, 0), "type": "soot"})
		else:
			_haz_emitters.append({"pos": base + Vector3(0.5, fh * 0.6, 0.5), "type": "soot"})
		_haz_lights.append({"pos": base + Vector3(0, fh * 0.6, 0), "color": Color("#ff6a20"), "r": 2.4, "warm": 0.0})
	mesher.mb.owner = 0
	_haz_node.mesh = mesher.mb.commit()
	mesher.mb = keep
	atlas.flush()
	if actors != null:
		actors.set_extra(_bucket_lines(burning))
	_lights_dirty = true
	_lights_timer = 0.0
	_push_emitters()


## 양동이 줄: 불난 건물마다 가장 가까운 소방 시설 문에서 불난 집 문까지 주민 길(BFS)을 따라 사람이 늘어서 물통을 건넨다.
## 길이 없거나 소방 시설이 없으면 불난 집 문 앞에서 이웃 몇이 양동이를 들고 선다.
func _bucket_lines(burning: Array) -> Array:
	var out: Array = []
	if burning.is_empty() or people == null:
		return out
	var st: CityState = Game.state
	people.rebuild(st)
	var station_doors: Array = []
	for bid in _buildings():
		var b: Dictionary = _buildings()[bid]
		if str(b.get("kind", "")) != "facility" or not bool(b.get("active", true)):
			continue
		var c: Dictionary = st.cells.get(b.get("pos", Vector3i(-9, -9, -9)), {})
		var lk := mesher.look_name(c) if not c.is_empty() else str(b.get("look", ""))
		if lk == "fire_bucket" or lk == "fire_station":
			station_doors.append_array(people.doors.get(int(bid), []))
	var done: Dictionary = {}
	var k := 0
	var fh := cfg.floor_h
	for p in burning:
		var bid := int(st.cells[p].get("bid", -1))
		if done.has(bid):
			continue
		done[bid] = true
		var goal: Array = people.doors.get(bid, [])
		if goal.is_empty():
			continue
		var path: Array = []
		for sd in station_doors:
			var pth: Array = people._path(sd, goal, 3000)
			if not pth.is_empty() and (path.is_empty() or pth.size() < path.size()):
				path = pth
		if path.size() < 2:
			var g0: Vector3i = goal[0]
			for i in 3:
				out.append({"bid": -100 - k, "i": i, "pos": Vector3(g0.x + 0.3 + 0.2 * float(i), g0.z * fh, g0.y + 0.3 + 0.15 * float(i % 2)), "dir": Vector3(0, 0, -1), "pose": "bucket", "role": "idle", "out": true, "z": g0.z, "t0": 1, "look": "fire", "tier": 1})
			k += 1
			continue
		var pts: Array = []
		for n in path:
			pts.append(Vector3(n.x + 0.5, n.z * fh, n.y + 0.5))
		var acc := 0.0
		var idx := 0
		for i in pts.size() - 1:
			var a0: Vector3 = pts[i]
			var a1: Vector3 = pts[i + 1]
			var seg := a0.distance_to(a1)
			var dv := (a1 - a0) / maxf(seg, 0.001)
			while acc <= seg and idx < 40:
				var pos := a0 + dv * acc + Vector3(-dv.z, 0, dv.x) * (0.08 if idx % 2 == 0 else -0.08)
				out.append({"bid": -100 - k, "i": idx, "pos": pos, "dir": dv if idx % 2 == 0 else -dv, "pose": "pass", "role": "idle", "out": true, "z": int(pos.y / fh + 0.1), "t0": 1, "look": "fire_bucket", "tier": 2})
				idx += 1
				acc += 0.45
			acc -= seg
		k += 1
	return out


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
