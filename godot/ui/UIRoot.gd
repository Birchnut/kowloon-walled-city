class_name UIRoot
extends Control
## UIRoot — PC판(v0.4) 화면 층의 조립과 교통정리. 1920×1080 기준, 마우스 + 키보드.
##
## 규칙(ARCHITECTURE 규칙 3): UI는 규칙을 모른다. Game.query()/can() 이 준 값·이유·문장을 그리고,
## 명령은 전부 cmd() 를 지나 Game.cmd() 로 부탁한다. 뷰는 계약의 CityView API 로만(Q.vcall).
## v4 시뮬·뷰를 그대로 부른다(개발용 다리 V4Shim 은 통합 때 지웠다).
##
## 배치(docs/UI_NOTES.md v4 '화면 지도'):
##   위 띠 TopBar · 왼쪽 기둥 LeftColumn(목표·알림·층/렌즈) · 아래 가운데 BuildBar · 오른쪽 Inspector
##   창: 현황판(Tab) 경제(F2) 교역(F3) 탐험(F4) 성채(F6) 승급 · 도움말(F1) · 확인 창 · 알림(Toasts) · 오프닝(PcTutorial) · 툴팁(TipLayer)

signal cmd_done(cmd_name: String, args: Dictionary, result: Dictionary)
signal screen_changed(screen: String)

const HUD_POLL := 0.25
const GAP := 10.0

@export var auto_tutorial: bool = true

var hud: Dictionary = {}
var chrome: Control
var top: TopBar
var left: LeftColumn
var build: BuildBar
var inspector: Inspector
var menu: MenuGrid
var place: Placement
var windows: Control
var wins: Dictionary = {}          # id -> PcWindow
var upgrade: UpgradeWin
var help: HelpOverlay
var toasts: Toasts
var tutorial: PcTutorial
var modals: Control
var tips: TipLayer
var runs: RunPanel
var lens: String = ""
var screen: String = ""            # 맨 위에 열린 창 id(없으면 "") — 튜토리얼·하네스가 본다

var _view: Node = null
var _poll_t: float = 0.0
var _names: Dictionary = {}
var _names_t: float = 0.0
var _right_down := Vector2(-1, -1)
var _build_laid := Vector2.ZERO
var _menu_t := 2.0
var _left_down := false
var _hz_seen: Dictionary = {}
var _alert_ids: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	theme = PcTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chrome = _layer()
	add_child(chrome)
	top = TopBar.new()
	chrome.add_child(top)
	top.jump.connect(jump)
	top.speed_pressed.connect(set_speed)
	menu = MenuGrid.new()
	chrome.add_child(menu)
	menu.window_pressed.connect(toggle_window)
	left = LeftColumn.new()
	chrome.add_child(left)
	left.jump.connect(jump)
	inspector = Inspector.new()
	inspector.ui = self
	chrome.add_child(inspector)
	inspector.jump.connect(jump)
	build = BuildBar.new()
	build.ui = self
	chrome.add_child(build)
	build.tool_pressed.connect(_on_tool)
	build.item_pressed.connect(func(it: Dictionary) -> void: place.start_build(it))
	place = Placement.new()
	place.ui = self
	add_child(place)
	place.mode_changed.connect(func(_m: String) -> void:
		if place.active():
			close_all_windows()      # 짓기를 시작하면 창을 닫는다(창이 있는 동안 뷰 입력은 꺼져 있다)
		_layout())

	windows = _layer()
	add_child(windows)
	for w: PcWindow in [MetricsWin.new(), EconomyWin.new(), TradeWin.new(), ExpeditionWin.new(), KeepWin.new()]:
		_add_window(w)
	upgrade = UpgradeWin.new()
	_add_window(upgrade)
	toasts = Toasts.new()
	add_child(toasts)
	tutorial = PcTutorial.new()
	tutorial.ui = self
	add_child(tutorial)
	help = HelpOverlay.new()
	add_child(help)
	modals = _layer()
	add_child(modals)
	tips = TipLayer.new()
	add_child(tips)
	runs = RunPanel.new()
	runs.ui = self
	add_child(runs)

	left.floors.floor_pressed.connect(func(z: int) -> void: Q.vcall("set_floor_cut", [z]))
	left.floors.lens_pressed.connect(set_lens)

	Game.event.connect(_on_event)
	Game.state_replaced.connect(_on_state_replaced)
	get_viewport().size_changed.connect(_layout)
	resized.connect(_layout)
	Settings.apply_all(self)
	_refresh_hud()
	build.refresh()
	_layout()
	_start_session.call_deferred()


