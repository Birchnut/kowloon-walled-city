class_name BuildBar
extends PanelContainer
## 아래 가운데 짓기 막대.
##  윗줄: 도구 [주거 칠하기 H] [철거 X] [따라 짓기 G] | 분류 탭(그림·이름·단축키 Z C V B N M , . /)
##  아랫줄(분류를 고르면): 시설 카드(그림·이름·비용). 올리면 설명 전부(모양 그림·범위·일손·유지비·공사 시간·잠긴 이유).
## 읽는 것: build_menu(데이터 순서 그대로). 보내는 것: tool_pressed(id) / item_pressed(item).

signal tool_pressed(id: String)
signal item_pressed(item: Dictionary)

## 분류 열한 개(v4: 방재 safety 추가) — 아래 줄 아홉 + K·L(기반·명소). WASD·Q·E 는 뷰, R·H·X·G·U 는 UI 가 쓴다.
const CAT_KEYS := ["Z", "C", "V", "B", "N", "M", ",", ".", "/", "K", "L"]
const CAT_KEYCODES := [KEY_Z, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_K, KEY_L]

var ui: Node = null
var _tools: Dictionary = {}
var _cat_row: HBoxContainer
var _cat_btns: Dictionary = {}
var _items_scroll: ScrollContainer
var _items: HBoxContainer
var _menu: Array = []
var _menu_sig: String = ""
var cat: String = ""
var active_tool: String = ""       # house / demolish / pick / <시설 id>
var _cards: Dictionary = {}        # id -> Button
var _top: HFlowContainer


## 한 줄에 다 놓을 때의 폭(UIRoot 가 max_w 와 비교해 막대 폭을 정한다).
func desired_width() -> float:
	var w := 0.0
	if _top == null:
		return 300.0
	for c: Node in _top.get_children():
		if c is Control and (c as Control).visible:
			w += (c as Control).get_combined_minimum_size().x + 4.0
	var sb := get_theme_stylebox("panel")
	return w + (sb.get_minimum_size().x if sb != null else 0.0)


var max_w: float = 1100.0:
	set(v):
		if absf(v - max_w) > 1.0:
			max_w = v
			_apply_compact()
var _compact := false


func _init() -> void:
	theme_type_variation = "PanelBar"
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var v := UI.vbox(6)
	add_child(v)
	# 좁은 창에서는 분류 탭 묶음이 둘째 줄로 내려간다(HFlow)
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 4)
	top.add_theme_constant_override("v_separation", 4)
	_top = top
	v.add_child(top)
	for t: Array in [["house", "주거 칠하기", "house", "H"], ["demolish", "철거", "demolish", "X"], ["pick", "따라 짓기", "pick", "G"]]:
		var b := PcButton.make(t[1], t[2], t[3], "ButtonToggle")
		b.toggle_mode = true
		b.min_h = 40
		var id: String = t[0]
		b.pressed.connect(func() -> void: tool_pressed.emit(id))
		TipLayer.set_tip(b, _tool_tip(id))
		top.add_child(b)
		_tools[id] = b
	top.add_child(VSeparator.new())
	_cat_row = UI.hbox(2)
	top.add_child(_cat_row)
	_items_scroll = ScrollContainer.new()
	_items_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_items_scroll.custom_minimum_size = Vector2(0, 112)
	_items_scroll.visible = false
	v.add_child(_items_scroll)
	_items = UI.hbox(6)
	_items.mouse_filter = Control.MOUSE_FILTER_PASS
	_items_scroll.add_child(_items)


func _tool_tip(id: String) -> Variant:
	match id:
		"house":
			return func() -> String:
				var it := find("house")
				return "주거 칠하기 [H]\n땅을 눌러 끌면 네모 안이 판잣집이 된다(한 칸 = 한 채, %s). Shift를 누른 채 끌면 지나간 칸만.\n칠하는 칸은 바닥만 밝게 보인다. 놓을 수 없는 칸은 빨강.\n오른쪽 클릭·Esc = 그만." % UI.won(UI.to_dict(it.get("cost", {})).get("money", 0))
		"demolish":
			return "철거 [X / Delete]\n건물을 눌러 허문다(확인 창이 나온다). 위에 뭔가 있으면 골조가 남는다.\n오른쪽 클릭·Esc = 그만."
		"pick":
			return "따라 짓기 [G]\n도시의 시설 위에서 G를 누르면(또는 이 도구로 누르면) 같은 시설을 바로 놓는다."
	return ""


