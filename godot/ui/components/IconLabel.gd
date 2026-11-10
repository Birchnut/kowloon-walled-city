class_name IconLabel
extends HBoxContainer
## IconLabel — 아이콘 + 숫자. 값이 바뀌면 숫자가 굴러가고 변화량(+12 / -5)이 잠깐 떠오른다.

var icon_name: String = "coin"
var label_variation: String = "LabelBold"
var show_delta: bool = true
var min_digits_width: float = 0.0
var delta_min: float = 1.0           # 이보다 작은 변화는 떠오르지 않는다(세수처럼 끊임없이 붙는 돈은 숫자만 굴린다)
var short_big: bool = false         # true = 100만 이상은 만/억으로(UI.big)
var delta_side: bool = false         # true = 변화량을 아이콘 왼쪽 같은 줄에(아래 줄을 가리지 않게)

var _icon: TextureRect
var _label: Label
var _anchor: Control
var _value: float = 0.0
var _shown: float = 0.0
var _has_value: bool = false
var _tween: Tween


static func make(icon_id: String, variation: String = "LabelBold") -> IconLabel:
	var il := IconLabel.new()
	il.icon_name = icon_id
	il.label_variation = variation
	return il


func _init() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_icon = UI.icon_rect(icon_name)
	add_child(_icon)
	_label = UI.label("0", label_variation)
	_label.custom_minimum_size.x = min_digits_width
	add_child(_label)
	_anchor = Control.new()
	_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_anchor)
	_label.text = _fmt(_shown)


func _fmt(v: float) -> String:
	return UI.big(v) if short_big else UI.num(v)


func icon_center() -> Vector2:
	if _icon == null:
		return global_position
	return _icon.global_position + _icon.size * 0.5


func set_value(v: float, animate: bool = true) -> void:
	var first := not _has_value
	_has_value = true
	var d := floorf(v + 0.0001) - floorf(_value + 0.0001)
	_value = v
	if _label == null:
		_shown = v
		return
	if first or not animate or absf(d) < 1.0:
		if absf(d) >= 1.0 or first:
			_shown = v
			_label.text = _fmt(v)
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_roll, _shown, v, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if show_delta and absf(d) >= delta_min:
		_spawn_delta(int(d))
	# 아이콘 통통
	_icon.pivot_offset = _icon.size * 0.5
	var t2 := create_tween()
	t2.tween_property(_icon, "scale", Vector2(1.3, 1.3), 0.08)
	t2.tween_property(_icon, "scale", Vector2.ONE, 0.16)


func _roll(v: float) -> void:
	_shown = v
	_label.text = _fmt(v)


func _spawn_delta(d: int) -> void:
	if d == 0:
		return
	var l := UI.label(("+" if d > 0 else "-") + _fmt(absi(d)), "LabelSmall")
	l.add_theme_color_override("font_color", UI.col("jade_hi") if d > 0 else UI.col("red_hi"))
	l.add_theme_color_override("font_shadow_color", UI.col("out"))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.z_index = 5
	_anchor.add_child(l)
	var tw := l.create_tween()
	if delta_side:
		# 아이콘 왼쪽, 같은 줄에서 왼쪽으로 조금 밀려나며 사라진다
		var w := l.get_combined_minimum_size().x
		var sep := float(get_theme_constant("separation"))
		l.position = Vector2(-(_label.size.x + _icon.size.x + sep * 2.0 + w + 4.0), (size.y - l.get_combined_minimum_size().y) * 0.5)
		tw.tween_property(l, "position:x", l.position.x - 10.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		l.position = Vector2(-_label.size.x, _label.size.y - 6)
		tw.tween_property(l, "position:y", l.position.y + 14.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
