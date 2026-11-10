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
	_cards = UI.hbox(8)
	v.add_child(_cards)
	_same = UI.label("", "LabelSmall", true)
	_same.add_theme_color_override("font_color", UI.col("gold"))
	v.add_child(_same)
	var sb := Screen.scroll_body(4)
	_scroll = sb[0]
	_body = sb[1]
	v.add_child(_scroll)
	_why = UI.label("", "LabelSmall", true)
	_why.add_theme_color_override("font_color", UI.col("red_hi"))
	v.add_child(_why)
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
	var h := clampf(vh * 0.74, 520.0, vh - _bar - _top - 40.0)
	_panel.position = Vector2(0, vh - _bar - h)
	_panel.size = Vector2(size.x, h)
	_scrim.position = Vector2(0, _top)
	_scrim.size = Vector2(size.x, vh - _top)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


# ------------------------------------------------------------------ 열기
func open_single(bid: int, info: Dictionary) -> void:
	bids = [bid]
	_batch = false
	_info = info if not info.is_empty() else Q.dict("info", {"bid": bid})
	_open()


func open_batch(b: Array) -> void:
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
			cost = UI.to_dict(q.get("cost", cost))
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
	_why.text = UI.keep("  ".join(PackedStringArray(blockers.map(func(x: Variant) -> String: return "· " + str(x))))) if not ok else ""
	_why.visible = not ok and not blockers.is_empty()
	var mname := ""
	for mt: Variant in UI.to_array(up.get("materials", [])):
		if mt is Dictionary and str(mt.get("id", "")) == mat:
			mname = str(mt.get("name", mat))
	_go.label_text = "승급 — ₩%s · %s %d" % [UI.num(float(cost.get("money", 0))), mname, qty] if mname != "" else "자재를 고른다"
	_go.disabled = not ok or mat == ""
	_go.theme_type_variation = "ButtonJade" if not _go.disabled else ""
	_scroll.adopt_buttons()


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


func _on_go() -> void:
	if mat == "" or ui == null:
		return
	var r: Dictionary = ui.cmd("upgrade", {"bids": bids, "material": mat})
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
		c.custom_minimum_size = Vector2(150, 210)
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
		_have.text = "보유 %d / 필요 %d" % [have, need]
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