func refresh() -> void:
	var m := Q.list("build_menu")
	var sig := JSON.stringify(m).md5_text()
	if sig == _menu_sig:
		return
	_menu_sig = sig
	_menu = m
	_rebuild_cats()
	if cat != "":
		_rebuild_items()


func _rebuild_cats() -> void:
	PcWindow.clear(_cat_row)
	_cat_btns.clear()
	var i := 0
	for c: Variant in _menu:
		var cd := UI.to_dict(c)
		var cid := str(cd.get("cat", ""))
		if cid == "house":
			continue
		var items := UI.to_array(cd.get("items", []))
		var open_n := 0
		for it: Variant in items:
			if not bool(UI.to_dict(it).get("locked", false)):
				open_n += 1
		var key: String = CAT_KEYS[i] if i < CAT_KEYS.size() else ""
		var b := PcButton.make(str(cd.get("cat_name", cid)), UI.cat_picto(cid), key, "ButtonToggle")
		b.toggle_mode = true
		b.min_h = 40
		b.sfx_name = "tab"
		b.set_pressed_no_signal(cid == cat)
		b.modulate = Color(1, 1, 1, 1.0 if open_n > 0 else 0.5)
		var cc := cid
		b.pressed.connect(func() -> void: select_cat("" if cat == cc else cc))
		var nm := str(cd.get("cat_name", cid))
		TipLayer.set_tip(b, "%s%s\n지을 수 있는 것 %d / %d" % [nm, (" [%s]" % key) if key != "" else "", open_n, items.size()])
		_cat_row.add_child(b)
		_cat_btns[cid] = b
		i += 1
	_apply_compact.call_deferred()


## 폭이 모자라면 분류 탭에서 이름을 빼고 그림·단축키만(이름은 툴팁). 따라 짓기·철거도 그림만.
func _apply_compact() -> void:
	if _cat_row == null:
		return
	var full := 0.0
	for b: Variant in _cat_btns.values():
		full += 46.0 + 14.0 * str((b as PcButton).label_text).length() + 22.0
	full += 470.0 + 24.0
	var want := full > max_w - 30.0
	if want == _compact and not _cat_btns.is_empty():
		pass
	_compact = want
	for k: String in _cat_btns:
		var pb: PcButton = _cat_btns[k]
		if not pb.has_meta("full"):
			pb.set_meta("full", pb.label_text)
		pb.label_text = "" if want else str(pb.get_meta("full"))
	for t: String in ["demolish", "pick"]:
		var tb: PcButton = _tools[t]
		if not tb.has_meta("full"):
			tb.set_meta("full", tb.label_text)
		tb.label_text = "" if want else str(tb.get_meta("full"))


## 단축키 순서(Z C V …)의 n번째 분류.
func cat_at(n: int) -> String:
	var i := 0
	for c: Variant in _menu:
		var cid := str(UI.to_dict(c).get("cat", ""))
		if cid == "house":
			continue
		if i == n:
			return cid
		i += 1
	return ""


func select_cat(c: String) -> void:
	cat = c
	for k: String in _cat_btns:
		(_cat_btns[k] as Button).set_pressed_no_signal(k == c)
	_items_scroll.visible = c != ""
	_rebuild_items()


func _rebuild_items() -> void:
	PcWindow.clear(_items)
	_cards.clear()
	if cat == "":
		return
	for c: Variant in _menu:
		var cd := UI.to_dict(c)
		if str(cd.get("cat", "")) != cat:
			continue
		for it: Variant in UI.to_array(cd.get("items", [])):
			_items.add_child(_card(UI.to_dict(it), cat))
	set_active(active_tool)


