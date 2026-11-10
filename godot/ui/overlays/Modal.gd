class_name Modal
extends Control
## Modal — 화면 가운데 뜨는 창(확인·자리 비운 사이). 뒤는 어둡게 가리고 터치를 막는다.
##
##   Modal.confirm(parent, {title, kicker?, lines[], ok_text?, cancel_text?, danger?, ok_enabled?}, on_ok)
##   Modal.notice(parent, {title, kicker?, lines[], ok_text?}, on_close)

signal closed(ok: bool)

var _panel: PanelContainer
var _scrim: ColorRect
var _on_ok: Callable
var _on_close: Callable


static func confirm(parent: Node, opt: Dictionary, on_ok: Callable = Callable()) -> Modal:
	var m := Modal.new()
	m._on_ok = on_ok
	parent.add_child(m)
	m._build(opt, true)
	return m


static func notice(parent: Node, opt: Dictionary, on_close: Callable = Callable()) -> Modal:
	var m := Modal.new()
	m._on_close = on_close
	parent.add_child(m)
	m._build(opt, false)
	return m


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build(opt: Dictionary, two_buttons: bool) -> void:
	_scrim = ColorRect.new()
	_scrim.color = Color(UI.col("out"), 0.72)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UI.panel("PanelGold")
	_panel.custom_minimum_size = Vector2(minf(460.0, get_viewport_rect().size.x - 40.0), 0)
	center.add_child(_panel)
	var m := UI.margin(6, 8, 6, 6)
	_panel.add_child(m)
	var v := UI.vbox(10)
	m.add_child(v)
	if str(opt.get("kicker", "")) != "":
		var kr := UI.hbox(0)
		v.add_child(kr)
		kr.add_child(UI.tag(str(opt["kicker"]), "red"))
	v.add_child(UI.label(str(opt.get("title", "")), "LabelHead", true))
	var lines := UI.to_array(opt.get("lines", []))
	if not lines.is_empty():
		var lv := UI.vbox(4)
		v.add_child(lv)
		for l in lines:
			var s := str(l)
			if s == "":
				lv.add_child(UI.spacer(false, Vector2(0, 4)))
				continue
			if bool(opt.get("bullets", false)):
				var row := UI.hbox(8)
				var dot := UI.icon_rect("dot", UI.col("gold_d"))
				dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
				row.add_child(dot)
				row.add_child(UI.label(s, "LabelSmall", true))
				lv.add_child(row)
			else:
				lv.add_child(UI.label(s, "LabelSmall", true))
	v.add_child(UI.spacer(false, Vector2(0, 2)))
	var br := UI.hbox(8)
	br.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(br)
	if two_buttons:
		var cancel := PixelButton.make(str(opt.get("cancel_text", "그만둔다")), "", "")
		cancel.min_size = Vector2(130, UI.TOUCH)
		cancel.pressed.connect(_close.bind(false))
		br.add_child(cancel)
	var ok := PixelButton.make(str(opt.get("ok_text", "알았다")), "",
			"ButtonRed" if bool(opt.get("danger", false)) else ("ButtonJade" if two_buttons else "ButtonRed"))
	ok.min_size = Vector2(150, UI.TOUCH)
	ok.disabled = not bool(opt.get("ok_enabled", true))
	ok.pressed.connect(_close.bind(true))
	br.add_child(ok)
	# 등장
	modulate.a = 0.0
	_panel.pivot_offset = Vector2(_panel.custom_minimum_size.x * 0.5, 80)
	_panel.scale = Vector2(0.92, 0.92)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.12)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close(ok: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit(ok)
	if ok and _on_ok.is_valid():
		_on_ok.call()
	if _on_close.is_valid():
		_on_close.call()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.1)
	tw.tween_callback(queue_free)
