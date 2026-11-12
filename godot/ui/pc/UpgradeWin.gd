class_name UpgradeWin
extends PcWindow
## 승급 창(한 채 또는 계층 묶음 일괄). v0.3 판을 PC 창으로.
##  위: 계층 묶음 칩(여럿이면) · 세 자재 카드(외관 미리보기 + 보유/필요). 세 자재는 값이 같다 — 한 줄로 못 박는다.
##  아래: 미리보기(정원·이주·일손·세수·수요 문장) · 막힌 이유 · 모자란 자재와 가장 빠른 탐험 · [승급] (다 안 되면 "앞에서부터 n채만").
## 한 채: info.upgrade, 여러 채: upgrade_preview{bids, material}. 성공하면 닫는다(뷰의 비계 연출을 가리지 않게).

const PREVIEW := "res://assets/ui/house_previews/t%d_%s.png"

var bids: Array = []
var mat: String = ""
var _info: Dictionary = {}
var _batch := false
var _groups: Array = []
var _tier_row: HBoxContainer
var _cards: HBoxContainer
var _card_btns: Dictionary = {}
var _same: Label
var _pv: VBoxContainer
var _why: Label
var _short: VBoxContainer
var _go: PcButton
var _fit_k := 0


func _init() -> void:
	super._init()
	win_id = "upgrade"
	title_text = "승급"
	key_hint = "U"
	want_size = Vector2(1000, 760)
	poll = 2.0


