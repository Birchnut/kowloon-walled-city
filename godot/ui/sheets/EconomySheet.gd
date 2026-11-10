class_name EconomySheet
extends Screen
## EconomySheet — 경제(긴 시트). 탭: 상품 / 노동력 / 물·전기 / 장부. 전부 query("economy") (+ 없으면 hud 로 버팀).
##  상품: 분류별 행 — 재고/한도 막대, +생산 −소비(±교역) = 순/일, 남은 날, 상태색. 쓰지 않는 상품은 접어 둔다.
##  노동력: 계층별 있음/필요/남음 막대 + 계층 요약(인구·집·만실·승급 가능 → 일괄 승급)
##  물·전기: 공급 vs 수요 막대와 공급원
##  장부: 오늘 / 최근 평균, 세수·유지비·교역·건설·음성을 줄마다 따로, 순수지.
## arg: 상품 id(그 행을 번쩍) | labor | utilities | water | power | finance

const TABS := [{"id": "goods", "name": "상품"}, {"id": "labor", "name": "노동력"}, {"id": "utilities", "name": "물·전기"}, {"id": "finance", "name": "장부"}]

var tab: String = "goods"
var _seg: Segmented
var _scroll: DragScroll
var _body: VBoxContainer
var _flash_id: String = ""
var _rows: Dictionary = {}
var _sig: String = ""
var _show_idle: bool = false


func _init() -> void:
	super._init()
	make_sheet("경제", 0.68, 360.0)
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
	var sb := Screen.scroll_body(4)
	_scroll = sb[0]
	_body = sb[1]
	sheet.body.add_child(_scroll)
	poll_sec = 1.0


func _on_open(a: String, _was: bool) -> void:
	_flash_id = ""
	match a:
		"", "goods":
			pass
		"labor":
			tab = "labor"
		"utilities", "water", "power":
			tab = "utilities"
		"finance":
			tab = "finance"
		_:
			tab = "goods"
			_flash_id = a
	_seg.set_value(tab)
	_sig = ""
	refresh()
	_scroll.scroll_to(0.0)
	if _flash_id != "":
		_scroll_to_flash.call_deferred()


func refresh() -> void:
	var e := Q.dict("economy")
	var hud: Dictionary = ui.hud if ui != null else {}
	var sig := tab + JSON.stringify(e).md5_text() + str(_show_idle)
	if sig == _sig:
		return
	_sig = sig
	Screen.clear(_body)
	_rows.clear()
	match tab:
		"goods":
			_goods(UI.to_array(e.get("goods", [])))
		"labor":
			var lab := UI.to_array(e.get("labor", []))
			if lab.is_empty():
				lab = UI.to_array(hud.get("labor", []))
			_labor(lab, UI.to_array(e.get("tiers", [])))
		"utilities":
			_utilities(UI.to_array(e.get("utilities", [])), hud)
		"finance":
			_finance(UI.to_dict(e.get("finance", {})))
	_scroll.adopt_buttons()


# ------------------------------------------------------------------ 상품
func _goods(rows: Array) -> void:
	if rows.is_empty():
		_body.add_child(UI.label("상품 정보가 없다.", "LabelMute"))
		return
	var by_cat := {}
	var order: Array = []
	var idle: Array = []
	for g: Variant in rows:
		if not (g is Dictionary):
			continue
		var flow := absf(float(g.get("prod", 0))) + absf(float(g.get("cons", 0))) + absf(float(g.get("imp", 0))) + absf(float(g.get("exp", 0)))
		if float(g.get("stock", 0)) < 0.5 and flow < 0.01 and str(g.get("id", "")) != _flash_id:
			idle.append(g)
			continue
		var c := str(g.get("cat_name", g.get("cat", "")))
		if not by_cat.has(c):
			by_cat[c] = []
			order.append(c)
		by_cat[c].append(g)
	for c: String in order:
		_body.add_child(Screen.section(c))
		for g: Dictionary in by_cat[c]:
			var r := _good_row(g)
			_body.add_child(r)
			_rows[str(g.get("id", ""))] = r
	if not idle.is_empty():
		var b := PixelButton.make(("쓰지 않는 상품 %d개 접기" if _show_idle else "아직 쓰지 않는 상품 %d개") % idle.size(), "chev_r", "ButtonGhost")
		b.small = true
		b.pressed.connect(func() -> void:
			_show_idle = not _show_idle
			_sig = ""
			refresh())
		_body.add_child(b)
		if _show_idle:
			for g: Dictionary in idle:
				_body.add_child(_good_row(g))


