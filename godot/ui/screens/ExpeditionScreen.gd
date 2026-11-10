class_name ExpeditionScreen
extends Screen
## ExpeditionScreen — 탐험(전면). query("expeditions") 를 1초마다 다시 읽는다(남은 시간은 질의 값 그대로 — 자체 계산 없음).
##  위: 자재 칩(보유량, 누르면 그 자재를 주는 곳만 밝힘 — 기본은 가장 적은 자재) · 탐험대 수
##  가운데: WorldMap(성채·거리 띠·목적지·길·걷는 팀)
##  목적지를 누르면 카드: 주력 자재·보장량·덤·실제 시간·비용·보급 토글·자재 고르기·파견
##  아래: 팀 줄(대기 / 나가 있음 + 남은 시간 / 돌아옴 → 수령, 모두 수령). 수령하면 보상이 펼쳐져 위로 날아가고
##       "이걸로 승급 가능한 집 n채"(Q.upgradable) 한 줄.
##  탐험 거점이 없으면 그렇다고 말하고 짓기로 건너뛴다.

var source: Callable = func() -> Dictionary: return Q.dict("expeditions")
var data: Dictionary = {}
var _top: float = 110.0
var _bar: float = 80.0
var _bg: Panel
var _head: HBoxContainer
var _mats: HBoxContainer
var _slots: Label
var _map: WorldMap
var _card: PanelContainer
var _card_body: VBoxContainer
var _teams_panel: PanelContainer
var _teams: HBoxContainer
var _empty: PanelContainer
var _pop: Control
var _sel: String = ""
var _provision: bool = false
var _pick: String = ""
var _focus: String = ""
var _focus_set: bool = false
var _send_btn: PixelButton
var _claim_btns: Dictionary = {}


func _init() -> void:
	super._init()
	visible = false
	poll_sec = 1.0
	_bg = Panel.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c1a22")
	_bg.add_theme_stylebox_override("panel", sb)
	add_child(_bg)
	_map = WorldMap.new()
	_map.dest_pressed.connect(_on_dest)
	add_child(_map)
	# 머리
	var hp := UI.panel("PanelDeep")
	hp.name = "Head"
	add_child(hp)
	var hv := UI.vbox(4)
	hp.add_child(hv)
	_head = UI.hbox(6)
	hv.add_child(_head)
	var plaque := UI.panel("PanelPlaque")
	plaque.add_child(UI.label("탐험", "LabelHead"))
	_head.add_child(plaque)
	_slots = UI.label("", "LabelDim")
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots.clip_text = true
	_head.add_child(_slots)
	var x := PixelButton.make("", "close", "ButtonRed")
	x.pressed.connect(func() -> void:
		close()
		finished.emit())
	_head.add_child(x)
	# 자재 칩은 둘째 줄 전체 폭(통합: 한 줄에 넣으면 칩 넷이 화면 밖으로 밀려났다)
	_mats = UI.hbox(4)
	hv.add_child(_mats)
	# 목적지 카드
	_card = UI.panel("PanelGold")
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = false
	add_child(_card)
	_card_body = UI.vbox(6)
	_card.add_child(_card_body)
	# 팀 줄
	_teams_panel = UI.panel("PanelSheet")
	_teams_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_teams_panel)
	var tm := UI.margin(8, 6, 8, 6)
	_teams_panel.add_child(tm)
	_teams = UI.hbox(6)
	tm.add_child(_teams)
	# 거점 없음
	_empty = UI.panel("PanelGold")
	_empty.visible = false
	add_child(_empty)
	# 보상 연출 층
	_pop = Control.new()
	_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_pop)
	resized.connect(_layout)


func set_area(top: float, bar: float) -> void:
	_top = top
	_bar = bar
	_layout()


func _layout() -> void:
	var w := size.x
	var hp: Control = get_node("Head")
	hp.reset_size()
	hp.position = Vector2(0, _top)
	hp.size = Vector2(w, hp.get_combined_minimum_size().y)
	var head_h := hp.size.y
	_teams_panel.reset_size()
	var th := maxf(_teams_panel.get_combined_minimum_size().y, 72.0)
	_teams_panel.size = Vector2(w, th)
	_teams_panel.position = Vector2(0, size.y - _bar - th)
	_bg.position = Vector2(0, _top)
	_bg.size = Vector2(w, size.y - _top - _bar)
	_map.position = Vector2(0, _top + head_h)
	_map.size = Vector2(w, _teams_panel.position.y - _map.position.y)
	_place_card()
	_place_empty()


func inset() -> float:
	return 0.0


