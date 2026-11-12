class_name KeepWin
extends PcWindow
## 성채(F6) — 탭: 목표 · 정책 · 연구 · 기록 · 설정 · 디버그(config debug.enabled 일 때).
##  목표: 지금 목표(방법 줄·가는 버튼) → 앞으로 → 끝낸 것.   정책: 칸 수, 켜고 끄기, 잠긴 이유, 단속 위험.
##  연구: 갈래별 마디(상태색·비용·날), 시작/그만두기(절반 환불 확인).   기록: log{n:60}.
##  설정: 창/전체 화면(F11) · UI 크기 100/125/150% · 시작 배속 · 저장(Ctrl+S) · 이어 하기 · 새 도시 · 오프닝 다시.
##  디버그: 돈·자재·하루·전부 해금·불·병·층 채우기.

var tab := "goals"
var _tabs: Dictionary = {}
var _list: VBoxContainer
var _sig := ""


func _init() -> void:
	super._init()
	win_id = "keep"
	title_text = "성채"
	key_hint = "F6"
	want_size = Vector2(1200, 820)


func _build(b: VBoxContainer) -> void:
	var items := [["goals", "목표", "goal"], ["policies", "정책", "keep"], ["research", "연구", "tier"], ["log", "기록", "economy"], ["settings", "설정", "gear"]]
	if bool(Data.cfg("debug.enabled", false)):
		items.append(["debug", "디버그", "warn"])
	_tabs = PcWindow.tabs(b, items, func(id: String) -> void:
		tab = id
		PcWindow.set_tab(_tabs, id)
		_sig = ""
		_refresh())
	PcWindow.set_tab(_tabs, tab)
	_list = PcWindow.scroll_list(b)


func _on_open(arg: String) -> void:
	var a: String = {"policy": "policies", "goal": "goals"}.get(arg, arg)
	if _tabs.has(a):
		tab = a
	PcWindow.set_tab(_tabs, tab)
	_sig = ""


func _refresh() -> void:
	if body == null:
		return
	var d: Variant = {}
	match tab:
		"goals":
			d = Q.dict("goals")
		"policies":
			d = [Q.dict("policies"), Q.dict("vice")]
		"research":
			d = Q.dict("research")
		"log":
			d = Q.raw("log", {"n": 60})
		_:
			d = [tab, Settings.ui_scale(), Settings.is_fullscreen(), Game.speed]
	var sig := JSON.stringify(d).md5_text() + tab
	if sig == _sig:
		return
	_sig = sig
	PcWindow.clear(_list)
	match tab:
		"goals":
			_goals(d)
		"policies":
			_policies(d[0], d[1])
		"research":
			_research(d)
		"log":
			_log(d)
		"settings":
			_settings()
		"debug":
			_debug()


func _w(t: String, v: String = "LabelSmall", w: float = 1080.0) -> Label:
	var l := UI.label(t, v, true)
	l.custom_minimum_size.x = w
	return l


