class_name ExpeditionWin
extends PcWindow
## 탐험(F4) — 게임 시계로 도는 자동 파견 + "직접 줍기"(아직 준비 중: 목적지마다 보이되 꺼진 버튼, 던전 재고 %와 위험).
##  왼쪽: 탐험대(상태·가는 곳·남은 시간 막대·받기). 자재 보유 줄.
##  오른쪽: 목적지 목록(거리 띠 근·중·원) — 고르면 아래에 보내기 판(보급·고를 자재·비용·이유·[보내기]).
## 읽는 것: expeditions(1초 — days_left/total_days, stock_pct, run{available,danger,text}). 보내는 것: expedition_send / expedition_claim / run_begin(직접 줍기, 준비되면).

var _teams: VBoxContainer
var _mats: HBoxContainer
var _dests: VBoxContainer
var _send: VBoxContainer
var _sel: String = ""
var _pick: String = ""
var _provision := false
var _data: Dictionary = {}
var _sig := ""
var _good_hl := ""


func _init() -> void:
	super._init()
	win_id = "expedition"
	title_text = "탐험"
	key_hint = "F4"
	want_size = Vector2(1480, 860)
	poll = 1.0


func _build(b: VBoxContainer) -> void:
	_mats = UI.hbox(14)
	b.add_child(_mats)
	var h := UI.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(h)
	var lv := UI.vbox(6)
	lv.custom_minimum_size.x = 480
	h.add_child(lv)
	PcWindow.section(lv, "탐험대")
	_teams = PcWindow.scroll_list(lv)
	var rv := UI.vbox(6)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rv)
	PcWindow.section(rv, "목적지 — 고르면 아래에서 보낸다")
	_dests = PcWindow.scroll_list(rv)
	var sp := UI.panel("PanelDeep")
	rv.add_child(sp)
	_send = UI.vbox(6)
	sp.add_child(_send)


func _on_open(arg: String) -> void:
	_good_hl = arg
	_sig = ""


func _refresh() -> void:
	if body == null:
		return
	_data = Q.dict("expeditions")
	var sig := JSON.stringify(_data).md5_text() + _sel + _pick + str(_provision) + _good_hl
	if sig == _sig:
		_tick_bars()
		return
	_sig = sig
	var slots := UI.to_dict(_data.get("slots", {}))
	set_subtitle("탐험대 %d / %d" % [int(slots.get("have", 0)), int(slots.get("max", 0))])
	_build_mats()
	_build_teams()
	_build_dests()
	_build_send()


func _build_mats() -> void:
	PcWindow.clear(_mats)
	_mats.add_child(UI.label("가진 자재", "LabelDim"))
	for m: Variant in UI.to_array(_data.get("materials", [])):
		var md := UI.to_dict(m)
		var h := UI.hbox(4)
		h.add_child(Picto.make("mat", UI.col("gold") if str(md.get("id", "")) == _good_hl else UI.col("paper2")))
		h.add_child(UI.label("%s %s" % [str(md.get("name", "")), UI.num(md.get("have", 0))], "LabelSmall"))
		_mats.add_child(h)


var _bars: Array = []


