class_name ContractsSheet
extends Screen
## ContractsSheet — 교역(정기 계약). query("contracts") 하나.
##  진행 중: 상대 · 상품 · 수입/수출 · 회당 수량·주기·단가 · 다음 회차 · 최근 결과 · 하루 돈 흐름
##           · 멈춤 토글 · 최소 보유량(수출만, ±10) · 해지(확인)
##  제안: 거래처별로 묶고, 수량 단계 버튼마다 하루 돈 흐름. 모르는 거래처는 잠김 + 어떻게 만나는지.
##  교역소가 없으면 그렇다고 말하고 짓기로 건너뛴다.

const RESERVE_STEP := 10.0

var tab: String = "active"
var _seg: Segmented
var _slots: Label
var _scroll: DragScroll
var _body: VBoxContainer
var _sig: String = ""


func _init() -> void:
	super._init()
	make_sheet("교역", 0.62, 340.0)
	var top := UI.hbox(8)
	sheet.body.add_child(top)
	_seg = Segmented.new()
	_seg.small_text = true
	_seg.chip_min = Vector2(56, 50)
	_seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seg.set_options([{"id": "active", "name": "진행 중"}, {"id": "offers", "name": "제안"}], tab)
	_seg.selected.connect(func(id: String) -> void:
		tab = id
		_sig = ""
		refresh()
		_scroll.scroll_to(0.0))
	top.add_child(_seg)
	_slots = UI.label("", "LabelGoldSmall")
	top.add_child(_slots)
	var sb := Screen.scroll_body(6)
	_scroll = sb[0]
	_body = sb[1]
	sheet.body.add_child(_scroll)
	sheet.header.add_child(UI.label("정기 수출입", "LabelDim"))
	poll_sec = 1.0


func _on_open(a: String, _was: bool) -> void:
	if a == "offers":
		tab = "offers"
	elif a == "active":
		tab = "active"
	else:
		var d := Q.dict("contracts")
		tab = "active" if not UI.to_array(d.get("active", [])).is_empty() else "offers"
	_seg.set_value(tab)
	_sig = ""
	refresh()


func refresh() -> void:
	var d := Q.dict("contracts")
	var sig := tab + JSON.stringify(d)
	if sig == _sig:
		return
	_sig = sig
	var sl := UI.to_dict(d.get("slots", {}))
	_slots.text = "계약 %d/%d자리" % [int(sl.get("used", 0)), int(sl.get("max", 0))]
	var keep_off := _scroll.offset
	Screen.clear(_body)
	if bool(d.get("no_post", false)) and UI.to_array(d.get("active", [])).is_empty():
		_no_post()
	elif tab == "active":
		_active(UI.to_array(d.get("active", [])))
	else:
		if bool(d.get("no_post", false)):
			_no_post()
		_offers(UI.to_array(d.get("offers", [])), bool(d.get("no_post", false)))
	_scroll.adopt_buttons()
	_scroll.scroll_to.call_deferred(keep_off)


func _no_post() -> void:
	var p := UI.panel("PanelGold")
	var v := UI.vbox(6)
	p.add_child(v)
	v.add_child(UI.label("교역소가 없다", "LabelBold"))
	v.add_child(UI.label("교역소를 지으면 계약 자리가 생긴다. 길 건너 도매상은 처음부터 거래해 준다.", "LabelSmall", true))
	var b := PixelButton.make("교역소 지으러 가기", "chev_r", "ButtonJade")
	b.pressed.connect(func() -> void: ui.jump({"screen": "build", "arg": "trade_post"}))
	v.add_child(b)
	_body.add_child(p)


# ------------------------------------------------------------------ 진행 중
func _active(rows: Array) -> void:
	if rows.is_empty():
		_body.add_child(UI.label("맺은 계약이 없다. '제안'에서 고른다.", "LabelMute", true))
		return
	for c: Variant in rows:
		if c is Dictionary:
			_body.add_child(_active_row(c))


