class_name UpgradeDialog
extends Control
## UpgradeDialog — 승급 창(한 채 또는 여러 채 일괄). 아래에서 올라오는 큰 판, 위로는 도시가 보인다.
##  1) 세 자재 카드(목재·철제·콘크리트): 보유/필요 + 목표 계층 × 자재 외관 미리보기(assets/ui/house_previews)
##     → 세 자재의 값이 같다는 걸 한 줄로 못 박는다.
##  2) 미리보기(질의 그대로): 정원 from→to, 이주해야 할 주민·빈자리, 계층별 노동력 변화, 세수 변화, 수요 문장, 비용
##  3) 승급 버튼 하나. 성공하면 창을 닫는다(뷰의 비계·먼지 연출을 가리지 않게).
## 한 채: query("info").upgrade, 여러 채: query("upgrade_preview", {bids, mat}) — 없으면 can("upgrade") 로 버틴다.

const PREVIEW := "res://assets/ui/house_previews/t%d_%s.png"

var ui: Node = null
var bids: Array = []
var mat: String = ""
var _info: Dictionary = {}          # 첫 집의 info(이름표·자재 목록)
var _batch: bool = false
var _scrim: ColorRect
var _panel: PanelContainer
var _title: Label
var _kicker: Label
var _cards: HBoxContainer
var _same: Label
var _scroll: DragScroll
var _body: VBoxContainer
var _go: PixelButton
var _why: Label
var _card_btns: Dictionary = {}
var _top: float = 110.0
var _bar: float = 80.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.35)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			close())
	add_child(_scrim)
	_panel = UI.panel("PanelSheet")
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var m := UI.margin(12, 8, 12, 10)
	_panel.add_child(m)
	var v := UI.vbox(8)
	m.add_child(v)
	var hr := UI.hbox(8)
	v.add_child(hr)
	var hc := UI.vbox(0)
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(hc)
	_kicker = UI.label("승급", "LabelGoldSmall")
	hc.add_child(_kicker)
	_title = UI.label("", "LabelHead", true)
	hc.add_child(_title)
	var x := PixelButton.make("", "close", "ButtonRed")
	x.pressed.connect(close)
	hr.add_child(x)
	_tier_row = UI.hbox(4)
	v.add_child(_tier_row)
	_cards = UI.hbox(8)
	v.add_child(_cards)
	# 줄바꿈 글자(같은 값 한 줄·막힌 이유)는 끌기 목록 안에 둔다 — 밖에 두면 판이 글자 높이만큼 늘어나
	# 승급 버튼이 화면 아래로 밀려 사라졌다(통합). 버튼은 늘 판 맨 아래에 보인다.
	var sb := Screen.scroll_body(4)
	_scroll = sb[0]
	var inner: VBoxContainer = sb[1]
	v.add_child(_scroll)
	_same = UI.label("", "LabelSmall", true)
	_same.add_theme_color_override("font_color", UI.col("gold"))
	inner.add_child(_same)
	_why = UI.label("", "LabelSmall", true)
	_why.add_theme_color_override("font_color", UI.col("red_hi"))
	inner.add_child(_why)
	_body = UI.vbox(4)
	inner.add_child(_body)
	_go = PixelButton.make("승급", "up", "ButtonJade")
	_go.pressed.connect(_on_go)
	v.add_child(_go)


func set_area(top: float, bar: float) -> void:
	_top = top
	_bar = bar
	_place()


func _place() -> void:
	if not is_inside_tree():
		return
	var vh := size.y
	var h := clampf(vh * (0.72 if _groups.size() > 1 else 0.64), 560.0, maxf(560.0, vh - _bar - _top - 40.0))
	_panel.position = Vector2(0, vh - _bar - h)
	_panel.size = Vector2(size.x, h)
	_scrim.position = Vector2(0, _top)
	_scrim.size = Vector2(size.x, vh - _top)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


# ------------------------------------------------------------------ 열기
func open_single(bid: int, info: Dictionary) -> void:
	_groups = []
	_build_tier_row(0)
	bids = [bid]
	_batch = false
	_info = info if not info.is_empty() else Q.dict("info", {"bid": bid})
	_open()


