class_name BuildSheet
extends Screen
## BuildSheet — 짓기. query("build_menu") 의 분류 탭 + 항목 카드(간판·이름·비용·인력·유지비·효과·잠김 이유).
## 작업 층 = 레일에서 고른 층(전체면 지상). 열린 층만 고를 수 있다(레일이 열린 층만 보여 준다).
##  주거: 격자 켜고 칠하기 모드(cell_dragged) → 고른 칸(show_cells select) + can("zone") 로 "n칸 · ₩ · 골조 m" → 짓기/취소
##  시설: 격자 켜고 칠하기 모드로 자리를 끈다 → show_ghost(칸, ok, 골조) + range_preview 범위 + "주거 n채 닿음"
##        → 확정/취소 알약(막히면 can 의 이유). 지은 뒤에도 같은 시설 배치 모드에 남는다(연달아 짓기).
##  철거: 도구 칩 → 건물을 누르면 잃는 것을 보여 주고 확인.
## 시트를 떠나면 오버레이·격자·칠하기 모드를 전부 거둔다. 두 손가락은 언제나 팬·줌, "이동" 토글이면 한 손가락도 팬.

var mode: String = "menu"            # menu | paint | place | demolish
var item: Dictionary = {}            # 배치 중인 항목(build_menu 의 item)
var cells: Array = []                # 주거 칠하기로 고른 칸
var place_pos: Variant = null        # 시설 후보 자리(origin)
var _menu: Array = []
var _cat: String = ""
var _focus_id: String = ""
var _tabs: Segmented
var _tabs_scroll: DragScroll
var _cards_scroll: DragScroll
var _cards: HBoxContainer
var _card_nodes: Dictionary = {}
var _demolish_chip: PixelButton
var _bar: PlaceBar
var _grid_z: int = -1
var _erase_stroke: bool = false
var _move: bool = false
var _menu_sig: String = ""
var _spots: Array = []               # 이 층에서 can("build") 이 ok 인 자리(origin) — 배치 도움


func _init() -> void:
	super._init()
	make_sheet("짓기", 0.37, 300.0)
	var top := UI.hbox(4)
	sheet.body.add_child(top)
	_tabs_scroll = DragScroll.new()
	_tabs_scroll.horizontal = true
	_tabs_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs = Segmented.new()
	_tabs.equal_width = false
	_tabs.small_text = true
	_tabs.chip_min = Vector2(64, 50)
	_tabs.selected.connect(func(id: String) -> void:
		_cat = id
		_build_cards())
	_tabs_scroll.set_content(_tabs)
	_tabs_scroll.custom_minimum_size = Vector2(0, 52)
	top.add_child(_tabs_scroll)
	_demolish_chip = PixelButton.make("철거", "wreck", "ButtonChipRed")
	_demolish_chip.small = true
	_demolish_chip.min_size = Vector2(64, 50)
	_demolish_chip.pressed.connect(func() -> void: _enter("demolish"))
	top.add_child(_demolish_chip)
	_cards_scroll = DragScroll.new()
	_cards_scroll.horizontal = true
	_cards = UI.hbox(8)
	_cards_scroll.set_content(_cards)
	sheet.body.add_child(_cards_scroll)
	_bar = PlaceBar.new()
	_bar.visible = false
	add_child(_bar)
	_bar.confirm.connect(_on_confirm)
	_bar.cancel.connect(_on_cancel)
	_bar.menu.connect(func() -> void: _enter("menu"))
	_bar.wreck.connect(func() -> void: _enter("demolish"))
	_bar.move_toggled.connect(func(on: bool) -> void:
		_move = on
		Q.vcall("set_drag_paint", [mode in ["paint", "place"] and not _move]))
	poll_sec = 1.5


func set_frame(bottom_gap: float, top_limit: float) -> void:
	super.set_frame(bottom_gap, top_limit)
	_bar.bottom_gap = bottom_gap


func inset() -> float:
	if mode == "menu":
		return super.inset()
	return _bar.size.y