func _good_row(g: Dictionary) -> Control:
	var st := str(g.get("state", "ok"))
	var tone: String = {"ok": "ok", "full": "paper", "low": "warn", "out": "bad"}.get(st, "ok")
	var v := UI.vbox(0)
	var h := UI.hbox(6)
	v.add_child(h)
	var nm := UI.label(str(g.get("name", "")), "LabelSmall")
	nm.custom_minimum_size.x = 112
	nm.clip_text = true
	h.add_child(nm)
	var cap := maxf(1.0, float(g.get("cap", 1)))
	var stock := float(g.get("stock", 0))
	h.add_child(RatioBar.make(stock / cap, tone, 8))
	var sl := UI.label("%s/%s" % [UI.num(stock), UI.num(cap)], "LabelSmall")
	sl.custom_minimum_size.x = 92
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(sl)
	var net := float(g.get("net", 0))
	var nl := UI.label("%s/일" % _f(net, true), "LabelSmall")
	nl.custom_minimum_size.x = 84
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nl.add_theme_color_override("font_color", UI.col("jade_hi") if net > 0.05 else (UI.col("red_hi") if net < -0.05 else UI.col("dim")))
	h.add_child(nl)
	var parts: Array = []
	if float(g.get("prod", 0)) > 0.0:
		parts.append("생산 +%s" % _f(float(g["prod"])))
	if float(g.get("imp", 0)) > 0.0:
		parts.append("수입 +%s" % _f(float(g["imp"])))
	if float(g.get("cons", 0)) > 0.0:
		parts.append("소비 -%s" % _f(float(g["cons"])))
	if float(g.get("exp", 0)) > 0.0:
		parts.append("수출 -%s" % _f(float(g["exp"])))
	var dl := float(g.get("days_left", -1))
	var tail := ""
	match st:
		"out":
			tail = "바닥났다"
		"full":
			tail = "창고가 가득"
		_:
			if dl >= 0.0:
				tail = "%s일분 남음" % str(snappedf(dl, 0.1))
	if tail != "":
		parts.append(tail)
	if not parts.is_empty():
		var sub := UI.label(" · ".join(parts), "LabelDim")
		sub.clip_text = true
		if st in ["out", "low"]:
			sub.add_theme_color_override("font_color", UI.col("red_hi") if st == "out" else UI.col("gold"))
		var m := UI.margin(8, 0, 0, 2)
		m.add_child(sub)
		v.add_child(m)
	return v


func _f(x: float, sign: bool = false) -> String:
	var s := str(snappedf(absf(x), 0.1))
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	if not sign:
		return s
	return ("+" if x >= 0 else "-") + s


func _scroll_to_flash() -> void:
	await get_tree().process_frame
	if _rows.has(_flash_id):
		var r: Control = _rows[_flash_id]
		_scroll.scroll_to(r.position.y - 40.0)
		var tw := r.create_tween().set_loops(3)
		tw.tween_property(r, "modulate", Color(1.8, 1.6, 0.8), 0.18)
		tw.tween_property(r, "modulate", Color.WHITE, 0.25)


