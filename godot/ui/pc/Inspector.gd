class_name Inspector
extends PanelContainer
## 오른쪽 살피기 판. 고른 건물(클릭)을 보여 주고, 고른 것이 없으면 마우스 아래 건물을 옅게 미리 보여 준다.
##  주거: 사는 사람/정원·들어오는 중·행복·세금, 불·병 상태와 수리, 수요 줄(상태·원인·고칠 곳 버튼), 승급.
##  시설: 가동·일손·효율·원인, 들고 나는 것, 범위(보기 켜기), 멈춤, 수리, 공사 진행, 철거.
##  골조·빈 칸: 제목과 줄.
## 읽는 것: info{pos|bid}(1초·building_changed). 보내는 것: pause / repair / demolish(확인) — UIRoot.cmd 를 지난다.

signal jump(target: Variant)
signal closed

const W := 420.0

var ui: Node = null
var selected_pos: Variant = null     # Vector3i | null — 클릭으로 고정
var hover_pos: Variant = null
var info: Dictionary = {}
var show_range: bool = false
var _v: VBoxContainer
var _t: float = 0.0
var _sig: String = ""
var _is_hover := false


func _init() -> void:
	theme_type_variation = "PanelGold"
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(W, 0)
	visible = false


func _ready() -> void:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(sc)
	_v = UI.vbox(6)
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_v)


func select(pos: Variant) -> void:
	selected_pos = pos
	show_range = false
	_sig = ""
	_refresh()


func deselect() -> void:
	if selected_pos == null and not visible:
		return
	selected_pos = null
	show_range = false
	Q.vcall("show_cells", [[], "select"])
	Q.vcall("show_cells", [[], "range"])
	_sig = ""
	_refresh()
	closed.emit()


func set_hover(pos: Variant) -> void:
	if pos == hover_pos:
		return
	hover_pos = pos
	if selected_pos == null:
		_sig = ""
		_refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0 and visible:
		_t = 1.0
		_refresh()


func refresh_now() -> void:
	_t = 0.0


func _refresh() -> void:
	var pos: Variant = selected_pos if selected_pos != null else hover_pos
	_is_hover = selected_pos == null
	if not (pos is Vector3i):
		visible = false
		info = {}
		return
	info = Q.dict("info", {"pos": pos})
	var kind := str(info.get("kind", ""))
	if info.is_empty() or (kind in ["", "empty"] and _is_hover):
		visible = false
		return
	var sig := JSON.stringify(info).md5_text() + str(_is_hover) + str(show_range)
	visible = true
	if sig == _sig:
		return
	_sig = sig
	PcWindow.clear(_v)
	_header(kind)
	match kind:
		"house":
			_house()
		"facility", "site":
			_facility()
		_:
			for ln: Variant in UI.to_array(info.get("lines", [])):
				_v.add_child(_wrap(str(ln), "LabelSmall"))
	if not _is_hover:
		var fp := UI.to_array(info.get("footprint", []))
		if fp.is_empty() and pos is Vector3i:
			fp = [pos]
		Q.vcall("show_cells", [fp, "select"])
	_range_cells()
	_fit_h.call_deferred()


var max_h: float = 700.0


func _fit_h() -> void:
	var sb := get_theme_stylebox("panel")
	var want := _v.get_combined_minimum_size().y + (sb.get_minimum_size().y if sb != null else 0.0)
	custom_minimum_size = Vector2(W, minf(want, max_h))
	size = custom_minimum_size


func _wrap(t: String, var_name: String) -> Label:
	var l := UI.label(t, var_name, true)
	l.custom_minimum_size.x = W - 40
	return l


func _header(kind: String) -> void:
	var h := UI.hbox(8)
	_v.add_child(h)
	var pic := "house" if kind == "house" else (UI.cat_picto(ui.build.cat_of(str(info.get("type", "")))) if ui != null and kind in ["facility", "site"] else "floor")
	h.add_child(Picto.make(pic, UI.col("gold_hi"), 3))
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var t := UI.label(str(info.get("title", "")), "LabelGold", true)
	t.custom_minimum_size.x = W - 150
	tv.add_child(t)
	var sub := ""
	if kind == "house":
		sub = "%s · %s" % [str(info.get("tier_name", "")), str(info.get("material_name", ""))]
	elif kind in ["facility", "site"]:
		sub = "%d×%d%s" % [int(info.get("w", info.get("size", 1))), int(info.get("h", info.get("size", 1))), (" · %d개 층" % int(info.get("d", 1))) if int(info.get("d", 1)) > 1 else ""]
	if _is_hover:
		sub += "  — 마우스 아래 · 눌러서 고정"
	tv.add_child(UI.label(sub, "LabelDim"))
	if not _is_hover:
		var x := PcButton.make("", "close", "", "ButtonFlat")
		x.min_h = 32
		x.pressed.connect(deselect)
		TipLayer.set_tip(x, "닫기 [오른쪽 클릭 · Esc]")
		h.add_child(x)