# ------------------------------------------------------------------ 열기/닫기
func _on_open(a: String, _was: bool) -> void:
	_focus_id = ""
	_menu_sig = ""
	refresh()
	if a == "house":
		var it := _find("house")
		if not it.is_empty() and not bool(it.get("locked", false)):
			_start(it)
			return
	if a != "":
		var hit := _find(a)
		if not hit.is_empty():
			_focus_id = a
			_cat = str(hit.get("_cat", _cat))
		elif _has_cat(a):
			_cat = a
	_enter("menu")


func _on_closed() -> void:
	_leave_mode()
	_bar.visible = false
	mode = "menu"


## 다시 메뉴로/다른 모드로. 오버레이는 매번 깨끗이.
func _enter(m: String) -> void:
	_leave_mode()
	mode = m
	match m:
		"menu":
			_bar.visible = false
			sheet.open()
			_build_tabs()
			_build_cards()
		"paint", "place":
			sheet.snap_open(false)
			_grid_on()
			if m == "place":
				_scan_spots()
			Q.vcall("set_drag_paint", [not _move])
			_bar.visible = true
			_update_bar()
		"demolish":
			sheet.snap_open(false)
			_bar.visible = true
			_update_bar()
	if ui != null:
		ui._sync_inset()


func _leave_mode() -> void:
	Q.vcall("set_drag_paint", [false])
	Q.vcall("clear_overlay")
	if _grid_z >= 0:
		Q.vcall("show_floor_grid", [_grid_z, false])
		_grid_z = -1
		if ui != null:
			Q.vcall("set_floor_cut", [ui.rail.cut])
	cells.clear()
	place_pos = null


func _grid_on() -> void:
	var z: int = ui.work_z() if ui != null else 0
	_grid_z = z
	Q.vcall("show_floor_grid", [z, true])


## 레일에서 층을 바꿨다.
func on_floor_changed() -> void:
	if mode in ["paint", "place"]:
		cells.clear()
		place_pos = null
		Q.vcall("clear_overlay")
		_grid_on()
		if mode == "place":
			_scan_spots()
		_update_bar()


## 이 층에서 놓을 수 있는 자리를 can() 에 하나씩 물어 "valid" 칸으로 보여 준다(판정은 시뮬, UI는 묻기만).
func _scan_spots() -> void:
	_spots.clear()
	var id := str(item.get("id", ""))
	var gw := int(Data.cfg("grid.width", 12))
	var gh := int(Data.cfg("grid.height", 12))
	for x in gw:
		for y in gh:
			var p := Vector3i(x, y, _grid_z)
			var c := Q.can_full("build", {"type": id, "pos": p})
			# 자리 자체는 되는데 돈·자재만 모자란 곳도 "놓을 수 있는 자리"로 보인다(이유 코드가 없어 문장으로 가른다 — UI_NOTES 빈틈)
			if bool(c.get("ok", false)) or str(c.get("reason", "")).contains("모자란다"):
				_spots.append(p)
	Q.vcall("show_cells", [_spots, "valid"])


# ------------------------------------------------------------------ 메뉴
func refresh() -> void:
	_menu = Q.list("build_menu")
	if mode == "menu" and sheet.is_open:
		var sig := JSON.stringify(_menu)
		if sig != _menu_sig:
			_menu_sig = sig
			_build_tabs()
			_build_cards()
	elif mode in ["paint", "place"]:
		_update_bar()


func _has_cat(c: String) -> bool:
	for cat: Variant in _menu:
		if cat is Dictionary and str(cat.get("cat", "")) == c:
			return true
	return false


func _find(id: String) -> Dictionary:
	for cat: Variant in _menu:
		for it: Variant in UI.to_array(UI.to_dict(cat).get("items", [])):
			if it is Dictionary and str(it.get("id", "")) == id:
				var d: Dictionary = it.duplicate()
				d["_cat"] = str(cat.get("cat", ""))
				return d
	return {}


