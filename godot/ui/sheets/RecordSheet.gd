class_name RecordSheet
extends Control
## RecordSheet — 기록. 두 쪽: [기록] 도시의 이름·별명·명물 딱지, 숫자 몇 개, 날짜별 일지 / [설정] 배속·멈춤·감상 모드·새 게임·디버그.
##
## 데이터: query("hud")(title, epithet, tags?) / query("stats")?(있으면) / query("log",{n}).
## 설정이 만지는 것: Game.speed, Game.paused, view.set_time_override, Game.delete_save()+new_game(), cmd("debug").

signal finished
signal replay_tutorial

const LOG_N := 50
const SPEEDS := [1.0, 4.0, 16.0]

var ui: Node = null
var sheet: BottomSheet
var _tabs: Segmented
var _scroll: DragScroll
var _page: VBoxContainer
var _tab: String = "log"
var _scrub: HSlider
var _scrub_label: Label
var _scrub_on: bool = false
var bottom_gap: float = 78.0:
	set(v):
		bottom_gap = v
		if sheet != null:
			sheet.bottom_gap = v


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet = BottomSheet.new()
	sheet.title = "기록"
	sheet.height_ratio = 0.7
	sheet.min_height = 420.0
	add_child(sheet)
	_tabs = Segmented.new()
	_tabs.equal_width = false
	_tabs.set_options([{"id": "log", "name": "일지"}, {"id": "settings", "name": "설정"}], _tab)
	_tabs.selected.connect(func(id: String) -> void:
		_tab = id
		refresh())
	for id in ["log", "settings"]:
		_tabs.button(id).min_size = Vector2(92, 40)
	sheet.header.add_child(_tabs)
	sheet.header.add_child(UI.spacer(false, Vector2(60, 0)))
	_scroll = DragScroll.new()
	sheet.body.add_child(_scroll)
	_page = UI.vbox(10)
	_scroll.set_content(_page)
	sheet.closed.connect(func() -> void: finished.emit())


func _ready() -> void:
	sheet.bottom_gap = bottom_gap


func open(tab: String = "") -> void:
	if tab != "":
		_tab = tab
		_tabs.set_value(tab)
	refresh()
	sheet.open()


func close() -> void:
	if sheet.is_open:
		sheet.close()


func is_open() -> bool:
	return sheet.is_open


func refresh() -> void:
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	_scrub = null
	if _tab == "settings":
		_build_settings()
	else:
		_build_log()
	_scroll.adopt_buttons()
	_scroll.scroll_to(0.0)


# ------------------------------------------------------------------ 일지
func _build_log() -> void:
	var hud := Q.dict("hud")
	var title := str(hud.get("title", "대장"))
	var ep := str(hud.get("epithet", ""))
	# 문패
	var plate := UI.panel("PanelGold")
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(plate)
	var ph := UI.hbox(12)
	plate.add_child(ph)
	ph.add_child(SignTile.make("城寨"))
	var pv := UI.vbox(4)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pv)
	pv.add_child(UI.label(ep if ep != "" else "아직 이름 없는 땅", "LabelHead", true))
	var who := UI.hbox(6)
	pv.add_child(who)
	who.add_child(UI.label("사람들은 당신을", "LabelDim"))
	who.add_child(UI.tag(title, "gold"))
	who.add_child(UI.label(UI.josa(title, "라", "이라").substr(title.length()) + " 부른다.", "LabelDim"))
	var tags := UI.to_array(hud.get("tags", []))
	if not tags.is_empty():
		var flow := HFlowContainer.new()
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pv.add_child(flow)
		for t in tags:
			flow.add_child(UI.tag(str(t), ""))
	else:
		pv.add_child(UI.label("명물이 아직 없다. 뭐든 많아지면 그게 이름이 된다.", "LabelMute", true))

	# 숫자 몇 개
	var stats: Array = []
	var qs: Variant = Q.raw("stats")
	if qs is Array:
		stats = qs
	elif qs is Dictionary:
		for k in qs:
			stats.append({"label": str(k), "value": str(qs[k])})
	if stats.is_empty() and not hud.is_empty():
		stats = [
			{"label": "날짜", "value": "%d일차" % int(hud.get("day", 1))},
			{"label": "인구", "value": UI.num(hud.get("population", 0))},
			{"label": "전기", "value": "있음" if int(hud.get("power_level", 0)) > 0 else "없음"},
		]
	if not stats.is_empty():
		var grid := HFlowContainer.new()
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_theme_constant_override("h_separation", 8)
		_page.add_child(grid)
		for s in stats:
			if not (s is Dictionary):
				continue
			var cell := UI.panel("PanelInset")
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var ch := UI.hbox(8)
			cell.add_child(ch)
			ch.add_child(UI.label(str(s.get("label", "")), "LabelDim"))
			ch.add_child(UI.label(str(s.get("value", "")), "LabelSmall"))
			grid.add_child(cell)

	# 일지: 최근 날짜가 위
	var lines := Q.list("log", {"n": LOG_N})
	if lines.is_empty():
		var e := UI.label("아직 적을 일이 없었다.", "LabelDim")
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_page.add_child(e)
		return
	var cur_day := -1
	var box: VBoxContainer = null
	for i in range(lines.size() - 1, -1, -1):
		var l: Variant = lines[i]
		if not (l is Dictionary):
			continue
		var day := int(l.get("day", 0))
		if day != cur_day:
			cur_day = day
			var dh := UI.hbox(8)
			_page.add_child(dh)
			dh.add_child(UI.tag("%d일차" % day, "red"))
			var rule := HSeparator.new()
			rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dh.add_child(rule)
			box = UI.vbox(4)
			_page.add_child(box)
		var row := UI.hbox(8)
		box.add_child(row)
		var tm := UI.label(UI.clock(float(l.get("hour", 0.0))), "LabelMute")
		tm.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		tm.custom_minimum_size = Vector2(54, 0)
		row.add_child(tm)
		var tx := UI.label(str(l.get("text", "")), "LabelSmall", true)
		var tone := str(l.get("tone", ""))
		if tone != "":
			tx.add_theme_color_override("font_color", UI.tone_col(tone))
		row.add_child(tx)


