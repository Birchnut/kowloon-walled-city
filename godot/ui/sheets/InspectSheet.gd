class_name InspectSheet
extends Screen
## InspectSheet — 도구 없이 칸을 누르면 뜨는 들여다보기. 전부 query("info", {pos}) 하나.
##  주거: 계층·자재 칩, 주민 n/정원, 행복, 세수/일, 수요(기본/승급 조건/여유 묶음, 막대·상태색·원인 문장 → 누르면 jump),
##        승급 버튼(upgrade.ready 일 때만, 아니면 막힌 이유) + "승급 가능한 n채 모두"(Q.upgradable)
##  시설: 상태 줄(원인), 인력, 들어감/나옴, 유지비, 범위 보기(range_preview → show_cells range), 일시정지/철거(확인)
##  골조·빈 칸·공사장: 한두 줄.

var pos: Variant = null
var info: Dictionary = {}
var _head: VBoxContainer
var _scroll: DragScroll
var _body: VBoxContainer
var _foot: VBoxContainer
var _up_btn: PixelButton
var _needs_box: Control
var _range_on: bool = false
var _sig: String = ""


func _init() -> void:
	super._init()
	make_sheet("", 0.5, 160.0)
	sheet.show_close = true
	_head = UI.vbox(4)
	sheet.body.add_child(_head)
	var sb := Screen.scroll_body(4)
	_scroll = sb[0]
	_body = sb[1]
	sheet.body.add_child(_scroll)
	_foot = UI.vbox(6)
	sheet.body.add_child(_foot)
	poll_sec = 1.0


func show_cell(p: Vector3i) -> void:
	pos = p
	_range_on = false
	Q.vcall("show_cells", [[], "range"])
	_sig = ""
	refresh()
	_scroll.scroll_to(0.0)


func _on_closed() -> void:
	Q.vcall("show_cells", [[], "select"])
	Q.vcall("show_cells", [[], "range"])
	pos = null
	info = {}


func on_event(n: String, _p: Dictionary) -> void:
	if n in ["cell_changed", "building_changed", "house_upgraded"]:
		_poll_t = minf(_poll_t, 0.1)


func refresh() -> void:
	if not (pos is Vector3i):
		return
	info = Q.dict("info", {"pos": pos})
	# 같은 내용이면 다시 짓지 않는다(막대가 깜빡이지 않게)
	var sig := JSON.stringify(info)
	if sig == _sig:
		return
	_sig = sig
	Screen.clear(_head)
	Screen.clear(_body)
	Screen.clear(_foot)
	_up_btn = null
	_needs_box = null
	match str(info.get("kind", "empty")):
		"house":
			_house()
		"facility":
			_facility()
		"site":
			_simple(true)
		_:
			_simple(false)
	_scroll.adopt_buttons()
	ui._sync_inset()


func _set_height(r: float) -> void:
	if not is_equal_approx(sheet.height_ratio, r):
		sheet.height_ratio = r
		sheet._place()


func _select(cells: Array) -> void:
	Q.vcall("show_cells", [cells, "select"])