func _on_open(_a: String, _was: bool) -> void:
	visible = true
	_sel = ""
	_card.visible = false
	_focus_set = false
	_layout()
	refresh()


func _on_closed() -> void:
	visible = false


func close() -> void:
	if not _open:
		return
	_open = false
	_on_closed()


# ------------------------------------------------------------------ 새로고침(1초)
func refresh() -> void:
	var d: Variant = source.call()
	data = d if d is Dictionary else {}
	var mats := UI.to_array(data.get("materials", []))
	if not _focus_set:
		_focus_set = true
		_focus = _least(mats)
	_build_mats(mats)
	var slots := UI.to_dict(data.get("slots", {}))
	var teams := UI.to_array(data.get("teams", []))
	var out_n := 0
	for tm0: Variant in teams:
		if tm0 is Dictionary and str(tm0.get("state", "")) == "out":
			out_n += 1
	var have_n := int(slots.get("have", teams.size()))
	_slots.text = ("탐험대 %d팀 · 나가 있음 %d · 거점 하나에 한 팀(최대 %d)" % [have_n, out_n, int(slots.get("max", 0))]) if have_n > 0 else "탐험대 없음 — 탐험 거점을 지으면 생긴다"
	_map.focus_good = _focus
	_map.selected = _sel
	_map.set_data(UI.to_array(data.get("dests", [])), teams)
	_build_teams(teams)
	var no_post := teams.is_empty() and int(slots.get("have", 0)) <= 0
	_empty.visible = no_post
	if no_post:
		if _base_under_construction():
			_build_empty("탐험 거점을 짓는 중", "공사가 끝나면 탐험대가 생긴다. 잠깐이면 된다.", false)
		else:
			_build_empty()
	elif UI.to_array(data.get("dests", [])).is_empty():
		_empty.visible = true
		_build_empty("아직 아는 곳이 없다", "목적지 정보가 아직 오지 않았다(시뮬 B 파트). 성채 둘레는 조용하다.", false)
	if _card.visible:
		_build_card()
	_layout.call_deferred()


## 가장 적은 자재(기본 필터). 모두 같으면 필터 없음.
func _least(mats: Array) -> String:
	var lo := ""
	var lo_n := 1e9
	var hi_n := -1.0
	for m: Variant in mats:
		if m is Dictionary:
			var n := float(m.get("have", 0))
			hi_n = maxf(hi_n, n)
			if n < lo_n:
				lo_n = n
				lo = str(m.get("id", ""))
	return lo if hi_n > lo_n else ""


func _build_mats(mats: Array) -> void:
	Screen.clear(_mats)
	for m: Variant in mats:
		if not (m is Dictionary):
			continue
		var id := str(m.get("id", ""))
		var nm := str(m.get("name", id))
		nm = {"concrete": "콘크리트", "parts": "부품"}.get(id, nm)
		var c := Chip.chip("%s %s" % [nm, UI.num(float(m.get("have", 0)))], "", id == _focus)
		c.small = true
		c.min_size = Vector2(48, 44)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.pressed.connect(func() -> void:
			_focus = "" if _focus == id else id
			refresh())
		_mats.add_child(c)


## 탐험 거점이 공사 중인가(읽기만 — 질의에 "짓는 중"이 없어서 상태의 건물 목록을 본다).
func _base_under_construction() -> bool:
	var st: Variant = Game.state
	if st == null:
		return false
	for b: Variant in st.buildings.values():
		if b is Dictionary and str(b.get("kind", "")) == "site" and str(b.get("type", "")) == "expedition_base":
			return true
	return false


