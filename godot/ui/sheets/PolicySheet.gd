class_name PolicySheet
extends Control
## PolicySheet — 허가. query("policies") 의 축마다 칩 한 줄 + 고른 선택지의 결과 한 줄.
## 바꾸면 바로 cmd("policy",{axis,value}) + "변경됨" 토스트. 확인 창 없음.
## "선택지 설명"을 펼치면 고르기 전에 모든 선택지의 결과를 읽을 수 있다.

signal finished

var ui: Node = null
var sheet: BottomSheet
var _scroll: DragScroll
var _list: VBoxContainer
var _empty: Label
var _open_axes: Dictionary = {}     # 설명을 펼쳐 둔 축
var bottom_gap: float = 78.0:
	set(v):
		bottom_gap = v
		if sheet != null:
			sheet.bottom_gap = v


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet = BottomSheet.new()
	sheet.title = "허가"
	sheet.height_ratio = 0.56
	sheet.min_height = 360.0
	add_child(sheet)
	var hint := UI.label("눈감은 만큼 돈이 된다.", "LabelDim")
	hint.clip_text = true
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.header.add_child(hint)
	sheet.header.add_child(UI.spacer(false, Vector2(60, 0)))
	_scroll = DragScroll.new()
	sheet.body.add_child(_scroll)
	_list = UI.vbox(14)
	_scroll.set_content(_list)
	_empty = UI.label("정할 수 있는 게 아직 없다.\n사람이 모이면 정할 것도 생긴다.", "LabelDim")
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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


func refresh() -> void:
	var keep := _scroll.offset
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var axes := Q.list("policies")
	var n := 0
	for ax in axes:
		if ax is Dictionary:
			_list.add_child(_axis(ax))
			n += 1
	_empty.visible = n == 0
	_scroll.visible = n > 0
	_scroll.adopt_buttons()
	_scroll.scroll_to.call_deferred(keep)


func _axis(ax: Dictionary) -> Control:
	var axis := str(ax.get("axis", ""))
	var value := str(ax.get("value", ""))
	var options := UI.to_array(ax.get("options", []))
	var v := UI.vbox(4)
	var head := UI.hbox(8)
	v.add_child(head)
	head.add_child(UI.icon_rect("diamond", UI.col("red")))
	head.add_child(UI.label(str(ax.get("name", axis)), "LabelGold"))
	head.add_child(UI.spacer(true))
	var more := PixelButton.make("선택지 설명", "down", "ButtonGhost")
	more.min_size = Vector2(0, 40)
	more.toggle_mode = true
	more.button_pressed = _open_axes.has(axis)
	head.add_child(more)

	var seg := Segmented.new()
	var opts: Array = []
	for o in options:
		if o is Dictionary:
			opts.append({"id": str(o.get("id", "")), "name": str(o.get("name", o.get("id", ""))), "locked": bool(o.get("locked", false))})
	seg.set_options(opts, value)
	v.add_child(seg)

	var desc := UI.label(_desc_of(options, value), "LabelSmall", true)
	desc.custom_minimum_size = Vector2(0, 22)
	v.add_child(desc)

	# 펼침: 모든 선택지의 결과
	var all := UI.panel("PanelInset")
	all.mouse_filter = Control.MOUSE_FILTER_IGNORE
	all.visible = _open_axes.has(axis)
	var av := UI.vbox(4)
	all.add_child(av)
	for o in options:
		if not (o is Dictionary):
			continue
		var row := UI.hbox(8)
		av.add_child(row)
		var nm := UI.label(str(o.get("name", "")), "LabelGoldSmall")
		nm.custom_minimum_size = Vector2(84, 0)
		nm.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(nm)
		var txt := str(o.get("desc", ""))
		if bool(o.get("locked", false)):
			var lh := str(o.get("lock_hint", ""))
			txt += ("  (잠김: %s)" % lh) if lh != "" else "  (잠김)"
		row.add_child(UI.label(txt, "LabelDim", true))
	v.add_child(all)
	more.toggled.connect(func(on: bool) -> void:
		all.visible = on
		if on:
			_open_axes[axis] = true
		else:
			_open_axes.erase(axis))

	seg.selected.connect(func(id: String) -> void:
		if ui == null:
			return
		var r: Dictionary = ui.cmd("policy", {"axis": axis, "value": id})
		if bool(r.get("ok", false)):
			desc.text = UI.keep(_desc_of(options, id))
			desc.modulate = Color(2, 2, 2)
			desc.create_tween().tween_property(desc, "modulate", Color.WHITE, 0.5)
			ui.toast("변경됨 — %s: %s" % [str(ax.get("name", axis)), _name_of(options, id)], "gold")
		else:
			seg.set_value(seg.previous)
			ui.toast(str(r.get("reason", "")) if str(r.get("reason", "")) != "" else "지금은 못 바꾼다.", "bad"))
	seg.locked_pressed.connect(func(id: String) -> void:
		if ui == null:
			return
		var why := ""
		for o in options:
			if o is Dictionary and str(o.get("id", "")) == id:
				why = str(o.get("lock_hint", ""))
		if why == "":
			why = Q.can("policy", {"axis": axis, "value": id})["reason"]
		ui.toast(why if why != "" else "아직 못 고른다.", "warn", "lock"))
	return v


func _desc_of(options: Array, id: String) -> String:
	for o in options:
		if o is Dictionary and str(o.get("id", "")) == id:
			return "→ " + str(o.get("desc", ""))
	return ""


func _name_of(options: Array, id: String) -> String:
	for o in options:
		if o is Dictionary and str(o.get("id", "")) == id:
			return str(o.get("name", id))
	return id
