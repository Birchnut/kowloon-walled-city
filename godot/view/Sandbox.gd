extends Control
## Sandbox — 뷰만 따로 띄우는 씬. FakeCity(또는 state= 스냅샷)로 도시를 채운다.
## 사용자 인자: city=<preset> seed=<n> tod=<0..1> angle=<0..3> cut=<-1|n> zoom=<level> pan=<x,y>
##             speed=<배속> state=<CityState.to_dict() JSON 경로> hud=0 power=<0|1|2> wave=1 plane=1
## 키: Q/E 회전, R/F 층 컷, 휠·+/- 줌, T 시간 넘기기(Shift+T 실시간), 1-6 프리셋, P 첫 전기, L 비행기, Z 구획, H 도움말

@onready var view: Control = $CityView

var _preset := "day30_mixed"
var _seed := 1
var _tod := -1.0
var _label: Label
var _args: Dictionary = {}
var _frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
			if kv[0].begins_with("r:"):
				# 렌더 설정 덮어쓰기: r:outline.strength=0
				var val: Variant = kv[1]
				if kv[1] == "true" or kv[1] == "false":
					val = kv[1] == "true"
				elif kv[1].is_valid_float():
					val = float(kv[1])
				ViewCfg.overrides[kv[0].substr(2)] = val
	_preset = str(_args.get("city", _preset))
	_seed = int(_args.get("seed", 1))
	Game.autosave = false
	Game.speed = float(_args.get("speed", 0.0))
	Game.paused = Game.speed <= 0.0
	_load_city()
	if _args.has("tod"):
		_tod = float(_args["tod"])
		view.set_time_override(_tod)
	if _args.has("angle"):
		var n := int(_args["angle"])
		view.angle = posmod(n, 4)
		view._yaw = 45.0 + 90.0 * float(view.angle)
		view._yaw_from = view._yaw
		view._yaw_to = view._yaw
	if _args.has("zoom"):
		view.set_zoom(int(_args["zoom"]))
	if _args.has("cut"):
		view.set_floor_cut(int(_args["cut"]))
	if _args.has("pan"):
		var pv := str(_args["pan"]).split(",")
		if pv.size() >= 2:
			view.target = Vector3(float(pv[0]), float(pv[2]) if pv.size() > 2 else view.target.y, float(pv[1]))
	view._apply_camera()
	if str(_args.get("hud", "1")) != "0":
		_label = Label.new()
		_label.position = Vector2(8, 6)
		_label.add_theme_font_size_override("font_size", 11)
		_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		_label.add_theme_constant_override("outline_size", 3)
		add_child(_label)
	view.cell_tapped.connect(func(info: Dictionary) -> void: print("tap ", info))


func _load_city() -> void:
	var s: CityState
	if _args.has("state"):
		var path := str(_args["state"])
		var json := JSON.new()
		if FileAccess.file_exists(path) and json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
			s = CityState.new()
			s.from_dict(json.data)
		else:
			push_warning("state= 파일을 읽지 못함: %s" % path)
	if s == null:
		s = FakeCity.build(_preset, _seed, Vector3i(int(Data.cfg("grid.width", 12)), int(Data.cfg("grid.height", 12)), int(Data.cfg("grid.max_floors", 10))))
	if _args.has("power"):
		s.power_level = int(_args["power"])
	Game.replace_state(s)


func _process(_dt: float) -> void:
	_frame += 1
	if _args.has("wave") and _frame == int(_args.get("wave", 5)):
		# 첫 전기의 밤 연출 시험
		Game.state.power_level = 1
		Game.event.emit("power_changed", {"level": 1})
	if _args.has("sitedone") and _frame == int(_args["sitedone"]):
		# 공사 완료 연출 시험: 모든 공사 칸을 방으로 바꾸고 cell_changed를 쏜다
		for p in Game.state.cells.keys():
			var c: Dictionary = Game.state.cells[p]
			if str(c.get("kind", "")) == "site":
				var b: Dictionary = c.get("becomes", {})
				c["kind"] = str(b.get("kind", "housing"))
				c["type"] = str(b.get("type", "room"))
				c["material"] = str(b.get("material", c.get("material", "")))
				c.erase("progress")
				c.erase("becomes")
				Game.event.emit("cell_changed", {"pos": p})
	if _args.has("save_state") and _frame == 2:
		var f := FileAccess.open(str(_args["save_state"]), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(Game.state.to_dict()))
	if _args.has("perf") and _frame == 6:
		var verts := 0
		var meshes := 0
		for n in view._floor_nodes:
			var m: Mesh = (n as MeshInstance3D).mesh
			if m != null:
				verts += m.surface_get_array_len(0)
				meshes += 1
		var gm: Mesh = view._ground.mesh
		print("PERF cells=%d floor_meshes=%d city_verts=%d ground_verts=%d draw_calls=%d primitives=%d objects=%d people=%d" % [
			Game.state.cells.size(), meshes, verts, gm.surface_get_array_len(0) if gm else 0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			view.people.agents.size()])
	if _args.has("plane") and _frame == 2:
		view._plane_next = 0.0
	if _args.has("dump_atlas") and _frame == 3:
		view.atlas.img.save_png(str(_args["dump_atlas"]))
	if _label:
		var st: CityState = Game.state
		_label.text = "%s seed %d · %d일 %02d시 · 셀 %d · 각 %d 줌 ×%s 컷 %d\nQ/E 회전  R/F 층  휠 줌  T 시간  1-6 프리셋  P 전기  L 비행기" % [
			_preset, _seed, st.day, int(view.tod() * 24.0), st.cells.size(), view.angle, view._zoom_levels[view.zoom_i], view.floor_cut]


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed:
		return
	var k: InputEventKey = ev
	match k.keycode:
		KEY_Q:
			view.rotate_view(-1)
		KEY_E:
			view.rotate_view(1)
		KEY_R:
			view.set_floor_cut(mini(view.floor_cut + 1, 10))
		KEY_F:
			view.set_floor_cut(maxi(view.floor_cut - 1, -1))
		KEY_EQUAL, KEY_KP_ADD:
			view.zoom_step(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			view.zoom_step(-1)
		KEY_T:
			if k.shift_pressed:
				_tod = -1.0
			else:
				_tod = fposmod((view.tod() if _tod < 0.0 else _tod) + 1.0 / 48.0, 1.0)
			view.set_time_override(_tod)
		KEY_P:
			var lv := 0 if Game.state.power_level > 0 else 1
			Game.state.power_level = lv
			Game.event.emit("power_changed", {"level": lv})
		KEY_L:
			view._plane_next = 0.0
		KEY_Z:
			view.show_zones(not view._show_zones)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			if not k.echo:
				_preset = FakeCity.PRESETS[k.keycode - KEY_1]
				_args.erase("state")
				_load_city()
		KEY_N:
			if not k.echo:
				_seed += 1
				_load_city()