# ------------------------------------------------------------------ 주거
func _house() -> void:
	_set_height(0.52)
	sheet.title = str(info.get("title", "집"))
	_select([pos])
	var chips := UI.hbox(6)
	_head.add_child(chips)
	chips.add_child(UI.tag(str(info.get("tier_name", "")), "gold"))
	var mn := str(info.get("material_name", ""))
	if mn != "" and str(info.get("material", "")) != "common":
		chips.add_child(UI.tag(mn, "paper"))
	if bool(info.get("scaffold", false)):
		chips.add_child(UI.tag("승급 공사 중", "jade"))
	chips.add_child(UI.spacer(true))
	chips.add_child(UI.label("%d층" % (int((pos as Vector3i).z) + 1), "LabelMute"))
	var st := UI.hbox(14)
	_head.add_child(st)
	var res := int(info.get("residents", 0))
	var cap := int(info.get("cap", 0))
	st.add_child(_stat("pop", "%d/%d명" % [res, cap], "LabelBold" if res >= cap else "LabelSmall"))
	st.add_child(_stat("", "행복 %d" % int(float(info.get("happiness", 0))), "LabelSmall"))
	st.add_child(_stat("coin", "₩%s/일" % str(snappedf(float(info.get("tax_per_day", 0.0)), 0.1)), "LabelGoldSmall"))

	# 수요 묶음
	var groups := {"basic": [], "advance": [], "luxury": []}
	var role_names := {"basic": "기본", "advance": "승급 조건", "luxury": "여유"}
	for n: Variant in UI.to_array(info.get("needs", [])):
		if n is Dictionary:
			var r := str(n.get("role", "basic"))
			if not groups.has(r):
				groups[r] = []
			groups[r].append(n)
			role_names[r] = str(n.get("role_name", role_names.get(r, r)))
	_needs_box = UI.vbox(4)
	_body.add_child(_needs_box)
	var any := false
	for r: String in ["basic", "advance", "luxury"]:
		var rows: Array = groups.get(r, [])
		if rows.is_empty():
			continue
		any = true
		_needs_box.add_child(Screen.section(role_names[r]))
		for n: Dictionary in rows:
			_needs_box.add_child(_need_row(n))
	if not any:
		_needs_box.add_child(UI.label("수요 정보가 아직 없다.", "LabelMute"))

	# 승급
	var up := UI.to_dict(info.get("upgrade", {}))
	var to_name := str(up.get("to_name", ""))
	var row := UI.hbox(8)
	_foot.add_child(row)
	var ready := bool(up.get("ready", false))
	if to_name != "":
		_up_btn = PixelButton.make("승급 → %s" % to_name, "up", "ButtonJade" if ready else "")
		_up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_up_btn.pressed.connect(func() -> void: ui.open_upgrade(int(info.get("bid", -1)), info))
		_up_btn.disabled = bool(info.get("scaffold", false))
		row.add_child(_up_btn)
	# 같은 계층 승급 가능 묶음
	var t := int(info.get("tier", 0))
	for g: Variant in Q.upgradable():
		if g is Dictionary and int(g.get("tier", 0)) == t and int(g.get("count", 0)) > 1:
			var all := PixelButton.make("가능한 %d채 모두" % int(g["count"]), "", "")
			all.small = true
			all.pressed.connect(func() -> void: ui.upgrade_all(t))
			row.add_child(all)
	var blockers := UI.to_array(up.get("blockers", []))
	if not ready and not blockers.is_empty():
		var parts := PackedStringArray()
		for x: Variant in blockers:
			parts.append("· " + str(x))
		var bl := UI.label("  ".join(parts), "LabelSmall", true)
		bl.add_theme_color_override("font_color", UI.col("gold"))
		_foot.add_child(bl)
	elif to_name == "" and not blockers.is_empty():
		_foot.add_child(UI.label(str(blockers[0]), "LabelMute"))


func _stat(icon: String, text: String, v: String) -> HBoxContainer:
	var h := UI.hbox(4)
	if icon != "":
		h.add_child(UI.icon_rect(icon))
	h.add_child(UI.label(text, v))
	return h


## 수요 한 줄: 상태 점 · 이름(쓰는 것) · 막대 · 원인 문장. jump 가 있으면 누를 수 있다.
func _need_row(n: Dictionary) -> Control:
	var jmp := UI.to_dict(n.get("jump", {}))
	var st := str(n.get("state", "ok"))
	var b := Button.new()
	b.theme_type_variation = "ButtonFlat"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := UI.vbox(0)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(v)
	var h := UI.hbox(6)
	v.add_child(h)
	var dot := ColorRect.new()
	dot.color = RatioBar.tone_color(st)
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	var nm := UI.label(str(n.get("name", "")), "LabelSmall")
	nm.custom_minimum_size.x = 150
	nm.clip_text = true
	h.add_child(nm)
	var using := str(n.get("using", ""))
	var bar := RatioBar.make(float(n.get("ratio", 0.0)), st, 8)
	h.add_child(bar)
	var pct := UI.label("%d%%" % int(round(float(n.get("ratio", 0.0)) * 100.0)), "LabelDim")
	pct.custom_minimum_size.x = 52
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(pct)
	if not jmp.is_empty():
		h.add_child(UI.icon_rect("chev_r", UI.col("gold")))
	else:
		h.add_child(UI.spacer(false, Vector2(24, 0)))
	var ct := str(n.get("cause_text", ""))
	var sub := ct if ct != "" else (("쓰는 것: " + using) if using != "" and st == "ok" else "")
	if sub != "":
		var l := UI.label(sub, "LabelSmall")
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.add_theme_color_override("font_color", UI.col("dim") if ct == "" else (UI.col("red_hi") if st == "bad" else UI.col("gold")))
		var m := UI.margin(14, 0, 0, 0)
		m.add_child(l)
		v.add_child(m)
	b.custom_minimum_size = Vector2(0, maxf(v.get_combined_minimum_size().y, 34.0 if sub == "" else 52.0))
	if not jmp.is_empty():
		b.pressed.connect(func() -> void: ui.jump(jmp))
	return b


