class_name KeepSheet
extends Screen
## KeepSheet — 성채. 탭: 목표 / 정책 / 연구 / 기록.
##  목표: query("goals") — 등급·호칭, 단계마다 조건 문장·진행·보상(지금 단계는 막대로)
##  정책: query("policies") — 칸 수, 켜고 끄기(policy_set), 잠긴 것은 이유
##  연구: query("research") — 갈래 셋을 세로 줄로, 마디 카드(상태색), 시작(research_start), 진행 중 남은 날
##  기록: query("log") + 설정(배속 ×1/×4/×16, 멈춤, 감상 시간, 오프닝 다시 보기, 새 도시) + 디버그(debug.enabled 일 때)
## arg: goals | policy | research | log

const TABS := [{"id": "goals", "name": "목표"}, {"id": "policy", "name": "정책"}, {"id": "research", "name": "연구"}, {"id": "log", "name": "기록"}]
const SPEEDS := [1.0, 4.0, 16.0]

var tab: String = "goals"
var research_source: Callable = func() -> Dictionary: return Q.dict("research")
var policy_source: Callable = func() -> Dictionary: return Q.dict("policies")
var _seg: Segmented
var _scroll: DragScroll
var _body: VBoxContainer
var _sig: String = ""
var _scrub: float = -1.0


func _init() -> void:
	super._init()
	make_sheet("성채", 0.66, 360.0)
	_seg = Segmented.new()
	_seg.small_text = true
	_seg.chip_min = Vector2(56, 50)
	_seg.set_options(TABS, tab)
	_seg.selected.connect(func(id: String) -> void:
		tab = id
		_sig = ""
		refresh()
		_scroll.scroll_to(0.0))
	sheet.body.add_child(_seg)
	var sb := Screen.scroll_body(6)
	_scroll = sb[0]
	_body = sb[1]
	sheet.body.add_child(_scroll)
	poll_sec = 1.0


func _on_open(a: String, _was: bool) -> void:
	if a in ["goals", "policy", "research", "log"]:
		tab = a
	elif a in ["policies"]:
		tab = "policy"
	_seg.set_value(tab)
	_sig = ""
	if ui != null:
		ui.clear_keep_badge()
	refresh()
	_scroll.scroll_to(0.0)


func _on_closed() -> void:
	if _scrub >= 0.0:
		_scrub = -1.0
		Q.vcall("set_time_override", [-1.0])


func refresh() -> void:
	var d: Variant
	match tab:
		"goals":
			d = Q.dict("goals")
		"policy":
			d = policy_source.call()
		"research":
			d = research_source.call()
		_:
			d = Q.list("log", {"n": 40})
	var sig := tab + JSON.stringify(d) + str(Game.speed) + str(Game.paused)
	if sig == _sig:
		return
	_sig = sig
	Screen.clear(_body)
	match tab:
		"goals":
			_goals(d)
		"policy":
			_policies(d)
		"research":
			_research(d)
		_:
			_log(d)
	_scroll.adopt_buttons()


# ------------------------------------------------------------------ 목표
func _goals(g: Dictionary) -> void:
	var head := UI.panel("PanelDeep")
	var hv := UI.vbox(2)
	head.add_child(hv)
	hv.add_child(UI.label("성채 등급 · %s" % str(g.get("grade_name", "")), "LabelGoldSmall"))
	var t := str(g.get("title", ui.title() if ui != null else "대장"))
	hv.add_child(UI.label("사람들은 당신을 '%s'%s 부른다" % [t, UI.josa(t, "라", "이라").substr(t.length())], "LabelBold", true))
	_body.add_child(head)
	var steps := UI.to_array(g.get("steps", []))
	if steps.is_empty():
		_body.add_child(UI.label("목표가 아직 없다.", "LabelMute"))
		return
	var current_found := false
	for s: Variant in steps:
		if not (s is Dictionary):
			continue
		var done := bool(s.get("done", false))
		var cur := not done and not current_found
		if cur:
			current_found = true
		var p := UI.panel("PanelInset" if not cur else "PanelGold")
		var v := UI.vbox(4)
		p.add_child(v)
		var h := UI.hbox(6)
		v.add_child(h)
		h.add_child(UI.icon_rect("check" if done else ("chev_r" if cur else "lock"), UI.col("jade_hi") if done else (UI.col("gold") if cur else UI.col("mute"))))
		var tl := UI.label(str(s.get("text", "")), "LabelBold" if cur else "LabelSmall", true)
		if not cur and not done:
			tl.add_theme_color_override("font_color", UI.col("dim"))
		h.add_child(tl)
		if cur:
			var pr := float(s.get("progress", 0))
			var r := UI.hbox(6)
			v.add_child(r)
			r.add_child(RatioBar.make(pr, "gold", 10))
			r.add_child(UI.label("%d%%" % int(pr * 100.0), "LabelGoldSmall"))
		var rw := UI.to_array(s.get("rewards", []))
		if not rw.is_empty() and not done:
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 4)
			flow.add_theme_constant_override("v_separation", 4)
			flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(flow)
			for x: Variant in rw:
				flow.add_child(UI.tag(str(x), "gold" if str(x).begins_with("성채 등급") else ""))
		if done:
			p.modulate = Color(1, 1, 1, 0.6)
		_body.add_child(p)


