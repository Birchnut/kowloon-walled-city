extends Node
## UISandbox — 가짜 시뮬(MockSim) + 가짜 뷰(MockView) 위에서 UI 전체를 돌려 본다.
##
##   tools/shot.sh res://ui/dev/UISandbox.tscn out 30 540x960 city=mid scn=plant
##
## 사용자 인자:
##   city=empty|mid|tall   시작 도시(기본 mid)
##   scn=<이름>            아래 _scn_* 시나리오를 자동으로 연기한다(스크린샷용)
##   tutorial=1            오프닝을 튼다(city=empty 와 함께)
##   tod=0..1              감상 시간 고정
##   png=<경로> png_at=<초> 실제 창 크기로 한 장 찍고 종료(다른 화면비 확인용)

var ui: UIRoot
var view: MockView
var sim: MockSim
var args: Dictionary = {}


func _ready() -> void:
	# (주의) 오토로드 Game._ready 가 끝난 뒤여야 한다 → _enter_tree 가 아니라 _ready 에서 갈아 끼운다.
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	sim = MockSim.new()
	sim.setup(Data.files)
	Game.sim = sim
	Game.autosave = false
	Game.new_game(1234)
	sim.preset(Game.state, str(args.get("city", "mid")))
	Game.state.events.clear()
	if args.has("offline"):
		Game._offline_summary = MockSim.offline_sample()
	view = MockView.new()
	add_child(view)
	ui = (load("res://ui/UIRoot.tscn") as PackedScene).instantiate()
	ui.auto_tutorial = args.has("tutorial")
	add_child(ui)
	if args.has("tod"):
		view.set_time_override(float(args["tod"]))
	if args.has("scn"):
		_run.call_deferred(str(args["scn"]))
	if args.has("png"):
		_snap.call_deferred(str(args["png"]), float(args.get("png_at", "2.2")))


## png=<절대 경로> [png_at=<초>] : 실제 창 크기 그대로 한 장 찍고 끝낸다.
## (tools/shot.sh 의 무비 기록은 항상 540x960 이라 다른 화면비를 못 본다)
func _snap(path: String, at: float) -> void:
	await get_tree().create_timer(at).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _tap(pos: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = pos
		e.global_position = pos
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		get_viewport().push_input(e, true)
		await get_tree().process_frame


func _drag(from: Vector2, to: Vector2, steps: int = 8) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = from
	e.global_position = from
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e, true)
	var last := from
	for i in steps:
		var p := from.lerp(to, float(i + 1) / float(steps))
		var m := InputEventMouseMotion.new()
		m.position = p
		m.global_position = p
		m.relative = p - last
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(m, true)
		last = p
		await get_tree().process_frame
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = to
	u.global_position = to
	get_viewport().push_input(u, true)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _run(scn: String) -> void:
	await _wait(0.3)
	var m := "_scn_" + scn
	if has_method(m):
		await call(m)
	else:
		push_warning("모르는 시나리오: " + scn)


# ------------------------------------------------------------------ 시나리오
func _scn_hud() -> void:
	pass


func _scn_plant() -> void:
	await _tap(_center(ui.verbs.button("plant")))


func _scn_plant_scrolled() -> void:
	await _tap(_center(ui.verbs.button("plant")))
	await _wait(0.4)
	var r := ui.plant.sheet.get_global_rect()
	await _drag(Vector2(460, r.size.y - 200), Vector2(120, r.size.y - 200), 10)


func _scn_plant_place() -> void:
	await _tap(_center(ui.verbs.button("plant")))
	await _wait(0.5)
	await _tap(ui.plant.card_rect(1).get_center())
	await _wait(0.5)
	await _tap(view.project(Vector3i(9, 6, 0)) + Vector2(0, 18))


func _scn_plant_bad() -> void:
	await _tap(_center(ui.verbs.button("plant")))
	await _wait(0.5)
	await _tap(ui.plant.card_rect(1).get_center())
	await _wait(0.5)
	await _tap(view.project(Vector3i(2, 2, 0)) + Vector2(0, 18))


func _scn_zone() -> void:
	await _tap(_center(ui.verbs.button("zone")))
	await _wait(0.5)
	await _drag(view.project(Vector3i(10, 4, 0)) + Vector2(0, 18), view.project(Vector3i(10, 7, 0)) + Vector2(0, 18), 12)


func _scn_demolish() -> void:
	await _tap(_center(ui.verbs.button("zone")))
	await _wait(0.5)
	await _tap(_center(ui.zone._seg.button("demolish")))
	await _wait(0.2)
	var top := Game.state.column_height(Vector2i(7, 6)) - 1
	await _tap(view.project(Vector3i(7, 6, top)) + Vector2(0, 4))