# ------------------------------------------------------------------ 목표
func _goals(g: Dictionary) -> void:
	set_subtitle("%s · %s  —  %d / %d" % [str(g.get("grade_name", "")), str(g.get("title", "")), int(g.get("done_count", 0)), int(g.get("total", 0))])
	var steps := UI.to_array(g.get("steps", []))
	var cur: Dictionary = {}
	var next: Array = []
	var done: Array = []
	for s: Variant in steps:
		var sd := UI.to_dict(s)
		if bool(sd.get("done", false)):
			done.append(sd)
		elif cur.is_empty():
			cur = sd
		else:
			next.append(sd)
	if not cur.is_empty():
		var p := UI.panel("PanelGold")
		_list.add_child(p)
		var v := UI.vbox(6)
		p.add_child(v)
		v.add_child(UI.label("지금", "LabelGoldSmall"))
		v.add_child(_w(str(cur.get("text", "")), "LabelBold", 1040))
		var h := UI.hbox(8)
		v.add_child(h)
		h.add_child(PcWindow.bar(float(cur.get("progress", 0)), "ok", 400, 12))
		h.add_child(UI.label(UI.pct(cur.get("progress", 0)), "LabelSmall"))
		var tip := LeftColumn.goal_tip(str(cur.get("id", "")), str(cur.get("text", "")))
		if str(tip.get("tip", "")) != "":
			v.add_child(_w(str(tip.get("tip", "")), "LabelDim", 1040))
		var rw: Array = []
		for r: Variant in UI.to_array(cur.get("rewards", [])):
			rw.append(str(r))
		if not rw.is_empty():
			v.add_child(_w("보상 " + " · ".join(rw), "LabelGoldSmall", 1040))
		var bh := UI.hbox(6)
		v.add_child(bh)
		for b: Variant in UI.to_array(tip.get("go", [])):
			var bd := UI.to_dict(b)
			var btn := PcButton.make(str(bd.get("label", "")), "right", "", "Button")
			var j: Variant = bd.get("jump", {})
			btn.pressed.connect(func() -> void:
				close()
				ui.jump(j))
			bh.add_child(btn)
	if not next.is_empty():
		PcWindow.section(_list, "앞으로")
		for s2: Dictionary in next:
			_list.add_child(_w("· " + str(s2.get("text", "")), "LabelSmall"))
	if not done.is_empty():
		PcWindow.section(_list, "끝낸 것")
		done.reverse()
		for s3: Dictionary in done:
			var l := _w("✓ %s%s" % [str(s3.get("text", "")), ("  (%d일째)" % int(s3.get("done_day", 0))) if int(s3.get("done_day", 0)) > 0 else ""], "LabelDim")
			_list.add_child(l)


# ------------------------------------------------------------------ 정책
func _policies(p: Dictionary, vice: Dictionary) -> void:
	var sl := UI.to_dict(p.get("slots", {}))
	set_subtitle("정책 자리 %d / %d" % [int(sl.get("used", 0)), int(sl.get("max", 0))])
	if float(vice.get("heat", 0)) > 0.0 or not UI.to_array(vice.get("items", [])).is_empty():
		var vp := UI.panel("PanelRed")
		_list.add_child(vp)
		var vv := UI.vbox(4)
		vp.add_child(vv)
		var hh := UI.hbox(8)
		vv.add_child(hh)
		hh.add_child(Picto.make("warn", UI.col("red_hi")))
		hh.add_child(UI.label("단속 위험 %d / 100" % int(float(vice.get("heat", 0))), "LabelRed"))
		hh.add_child(PcWindow.bar(float(vice.get("heat", 0)) / 100.0, "bad", 240, 10))
		vv.add_child(_w("하루 +%s, 저절로 -%s. 높으면 음성 시설이 단속으로 닫힌다." % [UI.dec(vice.get("gain_per_day", 0)), UI.dec(vice.get("decay_per_day", 0))], "LabelSmall", 1040))
	for it: Variant in UI.to_array(p.get("items", [])):
		var d := UI.to_dict(it)
		var row := UI.panel("PanelRow")
		_list.add_child(row)
		var h := UI.hbox(10)
		row.add_child(h)
		var on := bool(d.get("on", false))
		var locked := bool(d.get("locked", false))
		var b := PcButton.make("켜짐" if on else "꺼짐", "check" if on else "minus", "", "ButtonToggle")
		b.toggle_mode = true
		b.min_w = 96
		b.set_pressed_no_signal(on)
		b.disabled = locked
		var id := str(d.get("id", ""))
		b.pressed.connect(func() -> void:
			var r: Dictionary = ui.cmd("policy_set", {"id": id, "on": not on})
			if not bool(r.get("ok", false)):
				ui.toast(str(r.get("reason", "")), "warn")
			_sig = ""
			_refresh())
		h.add_child(b)
		var v := UI.vbox(2)
		h.add_child(v)
		v.add_child(UI.label(str(d.get("name", "")) + (("  유지비 %s/일" % UI.won(d.get("upkeep", 0))) if float(d.get("upkeep", 0)) > 0 else ""), "LabelBold"))
		v.add_child(_w(str(d.get("desc", "")), "LabelDim", 900))
		if locked:
			v.add_child(_w("잠김 — " + str(d.get("lock_hint", "")), "LabelRedSmall", 900))


