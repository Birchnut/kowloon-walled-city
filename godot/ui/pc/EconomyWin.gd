class_name EconomyWin
extends PcWindow
## 경제(F2) — 탭: 상품(재고·한도·만듦·씀·수입·수출·순·남은 날) · 일손 · 장부(오늘·평균, 줄마다).
## 현황판이 "무엇이 문제인가"라면 여기는 "숫자 전부". 읽는 것: economy(1초). jump arg: 상품 id → 그 행을 깜박인다, finance/labor → 탭.

var tab := "goods"
var _tabs: Dictionary = {}
var _list: VBoxContainer
var _sig := ""
var _focus := ""
var _show_all := false


func _init() -> void:
	super._init()
	win_id = "economy"
	title_text = "돈"
	key_hint = "F2"
	want_size = Vector2(1300, 820)


func _build(b: VBoxContainer) -> void:
	_tabs = PcWindow.tabs(b, [["goods", "상품", "goods"], ["labor", "일손", "labor"], ["finance", "수지", "economy"]], func(id: String) -> void:
		tab = id
		PcWindow.set_tab(_tabs, id)
		_sig = ""
		_refresh())
	PcWindow.set_tab(_tabs, tab)
	_list = PcWindow.scroll_list(b)


func _on_open(arg: String) -> void:
	if arg in ["goods", "labor", "finance"]:
		tab = arg
	elif arg in ["utilities", "utility"]:
		tab = "goods"
	elif arg != "":
		tab = "goods"
		_focus = arg
	PcWindow.set_tab(_tabs, tab)
	_sig = ""


func _refresh() -> void:
	if body == null:
		return
	var e := Q.dict("economy")
	var sig := JSON.stringify(e).md5_text() + tab + str(_show_all) + _focus
	if sig == _sig:
		return
	_sig = sig
	PcWindow.clear(_list)
	match tab:
		"goods":
			_goods(e)
		"labor":
			_labor(e)
		"finance":
			_finance(e)


func _row(cells: Array, widths: Array, vars: Array = [], tone: Array = []) -> HBoxContainer:
	var h := UI.hbox(10)
	for i in cells.size():
		var l := UI.label(str(cells[i]), vars[i] if i < vars.size() else "LabelSmall")
		l.custom_minimum_size.x = widths[i] if i < widths.size() else 80
		if i > 0:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if i < tone.size() and str(tone[i]) != "":
			l.add_theme_color_override("font_color", UI.tone_col(str(tone[i])))
		h.add_child(l)
	return h


func _goods(e: Dictionary) -> void:
	var w := [200, 120, 90, 90, 90, 90, 100, 100]
	_list.add_child(_row(["상품", "재고 / 한도", "만듦", "씀", "들여옴", "내보냄", "하루 순", "남은 날"], w, ["LabelMute", "LabelMute", "LabelMute", "LabelMute", "LabelMute", "LabelMute", "LabelMute", "LabelMute"]))
	var cat := ""
	var hidden := 0
	for g: Variant in UI.to_array(e.get("goods", [])):
		var gd := UI.to_dict(g)
		var idle := float(gd.get("stock", 0)) <= 0.0 and float(gd.get("prod", 0)) <= 0.0 and float(gd.get("cons", 0)) <= 0.0 and float(gd.get("imp", 0)) <= 0.0
		if idle and not _show_all and str(gd.get("id", "")) != _focus:
			hidden += 1
			continue
		if str(gd.get("cat_name", "")) != cat:
			cat = str(gd.get("cat_name", ""))
			_list.add_child(UI.label(cat, "LabelGold"))
		var net := float(gd.get("net", 0))
		var dl := float(gd.get("days_left", -1))
		var st := str(gd.get("state", "ok"))
		var r := _row([str(gd.get("name", "")), "%s / %s" % [UI.num(gd.get("stock", 0)), UI.num(gd.get("cap", 0))], UI.dec(gd.get("prod", 0)), UI.dec(gd.get("cons", 0)), UI.dec(gd.get("imp", 0)), UI.dec(gd.get("exp", 0)),
			("+" if net >= 0 else "") + UI.dec(net), UI.days(dl) if dl >= 0 else "—"], w, [], ["bad" if st == "bad" else ("warn" if st == "warn" else ""), "", "", "", "", "", "good" if net >= 0 else "bad", "bad" if dl >= 0 and dl < 1 else ""])
		var p := UI.panel("PanelRow")
		p.add_child(r)
		_list.add_child(p)
		if str(gd.get("id", "")) == _focus:
			var tw := create_tween().set_loops(4)
			tw.tween_property(p, "modulate", Color(1.7, 1.5, 0.8), 0.18)
			tw.tween_property(p, "modulate", Color.WHITE, 0.25)
			(func() -> void: (_list.get_parent() as ScrollContainer).ensure_control_visible(p)).call_deferred()
	_focus = ""
	if hidden > 0 or _show_all:
		var b := PcButton.make(("아직 쓰지 않는 상품 %d개 보기" % hidden) if not _show_all else "쓰지 않는 상품 접기", "", "", "ButtonFlat")
		b.pressed.connect(func() -> void:
			_show_all = not _show_all
			_sig = ""
			_refresh())
		_list.add_child(b)


