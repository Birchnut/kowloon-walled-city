class_name UIRoot
extends Control
## UIRoot — 플레이어가 만지는 층 전체의 조립과 교통정리.
##
## 규칙(ARCHITECTURE 규칙 3): UI는 규칙을 모른다. Game.query() 가 준 것을 그리고, Game.can() 에 묻고,
## Game.cmd() 로 부탁한다. Game.state 는 고치지 않는다. 뷰는 계약의 CityView API 로만 부른다(Q.vcall).
##
## 화면 구성(위→아래 순으로 덮는다):
##   PaintCatcher(긋기 중 끌기) · BubbleLayer(수금 말풍선) · TopStrip · FloorRail ·
##   시트들(심기/긋기/허가/결재/들여다보기/기록) · VerbBar · ToastLayer · Banner · Tutorial · 모달
##
## 도구(tool): "" | plant | zone | policy | cards | record | inspect. 한 번에 하나.

signal cmd_done(cmd_name: String, args: Dictionary, result: Dictionary)
signal plant_picked(facility_id: String)
signal tool_changed(tool_name: String)

const HUD_POLL := 0.25
const BUBBLE_POLL := 0.5
const SHEET_TOOLS := ["plant", "zone", "policy", "cards", "record"]

## 새 도시면 오프닝을 자동으로 튼다(샌드박스는 끈다).
@export var auto_tutorial: bool = true

var tool: String = ""
var chrome: Control
var paint: Control
var bubbles: BubbleLayer
var strip: TopStrip
var rail: FloorRail
var plant: PlantSheet
var zone: ZoneBar
var policy: PolicySheet
var cards: CardsSheet
var inspect: InspectSheet
var record: RecordSheet
var verbs: VerbBar
var toasts: ToastLayer
var banner: Banner
var tutorial: Tutorial
var modals: Control

var _view: Node = null
var _poll_t: float = 0.0
var _bubble_t: float = 0.0
var _power: int = -1
var _title: String = ""
var _epithet: String = ""
var _money_hold: float = 0.0
var _dim_tw: Tween
var _painting: bool = false
var _hud: Dictionary = {}
var log_seq: int = 0                # log 이벤트가 올 때마다 +1 (같은 일을 두 번 토스트하지 않으려고)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chrome = _layer()
	add_child(chrome)

	paint = Control.new()
	paint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint.gui_input.connect(_on_paint_input)
	chrome.add_child(paint)

	bubbles = BubbleLayer.new()
	chrome.add_child(bubbles)
	bubbles.collect_requested.connect(_on_collect_requested)

	strip = TopStrip.new()
	chrome.add_child(strip)
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.pressed.connect(func() -> void: set_tool("record"))
	strip.resized.connect(_layout)

	rail = FloorRail.new()
	chrome.add_child(rail)
	rail.cut_changed.connect(_on_cut_changed)
	rail.rotate_pressed.connect(func(d: int) -> void: Q.vcall("rotate_view", [d]))
	rail.zoom_pressed.connect(func(d: int) -> void: Q.vcall("zoom_step", [d]))

	plant = PlantSheet.new()
	zone = ZoneBar.new()
	policy = PolicySheet.new()
	cards = CardsSheet.new()
	inspect = InspectSheet.new()
	record = RecordSheet.new()
	for s in [inspect, plant, zone, policy, cards, record]:
		s.ui = self
		chrome.add_child(s)
		if s.get("sheet") != null:
			s.sheet.opened.connect(_sync_inset)
			s.sheet.closed.connect(_sync_inset)
	plant.finished.connect(_on_tool_finished.bind("plant"))
	zone.finished.connect(_on_tool_finished.bind("zone"))
	policy.finished.connect(_on_tool_finished.bind("policy"))
	cards.finished.connect(_on_tool_finished.bind("cards"))
	record.finished.connect(_on_tool_finished.bind("record"))
	inspect.finished.connect(_on_tool_finished.bind("inspect"))
	zone.mode_changed.connect(_sync_paint)
	record.replay_tutorial.connect(_replay_tutorial)

	verbs = VerbBar.new()
	chrome.add_child(verbs)
	verbs.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	verbs.grow_vertical = Control.GROW_DIRECTION_BEGIN
	verbs.verb_pressed.connect(set_tool)
	verbs.resized.connect(_layout)

	toasts = ToastLayer.new()
	add_child(toasts)
	banner = Banner.new()
	add_child(banner)
	tutorial = Tutorial.new()
	tutorial.ui = self
	add_child(tutorial)
	# 비는 HUD 뒤에서 내린다(도시 위, 크롬 아래)
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
	_refresh_all()
	_power = int(_hud.get("power_level", 0))
	_start_session.call_deferred()


