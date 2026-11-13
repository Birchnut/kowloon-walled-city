extends Node
## 직접 줍기 — 한 판을 여는 장면(혼자서도 돈다): godot --path godot res://expedition/RunSandbox.tscn
##
## 통합용 진입점:
##   var run := preload("res://expedition/RunSandbox.tscn").instantiate()
##   run.dest = "scrap_yard"; run.standalone = false
##   run.run_finished.connect(func(result): ...)   # result = {dest, loot, outcome, finds, ...}
##   add_child(run)          # 시작 화면 → 줍기 → 결과 화면 → "도시로"를 누르면 신호
## run_result 명령은 결과 화면이 뜰 때 CityLink.result()가 이미 보낸다(신호는 화면을 닫으라는 뜻).
##
## 사용자 인자(-- 뒤): seed=N, auto=careless|average|careful(자동 플레이), start=run(시작 화면 건너뜀),
##   speed=2(시간 배속), nofog, mute, panel=start|result|pause(그 화면을 바로 띄움), script=이름(입력 대본)

signal run_finished(result: Dictionary)

const RunWorld = preload("res://expedition/RunWorld.gd")
const RunView = preload("res://expedition/RunView.gd")
const RunHud = preload("res://expedition/RunHud.gd")
const RunMenus = preload("res://expedition/RunMenus.gd")
const RunSfx = preload("res://expedition/RunSfx.gd")
const AutoPlayer = preload("res://expedition/AutoPlayer.gd")
const CityLink = preload("res://expedition/CityLink.gd")
const RunCfg = preload("res://expedition/RunCfg.gd")
const RunScript = preload("res://expedition/RunScript.gd")

const STEP := 1.0 / 60.0

@export var dest: String = "scrap_yard"
@export var standalone: bool = true

var world: RunWorld = null
var view: RunView
var hud: RunHud
var menus: RunMenus
var sfx: RunSfx = null
var container: SubViewportContainer
var subvp: SubViewport
var bot: AutoPlayer = null
var auto_profile := ""
var script_player: RefCounted = null
var mode := "start"          # start run pause result
var begin: Dictionary = {}
var acc := 0.0
var speed := 1.0
var scale_i := 4
var finish_delay := 0.0
var result_sent := false
var args: Dictionary = {}
var seed_arg := -1
var mouse_l := false
var mouse_r := false
var ticker_t := 0.0
var ticker_i := 0


func _ready() -> void:
	# 도시에서 띄울 때(standalone=false)는 도시를 몰던 인자(script=·speed=…)를 읽지 않는다 — run_ 로 시작하는 것만(run_auto=average 등).
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		var key: String = kv[0]
		if not standalone:
			if not key.begins_with("run_"):
				continue
			key = key.substr(4)
		args[key] = kv[1] if kv.size() == 2 else "1"
	seed_arg = int(args.get("seed", "-1"))
	auto_profile = str(args.get("auto", ""))
	speed = float(args.get("speed", "1"))
	var win := get_window()
	if standalone:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		if DisplayServer.get_name() != "headless" and win.size == Vector2i(540, 960):
			win.size = Vector2i(1920, 1080)
			win.move_to_center()
	RenderingServer.set_default_clear_color(Color(0.05, 0.04, 0.06))
	container = SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(container)
	subvp = SubViewport.new()
	subvp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	subvp.snap_2d_transforms_to_pixel = true
	subvp.snap_2d_vertices_to_pixel = true
	container.add_child(subvp)
	view = RunView.new()
	subvp.add_child(view)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = RunHud.new()
	layer.add_child(hud)
	var layer2 := CanvasLayer.new()
	layer2.layer = 6
	add_child(layer2)
	menus = RunMenus.new()
	menus.city_mode = not standalone
	layer2.add_child(menus)
	menus.action.connect(_on_action)
	if DisplayServer.get_name() != "headless":
		sfx = RunSfx.new()
		add_child(sfx)
		view.sfx = sfx
		if args.has("mute"):
			sfx.set_muted(true)
			hud.muted = true
	view.hud = hud
	view.fog = not args.has("nofog")
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	# 혼자 띄운 연습판은 도시(Game)를 건드리지 않는다 — 견본 재고로 돈다. 도시에서 띄우면 진짜 run_begin/run_result.
	CityLink.use_city = not standalone or args.has("city")
	hud.ticker_lines = CityLink.ticker().slice(0, 2)
	if args.has("dest"):
		dest = str(args["dest"])
	begin = CityLink.begin(dest, seed_arg)
	begin["dest"] = dest
	if args.get("start", "") == "run" or auto_profile != "" or args.has("script"):
		_start_run()
	else:
		_show_start()
	if args.has("png_dir"):
		RenderingServer.frame_post_draw.connect(_capture)
	if args.has("panel"):
		match str(args["panel"]):
			"pause":
				mode = "pause"
				menus.show_mode("pause")


