class_name Dialog
extends Control
## 확인 창(철거·해지·새 도시…). 뒤를 어둡게 막고, Enter = 확인, Esc = 취소.
##   Dialog.confirm(parent, {title, kicker?, lines[], ok_text?, cancel_text?, danger?}, on_ok)
##   Dialog.notice(parent, {title, lines[], ok_text?})

var _on_ok: Callable
var _two := true
static var open_count: int = 0


static func confirm(parent: Node, opt: Dictionary, on_ok: Callable = Callable()) -> Dialog:
	var d := Dialog.new()
	d._on_ok = on_ok
	parent.add_child(d)
	d._build(opt, true)
	return d


static func notice(parent: Node, opt: Dictionary) -> Dialog:
	var d := Dialog.new()
	parent.add_child(d)
	d._build(opt, false)
	return d


func _init() -> void:
	theme = PcTheme.paper_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _enter_tree() -> void:
	open_count += 1
	Q.vcall("set_input_enabled", [false])


func _exit_tree() -> void:
	open_count -= 1
	if open_count <= 0:
		Q.vcall("set_input_enabled", [true])


func _build(opt: Dictionary, two: bool) -> void:
	_two = two
	var scrim := ColorRect.new()
	scrim.color = Color(0.05, 0.04, 0.03, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var p := UI.panel("PanelGold")
	p.custom_minimum_size = Vector2(560, 0)
	cc.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	if str(opt.get("kicker", "")) != "":
		v.add_child(UI.label(str(opt["kicker"]), "LabelGoldSmall"))
	var t := UI.label(str(opt.get("title", "")), "LabelHead", true)
	t.custom_minimum_size.x = 520
	v.add_child(t)
	for ln: Variant in UI.to_array(opt.get("lines", [])):
		var l := UI.label("· " + str(ln), "LabelSmall", true)
		l.custom_minimum_size.x = 520
		v.add_child(l)
	var row := UI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	if two:
		var c := PcButton.make(str(opt.get("cancel_text", "그만둔다")), "", "Esc", "Button")
		c.pressed.connect(_cancel)
		row.add_child(c)
	var ok := PcButton.make(str(opt.get("ok_text", "확인")), "check", "Enter", "ButtonRed" if bool(opt.get("danger", false)) else "ButtonGold")
	ok.pressed.connect(_ok)
	row.add_child(ok)


func _ok() -> void:
	if _on_ok.is_valid():
		_on_ok.call()
	queue_free()


func _cancel() -> void:
	queue_free()


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if (ev as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _two:
			_cancel()
		else:
			_ok()
	elif (ev as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_ok()