func _labor(e: Dictionary) -> void:
	var w := [200, 120, 120, 120]
	_list.add_child(_row(["계층", "있음", "필요", "남음"], w, ["LabelMute", "LabelMute", "LabelMute", "LabelMute"]))
	for l: Variant in UI.to_array(e.get("labor", [])):
		var ld := UI.to_dict(l)
		var sp := float(ld.get("spare", 0))
		_list.add_child(_row([str(ld.get("name", "")), UI.num(ld.get("have", 0)), UI.num(ld.get("need", 0)), ("+" if sp >= 0 else "") + UI.num(sp)], w, [], ["", "", "", "good" if sp >= 0 else "bad"]))
	_list.add_child(UI.label("일손 = 일하는 나이의 주민. 시설은 필요한 계층의 일손이 다 차야 제대로 돈다. 모자라면 그 계층 집을 늘리거나 승급을 늦춘다.", "LabelDim", true))
	var tiers := UI.to_array(e.get("tiers", []))
	if not tiers.is_empty():
		PcWindow.section(_list, "계층")
		var w2 := [200, 120, 120, 120, 120]
		_list.add_child(_row(["계층", "인구", "집", "만실", "승급 가능"], w2, ["LabelMute", "LabelMute", "LabelMute", "LabelMute", "LabelMute"]))
		for t: Variant in tiers:
			var td := UI.to_dict(t)
			_list.add_child(_row([str(td.get("name", "")), UI.big(td.get("pop", 0)), UI.num(td.get("houses", 0)), UI.num(td.get("full_houses", 0)), UI.num(td.get("upgradable", 0))], w2))


func _finance(e: Dictionary) -> void:
	var f := UI.to_dict(e.get("finance", {}))
	var today := UI.to_dict(f.get("today", {}))
	var avg := UI.to_dict(f.get("avg", {}))
	var w := [240, 160, 160]
	_list.add_child(_row(["항목", "오늘(지금까지)", "최근 평균/일"], w, ["LabelMute", "LabelMute", "LabelMute"]))
	for ln: Variant in UI.to_array(f.get("lines", [])):
		var ld := UI.to_dict(ln)
		var id := str(ld.get("id", ""))
		var a := float(today.get(id, 0))
		var b := float(avg.get(id, ld.get("amount", 0)))
		_list.add_child(_row([str(ld.get("name", "")), UI.won_signed(a), UI.won_signed(b)], w, [], ["", "good" if a >= 0 else "bad", "good" if b >= 0 else "bad"]))
	var tn := float(today.get("net", 0))
	var an := float(avg.get("net", f.get("net", 0)))
	_list.add_child(HSeparator.new())
	_list.add_child(_row(["순수입", UI.won_signed(tn), UI.won_signed(an)], w, ["LabelBold", "LabelBold", "LabelBold"], ["", "good" if tn >= 0 else "bad", "good" if an >= 0 else "bad"]))