# ------------------------------------------------------------------ 연구
func _research(r: Dictionary) -> void:
	set_subtitle("연구 %d / %d" % [int(r.get("done", 0)), int(r.get("total", 0))])
	var act := UI.to_dict(r.get("active", {}))
	if not bool(r.get("can", true)):
		_list.add_child(_w(str(r.get("hint", "공부방이 있어야 연구한다.")), "LabelRedSmall"))
	if str(act.get("id", "")) != "":
		var p := UI.panel("PanelGold")
		_list.add_child(p)
		var h := UI.hbox(10)
		p.add_child(h)
		h.add_child(UI.label("연구 중: %s — %s 남음" % [str(act.get("name", "")), UI.days(act.get("left_days", 0))], "LabelBold"))
		var cb := PcButton.make("그만두기", "close", "", "ButtonRed")
		cb.pressed.connect(func() -> void:
			ui.confirm({"title": "연구를 그만둔다", "lines": ["들인 돈의 절반을 돌려받는다."], "ok_text": "그만둔다", "danger": true}, func() -> void:
				ui.cmd("research_cancel", {})
				_sig = ""
				_refresh()))
		h.add_child(cb)
	var branches := {}
	var order: Array = []
	for n: Variant in UI.to_array(r.get("nodes", [])):
		var nd := UI.to_dict(n)
		var br := str(nd.get("branch_name", nd.get("branch", "")))
		if not branches.has(br):
			branches[br] = []
			order.append(br)
		branches[br].append(nd)
	var cols := UI.hbox(10)
	_list.add_child(cols)
	for br2: String in order:
		var cv := UI.vbox(6)
		cv.custom_minimum_size.x = 350
		cols.add_child(cv)
		cv.add_child(UI.label(br2, "LabelGold"))
		for nd2: Dictionary in branches[br2]:
			cv.add_child(_node(nd2))


func _node(n: Dictionary) -> Control:
	var st := str(n.get("state", "locked"))
	var p := UI.panel({"done": "PanelJade", "active": "PanelGoldFill", "ready": "PanelRowHi"}.get(st, "PanelRow"))
	var v := UI.vbox(3)
	p.add_child(v)
	v.add_child(UI.label(str(n.get("name", "")), "LabelBold"))
	v.add_child(_w(str(n.get("desc", "")), "LabelDim", 320))
	var h := UI.hbox(8)
	v.add_child(h)
	h.add_child(UI.label("%s · %s" % [UI.won(n.get("cost", 0)), UI.days(n.get("days", 0))], "LabelSmall"))
	if st == "ready":
		var b := PcButton.make("시작", "play", "", "ButtonGold")
		b.min_h = 30
		var id := str(n.get("id", ""))
		var can := Q.can_full("research_start", {"id": id})
		b.disabled = not bool(can.get("ok", false))
		TipLayer.set_tip(b, "연구 시작\n%s" % str(can.get("reason", "")))
		b.pressed.connect(func() -> void:
			var r: Dictionary = ui.cmd("research_start", {"id": id})
			if not bool(r.get("ok", false)):
				ui.toast(str(r.get("reason", "")), "warn")
			_sig = ""
			_refresh())
		h.add_child(b)
	elif st == "locked" and str(n.get("lock_hint", "")) != "":
		v.add_child(_w("잠김 — " + str(n.get("lock_hint", "")), "LabelMute", 320))
	elif st == "done":
		h.add_child(UI.label("끝", "LabelJadeSmall"))
	return p


# ------------------------------------------------------------------ 기록
func _log(d: Variant) -> void:
	set_subtitle("최근 기록")
	var lines := UI.to_array(d)
	if lines.is_empty():
		_list.add_child(UI.label("기록이 없다.", "LabelDim"))
	for ln: Variant in lines:
		var t := str(UI.to_dict(ln).get("text", ln)) if ln is Dictionary else str(ln)
		var tone := str(UI.to_dict(ln).get("tone", "")) if ln is Dictionary else ""
		if tone == "debug" and not bool(Data.cfg("debug.enabled", false)):
			continue
		var l := _w(t, "LabelSmall")
		if tone != "":
			l.add_theme_color_override("font_color", UI.tone_col(tone))
		_list.add_child(l)


