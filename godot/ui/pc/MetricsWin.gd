class_name MetricsWin
extends PcWindow
## 현황판(Tab) — Jin: "숫자가 흩어져 있어 읽기 어렵다" → 모든 수급을 한 장에.
##  왼쪽 큰 표: 묶음(물·전기 / 먹을 것 / 물건 / 서비스 / 위험)마다 행 = 상태 · 이름 · 공급 · 수요 · 막대 · 남은 날 · 무엇을 하면 되나 · →(그 자리로)
##  오른쪽: 계층별 일손 · 계층 표(인구·집·만실·승급 가능·입주 중) · 재정 요약 · 위험 범위.
## 읽는 것: metrics(1초). 판정·문장은 전부 질의 값 — UI는 정렬·색만 한다.

const GROUPS := [["utility", "물·전기", "water"], ["food", "먹을 것", "food"], ["goods", "물건", "goods"], ["service", "서비스·범위", "service"], ["hazard", "위험", "fire"]]

var _filter := "all"
var _filter_btns: Dictionary = {}
var _table: VBoxContainer
var _side: VBoxContainer
var _summary: Label
var _sig := ""
var _focus_row := ""
var _row_nodes: Dictionary = {}
var _sections: Dictionary = {}
var _m: Dictionary = {}


func _init() -> void:
	super._init()
	win_id = "metrics"
	title_text = "장부"
	key_hint = "Tab"
	want_size = Vector2(1560, 880)
	poll = 1.0


func _build(b: VBoxContainer) -> void:
	var top := UI.hbox(8)
	b.add_child(top)
	_filter_btns = PcWindow.tabs(top, [["all", "전부", ""], ["bad", "문제만", "warn"]], func(id: String) -> void:
		_filter = id
		PcWindow.set_tab(_filter_btns, id)
		_sig = ""
		_refresh())
	PcWindow.set_tab(_filter_btns, _filter)
	_summary = UI.label("", "LabelSmall")
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_summary)
	top.add_child(UI.label("행을 누르면 그 자리로 · 숫자는 하루 기준", "LabelMute"))
	var h := UI.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(h)
	var lv := UI.vbox(4)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.size_flags_stretch_ratio = 2.0
	h.add_child(lv)
	lv.add_child(_header_row())
	lv.add_child(HSeparator.new())
	_table = PcWindow.scroll_list(lv)
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rs.custom_minimum_size.x = 430
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(rs)
	_side = UI.vbox(10)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(_side)


func _cols() -> Array:
	return [26, 190, 80, 80, 100, 76, 70]


func _header_row() -> Control:
	var r := UI.hbox(8)
	var c := _cols()
	for i in [0, 1, 2, 3, 6, 4, 5]:
		var l := UI.label(["", "품목", "들어옴", "나감", "", "남은 날", "재고"][i], "LabelMute")
		l.custom_minimum_size.x = c[i]
		if i in [2, 3, 5, 6]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(l)
	var last := UI.label("장부지기의 말", "LabelMute")
	last.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(last)
	return r


func _on_open(arg: String) -> void:
	_focus_row = arg
	_sig = ""


func _refresh() -> void:
	if body == null:
		return
	_m = Q.dict("metrics")
	var sig := JSON.stringify(_m).md5_text() + _filter + _focus_row
	if sig == _sig:
		return
	_sig = sig
	var rows := UI.to_array(_m.get("rows", []))
	var nbad := 0
	var nwarn := 0
	for r: Variant in rows:
		var st := str(UI.to_dict(r).get("state", ""))
		if st == "bad":
			nbad += 1
		elif st == "warn":
			nwarn += 1
	_summary.text = "위험 %d · 주의 %d · 전부 %d줄" % [nbad, nwarn, rows.size()]
	_summary.add_theme_color_override("font_color", UI.pcol("red_hi") if nbad > 0 else (UI.pcol("gold") if nwarn > 0 else UI.pcol("jade_hi")))
	set_subtitle("빨강 %d · 노랑 %d" % [nbad, nwarn] if nbad + nwarn > 0 else "모두 괜찮다")
	_build_table(rows)
	_build_side()
	if _focus_row != "":
		_scroll_to.call_deferred(_focus_row)