# ------------------------------------------------------------------ 노동력
func _labor(lab: Array, tiers: Array) -> void:
	if lab.is_empty():
		_body.add_child(UI.label("아직 일할 사람이 없다.", "LabelMute"))
	else:
		_body.add_child(Screen.section("계층별 일손 — 있음 / 필요"))
		for l: Variant in lab:
			if not (l is Dictionary):
				continue
			var have := float(l.get("have", 0))
			var need := float(l.get("need", 0))
			if have <= 0.0 and need <= 0.0:
				continue
			var spare := float(l.get("spare", have - need))
			var h := UI.hbox(6)
			_body.add_child(h)
			var nm := UI.label(str(l.get("name", "")), "LabelSmall")
			nm.custom_minimum_size.x = 76
			h.add_child(nm)
			var bar := RatioBar.make(need / maxf(have, 1.0) if have > 0.0 else (1.0 if need > 0.0 else 0.0), "bad" if spare < 0.0 else "ok", 10)
			h.add_child(bar)
			var t := UI.label("%s / %s" % [UI.num(have), UI.num(ceilf(need))], "LabelSmall")
			t.custom_minimum_size.x = 104
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(t)
			var s := UI.label(("남음 %s" % UI.num(spare)) if spare >= 0.0 else ("모자람 %s" % UI.num(-spare)), "LabelSmall")
			s.custom_minimum_size.x = 104
			s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			s.add_theme_color_override("font_color", UI.col("jade_hi") if spare >= 0.0 else UI.col("red_hi"))
			h.add_child(s)
		_body.add_child(UI.label("막대 = 일자리가 일손을 얼마나 쓰는지. 빨강이면 시설이 덜 돈다.", "LabelMute", true))
	if not tiers.is_empty():
		_body.add_child(Screen.section("계층 요약"))
		for t: Variant in tiers:
			if not (t is Dictionary) or int(t.get("houses", 0)) <= 0:
				continue
			var h2 := UI.hbox(8)
			_body.add_child(h2)
			var nm2 := UI.label(str(t.get("name", "")), "LabelSmall")
			nm2.custom_minimum_size.x = 76
			h2.add_child(nm2)
			h2.add_child(UI.label("%s명 · 집 %d채 (만실 %d)" % [UI.num(float(t.get("pop", 0))), int(t.get("houses", 0)), int(t.get("full_houses", 0))], "LabelSmall"))
			h2.add_child(UI.spacer(true))
			var up := int(t.get("upgradable", 0))
			if up > 0:
				var b := PixelButton.make("승급 %d채" % up, "up", "ButtonJade")
				b.small = true
				b.min_size = Vector2(56, 44)
				var tier := int(t.get("tier", 0))
				b.pressed.connect(func() -> void: ui.upgrade_all(tier))
				h2.add_child(b)


# ------------------------------------------------------------------ 물·전기
func _utilities(us: Array, hud: Dictionary) -> void:
	if us.is_empty():
		for id: String in ["water", "power"]:
			var d := UI.to_dict(hud.get(id, {}))
			us.append({"id": id, "name": "물" if id == "water" else "전기", "supply": d.get("supply", 0), "demand": d.get("demand", 0), "sources": []})
	for u: Variant in us:
		if not (u is Dictionary):
			continue
		var sup := float(u.get("supply", 0))
		var dem := float(u.get("demand", 0))
		_body.add_child(Screen.section(str(u.get("name", ""))))
		var short := dem > sup + 0.01
		for pair: Array in [["공급", sup], ["수요", dem]]:
			var h := UI.hbox(6)
			_body.add_child(h)
			var nm := UI.label(pair[0], "LabelSmall")
			nm.custom_minimum_size.x = 56
			h.add_child(nm)
			var mx := maxf(maxf(sup, dem), 1.0)
			h.add_child(RatioBar.make(float(pair[1]) / mx, ("bad" if short else "ok") if pair[0] == "수요" else "paper", 10))
			var t := UI.label("%s/일" % UI.num(float(pair[1])), "LabelSmall")
			t.custom_minimum_size.x = 104
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(t)
		var verdict := UI.label(("모자란다 — 주거부터 받고, 시설은 순서대로 덜 돈다." if short else "넉넉하다.") if dem > 0.0 or sup > 0.0 else "아직 쓰는 곳이 없다.", "LabelSmall", true)
		verdict.add_theme_color_override("font_color", UI.col("red_hi") if short else UI.col("dim"))
		_body.add_child(verdict)
		var src := UI.to_array(u.get("sources", []))
		for s: Variant in src:
			_body.add_child(UI.label("· " + str(s), "LabelDim", true))
		var row := UI.hbox(6)
		_body.add_child(row)
		row.add_child(UI.spacer(true))
		var cat := str(u.get("id", ""))
		var b := PixelButton.make("%s 시설 짓기" % str(u.get("name", "")), "chev_r", "")
		b.small = true
		b.pressed.connect(func() -> void: ui.jump({"screen": "build", "arg": cat}))
		row.add_child(b)