func _card(it: Dictionary, cid: String) -> Control:
	var b := Button.new()
	b.theme_type_variation = "ButtonCard"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(150, 104)
	var v := UI.vbox(2)
	v.position = Vector2(8, 6)
	v.custom_minimum_size = Vector2(134, 0)
	b.add_child(v)
	var top := UI.hbox(4)
	v.add_child(top)
	var locked := bool(it.get("locked", false))
	top.add_child(Picto.make(UI.cat_picto(cid), UI.col("mute") if locked else UI.col("paper")))
	top.add_child(UI.spacer(true))
	var fp := UI.to_array(it.get("footprint", [1, 1]))
	var shape := "%d×%d" % [int(fp[0]) if fp.size() > 0 else 1, int(fp[1]) if fp.size() > 1 else 1]
	if int(it.get("floors", 1)) > 1:
		shape += "·%d층" % int(it.get("floors", 1))
	top.add_child(UI.label(shape, "LabelMute"))
	if locked:
		top.add_child(Picto.make("lock", UI.col("mute")))
	var nm_l := UI.label(str(it.get("name", "")), "LabelSmall", true)
	nm_l.custom_minimum_size = Vector2(134, 0)
	nm_l.max_lines_visible = 2
	if locked:
		nm_l.add_theme_color_override("font_color", UI.col("mute"))
	v.add_child(nm_l)
	var cost := UI.label(cost_text(it, true), "LabelGoldSmall")
	if not bool(it.get("affordable", true)) and not locked:
		cost.add_theme_color_override("font_color", UI.col("red_hi"))
	elif locked:
		cost.add_theme_color_override("font_color", UI.col("mute"))
	v.add_child(cost)
	b.mouse_entered.connect(func() -> void: Sfx.play("hover"))
	b.pressed.connect(func() -> void:
		b.set_pressed_no_signal(false)
		Sfx.play("click")
		item_pressed.emit(it))
	var itc := it
	TipLayer.set_tip(b, func() -> Control: return item_tip(itc, ui))
	_cards[str(it.get("id", ""))] = b
	return b


## 비용 한 줄: "₩40 · 고물 10"
func cost_text(it: Dictionary, short: bool = false) -> String:
	var c := UI.to_dict(it.get("cost", {}))
	var parts: Array = [UI.won(c.get("money", 0))]
	var names: Dictionary = ui.good_names() if ui != null else {}
	var g := UI.to_dict(c.get("goods", {}))
	for k: String in g:
		parts.append("%s %s" % [str(names.get(k, k)), UI.num(g[k])])
	if short and parts.size() > 2:
		return "%s · %s +%d" % [parts[0], parts[1], parts.size() - 2]
	return " · ".join(parts)