func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ------------------------------------------------------------------ 배치
func _layout() -> void:
	if verbs == null or not is_inside_tree():
		return
	var safe := UI.safe_insets(self)
	strip.set_safe_top(safe.x)
	verbs.set_safe_bottom(safe.y)
	var top := strip.get_combined_minimum_size().y
	var bar := maxf(verbs.get_combined_minimum_size().y, VerbBar.BAR_H)
	rail.reset_size()
	rail.position = Vector2(size.x - rail.size.x - 4.0, top + 6.0)
	# 레일이 화면의 62%를 넘겨 엄지 자리로 내려오면 줌 버튼을 접는다
	rail.show_zoom = size.y >= 900.0
	for s in [plant, zone, policy, cards, inspect, record]:
		s.bottom_gap = bar
		s.sheet.top_limit = top + 34.0
	toasts.top_offset = top + 8.0
	bubbles.top_guard = top
	bubbles.bottom_guard = bar
	tutorial.dialog.bottom_gap = bar        # 대화 상자는 동사 바를 가리지 않는다(강조할 때 보여야 하므로)
	tutorial.dialog.top_offset = top + 8.0
	bubbles.coin_target = strip.money.icon_center()
	bubbles.reposition()


# ------------------------------------------------------------------ 매 프레임
func _process(delta: float) -> void:
	var v := Q.view()
	if v != _view:
		_bind_view(v)
	if Game.state != null:
		strip.set_time(Game.time_of_day())
	_money_hold = maxf(0.0, _money_hold - delta)
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = HUD_POLL
		_refresh_hud()
	_bubble_t -= delta
	if _bubble_t <= 0.0:
		_bubble_t = BUBBLE_POLL
		_sync_bubbles()


func _bind_view(v: Node) -> void:
	if _view != null and is_instance_valid(_view):
		if _view.has_signal("cell_tapped") and _view.is_connected("cell_tapped", _on_cell_tapped):
			_view.disconnect("cell_tapped", _on_cell_tapped)
		if _view.has_signal("view_changed") and _view.is_connected("view_changed", _on_view_changed):
			_view.disconnect("view_changed", _on_view_changed)
	_view = v
	if v == null:
		return
	if v.has_signal("cell_tapped"):
		v.connect("cell_tapped", _on_cell_tapped)
	if v.has_signal("view_changed"):
		v.connect("view_changed", _on_view_changed)
	_on_view_changed()


# ------------------------------------------------------------------ 새로고침
func _refresh_all() -> void:
	_refresh_hud()
	_sync_bubbles()


func _refresh_hud() -> void:
	_hud = Q.dict("hud")
	var shown := _hud
	if _money_hold > 0.0 and _hud.has("money"):
		# 동전이 날아가는 동안은 돈 숫자를 붙잡아 둔다(도착할 때 오르게)
		shown = _hud.duplicate()
		shown.erase("money")
		shown["money"] = strip.money._value
	strip.refresh(shown)
	verbs.set_badge("cards", int(_hud.get("cards", 0)))
	rail.set_floors(_floor_count())
	_title = str(_hud.get("title", _title))
	_epithet = str(_hud.get("epithet", _epithet))