# ------------------------------------------------------------------ 팀 줄
func _build_teams(teams: Array) -> void:
	Screen.clear(_teams)
	_claim_btns.clear()
	if teams.is_empty():
		_teams.add_child(UI.label("탐험대가 없다.", "LabelMute"))
		return
	var done_n := 0
	for tm: Variant in teams:
		if not (tm is Dictionary):
			continue
		var st := str(tm.get("state", "idle"))
		var box := UI.panel("PanelInset")
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.custom_minimum_size.x = 60
		box.clip_contents = true
		var v := UI.vbox(2)
		box.add_child(v)
		var hd := UI.hbox(4)
		v.add_child(hd)
		hd.add_child(UI.label(str(tm.get("name", "탐험대")), "LabelGoldSmall"))
		var sub := UI.label("", "LabelDim")
		sub.clip_text = true
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hd.add_child(sub)
		match st:
			"idle":
				sub.text = "대기"
				v.add_child(UI.label("지도에서 고른다", "LabelDim"))
			"out":
				sub.text = str(tm.get("dest_name", "")) + (" · 은퇴 예정" if bool(tm.get("retired", false)) else "")
				var l := UI.label("%s 남음" % fmt_time(float(tm.get("seconds_left", 0))), "LabelBold")
				v.add_child(l)
				var bar := RatioBar.make(1.0 - float(tm.get("seconds_left", 0)) / maxf(1.0, float(tm.get("total_seconds", 1))), "gold", 6)
				v.add_child(bar)
			"done":
				done_n += 1
				sub.text = str(tm.get("reward_text", ""))
				var b := PixelButton.make("수령", "check", "ButtonJade")
				b.small = true
				b.min_size = Vector2(56, 48)
				var tid: Variant = tm.get("id")
				b.pressed.connect(func() -> void: _claim(tid))
				v.add_child(b)
				_claim_btns[str(tid)] = b
		_teams.add_child(box)
	if done_n > 1:
		var all := PixelButton.make("모두 수령", "check", "ButtonJade")
		all.small = true
		all.pressed.connect(func() -> void: _claim(null))
		_teams.add_child(all)
		_claim_btns["all"] = all


static func fmt_time(sec: float) -> String:
	var s := int(maxf(sec, 0.0))
	if s >= 3600:
		return "%d시간 %02d분" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]