# ------------------------------------------------------------------ 장부
func _finance(f: Dictionary) -> void:
	var lines := UI.to_array(f.get("lines", []))
	var today := UI.to_dict(f.get("today", {}))
	var days := int(f.get("days", 0))
	if lines.is_empty() and today.is_empty():
		_body.add_child(UI.label("아직 장부에 적힌 게 없다. 하루가 지나면 채워진다.", "LabelMute", true))
		return
	var head := UI.hbox(6)
	_body.add_child(head)
	head.add_child(UI.label("항목", "LabelDim"))
	head.add_child(UI.spacer(true))
	for t: String in ["오늘", ("최근 %d일 평균" % days) if days > 0 else "평균"]:
		var l := UI.label(t, "LabelDim")
		l.custom_minimum_size.x = 120
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(l)
	var groups := [["들어온 돈", ["tax", "export", "vice"]], ["나간 돈", ["upkeep", "import"]], ["투자", ["build"]]]
	var by_id := {}
	for l: Variant in lines:
		if l is Dictionary:
			by_id[str(l.get("id", ""))] = l
	var shown := {}
	for g: Array in groups:
		var any := false
		for id: String in g[1]:
			if by_id.has(id) or today.has(id):
				any = true
		if not any:
			continue
		_body.add_child(Screen.section(g[0]))
		for id: String in g[1]:
			if not (by_id.has(id) or today.has(id)):
				continue
			shown[id] = true
			var ln: Dictionary = by_id.get(id, {"name": id, "amount": 0})
			_body.add_child(_fin_row(str(ln.get("name", id)), float(today.get(id, 0.0)), float(ln.get("amount", 0.0))))
	for id: String in by_id:
		if not shown.has(id):
			var ln2: Dictionary = by_id[id]
			_body.add_child(_fin_row(str(ln2.get("name", id)), float(today.get(id, 0.0)), float(ln2.get("amount", 0.0))))
	var sep := ColorRect.new()
	sep.color = UI.col("gold_d")
	sep.custom_minimum_size = Vector2(0, 2)
	_body.add_child(sep)
	# 오늘의 순수지는 질의가 주면 쓰고, 없으면 비워 둔다(UI가 더하지 않는다)
	_body.add_child(_fin_row("순수지", float(today["net"]) if today.has("net") else NAN, float(f.get("net", 0.0)), true))
	_body.add_child(UI.label("세수는 주민에게 판 몫까지 들어 있다(따로 매출을 잡지 않는다). 건설·승급은 운영수지와 따로 본다.", "LabelMute", true))


func _fin_row(nm: String, today: float, avg: float, bold: bool = false) -> Control:
	var h := UI.hbox(6)
	h.add_child(UI.label(nm, "LabelBold" if bold else "LabelSmall"))
	h.add_child(UI.spacer(true))
	for x: float in [today, avg]:
		var l := UI.label("—" if is_nan(x) else (("+₩" if x >= 0.0 else "-₩") + UI.num(absf(x))), "LabelBold" if bold else "LabelSmall")
		l.custom_minimum_size.x = 120
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_color_override("font_color", UI.col("jade_hi") if x > 0.05 else (UI.col("red_hi") if x < -0.05 else UI.col("dim")))
		h.add_child(l)
	return h
