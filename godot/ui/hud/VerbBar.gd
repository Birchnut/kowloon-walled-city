class_name VerbBar
extends PanelContainer
## VerbBar — 하단 동사 바. 심기 / 긋기 / 허가 / 결재(배지) / 기록. 거두기는 버튼이 아니다(말풍선을 누른다).
## 동사를 빼거나 넣으려면 VERBS 만 고친다.

signal verb_pressed(id: String)

const VERBS := [
	{"id": "plant", "name": "심기", "icon": "v_plant"},
	{"id": "zone", "name": "긋기", "icon": "v_zone"},
	{"id": "policy", "name": "허가", "icon": "v_policy"},
	{"id": "cards", "name": "결재", "icon": "v_cards"},
	{"id": "record", "name": "기록", "icon": "v_record"},
]
const BAR_H := 78.0

var _buttons: Dictionary = {}
var _safe: Control


func _init() -> void:
	theme_type_variation = "PanelBar"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(0)
	add_child(v)
	var m := UI.margin(6, 2, 6, 4)
	v.add_child(m)
	var row := UI.hbox(4)
	m.add_child(row)
	for vb in VERBS:
		var b := PixelButton.make(vb["name"], vb["icon"], "ButtonVerb", true)
		b.tint_icon = false
		b.toggle_mode = true
		b.min_size = Vector2(UI.TOUCH, 66)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_pressed.bind(vb["id"]))
		row.add_child(b)
		_buttons[vb["id"]] = b
	_safe = UI.spacer(false, Vector2.ZERO)
	v.add_child(_safe)


func set_safe_bottom(px: float) -> void:
	_safe.custom_minimum_size.y = px


func bar_height() -> float:
	return maxf(BAR_H, size.y)


func _on_pressed(id: String) -> void:
	verb_pressed.emit(id)


## 켜진 동사 표시(빈 문자열 = 없음).
func set_active(id: String) -> void:
	for k in _buttons:
		(_buttons[k] as PixelButton).set_pressed_no_signal(k == id)


func set_badge(id: String, n: int) -> void:
	if _buttons.has(id):
		(_buttons[id] as PixelButton).set_badge(n)


func pulse(id: String) -> void:
	if _buttons.has(id):
		(_buttons[id] as PixelButton).pulse_badge(5)


## null/빈 배열 = 전부 켬. 튜토리얼이 아직 안 가르친 동사를 잠글 때 쓴다.
func set_enabled(ids: Variant) -> void:
	for k in _buttons:
		var on: bool = not (ids is Array) or (ids as Array).is_empty() or k in (ids as Array)
		var b: PixelButton = _buttons[k]
		b.disabled = not on
		b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.45)


func button(id: String) -> PixelButton:
	return _buttons.get(id)