## 지금 가장 높은 층 수: hud.floors(있으면) → view.get_max_floor()(있으면) → 설정의 최대 층.
func _floor_count() -> int:
	if _hud.has("floors"):
		return int(_hud["floors"])
	var v: Variant = Q.vcall("get_max_floor")
	if v is int:
		return v
	if _hud.is_empty():
		return 0
	return int(Data.cfg("grid.max_floors", 10))


func _sync_bubbles() -> void:
	bubbles.sync(Q.list("collect_points"))


func _refresh_soon() -> void:
	_poll_t = 0.0
	_bubble_t = minf(_bubble_t, 0.05)


# ------------------------------------------------------------------ 공용 창구
## 모든 명령은 여기를 지난다(튜토리얼이 엿듣고, 끝나면 화면을 새로 고친다).
func cmd(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	var r: Variant = Game.cmd(cmd_name, args)
	var d: Dictionary = r if r is Dictionary else {"ok": false, "reason": ""}
	cmd_done.emit(cmd_name, args, d)
	tutorial.on_cmd(cmd_name, args, d)
	_refresh_soon()
	return d


func toast(text: String, tone: String = "", icon_id: String = "") -> void:
	toasts.push(text, tone, icon_id)


func confirm(opt: Dictionary, on_ok: Callable = Callable()) -> void:
	Modal.confirm(modals, opt, on_ok)


## 튜토리얼 강조 대상의 화면 영역. 모르는 이름이면 빈 Rect2.
func target_rect(target: String) -> Rect2:
	if target.begins_with("verb_"):
		var b := verbs.button(target.substr(5))
		return b.get_global_rect() if b != null else Rect2()
	match target:
		"plant_flow":
			if plant.is_placing():
				return Rect2()
			if plant.sheet.is_open:
				return plant.card_rect(0)
			return verbs.button("plant").get_global_rect()
		"bubble":
			return bubbles.first_bubble_rect()
		"strip":
			return strip.get_global_rect()
		"rail":
			return rail.get_global_rect()
		"money":
			return strip.money.get_global_rect()
	return Rect2()


# ------------------------------------------------------------------ 도구
func set_tool(t: String) -> void:
	if t == tool and t != "inspect":
		t = ""                       # 같은 동사를 다시 누르면 닫는다
	var prev := tool
	tool = t
	if prev != t:
		match prev:
			"plant":
				plant.close()
			"zone":
				zone.close()
			"policy":
				policy.close()
			"cards":
				cards.close()
			"record":
				record.close()
			"inspect":
				inspect.close()
	match t:
		"plant":
			plant.open()
		"zone":
			zone.open()
		"policy":
			policy.open()
		"cards":
			cards.open()
		"record":
			record.open()
	verbs.set_active(t if t in SHEET_TOOLS else "")
	_sync_suppress()
	_sync_paint()
	_sync_inset()
	tool_changed.emit(tool)


## 열린 하단 시트 높이를 뷰에 알린다 → 도시가 시트 위 빈 영역으로 올라온다.
func _sync_inset() -> void:
	var h := 0.0
	for s in [plant, zone, policy, cards, inspect, record]:
		if s != null and s.get("sheet") != null and s.sheet.is_open:
			h = maxf(h, s.sheet.sheet_height())
	Q.vcall("set_bottom_inset", [h])


func _on_tool_finished(which: String) -> void:
	if tool == which:
		set_tool("")


func _sync_suppress() -> void:
	bubbles.set_suppressed(tool in SHEET_TOOLS or rail.cut >= 0)


func _sync_paint() -> void:
	paint.mouse_filter = Control.MOUSE_FILTER_STOP if (tool == "zone" and zone.wants_paint()) else Control.MOUSE_FILTER_IGNORE
	_painting = false


func _on_paint_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_painting = ev.pressed
		if ev.pressed:
			zone.stroke_begin()
			zone.paint_at(ev.global_position)
		paint.accept_event()
	elif ev is InputEventMouseMotion and _painting:
		zone.paint_at(ev.global_position)
		paint.accept_event()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		Q.vcall("zoom_step", [1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else -1])


func _on_cut_changed(n: int) -> void:
	Q.vcall("set_floor_cut", [n])
	_sync_suppress()


# ------------------------------------------------------------------ 뷰에서 오는 것
func _on_view_changed() -> void:
	bubbles.reposition()


func _on_cell_tapped(info: Variant) -> void:
	var d: Dictionary = info if info is Dictionary else {}
	match tool:
		"plant":
			if plant.is_placing():
				plant.on_cell(d)
			else:
				set_tool("")
		"zone":
			zone.on_cell(d)
		"policy", "cards", "record":
			set_tool("")             # 바깥을 누르면 닫힌다
		_:
			_inspect(d)


func _inspect(info: Dictionary) -> void:
	var pos: Variant = info.get("pos")
	if not bool(info.get("hit", false)) or not (pos is Vector3i):
		if tool == "inspect":
			set_tool("")
		return
	if tool != "inspect":
		set_tool("inspect")
	if not inspect.show_cell(pos):
		set_tool("")


# ------------------------------------------------------------------ 거두기
func _on_collect_requested(point_id: int) -> void:
	var args: Dictionary = {} if point_id < 0 else {"point": point_id}
	var r := cmd("collect", args)
	if not bool(r.get("ok", false)):
		var why := str(r.get("reason", ""))
		toast(why if why != "" else "아직 거둘 게 없다.", "warn")
		return
	var bonus: Variant = r.get("bonus")
	if bonus is Dictionary:
		bonus = bonus.get("text", "")
	if bonus is String and bonus != "":
		toast(bonus, "good", "mat")


func _coins_arrived() -> void:
	_money_hold = 0.0
	_refresh_hud()


# ------------------------------------------------------------------ 이벤트
func _on_event(n: String, p: Dictionary) -> void:
	match n:
		"log":
			log_seq += 1
			var tone := str(p.get("tone", ""))
			if tone != "debug" or bool(Data.cfg("debug.enabled", false)):
				toasts.push(str(p.get("text", "")), tone)
		"collected":
			var amount := float(p.get("amount", 0.0))
			if amount >= 1.0:
				_money_hold = 0.6
				bubbles.fly_coins(bubbles.bubble_origin(int(p.get("point", -1))), amount, _coins_arrived)
			if float(p.get("skimmed", 0.0)) >= 1.0:
				toasts.push("그사이 %s 떼였다. 수금원은 모르는 일이라고 한다." % UI.josa(UI.num(p["skimmed"]), "를", "을"), "warn")
			var bonus: Variant = p.get("bonus")
			if bonus is String and bonus != "":
				toasts.push(bonus, "good")
			_bubble_t = 0.0
		"collect_ready":
			_bubble_t = 0.0
		"cards_ready":
			verbs.set_badge("cards", int(p.get("count", _hud.get("cards", 1))))
			verbs.pulse("cards")
			if tool == "cards":
				cards.refresh()
		"unlock":
			_banner_unlock(p)
			if tool == "plant" and not plant.is_placing():
				plant.refresh()
			if tool == "policy":
				policy.refresh()
		"identity_changed":
			_banner_identity(p)
		"power_changed":
			_on_power(int(p.get("level", 0)))
		"hour", "day_started", "day_ended":
			_poll_t = 0.0
		"cell_changed":
			_refresh_soon()
			if tool == "inspect":
				inspect.refresh.call_deferred()
			bubbles.reposition.call_deferred()


func _on_state_replaced() -> void:
	set_tool("")
	toasts.clear()
	rail.set_cut(-1)
	_refresh_all()
	_power = int(_hud.get("power_level", 0))
	_start_session.call_deferred()


## 접속(또는 새 도시) 직후: 자리 비운 사이 요약 → 필요하면 오프닝.
func _start_session() -> void:
	var s: Variant = Game.query("offline_summary")
	if s is Dictionary:
		_show_offline(s)
		return
	if auto_tutorial and not tutorial.running and not tutorial.is_done():
		tutorial.start(tutorial.saved_step())


func _show_offline(s: Dictionary) -> void:
	var hours := float(s.get("hours", 0.0))
	var span := ("%d일 %d시간" % [int(hours) / 24, int(hours) % 24]) if hours >= 24.0 else ("%d시간" % maxi(1, int(round(hours))))
	var lines := UI.to_array(s.get("lines", []))
	if lines.is_empty():
		lines = ["별일 없었다. 그게 제일 수상하다."]
	Modal.notice(modals, {
		"kicker": "자리를 비운 사이",
		"title": "%s이 흘렀다" % span,
		"lines": lines, "bullets": true, "ok_text": "돌아왔다",
	})


func _replay_tutorial() -> void:
	set_tool("")
	tutorial.start(0)


# ------------------------------------------------------------------ 현수막
func _banner_unlock(p: Dictionary) -> void:
	var id := str(p.get("id", ""))
	var entry := _lookup(id)
	var name := str(p.get("name", entry.get("name", id)))
	var desc := str(p.get("desc", entry.get("desc", "")))
	banner.show_banner("새로 열렸다", name, desc, "gold", 3.0, str(entry.get("sign", "")).substr(0, 2))


## 해금된 id 의 표시 이름 찾기: 시설 질의 → (없으면) 콘텐츠 표의 name/desc/sign.
## 규칙 계산이 아니라 이름표 읽기다. 이벤트가 name 을 실어 주면 이 함수는 필요 없다(UI_NOTES 계약 요청).
func _lookup(id: String) -> Dictionary:
	for f in Q.list("facilities"):
		if f is Dictionary and str(f.get("id", "")) == id:
			return f
	for file_name in Data.files:
		var it := Data.item(file_name, id)
		if not it.is_empty() and it.has("name"):
			return it
	return {}


func _banner_identity(p: Dictionary) -> void:
	var title := str(p.get("title", _title))
	var ep := str(p.get("epithet", _epithet))
	if title != _title and title != "":
		var j := UI.josa(title, "라", "이라").substr(title.length())
		banner.show_banner("호칭이 바뀌었다", "이제 사람들은 당신을\n'%s'%s 부른다" % [title, j],
				("「%s」의 %s." % [ep, title]) if ep != "" else "", "red", 3.6)
	elif ep != _epithet and ep != "":
		banner.show_banner("별명이 붙었다", "「%s」" % ep, "사람들이 이곳을 그렇게 부르기 시작했다.", "ink", 3.2)
	_title = title
	_epithet = ep


## 첫 전기: 몇 초간 UI를 거의 지운다. 뷰가 창을 하나씩 켜는 장면이 주인공이다.
func _on_power(level: int) -> void:
	var first := _power == 0 and level > 0
	_power = level
	if not first:
		return
	if _dim_tw != null and _dim_tw.is_valid():
		_dim_tw.kill()
	set_tool("")
	_dim_tw = create_tween()
	_dim_tw.tween_property(chrome, "modulate:a", 0.08, 0.6)
	_dim_tw.parallel().tween_property(toasts, "modulate:a", 0.0, 0.4)
	_dim_tw.tween_interval(4.2)
	_dim_tw.tween_property(chrome, "modulate:a", 1.0, 0.8)
	_dim_tw.parallel().tween_property(toasts, "modulate:a", 1.0, 0.8)
	_dim_tw.tween_callback(func() -> void:
		banner.show_banner("첫 전기", "밤이 밝아졌다", "창이 하나씩 켜진다. 전기세 고지서는 아직 안 왔다.", "gold", 3.0, "電"))