func _on_resize() -> void:
	var vs := get_viewport().get_visible_rect().size
	scale_i = maxi(1, int(round(vs.y / 270.0)))
	container.stretch_shrink = scale_i
	container.set_deferred("size", vs)
	hud.set_deferred("size", vs)
	menus.set_deferred("size", vs)
	view.view_size = vs / scale_i


func _show_start() -> void:
	mode = "start"
	menus.show_mode("start", begin)


func _start_run() -> void:
	if not begin.get("ok", true):
		push_warning("run_begin 실패: %s" % begin.get("reason", ""))
	world = RunWorld.new()
	world.setup(dest, begin)
	world.wanted = CityLink.wanted()
	view.bind(world)
	hud.bind(world)
	view.aim_world = world.input.aim
	mode = "run"
	result_sent = false
	finish_delay = 0.0
	menus.show_mode("")
	bot = null
	if auto_profile != "":
		bot = AutoPlayer.new()
		bot.setup(auto_profile, int(begin.get("seed", 1)))
	script_player = null
	if args.has("script"):
		script_player = RunScript.new()
		script_player.setup(str(args["script"]), world)
	hud.on_event({"t": "room", "depth": 0, "name": world.rooms[world.cur_room]["name"]})


func _on_action(id: String) -> void:
	match id:
		"enter":
			_start_run()
		"reroll":
			begin["seed"] = int(begin.get("seed", 1)) + 1 + randi() % 997
			menus.show_mode("start", begin)
		"skin":
			var ids: Array = RunCfg.file("run_skins").get("items", {}).keys()
			var cur := ids.find(RunCfg.skin_for(dest))
			dest = str(ids[(cur + 1) % ids.size()])
			begin = CityLink.begin(dest, int(begin.get("seed", 1)))
			begin["dest"] = dest
			menus.show_mode("start", begin)
		"resume":
			mode = "run"
			menus.show_mode("")
		"restart":
			_start_run()
		"mute":
			_toggle_mute()
		"giveup":
			mode = "run"
			menus.show_mode("")
			world.give_up()
		"city":
			run_finished.emit(world.result)
			if standalone:
				begin["seed"] = int(begin.get("seed", 1)) + 1
				_show_start()
		"again":
			if not standalone:
				return      # 도시에서는 한 판마다 탐험 창에서 다시 보낸다(팀·던전 재고를 도시가 정한다)
			begin["seed"] = int(begin.get("seed", 1)) + 1
			_start_run()


func _toggle_mute() -> void:
	if sfx != null:
		sfx.set_muted(not sfx.muted)
		hud.muted = sfx.muted


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.physical_keycode
		if k == KEY_M:
			_toggle_mute()
			return
		match mode:
			"start":
				if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
					_on_action("enter")
				elif k == KEY_R:
					_on_action("reroll")
				elif k == KEY_D:
					_on_action("skin")
			"pause":
				if k == KEY_ESCAPE:
					_on_action("resume")
				elif k == KEY_R:
					_on_action("restart")
				elif k == KEY_Q:
					_on_action("giveup")
			"result":
				if k == KEY_ENTER or k == KEY_KP_ENTER:
					_on_action("city")
				elif k == KEY_R and standalone:
					_on_action("again")
			"run":
				if k == KEY_ESCAPE:
					if world.pack_open:
						world.input.pack_toggle = true
					else:
						mode = "pause"
						menus.show_mode("pause")
				elif k == KEY_TAB:
					world.input.pack_toggle = true
				elif k == KEY_SPACE:
					world.input.roll = true
				elif k >= KEY_1 and k <= KEY_6 and world.pack_open:
					if ev.shift_pressed:
						world.input.slot_one = k - KEY_1
					else:
						world.input.slot_action = k - KEY_1
				elif k == KEY_F2:
					if bot == null:
						bot = AutoPlayer.new()
						bot.setup("average", int(begin.get("seed", 1)))
						auto_profile = "average"
					else:
						bot = null
						auto_profile = ""
	elif ev is InputEventMouseButton and ev.pressed and mode == "run":
		if ev.button_index == MOUSE_BUTTON_LEFT:
			var sl := hud.slot_at(ev.position)
			if world.pack_open and sl >= 0:
				world.input.slot_action = sl
			elif not world.pack_open:
				world.input.attack = true
		elif ev.button_index == MOUSE_BUTTON_RIGHT and world.pack_open:
			var sl2 := hud.slot_at(ev.position)
			if sl2 >= 0:
				world.input.slot_one = sl2
		elif ev.button_index == MOUSE_BUTTON_RIGHT and not world.pack_open:
			world.input.throw_hold = true
	elif ev is InputEventMouseButton and not ev.pressed and mode == "run" and ev.button_index == MOUSE_BUTTON_RIGHT:
		if world.input.throw_hold and not world.pack_open:
			world.input.throw = true
		world.input.throw_hold = false