func _build_table(rows: Array) -> void:
	PcWindow.clear(_table)
	_row_nodes.clear()
	for g: Array in GROUPS:
		var list: Array = []
		for r: Variant in rows:
			var rd := UI.to_dict(r)
			if str(rd.get("group", "")) != g[0]:
				continue
			if _filter == "bad" and str(rd.get("state", "ok")) in ["ok", "off"]:
				continue
			list.append(rd)
		if list.is_empty():
			continue
		# 나쁜 것 먼저
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _rank(str(a.get("state", ""))) < _rank(str(b.get("state", ""))))
		var gh := UI.hbox(6)
		var gm := UI.margin(0, 8, 0, 2)
		gm.add_child(gh)
		_table.add_child(gm)
		gh.add_child(Picto.make(g[2], UI.pcol("red")))
		gh.add_child(UI.label(g[1], "LabelGold"))
		_row_nodes[g[0]] = gm
		for rd2: Dictionary in list:
			var row := _row(rd2)
			var wrap := VBoxContainer.new()
			wrap.add_theme_constant_override("separation", 0)
			wrap.add_child(row)
			var ln := HSeparator.new()
			ln.add_theme_constant_override("separation", 1)
			wrap.add_child(ln)
			_table.add_child(wrap)
			_row_nodes[str(rd2.get("id", ""))] = wrap
	if _table.get_child_count() == 0:
		_table.add_child(UI.label("문제가 없다." if _filter == "bad" else "아직 보여 줄 것이 없다.", "LabelDim"))


static func _rank(st: String) -> int:
	return {"bad": 0, "warn": 1, "ok": 2, "off": 3}.get(st, 2)


func _row(r: Dictionary) -> Control:
	var st := str(r.get("state", "ok"))
	var b := Button.new()
	b.theme_type_variation = "ButtonFlat"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 36)
	var h := UI.hbox(8)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 4
	b.add_child(h)
	var c := _cols()
	var dot := Picto.make("dot" if st != "off" else "minus", UI.pstate(st))
	dot.custom_minimum_size.x = c[0]
	h.add_child(dot)
	var nm := UI.label(str(r.get("name", "")), "LabelBody" if st == "bad" else "LabelSmall")
	nm.custom_minimum_size.x = c[1]
	nm.clip_text = true
	if st == "bad":
		nm.add_theme_color_override("font_color", UI.pcol("red_hi"))
	h.add_child(nm)
	var unit := str(r.get("unit", ""))
	for v: Variant in [r.get("supply", 0), r.get("demand", 0)]:
		# 꺼진 위험(불·병이 아직 안 켜짐)은 숫자 대신 "—"
		var l := UI.label("—" if st == "off" else UI.dec(v) + ("%" if unit == "%" else ""), "LabelSmall")
		l.custom_minimum_size.x = c[2]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	var stv: Variant = r.get("stock")
	var stl := UI.label(UI.dec(stv) if (stv is float or stv is int) else "", "LabelDim")
	stl.custom_minimum_size.x = c[6]
	stl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(stl)
	var no_demand := (float(r.get("demand", 0)) <= 0.0 and str(r.get("group", "")) != "hazard") or st == "off"
	var bar := PcWindow.bar(0.0 if no_demand else float(r.get("ratio", 0.0)), st, c[4], 12)
	if no_demand:
		b.modulate.a = 0.6
	h.add_child(bar)
	var dl: Variant = r.get("days_left")
	var dls := UI.days(dl) if (dl is float or dl is int) else "—"
	var dll := UI.label(dls, "LabelSmall")
	dll.custom_minimum_size.x = c[5]
	dll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if (dl is float or dl is int) and float(dl) < 1.0:
		dll.add_theme_color_override("font_color", UI.pcol("red_hi"))
	h.add_child(dll)
	var hint := UI.label(str(r.get("hint", "")), "LabelSmall" if st in ["bad", "warn"] else "LabelDim")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.clip_text = true
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(hint)
	var j: Variant = r.get("jump", {})
	var go := Picto.make("right", UI.pcol("mute"))
	h.add_child(go)
	b.pressed.connect(func() -> void:
		if ui != null:
			ui.jump(j))
	TipLayer.set_tip(b, func() -> String:
		var s := "%s\n공급 %s%s · 수요 %s%s" % [str(r.get("name", "")), UI.dec(r.get("supply", 0)), unit, UI.dec(r.get("demand", 0)), unit]
		if r.get("stock") != null:
			s += " · 재고 %s" % UI.dec(r.get("stock", 0))
		s += "\n남은 날 %s\n%s\n누르면: %s" % [dls, str(r.get("hint", "")), LeftColumn._jump_word(Q.norm_jump(j))]
		return s)
	return b


