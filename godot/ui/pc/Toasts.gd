class_name Toasts
extends Control
## 알림 두 가지 — 클릭을 먹지 않는 짧은 줄(토스트)과 소식 카드.
##  토스트: 위 띠 아래 가운데에 최대 4줄, 4초. push(text, tone, picto)
##  카드: 그 아래 한 장씩. card({kicker, title, body, tone, picto, life(0 = 누를 때까지), buttons:[{label, cb}]})
##        카드는 누르면 넘어간다. 셋 넘게 밀리면 넷째부터 한 장("소식 n가지")으로 합친다.

const MAX := 4
const LIFE := 4.0

var top: float = 60.0
var _items: Array = []         # [{node, born, life}]
var _cards: Array = []         # 기다리는 카드 opts
var _card: Control = null
var _card_t: float = 0.0
var _card_life: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func push(text: String, tone: String = "", pic: String = "", life: float = LIFE) -> void:
	text = UI.no_hanja(text).strip_edges()
	if text == "":
		return
	for it: Dictionary in _items:
		if str(it.get("text", "")) == text:
			it["born"] = Time.get_ticks_msec() / 1000.0
			return
	var p := UI.panel("PanelToast")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(8)
	p.add_child(h)
	var bar := ColorRect.new()
	bar.color = UI.tone_col(tone)
	bar.custom_minimum_size = Vector2(4, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	if pic != "":
		h.add_child(Picto.make(pic, UI.tone_col(tone)))
	var l := UI.label(text, "LabelSmall")
	l.add_theme_color_override("font_color", UI.tone_col(tone) if tone != "" else UI.col("paper"))
	h.add_child(l)
	add_child(p)
	_items.append({"node": p, "born": Time.get_ticks_msec() / 1000.0, "life": life, "text": text})
	while _items.size() > MAX:
		var old: Dictionary = _items.pop_front()
		(old["node"] as Node).queue_free()
	_relayout()


func card(opt: Dictionary) -> void:
	_cards.append(opt)
	if _cards.size() > 3:
		var rest := _cards.slice(2)
		_cards = _cards.slice(0, 2)
		var titles: Array = []
		for o: Dictionary in rest:
			titles.append(str(o.get("title", "")))
		_cards.append({"kicker": "소식 %d가지" % rest.size(), "title": " · ".join(titles), "tone": "gold", "picto": "alert"})
	if _card == null:
		_next_card()


func clear() -> void:
	for it: Dictionary in _items:
		(it["node"] as Node).queue_free()
	_items.clear()
	_cards.clear()
	if _card != null:
		_card.queue_free()
		_card = null


func _next_card() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	if _cards.is_empty():
		_relayout()
		return
	var o: Dictionary = _cards.pop_front()
	var tone := str(o.get("tone", "gold"))
	var p := UI.panel({"jade": "PanelJade", "red": "PanelRed", "gold": "PanelGoldFill"}.get(tone, "PanelGold"))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.custom_minimum_size = Vector2(520, 0)
	var h := UI.hbox(12)
	p.add_child(h)
	if str(o.get("picto", "")) != "":
		h.add_child(Picto.make(str(o["picto"]), UI.tone_col(tone), 3))
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	if str(o.get("kicker", "")) != "":
		v.add_child(UI.label(str(o["kicker"]), "LabelGoldSmall"))
	var t := UI.label(str(o.get("title", "")), "LabelBold", true)
	t.custom_minimum_size.x = 440
	v.add_child(t)
	if str(o.get("body", "")) != "":
		var b := UI.label(str(o["body"]), "LabelSmall", true)
		b.custom_minimum_size.x = 440
		v.add_child(b)
	var btns := UI.to_array(o.get("buttons", []))
	if not btns.is_empty():
		var row := UI.hbox(6)
		v.add_child(row)
		for bd: Variant in btns:
			var bb := PcButton.make(str(UI.to_dict(bd).get("label", "")), "", "", "Button")
			bb.min_h = 34
			var cb: Callable = UI.to_dict(bd).get("cb", Callable())
			bb.pressed.connect(func() -> void:
				if cb.is_valid():
					cb.call()
				_next_card())
			row.add_child(bb)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_next_card())
	TipLayer.set_tip(p, "누르면 넘긴다")
	add_child(p)
	_card = p
	_card_t = 0.0
	_card_life = float(o.get("life", 3.5))
	_relayout()


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	for it: Dictionary in _items.duplicate():
		var age := now - float(it["born"])
		var n: Control = it["node"]
		if age > float(it["life"]):
			n.queue_free()
			_items.erase(it)
			changed = true
		elif age > float(it["life"]) - 0.5:
			n.modulate.a = (float(it["life"]) - age) / 0.5
	if _card != null:
		_card_t += delta
		if _card_life > 0.0 and _card_t >= _card_life:
			_next_card()
	if changed:
		_relayout()


func _relayout() -> void:
	var w := get_viewport_rect().size.x
	var y := top
	if _card != null:
		_card.reset_size()
		_card.position = Vector2(floorf((w - _card.size.x) * 0.5), y)
		y += _card.size.y + 8
	for it: Dictionary in _items:
		var n: Control = it["node"]
		n.reset_size()
		n.position = Vector2(floorf((w - n.size.x) * 0.5), y)
		y += n.size.y + 4


func card_rect() -> Rect2:
	return _card.get_global_rect() if _card != null else Rect2()
