class_name Banner
extends Control
## Banner — 화면 가로를 가로지르는 현수막(해금·호칭 변화·첫 전기). 잠깐 떴다 사라진다. 터치를 먹지 않는다.
##
##   banner.show_banner("새로 열림", "발전기", "시끄럽고 매캐하다. 그래도 밤이 밝아진다.", "gold")

var y_ratio: float = 0.2
var _queue: Array = []
var _busy: bool = false
var _band: Control = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_banner(kicker: String, title: String, sub: String = "", tone: String = "red", hold: float = 3.0, glyph: String = "") -> void:
	_queue.append({"kicker": kicker, "title": title, "sub": sub, "tone": tone, "hold": hold, "glyph": glyph})
	if not _busy:
		_next()


func is_busy() -> bool:
	return _busy


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var b: Dictionary = _queue.pop_front()
	var tone: String = b["tone"]
	var line_col := UI.col("gold")
	var bg := UI.col("red_dd")
	match tone:
		"gold":
			bg = UI.col("gold_dd")
		"jade":
			bg = UI.col("jade_dd")
			line_col = UI.col("jade_hi")
		"ink":
			bg = UI.col("ink0")

	var band := PanelContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line_col
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.expand_margin_top = 2
	sb.expand_margin_bottom = 2
	sb.shadow_color = UI.col("out")
	sb.shadow_size = 0
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	band.add_theme_stylebox_override("panel", sb)
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	band.add_child(row)
	if str(b["glyph"]) != "":
		row.add_child(SignTile.make(str(b["glyph"]), false, false))
	var col := UI.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	if str(b["kicker"]) != "":
		var k := UI.label(str(b["kicker"]), "LabelGoldSmall")
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(k)
	var t := UI.label(str(b["title"]), "LabelHead", true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	if str(b["sub"]) != "":
		var s := UI.label(str(b["sub"]), "LabelSmall", true)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(s)
	add_child(band)
	_band = band
	band.custom_minimum_size.x = size.x
	band.position = Vector2(0, floorf(size.y * y_ratio / 2.0) * 2.0)
	band.size = Vector2(size.x, 0)
	band.modulate.a = 0.0
	# 줄바꿈 라벨은 너비가 잡힌 다음에야 제 높이를 안다 → 한 프레임 뒤에 높이를 다시 맞춘다
	await get_tree().process_frame
	if not is_instance_valid(band):
		return
	band.size = Vector2(size.x, 0)
	band.modulate.a = 1.0
	band.pivot_offset = Vector2(size.x * 0.5, band.size.y * 0.5)
	band.scale = Vector2(1, 0.0)
	col.modulate.a = 0.0
	var tw := band.create_tween()
	tw.tween_property(band, "scale:y", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(col, "modulate:a", 1.0, 0.15)
	tw.tween_interval(float(b["hold"]))
	tw.tween_property(band, "modulate:a", 0.0, 0.4)
	tw.tween_callback(band.queue_free)
	tw.tween_callback(_next)
