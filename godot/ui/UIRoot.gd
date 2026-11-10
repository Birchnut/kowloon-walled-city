class_name UIRoot
extends Control
## UIRoot — 플레이어가 만지는 층 전체의 조립과 교통정리(구룡성채 v3, Anno식 도시경제).
##
## 규칙(ARCHITECTURE 규칙 3): UI는 규칙을 모른다. Game.query()/can() 이 준 값·이유·문장을 그리고,
## 명령은 전부 cmd() 를 지나 Game.cmd() 로 부탁한다. Game.state 는 고치지 않는다.
## 뷰는 계약의 CityView API 로만 부른다(Q.vcall).
##
## 화면 구성(아래 → 위):
##   chrome: TopStrip · FloorRail · 화면들(들여다보기/짓기/경제/교역/성채 시트, 탐험 지도) · NavBar
##   위층: UpgradeDialog · ToastLayer · Banner · Tutorial · 모달
## 화면(screen): "" | inspect | build | economy | expedition | trade | keep. 한 번에 하나.

signal cmd_done(cmd_name: String, args: Dictionary, result: Dictionary)
signal screen_changed(screen: String)

const HUD_POLL := 0.25
const SHEET_SCREENS := ["build", "economy", "expedition", "trade", "keep"]

@export var auto_tutorial: bool = true

var screen: String = ""
var chrome: Control
var strip: TopStrip
var rail: FloorRail
var nav: NavBar
var screens: Dictionary = {}          # id -> Screen
var inspect: InspectSheet
var build: BuildSheet
var economy: EconomySheet
var expedition: ExpeditionScreen
var trade: ContractsSheet
var keep: KeepSheet
var upgrade: UpgradeDialog
var toasts: ToastLayer
var banner: Banner
var tutorial: Tutorial
var modals: Control
var hud: Dictionary = {}

var _view: Node = null
var _poll_t: float = 0.0
var _dim_tw: Tween
var _last_dim_ms: int = -100000
var _names: Dictionary = {}          # 상품 id -> 이름(경제 질의에서)
var _names_t: float = 0.0
var _badge_keep: int = 0
var _goal_done: int = -1
var _research_active: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.ensure_cjk_fallback()
	chrome = _layer()
	add_child(chrome)

	strip = TopStrip.new()
	chrome.add_child(strip)
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.jump.connect(jump)
	strip.resized.connect(_layout)

	rail = FloorRail.new()
	chrome.add_child(rail)
	rail.cut_changed.connect(_on_cut_changed)
	rail.rotate_pressed.connect(func(d: int) -> void: Q.vcall("rotate_view", [d]))
	rail.zoom_pressed.connect(func(d: int) -> void: Q.vcall("zoom_step", [d]))
	rail.lens_toggled.connect(func(on: bool) -> void: Q.vcall("set_lens", ["needs" if on else ""]))
	rail.progress_pressed.connect(func() -> void: toast(rail._progress.info_text(), "dim"))

	inspect = InspectSheet.new()
	build = BuildSheet.new()
	economy = EconomySheet.new()
	trade = ContractsSheet.new()
	keep = KeepSheet.new()
	expedition = ExpeditionScreen.new()
	screens = {"inspect": inspect, "build": build, "economy": economy, "trade": trade, "keep": keep, "expedition": expedition}
	for id: String in ["inspect", "build", "economy", "trade", "keep"]:
		var s: Screen = screens[id]
		s.ui = self
		chrome.add_child(s)
		s.finished.connect(_on_screen_finished.bind(id))
		if s.sheet != null:
			s.sheet.opened.connect(_sync_inset)
			s.sheet.closed.connect(_sync_inset)

	nav = NavBar.new()
	chrome.add_child(nav)
	nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav.grow_vertical = Control.GROW_DIRECTION_BEGIN
	nav.screen_pressed.connect(func(id: String) -> void: open_screen("" if id == screen else id))
	nav.resized.connect(_layout)

	# 탐험 지도는 전면(하단 바는 남긴다)
	expedition.ui = self
	chrome.add_child(expedition)
	chrome.move_child(expedition, nav.get_index())
	expedition.finished.connect(_on_screen_finished.bind("expedition"))

	upgrade = UpgradeDialog.new()
	upgrade.ui = self
	add_child(upgrade)
	toasts = ToastLayer.new()
	add_child(toasts)
	banner = Banner.new()
	banner.y_ratio = 0.3
	add_child(banner)
	tutorial = Tutorial.new()
	tutorial.ui = self
	add_child(tutorial)
	tutorial.remove_child(tutorial.rain)
	add_child(tutorial.rain)
	move_child(tutorial.rain, 0)
	modals = _layer()
	add_child(modals)

	Game.event.connect(_on_event)
	Game.state_replaced.connect(_on_state_replaced)
	get_viewport().size_changed.connect(_layout)
	resized.connect(_layout)
	_layout()
	_refresh_hud()
	_start_session.call_deferred()