func _add_window(w: PcWindow) -> void:
	w.ui = self
	windows.add_child(w)
	wins[w.win_id] = w
	w.closed.connect(_on_window_closed)


func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ------------------------------------------------------------------ 배치
func _layout() -> void:
	if top == null or not is_inside_tree():
		return
	var vs := get_viewport_rect().size
	# 폭 기준 + 실제로 넘치면 한 단계 더(후반 큰 숫자 — 인구 1,224·₩20,169/일 — 에서 1920 폭인데 배속 버튼이 밀려났다)
	var cl := 0 if vs.x >= 1800.0 else (1 if vs.x >= 1450.0 else 2)
	top.set_compact(cl)
	while cl < 2 and top.get_combined_minimum_size().x > vs.x:
		cl += 1
		top.set_compact(cl)
	top.position = Vector2.ZERO
	top.size = Vector2(vs.x, 0)
	top.reset_size()
	top.size.x = vs.x
	var th := top.size.y
	toasts.top = th + 8.0
	left.position = Vector2(GAP, th + GAP)
	left.size = Vector2(LeftColumn.W, vs.y - th - 2.0 * GAP)
	var bw := minf(vs.x - LeftColumn.W - Inspector.W - 4.0 * GAP, 1240.0)
	build.max_w = bw
	build.reset_size()
	var bsz := build.get_combined_minimum_size()
	var bx0 := LeftColumn.W + 2.0 * GAP
	var w := clampf(maxf(bsz.x, build.desired_width()), 300.0, maxf(bw, 300.0))
	build.size = Vector2(w, 0)
	bsz = build.get_combined_minimum_size()
	_build_laid = bsz
	build.size = Vector2(w, bsz.y)
	var mid := bx0 + (vs.x - Inspector.W - GAP - bx0) * 0.5
	build.position = Vector2(floorf(mid - w * 0.5), vs.y - bsz.y - GAP)
	menu.reset_size()
	menu.size.x = Inspector.W
	menu.position = Vector2(vs.x - Inspector.W - GAP, vs.y - menu.size.y - GAP)
	inspector.position = Vector2(vs.x - Inspector.W - GAP, th + GAP)
	inspector.max_h = menu.position.y - th - 2.0 * GAP
	Q.vcall("set_insets", [LeftColumn.W + 2.0 * GAP, th, (Inspector.W + 2.0 * GAP) if inspector.visible else 0.0, bsz.y + 2.0 * GAP])


# ------------------------------------------------------------------ 매 프레임
func _process(delta: float) -> void:
	var v := Q.view()
	if v != _view:
		_bind_view(v)
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = HUD_POLL
		_refresh_hud()
	_sync_view_input()
	toasts.side = any_window()
	_names_t -= delta
	_menu_t -= delta
	if _menu_t <= 0.0:
		_menu_t = 2.0
		build.refresh()      # 해금·비용 가능 여부가 바뀐다(md5 비교라 같으면 그대로)
	# 짓기 막대 크기가 바뀌면(분류 열기·닫기) 다시 배치. 컨테이너는 스스로 커지므로 마지막으로 배치한 크기와 비교한다.
	var bs := build.get_combined_minimum_size()
	if not bs.is_equal_approx(_build_laid):
		_layout()


## 뷰 입력(카메라 키·휠·끌기·호버·탭)은 창·확인 창·도움말·직접 줍기가 떠 있으면 끈다(계약 set_input_enabled).
## 창이 떠 있을 때 도시를 누르면 창을 닫는다(_input) — 그러면 바로 다시 켜진다.
var _view_input := true