# ------------------------------------------------------------------ 시설
func _facility() -> void:
	_set_height(0.46)
	sheet.title = str(info.get("title", "시설"))
	var size_n := _size_of(str(info.get("type", "")))
	var cells: Array = []
	var o: Vector3i = info.get("pos", pos) if info.get("pos") is Vector3i else pos
	for dx in size_n:
		for dy in size_n:
			cells.append(o + Vector3i(dx, dy, 0))
	_select(cells)
	var top := UI.hbox(10)
	_head.add_child(top)
	top.add_child(SignTile.make(SignTile.glyph_for(info), not bool(info.get("active", false))))
	var tc := UI.vbox(2)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tc)
	var active := bool(info.get("active", false))
	var cause := str(info.get("cause", ""))
	var status := UI.label(("● " if active else "○ ") + str(info.get("cause_text", "")), "LabelBold")
	status.add_theme_color_override("font_color", UI.col("jade_hi") if active and cause == "" else (UI.col("gold") if cause in ["paused", "storage"] else UI.col("red_hi")))
	tc.add_child(status)
	var desc := str(info.get("desc", ""))
	if desc != "":
		tc.add_child(UI.label(desc, "LabelDim", true))

	var staff := UI.to_dict(info.get("staff", {}))
	var sl := UI.to_array(staff.get("lines", []))
	if not sl.is_empty():
		_body.add_child(Screen.section("인력"))
		var r := UI.hbox(8)
		_body.add_child(r)
		var sr := float(staff.get("ratio", 0.0))
		r.add_child(RatioBar.make(sr, "ok" if sr >= 0.99 else ("warn" if sr > 0.0 else "bad"), 8))
		r.add_child(UI.label("%d%%" % int(round(sr * 100.0)), "LabelSmall"))
		for l: Variant in sl:
			_body.add_child(UI.label(str(l), "LabelSmall", true))
	var io := UI.to_array(info.get("io_lines", []))
	if not io.is_empty():
		_body.add_child(Screen.section("생산"))
		for l: Variant in io:
			_body.add_child(UI.label(str(l), "LabelSmall", true))
	_body.add_child(Screen.section("운영"))
	_body.add_child(Screen.kv("유지비", "₩%s/일" % str(snappedf(float(info.get("upkeep", 0.0)), 0.1))))
	var rng := int(info.get("range", 0))
	if rng > 0:
		_body.add_child(Screen.kv("범위", "%d칸 · 닿는 주거 %d채" % [rng, int(info.get("served_houses", 0))]))

	var row := UI.hbox(6)
	_foot.add_child(row)
	if rng > 0:
		var rb := PixelButton.make("범위 보기", "eye", "ButtonChip")
		rb.small = true
		rb.toggle_mode = true
		rb.button_pressed = _range_on
		rb.pressed.connect(func() -> void: _toggle_range(rb.button_pressed))
		row.add_child(rb)
		if _range_on:
			_show_range(true)
	row.add_child(UI.spacer(true))
	_actions(row)


func _toggle_range(on: bool) -> void:
	_range_on = on
	_show_range(on)


func _show_range(on: bool) -> void:
	if not on:
		Q.vcall("show_cells", [[], "range"])
		return
	var o: Variant = info.get("pos", pos)
	var rp := Q.dict("range_preview", {"type": str(info.get("type", "")), "pos": o})
	Q.vcall("show_cells", [UI.to_array(rp.get("cells", [])), "range"])


