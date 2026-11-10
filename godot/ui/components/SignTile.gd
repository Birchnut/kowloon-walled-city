class_name SignTile
extends PanelContainer
## SignTile — 세로 간판 딱지. 한자 간판 글자(없으면 이름 첫 글자)를 1~3자 세로로 쌓는다.
## 시설·사업체 아이콘을 따로 그리지 않아도 되는 이유: 간판이 곧 아이콘이다.

var _box: VBoxContainer


static func make(glyphs: String, off: bool = false, big: bool = false) -> SignTile:
	var s := SignTile.new()
	s.setup(glyphs, off, big)
	return s


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func setup(glyphs: String, off: bool = false, big: bool = false) -> void:
	theme_type_variation = "PanelSignOff" if off else "PanelSign"
	if _box == null:
		_box = UI.vbox(-2)
		_box.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(_box)
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var text := glyphs.strip_edges()
	if text == "":
		text = "?"
	var n := mini(text.length(), 3)
	for i in n:
		var l := UI.label(text.substr(i, 1), "LabelSignBig" if big else "LabelSign")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(48, 48) if big else Vector2(28, 26)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if off:
			l.add_theme_color_override("font_color", UI.col("mute"))
			l.add_theme_color_override("font_shadow_color", UI.col("out"))
		_box.add_child(l)


## 표시용 간판 글자 고르기: 질의가 준 sign/icon → (없으면) 이름 첫 글자.
static func glyph_for(entry: Dictionary) -> String:
	for k in ["sign", "glyph"]:
		var s := str(entry.get(k, "")).strip_edges()
		if s != "":
			return s
	var name := str(entry.get("name", entry.get("title", ""))).strip_edges()
	return name.substr(0, 1) if name != "" else "?"