func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ------------------------------------------------------------------ 배치
func top_h() -> float:
	return strip.get_combined_minimum_size().y if strip != null else 110.0


func bar_h() -> float:
	return maxf(nav.get_combined_minimum_size().y, NavBar.BAR_H) if nav != null else NavBar.BAR_H


func _layout() -> void:
	if nav == null or not is_inside_tree():
		return
	var safe := UI.safe_insets(self)
	strip.set_safe_top(safe.x)
	nav.set_safe_bottom(safe.y)
	var top := top_h()
	var bar := bar_h()
	rail.reset_size()
	rail.position = Vector2(size.x - rail.size.x - 4.0, top + 6.0)
	# 레일이 하단 바에 닿으면 카메라 버튼을 접는다(두 손가락·휠로도 된다)
	rail.show_camera = true
	rail.reset_size()
	if rail.position.y + rail.get_combined_minimum_size().y > size.y - bar - 8.0:
		rail.show_camera = false
	for id: String in screens:
		(screens[id] as Screen).set_frame(bar, top + 36.0)
	expedition.set_area(top, bar)
	upgrade.set_area(top, bar)
	toasts.top_offset = top + 8.0
	toasts.right_reserve = rail.size.x + 12.0
	tutorial.dialog.bottom_gap = bar
	tutorial.dialog.top_offset = top + 8.0
	_sync_inset()


# ------------------------------------------------------------------ 매 프레임
func _process(delta: float) -> void:
	var v := Q.view()
	if v != _view:
		_bind_view(v)
	if Game.state != null:
		strip.set_time(Game.time_of_day())
	# 토스트는 위쪽 대화·힌트 아래로 비킨다(겹쳐 읽히지 않게)
	var t_off := maxf(top_h() + 8.0, tutorial.dialog.occupied_bottom() + 6.0)
	if absf(toasts.top_offset - t_off) > 0.5:
		toasts.top_offset = t_off
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = HUD_POLL
		_refresh_hud()
	_names_t -= delta


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
	_sync_inset()


func _refresh_hud() -> void:
	hud = Q.dict("hud")
	strip.refresh(hud)
	rail.refresh(hud)
	nav.set_badge("expedition", int(hud.get("teams_done", 0)))
	nav.set_badge("trade", int(hud.get("contracts_failed", 0)))
	nav.set_badge("keep", _badge_keep)


func refresh_soon() -> void:
	_poll_t = 0.0


## 상품 id → 이름(경제 질의의 goods 행). 몇 초에 한 번만 다시 읽는다.
func good_names() -> Dictionary:
	if _names.is_empty() or _names_t <= 0.0:
		_names_t = 5.0
		for g: Variant in UI.to_array(Q.dict("economy").get("goods", [])):
			if g is Dictionary:
				_names[str(g.get("id", ""))] = str(g.get("name", ""))
	return _names


func title() -> String:
	return str(hud.get("title", "대장"))


## 지금 작업 층(레일에서 고른 층, 전체면 지상).
func work_z() -> int:
	return maxi(rail.cut, 0)