func _build_tabs() -> void:
	var opts: Array = []
	for cat: Variant in _menu:
		if not (cat is Dictionary):
			continue
		var items := UI.to_array(cat.get("items", []))
		var open_n := 0
		for it: Variant in items:
			if it is Dictionary and not bool(it.get("locked", false)):
				open_n += 1
		if ui != null and ui.tutorial.running and not ui.tutorial.build_allowed_cat(items):
			continue
		opts.append({"id": str(cat.get("cat", "")), "name": str(cat.get("cat_name", "")), "variation": "ButtonChip" if open_n > 0 else "ButtonChip"})
	if _cat == "" or not opts.any(func(o: Dictionary) -> bool: return o["id"] == _cat):
		_cat = opts[0]["id"] if not opts.is_empty() else ""
	_tabs.set_options(opts, _cat)
	for o: Dictionary in opts:
		var b := _tabs.button(o["id"])
		if b != null:
			b.min_size = Vector2(64, 50)
	_tabs_scroll.adopt_buttons()


func _build_cards() -> void:
	Screen.clear(_cards)
	_card_nodes.clear()
	var names: Dictionary = ui.good_names() if ui != null else {}
	for cat: Variant in _menu:
		if not (cat is Dictionary) or str(cat.get("cat", "")) != _cat:
			continue
		for it: Variant in UI.to_array(cat.get("items", [])):
			if not (it is Dictionary):
				continue
			if ui != null and ui.tutorial.running and not ui.tutorial.build_allowed(str(it.get("id", ""))):
				continue
			var c := ItemCard.make(it, names)
			c.pressed.connect(_on_card.bind(it))
			_cards.add_child(c)
			_card_nodes[str(it.get("id", ""))] = c
			if str(it.get("id", "")) == _focus_id:
				c.focus_glow = true
	_cards_scroll.adopt_buttons()
	_cards_scroll.scroll_to(0.0)
	if _focus_id != "" and _card_nodes.has(_focus_id):
		_scroll_to_card.call_deferred(_focus_id)


func _scroll_to_card(id: String) -> void:
	if _card_nodes.has(id):
		var c: Control = _card_nodes[id]
		_cards_scroll.scroll_to(c.position.x - 12.0)


func _on_card(it: Dictionary) -> void:
	if bool(it.get("locked", false)):
		var h := str(it.get("lock_hint", ""))
		ui.toast(("아직 못 짓는다 — " + h) if h != "" else "아직 못 짓는다.", "dim")
		return
	_start(it)


func _start(it: Dictionary) -> void:
	item = it
	_enter("paint" if str(it.get("id", "")) == "house" else "place")


# ------------------------------------------------------------------ 도시 입력
func on_drag(info: Dictionary) -> void:
	if not bool(info.get("in_grid", info.get("ok", false))):
		return
	var p: Variant = info.get("pos")
	if not (p is Vector3i):
		return
	if mode == "paint":
		if bool(info.get("first", false)):
			_erase_stroke = p in cells
		if _erase_stroke:
			cells.erase(p)
		elif not (p in cells):
			cells.append(p)
		_update_bar()
	elif mode == "place":
		place_pos = p
		_update_bar()


func on_tap(info: Dictionary) -> bool:
	match mode:
		"demolish":
			var p: Variant = info.get("pos")
			if bool(info.get("hit", false)) and p is Vector3i:
				var inf := Q.dict("info", {"pos": p})
				if str(inf.get("kind", "")) in ["house", "facility", "site"]:
					InspectSheet.confirm_demolish(ui, p, inf)
				else:
					ui.toast("허물 건물이 없다.", "dim")
			return true
		"paint", "place":
			return true          # 이동 모드에서 누른 것: 아무 일도 없게
		"menu":
			return false
	return false


func on_event(n: String, _p: Dictionary) -> void:
	if n in ["unlock", "floor_unlocked"]:
		_menu_sig = ""
		_poll_t = 0.0