func _kv(g: GridContainer, k: String, v: String, tone: String = "") -> void:
	var kl := UI.label(k, "LabelDim")
	kl.custom_minimum_size.x = 120
	g.add_child(kl)
	# 값은 줄을 바꾼다(긴 문장 — "수요가 채워지면 더 들어온다(0/4)" — 이 판 밖으로 나가지 않게)
	var l := UI.label(v, "LabelSmall", true)
	l.custom_minimum_size.x = W - 40.0 - 120.0 - 8.0
	if tone != "":
		l.add_theme_color_override("font_color", UI.tone_col(tone))
	g.add_child(l)


# ------------------------------------------------------------------ 주거
func _house() -> void:
	var burn := str(info.get("burn", ""))
	if burn != "" or bool(info.get("sick", false)):
		_hazard_box(burn, bool(info.get("sick", false)))
	var g := GridContainer.new()
	g.columns = 2
	_v.add_child(g)
	var res := int(info.get("residents", 0))
	var cap := int(info.get("cap", 0))
	_kv(g, "사는 사람", "%d / %d명" % [res, cap], "good" if res >= cap and cap > 0 else "")
	var arr := str(info.get("arriving_text", ""))
	if arr != "":
		_kv(g, "들어오는 중", arr)
	_kv(g, "행복", "%d" % int(float(info.get("happiness", 0))), "good" if float(info.get("happiness", 0)) >= 60 else ("bad" if float(info.get("happiness", 0)) < 35 else ""))
	_kv(g, "세금", "%s/일" % UI.won(info.get("tax_per_day", 0)))
	PcWindow.section(_v, "수요")
	for n: Variant in UI.to_array(info.get("needs", [])):
		_need_row(UI.to_dict(n))
	# 승급
	var up := UI.to_dict(info.get("upgrade", {}))
	if not up.is_empty() and str(up.get("to_name", "")) != "":
		PcWindow.section(_v, "승급 → %s" % str(up.get("to_name", "")))
		var blockers := UI.to_array(up.get("blockers", []))
		if bool(up.get("ready", false)) and blockers.is_empty():
			_v.add_child(_wrap("조건이 다 찼다. 자재 하나를 골라 올린다.", "LabelJadeSmall"))
		elif not blockers.is_empty():
			_v.add_child(_wrap("· " + str(blockers[0]) + ("  (그 밖에 %d가지)" % (blockers.size() - 1) if blockers.size() > 1 else ""), "LabelSmall"))
		var row := UI.hbox(6)
		_v.add_child(row)
		var ub := PcButton.make("승급…", "up", "U", "ButtonJade")
		ub.disabled = not bool(up.get("ready", false))
		ub.pressed.connect(func() -> void: ui.open_upgrade(int(info.get("bid", -1)), info))
		TipLayer.set_tip(ub, "승급 [U]\n세 자재(목재·철제·콘크리트) 중 하나를 골라 올린다. 셋은 성능이 같다 — 모양만 다르다.")
		row.add_child(ub)
		var ab := PcButton.make("같은 계층 모두", "", "", "Button")
		ab.pressed.connect(func() -> void: ui.upgrade_all(int(info.get("tier", 0))))
		TipLayer.set_tip(ab, "일괄 승급\n지금 올릴 수 있는 같은 계층 집을 한꺼번에.")
		row.add_child(ab)
	_actions_row(false)


