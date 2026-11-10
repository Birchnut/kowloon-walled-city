extends Control
## Sandbox — 뷰만 따로 띄우는 씬. FakeCity v3(또는 state= 스냅샷)로 도시를 채운다. 시뮬은 멈춰 둔다.
## 사용자 인자: city=<early|mid|late_wood|late_metal|late_concrete|late_mixed|matrix> seed=<n> tod=<0..1> angle=<0..3>
##             cut=<-1|n> zoom=<0..2> pan=<x,y[,높이]> lens=<needs|tier|happiness> grid=<z> state=<to_dict JSON 경로> hud=0
## 오버레이 시험: ghost=<x,y,z[;…]> ghostbad=1 sup=<x,y,z[;…]> range=<x,y,z,r> select=<x,y,z>
## 연출 시험: wave=<프레임>(첫 전기) unlock=<프레임>(floor_unlocked) upgrade=<프레임>(scaffold 집 하나 승급) plane=1
## 개발: apitest=1(모든 API 호출 PASS/FAIL) perf=1 save_state=<경로> dump_atlas=<경로> r:<render.json 경로>=<값>
## 키: Q/E 회전, R/F 층, 휠·+/- 줌, T 시간(Shift+T 실시간), 1-7 프리셋, N 다음 seed, P 전기, L 비행기, G 격자, V 렌즈 순환, D 칠하기

@onready var view: Control = $CityView

var _preset := "late_mixed"
var _seed := 1
var _tod := -1.0
var _label: Label
var _args: Dictionary = {}
var _frame := 0
var _lenses := ["", "needs", "tier", "happiness"]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
			if kv[0].begins_with("r:"):
				var val: Variant = kv[1]
				if kv[1] == "true" or kv[1] == "false":
					val = kv[1] == "true"
				elif kv[1].is_valid_float():
					val = float(kv[1])
				ViewCfg.overrides[kv[0].substr(2)] = val
	_preset = str(_args.get("city", _preset))
	_seed = int(_args.get("seed", 1))
	Game.autosave = false
	Game.speed = 0.0
	Game.paused = true
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
	if _args.has("grid"):
		view.show_floor_grid(int(_args["grid"]), true)
	if _args.has("lens"):
		view.set_lens(str(_args["lens"]))
	if _args.has("pan"):
		var pv := str(_args["pan"]).split(",")
		if pv.size() >= 2:
			view.target = Vector3(float(pv[0]), float(pv[2]) if pv.size() > 2 else view.target.y, float(pv[1]))
	_apply_overlay_args()
	if str(_args.get("markers", "1")) == "0":
		view.markers.visible = false
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
	view.cell_dragged.connect(func(info: Dictionary) -> void: print("drag ", info))


static func _v3list(s: String) -> Array:
	var out: Array = []
	for part in s.split(";", false):
		var a := part.split(",")
		if a.size() >= 3:
			out.append(Vector3i(int(a[0]), int(a[1]), int(a[2])))
	return out


func _apply_overlay_args() -> void:
	if _args.has("ghost"):
		view.show_ghost(_v3list(str(_args["ghost"])), not _args.has("ghostbad"), _v3list(str(_args.get("sup", ""))))
	if _args.has("range"):
		var a := str(_args["range"]).split(",")
		if a.size() >= 4:
			var c := Vector3i(int(a[0]), int(a[1]), int(a[2]))
			var r := int(a[3])
			var cells: Array = []
			for x in range(c.x - r, c.x + r + 1):
				for y in range(c.y - r, c.y + r + 1):
					if absi(x - c.x) + absi(y - c.y) <= r and x >= 0 and y >= 0 and x < 12 and y < 12:
						cells.append(Vector3i(x, y, c.z))
			view.show_cells(cells, "range")
	if _args.has("select"):
		view.show_cells(_v3list(str(_args["select"])), "select")


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
	Game.replace_state(s)