# ------------------------------------------------------------------ 정책
func _policies(d: Dictionary) -> void:
	var items := UI.to_array(d.get("items", []))
	var sl := UI.to_dict(d.get("slots", {}))
	_body.add_child(Screen.kv("정책 칸", "%d / %d" % [int(sl.get("used", 0)), int(sl.get("max", 0))], "LabelGoldSmall"))
	if items.is_empty():
		_body.add_child(UI.label("정책은 아직 없다. 세입자가 늘면 첫 칸이 열린다.", "LabelMute", true))
		return
	for it: Variant in items:
		if not (it is Dictionary):
			continue
		var p := UI.panel("PanelInset")
		var h := UI.hbox(8)
		p.add_child(h)
		var v := UI.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UI.label(str(it.get("name", "")), "LabelBold"))
		v.add_child(UI.label(str(it.get("desc", "")), "LabelSmall", true))
		var locked := bool(it.get("locked", false))
		if locked:
			var l := UI.label("잠김 — " + str(it.get("lock_hint", "")), "LabelSmall", true)
			l.add_theme_color_override("font_color", UI.col("gold"))
			v.add_child(l)
			p.modulate = Color(1, 1, 1, 0.6)
		var on := bool(it.get("on", false))
		var c := Chip.chip("켬" if on else "끔", "", on)
		c.min_size = Vector2(72, 52)
		c.disabled = locked
		var id := str(it.get("id", ""))
		c.pressed.connect(func() -> void:
			var r: Dictionary = ui.cmd("policy_set", {"id": id, "on": c.button_pressed})
			if not bool(r.get("ok", false)):
				ui.toast(str(r.get("reason", "")), "warn")
			_sig = ""
			refresh())
		h.add_child(c)
		_body.add_child(p)