func _build_teams() -> void:
	PcWindow.clear(_teams)
	_bars.clear()
	var teams := UI.to_array(_data.get("teams", []))
	if teams.is_empty():
		var l := UI.label("탐험대가 없다. 기반 분류의 탐험 거점을 지으면 생긴다.", "LabelDim", true)
		l.custom_minimum_size.x = 440
		_teams.add_child(l)
		var gb := PcButton.make("짓기 — 기반", "infra", "", "Button")
		gb.pressed.connect(func() -> void:
			close()
			ui.jump({"screen": "build", "arg": "infra"}))
		_teams.add_child(gb)
		return
	var any_done := false
	for t: Variant in teams:
		var td := UI.to_dict(t)
		var st := str(td.get("state", "idle"))
		var p := UI.panel("PanelRow")
		_teams.add_child(p)
		var v := UI.vbox(3)
		p.add_child(v)
		var h := UI.hbox(8)
		v.add_child(h)
		h.add_child(Picto.make("expedition", UI.col("jade_hi") if st == "done" else (UI.col("gold") if st == "out" else UI.col("dim"))))
		h.add_child(UI.label(str(td.get("name", "")), "LabelBold"))
		var stl := UI.label(str(td.get("state_name", {"idle": "쉬는 중", "out": "나가 있음", "done": "돌아옴"}.get(st, st))), "LabelSmall")
		stl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(stl)
		if st == "done":
			any_done = true
			var cb := PcButton.make("받기", "check", "", "ButtonJade")
			var tid: Variant = td.get("id")
			cb.pressed.connect(func() -> void: _claim(tid))
			h.add_child(cb)
		if st in ["out", "done"]:
			v.add_child(UI.label("%s · %s" % [str(td.get("dest_name", "")), str(td.get("reward_text", ""))], "LabelDim"))
		if st == "out":
			var bh := UI.hbox(8)
			v.add_child(bh)
			var tot := float(td.get("total_days", 0.0))
			var left := float(td.get("days_left", 0.0))
			var bar := PcWindow.bar(1.0 - left / maxf(tot, 0.0001), "warn", 300, 10)
			bh.add_child(bar)
			bh.add_child(UI.label("%s 남음" % UI.days(left), "LabelSmall"))
	if any_done:
		var all := PcButton.make("모두 받기", "check", "", "ButtonJade")
		all.pressed.connect(func() -> void: _claim(null))
		_teams.add_child(all)


func _tick_bars() -> void:
	pass


func _claim(team: Variant) -> void:
	var args := {} if team == null else {"team": team}
	var r: Dictionary = ui.cmd("expedition_claim", args)
	if bool(r.get("ok", false)):
		Sfx.play("expedition")
		var parts: Array = []
		for rw: Variant in UI.to_array(r.get("rewards", [])):
			var rd := UI.to_dict(rw)
			parts.append("%s %s" % [str(rd.get("name", "")), UI.num(rd.get("n", 0))])
		ui.toast("받았다: " + (" · ".join(parts) if not parts.is_empty() else "빈손"), "good", "mat")
		for f: Variant in UI.to_array(r.get("finds", [])):
			ui.toasts.card({"kicker": "탐험에서 찾았다", "title": str(f), "tone": "gold", "picto": "expedition"})
	else:
		ui.toast(str(r.get("reason", "")), "warn")
	_sig = ""
	_refresh()


func _build_dests() -> void:
	PcWindow.clear(_dests)
	var bands := {"near": "가까운 곳", "mid": "중거리", "far": "먼 곳"}
	var last_band := ""
	for d: Variant in UI.to_array(_data.get("dests", [])):
		var dd := UI.to_dict(d)
		var band := str(dd.get("band", ""))
		if band != last_band:
			last_band = band
			_dests.add_child(UI.label(str(bands.get(band, band)), "LabelGoldSmall"))
		_dests.add_child(_dest_row(dd))


func _gives(dd: Dictionary, good: String) -> bool:
	if good == "":
		return false
	if str(UI.to_dict(dd.get("primary", {})).get("good", "")) == good:
		return true
	for pk: Variant in UI.to_array(dd.get("picks", [])):
		if str(UI.to_dict(pk).get("good", "")) == good:
			return true
	return good == "parts" and str(dd.get("bonus_text", "")).contains("부품")


