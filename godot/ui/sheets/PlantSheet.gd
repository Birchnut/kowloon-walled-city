class_name PlantSheet
extends Control
## PlantSheet — 심기. ① 시설 카드 고르기(시트) → ② 얇은 바 + 자리 표시 → ③ 자리 탭 → 고스트 + 놓기/취소.
##
## 데이터: query("facilities") / query("plant_spots",{facility}) / can("plant") / cmd("plant").
## 비용·잠김·가능 여부는 전부 질의 결과다. 여기서 계산하지 않는다.

signal finished          # 심었거나 닫았다 → UIRoot 가 도구를 끈다

const CARD_W := 216.0

var ui: Node = null                 # UIRoot
var only: Array = []                # (튜토리얼) 이 id 들만 보여 준다. 비면 전부
var sheet: BottomSheet
var _scroll: DragScroll
var _row: HBoxContainer
var _empty: Label
var _slim: PanelContainer
var _slim_sign: SignTile
var _slim_text: Label
var _slim_name: Label
var _pill: PanelContainer
var _pill_reason: Label
var _pill_ok: PixelButton
var _facility: Dictionary = {}
var _spots: Array = []
var _target: Variant = null
var bottom_gap: float = 78.0:
	set(v):
		bottom_gap = v
		if sheet != null:
			sheet.bottom_gap = v
		_place()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet = BottomSheet.new()
	sheet.title = "심기"
	sheet.height_px = 284.0
	sheet.min_height = 284.0
	add_child(sheet)
	var hint := UI.label("이유를 놓는다. 방은 사람들이 쌓는다.", "LabelDim")
	hint.clip_text = true
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.header.add_child(hint)
	sheet.header.add_child(UI.spacer(false, Vector2(60, 0)))
	_scroll = DragScroll.new()
	_scroll.horizontal = true
	sheet.body.add_child(_scroll)
	_row = UI.hbox(8)
	_scroll.set_content(_row)
	_empty = UI.label("심을 수 있는 게 아직 없다.", "LabelDim")
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.visible = false
	sheet.body.add_child(_empty)
	sheet.closed.connect(_on_sheet_closed)

	# ② 얇은 바
	_slim = UI.panel("PanelGold")
	_slim.visible = false
	add_child(_slim)
	var sr := UI.hbox(10)
	_slim.add_child(sr)
	_slim_sign = SignTile.make("?")
	_slim_sign.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sr.add_child(_slim_sign)
	var sv := UI.vbox(0)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sr.add_child(sv)
	_slim_name = UI.label("", "LabelGold")
	_slim_name.clip_text = true
	sv.add_child(_slim_name)
	_slim_text = UI.label("", "LabelDim")
	_slim_text.clip_text = true
	sv.add_child(_slim_text)
	var change := PixelButton.make("바꾸기", "", "")
	change.pressed.connect(_back_to_list)
	sr.add_child(change)
	var x := PixelButton.make("", "close", "ButtonRed")
	x.pressed.connect(func() -> void: finished.emit())
	sr.add_child(x)

	# ③ 놓기/취소
	_pill = UI.panel("PanelGold")
	_pill.visible = false
	add_child(_pill)
	var pv := UI.vbox(6)
	_pill.add_child(pv)
	_pill_reason = UI.label("", "LabelSmall", true)
	_pill_reason.custom_minimum_size = Vector2(300, 0)
	_pill_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(_pill_reason)
	var pr := UI.hbox(8)
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(pr)
	var cancel := PixelButton.make("취소", "", "")
	cancel.min_size = Vector2(110, UI.TOUCH)
	cancel.pressed.connect(_cancel_target)
	pr.add_child(cancel)
	_pill_ok = PixelButton.make("여기에 놓기", "check", "ButtonJade")
	_pill_ok.min_size = Vector2(190, UI.TOUCH)
	_pill_ok.pressed.connect(_confirm)
	pr.add_child(_pill_ok)


func _ready() -> void:
	resized.connect(_place)
	_pill.minimum_size_changed.connect(_place, CONNECT_DEFERRED)
	_slim.minimum_size_changed.connect(_place, CONNECT_DEFERRED)
	sheet.bottom_gap = bottom_gap