# ------------------------------------------------------------------ 설정
func _settings() -> void:
	set_subtitle("설정")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("v_separation", 10)
	g.add_theme_constant_override("h_separation", 20)
	_list.add_child(g)
	g.add_child(UI.label("화면", "LabelDim"))
	var fs := PcButton.make("전체 화면" if not Settings.is_fullscreen() else "창으로", "eye", "F11", "Button")
	fs.pressed.connect(func() -> void:
		Settings.toggle_fullscreen()
		_sig = "")
	g.add_child(fs)
	g.add_child(UI.label("UI 크기", "LabelDim"))
	var sh := UI.hbox(4)
	g.add_child(sh)
	for s: float in Settings.SCALES:
		var b := PcButton.make("%d%%" % int(round(s * 100.0)), "", "", "ButtonToggle")
		b.toggle_mode = true
		b.set_pressed_no_signal(absf(Settings.ui_scale() - s) < 0.01)
		b.pressed.connect(func() -> void:
			Settings.set_ui_scale(s)
			_sig = "")
		sh.add_child(b)
	g.add_child(UI.label("시작 배속", "LabelDim"))
	var sp := UI.hbox(4)
	g.add_child(sp)
	for v: Array in [[1.0, "×1"], [2.0, "×2"], [4.0, "×4"]]:
		var b2 := PcButton.make(v[1], "", "", "ButtonToggle")
		b2.toggle_mode = true
		var spd: float = v[0]
		b2.set_pressed_no_signal(absf(float(UISettings.get_value("start_speed", 1.0)) - spd) < 0.01)
		b2.pressed.connect(func() -> void:
			UISettings.set_value("start_speed", spd)
			_sig = "")
		sp.add_child(b2)
	g.add_child(UI.label("저장", "LabelDim"))
	var sv := UI.hbox(6)
	g.add_child(sv)
	var sb := PcButton.make("지금 저장", "save", "Ctrl+S", "Button")
	sb.pressed.connect(func() -> void: Settings.quick_save(ui))
	sv.add_child(sb)
	var lb := PcButton.make("저장한 곳에서 이어 하기", "play", "", "Button")
	lb.pressed.connect(func() -> void:
		ui.confirm({"title": "저장한 곳으로 돌아간다", "lines": ["저장하지 않은 진행은 사라진다."], "ok_text": "돌아간다"}, func() -> void:
			if not Game.load_game():
				ui.toast("저장이 없다.", "warn")))
	sv.add_child(lb)
	g.add_child(UI.label("새로", "LabelDim"))
	var nh := UI.hbox(6)
	g.add_child(nh)
	var ng := PcButton.make("새 도시", "plus", "", "ButtonRed")
	ng.pressed.connect(func() -> void:
		ui.confirm({"kicker": "새 도시", "title": "처음부터 다시 한다", "lines": ["지금 도시는 지워진다. 되돌릴 수 없다."], "ok_text": "새로 시작", "danger": true}, func() -> void:
			Game.delete_save()
			Game.new_game()))
	nh.add_child(ng)
	var tb := PcButton.make("오프닝 다시 보기", "help", "", "Button")
	tb.pressed.connect(func() -> void:
		close()
		ui.tutorial.start(0))
	nh.add_child(tb)
	# 소리: 버스 넷의 크기(바로 user://audio.cfg 에 저장 — AudioDirector) + 끄고 켜기
	for row: Array in [["master", "전체 소리"], ["sfx", "효과음"], ["ambience", "도시 소리"], ["music", "음악"]]:
		g.add_child(UI.label(row[1], "LabelDim"))
		var sh2 := UI.hbox(8)
		g.add_child(sh2)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(320, 28)
		sl.focus_mode = Control.FOCUS_NONE
		sl.value = Sfx.get_volume(row[0])
		var vl := UI.label("%d%%" % int(round(sl.value * 100.0)), "LabelSmall")
		vl.custom_minimum_size.x = 60
		var bus: String = row[0]
		sl.value_changed.connect(func(v: float) -> void:
			Sfx.set_volume(bus, v)
			vl.text = "%d%%" % int(round(v * 100.0)))
		sl.drag_ended.connect(func(_ch: bool) -> void: Sfx.play("click"))
		sh2.add_child(sl)
		sh2.add_child(vl)
	g.add_child(UI.label("켜고 끄기", "LabelDim"))
	var th := UI.hbox(6)
	g.add_child(th)
	var toggles: Array = [
		["전체 끔", func() -> bool: return Sfx.is_muted(), func(on: bool) -> void: Sfx.mute(on)],
		["효과음 끔", func() -> bool: return Sfx.muted, func(on: bool) -> void: Sfx.muted = on],
		["도시 소리 끔", func() -> bool: return not Sfx.ambience_enabled(), func(on: bool) -> void: Sfx.set_ambience_enabled(not on)],
		["음악 끔", func() -> bool: return not Sfx.music_enabled(), func(on: bool) -> void: Sfx.set_music_enabled(not on)]]
	for t: Array in toggles:
		var tb2 := PcButton.make(t[0], "", "", "ButtonToggle")
		tb2.toggle_mode = true
		var getter: Callable = t[1]
		var setter: Callable = t[2]
		tb2.set_pressed_no_signal(bool(getter.call()))
		tb2.toggled.connect(func(on: bool) -> void: setter.call(on))
		th.add_child(tb2)