func _dest_row(dd: Dictionary) -> Control:
	var id := str(dd.get("id", ""))
	var known := bool(dd.get("known", true))
	var row := ClickRow.new()
	if id == _sel:
		row.theme_type_variation = "PanelRowHi"
	var h := UI.hbox(10)
	row.add_child(h)
	var pic := Picto.make("expedition", UI.col("gold") if _gives(dd, _good_hl) else (UI.col("paper") if known else UI.col("mute")))
	h.add_child(pic)
	var v := UI.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var nh := UI.hbox(8)
	v.add_child(nh)
	nh.add_child(UI.label(str(dd.get("name", "")) if known else "???", "LabelBold" if known else "LabelDim"))
	if bool(dd.get("new", false)):
		nh.add_child(UI.tag("새로", "jade"))
	var days := float(dd.get("days", float(dd.get("seconds", 0)) / 600.0))
	nh.add_child(UI.label("%s(×1 %d분)" % [UI.days(days), maxi(1, int(round(days * 10.0)))], "LabelDim"))
	var pr := UI.to_dict(dd.get("primary", {}))
	var line := "%s %s~%s" % [str(pr.get("name", "")), UI.num(pr.get("min", 0)), UI.num(pr.get("max", 0))] if known else str(dd.get("locked_hint", "아직 모른다"))
	var bt := str(dd.get("bonus_text", ""))
	if known and bt != "":
		line += " · " + (bt if bt.begins_with("덤") else "덤: " + bt)
	var ll := UI.label(line, "LabelSmall", true)
	ll.custom_minimum_size.x = 560
	v.add_child(ll)
	# 직접 줍기: 보이되 꺼짐 — 던전 재고 % 와 위험
	var run := UI.to_dict(dd.get("run", {}))
	var rv := UI.vbox(2)
	rv.custom_minimum_size.x = 200
	h.add_child(rv)
	var rb := PcButton.make("직접 줍기", "pick", "", "Button")
	rb.min_h = 30
	rb.disabled = not bool(run.get("available", false)) or not known
	rb.pressed.connect(func() -> void: _run(id))
	TipLayer.set_tip(rb, "직접 줍기%s\n던전에 직접 들어가 배낭만큼 들고 나온다. 깊을수록 위험·보상이 크다. 털면 재고가 줄고 게임 시간으로 다시 찬다.\n%s" % [" (준비 중)" if rb.disabled else "", str(run.get("text", ""))])
	rv.add_child(rb)
	var sh := UI.hbox(4)
	rv.add_child(sh)
	sh.add_child(UI.label("재고", "LabelMute"))
	var sp := float(dd.get("stock_pct", 1.0))
	sh.add_child(PcWindow.bar(sp, "ok" if sp >= 0.6 else ("warn" if sp >= 0.3 else "bad"), 60, 8))
	var dg := int(run.get("danger", 0))
	sh.add_child(UI.label("위험 " + "■".repeat(dg) + "□".repeat(maxi(0, 3 - dg)), "LabelMute"))
	row.pressed.connect(func() -> void:
		if known:
			_sel = id
			_pick = ""
			_sig = ""
			_refresh())
	TipLayer.set_tip(row, "%s\n%s" % [str(dd.get("name", "")), str(dd.get("desc", ""))] if known else "아직 모르는 곳\n%s" % str(dd.get("locked_hint", "")))
	return row


func _dest(id: String) -> Dictionary:
	for d: Variant in UI.to_array(_data.get("dests", [])):
		if str(UI.to_dict(d).get("id", "")) == id:
			return d
	return {}


func _idle_team() -> Variant:
	for t: Variant in UI.to_array(_data.get("teams", [])):
		if str(UI.to_dict(t).get("state", "")) == "idle":
			return UI.to_dict(t).get("id")
	return null