func run_open() -> bool:
	return runs != null and runs.is_open()


func view_blocked() -> bool:
	return any_window() or Dialog.open_count > 0 or help.visible or run_open()


func _sync_view_input() -> void:
	var want := not view_blocked()
	if want != _view_input:
		_view_input = want
		Q.vcall("set_input_enabled", [want])
		if not want:
			inspector.set_hover(null)
			tips.cursor_text = ""


func _bind_view(v: Node) -> void:
	if _view != null and is_instance_valid(_view):
		for pair: Array in [["cell_tapped", _on_cell_tapped], ["cell_dragged", _on_cell_dragged]]:
			if _view.has_signal(pair[0]) and _view.is_connected(pair[0], pair[1]):
				_view.disconnect(pair[0], pair[1])
	_view = v
	if v == null:
		return
	if v.has_signal("cell_tapped"):
		v.connect("cell_tapped", _on_cell_tapped)
	if v.has_signal("cell_dragged"):
		v.connect("cell_dragged", _on_cell_dragged)
	_layout()


func _refresh_hud() -> void:
	hud = Q.dict("hud")
	top.refresh(hud)
	if top.compact < 2 and top.get_combined_minimum_size().x > get_viewport_rect().size.x:
		_layout.call_deferred()
	left.refresh(hud)
	if lens != "":
		_apply_lens_cells()
	_check_alerts()
	(menu.btns["expedition"] as PcButton).set_badge(int(hud.get("teams_done", 0)), "jade")
	(menu.btns["trade"] as PcButton).set_badge(int(hud.get("contracts_failed", 0)))


func refresh_soon() -> void:
	_poll_t = 0.0


## 상품 id → 이름(경제 질의). 몇 초에 한 번만 다시 읽는다.
func good_names() -> Dictionary:
	if _names.is_empty() or _names_t <= 0.0:
		_names_t = 5.0
		for g: Variant in UI.to_array(Q.dict("economy").get("goods", [])):
			if g is Dictionary:
				_names[str(g.get("id", ""))] = str(g.get("name", ""))
	return _names


func title() -> String:
	return str(hud.get("title", ""))