# ------------------------------------------------------------------ 연구
func _research(d: Dictionary) -> void:
	var act := UI.to_dict(d.get("active", {}))
	if not act.is_empty() and str(act.get("id", "")) != "":
		var p := UI.panel("PanelGold")
		var v := UI.vbox(2)
		p.add_child(v)
		v.add_child(UI.label("연구 중 · %s" % str(act.get("name", "")), "LabelBold"))
		v.add_child(UI.label("%s일 남음(경제 시간)" % str(snappedf(float(act.get("left_days", 0)), 0.1)), "LabelSmall"))
		_body.add_child(p)
	elif str(d.get("hint", "")) != "":
		_body.add_child(UI.label(str(d["hint"]), "LabelMute", true))
	var nodes := UI.to_array(d.get("nodes", []))
	if nodes.is_empty():
		return
	var by := {}
	var order: Array = []
	for n: Variant in nodes:
		if n is Dictionary:
			var b := str(n.get("branch_name", n.get("branch", "")))
			if not by.has(b):
				by[b] = []
				order.append(b)
			by[b].append(n)
	var cols := UI.hbox(6)
	_body.add_child(cols)
	var can_start := bool(d.get("can", false))
	for b: String in order:
		var col := UI.vbox(4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		var hd := UI.label(b, "LabelGoldSmall")
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(hd)
		for n: Dictionary in by[b]:
			col.add_child(_node_card(n, can_start))


func _node_card(n: Dictionary, can_start: bool) -> Control:
	var st := str(n.get("state", "locked"))
	var p := UI.panel({"done": "PanelInset", "active": "PanelGold", "ready": "PanelDeep"}.get(st, "PanelInset"))
	var v := UI.vbox(2)
	p.add_child(v)
	var nm := UI.label(str(n.get("name", "")), "LabelSmall", true)
	nm.add_theme_color_override("font_color", {"done": UI.col("jade_hi"), "active": UI.col("gold_hi"), "ready": UI.col("paper")}.get(st, UI.col("mute")))
	v.add_child(nm)
	var desc := str(n.get("desc", ""))
	if desc != "" and st != "done":
		v.add_child(UI.label(desc, "LabelDim", true))
	match st:
		"done":
			v.add_child(UI.label("끝", "LabelDim"))
		"active":
			v.add_child(UI.label("연구 중", "LabelGoldSmall"))
		"ready":
			var b := PixelButton.make("₩%s · %s일" % [UI.num(float(n.get("cost", 0))), str(n.get("days", 0))], "", "ButtonJade" if can_start else "")
			b.small = true
			b.min_size = Vector2(56, 48)
			b.disabled = not can_start
			var id := str(n.get("id", ""))
			b.pressed.connect(func() -> void:
				var r: Dictionary = ui.cmd("research_start", {"id": id})
				if not bool(r.get("ok", false)):
					ui.toast(str(r.get("reason", "")), "warn")
				_sig = ""
				refresh())
			v.add_child(b)
		_:
			var lh := str(n.get("lock_hint", ""))
			if lh != "":
				v.add_child(UI.label(lh, "LabelMute", true))
	return p


# ------------------------------------------------------------------ 기록 + 설정
func _log(rows: Array) -> void:
	_settings()
	_body.add_child(Screen.section("일지"))
	if rows.is_empty():
		_body.add_child(UI.label("별일 없었다. 그게 제일 수상하다.", "LabelMute"))
	var rs := rows.duplicate()
	rs.reverse()
	for r: Variant in rs:
		if not (r is Dictionary):
			continue
		var tone := str(r.get("tone", ""))
		if tone == "debug" and not bool(Data.cfg("debug.enabled", false)):
			continue
		var h := UI.hbox(8)
		var t := UI.label("%d일 %s" % [int(r.get("day", 0)), UI.clock(float(r.get("hour", 0)))], "LabelMute")
		t.custom_minimum_size.x = 112
		t.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(t)
		var l := UI.label(str(r.get("text", "")), "LabelSmall", true)
		if tone != "":
			l.add_theme_color_override("font_color", UI.tone_col(tone))
		h.add_child(l)
		_body.add_child(h)


func _settings() -> void:
	_body.add_child(Screen.section("시간"))
	var sp := UI.hbox(6)
	_body.add_child(sp)
	var seg := Segmented.new()
	seg.small_text = true
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var opts: Array = []
	for s: float in SPEEDS:
		opts.append({"id": str(int(s)), "name": "×%d" % int(s)})
	seg.set_options(opts, str(int(Game.speed)) if Game.speed in SPEEDS else "")
	seg.selected.connect(func(id: String) -> void:
		Game.speed = float(id)
		_sig = "")
	sp.add_child(seg)
	var pause := Chip.chip("멈춤", "pause", Game.paused)
	pause.small = true
	pause.min_size = Vector2(88, 56)
	pause.pressed.connect(func() -> void:
		Game.paused = pause.button_pressed
		_sig = "")
	sp.add_child(pause)
	var sc := UI.hbox(8)
	_body.add_child(sc)
	sc.add_child(UI.label("감상 시간", "LabelSmall"))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.value = _scrub if _scrub >= 0.0 else Game.time_of_day()
	sl.custom_minimum_size = Vector2(160, 48)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v: float) -> void:
		_scrub = v
		Q.vcall("set_time_override", [v]))
	sc.add_child(sl)
	var rb := PixelButton.make("지금", "", "")
	rb.small = true
	rb.pressed.connect(func() -> void:
		_scrub = -1.0
		Q.vcall("set_time_override", [-1.0])
		_sig = "")
	sc.add_child(rb)
	var row := UI.hbox(6)
	_body.add_child(row)
	var tut := PixelButton.make("오프닝 다시 보기", "play", "")
	tut.small = true
	tut.pressed.connect(func() -> void: ui.replay_tutorial())
	row.add_child(tut)
	row.add_child(UI.spacer(true))
	var ng := PixelButton.make("새 도시", "wreck", "ButtonRed")
	ng.small = true
	ng.pressed.connect(func() -> void:
		ui.confirm({"kicker": "새 도시", "title": "이 성채를 버리고 새로 시작한다", "lines": ["지금 도시는 돌아오지 않는다.", "저장도 지운다."],
			"ok_text": "새로 시작", "danger": true}, func() -> void:
				Game.delete_save()
				Game.new_game()))
	row.add_child(ng)
	if bool(Data.cfg("debug.enabled", false)):
		_debug()


func _debug() -> void:
	_body.add_child(Screen.section("디버그"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(flow)
	var ops: Array = [["₩+1000", {"op": "add_money", "n": 1000}], ["목재 +20", {"op": "add_stock", "good": "wood", "n": 20}],
		["철제 +20", {"op": "add_stock", "good": "metal", "n": 20}], ["콘크리트 +20", {"op": "add_stock", "good": "concrete", "n": 20}],
		["하루 건너뛰기", {"op": "skip_days", "n": 1}], ["탐험 +10분", {"op": "skip_real", "seconds": 600}],
		["탐험 +1시간", {"op": "skip_real", "seconds": 3600}], ["전부 해금", {"op": "unlock_all"}], ["거래처 공개", {"op": "reveal_partners"}]]
	for o: Array in ops:
		var b := PixelButton.make(o[0], "", "ButtonGhost")
		b.small = true
		b.min_size = Vector2(112, 52)
		var a: Dictionary = o[1]
		b.pressed.connect(func() -> void:
			var r: Dictionary = ui.cmd("debug", a)
			ui.toast(("디버그: " + str(o[0])) if bool(r.get("ok", false)) else str(r.get("reason", "")), "dim"))
		flow.add_child(b)
	flow.add_child(UI.label("디버그는 config debug.enabled 로 끈다", "LabelMute"))
	_scroll.adopt_buttons()
