class_name NavBar
extends PanelContainer
## NavBar — 하단 다섯 화면: 짓기 · 경제 · 탐험 · 교역 · 성채. 아이콘 대신 간판 한자(建 賬 探 行 城).
## 배지: 탐험 = hud.teams_done, 교역 = hud.contracts_failed, 성채 = 목표 달성·연구 끝(UIRoot 가 넣는다).
## 화면을 빼거나 넣으려면 SCREENS 만 고친다.

signal screen_pressed(id: String)

const SCREENS := [
	{"id": "build", "name": "짓기", "glyph": "建"},
	{"id": "economy", "name": "경제", "glyph": "賬"},
	{"id": "expedition", "name": "탐험", "glyph": "探"},
	{"id": "trade", "name": "교역", "glyph": "行"},
	{"id": "keep", "name": "성채", "glyph": "城"},
]
const BAR_H := 80.0

var _buttons: Dictionary = {}
var _safe: Control


func _init() -> void:
	theme_type_variation = "PanelBar"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(0)
	add_child(v)
	var m := UI.margin(6, 4, 6, 4)
	v.add_child(m)
	var row := UI.hbox(4)
	m.add_child(row)
	for s: Dictionary in SCREENS:
		var b := NavButton.nav_make(s["name"], s["glyph"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: screen_pressed.emit(s["id"]))
		row.add_child(b)
		_buttons[s["id"]] = b
	_safe = UI.spacer(false, Vector2.ZERO)
	v.add_child(_safe)


func set_safe_bottom(px: float) -> void:
	_safe.custom_minimum_size.y = px


func bar_height() -> float:
	return maxf(BAR_H, size.y)


func set_active(id: String) -> void:
	for k in _buttons:
		(_buttons[k] as PixelButton).set_pressed_no_signal(k == id)


func set_badge(id: String, n: int) -> void:
	if _buttons.has(id):
		(_buttons[id] as PixelButton).set_badge(n)


func pulse(id: String) -> void:
	if _buttons.has(id):
		(_buttons[id] as PixelButton).pulse_badge(5)


## null/빈 배열 = 전부 켬. 튜토리얼이 아직 안 가르친 화면을 잠글 때 쓴다.
func set_enabled(ids: Variant) -> void:
	for k in _buttons:
		var on: bool = not (ids is Array) or (ids as Array).is_empty() or k in (ids as Array)
		var b: PixelButton = _buttons[k]
		b.disabled = not on
		b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.4)


func button(id: String) -> PixelButton:
	return _buttons.get(id)


## 간판 글자 하나 + 이름. 켜지면 붉은 옻칠.
class NavButton extends PixelButton:
	var glyph: Label

	static func nav_make(nm: String, g: String) -> NavButton:
		var b := NavButton.new()
		b.label_text = nm
		b.vertical = true
		b.small = true
		b.toggle_mode = true
		b.theme_type_variation = "ButtonVerb"
		b.min_size = Vector2(UI.TOUCH, 68)
		b.set_meta("glyph", g)
		return b

	func _ready() -> void:
		super._ready()
		glyph = UI.label(str(get_meta("glyph", "")), "LabelSign")
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.custom_minimum_size = Vector2(0, 30)
		_box.add_child(glyph)
		_box.move_child(glyph, 0)
		_update_min()

	func _layout() -> void:
		super._layout()
		if glyph != null:
			glyph.modulate = Color(1, 1, 1, 0.4) if disabled else Color.WHITE