func _build(b: VBoxContainer) -> void:
	_tier_row = UI.hbox(4)
	b.add_child(_tier_row)
	_cards = UI.hbox(10)
	b.add_child(_cards)
	_same = UI.label("", "LabelGoldSmall", true)
	_same.custom_minimum_size.x = 940
	b.add_child(_same)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(sc)
	var inner := UI.vbox(6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	_pv = UI.vbox(4)
	inner.add_child(_pv)
	_why = UI.label("", "LabelRedSmall", true)
	_why.custom_minimum_size.x = 920
	inner.add_child(_why)
	_short = UI.vbox(4)
	inner.add_child(_short)
	var row := UI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	b.add_child(row)
	var cancel := PcButton.make("그만둔다", "", "Esc", "Button")
	cancel.pressed.connect(close)
	row.add_child(cancel)
	_go = PcButton.make("승급", "up", "Enter", "ButtonJade")
	_go.min_h = 44
	_go.pressed.connect(_on_go)
	row.add_child(_go)


func open_single(bid: int, info: Dictionary) -> void:
	_groups = []
	bids = [bid]
	_batch = false
	_info = info if not info.is_empty() else Q.dict("info", {"bid": bid})
	_start()


func open_groups(groups: Array, tier: int = 0) -> void:
	_groups = groups
	var pick: Dictionary = groups[0]
	for g: Dictionary in groups:
		if int(g.get("tier", 0)) == tier:
			pick = g
	_open_batch(UI.to_array(pick.get("bids", [])), int(pick.get("tier", 0)))


func _open_batch(b: Array, tier: int) -> void:
	bids = b.duplicate()
	_batch = bids.size() > 1
	_info = Q.dict("info", {"bid": int(bids[0])}) if not bids.is_empty() else {}
	_start(tier)


func _start(cur_tier: int = 0) -> void:
	open("")
	_build_tiers(cur_tier)
	var up := UI.to_dict(_info.get("upgrade", {}))
	var mats := UI.to_array(up.get("materials", []))
	mat = ""
	var best := -1
	for mt: Variant in mats:
		if mt is Dictionary and int(mt.get("have", 0)) > best:
			best = int(mt.get("have", 0))
			mat = str(mt.get("id", ""))
	_build_cards(mats, int(up.get("to_tier", 0)))
	_update()


func pick_material(m: String) -> void:
	mat = m
	_update()


func _build_tiers(cur: int) -> void:
	PcWindow.clear(_tier_row)
	_tier_row.visible = _groups.size() > 1
	if _groups.size() <= 1:
		return
	_tier_row.add_child(UI.label("계층:", "LabelDim"))
	for g: Dictionary in _groups:
		var t := int(g.get("tier", 0))
		var b := PcButton.make("%s %d채" % [str(g.get("tier_name", "")), int(g.get("count", 0))], "", "", "ButtonToggle")
		b.toggle_mode = true
		b.set_pressed_no_signal(t == cur)
		var gb: Array = UI.to_array(g.get("bids", []))
		b.pressed.connect(func() -> void: _open_batch(gb, t))
		_tier_row.add_child(b)


func _build_cards(mats: Array, to_tier: int) -> void:
	PcWindow.clear(_cards)
	_card_btns.clear()
	for mt: Variant in mats:
		if not (mt is Dictionary):
			continue
		var id := str(mt.get("id", ""))
		var b := Button.new()
		b.theme_type_variation = "ButtonCard"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(300, 200)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var v := UI.vbox(4)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_top = 8
		v.offset_right = -10
		v.offset_bottom = -8
		b.add_child(v)
		v.add_child(UI.label(str(mt.get("name", id)), "LabelBold"))
		var path := PREVIEW % [to_tier, id]
		if ResourceLoader.exists(path):
			var tr := TextureRect.new()
			tr.texture = load(path)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			v.add_child(tr)
		else:
			v.add_child(UI.spacer(true))
		var hl := UI.label("", "LabelSmall")
		hl.name = "have"
		v.add_child(hl)
		b.pressed.connect(func() -> void:
			mat = id
			Sfx.play("click")
			_update())
		TipLayer.set_tip(b, "%s로 올린다\n세 자재는 성능·값이 같다. 이 집의 모양만 달라진다." % str(mt.get("name", id)))
		_cards.add_child(b)
		_card_btns[id] = b


func _update() -> void:
	if not visible:
		return
	var up := UI.to_dict(_info.get("upgrade", {}))
	var n := bids.size()
	var to_name := str(up.get("to_name", ""))
	set_subtitle(("%s %d채 → %s" % [str(_info.get("tier_name", "")), n, to_name]) if _batch else ("%s → %s" % [str(_info.get("title", "집")), to_name]))
	var pv: Dictionary = UI.to_dict(up.get("preview", {}))
	var cost: Dictionary = UI.to_dict(up.get("cost", {}))
	var ok := bool(up.get("ready", false))
	var blockers: Array = UI.to_array(up.get("blockers", []))
	if _batch or mat != "":
		var q := Q.dict("upgrade_preview", {"bids": bids, "material": mat})
		if not q.is_empty():
			pv = q
			var qc := UI.to_dict(q.get("cost", {}))
			if int(qc.get("qty", 0)) > 0 or float(qc.get("money", 0)) > 0.0:
				cost = qc
			ok = bool(q.get("ok", ok))
			blockers = UI.to_array(q.get("blockers", blockers))
	var qty := int(cost.get("qty", 0))
	var mname := ""
	var have := 0
	for mt: Variant in UI.to_array(up.get("materials", [])):
		var md := UI.to_dict(mt)
		var id := str(md.get("id", ""))
		if _card_btns.has(id):
			var b: Button = _card_btns[id]
			b.set_pressed_no_signal(id == mat)
			var hl: Label = b.find_child("have", true, false)
			if hl != null:
				var hv := int(md.get("have", 0))
				hl.text = "가진 것 %s / 필요 %s" % [UI.num(hv), UI.num(qty)]
				hl.add_theme_color_override("font_color", UI.col("jade_hi") if hv >= qty else UI.col("red_hi"))
		if id == mat:
			mname = str(md.get("name", mat))
			have = int(md.get("have", 0))
	var extra := UI.to_dict(cost.get("extra", {}))
	var names: Dictionary = ui.good_names() if ui != null else {}
	var et: Array = []
	for g: String in extra:
		et.append("%s %s" % [str(names.get(g, g)), UI.num(extra[g])])
	_same.text = UI.keep("세 자재 모두 같은 값: %s + 자재 %d%s. 고른 자재가 이 집의 얼굴이 된다." % [UI.won(cost.get("money", 0)), qty, (" + " + " · ".join(et)) if not et.is_empty() else ""])
	_preview(pv)
	_fit_k = 0
	var label := "승급 — %s · %s %d" % [UI.won(cost.get("money", 0)), mname, qty] if mname != "" else "자재를 고른다"
	if not ok and _batch and mat != "":
		_fit_k = _fit_count()
		if _fit_k > 0:
			var c2 := UI.to_dict(Q.dict("upgrade_preview", {"bids": bids.slice(0, _fit_k), "material": mat}).get("cost", {}))
			label = "앞에서부터 %d채만 승급 — %s · %s %d" % [_fit_k, UI.won(c2.get("money", 0)), mname, int(c2.get("qty", 0))]
			ok = true
	_why.text = "" if ok else UI.keep("\n".join(PackedStringArray(blockers.map(func(x: Variant) -> String: return "· " + _josa_fix(str(x))))))
	_why.visible = _why.text != ""
	_go.label_text = label
	_go.disabled = not ok or mat == ""
	_short_row(qty, have, mname, blockers)


func _kv(k: String, v: String, tone: String = "") -> void:
	var h := UI.hbox(10)
	_pv.add_child(h)
	var kl := UI.label(k, "LabelDim")
	kl.custom_minimum_size.x = 170
	h.add_child(kl)
	var vl := UI.label(v, "LabelSmall")
	if tone != "":
		vl.add_theme_color_override("font_color", UI.tone_col(tone))
	h.add_child(vl)


func _preview(pv: Dictionary) -> void:
	PcWindow.clear(_pv)
	if pv.is_empty():
		_pv.add_child(UI.label("미리보기 정보가 없다.", "LabelMute"))
		return
	PcWindow.section(_pv, "바로 바뀌는 것")
	var cf := int(pv.get("cap_from", 0))
	var ct := int(pv.get("cap_to", 0))
	_kv("정원", "%d → %d명" % [cf, ct])
	var movers := int(pv.get("movers", 0))
	var vac := int(pv.get("vacancies", 0))
	if movers > 0:
		_kv("옮겨야 할 주민", "%d명 (같은 계층 빈자리 %d)" % [movers, vac], "warn")
	elif ct > cf:
		_kv("빈자리", "%d명분 — 나중에 이주민이 찬다" % (ct - cf))
	var parts: Array = []
	for l: Variant in UI.to_array(pv.get("labor", [])):
		var ld := UI.to_dict(l)
		parts.append("%s %s" % [str(ld.get("name", "")), ("+" if float(ld.get("delta", 0)) >= 0 else "") + UI.num(ld.get("delta", 0))])
	if not parts.is_empty():
		_kv("일손", " · ".join(parts))
	if pv.has("tax_delta"):
		var td := float(pv.get("tax_delta", 0.0))
		_kv("세수", "%s/일" % UI.won_signed(td), "good" if td >= 0 else "bad")
	var dt := UI.to_array(pv.get("demand_text", []))
	if not dt.is_empty():
		PcWindow.section(_pv, "입주가 끝나면 새로 찾는 것")
		for s: Variant in dt:
			var l2 := UI.label("· " + str(s), "LabelSmall", true)
			l2.custom_minimum_size.x = 900
			_pv.add_child(l2)


func _short_row(qty: int, have: int, mname: String, blockers: Array) -> void:
	PcWindow.clear(_short)
	if mat == "":
		return
	var need_good := ""
	var line := ""
	if qty > have:
		need_good = mat
		line = ("남은 %d채엔 %s %d 더(지금 %d / %d)." % [bids.size() - _fit_k, mname, qty - have, have, qty]) if (_batch and _fit_k > 0) else ("%s %d 모자람(지금 %d / %d)." % [mname, qty - have, have, qty])
	else:
		for b: Variant in blockers:
			if str(b).contains("설비 부품"):
				need_good = "parts"
				line = str(b)
	if need_good == "":
		return
	var src := ExpeditionWin.nearest_source(need_good)
	var l := UI.label(line + ((" 가장 빠른 곳: " + src) if src != "" else ""), "LabelGoldSmall", true)
	l.custom_minimum_size.x = 900
	_short.add_child(l)
	var b2 := PcButton.make("탐험 — 그 자재를 주는 곳", "expedition", "F4", "Button")
	b2.pressed.connect(func() -> void:
		close()
		ui.open_window("expedition", need_good))
	_short.add_child(b2)


## "목재이(가)" → "목재가"
static func _josa_fix(t: String) -> String:
	var re := RegEx.create_from_string("(\\S+?)이\\(가\\)")
	var m := re.search(t)
	while m != null:
		var w := m.get_string(1)
		t = t.substr(0, m.get_start()) + UI.josa(w, "가", "이") + t.substr(m.get_end())
		m = re.search(t)
	return t


func _fit_count() -> int:
	var lo := 0
	var hi := bids.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if bool(Q.dict("upgrade_preview", {"bids": bids.slice(0, mid), "material": mat}).get("ok", false)):
			lo = mid
		else:
			hi = mid - 1
	return lo


func _on_go() -> void:
	if mat == "" or ui == null or _go.disabled:
		return
	var go_bids: Array = bids.slice(0, _fit_k) if _fit_k > 0 else bids
	var r: Dictionary = ui.cmd("upgrade", {"bids": go_bids, "material": mat})
	if not bool(r.get("ok", false)):
		ui.toast(str(r.get("reason", "승급할 수 없다.")), "warn")
		_update()
		return
	Sfx.play("upgrade")
	ui.toast("승급 시작 — %d채" % go_bids.size(), "good", "up")
	close()


func _unhandled_key_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_on_go()


func _refresh() -> void:
	if _built and visible and not bids.is_empty():
		_info = Q.dict("info", {"bid": int(bids[0])})
		_update()


func target_rect(t: String) -> Rect2:
	if _card_btns.has(t):
		return (_card_btns[t] as Control).get_global_rect()
	if t == "go":
		return _go.get_global_rect()
	return Rect2()
