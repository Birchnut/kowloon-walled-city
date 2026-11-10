class_name ToastLayer
extends Control
## ToastLayer — 짧은 알림 줄. 상단 띠 아래 왼쪽에 쌓였다가 사라진다. 터치를 먹지 않는다.
##
##   toasts.push("자릿세 +12", "good", "coin")

const MAX_TOASTS := 4
const LIFE := 3.0

var top_offset: float = 118.0:
	set(v):
		top_offset = v
		_relayout(false)
var right_reserve: float = 76.0     # 우측 레일 자리
var _items: Array = []              # [{node, born}]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func push(text: String, tone: String = "", icon_id: String = "", life: float = LIFE) -> void:
	if text.strip_edges() == "":
		return
	var p := UI.panel("PanelDeep")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(8)
	p.add_child(h)
	var bar := ColorRect.new()
	bar.color = UI.tone_col(tone)
	bar.custom_minimum_size = Vector2(4, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	if icon_id != "" and UI.has_icon(icon_id):
		h.add_child(UI.icon_rect(icon_id))
	var l := UI.label(text, "LabelSmall", true)
	l.add_theme_color_override("font_color", UI.tone_col(tone) if tone != "" else UI.col("paper"))
	h.add_child(l)
	add_child(p)
	var max_w: float = maxf(200.0, size.x - 16.0 - right_reserve)
	var want: float = UI.font("small").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size("small")).x + 60.0 \
			+ (30.0 if icon_id != "" else 0.0)
	p.custom_minimum_size.x = minf(max_w, want)
	p.size = Vector2(p.custom_minimum_size.x, 0)
	p.modulate.a = 0.0
	_items.append({"node": p})
	while _items.size() > MAX_TOASTS:
		_drop(_items[0])
	_relayout.call_deferred(true, p)
	var tw := p.create_tween()
	tw.tween_interval(life)
	tw.tween_property(p, "modulate:a", 0.0, 0.35)
	tw.tween_callback(_expire.bind(p))


func clear() -> void:
	for it in _items.duplicate():
		_drop(it)


func _expire(p: Control) -> void:
	for it in _items:
		if it["node"] == p:
			_drop(it)
			_relayout(true)
			return


func _drop(it: Dictionary) -> void:
	_items.erase(it)
	var n: Control = it["node"]
	if is_instance_valid(n):
		n.queue_free()


func _relayout(animate: bool, fresh: Control = null) -> void:
	var y := top_offset
	for it in _items:
		var n: Control = it["node"]
		if not is_instance_valid(n):
			continue
		n.reset_size()
		var target := Vector2(8, y)
		if n == fresh:
			n.position = target + Vector2(-24, 0)
			var tw := n.create_tween().set_parallel(true)
			tw.tween_property(n, "position", target, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(n, "modulate:a", 1.0, 0.12)
		elif animate:
			n.create_tween().tween_property(n, "position", target, 0.15)
		else:
			n.position = target
		y += n.size.y + 4.0
