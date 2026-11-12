class_name TipLayer
extends Control
## TipLayer — 마우스를 올리면 뜨는 설명(툴팁). 모든 버튼·숫자가 "올려 보면 설명된다"(Jin: 가독성).
##   TipLayer.set_tip(ctrl, "제목\n설명 줄…")       # 첫 줄 = 금색 제목, 나머지 = 본문
##   TipLayer.set_tip(ctrl, func() -> Variant: return "…" 또는 Control)   # 열 때마다 새로 만든다
## 도시 위 마우스 옆 한 줄(배치 거절 이유 등): tips.cursor_text = "…"(빈 문자열이면 숨김)

const DELAY := 0.3
const META := "pc_tip"

var _hover: Control = null
var _hover_t: float = 0.0
var _panel: PanelContainer = null
var _shown_for: Control = null
var _cursor: PanelContainer
var _cursor_lab: Label
var cursor_text: String = "":
	set(v):
		cursor_text = v
		if _cursor_lab != null:
			_cursor_lab.text = UI.no_hanja(v)
			_cursor.visible = v != ""
			_cursor.reset_size()
var cursor_tone: String = ""


static func set_tip(c: Control, content: Variant) -> void:
	if c == null:
		return
	c.set_meta(META, content)
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 50


func _ready() -> void:
	_cursor = UI.panel("PanelTip")
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_lab = UI.label("", "LabelSmall")
	_cursor.add_child(_cursor_lab)
	_cursor.visible = false
	add_child(_cursor)


func _process(delta: float) -> void:
	var mp := get_global_mouse_position()
	if _cursor.visible:
		_cursor_lab.add_theme_color_override("font_color", UI.tone_col(cursor_tone) if cursor_tone != "" else UI.col("paper"))
		_cursor.position = _clamp(mp + Vector2(22, 22), _cursor.size)
	var h := get_viewport().gui_get_hovered_control()
	var owner := _find_owner(h)
	if owner != _hover:
		_hover = owner
		_hover_t = 0.0
		_hide()
	if _hover == null:
		return
	_hover_t += delta
	if _hover_t >= DELAY and _shown_for != _hover:
		_show(_hover)
	if _panel != null:
		_panel.position = _place(mp, _panel.size)


func _find_owner(c: Control) -> Control:
	var n: Node = c
	while n != null and n is Control:
		if n.has_meta(META) and (n as Control).is_visible_in_tree():
			return n
		n = n.get_parent()
	return null


## 지금 떠 있는 툴팁을 다시 만든다(값이 바뀌었을 때).
func refresh() -> void:
	if _shown_for != null and is_instance_valid(_shown_for):
		var c := _shown_for
		_hide()
		_show(c)


func _hide() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	_shown_for = null


func _show(c: Control) -> void:
	var content: Variant = c.get_meta(META)
	if content is Callable:
		content = (content as Callable).call()
	var body: Control = null
	if content is Control:
		body = content
	elif content is String and (content as String).strip_edges() != "":
		body = text_block(content)
	if body == null:
		return
	_panel = UI.panel("PanelTip")
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(body)
	add_child(_panel)
	_panel.reset_size()
	_panel.position = _place(get_global_mouse_position(), _panel.size)
	_shown_for = c


## "제목\n본문…" → 제목(금색) + 본문(줄바꿈, 최대 폭 440).
static func text_block(s: String, width: float = 440.0) -> Control:
	var v := UI.vbox(4)
	var lines := UI.no_hanja(s).split("\n")
	var first := true
	for ln: String in lines:
		var l: Label
		if first:
			l = UI.label(ln, "LabelGold")
			first = false
		else:
			l = UI.label(ln, "LabelSmall", true)
			l.custom_minimum_size.x = minf(width, maxf(160.0, ln.length() * 20.0))
		v.add_child(l)
	return v


func _place(mp: Vector2, sz: Vector2) -> Vector2:
	var vr := get_viewport_rect().size
	var p := mp + Vector2(18, 22)
	if p.x + sz.x > vr.x - 6:
		p.x = mp.x - sz.x - 12
	if p.y + sz.y > vr.y - 6:
		p.y = mp.y - sz.y - 12
	return Vector2(maxf(p.x, 4), maxf(p.y, 4)).floor()


func _clamp(p: Vector2, sz: Vector2) -> Vector2:
	var vr := get_viewport_rect().size
	return Vector2(clampf(p.x, 4, vr.x - sz.x - 4), clampf(p.y, 4, vr.y - sz.y - 4)).floor()