func _need_row(n: Dictionary) -> void:
	var st := str(n.get("state", "ok"))
	var b := ClickRow.new()
	var v := UI.vbox(1)
	b.add_child(v)
	var h := UI.hbox(6)
	v.add_child(h)
	var dot := Picto.make("dot", UI.state_col(st))
	h.add_child(dot)
	var nm := UI.label(str(n.get("name", "")), "LabelSmall")
	nm.custom_minimum_size.x = 118
	nm.clip_text = true
	h.add_child(nm)
	var role := str(n.get("role_name", ""))
	var rl := UI.label(role, "LabelMute")
	rl.custom_minimum_size.x = 80
	h.add_child(rl)
	var ratio := float(n.get("ratio", 0.0))
	h.add_child(PcWindow.bar(ratio, st, 64, 10))
	h.add_child(UI.label(UI.pct(ratio), "LabelSmall"))
	var cause := str(n.get("cause_text", ""))
	if cause != "" and st != "ok":
		var cl := UI.label(cause, "LabelDim", true)
		cl.custom_minimum_size.x = W - 70
		v.add_child(cl)
	var j: Variant = n.get("jump", {})
	b.pressed.connect(func() -> void: jump.emit(j))
	var alts := UI.to_array(n.get("jump_alt", []))
	TipLayer.set_tip(b, "%s — %s\n%s\n누르면 고칠 곳으로." % [str(n.get("name", "")), {"ok": "채워짐", "warn": "모자람", "bad": "없음"}.get(st, st), cause if cause != "" else "문제없다."])
	_v.add_child(b)
	if not alts.is_empty() and st != "ok":
		var row := UI.hbox(4)
		_v.add_child(row)
		row.add_child(UI.label("    얻는 곳:", "LabelMute"))
		for a: Variant in alts.slice(0, 3):
			var ad := UI.to_dict(a)
			var ab := PcButton.make(str(ad.get("label", "")), "", "", "Button")
			ab.min_h = 28
			var aj := {"screen": ad.get("screen", ""), "arg": ad.get("arg", "")}
			ab.pressed.connect(func() -> void: jump.emit(aj))
			row.add_child(ab)


func _hazard_box(burn: String, sick: bool) -> void:
	var p := UI.panel("PanelRed")
	_v.add_child(p)
	var v := UI.vbox(4)
	p.add_child(v)
	if burn == "burning":
		var h := UI.hbox(6)
		v.add_child(h)
		h.add_child(Picto.make("fire", UI.col("red_hi"), 2, UI.col("gold_hi")))
		h.add_child(UI.label("불타는 중", "LabelRed"))
		v.add_child(_wrap("소방대 범위 안이면 곧 꺼진다. 밖이면 옆 칸·위 칸으로 번진다.", "LabelSmall"))
	elif burn == "burnt":
		var h2 := UI.hbox(6)
		v.add_child(h2)
		h2.add_child(Picto.make("burnt", UI.col("paper3")))
		h2.add_child(UI.label("타 버렸다 — 수리해야 쓴다", "LabelRed"))
		var rp := UI.to_dict(info.get("repair", {}))
		var rb := PcButton.make("수리 %s" % str(rp.get("cost_text", "")), "repair", "", "ButtonGold")
		rb.disabled = rp.is_empty() or not bool(rp.get("ok", true))
		rb.pressed.connect(func() -> void:
			var r: Dictionary = ui.cmd("repair", {"bid": int(info.get("bid", -1))})
			if not bool(r.get("ok", false)):
				ui.toast(str(r.get("reason", "수리할 수 없다.")), "bad"))
		TipLayer.set_tip(rb, "수리\n%s. 시간이 걸린다(%s)." % [str(rp.get("cost_text", "")), UI.days(rp.get("days", 0.5))])
		v.add_child(rb)
	if sick:
		var h3 := UI.hbox(6)
		v.add_child(h3)
		h3.add_child(Picto.make("sick", UI.col("jade_hi"), 2, UI.col("red_hi")))
		h3.add_child(UI.label("병이 돈다", "LabelRed"))
		v.add_child(_wrap("일손이 반, 행복이 떨어진다. 의원 범위 안이면 빨리 낫는다. 쓰레기 수거 범위를 넓힌다.", "LabelSmall"))