# ------------------------------------------------------------------ 설정
func _section(text: String) -> void:
	var h := UI.hbox(8)
	_page.add_child(h)
	h.add_child(UI.icon_rect("diamond", UI.col("red")))
	h.add_child(UI.label(text, "LabelGold"))


func _build_settings() -> void:
	# 배속
	_section("시간")
	var row := UI.hbox(8)
	_page.add_child(row)
	var seg := Segmented.new()
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cur := "1"
	var opts: Array = []
	for s in SPEEDS:
		var id := str(int(s))
		opts.append({"id": id, "name": "×" + id})
		if is_equal_approx(Game.speed, s):
			cur = id
	seg.set_options(opts, cur)
	seg.selected.connect(func(id: String) -> void:
		Game.speed = float(id)
		if ui != null:
			ui.toast("시간 ×%s" % id, "dim"))
	row.add_child(seg)
	var pause := PixelButton.make("멈춤", "pause", "ButtonChip")
	pause.toggle_mode = true
	pause.button_pressed = Game.paused
	pause.min_size = Vector2(120, UI.TOUCH)
	pause.toggled.connect(func(on: bool) -> void:
		Game.paused = on
		if ui != null:
			ui.toast("도시가 멈췄다. 비도 멈췄다." if on else "다시 흐른다.", "dim"))
	row.add_child(pause)

	# 감상 모드
	_section("감상 모드")
	_page.add_child(UI.label("시간대를 골라 구경한다. 도시 시계는 그대로 간다.", "LabelDim", true))
	var sr := UI.hbox(10)
	_page.add_child(sr)
	_scrub_label = UI.label("끔", "LabelSmall")
	_scrub_label.custom_minimum_size = Vector2(64, 0)
	sr.add_child(_scrub_label)
	_scrub = HSlider.new()
	_scrub.min_value = 0.0
	_scrub.max_value = 24.0
	_scrub.step = 0.25
	_scrub.value = Game.time_of_day() * 24.0
	_scrub.custom_minimum_size = Vector2(0, UI.TOUCH)
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.focus_mode = Control.FOCUS_NONE
	_scrub.value_changed.connect(_on_scrub)
	sr.add_child(_scrub)
	var off := PixelButton.make("끄기", "", "")
	off.min_size = Vector2(84, UI.TOUCH)
	off.pressed.connect(_scrub_off)
	sr.add_child(off)
	if _scrub_on:
		_scrub_label.text = UI.clock(_scrub.value)

	# 게임
	_section("게임")
	var gr := UI.hbox(8)
	_page.add_child(gr)
	var tut := PixelButton.make("오프닝 다시 보기", "", "")
	tut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut.pressed.connect(func() -> void: replay_tutorial.emit())
	gr.add_child(tut)
	var ng := PixelButton.make("새 게임", "", "ButtonRed")
	ng.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ng.pressed.connect(_ask_new_game)
	gr.add_child(ng)

	# 디버그
	if bool(Data.cfg("debug.enabled", false)):
		_section("디버그")
		var flow := HFlowContainer.new()
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(flow)
		for d in [
			["돈 +500", {"op": "add_money", "amount": 500}],
			["자재 +50", {"op": "add_materials", "amount": 50}],
			["6시간 뒤", {"op": "skip_hours", "hours": 6}],
			["하루 뒤", {"op": "skip_hours", "hours": 24}],
			["전부 해금", {"op": "unlock_all"}],
		]:
			var b := PixelButton.make(d[0], "", "")
			b.pressed.connect(_debug.bind(d[1]))
			flow.add_child(b)
	_page.add_child(UI.label("구룡성채 v0.2 — 숫자는 전부 임시다.", "LabelMute"))


func _on_scrub(v: float) -> void:
	_scrub_on = true
	_scrub_label.text = UI.clock(v)
	Q.vcall("set_time_override", [fposmod(v, 24.0) / 24.0])


func _scrub_off() -> void:
	_scrub_on = false
	if _scrub_label != null:
		_scrub_label.text = "끔"
	Q.vcall("set_time_override", [-1.0])


func _ask_new_game() -> void:
	if ui == null:
		return
	ui.confirm({
		"title": "전부 밀고 새로 시작",
		"kicker": "새 게임",
		"lines": ["지금 성채는 사라진다. 저장도 지운다.", "사람들은 다른 데서 또 쌓겠지만, 여기는 아니다."],
		"ok_text": "밀어 버린다", "danger": true,
	}, func() -> void:
		_scrub_off()
		Game.delete_save()
		Game.new_game())


func _debug(args: Dictionary) -> void:
	if ui == null:
		return
	var r: Dictionary = ui.cmd("debug", args)
	if not bool(r.get("ok", false)):
		ui.toast("디버그 실패: %s" % str(r.get("reason", "?")), "dim")
	else:
		ui.toast("디버그: %s" % str(args.get("op", "")), "dim")