# ------------------------------------------------------------------ 알약/막대
func _update_bar() -> void:
	var names: Dictionary = ui.good_names() if ui != null else {}
	match mode:
		"paint":
			var good: Array = []
			if cells.is_empty():
				Q.vcall("show_ghost", [[], true, []])
				Q.vcall("show_cells", [[], "warn"])
				_bar.show_state("주거 구역 · %dF" % (_grid_z + 1), "칸을 누르거나 끌어서 칠한다. 칠한 칸을 다시 누르면 지운다.", "", false, "짓기")
				return
			var c := Q.can_full("zone", {"cells": cells})
			var bad: Array = []
			for s: Variant in UI.to_array(c.get("skipped", [])):
				if s is Dictionary and s.get("pos") is Vector3i:
					bad.append(s["pos"])
			for p: Vector3i in cells:
				if not (p in bad):
					good.append(p)
			Q.vcall("show_ghost", [good, true, UI.to_array(c.get("support_cells", []))])
			Q.vcall("show_cells", [bad, "warn"])
			var cost := UI.to_dict(c.get("cost", {}))
			var n := int(c.get("built", good.size()))
			var sup := int(c.get("supports", 0))
			var line := "%d칸 · ₩%s%s" % [n, UI.num(float(cost.get("money", 0))), (" · 골조 %d" % sup) if sup > 0 else ""]
			var why := ""
			if not bad.is_empty():
				var first: Dictionary = UI.to_array(c.get("skipped", []))[0]
				why = "%d칸 못 지음: %s" % [bad.size(), str(first.get("reason", ""))]
			if not bool(c.get("ok", false)):
				why = str(c.get("reason", why))
			_bar.show_state("주거 구역 · %dF" % (_grid_z + 1), line, why, bool(c.get("ok", false)), "짓기")
		"place":
			var nm := str(item.get("name", ""))
			var head := "%s · %dF" % [nm, _grid_z + 1]
			var costs := _cost_text(UI.to_dict(item.get("cost", {})), names)
			if not (place_pos is Vector3i):
				Q.vcall("show_ghost", [[], true, []])
				Q.vcall("show_cells", [[], "range"])
				if _spots.is_empty():
					var sz := int(item.get("size", 1))
					_bar.show_state(head, costs, "자리 없음 — 이 층에 %s 빈자리가 없다. 다른 층을 고르거나 [철거]로 비운다." % ("2×2" if sz > 1 else "한 칸"), false, "확정")
				else:
					_bar.show_state(head, "밝은 칸(%d곳)에 놓을 수 있다. 누르거나 끈다. %s" % [_spots.size(), costs], "", false, "확정")
				return
			var p: Vector3i = place_pos
			var size_n := maxi(1, int(item.get("size", 1)))
			var fp: Array = []
			for dx in size_n:
				for dy in size_n:
					fp.append(p + Vector3i(dx, dy, 0))
			var c2 := Q.can_full("build", {"type": str(item.get("id", "")), "pos": p})
			Q.vcall("show_ghost", [fp, bool(c2.get("ok", false)), UI.to_array(c2.get("support_cells", []))])
			var reach := ""
			if int(item.get("range", 0)) > 0:
				var rp := Q.dict("range_preview", {"type": str(item.get("id", "")), "pos": p})
				Q.vcall("show_cells", [UI.to_array(rp.get("cells", [])), "range"])
				reach = "주거 %d채 닿음" % int(rp.get("houses", 0))
			var cost2 := UI.to_dict(c2.get("cost", item.get("cost", {})))
			var sup2 := int(c2.get("supports", 0))
			var parts: Array = [_cost_text(cost2, names)]
			if sup2 > 0:
				parts.append("골조 %d" % sup2)
			if reach != "":
				parts.append(reach)
			_bar.show_state(head, " · ".join(parts), "" if bool(c2.get("ok", false)) else str(c2.get("reason", "")), bool(c2.get("ok", false)), "확정")
		"demolish":
			_bar.show_state("철거", "허물 건물을 누른다. 잃는 것을 보여 주고 묻는다.", "", false, "", true)


static func _cost_text(cost: Dictionary, names: Dictionary) -> String:
	var s := "₩" + UI.num(float(cost.get("money", 0)))
	var g := Screen.goods_text(UI.to_dict(cost.get("goods", {})), names)
	return s + ((" · " + g) if g != "" else "")


