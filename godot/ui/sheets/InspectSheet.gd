class_name InspectSheet
extends Control
## InspectSheet — 들여다보기. 도구가 꺼진 채 칸을 누르면 query("cell_info",{pos}) 를 작은 시트로.
## title / subtitle / lines("왜 여기에 지어졌나" 포함) / actions.
##
## actions 항목 모양(계약에 안 적혀 있어 UI가 가정한 것 — UI_NOTES.md 참고):
##   {label, cmd, args, confirm?:String, danger?:bool, enabled?:bool, reason?:String}

signal finished

var ui: Node = null
var sheet: BottomSheet
var pos: Variant = null
var _sub: Label
var _scroll: DragScroll
var _box: VBoxContainer
var bottom_gap: float = 78.0:
	set(v):
		bottom_gap = v
		if sheet != null:
			sheet.bottom_gap = v


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet = BottomSheet.new()
	sheet.height_px = 248.0
	sheet.min_height = 200.0
	add_child(sheet)
	_sub = UI.label("", "LabelDim")
	_sub.clip_text = true
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.header.add_child(_sub)
	sheet.header.add_child(UI.spacer(false, Vector2(60, 0)))
	_scroll = DragScroll.new()
	sheet.body.add_child(_scroll)
	_box = UI.vbox(6)
	_scroll.set_content(_box)
	sheet.closed.connect(func() -> void: finished.emit())


func _ready() -> void:
	sheet.bottom_gap = bottom_gap


func is_open() -> bool:
	return sheet.is_open


func close() -> void:
	if sheet.is_open:
		sheet.close()


## 칸 정보가 있으면 연다. 없으면(null) false.
func show_cell(p: Vector3i) -> bool:
	var info := Q.dict("cell_info", {"pos": p})
	if info.is_empty():
		return false
	pos = p
	_fill(info)
	sheet.open()
	return true


func refresh() -> void:
	if not sheet.is_open or not (pos is Vector3i):
		return
	var info := Q.dict("cell_info", {"pos": pos})
	if info.is_empty():
		close()
		return
	_fill(info)


func _fill(info: Dictionary) -> void:
	sheet.title = str(info.get("title", "?"))
	_sub.text = str(info.get("subtitle", ""))
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	for l in UI.to_array(info.get("lines", [])):
		var row := UI.hbox(8)
		var dot := UI.icon_rect("dot", UI.col("gold_d"))
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(dot)
		row.add_child(UI.label(str(l), "LabelSmall", true))
		_box.add_child(row)
	var actions := UI.to_array(info.get("actions", []))
	if not actions.is_empty():
		var ar := UI.hbox(8)
		ar.alignment = BoxContainer.ALIGNMENT_END
		_box.add_child(UI.spacer(false, Vector2(0, 2)))
		_box.add_child(ar)
		for a in actions:
			if not (a is Dictionary):
				continue
			var b := PixelButton.make(str(a.get("label", "?")), "", "ButtonRed" if bool(a.get("danger", false)) else "")
			b.min_size = Vector2(120, UI.TOUCH)
			var enabled := bool(a.get("enabled", true))
			if not enabled:
				b.modulate = Color(1, 1, 1, 0.5)
			b.pressed.connect(_on_action.bind(a))
			ar.add_child(b)
	_scroll.adopt_buttons()
	_scroll.scroll_to(0.0)


func _on_action(a: Dictionary) -> void:
	if ui == null:
		return
	var cmd_name := str(a.get("cmd", ""))
	var args := UI.to_dict(a.get("args", {}))
	if cmd_name == "":
		return
	var chk := Q.can(cmd_name, args)
	if not chk["ok"]:
		var why := chk["reason"] as String
		if why == "":
			why = str(a.get("reason", "지금은 안 된다."))
		ui.toast(why, "warn")
		return
	var run := func() -> void:
		var r: Dictionary = ui.cmd(cmd_name, args)
		if bool(r.get("ok", false)):
			refresh()
		else:
			ui.toast(str(r.get("reason", "안 된다.")), "bad")
	if str(a.get("confirm", "")) != "":
		ui.confirm({"title": str(a.get("label", "확인")), "lines": [str(a["confirm"])],
				"ok_text": str(a.get("label", "확인")), "danger": bool(a.get("danger", false))}, run)
	else:
		run.call()