# ------------------------------------------------------------------ 시설
func _facility() -> void:
	var kind := str(info.get("kind", ""))
	var burn := str(info.get("burn", ""))
	if burn != "":
		_hazard_box(burn, false)
	var bl := str(info.get("build_left_text", ""))
	if kind == "site" or bl != "":
		var pv := UI.hbox(8)
		_v.add_child(pv)
		pv.add_child(Picto.make("clock", UI.col("gold")))
		pv.add_child(UI.label("공사 중 " + bl, "LabelGold"))
		if info.has("build_progress"):
			var bp := float(info.get("build_progress", 0.0))
			var bh := UI.hbox(8)
			_v.add_child(bh)
			bh.add_child(PcWindow.bar(bp, "warn", int(W - 120.0), 12))
			bh.add_child(UI.label(UI.pct(bp), "LabelSmall"))
	var desc := str(info.get("desc", ""))
	if desc != "":
		_v.add_child(_wrap(desc, "LabelDim"))
	var g := GridContainer.new()
	g.columns = 2
	_v.add_child(g)
	if kind == "facility":
		var active := bool(info.get("active", false))
		var paused := bool(info.get("paused", false))
		var cause := str(info.get("cause_text", ""))
		_kv(g, "상태", "멈춤(직접)" if paused else ("가동" if active else ("멈춤 — " + cause if cause != "" else "멈춤")), "good" if active and not paused else "bad")
		var staff := UI.to_dict(info.get("staff", {}))
		if not staff.is_empty():
			_kv(g, "일손", UI.pct(staff.get("ratio", 0.0)), "good" if float(staff.get("ratio", 0)) >= 0.999 else "warn")
		if info.has("eff"):
			_kv(g, "효율", UI.pct(info.get("eff", 0.0)))
		if float(info.get("upkeep", 0)) > 0:
			_kv(g, "유지비", "%s/일" % UI.won(info.get("upkeep", 0)))
		var rg: Variant = info.get("range")
		if rg is Dictionary and not (rg as Dictionary).is_empty():
			_kv(g, "범위", "사방 %d칸 · 위 %d · 아래 %d층" % [int(rg.get("r", 0)), int(rg.get("up", 0)), int(rg.get("down", 0))])
		if info.has("served_houses"):
			_kv(g, "닿는 집", "%d채" % int(info.get("served_houses", 0)))
		for ln: Variant in UI.to_array(staff.get("lines", [])):
			_v.add_child(_wrap("· " + str(ln), "LabelSmall"))
		var io := UI.to_array(info.get("io_lines", []))
		if not io.is_empty():
			PcWindow.section(_v, "들고 나는 것")
			for ln2: Variant in io:
				_v.add_child(_wrap(str(ln2), "LabelSmall"))
	_actions_row(true)


func _actions_row(fac: bool) -> void:
	if _is_hover:
		return
	var row := HFlowContainer.new()
	_v.add_child(row)
	var kind := str(info.get("kind", ""))
	if fac and kind == "facility":
		var rg: Variant = info.get("range")
		if rg is Dictionary and not (rg as Dictionary).is_empty():
			var rb := PcButton.make("범위", "range", "", "ButtonToggle")
			rb.toggle_mode = true
			rb.set_pressed_no_signal(show_range)
			rb.pressed.connect(func() -> void:
				show_range = not show_range
				_sig = ""
				_refresh())
			TipLayer.set_tip(rb, "범위 보기\n이 시설이 닿는 칸(층마다 사각).")
			row.add_child(rb)
		var paused := bool(info.get("paused", false))
		var pb := PcButton.make("다시 돌리기" if paused else "멈춤", "play" if paused else "pause", "", "Button")
		pb.pressed.connect(func() -> void:
			ui.cmd("pause", {"bid": int(info.get("bid", -1)), "on": not paused})
			_sig = ""
			_refresh())
		TipLayer.set_tip(pb, "시설 멈춤\n멈추면 일손이 풀리고 유지비가 준다. 만들던 것도 멈춘다.")
		row.add_child(pb)
	if kind in ["house", "facility", "site"]:
		var db := PcButton.make("철거", "demolish", "Del", "ButtonRed")
		db.pressed.connect(func() -> void: ui.place.confirm_demolish(info.get("pos", selected_pos)))
		TipLayer.set_tip(db, "철거 [Delete]\n확인 창에 무엇이 사라지는지 나온다.")
		row.add_child(db)


func _range_cells() -> void:
	if _is_hover or not show_range:
		Q.vcall("show_cells", [[], "range"])
		return
	var pos: Variant = info.get("pos", selected_pos)
	var rp := Q.dict("range_preview", {"type": str(info.get("type", "")), "pos": pos, "rot": int(info.get("rot", 0))})
	Q.vcall("show_cells", [UI.to_array(rp.get("cells", [])), "range"])