## 시설 설명 툴팁(짓기 카드·배치 중 공용).
static func item_tip(it: Dictionary, uiroot: Node) -> Control:
	var v := UI.vbox(4)
	v.custom_minimum_size.x = 420
	var h := UI.hbox(8)
	v.add_child(h)
	h.add_child(UI.label(str(it.get("name", "")), "LabelGold"))
	if bool(it.get("locked", false)):
		h.add_child(UI.tag("잠김", "red"))
	var desc := str(it.get("desc", ""))
	if desc != "":
		var d := UI.label(desc, "LabelSmall", true)
		d.custom_minimum_size.x = 420
		v.add_child(d)
	var eff := str(it.get("effect_text", ""))
	if eff != "":
		var e := UI.label(eff, "LabelJadeSmall", true)
		e.custom_minimum_size.x = 420
		v.add_child(e)
	var row := UI.hbox(14)
	v.add_child(row)
	var fp := UI.to_array(it.get("footprint", [1, 1]))
	var fd := FootprintDraw.new()
	fd.w = int(fp[0]) if fp.size() > 0 else 1
	fd.h = int(fp[1]) if fp.size() > 1 else 1
	fd.floors = int(it.get("floors", 1))
	var rg := UI.to_dict(it.get("range", {}))
	fd.r = int(rg.get("r", 0))
	row.add_child(fd)
	var g := GridContainer.new()
	g.columns = 2
	row.add_child(g)
	var add := func(k: String, val: String, tone: String = "") -> void:
		g.add_child(UI.label(k, "LabelDim"))
		var l := UI.label(val, "LabelSmall")
		if tone != "":
			l.add_theme_color_override("font_color", UI.tone_col(tone))
		g.add_child(l)
	var bb: BuildBar = uiroot.build if uiroot != null and uiroot.get("build") != null else null
	add.call("비용", bb.cost_text(it) if bb != null else UI.won(UI.to_dict(it.get("cost", {})).get("money", 0)), "" if bool(it.get("affordable", true)) else "bad")
	add.call("모양", "%d×%d%s%s" % [fd.w, fd.h, (" · %d개 층" % fd.floors) if fd.floors > 1 else "", " · R로 돌림" if bool(it.get("rotatable", false)) else ""])
	if not rg.is_empty():
		add.call("범위", "사방 %d칸 · 위 %d층 · 아래 %d층" % [int(rg.get("r", 0)), int(rg.get("up", 0)), int(rg.get("down", 0))])
	var wf: Array = []
	for w: Variant in UI.to_array(it.get("workforce", [])):
		wf.append("%s %s" % [str(UI.to_dict(w).get("name", "")), UI.num(UI.to_dict(w).get("n", 0))])
	if not wf.is_empty():
		add.call("일손", " · ".join(wf))
	if float(it.get("upkeep", 0)) > 0.0:
		add.call("유지비", "%s/일" % UI.won(it.get("upkeep", 0)))
	var bd := float(it.get("build_days", 0.0))
	if bd > 0.0:
		add.call("공사", "%s (×1에서 약 %d분)" % [UI.days(bd), maxi(1, int(round(bd * 10.0)))])
	if bool(it.get("needs_sky", false)):
		add.call("자리", "위가 뚫린 칸만", "warn")
	if int(it.get("min_floor", 0)) > 0:
		add.call("층", "%d층 이상" % (int(it.get("min_floor", 0)) + 1), "warn")
	if bool(it.get("locked", false)) and str(it.get("lock_hint", "")) != "":
		var lk := UI.label("열리는 조건: " + str(it.get("lock_hint", "")), "LabelRedSmall", true)
		lk.custom_minimum_size.x = 420
		v.add_child(lk)
	elif not bool(it.get("locked", false)):
		v.add_child(UI.label("누르면 배치 — 왼쪽 클릭 짓기 · R 돌리기 · 오른쪽 클릭 그만", "LabelMute"))
	return v


func find(id: String) -> Dictionary:
	if _menu.is_empty():
		_menu = Q.list("build_menu")
	for c: Variant in _menu:
		for it: Variant in UI.to_array(UI.to_dict(c).get("items", [])):
			if str(UI.to_dict(it).get("id", "")) == id:
				return it
	return {}


func cat_of(id: String) -> String:
	if _menu.is_empty():
		_menu = Q.list("build_menu")
	for c: Variant in _menu:
		for it: Variant in UI.to_array(UI.to_dict(c).get("items", [])):
			if str(UI.to_dict(it).get("id", "")) == id:
				return str(UI.to_dict(c).get("cat", ""))
	return ""


## 지금 켜진 도구·시설을 눌린 모양으로.
func set_active(id: String) -> void:
	active_tool = id
	for k: String in _tools:
		(_tools[k] as Button).set_pressed_no_signal(k == id)
	for k2: String in _cards:
		(_cards[k2] as Button).set_pressed_no_signal(k2 == id)


func card_rect(id: String) -> Rect2:
	if _cards.has(id):
		return (_cards[id] as Control).get_global_rect()
	return Rect2()


func cat_rect(c: String) -> Rect2:
	return (_cat_btns[c] as Control).get_global_rect() if _cat_btns.has(c) else Rect2()


func tool_rect(id: String) -> Rect2:
	return (_tools[id] as Control).get_global_rect() if _tools.has(id) else Rect2()