static func fmt_real(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		var h := s / 3600
		var m := (s % 3600) / 60
		return ("실제 %d시간" % h) + ((" %d분" % m) if m > 0 else "")
	return "실제 %d분" % maxi(1, s / 60)


func _claim(team: Variant) -> void:
	var before := _total_upgradable()
	var args := {} if team == null else {"team": team}
	var r: Dictionary = ui.cmd("expedition_claim", args)
	if not bool(r.get("ok", false)):
		ui.toast(str(r.get("reason", "받을 것이 없다.")), "warn")
		return
	# G6 확정 모양: rewards = [{good, name, n}], finds = [문장] (발견: 거래처·목적지·도면)
	var rw := Screen.rewards_dict(r.get("rewards", []))
	if not rw.is_empty():
		_reward_pop(rw, before)
	for f: Variant in UI.to_array(r.get("finds", [])):
		if str(f) != "":
			ui.banner.show_banner("탐험대가 찾아 왔다", str(f), "", "gold", 2.6, "探")
	refresh()


func on_event(n: String, p: Dictionary) -> void:
	if n == "expedition_claimed" and _pop.get_child_count() == 0:
		var rw := Screen.rewards_dict(p.get("rewards", {}))
		if not rw.is_empty():
			_reward_pop(rw, -1)
	if n in ["expedition_done", "expedition_claimed"]:
		_poll_t = 0.0


func _total_upgradable() -> int:
	var n := 0
	for g: Variant in Q.upgradable():
		if g is Dictionary:
			n += int(g.get("count", 0))
	return n


## 보상 펼치기: 가운데에서 부채꼴로 퍼졌다가 위(상단 띠)로 날아간다. 끝나면 "이걸로 승급 가능한 집 n채".
func _reward_pop(rewards: Dictionary, _before: int) -> void:
	var names: Dictionary = ui.good_names()
	var c := Vector2(size.x * 0.5, _map.position.y + _map.size.y * 0.5)
	var keys := rewards.keys()
	var n := keys.size()
	var i := 0
	for g: Variant in keys:
		var chip := UI.panel("PanelGold")
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UI.hbox(4)
		chip.add_child(h)
		h.add_child(UI.icon_rect("mat"))
		h.add_child(UI.label("%s +%s" % [str(names.get(g, g)), UI.num(float(rewards[g]))], "LabelBold"))
		_pop.add_child(chip)
		chip.reset_size()
		chip.position = c - chip.size * 0.5
		chip.scale = Vector2(0.4, 0.4)
		chip.pivot_offset = chip.size * 0.5
		var ang := (-0.5 + (float(i) + 0.5) / float(maxi(n, 1))) * 1.6 - PI * 0.5
		var fan := c + Vector2(cos(ang), sin(ang)) * 110.0 - chip.size * 0.5
		var dest := Vector2(size.x * 0.3 + float(i) * 30.0, _top - 30.0)
		var tw := chip.create_tween()
		tw.tween_property(chip, "position", fan, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(chip, "scale", Vector2.ONE, 0.3)
		tw.tween_interval(0.9 + float(i) * 0.12)
		tw.tween_property(chip, "position", dest, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(chip, "scale", Vector2(0.5, 0.5), 0.45)
		tw.parallel().tween_property(chip, "modulate:a", 0.0, 0.45)
		tw.tween_callback(chip.queue_free)
		i += 1
	var up := _total_upgradable()
	var line := UI.panel("PanelDeep")
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(("이걸로 승급 가능한 집 %d채" % up) if up > 0 else "아직 승급할 집은 없다. 자재는 창고에 있다.", "LabelGold")
	line.add_child(l)
	_pop.add_child(line)
	line.reset_size()
	line.position = Vector2((size.x - line.size.x) * 0.5, c.y + 90.0)
	line.modulate.a = 0.0
	var t2 := line.create_tween()
	t2.tween_interval(0.5)
	t2.tween_property(line, "modulate:a", 1.0, 0.2)
	t2.tween_interval(2.6)
	t2.tween_property(line, "modulate:a", 0.0, 0.4)
	t2.tween_callback(line.queue_free)


# ------------------------------------------------------------------ 목적지 카드
func _on_dest(id: String) -> void:
	_sel = id
	_map.selected = id
	_pick = ""
	if id == "":
		_card.visible = false
		return
	_card.visible = true
	_build_card()


func _dest(id: String) -> Dictionary:
	for d: Variant in UI.to_array(data.get("dests", [])):
		if d is Dictionary and str(d.get("id", "")) == id:
			return d
	return {}


func _idle_team() -> Variant:
	for tm: Variant in UI.to_array(data.get("teams", [])):
		if tm is Dictionary and str(tm.get("state", "")) == "idle":
			return tm.get("id")
	return null


func _build_card() -> void:
	Screen.clear(_card_body)
	_send_btn = null
	var d := _dest(_sel)
	if d.is_empty():
		_card.visible = false
		return
	var known := bool(d.get("known", true))
	var hr := UI.hbox(8)
	_card_body.add_child(hr)
	var band: String = {"near": "근거리", "mid": "중거리", "far": "원거리"}.get(str(d.get("band", "")), "")
	hr.add_child(UI.tag(band, "jade" if str(d.get("band", "")) == "near" else ("gold" if str(d.get("band", "")) == "mid" else "red")))
	var nm := UI.label(str(d.get("name", "?")) if known else "알 수 없는 곳", "LabelBold")
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(nm)
	var x := PixelButton.make("", "close", "")
	x.min_size = Vector2(48, 44)
	x.pressed.connect(func() -> void: _on_dest(""))
	hr.add_child(x)
	if not known:
		_card_body.add_child(UI.label(str(d.get("locked_hint", "아직 길을 모른다.")), "LabelSmall", true))
		_place_card.call_deferred()
		return
	var desc := str(d.get("desc", ""))
	if desc != "":
		_card_body.add_child(UI.label(desc, "LabelDim", true))
	var pr := UI.to_dict(d.get("primary", {}))
	var amount := ("%d" % int(pr.get("min", 0))) if int(pr.get("max", 0)) <= int(pr.get("min", 0)) else ("%d~%d" % [int(pr.get("min", 0)), int(pr.get("max", 0))])
	var big := UI.hbox(10)
	_card_body.add_child(big)
	big.add_child(UI.icon_rect("mat"))
	big.add_child(UI.label("%s %s 보장" % [str(pr.get("name", "")), amount], "LabelGold"))
	big.add_child(UI.spacer(true))
	big.add_child(UI.label(fmt_real(float(d.get("seconds", 0))), "LabelBold"))
	var bonus := str(d.get("bonus_text", ""))
	if bonus != "":
		_card_body.add_child(UI.label("덤: " + bonus, "LabelSmall", true))
	var cost := UI.to_dict(d.get("cost", {}))
	if float(cost.get("money", 0)) > 0.0:
		_card_body.add_child(Screen.kv("준비 비용", "₩" + UI.num(float(cost["money"]))))
	if int(d.get("visits", 0)) > 0:
		_card_body.add_child(Screen.kv("다녀온 횟수", "%d번" % int(d["visits"])))
	var picks := UI.to_array(d.get("picks", []))
	if not picks.is_empty():
		var opts: Array = []
		for pk: Variant in picks:
			if pk is Dictionary:
				opts.append({"id": str(pk.get("good", "")), "name": str(pk.get("name", ""))})
		if _pick == "" and not opts.is_empty():
			_pick = _focus if opts.any(func(o: Dictionary) -> bool: return o["id"] == _focus) else str(opts[0]["id"])
		var seg := Segmented.new()
		seg.small_text = true
		seg.chip_min = Vector2(56, 44)
		seg.set_options(opts, _pick)
		seg.selected.connect(func(id: String) -> void:
			_pick = id
			_build_card())
		_card_body.add_child(UI.label("가져올 자재를 고른다", "LabelDim"))
		_card_body.add_child(seg)
	var prov := UI.to_dict(data.get("provision", {}))
	if str(prov.get("good_text", "")) != "" or str(prov.get("bonus_text", "")) != "":
		var pr2 := UI.hbox(8)
		_card_body.add_child(pr2)
		var c := Chip.chip("보급", "food", _provision)
		c.small = true
		c.min_size = Vector2(80, 48)
		c.disabled = not bool(prov.get("enough", false)) and not _provision
		c.pressed.connect(func() -> void:
			_provision = c.button_pressed
			_build_card())
		pr2.add_child(c)
		pr2.add_child(UI.label("%s → %s%s" % [str(prov.get("good_text", "")), str(prov.get("bonus_text", "")), "" if bool(prov.get("enough", false)) else " (모자람)"], "LabelSmall", true))
	var team: Variant = _idle_team()
	var args := {"team": team, "dest": _sel, "provision": _provision}
	if _pick != "":
		args["pick"] = _pick
	var can := Q.can_full("expedition_send", args) if team != null else {"ok": false, "reason": "쉬는 탐험대가 없다."}
	_send_btn = PixelButton.make("파견 — " + fmt_real(float(d.get("seconds", 0))), "chev_r", "ButtonJade" if bool(can.get("ok", false)) else "")
	_send_btn.disabled = not bool(can.get("ok", false))
	_send_btn.pressed.connect(func() -> void: _send(args))
	_card_body.add_child(_send_btn)
	if not bool(can.get("ok", false)) and str(can.get("reason", "")) != "":
		var w := UI.label(str(can["reason"]), "LabelSmall", true)
		w.add_theme_color_override("font_color", UI.col("red_hi"))
		_card_body.add_child(w)
	_card_body.add_child(UI.label("돌아오는 데 실제 시간이 걸린다. 그동안 성채를 돌보면 된다. 늦게 받아도 줄지 않는다.", "LabelMute", true))
	_place_card.call_deferred()


func _send(args: Dictionary) -> void:
	var r: Dictionary = ui.cmd("expedition_send", args)
	if not bool(r.get("ok", false)):
		ui.toast(str(r.get("reason", "보낼 수 없다.")), "warn")
		return
	ui.toast("탐험대가 떠났다. %s 뒤에 돌아온다." % fmt_real(float(_dest(_sel).get("seconds", 0))).replace("실제 ", ""), "good")
	_on_dest("")
	refresh()


func _place_card() -> void:
	if not _card.visible:
		return
	_card.reset_size()
	var w := size.x - 24.0
	_card.size = Vector2(w, 0)
	_card.reset_size()
	_card.size.x = w
	_card.position = Vector2(12, _teams_panel.position.y - _card.size.y - 8)


func _build_empty(title: String = "탐험 거점이 없다", body: String = "탐험 거점을 지으면 탐험대가 생긴다. 근처 철거 골목은 실제로 몇 분이면 다녀온다.", show_btn: bool = true) -> void:
	Screen.clear(_empty)
	var v := UI.vbox(8)
	_empty.add_child(v)
	v.add_child(UI.label(title, "LabelHead"))
	v.add_child(UI.label(body, "LabelSmall", true))
	if show_btn:
		var b := PixelButton.make("탐험 거점 지으러 가기", "chev_r", "ButtonJade")
		b.pressed.connect(func() -> void: ui.jump({"screen": "build", "arg": "expedition_base"}))
		v.add_child(b)
	_place_empty.call_deferred()


func _place_empty() -> void:
	if not _empty.visible:
		return
	var w := size.x - 48.0
	_empty.size = Vector2(w, 0)
	_empty.reset_size()
	_empty.size.x = w
	_empty.position = Vector2(24, _map.position.y + _map.size.y * 0.62 - _empty.size.y * 0.5)


func target_rect(t: String) -> Rect2:
	if not _open:
		return Rect2()
	if t == "send":
		return _send_btn.get_global_rect() if _send_btn != null and is_instance_valid(_send_btn) and _card.visible else Rect2()
	if t == "claim":
		for k: String in _claim_btns:
			return (_claim_btns[k] as Control).get_global_rect()
		return Rect2()
	if t == "teams":
		return _teams_panel.get_global_rect()
	if t.begins_with("dest:"):
		return _map.dest_rect(t.substr(5))
	if t == "empty":
		return _empty.get_global_rect() if _empty.visible else Rect2()
	return Rect2()