func _on_confirm() -> void:
	match mode:
		"paint":
			if cells.is_empty():
				return
			var r: Dictionary = ui.cmd("zone", {"cells": cells.duplicate()})
			if not bool(r.get("ok", false)):
				ui.toast(str(r.get("reason", "지을 수 없다.")), "warn")
				return
			var built := int(r.get("built", 0))
			var sk := UI.to_array(r.get("skipped", []))
			ui.toast("판잣집 %d채가 섰다.%s" % [built, (" %d칸은 못 지었다." % sk.size()) if not sk.is_empty() else ""], "good", "house")
			cells.clear()
			_update_bar()
		"place":
			if not (place_pos is Vector3i):
				return
			var r2: Dictionary = ui.cmd("build", {"type": str(item.get("id", "")), "pos": place_pos})
			if not bool(r2.get("ok", false)):
				ui.toast(str(r2.get("reason", "지을 수 없다.")), "warn")
				return
			ui.toast("%s 공사를 시작했다." % str(item.get("name", "")), "good")
			place_pos = null
			Q.vcall("clear_overlay")
			_scan_spots()
			_menu = Q.list("build_menu")
			var again := _find(str(item.get("id", "")))
			if not again.is_empty():
				item = again
			_update_bar()


func _on_cancel() -> void:
	if mode == "paint" and not cells.is_empty():
		cells.clear()
		_update_bar()
		return
	if mode == "place" and place_pos is Vector3i:
		place_pos = null
		Q.vcall("clear_overlay")
		_update_bar()
		return
	close()


func close() -> void:
	if not _open:
		return
	_open = false
	if sheet.is_open:
		sheet.close()
	_on_closed()
	finished.emit()


func target_rect(t: String) -> Rect2:
	if t == "bar":
		return _bar.get_global_rect() if _bar.visible else Rect2()
	if t == "confirm":
		return _bar.confirm_rect()
	if _card_nodes.has(t) and sheet.is_open:
		return (_card_nodes[t] as Control).get_global_rect()
	if t.begins_with("cat:"):
		var b := _tabs.button(t.substr(4))
		return b.get_global_rect() if b != null and sheet.is_open else Rect2()
	return Rect2()


# ------------------------------------------------------------------ 부품
## 항목 카드(세로): 간판 · 이름 · 비용 · 인력 · 유지비 · 효과. 잠기면 흐리게 + 이유.
class ItemCard extends Button:
	var focus_glow := false
	var _t := 0.0

	static func make(it: Dictionary, names: Dictionary) -> ItemCard:
		var c := ItemCard.new()
		c.theme_type_variation = "ButtonFlat"
		c.focus_mode = Control.FOCUS_NONE
		c.custom_minimum_size = Vector2(196, 0)
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var locked := bool(it.get("locked", false))
		var m := UI.margin(10, 10, 10, 8)
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.add_child(m)
		var v := UI.vbox(3)
		m.add_child(v)
		var h := UI.hbox(8)
		v.add_child(h)
		var glyph := str(it.get("sign", ""))
		if str(it.get("id", "")) == "house":
			glyph = "住"
		h.add_child(SignTile.make(glyph if glyph != "" else str(it.get("name", "?")).substr(0, 1), locked))
		var nc := UI.vbox(0)
		nc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nc)
		var nm := UI.label(str(it.get("name", "")), "LabelBold", true)
		nc.add_child(nm)
		var cost := UI.to_dict(it.get("cost", {}))
		var cl := UI.label(BuildSheet._cost_text(cost, names), "LabelGoldSmall", true)
		if not bool(it.get("affordable", true)):
			cl.add_theme_color_override("font_color", UI.col("red_hi"))
		nc.add_child(cl)
		if int(it.get("size", 1)) > 1:
			nc.add_child(UI.label("%d×%d칸" % [int(it["size"]), int(it["size"])], "LabelDim"))
		var wf: Array = []
		for w: Variant in UI.to_array(it.get("workforce", [])):
			if w is Dictionary:
				wf.append("%s %d" % [str(w.get("name", "")), int(w.get("n", 0))])
		v.add_child(UI.label(("인력 " + ", ".join(wf)) if not wf.is_empty() else "인력 없음", "LabelSmall", true))
		if float(it.get("upkeep", 0)) > 0.0:
			v.add_child(UI.label("유지비 ₩%s/일" % str(snappedf(float(it["upkeep"]), 0.1)), "LabelDim"))
		var eff := UI.label(str(it.get("effect_text", "")), "LabelSmall", true)
		eff.add_theme_color_override("font_color", UI.col("jade_hi") if not locked else UI.col("mute"))
		v.add_child(eff)
		if locked:
			var lh := str(it.get("lock_hint", ""))
			var ll := UI.label("잠김 — " + (lh if lh != "" else "아직"), "LabelSmall", true)
			ll.add_theme_color_override("font_color", UI.col("gold"))
			v.add_child(ll)
			c.modulate = Color(1, 1, 1, 0.62)
		c.set_meta("locked", locked)
		return c

	func _process(d: float) -> void:
		if focus_glow:
			_t += d
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var pressed_now := get_draw_mode() in [DRAW_PRESSED, DRAW_HOVER_PRESSED]
		draw_rect(r, UI.col("out"))
		draw_rect(r.grow(-2), UI.col("ink3") if pressed_now else UI.col("ink2"))
		draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 2)), UI.col("line"))
		if focus_glow and fmod(_t, 0.8) < 0.5:
			draw_rect(r, UI.col("gold"), false, 2.0)


