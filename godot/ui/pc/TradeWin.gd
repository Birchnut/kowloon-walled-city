class_name TradeWin
extends PcWindow
## 교역(F3) — 왼쪽: 맺은 계약(수입/수출 · 수량·주기·값 · 다음 회차 · 최근 결과 · 멈춤 · 수출 최소 보유 ± · 해지).
## 오른쪽: 거래처별 제안(크기 단계 버튼 = 맺기). 교역소가 없으면 짓기로 가는 버튼.
## 읽는 것: contracts(1초). 보내는 것: contract_sign / contract_set / contract_cancel(확인).

const RESERVE_STEP := 10.0

var _active: VBoxContainer
var _offers: VBoxContainer
var _sig := ""


func _init() -> void:
	super._init()
	win_id = "trade"
	title_text = "교역"
	key_hint = "F3"
	want_size = Vector2(1400, 820)


func _build(b: VBoxContainer) -> void:
	var h := UI.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(h)
	var lv := UI.vbox(6)
	lv.custom_minimum_size.x = 560
	h.add_child(lv)
	PcWindow.section(lv, "맺은 계약")
	_active = PcWindow.scroll_list(lv)
	var rv := UI.vbox(6)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rv)
	PcWindow.section(rv, "제안 — 크기를 누르면 맺는다")
	_offers = PcWindow.scroll_list(rv)


func _refresh() -> void:
	if body == null:
		return
	var d := Q.dict("contracts")
	var sig := JSON.stringify(d).md5_text()
	if sig == _sig:
		return
	_sig = sig
	var sl := UI.to_dict(d.get("slots", {}))
	set_subtitle("계약 자리 %d / %d" % [int(sl.get("used", 0)), int(sl.get("max", 0))])
	PcWindow.clear(_active)
	PcWindow.clear(_offers)
	var no_post := bool(d.get("no_post", false))
	if no_post:
		var p := UI.panel("PanelGold")
		var v := UI.vbox(6)
		p.add_child(v)
		v.add_child(UI.label("뒷문 무역관이 없다", "LabelBold"))
		var l := UI.label("기반(K)의 뒷문 무역관을 지으면 계약 자리가 생긴다(월세 전사 40명이 되면 열린다).", "LabelSmall", true)
		l.custom_minimum_size.x = 540
		v.add_child(l)
		var b := PcButton.make("뒷문 무역관 짓기", "infra", "K", "ButtonJade")
		b.pressed.connect(func() -> void:
			close()
			ui.jump({"screen": "build", "arg": "trade_post"}))
		v.add_child(b)
		_active.add_child(p)
	var act := UI.to_array(d.get("active", []))
	if act.is_empty() and not no_post:
		_active.add_child(UI.label("맺은 계약이 없다. 오른쪽에서 고른다.", "LabelDim"))
	for c: Variant in act:
		_active.add_child(_active_row(UI.to_dict(c)))
	_offer_list(UI.to_array(d.get("offers", [])), no_post)


func _active_row(c: Dictionary) -> Control:
	var p := UI.panel("PanelRow")
	var v := UI.vbox(4)
	p.add_child(v)
	var id: Variant = c.get("id")
	var exp := str(c.get("dir", "")) == "export"
	var paused := bool(c.get("paused", false))
	var h := UI.hbox(8)
	v.add_child(h)
	h.add_child(UI.tag("수출" if exp else "수입", "gold" if exp else "jade"))
	var nm := UI.label("%s · %s" % [str(c.get("good_name", "")), str(c.get("partner_name", ""))], "LabelBold")
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)
	var pm := float(c.get("per_day_money", 0))
	var ml := UI.label("%s/일" % UI.won_signed(pm), "LabelSmall")
	ml.add_theme_color_override("font_color", UI.col("jade_hi") if pm >= 0 else UI.col("red_hi"))
	h.add_child(ml)
	v.add_child(UI.label("%s개씩 %s시간마다 · 개당 %s · %s" % [UI.num(c.get("qty", 0)), UI.dec(c.get("interval_h", 0)), UI.won(c.get("price", 0)),
		"멈춤" if paused else ("다음 회차 %s시간 뒤" % UI.dec(c.get("next_in_h", 0)))], "LabelDim"))
	var last := str(c.get("last_text", ""))
	if last != "":
		var ll := UI.label("최근: " + last, "LabelSmall", true)
		ll.custom_minimum_size.x = 560
		v.add_child(ll)
	var ctl := UI.hbox(6)
	v.add_child(ctl)
	var pc := PcButton.make("다시 돌리기" if paused else "멈춤", "play" if paused else "pause", "", "Button")
	pc.pressed.connect(func() -> void: _set_contract(id, {"paused": not paused}))
	ctl.add_child(pc)
	if exp:
		var rv := float(c.get("reserve", 0))
		var minus := PcButton.make("", "minus", "", "Button")
		minus.pressed.connect(func() -> void: _set_contract(id, {"reserve": maxf(0.0, rv - RESERVE_STEP)}))
		ctl.add_child(minus)
		var rl := UI.label("최소 보유 %s" % UI.num(rv), "LabelSmall")
		ctl.add_child(rl)
		TipLayer.set_tip(rl, "수출 최소 보유\n재고가 이만큼 아래면 그 회차는 수출하지 않는다.")
		var plus := PcButton.make("", "plus", "", "Button")
		plus.pressed.connect(func() -> void: _set_contract(id, {"reserve": rv + RESERVE_STEP}))
		ctl.add_child(plus)
	ctl.add_child(UI.spacer(true))
	var cx := PcButton.make("해지", "close", "", "ButtonRed")
	cx.pressed.connect(func() -> void:
		ui.confirm({"kicker": "계약 해지", "title": "%s 계약을 끝낸다" % str(c.get("good_name", "")),
			"lines": ["정기 %s이 멈춘다. 벌금은 없다." % ("수출" if exp else "수입")], "ok_text": "해지", "danger": true}, func() -> void:
				var r: Dictionary = ui.cmd("contract_cancel", {"id": id})
				if not bool(r.get("ok", false)):
					ui.toast(str(r.get("reason", "")), "warn")
				_sig = ""
				_refresh()))
	ctl.add_child(cx)
	return p