# ------------------------------------------------------------------ 공용 창구
## 모든 명령은 여기를 지난다(튜토리얼이 엿듣고, 끝나면 화면을 새로 고친다).
func cmd(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	var r: Variant = Game.cmd(cmd_name, args)
	var d: Dictionary = r if r is Dictionary else {"ok": false, "reason": ""}
	cmd_done.emit(cmd_name, args, d)
	tutorial.on_cmd(cmd_name, args, d)
	refresh_soon()
	return d


func toast(text: String, tone: String = "", icon_id: String = "") -> void:
	toasts.push(text, tone, icon_id)


func confirm(opt: Dictionary, on_ok: Callable = Callable()) -> void:
	Modal.confirm(modals, opt, on_ok)


# ------------------------------------------------------------------ 화면
func open_screen(id: String, a: String = "") -> void:
	if tutorial.running and id != "" and id != "inspect" and not tutorial.screen_allowed(id):
		return
	var prev := screen
	if prev != "" and prev != id and screens.has(prev):
		(screens[prev] as Screen).close()
	screen = id
	if id != "" and screens.has(id):
		(screens[id] as Screen).open(a)
	nav.set_active(id if id in SHEET_SCREENS else "")
	_sync_inset()
	screen_changed.emit(screen)


func close_screen() -> void:
	open_screen("")


func _on_screen_finished(id: String) -> void:
	if screen == id:
		screen = ""
		nav.set_active("")
		_sync_inset()
		screen_changed.emit(screen)


## 열린 하단 시트 높이를 뷰에 알린다 → 도시가 시트 위 빈 영역으로 올라온다.
func _sync_inset() -> void:
	var h := 0.0
	if screens.has(screen):
		h = (screens[screen] as Screen).inset()
	Q.vcall("set_bottom_inset", [h])


## 다른 화면으로 건너뛰기: {screen, arg}. 알림·수요 원인·튜토리얼이 쓴다.
func jump(target: Variant) -> void:
	var j := Q.norm_jump(target)
	var s: String = j["screen"]
	var a: String = j["arg"]
	match s:
		"":
			return
		"upgrade":
			upgrade_all()
		"inspect":
			pass
		_:
			if screens.has(s):
				open_screen(s, a)


## 승급 가능한 집을 계층 묶음으로 일괄 승급 창에. tier=0 이면 가장 낮은 계층 묶음부터(창 안에서 계층을 바꿀 수 있다).
func upgrade_all(tier: int = 0) -> void:
	var groups: Array = []
	for row: Variant in Q.upgradable():
		if row is Dictionary and not UI.to_array(row.get("bids", [])).is_empty():
			groups.append(row)
	if groups.is_empty():
		toast("지금 승급할 수 있는 집이 없다.", "dim")
		return
	upgrade.open_groups(groups, tier)


func open_upgrade(bid: int, info: Dictionary) -> void:
	upgrade.open_single(bid, info)


# ------------------------------------------------------------------ 뷰에서 오는 것
func _on_cut_changed(n: int) -> void:
	Q.vcall("set_floor_cut", [n])
	if screen == "build":
		build.on_floor_changed()


func _on_cell_tapped(info: Variant) -> void:
	var d: Dictionary = info if info is Dictionary else {}
	if upgrade.visible:
		return
	if screens.has(screen) and (screens[screen] as Screen).on_tap(d):
		return
	if screen in ["economy", "trade", "keep"]:
		close_screen()          # 바깥(도시)을 누르면 닫힌다
		return
	_inspect(d)


func _on_cell_dragged(info: Variant) -> void:
	if screens.has(screen):
		(screens[screen] as Screen).on_drag(info if info is Dictionary else {})


func _inspect(info: Dictionary) -> void:
	var pos: Variant = info.get("pos")
	if not bool(info.get("hit", false)) or not (pos is Vector3i):
		if screen == "inspect":
			close_screen()
		return
	if screen != "inspect":
		open_screen("inspect")
	inspect.show_cell(pos)


# ------------------------------------------------------------------ 이벤트
func _on_event(n: String, p: Dictionary) -> void:
	if screens.has(screen):
		(screens[screen] as Screen).on_event(n, p)
	match n:
		"log":
			var tone := str(p.get("tone", ""))
			var tx := str(p.get("text", ""))
			# 목표 달성은 현수막이 말한다(같은 말을 두 번 하지 않게). 일지에는 남는다.
			if tx.begins_with("목표 달성"):
				return
			if tone != "debug" or bool(Data.cfg("debug.enabled", false)):
				toasts.push(tx, tone)
		"unlock":
			_banner_unlock(p)
		"milestone":
			_banner_milestone(p)
		"floor_unlocked":
			var z := int(p.get("z", 0))
			banner.show_banner("새 층", "%d층이 열렸다" % (z + 1), "아래층이 충분히 붐볐다. 이제 위로 쌓을 수 있다.", "jade", 3.0, "樓")
			refresh_soon()
		"power_changed":
			if bool(p.get("on", false)):
				_lights_on()
		"expedition_done":
			refresh_soon()
			_refresh_hud.call_deferred()
			nav.pulse.call_deferred("expedition")
			# 문장은 시뮬 기록 줄("탐험대 n이 …에서 돌아왔다")이 토스트로 이미 띄운다 — 배지·알림 줄로 충분
		"goal_done":
			_on_goal_done(p)
		"contract_done":
			if not bool(p.get("ok", true)):
				toast("계약 회차를 건너뛰었다 — %s" % str(p.get("reason", "")), "warn")
		"day_started", "hour":
			_poll_t = 0.0
			if n == "day_started":
				_check_keep_badge()


func _on_state_replaced() -> void:
	open_screen("")
	upgrade.close()
	toasts.clear()
	rail.set_cut(-1)
	Q.vcall("set_floor_cut", [-1])
	Q.vcall("set_lens", [""])
	rail.set_lens(false)
	_names.clear()
	_goal_done = -1
	_refresh_hud()
	_start_session.call_deferred()


## 성채 배지: 새로 끝난 목표 단계 수 + 연구가 끝났으면 1.
func _check_keep_badge() -> void:
	var g := Q.dict("goals")
	var done := 0
	for s: Variant in UI.to_array(g.get("steps", [])):
		if s is Dictionary and bool(s.get("done", false)):
			done += 1
	if _goal_done < 0:
		_goal_done = done
	elif done > _goal_done:
		_badge_keep += done - _goal_done
		_goal_done = done
		nav.pulse.call_deferred("keep")
	var r := Q.dict("research")
	var act := str(UI.to_dict(r.get("active", {})).get("id", ""))
	if _research_active != "" and act == "":
		_badge_keep += 1
	_research_active = act


func clear_keep_badge() -> void:
	_badge_keep = 0
	nav.set_badge("keep", 0)


## 접속(또는 새 도시) 직후: 자리 비운 사이 요약 → 필요하면 오프닝.
func _start_session() -> void:
	_check_keep_badge()
	var s: Variant = Game.query("offline_summary")
	if s is Dictionary and (float(s.get("real_hours", 0.0)) > 0.0 or not UI.to_array(s.get("lines", [])).is_empty()):
		_show_offline(s)
		return
	if auto_tutorial and not tutorial.running and not tutorial.is_done():
		tutorial.start(tutorial.saved_step())


func _show_offline(s: Dictionary) -> void:
	var hours := float(s.get("real_hours", 0.0))
	var span := ("%d시간 %d분" % [int(hours), int(fmod(hours, 1.0) * 60.0)]) if hours >= 1.0 else ("%d분" % maxi(1, int(round(hours * 60.0))))
	var lines := UI.to_array(s.get("lines", []))
	if lines.is_empty():
		lines = ["별일 없었다. 그게 제일 수상하다."]
	Modal.notice(modals, {
		"kicker": "자리를 비운 사이",
		"title": "%s 동안 경제 시간으로 %s일" % [span, str(snappedf(float(s.get("econ_days", 0.0)), 0.1))],
		"lines": lines, "bullets": true, "ok_text": "돌아왔다",
	})


## 목표 id → {tip, go:[{label, jump}]}(data/ui/goal_tips.json). 없으면 {}.
static func goal_tip(id: String) -> Dictionary:
	var root: Variant = Data.file("goal_tips")
	if root is Dictionary:
		return UI.to_dict(UI.to_dict(root.get("items", {})).get(id, {}))
	return {}


## 목표 달성: 현수막(보상) → 토스트(다음 목표). 오프닝이 도는 중이면 현수막만 짧게(대사를 덮지 않게).
func _on_goal_done(p: Dictionary) -> void:
	var rw: Array = []
	for r: Variant in UI.to_array(p.get("rewards", [])):
		rw.append(str(r))
	var title := ("보상 " + " · ".join(rw)) if not rw.is_empty() else "해냈다"
	banner.show_banner("목표 달성", title, str(p.get("text", "")), "jade", 1.8 if tutorial.running else 2.6, "成")
	_after_goal.call_deferred()


func _after_goal() -> void:
	var h := Q.dict("hud")
	var ng := UI.to_dict(h.get("next_goal", {}))
	if str(ng.get("text", "")) != "":
		toasts.push("다음 목표: " + str(ng["text"]) + " — [성채]에 방법", "good", "", 5.0)
	nav.pulse("keep")


func replay_tutorial() -> void:
	open_screen("")
	tutorial.start(0)


# ------------------------------------------------------------------ 현수막
func _banner_unlock(p: Dictionary) -> void:
	var id := str(p.get("id", ""))
	var nm := str(p.get("name", id))
	var glyph := ""
	var desc := ""
	for cat: Variant in Q.list("build_menu"):
		for it: Variant in UI.to_array(UI.to_dict(cat).get("items", [])):
			if it is Dictionary and str(it.get("id", "")) == id:
				glyph = str(it.get("sign", ""))
				desc = str(it.get("effect_text", it.get("desc", "")))
				if nm == id:
					nm = str(it.get("name", id))
	banner.show_banner("새로 지을 수 있다", nm, desc, "gold", 2.6, glyph.substr(0, 2))


func _banner_milestone(p: Dictionary) -> void:
	var t := str(p.get("title", title()))
	var j := UI.josa(t, "라", "이라").substr(t.length())
	banner.show_banner("성채 등급: %s" % str(p.get("grade_name", "")), "이제 사람들은 당신을\n'%s'%s 부른다" % [t, j], "", "red", 3.6, "城")


## 전기가 들어오면: 몇 초간 UI를 거의 지운다. 뷰가 창을 하나씩 켜는 장면이 주인공이다. (1분에 한 번만)
func _lights_on() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_dim_ms < 60000:
		return
	_last_dim_ms = now
	if _dim_tw != null and _dim_tw.is_valid():
		_dim_tw.kill()
	_dim_tw = create_tween()
	_dim_tw.tween_property(chrome, "modulate:a", 0.1, 0.5)
	_dim_tw.parallel().tween_property(toasts, "modulate:a", 0.0, 0.4)
	_dim_tw.tween_interval(3.2)
	_dim_tw.tween_property(chrome, "modulate:a", 1.0, 0.8)
	_dim_tw.parallel().tween_property(toasts, "modulate:a", 1.0, 0.8)
	_dim_tw.tween_callback(func() -> void:
		banner.show_banner("불이 들어왔다", "창이 하나씩 켜진다", "전기세 고지서는 아직 안 왔다.", "gold", 2.4, "電"))


# ------------------------------------------------------------------ 튜토리얼 강조 대상
## 이름 → 화면 영역. 모르는 이름이면 빈 Rect2(강조 없음).
func target_rect(target: String) -> Rect2:
	if target.begins_with("nav_"):
		var b := nav.button(target.substr(4))
		return b.get_global_rect() if b != null else Rect2()
	if target.begins_with("flow:"):
		# 짓기 흐름을 따라 강조가 옮겨 다닌다: 바 버튼 → 카드 → 확정
		var id := target.substr(5)
		if screen != "build":
			return nav.button("build").get_global_rect()
		if build.mode in ["paint", "place"]:
			return build.target_rect("confirm")
		var r := build.target_rect(id)
		return r if r.size.x > 0 else build.sheet.get_global_rect()
	if target.begins_with("build:"):
		return build.target_rect(target.substr(6))
	if target.begins_with("exp:"):
		return expedition.target_rect(target.substr(4))
	if target.begins_with("inspect:"):
		return inspect.target_rect(target.substr(8))
	if target.begins_with("upgrade:"):
		return upgrade.target_rect(target.substr(8))
	match target:
		"strip":
			return strip.get_global_rect()
		"alert":
			return strip.alert_rect()
		"money":
			return strip.money_rect()
		"rail":
			return rail.floor_rect()
		"progress":
			return rail.progress_rect()
	return Rect2()