func _build_send() -> void:
	PcWindow.clear(_send)
	var dd := _dest(_sel)
	if dd.is_empty():
		_send.add_child(UI.label("목적지를 고른다.", "LabelDim"))
		return
	var h := UI.hbox(10)
	_send.add_child(h)
	h.add_child(UI.label(str(dd.get("name", "")), "LabelGold"))
	var cost := UI.to_dict(dd.get("cost", {}))
	if float(cost.get("money", 0)) > 0:
		h.add_child(UI.label("비용 " + UI.won(cost.get("money", 0)), "LabelSmall"))
	var picks := UI.to_array(dd.get("picks", []))
	if not picks.is_empty():
		var ph := UI.hbox(4)
		_send.add_child(ph)
		ph.add_child(UI.label("가져올 자재:", "LabelDim"))
		if _pick == "":
			_pick = str(UI.to_dict(picks[0]).get("good", ""))
		for pk: Variant in picks:
			var pd := UI.to_dict(pk)
			var g := str(pd.get("good", ""))
			var b := PcButton.make(str(pd.get("name", g)), "mat", "", "ButtonToggle")
			b.toggle_mode = true
			b.set_pressed_no_signal(g == _pick)
			b.pressed.connect(func() -> void:
				_pick = g
				_sig = ""
				_refresh())
			ph.add_child(b)
	var prov := UI.to_dict(_data.get("provision", {}))
	var pv := PcButton.make("보급 챙기기 — %s" % str(prov.get("good_text", "")), "food", "", "ButtonToggle")
	pv.toggle_mode = true
	pv.set_pressed_no_signal(_provision)
	pv.disabled = not bool(prov.get("enough", true)) and not _provision
	pv.pressed.connect(func() -> void:
		_provision = not _provision
		_sig = ""
		_refresh())
	TipLayer.set_tip(pv, "보급\n%s" % str(prov.get("bonus_text", "")))
	_send.add_child(pv)
	var team: Variant = _idle_team()
	var args := {"team": team, "dest": _sel, "provision": _provision}
	if _pick != "":
		args["pick"] = _pick
	var can := Q.can_full("expedition_send", args) if team != null else {"ok": false, "reason": "쉬는 탐험대가 없다."}
	var row := UI.hbox(10)
	_send.add_child(row)
	var why := UI.label("" if bool(can.get("ok", false)) else str(can.get("reason", "")), "LabelRedSmall", true)
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	why.custom_minimum_size.x = 400
	row.add_child(why)
	var go := PcButton.make("보내기", "right", "Enter", "ButtonGold")
	go.disabled = not bool(can.get("ok", false))
	go.pressed.connect(func() -> void:
		var r: Dictionary = ui.cmd("expedition_send", args)
		if bool(r.get("ok", false)):
			Sfx.play("expedition")
			ui.toast("%s(으)로 보냈다." % str(dd.get("name", "")), "good", "expedition")
		else:
			ui.toast(str(r.get("reason", "")), "warn")
		_sig = ""
		_refresh())
	row.add_child(go)


func _run(id: String) -> void:
	var r: Dictionary = ui.cmd("run_begin", {"dest": id})
	if not bool(r.get("ok", false)):
		ui.toast(str(r.get("reason", "직접 줍기는 아직 준비 중이다.")), "dim")


## 그 자재를 주는 가장 빠른 곳: "이름 · 0.3일"(승급 창 모자람 줄)
static func nearest_source(good: String) -> String:
	var best := {}
	for d: Variant in UI.to_array(Q.dict("expeditions").get("dests", [])):
		var dd := UI.to_dict(d)
		if not bool(dd.get("known", true)):
			continue
		var hit := str(UI.to_dict(dd.get("primary", {})).get("good", "")) == good
		for pk: Variant in UI.to_array(dd.get("picks", [])):
			if str(UI.to_dict(pk).get("good", "")) == good:
				hit = true
		if good == "parts" and str(dd.get("bonus_text", "")).contains("부품"):
			hit = true
		if hit and (best.is_empty() or float(dd.get("seconds", 0)) < float(best.get("seconds", 0))):
			best = dd
	if best.is_empty():
		return ""
	return "%s · %s" % [str(best.get("name", "")), UI.days(float(best.get("days", float(best.get("seconds", 0)) / 600.0)))]


func on_event(n: String, _p: Dictionary) -> void:
	if n in ["expedition_done", "expedition_claimed"]:
		_sig = ""