# ------------------------------------------------------------------ 열기/닫기
func open() -> void:
	_facility = {}
	_target = null
	_slim.visible = false
	_pill.visible = false
	refresh()
	sheet.open()


## 도구를 완전히 끈다(뷰 오버레이도 지운다).
func close() -> void:
	_facility = {}
	_target = null
	_slim.visible = false
	_pill.visible = false
	Q.vcall("clear_overlay")
	if sheet.is_open:
		sheet.close()


func is_placing() -> bool:
	return not _facility.is_empty()


func is_open() -> bool:
	return sheet.is_open or is_placing()


func _on_sheet_closed() -> void:
	# 시트만 닫히고 고른 게 없으면 도구 종료
	if _facility.is_empty():
		finished.emit()


func refresh() -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	var list := Q.list("facilities")
	var hud := Q.dict("hud")
	var shown := 0
	for f in list:
		if not (f is Dictionary):
			continue
		if not only.is_empty() and not (str(f.get("id", "")) in only):
			continue
		_row.add_child(_card(f, hud))
		shown += 1
	_empty.visible = shown == 0
	_scroll.visible = shown > 0
	_scroll.adopt_buttons()
	_scroll.scroll_to(0.0)


func card_rect(index: int = 0) -> Rect2:
	if index < _row.get_child_count():
		var c := _row.get_child(index) as Control
		return Rect2(c.global_position, c.size)
	return Rect2()