## 배치 중 아래 막대: 제목 · 상황 한 줄 · 막힌 이유 · [목록] [이동] [취소] [확정].
class PlaceBar extends PanelContainer:
	signal confirm
	signal cancel
	signal menu
	signal move_toggled(on: bool)
	signal wreck
	var bottom_gap := 80.0:
		set(v):
			bottom_gap = v
			_place()
	var _title: Label
	var _line: Label
	var _why: Label
	var _ok: PixelButton
	var _move: PixelButton
	var _wreck_btn: PixelButton

	func _init() -> void:
		theme_type_variation = "PanelSheet"
		mouse_filter = Control.MOUSE_FILTER_STOP
		var m := UI.margin(10, 6, 10, 6)
		add_child(m)
		var v := UI.vbox(4)
		m.add_child(v)
		var hr := UI.hbox(6)
		v.add_child(hr)
		_title = UI.label("", "LabelGold")
		_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_title.clip_text = true
		hr.add_child(_title)
		var mb := PixelButton.make("목록", "chev_l", "")
		mb.small = true
		mb.pressed.connect(func() -> void: menu.emit())
		hr.add_child(mb)
		var wb := PixelButton.make("철거", "wreck", "ButtonChipRed")
		wb.small = true
		wb.pressed.connect(func() -> void: wreck.emit())
		hr.add_child(wb)
		_wreck_btn = wb
		_move = PixelButton.make("이동", "move", "ButtonChip")
		_move.small = true
		_move.toggle_mode = true
		_move.pressed.connect(func() -> void: move_toggled.emit(_move.button_pressed))
		hr.add_child(_move)
		_line = UI.label("", "LabelSmall", true)
		v.add_child(_line)
		_why = UI.label("", "LabelSmall", true)
		_why.add_theme_color_override("font_color", UI.col("red_hi"))
		v.add_child(_why)
		var br := UI.hbox(8)
		v.add_child(br)
		var cx := PixelButton.make("취소", "close", "")
		cx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cx.pressed.connect(func() -> void: cancel.emit())
		br.add_child(cx)
		_ok = PixelButton.make("확정", "check", "ButtonJade")
		_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ok.pressed.connect(func() -> void: confirm.emit())
		br.add_child(_ok)

	func _ready() -> void:
		get_viewport().size_changed.connect(_place)
		resized.connect(_place)
		visibility_changed.connect(_place)
		_place()

	var _placing := false

	func _place() -> void:
		if not is_inside_tree() or _placing:
			return
		_placing = true
		var vs := get_parent_control().size if get_parent_control() != null else Vector2(540, 960)
		var h := get_combined_minimum_size().y
		var want := Rect2(0, vs.y - bottom_gap - h, vs.x, h)
		if Rect2(position, size) != want:
			size = want.size
			position = want.position
		_placing = false

	func show_state(title: String, line: String, why: String, ok: bool, ok_text: String, no_ok: bool = false) -> void:
		_title.text = title
		_line.text = UI.keep(line)
		_why.text = UI.keep(why)
		_why.visible = why != ""
		_ok.visible = not no_ok
		_wreck_btn.visible = not no_ok
		_ok.label_text = ok_text
		_ok.disabled = not ok
		_ok.theme_type_variation = "ButtonJade" if ok else ""
		_place.call_deferred()

	func confirm_rect() -> Rect2:
		return _ok.get_global_rect() if visible else Rect2()