func _process(delta: float) -> void:
	hud.tick(delta)
	ticker_t += delta
	if ticker_t > 6.0:
		ticker_t = 0.0
		var lines: Array = CityLink.ticker()
		ticker_i = (ticker_i + 1) % lines.size()
		hud.ticker_lines = [lines[ticker_i], lines[(ticker_i + lines.size() - 1) % lines.size()]]
	if world == null:
		return
	if mode == "run":
		acc += minf(delta, 0.25) * speed
		while acc >= STEP:
			acc -= STEP
			_read_input()
			if bot != null:
				bot.fill(world.input, world, STEP)
			if script_player != null:
				script_player.fill(world.input, world, STEP)
			world.step(STEP)
			if world.finished:
				break
		if world.finished:
			finish_delay += delta
			if finish_delay > (0.6 if world.outcome != "down" else 0.2):
				_show_result()
	view.aim_world = world.input.aim
	view.tick(delta if mode == "run" else 0.0)


func _read_input() -> void:
	var inp := world.input
	if bot != null or script_player != null:
		return
	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		mv.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		mv.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		mv.y += 1
	inp.move = mv.normalized()
	inp.interact = Input.is_physical_key_pressed(KEY_E)
	var mp := get_viewport().get_mouse_position()
	inp.aim = view.world_from_screen(mp, get_viewport().get_visible_rect().size, scale_i)
	# 누르고 있으면 계속 휘두른다(버퍼가 받는다)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not world.pack_open and hud.slot_at(mp) < 0:
		inp.attack = true


var _frame := 0


var _shots_taken := 0
var _shot_cool := 0


## 화면 확인용: png_dir=<절대경로> png_every=N(기본 1) 또는 png_at=3,10,40 — 실제 창 크기로 저장한다.
## shot_when=조건 이면 조건이 맞는 프레임만 shot_N.png 로(shot_count=1, shot_gap=프레임 간격).
##   조건: tele:rat|dog|guard|rival, boss:<상태>, marks, search, wave, pack, result, junk, wire, alert, distract, time:초
func _capture() -> void:
	_frame += 1
	if args.has("shot_when"):
		_shot_cool -= 1
		if _shots_taken < int(args.get("shot_count", "1")) and _shot_cool <= 0 and _shot_cond(str(args["shot_when"])):
			_shots_taken += 1
			_shot_cool = int(args.get("shot_gap", "8"))
			get_viewport().get_texture().get_image().save_png(str(args["png_dir"]).path_join("shot_%d.png" % _shots_taken))
			print("[shot] ", args["shot_when"], " frame ", _frame)
		return
	var every := int(args.get("png_every", "1"))
	var at: PackedStringArray = str(args.get("png_at", "")).split(",", false)
	if not at.is_empty():
		if not (str(_frame) in at):
			return
	elif _frame % every != 0:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(str(args["png_dir"]).path_join("f%05d.png" % _frame))


func _shot_cond(c: String) -> bool:
	if c == "result":
		return mode == "result" and menus.t > 0.0
	if world == null or mode != "run":
		return false
	var kv := c.split(":")
	match kv[0]:
		"tele":
			for e in world.enemies:
				if not e.dead and e.kind == kv[1] and e.state == "tele" and e.st >= e.timer * 0.62 and e.pos.distance_to(world.player.pos) < 120:
					return true
		"boss":
			var b = world.boss
			return b != null and not b.dead and b.state == kv[1] and (b.st >= minf(0.5, b.timer * 0.6) if b.timer > 0 else b.st > 0.4)
		"marks":
			for m in world.marks:
				if m["t"] > m["dur"] * 0.6:
					return true
		"search":
			return not world.search_target.is_empty() and world.search_target["progress"] > 0.35
		"wave":
			return world.time - world.last_event_t > 0.4 and world.time - world.last_event_t < 1.5
		"pack":
			return world.pack_open
		"junk":
			for j in world.junks:
				if j["state"] == "warn" and j["t"] > 0.5:
					return true
		"wire":
			for wv in world.wires:
				if wv["state"] == "active" and (wv["box"] as Rect2).grow(40).has_point(world.player.pos):
					return true
		"alert":
			for e in world.enemies:
				if not e.dead and e.kind == "guard" and not e.aware and e.alert > 0.45:
					return true
		"time":
			return world.time >= float(kv[1])
		"bonk":
			return not view.stars.is_empty() and view.stars[0]["life"] < 0.75
		"hitspin":
			for e in world.enemies:
				if absf(e.spin_v) > 4.0:
					return true
		"nameplate":
			return hud.nameplate_t > 0.6 and hud.nameplate_t < 1.6
		"hush":
			return world.hushing and world.still_t > 2.0
		"flood":
			return world.floodlights and world.time - world.last_event_t > 1.0 and world.time - world.last_event_t < 2.0
		"distract":
			for e in world.enemies:
				if not e.dead and e.kind == "guard" and e.state == "investigate" and e.st > 0.4:
					return true
	return false


func _show_result() -> void:
	if mode == "result":
		return
	mode = "result"
	if not result_sent:
		result_sent = true
		CityLink.result(world.result)
	if sfx != null:
		sfx.loop_search(false)
	menus.show_mode("result", world.result)