func _scroll_to(id: String) -> void:
	var n: Variant = _row_nodes.get(id)
	if n is Control:
		var sc := _table.get_parent() as ScrollContainer
		if sc != null:
			sc.ensure_control_visible(n)
		_flash(n)
	elif _sections.has(id):
		_flash(_sections[id])
	_focus_row = ""


func _flash(c: Control) -> void:
	var tw := create_tween().set_loops(3)
	tw.tween_property(c, "modulate", Color(1.6, 1.4, 0.8), 0.18)
	tw.tween_property(c, "modulate", Color.WHITE, 0.25)


# ------------------------------------------------------------------ 오른쪽
func _build_side() -> void:
	PcWindow.clear(_side)
	_sections.clear()
	_sections["labor"] = _sec_labor()
	_sections["tiers"] = _sec_tiers()
	_sections["finance"] = _sec_finance()
	_sections["hazards"] = _sec_hazards()


func _box(title: String, pic: String) -> VBoxContainer:
	if _side.get_child_count() > 0:
		_side.add_child(HSeparator.new())
	var v := UI.vbox(4)
	_side.add_child(v)
	var h := UI.hbox(6)
	v.add_child(h)
	h.add_child(Picto.make(pic, UI.pcol("red")))
	h.add_child(UI.label(title, "LabelGold"))
	return v


func _sec_labor() -> Control:
	var v := _box("일손", "labor")
	var g := GridContainer.new()
	g.columns = 4
	v.add_child(g)
	for t: String in ["계층", "있음 / 필요", "", "남음"]:
		g.add_child(UI.label(t, "LabelMute"))
	for l: Variant in UI.to_array(_m.get("labor", [])):
		var ld := UI.to_dict(l)
		var have := float(ld.get("have", 0))
		var need := float(ld.get("need", 0))
		if have <= 0.0 and need <= 0.0:
			continue
		var nm := UI.label(str(ld.get("name", "")), "LabelSmall")
		nm.add_theme_color_override("font_color", UI.ptier(int(ld.get("tier", 0))))
		nm.custom_minimum_size.x = 120
		g.add_child(nm)
		g.add_child(UI.label("%s / %s" % [UI.num(have), UI.num(need)], "LabelSmall"))
		var st := "ok" if have >= need else ("warn" if have >= need * 0.8 else "bad")
		g.add_child(PcWindow.bar(have / maxf(need, 1.0), st, 110, 10))
		var spare := float(ld.get("spare", have - need))
		var sl := UI.label(("+" if spare >= 0 else "") + UI.num(spare), "LabelSmall")
		sl.add_theme_color_override("font_color", UI.pstate("ok" if spare >= 0 else "bad"))
		g.add_child(sl)
	if g.get_child_count() <= 4:
		v.add_child(UI.label("아직 일하는 사람이 없다.", "LabelDim"))
	return v


func _sec_tiers() -> Control:
	var v := _box("계층", "tier")
	var g := GridContainer.new()
	g.columns = 6
	v.add_child(g)
	for t: String in ["계층", "인구", "집", "만실", "승급", "입주 중"]:
		g.add_child(UI.label(t, "LabelMute"))
	var any := false
	for t2: Variant in UI.to_array(_m.get("tiers", [])):
		var td := UI.to_dict(t2)
		if int(td.get("houses", 0)) <= 0 and int(td.get("pop", 0)) <= 0:
			continue
		any = true
		var nm := UI.label(str(td.get("name", "")), "LabelSmall")
		nm.add_theme_color_override("font_color", UI.ptier(int(td.get("tier", 0))))
		nm.custom_minimum_size.x = 110
		g.add_child(nm)
		g.add_child(UI.label(UI.big(td.get("pop", 0)), "LabelSmall"))
		g.add_child(UI.label(UI.num(td.get("houses", 0)), "LabelSmall"))
		g.add_child(UI.label(UI.num(td.get("full", td.get("full_houses", 0))), "LabelSmall"))
		var up := int(td.get("upgradable", 0))
		if up > 0:
			var ub := PcButton.make("%d채" % up, "up", "", "ButtonJade")
			ub.min_h = 28
			var tier := int(td.get("tier", 0))
			ub.pressed.connect(func() -> void: ui.upgrade_all(tier))
			TipLayer.set_tip(ub, "일괄 승급\n지금 올릴 수 있는 %s 집 %d채." % [str(td.get("name", "")), up])
			g.add_child(ub)
		else:
			g.add_child(UI.label("0", "LabelDim"))
		g.add_child(UI.label(UI.num(td.get("arriving", 0)), "LabelSmall"))
	if not any:
		v.add_child(UI.label("아직 집이 없다. H로 칠한다.", "LabelDim"))
	return v