func _process(_dt: float) -> void:
	_frame += 1
	if _args.has("wave") and _frame == int(_args.get("wave", 5)):
		Game.event.emit("power_changed", {"on": true})
	if _args.has("unlock") and _frame == int(_args["unlock"]):
		var z := int(Game.state.floors_unlocked)
		Game.state.floors_unlocked = z + 1
		Game.event.emit("floor_unlocked", {"z": z})
	if _args.has("upgrade") and _frame == int(_args["upgrade"]):
		# 비계 친 집 하나를 한 단계 올린다(연출 시험)
		for p in Game.state.cells:
			var c: Dictionary = Game.state.cells[p]
			if bool(c.get("scaffold", false)):
				c["scaffold"] = false
				c["tier"] = mini(int(c.get("tier", 1)) + 1, 5)
				if str(c.get("material", "")) == "common":
					c["material"] = "wood"
				var b: Dictionary = Game.state.buildings.get(int(c["bid"]), {})
				b["tier"] = c["tier"]
				b["material"] = c["material"]
				Game.event.emit("house_upgraded", {"bid": int(c["bid"]), "tier": c["tier"], "material": c["material"]})
				print("UPGRADE ", p, " -> ", c["material"], " T", c["tier"])
				break
	if _args.has("save_state") and _frame == 2:
		var f := FileAccess.open(str(_args["save_state"]), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(Game.state.to_dict()))
	if _args.has("apitest") and _frame == 4:
		_apitest()
	if _args.has("perf") and _frame == 6:
		var verts := 0
		var meshes := 0
		for n in view._floor_nodes:
			var m: Mesh = (n as MeshInstance3D).mesh
			if m != null:
				verts += m.surface_get_array_len(0)
				meshes += 1
		var gm: Mesh = view._ground.mesh
		print("PERF cells=%d supports=%d floor_meshes=%d city_verts=%d ground_verts=%d draw_calls=%d primitives=%d objects=%d people=%d markers=%d" % [
			Game.state.cells.size(), Game.state.supports.size(), meshes, verts, gm.surface_get_array_len(0) if gm else 0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			view.people.agents.size(), view.markers.count()])
		var t0 := Time.get_ticks_usec()
		view.rebuild_all()
		var t1 := Time.get_ticks_usec()
		Game.event.emit("building_changed", {"bid": 1})
		view._process(0.0)
		var t2 := Time.get_ticks_usec()
		print("PERF rebuild_all_ms=%.1f building_changed_ms=%.2f" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	if _args.has("plane") and _frame == 2:
		view._plane_next = 0.0
	if _args.has("dump_atlas") and _frame == 3:
		view.atlas.img.save_png(str(_args["dump_atlas"]))
	if _label:
		var st: CityState = Game.state
		_label.text = "%s seed %d · %d일 %02d시 · 셀 %d 골조 %d · 각 %d 줌 ×%s 컷 %d %s\nQ/E 회전  R/F 층  휠 줌  T 시간  1-7 프리셋  G 격자  V 렌즈  D 칠하기" % [
			_preset, _seed, st.day, int(view.tod() * 24.0), st.cells.size(), st.supports.size(), view.angle, view._zoom_levels[view.zoom_i], view.floor_cut, view.lens]


## 모든 공개 API를 한 번씩 부르고 결과를 검사한다.
func _apitest() -> void:
	var cnt := {"ok": 0, "bad": 0}
	var check := func(name: String, cond: bool, extra: Variant = "") -> void:
		print(("PASS " if cond else "FAIL ") + name + " " + str(extra))
		cnt["ok" if cond else "bad"] += 1
	var c := view.size * 0.5
	var hit: Dictionary = view.pick(c)
	check.call("pick", hit.has("hit") and hit.has("pos"), hit)
	if hit.get("hit", false):
		var back: Vector2 = view.project(hit["pos"])
		check.call("project", back.distance_to(c) < view.size.x * 0.25, back)
	# pick_floor ↔ project_world 왕복: 칸 중심을 화면으로 보내고 다시 집으면 같은 칸
	var all_ok := true
	for z in [0, 2, 5]:
		for q in [Vector3i(3, 4, z), Vector3i(8, 9, z), Vector3i(0, 0, z), Vector3i(11, 11, z)]:
			var sp: Vector2 = view.project_world(Vector3(q.x + 0.5, q.z * view.cfg.floor_h, q.y + 0.5))
			var pf: Dictionary = view.pick_floor(sp, z)
			if pf["pos"] != q or not pf["ok"]:
				all_ok = false
				print("  pick_floor miss ", q, " -> ", pf)
	check.call("pick_floor roundtrip", all_ok)
	var off: Dictionary = view.pick_floor(Vector2(-500, -500), 0)
	check.call("pick_floor outside -> ok=false", not off["ok"], off)
	view.show_floor_grid(2, true)
	check.call("show_floor_grid on -> cut=2", view.floor_cut == 2 and view._grid_z == 2)
	view.show_floor_grid(2, false)
	check.call("show_floor_grid off -> cut restored", view.floor_cut == -1 and view._grid_z == -1, view.floor_cut)
	view.show_ghost([Vector3i(1, 1, 3), Vector3i(2, 1, 3)], true, [Vector3i(1, 1, 2)])
	check.call("show_ghost", view._ghost_cells.size() == 2 and view._ghost_sup.size() == 1)
	view.show_ghost(Vector3i(4, 4, 0), "stall", false)
	check.call("show_ghost (v2 signature)", view._ghost_cells.size() == 1 and not view._ghost_ok)
	for st in ["range", "valid", "select", "warn"]:
		view.show_cells([Vector3i(5, 5, 0), Vector3i(6, 5, 0)], st)
	check.call("show_cells x4", view._cell_sets.size() == 4)
	view._rebuild_overlay()
	check.call("overlay mesh built", view._overlay.mesh != null)
	view.clear_overlay()
	view._rebuild_overlay()
	check.call("clear_overlay", view._ghost_cells.is_empty() and view._cell_sets.is_empty() and view._overlay.mesh == null)
	for ln in ["needs", "tier", "happiness", "bogus", ""]:
		view.set_lens(ln)
		view._update_cell_tex()
	check.call("set_lens (bogus -> off)", view.lens == "")
	var got: Array = []
	view.cell_dragged.connect(func(info: Dictionary) -> void: got.append(info))
	view.set_drag_paint(true)
	var p0: Vector2 = view.project_world(Vector3(3.5, 0, 3.5))
	var p1: Vector2 = view.project_world(Vector3(6.5, 0, 3.5))
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = p0
	view._gui_input(ev)
	for i in 6:
		var dv := InputEventScreenDrag.new()
		dv.index = 0
		dv.position = p0.lerp(p1, float(i + 1) / 6.0)
		dv.relative = (p1 - p0) / 6.0
		view._gui_input(dv)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = p1
	view._gui_input(up)
	view.set_drag_paint(false)
	var cells_got: Array = []
	for g in got:
		cells_got.append(g["pos"])
	check.call("set_drag_paint -> cell_dragged 3..6,3", got.size() >= 3 and cells_got.has(Vector3i(3, 3, 0)) and cells_got.has(Vector3i(6, 3, 0)), cells_got)
	view.set_floor_cut(1)
	view.set_floor_cut(-1)
	view.rotate_view(1)
	view.rotate_view(-1)
	view.zoom_step(1)
	view.set_zoom(0)
	view.set_bottom_inset(120)
	view.set_bottom_inset(0)
	view.set_time_override(0.5)
	check.call("get_max_floor", view.get_max_floor() >= 1, view.get_max_floor())
	for ev_name in ["cell_changed", "support_changed", "building_changed", "floor_unlocked", "house_upgraded", "power_changed", "expedition_done", "expedition_claimed", "bogus_event"]:
		Game.event.emit(ev_name, {"pos": Vector3i(0, 0, 0), "bid": 1, "z": 1, "on": true, "team": 1, "tier": 2, "material": "wood"})
	view._process(0.016)
	check.call("events handled (no crash)", true)
	print("APITEST %d passed, %d failed" % [cnt["ok"], cnt["bad"]])
	if _tod >= 0.0:
		view.set_time_override(_tod)


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
			Game.event.emit("power_changed", {"on": true})
		KEY_L:
			view._plane_next = 0.0
		KEY_G:
			view.show_floor_grid(maxi(view.floor_cut, 0), view._grid_z < 0)
		KEY_V:
			view.set_lens(_lenses[(_lenses.find(view.lens) + 1) % _lenses.size()])
		KEY_D:
			view.set_drag_paint(not view.drag_paint)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			if not k.echo:
				_preset = FakeCity.PRESETS[k.keycode - KEY_1]
				_args.erase("state")
				_load_city()
		KEY_N:
			if not k.echo:
				_seed += 1
				_load_city()