# ------------------------------------------------------------------ 공용 창구
## 모든 명령은 여기를 지난다(튜토리얼이 엿듣고, 끝나면 화면을 새로 고친다).
func cmd(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	var r: Variant = Game.cmd(cmd_name, args)
	var d: Dictionary = r if r is Dictionary else {"ok": false, "reason": ""}
	cmd_done.emit(cmd_name, args, d)
	tutorial.on_cmd(cmd_name, args, d)
	refresh_soon()
	inspector.refresh_now()
	if cmd_name in ["build", "zone", "demolish"]:
		build.refresh.call_deferred()
	return d


func toast(text: String, tone: String = "", pic: String = "") -> void:
	toasts.push(text, tone, pic)


func confirm(opt: Dictionary, on_ok: Callable = Callable()) -> void:
	Dialog.confirm(modals, opt, on_ok)


## 배속: speed ∈ {1,2,4}, paused. 계약: Game.speed / Game.paused(v4 hud.speed·paused 로 읽는다).
func set_speed(spd: float, paused: bool) -> void:
	Game.set_speed(spd)
	Game.set_paused(paused)
	Sfx.play("speed")
	tutorial.on_signal("speed")
	refresh_soon()


func set_lens(id: String) -> void:
	lens = id
	left.floors.set_lens(id)
	Q.vcall("set_coverage", [[], []])
	if id in ["", "needs", "tier", "happiness"]:
		Q.vcall("set_lens", [id])
	else:
		Q.vcall("set_lens", ["coverage"])
		_apply_lens_cells()
		var cv := Q.dict("coverage", {"kind": id})
		if str(cv.get("text", "")) != "":
			toast("%s — 범위 안 %s" % [_lens_name(id), str(cv.get("text", ""))], "dim", "eye")
	tutorial.on_signal("lens")


func _lens_name(id: String) -> String:
	for l: Array in FloorPanel.LENSES:
		if l[0] == id:
			return l[1]
	return id


func _apply_lens_cells() -> void:
	if lens in ["", "needs", "tier", "happiness"]:
		return
	var cv := Q.dict("coverage", {"kind": lens})
	Q.vcall("set_coverage", [UI.to_array(cv.get("covered", [])), UI.to_array(cv.get("uncovered", []))])


# ------------------------------------------------------------------ 창
func toggle_window(id: String) -> void:
	if id == "help":
		help.toggle()
		return
	if wins.has(id) and (wins[id] as PcWindow).visible:
		(wins[id] as PcWindow).close()
	else:
		open_window(id)


func open_window(id: String, arg: String = "") -> void:
	if not wins.has(id):
		return
	var w: PcWindow = wins[id]
	w.open(arg)
	windows.move_child(w, -1)
	screen = id
	screen_changed.emit(screen)
	tutorial.on_signal("window:" + id)


func _on_window_closed() -> void:
	screen = ""
	for i in range(windows.get_child_count() - 1, -1, -1):
		var w: PcWindow = windows.get_child(i)
		if w.visible:
			screen = w.win_id
			break
	screen_changed.emit(screen)


func close_top_window() -> bool:
	for i in range(windows.get_child_count() - 1, -1, -1):
		var w: PcWindow = windows.get_child(i)
		if w.visible:
			w.close()
			return true
	return false


func close_all_windows() -> void:
	while close_top_window():
		pass


func any_window() -> bool:
	for w: Node in windows.get_children():
		if (w as PcWindow).visible:
			return true
	return false


## 다른 화면으로 건너뛰기: {screen, arg} 또는 "screen:arg". 알림·수요 원인·목표·신호등이 쓴다.
func jump(target: Variant) -> void:
	var j := Q.norm_jump(target)
	var s: String = j["screen"]
	var a: String = j["arg"]
	if s in ["focus", "lens", "inspect", "build"]:
		close_all_windows()          # 도시로 가는 jump 는 창을 닫는다(창이 도시를 가리고 뷰 입력도 꺼져 있다)
	match s:
		"":
			return
		"upgrade":
			upgrade_all(int(a) if a.is_valid_int() else 0)
		"focus":
			var p := a.split(",")
			if p.size() >= 3:
				var pos := Vector3i(int(p[0]), int(p[1]), int(p[2]))
				Q.vcall("focus", [pos, -1])
				inspector.select(pos)
				_layout()
		"lens":
			set_lens(a)
		"inspect":
			var inf := Q.dict("info", {"bid": int(a)}) if a.is_valid_int() else {}
			var pp: Variant = inf.get("pos")
			if pp is Vector3i:
				Q.vcall("focus", [pp, -1])
				inspector.select(pp)
		"build":
			_jump_build(a)
		_:
			if wins.has(s):
				open_window(s, a)


func _jump_build(a: String) -> void:
	if a == "" :
		return
	if a == "house":
		place.start_zone()
		return
	var it := build.find(a)
	if not it.is_empty():
		build.select_cat(build.cat_of(a))
		place.start_build(it)
		return
	# 분류 id 이거나 모르는 id(SIM 이 이름을 바꿨을 때) → 그 분류만 연다
	build.select_cat(a if build.cat_rect(a).size.x > 0 else "")
	if build.cat == "":
		toast("짓기 막대에서 찾는다(아래).", "dim")


## 승급 가능한 집을 계층 묶음으로 일괄 승급 창에. tier=0 이면 가장 낮은 계층부터.
func upgrade_all(tier: int = 0) -> void:
	var groups: Array = []
	for row: Variant in Q.upgradable():
		if row is Dictionary and not UI.to_array(row.get("bids", [])).is_empty():
			groups.append(row)
	if groups.is_empty():
		toast("지금 승급할 수 있는 집이 없다.", "dim")
		return
	upgrade.open_groups(groups, tier)
	_after_open_upgrade()


func open_upgrade(bid: int, info: Dictionary) -> void:
	upgrade.open_single(bid, info)
	_after_open_upgrade()


func _after_open_upgrade() -> void:
	windows.move_child(upgrade, -1)
	screen = "upgrade"
	screen_changed.emit(screen)


# ------------------------------------------------------------------ 입력
func _on_tool(id: String) -> void:
	match id:
		"house":
			if place.mode == "zone":
				place.cancel()
			else:
				place.start_zone()
		"demolish":
			if place.mode == "demolish":
				place.cancel()
			else:
				place.start_demolish()
		"pick":
			if place.mode == "pick":
				place.cancel()
			else:
				place.start_pick()


func _mouse_on_world() -> bool:
	var h := get_viewport().gui_get_hovered_control()
	if h == null:
		return true
	var v := Q.view()
	return v != null and (h == v or v.is_ancestor_of(h))


func _input(ev: InputEvent) -> void:
	if Dialog.open_count > 0 or help.visible or run_open():
		return
	# 창이 떠 있는 동안 도시(창 밖)를 누르면 창을 닫는다 — 뷰 입력은 창이 있는 동안 꺼져 있다(D-I2).
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and any_window() and not place.active() \
			and (ev as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and _mouse_on_world():
		while close_top_window():
			pass
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseMotion:
		if _mouse_on_world():
			var mp: Vector2 = (ev as InputEventMouseMotion).position
			if place.active():
				place.on_mouse_move(mp)
			else:
				var hv: Dictionary = UI.to_dict(Q.vcall("hover", [mp], {}))
				inspector.set_hover(hv.get("pos") if bool(hv.get("hit", false)) else null)
				# 마우스 아래 주민 한 줄(뷰 who): "굴러온 돌 · 통조림 사러 가는 중"
				var w: Dictionary = UI.to_dict(Q.vcall("who", [mp], {}))
				tips.cursor_tone = "dim"
				tips.cursor_text = str(w.get("text", "")) if bool(w.get("ok", false)) else ""
		elif not place.active():
			inspector.set_hover(null)
			tips.cursor_text = ""
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			place.on_left_release()
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_down = mb.position if _mouse_on_world() else Vector2(-1, -1)
			elif _right_down.x >= 0.0 and mb.position.distance_to(_right_down) < 8.0:
				_right_down = Vector2(-1, -1)
				_on_right_click()


func _on_right_click() -> void:
	if place.active():
		place.cancel()
	elif inspector.selected_pos != null:
		inspector.deselect()
		_layout()


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed:
		return
	var k := ev as InputEventKey
	if Dialog.open_count > 0 or run_open():
		return
	if k.echo:
		return
	if help.visible:
		if k.keycode in [KEY_ESCAPE, KEY_F1]:
			help.toggle()
			get_viewport().set_input_as_handled()
		return
	var handled := true
	match k.keycode:
		KEY_ESCAPE:
			if place.active():
				place.cancel()
			elif close_top_window():
				pass
			elif inspector.selected_pos != null:
				inspector.deselect()
			elif lens != "":
				set_lens("")
			else:
				handled = false
		KEY_SPACE:
			set_speed(Game.speed, not Game.paused)
		KEY_1:
			set_speed(1.0, false)
		KEY_2:
			set_speed(2.0, false)
		KEY_3:
			set_speed(4.0, false)
		KEY_TAB:
			toggle_window("metrics")
		KEY_F1:
			help.toggle()
		KEY_F2:
			toggle_window("economy")
		KEY_F3:
			toggle_window("trade")
		KEY_F4:
			toggle_window("expedition")
		KEY_F6:
			toggle_window("keep")
		KEY_F11:
			Settings.toggle_fullscreen()
		KEY_H:
			_on_tool("house")
		KEY_X, KEY_DELETE:
			if not place.active() and inspector.selected_pos != null and k.keycode == KEY_DELETE:
				place.confirm_demolish(inspector.selected_pos)
			else:
				_on_tool("demolish")
		KEY_G:
			var hv: Dictionary = UI.to_dict(Q.vcall("hover", [get_viewport().get_mouse_position()], {}))
			if bool(hv.get("hit", false)) and _mouse_on_world():
				place.pick_at(hv.get("pos"))
			else:
				_on_tool("pick")
		KEY_R:
			if place.mode == "build":
				place.rotate()
			else:
				handled = false
		KEY_U:
			var inf := inspector.info
			if inspector.selected_pos != null and str(inf.get("kind", "")) == "house":
				open_upgrade(int(inf.get("bid", -1)), inf)
			else:
				upgrade_all()
		KEY_S:
			if k.ctrl_pressed:
				Settings.quick_save(self)
			else:
				handled = false
		_:
			var i := BuildBar.CAT_KEYCODES.find(k.keycode)
			if i >= 0 and not k.ctrl_pressed:
				var c := build.cat_at(i)
				if c != "":
					build.select_cat("" if build.cat == c else c)
			else:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ 뷰에서 오는 것
func _on_cell_tapped(info: Variant) -> void:
	var d: Dictionary = info if info is Dictionary else {}
	if int(d.get("button", 1)) == 2:
		_on_right_click()
		return
	if place.active():
		return          # 배치·칠하기는 cell_dragged 로 받는다
	var pos: Variant = d.get("pos")
	if not bool(d.get("hit", false)) or not (pos is Vector3i):
		inspector.deselect()
		_layout()
		return
	inspector.select(pos)
	tutorial.on_signal("inspect:" + str(inspector.info.get("kind", "")))
	_layout()


func _on_cell_dragged(info: Variant) -> void:
	if place.active():
		place.on_cell_dragged(info if info is Dictionary else {})


# ------------------------------------------------------------------ 이벤트
func _on_event(n: String, p: Dictionary) -> void:
	for w: Node in windows.get_children():
		if (w as PcWindow).visible and w.has_method("on_event"):
			w.call("on_event", n, p)
	tutorial.on_event(n, p)
	match n:
		"log":
			var tone := str(p.get("tone", ""))
			var tx := str(p.get("text", ""))
			if tx.begins_with("목표 달성") or tx.begins_with("성채 등급") or tx.begins_with("새로 지을 수 있다"):
				return
			if tone != "debug" or bool(Data.cfg("debug.enabled", false)):
				toasts.push(tx, tone)
		"unlock":
			_unlock_pending.append(p)
			_celebrate_soon()
			build.refresh.call_deferred()
		"goal_done":
			_goal_pending.append(p)
			_celebrate_soon()
			Sfx.play("goal")
		"milestone":
			toasts.card({"kicker": "성채 등급: %s" % str(p.get("grade_name", "")), "title": "이제 사람들은 당신을 '%s'(이)라 부른다" % str(p.get("title", "")), "tone": "red", "picto": "keep", "life": 4.0})
		"floor_unlocked":
			var z := int(p.get("z", 0))
			Sfx.play("floor")
			toasts.card({"kicker": "새 층", "title": "%d층이 열렸다" % (z + 1), "body": "왼쪽 아래 층 고르기나 PgUp으로 %dF를 보고 짓는다." % (z + 1), "tone": "jade", "picto": "floor"})
		"hazard_on":
			_hazard_intro(str(p.get("kind", "")), float(p.get("grace_days", 0.0)))
		"fire_started":
			Sfx.play("fire")
			var pos: Variant = p.get("pos")
			toasts.push("불이 났다! 왼쪽 알림을 누르면 그 자리로 간다.", "bad", "fire")
			if pos is Vector3i and not bool(_hz_seen.get("fire_first", false)):
				_hz_seen["fire_first"] = true
				Q.vcall("focus", [pos, -1])
		"fire_out":
			toasts.push("불이 꺼졌다%s" % (" — 탄 집은 수리해야 쓴다" if bool(p.get("burnt", false)) else ""), "dim", "fire")
		"outbreak":
			Sfx.play("disease")
			toasts.push("병이 돌기 시작했다 — 집 %d채" % UI.to_array(p.get("bids", [])).size(), "bad", "disease")
		"construction_done":
			pass
		"research_done":
			toasts.card({"kicker": "연구 끝", "title": str(p.get("name", "")), "body": "성채 › 연구에서 다음 것을 고른다.", "tone": "jade", "picto": "check"})
		"raid":
			toasts.card({"kicker": "단속", "title": "%s 닫혔다" % UI.josa(_type_name(str(p.get("type", ""))), "가", "이"), "body": "벌금 %s. 이틀 뒤 다시 연다. 뒷돈 정책이 위험을 늦춘다." % UI.won(p.get("fine", 0)), "tone": "red", "picto": "warn"})
		"raid_end":
			toast("단속이 풀렸다. 닫혔던 곳이 다시 연다.", "good")
		"expedition_done":
			Sfx.play("expedition")
			refresh_soon()
		"contract_done":
			if not bool(p.get("ok", true)):
				toast("계약 회차를 건너뛰었다 — %s" % str(p.get("reason", "")), "warn")
		"speed_changed":
			refresh_soon()
		"day_started", "hour":
			_poll_t = 0.0


func _type_name(id: String) -> String:
	var it := build.find(id)
	return str(it.get("name", id))


## 새 경고 알림이 뜨면 소리(같은 id 는 한 번).
func _check_alerts() -> void:
	var now := {}
	for a: Variant in UI.to_array(hud.get("alerts", [])):
		var id := str(UI.to_dict(a).get("id", UI.to_dict(a).get("text", "")))
		now[id] = true
		if not _alert_ids.has(id) and str(UI.to_dict(a).get("tone", "")) in ["bad", "danger", "red", "alert"]:
			Sfx.play("alert")
	_alert_ids = now


## 불·병이 처음 켜질 때 한 번: 짧은 설명 카드(누를 때까지) + 렌즈 버튼.
func _hazard_intro(kind: String, grace: float) -> void:
	if bool(_hz_seen.get(kind, false)):
		return
	_hz_seen[kind] = true
	Sfx.play("hazard_on")
	if kind == "fire":
		toasts.card({"kicker": "새 위험 — 불", "title": "이제부터 불이 날 수 있다%s" % ((" (%s 뒤부터)" % UI.days(grace)) if grace > 0.0 else ""),
			"body": "소방대 범위 밖의 칸에 불이 나면 옆·위로 번진다. 탄 집은 수리해야 쓴다. 소방대(양동이)는 위아래 한 층까지 닿는다. 위 띠의 불 신호등과 '소방' 렌즈로 빈 곳을 본다.",
			"tone": "red", "picto": "fire", "life": 0.0, "buttons": [{"label": "소방대 짓기", "cb": func() -> void:
				set_lens("fire")
				jump({"screen": "build", "arg": "fire_bucket"})}, {"label": "소방 렌즈 보기", "cb": func() -> void: set_lens("fire")}, {"label": "알았다", "cb": Callable()}]})
	elif kind == "disease":
		toasts.card({"kicker": "새 위험 — 병", "title": "이제부터 병이 돌 수 있다%s" % ((" (%s 뒤부터)" % UI.days(grace)) if grace > 0.0 else ""),
			"body": "집마다 쓰레기가 나온다. 수거 범위 밖에 쌓이면 그 구역에 병이 돈다 — 일손 반, 행복 하락. 넝마주이 조합(수거)과 의원으로 막는다. '수거'·'의원' 렌즈로 본다.",
			"tone": "red", "picto": "disease", "life": 0.0, "buttons": [{"label": "조합 짓기", "cb": func() -> void:
				set_lens("trash")
				jump({"screen": "build", "arg": "trash_guild"})}, {"label": "수거 렌즈 보기", "cb": func() -> void: set_lens("trash")}, {"label": "알았다", "cb": Callable()}]})


var _unlock_pending: Array = []
var _goal_pending: Array = []
var _celebrate_armed := false


func _celebrate_soon() -> void:
	if _celebrate_armed:
		return
	_celebrate_armed = true
	get_tree().create_timer(0.3).timeout.connect(_flush_celebrate)


func _flush_celebrate() -> void:
	_celebrate_armed = false
	var goals := _goal_pending.duplicate()
	var ps := _unlock_pending.duplicate()
	_goal_pending.clear()
	_unlock_pending.clear()
	var names: Array = []
	for q: Variant in ps:
		var id := str(UI.to_dict(q).get("id", ""))
		var nm := str(UI.to_dict(q).get("name", id))
		names.append(_type_name(id) if nm == id else nm)
	for gi in goals.size():
		var g: Dictionary = UI.to_dict(goals[gi])
		var rw: Array = []
		for r: Variant in UI.to_array(g.get("rewards", [])):
			rw.append(str(r))
		var body := ("보상 " + " · ".join(rw)) if not rw.is_empty() else ""
		if gi == goals.size() - 1 and not names.is_empty():
			body += ("\n" if body != "" else "") + "새로 지을 수 있다: " + " · ".join(names)
			names.clear()
		var ng := UI.to_dict(Q.dict("hud").get("next_goal", {}))
		if gi == goals.size() - 1 and str(ng.get("text", "")) != "":
			body += "\n다음: " + str(ng.get("text", ""))
		toasts.card({"kicker": "목표 달성", "title": str(g.get("text", "")), "body": body, "tone": "jade", "picto": "goal", "life": 4.0})
		if not rw.is_empty():
			Sfx.play("money")
	if not names.is_empty():
		Sfx.play("unlock")
		toasts.card({"kicker": "새로 지을 수 있다" + (" · %d가지" % names.size() if names.size() > 1 else ""), "title": " · ".join(names), "body": "아래 짓기 막대에서 찾는다.", "tone": "gold", "picto": "plus"})


func _on_state_replaced() -> void:
	place.cancel()
	for w: Node in windows.get_children():
		(w as PcWindow).close()
	toasts.clear()
	inspector.deselect()
	set_lens("")
	Q.vcall("set_floor_cut", [-1])
	_names.clear()
	_hz_seen.clear()
	_refresh_hud()
	build.refresh()
	_start_session.call_deferred()


func _start_session() -> void:
	if auto_tutorial and not tutorial.running and not tutorial.is_done():
		tutorial.start(tutorial.saved_step())


# ------------------------------------------------------------------ 튜토리얼·하네스 대상
## 이름 → 화면 영역. 모르는 이름이면 빈 Rect2.
func target_rect(t: String) -> Rect2:
	if t.begins_with("tool:"):
		return build.tool_rect(t.substr(5))
	if t.begins_with("cat:"):
		return build.cat_rect(t.substr(4))
	if t.begins_with("card:"):
		return build.card_rect(t.substr(5))
	if t.begins_with("win:"):
		var b: Control = menu.btns.get(t.substr(4))
		return b.get_global_rect() if b != null else Rect2()
	if t.begins_with("signal:"):
		return top.signal_rect(t.substr(7))
	if t.begins_with("lens:"):
		return left.floors.lens_rect(t.substr(5))
	match t:
		"top":
			return top.get_global_rect()
		"speed":
			return (top._speed_btns["x1"] as Control).get_global_rect().merge((top._speed_btns["x4"] as Control).get_global_rect()).merge((top._speed_btns["pause"] as Control).get_global_rect())
		"goal":
			return left.goal_rect()
		"floors":
			return left.floors.floors_rect()
		"inspector":
			return inspector.get_global_rect() if inspector.visible else Rect2()
		"build":
			return build.get_global_rect()
		"cats":
			return build._cat_row.get_global_rect()
		"world":
			var vs := get_viewport_rect().size
			return Rect2(Vector2(LeftColumn.W + 40, 120), Vector2(vs.x - LeftColumn.W - Inspector.W - 80, vs.y - 400))
	return Rect2()
