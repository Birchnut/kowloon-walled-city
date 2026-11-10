class_name Banner
extends Control
## Banner — 축하·소식 카드(목표 달성·해금·등급·새 층·연구·단속). 상단 띠 바로 아래 왼쪽, 레일 앞까지.
## 한 번에 하나만, 줄을 서서 짧게(기본 2초) 떴다 사라진다. 카드를 누르면 바로 넘긴다.
## 카드 밖은 터치를 막지 않는다(도시·버튼을 그대로 누를 수 있다). 줄이 셋을 넘으면 나머지는 요약 한 장으로 합친다.
##
##   banner.show_banner("새로 열림", "발전기", "시끄럽고 매캐하다.", "gold", 2.0, "電")

const MAX_QUEUE := 3           # 기다리는 카드가 이보다 많으면 뒤는 요약 하나로
const HOLD := 2.0

var top_offset: float = 132.0      # 상단 띠 아래(UIRoot 가 맞춘다)
var right_reserve: float = 76.0    # 우측 레일 자리
var _queue: Array = []
var _busy: bool = false
var _band: Control = null
var _tw: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_banner(kicker: String, title: String, sub: String = "", tone: String = "red", hold: float = HOLD, glyph: String = "") -> void:
	var b := {"kicker": kicker, "title": title, "sub": sub, "tone": tone, "hold": minf(hold, 3.0), "glyph": glyph}
	if _queue.size() >= MAX_QUEUE:
		var last: Dictionary = _queue[_queue.size() - 1]
		if bool(last.get("summary", false)):
			last["names"].append(_short(b))
			_fill_summary(last)
		else:
			var s := {"summary": true, "names": [_short(last), _short(b)], "tone": "ink", "hold": HOLD, "glyph": "", "kicker": ""}
			_fill_summary(s)
			_queue[_queue.size() - 1] = s
	else:
		_queue.append(b)
	if not _busy:
		_next()


func is_busy() -> bool:
	return _busy


## 지금 카드가 차지한 아래 끝(토스트가 그 밑으로 비킨다). 없으면 0.
func occupied_bottom() -> float:
	if _band != null and is_instance_valid(_band) and _band.visible:
		return _band.position.y + _band.size.y
	return 0.0


func clear() -> void:
	_queue.clear()
	_dismiss()


static func _short(b: Dictionary) -> String:
	var k := str(b.get("kicker", "")).split(" · ")[0]
	var t := str(b.get("title", "")).replace("\n", " ")
	var out := (k + " " + t) if k != "" else t
	return out if out.length() <= 18 else out.substr(0, 17) + "…"


static func _fill_summary(s: Dictionary) -> void:
	var names: Array = s["names"]
	s["title"] = "소식 %d가지" % names.size()
	s["sub"] = " · ".join(names)


func _dismiss() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null
	if _band != null and is_instance_valid(_band):
		_band.queue_free()
	_band = null
	_next.call_deferred()


func _on_band_input(e: InputEvent) -> void:
	var tapped: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if tapped:
		accept_event()
		_dismiss()


func _next() -> void:
	if _band != null and is_instance_valid(_band):
		return
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
	band.mouse_filter = Control.MOUSE_FILTER_STOP     # 카드만 누름을 받는다(누르면 넘김) — 밖은 통과
	band.gui_input.connect(_on_band_input)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line_col
	sb.set_border_width_all(2)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 7
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	band.add_theme_stylebox_override("panel", sb)
	var row := UI.hbox(10)
	band.add_child(row)
	if str(b["glyph"]) != "":
		var tile := SignTile.make(str(b["glyph"]), false, false)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tile)
	var col := UI.vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	if str(b["kicker"]) != "":
		col.add_child(UI.label(str(b["kicker"]), "LabelGoldSmall"))
	col.add_child(UI.label(str(b["title"]), "LabelHead", true))
	if str(b["sub"]) != "":
		col.add_child(UI.label(str(b["sub"]), "LabelSmall", true))
	for c: Node in band.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	_band = band
	var w := maxf(200.0, size.x - right_reserve - 16.0)
	band.custom_minimum_size.x = w
	band.position = Vector2(8, top_offset)
	band.size = Vector2(w, 0)
	band.modulate.a = 0.0
	# 줄바꿈 라벨은 너비가 잡힌 다음에야 제 높이를 안다 → 한 프레임 뒤에 높이를 다시 맞춘다
	await get_tree().process_frame
	if not is_instance_valid(band) or band != _band:
		return
	band.size = Vector2(w, 0)
	band.position = Vector2(-16, top_offset)
	_tw = band.create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(band, "modulate:a", 1.0, 0.12)
	_tw.tween_property(band, "position:x", 8.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.chain().tween_interval(float(b["hold"]))
	_tw.chain().tween_property(band, "modulate:a", 0.0, 0.25)
	_tw.chain().tween_callback(_dismiss)