func _sec_finance() -> Control:
	var v := _box("재정 (하루)", "coin")
	var f := UI.to_dict(_m.get("finance", {}))
	var h := UI.hbox(14)
	v.add_child(h)
	for it: Array in [["들어옴", f.get("income", 0), "good"], ["나감", f.get("cost", 0), "bad"], ["순수입", f.get("net", 0), "good" if float(f.get("net", 0)) >= 0 else "bad"]]:
		var c := UI.vbox(0)
		h.add_child(c)
		c.add_child(UI.label(it[0], "LabelMute"))
		var l := UI.label(UI.won_signed(it[1]) if it[0] != "나감" else UI.won(absf(float(it[1]))), "LabelBold")
		l.add_theme_color_override("font_color", UI.ptone(it[2]))
		c.add_child(l)
	var g := GridContainer.new()
	g.columns = 2
	v.add_child(g)
	for ln: Variant in UI.to_array(f.get("lines", [])):
		var ld := UI.to_dict(ln)
		if absf(float(ld.get("amount", 0))) < 0.5:
			continue
		var nl := UI.label(str(ld.get("name", "")), "LabelDim")
		nl.custom_minimum_size.x = 200
		g.add_child(nl)
		var al := UI.label(UI.won_signed(ld.get("amount", 0)), "LabelSmall")
		al.add_theme_color_override("font_color", UI.pcol("jade_hi") if float(ld.get("amount", 0)) >= 0 else UI.pcol("red_hi"))
		g.add_child(al)
	var more := PcButton.make("돈 자세히", "economy", "F2", "ButtonFlat")
	more.min_h = 28
	more.pressed.connect(func() -> void: ui.open_window("economy", "finance"))
	v.add_child(more)
	return v


func _sec_hazards() -> Control:
	var v := _box("위험", "fire")
	for hz: Variant in UI.to_array(_m.get("hazards", [])):
		var hd := UI.to_dict(hz)
		var on := bool(hd.get("on", false))
		var h := UI.hbox(8)
		v.add_child(h)
		var pic := "fire" if str(hd.get("id", "")) == "fire" else "disease"
		h.add_child(Picto.make(pic, UI.pcol("red_hi") if on else UI.pcol("mute"), 2, UI.pcol("gold_hi")))
		var nm := UI.label(str(hd.get("name", "")), "LabelBold")
		nm.custom_minimum_size.x = 50
		h.add_child(nm)
		if on:
			var cov := float(hd.get("covered_pct", 0.0))
			h.add_child(UI.label("범위 %s" % UI.pct(cov), "LabelSmall"))
			h.add_child(PcWindow.bar(cov, "ok" if cov >= 0.9 else ("warn" if cov >= 0.6 else "bad"), 90, 10))
			var act := int(hd.get("active", 0))
			var al := UI.label(("지금 %d곳" % act) if act > 0 else "조용함", "LabelSmall")
			al.add_theme_color_override("font_color", UI.pcol("red_hi") if act > 0 else UI.pcol("jade_hi"))
			h.add_child(al)
		else:
			h.add_child(UI.label("꺼짐", "LabelDim"))
		var lb := PcButton.make("렌즈", "eye", "", "ButtonFlat")
		lb.min_h = 28
		var j: Variant = hd.get("jump", {})
		lb.pressed.connect(func() -> void:
			ui.jump(j)
			close())
		h.add_child(lb)
		var tl := UI.label(str(hd.get("text", "")), "LabelDim", true)
		tl.custom_minimum_size.x = 380
		v.add_child(tl)
	if v.get_child_count() <= 1:
		v.add_child(UI.label("아직 위험이 없다.", "LabelDim"))
	return v