# ------------------------------------------------------------------ ① 카드
func _card(f: Dictionary, hud: Dictionary) -> Control:
	var locked := bool(f.get("locked", false))
	var p := UI.panel("PanelDeep" if locked else "")
	p.custom_minimum_size = Vector2(CARD_W, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UI.vbox(6)
	p.add_child(v)
	var top := UI.hbox(8)
	v.add_child(top)
	top.add_child(SignTile.make(SignTile.glyph_for(f), locked))
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	var name := UI.label(str(f.get("name", f.get("id", "?"))), "LabelGold" if not locked else "LabelDim", true)
	tv.add_child(name)
	# 값
	var cost := UI.to_dict(f.get("cost", {}))
	var cm := float(cost.get("money", 0))
	var cx := float(cost.get("materials", 0))
	var cr := UI.hbox(8)
	tv.add_child(cr)
	if cm <= 0.0 and cx <= 0.0:
		cr.add_child(UI.label("외상" if not locked else "—", "LabelJade" if not locked else "LabelMute"))
	else:
		if cm > 0.0:
			cr.add_child(_cost("coin", cm, hud.has("money") and float(hud.get("money", 0)) < cm, locked))
		if cx > 0.0:
			cr.add_child(_cost("mat", cx, hud.has("materials") and float(hud.get("materials", 0)) < cx, locked))
	if locked:
		var lr := UI.hbox(6)
		v.add_child(lr)
		var li := UI.icon_rect("lock", UI.col("gold_d"))
		li.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		lr.add_child(li)
		var lh := UI.label(str(f.get("lock_hint", "아직 못 심는다.")), "LabelDim", true)
		lh.add_theme_color_override("font_color", UI.col("gold_d"))
		lr.add_child(lh)
	else:
		v.add_child(UI.label(str(f.get("desc", "")), "LabelSmall", true))
	var hit := Button.new()
	hit.theme_type_variation = "ButtonFlat"
	hit.focus_mode = Control.FOCUS_NONE
	hit.pressed.connect(_on_card.bind(f))
	p.add_child(hit)
	return p


func _cost(icon_id: String, n: float, short: bool, locked: bool) -> Control:
	var h := UI.hbox(2)
	var ic := UI.icon_rect(icon_id)
	if locked:
		ic.modulate = Color(1, 1, 1, 0.4)
	h.add_child(ic)
	var l := UI.label(UI.num(n), "LabelSmall")
	if locked:
		l.add_theme_color_override("font_color", UI.col("mute"))
	elif short:
		l.add_theme_color_override("font_color", UI.col("red_hi"))   # 재고가 값보다 적다(표시만, 판정은 can)
	h.add_child(l)
	return h


func _on_card(f: Dictionary) -> void:
	if bool(f.get("locked", false)):
		if ui != null:
			ui.toast(str(f.get("lock_hint", "아직 못 심는다.")), "warn", "lock")
		return
	_facility = f
	_target = null
	sheet.close()
	_spots = Q.list("plant_spots", {"facility": str(f.get("id", ""))})
	Q.vcall("show_spots", [_spots])
	_slim_sign.setup(SignTile.glyph_for(f).substr(0, 1))
	_slim_name.text = str(f.get("name", ""))
	_slim_text.text = "놓을 자리를 누른다" if not _spots.is_empty() else "지금은 놓을 자리가 없다"
	_slim.visible = true
	_pill.visible = false
	_place()
	if ui != null:
		ui.plant_picked.emit(str(f.get("id", "")))


func _back_to_list() -> void:
	_facility = {}
	_target = null
	_slim.visible = false
	_pill.visible = false
	Q.vcall("clear_overlay")
	refresh()
	sheet.open()


# ------------------------------------------------------------------ ②→③ 자리
## UIRoot 가 view.cell_tapped 를 넘겨준다.
func on_cell(info: Dictionary) -> void:
	if _facility.is_empty():
		return
	var pos: Variant = _resolve(info)
	if pos == null:
		return
	_target = pos
	var fid := str(_facility.get("id", ""))
	var chk := Q.can("plant", {"facility": fid, "pos": pos})
	Q.vcall("show_ghost", [pos, fid, chk["ok"]])
	_pill_ok.visible = chk["ok"]
	if chk["ok"]:
		_pill_reason.text = UI.keep("%s 여기에?" % UI.josa(str(_facility.get("name", "")), "를", "을"))
		_pill_reason.add_theme_color_override("font_color", UI.col("paper"))
	else:
		_pill_reason.text = UI.keep(chk["reason"] if chk["reason"] != "" else "여긴 안 된다.")
		_pill_reason.add_theme_color_override("font_color", UI.col("red_hi"))
	_pill.visible = true
	_place()


## 탭한 곳 → 심을 칸. 같은 기둥에 가능한 자리가 있으면 그 자리(지붕 위든 빈 땅이든).
func _resolve(info: Dictionary) -> Variant:
	var col: Variant = info.get("col")
	if col is Vector2i:
		for s in _spots:
			if s is Vector3i and s.x == col.x and s.y == col.y:
				return s
	if not bool(info.get("hit", false)):
		return null
	for k in ["above", "pos"]:
		if info.get(k) is Vector3i:
			return info[k]
	return null


func _cancel_target() -> void:
	_target = null
	_pill.visible = false
	Q.vcall("clear_overlay")
	Q.vcall("show_spots", [_spots])


func _confirm() -> void:
	if _facility.is_empty() or not (_target is Vector3i) or ui == null:
		return
	var r: Dictionary = ui.cmd("plant", {"facility": str(_facility.get("id", "")), "pos": _target})
	if bool(r.get("ok", false)):
		Q.vcall("clear_overlay")
		finished.emit()
	else:
		ui.toast(str(r.get("reason", "안 된다.")) if str(r.get("reason", "")) != "" else "안 된다.", "bad")
		on_cell({"hit": true, "pos": _target, "above": _target, "col": Vector2i(_target.x, _target.y)})


func _place() -> void:
	if _slim == null or not is_inside_tree():
		return
	var w := size.x
	_slim.custom_minimum_size = Vector2(w - 16, 0)
	_slim.size = Vector2.ZERO
	_slim.position = UI.snap(Vector2(8, size.y - bottom_gap - _slim.size.y - 6))
	_pill.custom_minimum_size = Vector2(minf(w - 40, 340), 0)
	_pill.size = Vector2.ZERO
	_pill.position = UI.snap(Vector2((w - _pill.size.x) * 0.5, _slim.position.y - _pill.size.y - 8))


func slim_rect() -> Rect2:
	return Rect2(_slim.global_position, _slim.size) if _slim.visible else Rect2()