func _set_contract(id: Variant, a: Dictionary) -> void:
	var args := {"id": id}
	args.merge(a)
	var r: Dictionary = ui.cmd("contract_set", args)
	if not bool(r.get("ok", false)):
		ui.toast(str(r.get("reason", "")), "warn")
	_sig = ""
	_refresh()


func _offer_list(rows: Array, no_post: bool) -> void:
	var by := {}
	var order: Array = []
	for o: Variant in rows:
		var od := UI.to_dict(o)
		var pn := str(od.get("partner_name", od.get("partner", "")))
		if not by.has(pn):
			by[pn] = []
			order.append(pn)
		by[pn].append(od)
	if order.is_empty():
		_offers.add_child(UI.label("제안이 없다.", "LabelDim"))
		return
	for pn: String in order:
		var known := bool((by[pn][0] as Dictionary).get("known", true))
		_offers.add_child(UI.label(pn if known else pn + " (모름)", "LabelGold"))
		if not known:
			var hint := str((by[pn][0] as Dictionary).get("lock_hint", ""))
			_offers.add_child(UI.label("잠김 — " + (hint if hint != "" else "탐험으로 만난다"), "LabelDim"))
			continue
		for od2: Dictionary in by[pn]:
			_offers.add_child(_offer_row(od2, no_post))


func _offer_row(o: Dictionary, no_post: bool) -> Control:
	var p := UI.panel("PanelRow")
	var h := UI.hbox(8)
	p.add_child(h)
	var exp := str(o.get("dir", "")) == "export"
	h.add_child(UI.tag("수출" if exp else "수입", "gold" if exp else "jade"))
	var nm := UI.label(str(o.get("good_name", "")), "LabelSmall")
	nm.custom_minimum_size.x = 120
	h.add_child(nm)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(flow)
	for s: Variant in UI.to_array(o.get("sizes", [])):
		var sd := UI.to_dict(s)
		var pm := float(sd.get("per_day_money", 0))
		var b := PcButton.make("%s개/%s시간 %s/일" % [UI.num(sd.get("qty", 0)), UI.dec(sd.get("interval_h", 0)), UI.won_signed(pm)], "", "", "Button")
		b.min_h = 32
		var size_i := UI.to_array(o.get("sizes", [])).find(s)
		var args := {"offer": o.get("id"), "size": size_i}
		var can := Q.can_full("contract_sign", args)
		b.disabled = no_post or not bool(can.get("ok", false))
		b.pressed.connect(func() -> void:
			var r: Dictionary = ui.cmd("contract_sign", args)
			if bool(r.get("ok", false)):
				ui.toast("계약을 맺었다 — %s" % str(o.get("good_name", "")), "good", "trade")
			else:
				ui.toast(str(r.get("reason", "")), "warn")
			_sig = ""
			_refresh())
		TipLayer.set_tip(b, "%s %s\n%s개를 %s시간마다, 개당 %s. 하루 %s.%s" % ["수출" if exp else "수입", str(o.get("good_name", "")), UI.num(sd.get("qty", 0)), UI.dec(sd.get("interval_h", 0)), UI.won(sd.get("price", 0)), UI.won_signed(pm), ("\n" + str(can.get("reason", ""))) if not bool(can.get("ok", false)) else ""])
		flow.add_child(b)
	return p
