class_name CardsSheet
extends Control
## CardsSheet — 결재. query("cards") 를 서류 더미로. 맨 위 한 장을 처리하면 도장이 찍히고 다음 장이 밀려 들어온다.
## cmd("card",{uid,choice}). 결과 문장은 명령 결과의 result(있으면) 또는 뒤따르는 log 이벤트가 토스트로 보여 준다.

signal finished

var ui: Node = null
var sheet: BottomSheet
var _scroll: DragScroll
var _holder: VBoxContainer
var _empty: Control
var _count: Label
var _busy: bool = false
var bottom_gap: float = 78.0:
	set(v):
		bottom_gap = v
		if sheet != null:
			sheet.bottom_gap = v


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet = BottomSheet.new()
	sheet.title = "결재"
	sheet.height_ratio = 0.6
	sheet.min_height = 420.0
	add_child(sheet)
	_count = UI.label("", "LabelDim")
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.header.add_child(_count)
	sheet.header.add_child(UI.spacer(false, Vector2(60, 0)))
	_scroll = DragScroll.new()
	sheet.body.add_child(_scroll)
	_holder = UI.vbox(0)
	_scroll.set_content(_holder)
	# 빈 상태
	var ev := UI.vbox(10)
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var seal := UI.panel("PanelSeal")
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sl := UI.label("閑", "LabelSignBig")
	sl.add_theme_color_override("font_color", UI.col("red"))
	sl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	seal.add_child(sl)
	ev.add_child(seal)
	var et := UI.label("올라온 서류가 없다.\n하루가 저물면 누군가 뭘 들고 온다.", "LabelDim")
	et.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ev.add_child(et)
	_empty = ev
	_empty.visible = false
	sheet.body.add_child(_empty)
	sheet.closed.connect(func() -> void: finished.emit())


func _ready() -> void:
	sheet.bottom_gap = bottom_gap


func open() -> void:
	refresh()
	sheet.open()


func close() -> void:
	if sheet.is_open:
		sheet.close()


func is_open() -> bool:
	return sheet.is_open


## 맨 위 카드를 다시 그린다. slide = 오른쪽에서 밀려 들어오는 연출.
func refresh(slide: bool = false) -> void:
	if _busy:
		return
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	var cards := Q.list("cards")
	var n := 0
	var first: Dictionary = {}
	for cd in cards:
		if cd is Dictionary:
			if n == 0:
				first = cd
			n += 1
	_empty.visible = n == 0
	_scroll.visible = n > 0
	_count.text = ("남은 서류 %d장" % n) if n > 0 else ""
	if n == 0:
		return
	var wrap := UI.margin(2, 4, 2, 6)
	_holder.add_child(wrap)
	var card := CardView.make(first, ("%d장 남음" % n) if n > 1 else "마지막 장")
	card.chosen.connect(_on_chosen.bind(card))
	# 더미: 뒤에 깔린 종이가 오른쪽·아래로 8px 삐져나온다
	if n > 1:
		var um := UI.margin(8, 8, 0, 0)
		var under := UI.panel("PanelPaper")
		under.mouse_filter = Control.MOUSE_FILTER_IGNORE
		under.modulate = Color(0.78, 0.76, 0.72)
		um.add_child(under)
		wrap.add_child(um)
	var cm := UI.margin(0, 0, 8 if n > 1 else 0, 8 if n > 1 else 0)
	cm.add_child(card)
	wrap.add_child(cm)
	_scroll.adopt_buttons()
	_scroll.scroll_to(0.0)
	if slide:
		card.modulate.a = 0.0
		card.position.x = 80
		var tw := card.create_tween().set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.18)
		tw.tween_property(card, "position:x", 0.0, 0.22).from(80.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_chosen(index: int, card: CardView) -> void:
	if ui == null or _busy:
		return
	var uid: Variant = card.card.get("uid", 0)
	var seq: int = ui.log_seq
	var r: Dictionary = ui.cmd("card", {"uid": int(uid), "choice": index})
	if not bool(r.get("ok", false)):
		card.unlock()
		ui.toast(str(r.get("reason", "")) if str(r.get("reason", "")) != "" else "지금은 처리할 수 없다.", "bad")
		return
	_busy = true
	card.stamp(str(r.get("stamp", "准")))
	if str(r.get("result", "")) != "" and ui.log_seq == seq:
		ui.toast(str(r["result"]), "gold")     # 시뮬이 log 로 이미 알렸으면 겹치지 않게 생략
	var tw := card.create_tween()
	tw.tween_interval(0.45)
	tw.tween_property(card, "modulate:a", 0.0, 0.16)
	tw.parallel().tween_property(card, "position:x", -120.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_busy = false
		refresh(true))