## 계층 묶음들 [{tier, tier_name, count, bids}] — 계층 칩으로 고른다.
var _groups: Array = []
var _tier_row: HBoxContainer


func open_groups(groups: Array, tier: int = 0) -> void:
	_groups = groups
	var pick: Dictionary = groups[0]
	for g: Dictionary in groups:
		if int(g.get("tier", 0)) == tier:
			pick = g
	_build_tier_row(int(pick.get("tier", 0)))
	open_batch(UI.to_array(pick.get("bids", [])), true)


func _build_tier_row(cur: int) -> void:
	Screen.clear(_tier_row)
	_tier_row.visible = _groups.size() > 1
	if _groups.size() <= 1:
		return
	var sc := DragScroll.new()
	sc.horizontal = true
	sc.custom_minimum_size = Vector2(0, 48)
	var seg := Segmented.new()
	seg.small_text = true
	seg.equal_width = false
	seg.chip_min = Vector2(56, 44)
	var opts: Array = []
	for g: Dictionary in _groups:
		opts.append({"id": str(g.get("tier", 0)), "name": "%s %d채" % [str(g.get("tier_name", "")), int(g.get("count", 0))]})
	seg.set_options(opts, str(cur))
	seg.selected.connect(func(id: String) -> void:
		for g: Dictionary in _groups:
			if str(g.get("tier", 0)) == id:
				open_batch(UI.to_array(g.get("bids", [])), true))
	sc.set_content(seg)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier_row.add_child(sc)


func open_batch(b: Array, keep_groups: bool = false) -> void:
	if not keep_groups:
		_groups = []
		_build_tier_row(0)
	bids = b.duplicate()
	_batch = bids.size() > 1
	_info = Q.dict("info", {"bid": int(bids[0])}) if not bids.is_empty() else {}
	_open()