func _size_of(type: String) -> int:
	for cat: Variant in Q.list("build_menu"):
		for it: Variant in UI.to_array(UI.to_dict(cat).get("items", [])):
			if it is Dictionary and str(it.get("id", "")) == type:
				return maxi(1, int(it.get("size", 1)))
	return 1


func _actions(row: HBoxContainer) -> void:
	for a: Variant in UI.to_array(info.get("actions", [])):
		if not (a is Dictionary):
			continue
		var id := str(a.get("id", ""))
		var b := PixelButton.make(str(a.get("label", id)), "", "ButtonRed" if id == "demolish" else "")
		b.small = true
		b.disabled = not bool(a.get("enabled", true))
		b.pressed.connect(_on_action.bind(id))
		row.add_child(b)
		if b.disabled and str(a.get("reason", "")) != "":
			_foot.add_child(UI.label(str(a["reason"]), "LabelMute", true))


func _on_action(id: String) -> void:
	match id:
		"pause":
			var r: Dictionary = ui.cmd("pause", {"bid": int(info.get("bid", -1)), "on": not bool(info.get("paused", false))})
			if not bool(r.get("ok", false)):
				ui.toast(str(r.get("reason", "")), "warn")
			_sig = ""
			refresh()
		"demolish":
			confirm_demolish(ui, pos, info)


## 철거 확인(들여다보기·짓기의 철거 도구가 같이 쓴다). 잃는 것을 보여 주고 확인받는다.
static func confirm_demolish(root: Node, p: Variant, inf: Dictionary) -> void:
	var c := Q.can_full("demolish", {"pos": p})
	if not bool(c.get("ok", false)):
		root.toast(str(c.get("reason", "철거할 수 없다.")), "warn")
		return
	var lines: Array = []
	match str(inf.get("kind", "")):
		"house":
			var res := int(inf.get("residents", 0))
			lines.append("%s %d명이 집을 잃는다." % [str(inf.get("tier_name", "주민")), res] if res > 0 else "빈집이다.")
			if str(inf.get("material", "")) not in ["", "common"]:
				lines.append("%s 외관과 들인 자재는 돌아오지 않는다." % str(inf.get("material_name", "")))
		"facility":
			lines.append("들인 돈과 자재는 돌아오지 않는다.")
			var sv := int(inf.get("served_houses", 0))
			if sv > 0:
				lines.append("이 시설에 기대던 주거 %d채가 영향을 받는다." % sv)
		"site":
			lines.append("공사에 들인 것은 돌아오지 않는다.")
	lines.append("위에 무언가 있으면 골조는 남는다.")
	Modal.confirm(root.modals, {"kicker": "철거", "title": "%s 허문다" % UI.josa(str(inf.get("title", "이것")), "를", "을"),
		"lines": lines, "ok_text": "허문다", "cancel_text": "그만둔다", "danger": true}, func() -> void:
			var r: Dictionary = root.cmd("demolish", {"pos": p})
			if not bool(r.get("ok", false)):
				root.toast(str(r.get("reason", "")), "warn")
			elif root.screen == "inspect":
				root.close_screen())


# ------------------------------------------------------------------ 그 밖
func _simple(site: bool) -> void:
	_set_height(0.2 if not site else 0.26)
	sheet.title = str(info.get("title", "빈 칸"))
	_select([pos])
	for l: Variant in UI.to_array(info.get("lines", [])):
		_head.add_child(UI.label(str(l), "LabelSmall", true))
	if site:
		var row := UI.hbox(6)
		row.add_child(UI.spacer(true))
		_foot.add_child(row)
		_actions(row)


func target_rect(t: String) -> Rect2:
	match t:
		"upgrade":
			return _up_btn.get_global_rect() if _up_btn != null and is_instance_valid(_up_btn) else Rect2()
		"needs":
			return _needs_box.get_global_rect() if _needs_box != null and is_instance_valid(_needs_box) else Rect2()
	return sheet.get_global_rect() if sheet.is_open else Rect2()