func _active_row(c: Dictionary) -> Control:
	var p := UI.panel("PanelInset")
	var v := UI.vbox(4)
	p.add_child(v)
	var id: Variant = c.get("id")
	var exp := str(c.get("dir", "")) == "export"
	var paused := bool(c.get("paused", false))
	var h := UI.hbox(6)
	v.add_child(h)
	h.add_child(UI.tag("수출" if exp else "수입", "gold" if exp else "jade"))
	var nm := UI.label("%s · %s" % [str(c.get("good_name", "")), str(c.get("partner_name", ""))], "LabelBold")
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)
	var pm := float(c.get("per_day_money", 0))
	var ml := UI.label("%s₩%s/일" % ["+" if pm >= 0 else "-", UI.num(absf(pm))], "LabelSmall")
	ml.add_theme_color_override("font_color", UI.col("jade_hi") if pm >= 0 else UI.col("red_hi"))
	h.add_child(ml)
	v.add_child(UI.label("%d개씩 %d시간마다 · 개당 ₩%s · %s" % [int(c.get("qty", 0)), int(c.get("interval_h", 0)), str(snappedf(float(c.get("price", 0)), 0.01)),
		"멈춤" if paused else ("다음 회차 %s시간 뒤" % str(snappedf(float(c.get("next_in_h", 0)), 0.1)))], "LabelDim"))
	var last := str(c.get("last_text", ""))
	if last != "":
		var ll := UI.label("최근: " + last, "LabelSmall", true)
		ll.add_theme_color_override("font_color", UI.col("paper") if bool(c.get("last_ok", true)) else UI.col("red_hi"))
		v.add_child(ll)
	var ctl := UI.hbox(6)
	v.add_child(ctl)
	var pc := Chip.chip("멈춤", "pause", paused)
	pc.small = true
	pc.min_size = Vector2(80, 48)
	pc.pressed.connect(func() -> void: _set_contract(id, {"paused": pc.button_pressed}))
	ctl.add_child(pc)
	if exp:
		var rv := float(c.get("reserve", 0))
		var minus := PixelButton.make("", "minus", "")
		minus.min_size = Vector2(48, 48)
		minus.pressed.connect(func() -> void: _set_contract(id, {"reserve": maxf(0.0, rv - RESERVE_STEP)}))
		ctl.add_child(minus)
		var rl := UI.label("최소 %s" % UI.num(rv), "LabelSmall")
		rl.custom_minimum_size.x = 76
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ctl.add_child(rl)
		var plus := PixelButton.make("", "plus", "")
		plus.min_size = Vector2(48, 48)
		plus.pressed.connect(func() -> void: _set_contract(id, {"reserve": rv + RESERVE_STEP}))
		ctl.add_child(plus)
	ctl.add_child(UI.spacer(true))
	var cx := PixelButton.make("해지", "close", "ButtonRed")
	cx.small = true
	cx.min_size = Vector2(72, 48)
	cx.pressed.connect(func() -> void:
		ui.confirm({"kicker": "계약 해지", "title": "%s 계약을 끝낸다" % str(c.get("good_name", "")),
			"lines": ["%s의 정기 %s이 멈춘다. 벌금은 없다." % [UI.josa(str(c.get("partner_name", "")), "와", "과"), "수출" if exp else "수입"]],
			"ok_text": "해지", "danger": true}, func() -> void:
				var r: Dictionary = ui.cmd("contract_cancel", {"id": id})
				if not bool(r.get("ok", false)):
					ui.toast(str(r.get("reason", "")), "warn")
				_sig = ""
				refresh()))
	ctl.add_child(cx)
	return p


func _set_contract(id: Variant, a: Dictionary) -> void:
	var args := {"id": id}
	args.merge(a)
	var r: Dictionary = ui.cmd("contract_set", args)
	if not bool(r.get("ok", false)):
		ui.toast(str(r.get("reason", "")), "warn")
	_sig = ""
	refresh()


# ------------------------------------------------------------------ 제안
func _offers(rows: Array, no_post: bool) -> void:
	var by := {}
	var order: Array = []
	for o: Variant in rows:
		if not (o is Dictionary):
			continue
		var pn := str(o.get("partner_name", o.get("partner", "")))
		if not by.has(pn):
			by[pn] = []
			order.append(pn)
		by[pn].append(o)
	if order.is_empty():
		_body.add_child(UI.label("제안이 없다.", "LabelMute"))
		return
	for pn: String in order:
		var known := bool((by[pn][0] as Dictionary).get("known", true))
		_body.add_child(Screen.section(pn if known else pn + " (모름)"))
		if not known:
			var hint := str((by[pn][0] as Dictionary).get("lock_hint", ""))
			_body.add_child(UI.label("잠김 — " + (hint if hint != "" else "탐험으로 만난다"), "LabelMute", true))
			continue
		for o: Dictionary in by[pn]:
			_body.add_child(_offer_row(o, no_post))


func _offer_row(o: Dictionary, no_post: bool) -> Control:
	var v := UI.vbox(4)
	var exp := str(o.get("dir", "")) == "export"
	var h := UI.hbox(6)
	v.add_child(h)
	h.add_child(UI.tag("수출" if exp else "수입", "gold" if exp else "jade"))
	h.add_child(UI.label(str(o.get("good_name", "")), "LabelBold"))
	h.add_child(UI.spacer(true))
	h.add_child(UI.label("우리가 팔고 돈을 받는다" if exp else "우리가 사고 돈을 낸다", "LabelDim"))
	var sizes := UI.to_array(o.get("sizes", []))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	for i in sizes.size():
		var s := UI.to_dict(sizes[i])
		var pm := float(s.get("per_day_money", 0))
		var b := PixelButton.make("%d개/%d시간\n%s₩%s/일" % [int(s.get("qty", 0)), int(s.get("interval_h", 0)), "+" if pm >= 0 else "-", UI.num(absf(pm))], "", "")
		b.small = true
		b.min_size = Vector2(148, 60)
		var can := Q.can_full("contract_sign", {"offer": str(o.get("id", "")), "size": i})
		b.disabled = no_post or not bool(can.get("ok", false))
		if b.disabled:
			b.tooltip_text = str(can.get("reason", ""))
		var oid := str(o.get("id", ""))
		b.pressed.connect(func() -> void: _sign(oid, i))
		row.add_child(b)
	if not sizes.is_empty():
		var c0 := Q.can_full("contract_sign", {"offer": str(o.get("id", "")), "size": 0})
		if not bool(c0.get("ok", false)) and str(c0.get("reason", "")) != "" and not no_post:
			v.add_child(UI.label(str(c0["reason"]), "LabelMute", true))
	return v


func _sign(oid: String, i: int) -> void:
	var r: Dictionary = ui.cmd("contract_sign", {"offer": oid, "size": i})
	if not bool(r.get("ok", false)):
		ui.toast(str(r.get("reason", "맺을 수 없다.")), "warn")
		return
	ui.toast("계약을 맺었다. 첫 회차는 곧.", "good")
	tab = "active"
	_seg.set_value(tab)
	_sig = ""
	refresh()