# ------------------------------------------------------------------ 디버그
func _debug() -> void:
	set_subtitle("디버그 (config debug.enabled)")
	var f := HFlowContainer.new()
	f.custom_minimum_size.x = 1080
	_list.add_child(f)
	var ops: Array = [["₩+1,000", {"op": "add_money", "n": 1000}], ["₩+10,000", {"op": "add_money", "n": 10000}],
		["세 자재 +20", "mats"], ["고물 +50", {"op": "add_stock", "good": "scrap", "n": 50}], ["설비 부품 +5", {"op": "add_stock", "good": "parts", "n": 5}],
		["하루 건너뛰기", {"op": "skip_days", "n": 1}], ["전부 해금", {"op": "unlock_all"}], ["거래처 공개", {"op": "reveal_partners"}],
		["불 내기(가운데 집)", "fire"], ["병 퍼뜨리기", "outbreak"], ["지금 층 채우기", "fill"]]
	for o: Array in ops:
		var b := PcButton.make(o[0], "", "", "Button")
		var a: Variant = o[1]
		b.pressed.connect(func() -> void: _dbg(a))
		f.add_child(b)
	_list.add_child(_w("불·병·층 채우기는 v4 시뮬의 debug 명령(start_fire / start_outbreak / fill_floor)을 부른다. 이 클론의 v3 시뮬에 없으면 이유가 토스트로 나온다. ", "LabelDim"))


func _dbg(a: Variant) -> void:
	var r: Dictionary = {}
	if a is Dictionary:
		r = ui.cmd("debug", a)
	else:
		match str(a):
			"mats":
				for g: String in ["wood", "metal", "concrete"]:
					r = ui.cmd("debug", {"op": "add_stock", "good": g, "n": 20})
			"fire", "outbreak":
				var pos: Variant = ui.inspector.selected_pos
				if not (pos is Vector3i):
					var g2 := UI.to_dict(ui.hud.get("grid", {}))
					pos = Vector3i(int(g2.get("w", 12)) / 2, int(g2.get("h", 12)) / 2, 0)
				r = ui.cmd("debug", {"op": "start_fire" if str(a) == "fire" else "start_outbreak", "pos": pos})
			"fill":
				var v := Q.view()
				var z := maxi(0, int(v.get("floor_cut")) if v != null and v.get("floor_cut") != null else 0)
				r = ui.cmd("debug", {"op": "fill_floor", "z": z, "count": 9999})
	if not bool(r.get("ok", false)):
		ui.toast("디버그: " + str(r.get("reason", "안 됨")), "warn")
	else:
		ui.toast("디버그: 됨", "dim")