func _scn_policy() -> void:
	await _tap(_center(ui.verbs.button("policy")))


func _scn_policy_change() -> void:
	await _tap(_center(ui.verbs.button("policy")))
	await _wait(0.5)
	ui.policy._open_axes["ind_farm"] = true
	ui.policy.refresh()
	await _wait(0.2)
	var seg: Segmented = ui.policy._list.get_child(1).get_child(1)
	await _tap(_center(seg.button("allow")))


func _scn_cards() -> void:
	await _tap(_center(ui.verbs.button("cards")))


func _scn_cards_choose() -> void:
	await _tap(_center(ui.verbs.button("cards")))
	await _wait(0.6)
	var card: CardView = ui.cards._holder.get_child(0).get_child(1).get_child(0)
	await _tap(_center(card._choices_box.get_child(0)))


func _scn_cards_empty() -> void:
	Game.state.pending_cards.clear()
	await _tap(_center(ui.verbs.button("cards")))


func _scn_inspect() -> void:
	var top := Game.state.column_height(Vector2i(4, 5)) - 1
	await _tap(view.project(Vector3i(4, 5, top)) + Vector2(0, 4))


func _scn_record() -> void:
	await _tap(_center(ui.strip))


func _scn_settings() -> void:
	ui.set_tool("record")
	await _wait(0.3)
	ui.record.open("settings")


func _scn_collect() -> void:
	await _wait(0.4)
	var r := ui.bubbles.first_bubble_rect()
	for id in ui.bubbles._bubbles:
		var b: Bubble = ui.bubbles._bubbles[id]
		if b.ready_now and b.visible:
			r = b.get_global_rect()
	await _tap(r.get_center())


func _scn_collect_all() -> void:
	Game.cmd("debug", {"op": "fill"})
	await _wait(0.8)
	await _tap(_center(ui.bubbles._all_btn))


func _scn_cut() -> void:
	ui.rail.set_cut(1, true)


func _scn_toasts() -> void:
	ui.toast("자릿세 +31", "good", "coin")
	ui.toast("3층에서 싸움이 났다. 마작 때문이라고 한다.", "warn")
	ui.toast("안 거둔 자릿세 6을 누가 챙겼다. 누군지는 다들 안다.", "bad")
	ui.toast("빨랫줄이 하나 더 걸렸다.")


func _scn_unlock() -> void:
	Game.cmd("debug", {"op": "unlock_all"})


func _scn_identity() -> void:
	Game.cmd("debug", {"op": "rename", "title": "따거", "epithet": "천 개의 치과"})


func _scn_power() -> void:
	Game.cmd("debug", {"op": "power", "level": 1})


func _scn_cards_ready() -> void:
	Game.state.pending_cards.clear()
	await _wait(0.3)
	Game.cmd("debug", {"op": "cards"})


func _scn_confirm_new() -> void:
	ui.set_tool("record")
	ui.record.open("settings")
	await _wait(0.4)
	ui.record._ask_new_game()


## 오프닝을 처음부터 끝까지 사람처럼 눌러 본다(tutorial=1 city=empty 와 함께).
func _scn_tutorial_play() -> void:
	var t := ui.tutorial
	var guard := 0
	while t.running and guard < 400:
		guard += 1
		await _wait(0.25)
		if t.dialog._mode == "say":
			t.dialog.advance()
			continue
		var w: Dictionary = t._wait
		if w.is_empty():
			continue
		if str(w.get("cmd", "")) == "plant":
			if ui.tool != "plant":
				await _tap(_center(ui.verbs.button("plant")))
			elif not ui.plant.is_placing():
				await _wait(0.3)
				await _tap(ui.plant.card_rect(1).get_center())
			elif not ui.plant._pill.visible:
				await _tap(view.project(Vector3i(5, 6, 0)) + Vector2(0, 18))
			else:
				await _tap(_center(ui.plant._pill_ok))
		elif str(w.get("cmd", "")) == "collect":
			var r := ui.bubbles.first_bubble_rect()
			if r.size.x > 0:
				await _tap(r.get_center())


## 오프닝을 n 번째 단계까지만 넘긴다(step=<n>).
func _scn_tutorial_to() -> void:
	var t := ui.tutorial
	var until := int(args.get("step", "3"))
	var guard := 0
	while t.running and t.step_index() < until and guard < 200:
		guard += 1
		await _wait(0.15)
		if t.dialog._mode == "say":
			t.dialog.advance()
			t.dialog.advance()