func _open() -> void:
	var up := UI.to_dict(_info.get("upgrade", {}))
	var mats := UI.to_array(up.get("materials", []))
	# 기본 선택: 보유량이 가장 많은 자재(가장 덜 막히는 쪽) — 표시 기본값일 뿐, 고르는 건 플레이어
	mat = ""
	var best := -1
	for mt: Variant in mats:
		if mt is Dictionary and int(mt.get("have", 0)) > best:
			best = int(mt.get("have", 0))
			mat = str(mt.get("id", ""))
	visible = true
	_place()
	_build_cards(mats, int(up.get("to_tier", 0)))
	_refresh()
	modulate.a = 0.0
	_panel.position.y += 40
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.12)
	tw.tween_property(_panel, "position:y", _panel.position.y - 40, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Q.vcall("set_bottom_inset", [_panel.size.y])


func close() -> void:
	if not visible:
		return
	visible = false
	if ui != null:
		ui._sync_inset()


func _build_cards(mats: Array, to_tier: int) -> void:
	Screen.clear(_cards)
	_card_btns.clear()
	for mt: Variant in mats:
		if not (mt is Dictionary):
			continue
		var id := str(mt.get("id", ""))
		var c := MatCard.make(id, str(mt.get("name", id)), PREVIEW % [to_tier, id])
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size.x = 100
		c.clip_contents = true
		c.pressed.connect(func() -> void:
			mat = id
			_refresh())
		_cards.add_child(c)
		_card_btns[id] = c


# ------------------------------------------------------------------ 내용
func _refresh() -> void:
	var up := UI.to_dict(_info.get("upgrade", {}))
	var n := bids.size()
	var from_name := str(_info.get("tier_name", ""))
	var to_name := str(up.get("to_name", ""))
	_kicker.text = "승급 · %d채" % n if _batch else "승급"
	_title.text = UI.keep(("%s %d채 → %s" % [from_name, n, to_name]) if _batch else ("%s → %s" % [str(_info.get("title", "집")), to_name]))
	# 미리보기·비용: 한 채면 info, 여러 채면 upgrade_preview(없으면 can)
	var pv: Dictionary = UI.to_dict(up.get("preview", {}))
	var cost: Dictionary = UI.to_dict(up.get("cost", {}))
	var ok := bool(up.get("ready", false))
	var blockers: Array = UI.to_array(up.get("blockers", []))
	var have_preview := true
	if _batch or mat != "":
		var q: Variant = Game.query("upgrade_preview", {"bids": bids, "material": mat})
		if q is Dictionary:
			pv = q
			var qc := UI.to_dict(q.get("cost", {}))
			if int(qc.get("qty", 0)) > 0 or float(qc.get("money", 0)) > 0.0:
				cost = qc
			ok = bool(q.get("ok", ok))
			blockers = UI.to_array(q.get("blockers", blockers))
		else:
			var c := Q.can_full("upgrade", {"bids": bids, "material": mat})
			ok = bool(c.get("ok", false))
			blockers = [] if ok else [str(c.get("reason", ""))]
			if _batch:
				have_preview = false
				cost = {"money": c.get("money", 0), "qty": c.get("qty", 0), "extra": c.get("extra", {})}
	var qty := int(cost.get("qty", 0))
	for id: String in _card_btns:
		var have := 0
		for mt: Variant in UI.to_array(up.get("materials", [])):
			if mt is Dictionary and str(mt.get("id", "")) == id:
				have = int(mt.get("have", 0))
		(_card_btns[id] as MatCard).set_state(id == mat, have, qty)
	var extra := UI.to_dict(cost.get("extra", {}))
	var extra_t := Screen.goods_text(extra, ui.good_names() if ui != null else {})
	_same.text = UI.keep("세 자재 모두 같은 값: ₩%s + 자재 %d%s. 고른 자재가 이 집의 얼굴이 된다." % [UI.num(float(cost.get("money", 0))), qty, (" + " + extra_t) if extra_t != "" else ""])

	Screen.clear(_body)
	if not have_preview:
		_body.add_child(UI.label("여러 채 합산 미리보기는 아직 준비 중이다(시뮬 질의 upgrade_preview). 한 채씩 보면 자세히 나온다.", "LabelMute", true))
	else:
		_preview(pv)
	_last_blockers = blockers.duplicate()
	_why.text = UI.keep("  ".join(PackedStringArray(blockers.map(func(x: Variant) -> String: return "· " + _josa_fix(str(x)))))) if not ok else ""
	_why.visible = not ok and not blockers.is_empty()
	var mname := ""
	for mt: Variant in UI.to_array(up.get("materials", [])):
		if mt is Dictionary and str(mt.get("id", "")) == mat:
			mname = str(mt.get("name", mat))
	_go.label_text = "승급 — ₩%s · %s %d" % [UI.num(float(cost.get("money", 0))), mname, qty] if mname != "" else "자재를 고른다"
	# 여러 채가 다 안 되면, 되는 만큼(앞에서부터 k채)을 시뮬에 물어 버튼을 "k채만"으로 바꾼다(판정은 upgrade_preview)
	_fit_k = 0
	if not ok and _batch and mat != "":
		_fit_k = _fit_count()
		if _fit_k > 0:
			var q2: Variant = Game.query("upgrade_preview", {"bids": bids.slice(0, _fit_k), "material": mat})
			var c2 := UI.to_dict(UI.to_dict(q2).get("cost", {}))
			_go.label_text = "%d채만 승급 — ₩%s · %s %d" % [_fit_k, UI.num(float(c2.get("money", 0))), mname, int(c2.get("qty", 0))]
			ok = true
			_why.visible = false   # 빨간 '모자란다' 대신 아래 금색 줄이 남은 채와 모자란 양을 말한다
	_go.disabled = not ok or mat == ""
	_go.theme_type_variation = "ButtonJade" if not _go.disabled else ""
	_short_row(up, qty, mname)
	_scroll.adopt_buttons()
	_fit_size.call_deferred()


## 자재가 모자라면: 정확히 얼마가 모자란지 + 그 자재를 주는 가장 빠른 탐험 + [탐험] 버튼(그 자재를 비춘 지도).
## 판정은 시뮬(blockers·have·qty) 그대로 — 뺄셈만 한다.
func _short_row(up: Dictionary, qty: int, mname: String) -> void:
	if _short != null and is_instance_valid(_short):
		_short.queue_free()
	_short = null
	if mat == "":
		return
	var have := 0
	for mt: Variant in UI.to_array(up.get("materials", [])):
		if mt is Dictionary and str(mt.get("id", "")) == mat:
			have = int(mt.get("have", 0))
	var need_good := ""
	var line := ""
	if qty > have:
		need_good = mat
		if _batch and _fit_k > 0:
			line = "%s %d 모자람 — 남은 %d채까지 하려면 %s %d 더(지금 %d / %d)." % [mname, qty - have, bids.size() - _fit_k, mname, qty - have, have, qty]
		else:
			line = "%s %d 모자람(지금 %d / %d)." % [mname, qty - have, have, qty]
	else:
		# 자재는 되는데 막혔다 — 설비 부품 같은 추가 재료(시뮬 이유 문장에 이름이 있다)
		for b: Variant in UI.to_array(_last_blockers):
			if str(b).contains("설비 부품"):
				need_good = "parts"
				line = str(b)
	if need_good == "":
		return
	var src := ExpeditionScreen.nearest_source(need_good)
	var gname := "설비 부품" if need_good == "parts" else mname
	_short = UI.vbox(4)
	var l := UI.label(line + ((" 가장 빠른 곳: " + src) if src != "" else ""), "LabelSmall", true)
	l.add_theme_color_override("font_color", UI.col("gold"))
	_short.add_child(l)
	var b2 := PixelButton.make("탐험 — %s 주는 곳" % gname, "chev_r", "")
	b2.min_size = Vector2(0, 44)
	b2.pressed.connect(func() -> void:
		close()
		if ui != null:
			ui.jump({"screen": "expedition", "arg": need_good}))
	_short.add_child(b2)
	_why.get_parent().add_child(_short)
	_why.get_parent().move_child(_short, _why.get_index() + 1)
	_scroll.adopt_buttons()


var _short: Control = null


## 시뮬 문장의 "목재이(가)" → "목재가"(받침으로 고른다 — INTEG (b) 2 가 고쳐질 때까지).
static func _josa_fix(t: String) -> String:
	var re := RegEx.create_from_string("(\\S+?)이\\(가\\)")
	var m := re.search(t)
	while m != null:
		var w := m.get_string(1)
		t = t.substr(0, m.get_start()) + UI.josa(w, "가", "이") + t.substr(m.get_end())
		m = re.search(t)
	return t
var _last_blockers: Array = []


## 내용이 바뀌는 동안 판이 늘어난 채로 남지 않게 높이만 다시 맞춘다(위치 트윈은 건드리지 않는다).
func _fit_size() -> void:
	if not visible:
		return
	var vh := size.y
	var h := clampf(vh * (0.72 if _groups.size() > 1 else 0.64), 560.0, maxf(560.0, vh - _bar - _top - 40.0))
	_panel.size = Vector2(size.x, h)


func _preview(pv: Dictionary) -> void:
	if pv.is_empty():
		_body.add_child(UI.label("미리보기 정보가 없다.", "LabelMute"))
		return
	_body.add_child(Screen.section("바로 바뀌는 것"))
	var cf := int(pv.get("cap_from", 0))
	var ct := int(pv.get("cap_to", 0))
	_body.add_child(Screen.kv("정원", "%d → %d명" % [cf, ct], "LabelBold"))
	var movers := int(pv.get("movers", 0))
	var vac := int(pv.get("vacancies", 0))
	if movers > 0:
		var l := Screen.kv("이주해야 할 주민", "%d명 (같은 계층 빈자리 %d)" % [movers, vac], "LabelGoldSmall")
		_body.add_child(l)
		if vac < movers:
			var w := UI.label("빈자리가 모자라면 남는 주민은 대기 주민이 되어 빈집을 기다린다.", "LabelSmall", true)
			w.add_theme_color_override("font_color", UI.col("gold"))
			_body.add_child(w)
	elif ct > cf:
		_body.add_child(Screen.kv("빈자리", "%d명분 — 나중에 이주민이 찬다" % (ct - cf)))
	var labor := UI.to_array(pv.get("labor", []))
	if not labor.is_empty():
		var parts: Array = []
		for l: Variant in labor:
			if l is Dictionary:
				parts.append("%s %s" % [str(l.get("name", "")), Screen.signed(float(l.get("delta", 0)))])
		_body.add_child(Screen.kv("노동력", " · ".join(parts)))
	if pv.has("tax_after_now") or pv.has("tax_delta"):
		var td := float(pv.get("tax_delta", 0.0))
		_body.add_child(Screen.kv("세수", "%s/일" % Screen.signed(td), "LabelJade" if td >= 0 else "LabelRed"))
	var dt := UI.to_array(pv.get("demand_text", []))
	if not dt.is_empty():
		_body.add_child(Screen.section("입주가 끝나면"))
		if pv.has("tax_full"):
			_body.add_child(Screen.kv("세수(만실)", "₩%s/일" % str(snappedf(float(pv["tax_full"]), 0.1))))
		for s: Variant in dt:
			_body.add_child(UI.label("· " + str(s), "LabelSmall", true))


var _fit_k: int = 0


## 앞에서부터 몇 채까지 지금 승급되나(0 = 한 채도 안 됨). 이분 탐색으로 upgrade_preview 를 몇 번만 묻는다.
func _fit_count() -> int:
	var lo := 0
	var hi := bids.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		var q: Variant = Game.query("upgrade_preview", {"bids": bids.slice(0, mid), "material": mat})
		if q is Dictionary and bool(q.get("ok", false)):
			lo = mid
		else:
			hi = mid - 1
	return lo


func _on_go() -> void:
	if mat == "" or ui == null:
		return
	var go_bids: Array = bids.slice(0, _fit_k) if _fit_k > 0 else bids
	var r: Dictionary = ui.cmd("upgrade", {"bids": go_bids, "material": mat})
	if not bool(r.get("ok", false)):
		ui.toast(str(r.get("reason", "승급할 수 없다.")), "warn")
		_refresh()
		return
	close()
	if ui.screen == "inspect":
		ui.close_screen()
	Q.vcall("show_cells", [[], "select"])


func target_rect(t: String) -> Rect2:
	if not visible:
		return Rect2()
	if t == "go":
		return _go.get_global_rect()
	if _card_btns.has(t):
		return (_card_btns[t] as Control).get_global_rect()
	if t == "cards":
		return _cards.get_global_rect()
	return Rect2()


## 자재 카드: 외관 미리보기 + 이름 + 보유/필요. 고르면 금 테두리(상아 패).
class MatCard extends Button:
	var _img: TextureRect
	var _name: Label
	var _have: Label
	var _sel := false

	static func make(id: String, nm: String, tex_path: String) -> MatCard:
		var c := MatCard.new()
		c.theme_type_variation = "ButtonFlat"
		c.focus_mode = Control.FOCUS_NONE
		c.custom_minimum_size = Vector2(150, 222)
		var v := UI.vbox(2)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 6
		v.offset_top = 6
		v.offset_right = -6
		v.offset_bottom = -6
		c.add_child(v)
		c._img = TextureRect.new()
		c._img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c._img.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		c._img.custom_minimum_size = Vector2(0, 136)
		c._img.texture = load(tex_path) if ResourceLoader.exists(tex_path) else null
		v.add_child(c._img)
		c._name = UI.label(nm, "LabelBold")
		c._name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(c._name)
		c._have = UI.label("", "LabelSmall")
		c._have.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(c._have)
		c.set_meta("id", id)
		return c

	func set_state(sel: bool, have: int, need: int) -> void:
		_sel = sel
		_have.text = "보유 %d/%d" % [have, need]
		_have.add_theme_color_override("font_color", UI.col("jade_hi") if have >= need else UI.col("red_hi"))
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, UI.col("out"))
		draw_rect(r.grow(-2), UI.col("paper") if _sel else UI.col("ink2"))
		draw_rect(r.grow(-6), UI.col("ink1") if not _sel else UI.col("gold_dd"))
		if _sel:
			draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 4)), UI.col("gold"))
		if _img.texture == null:
			draw_string(UI.font("small"), Vector2(20, 80), "미리보기 없음", HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size("small"), UI.col("mute"))
