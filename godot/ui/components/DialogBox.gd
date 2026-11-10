class_name DialogBox
extends Control
## DialogBox — 오프닝/튜토리얼 대화 상자. 말하는 사람 간판, 타자기 글자, 탭으로 넘기기, 건너뛰기.
## 두 가지 모드:
##   say(…)  : 아래쪽 큰 상자. 화면 어디를 눌러도 넘어간다(이때만 화면 전체가 터치를 먹는다).
##   hint(…) : 위쪽 얇은 띠. 터치를 먹지 않는다(플레이어가 직접 뭔가 해야 하는 단계).

signal advanced
signal skipped

const CPS := 70.0          # 초당 글자 수(줄바꿈 방지용 폭 0 문자가 섞여 있어 실제로는 절반쯤)

var bottom_gap: float = 0.0
var top_offset: float = 118.0
var at_top: bool = false            # 시트가 열려 있으면 위쪽에(시트 내용을 가리지 않게)
var _catch: Control
var _box: PanelContainer
var _text: Label
var _plaque: PanelContainer
var _speaker: Label
var _role: PanelContainer
var _more: TextureRect
var _skip: PixelButton
var _hint: PanelContainer
var _hint_text: Label
var _chars: float = 0.0
var _typing: bool = false
var _mode: String = ""
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _ready() -> void:
	_catch = Control.new()
	_catch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catch.mouse_filter = Control.MOUSE_FILTER_STOP
	_catch.gui_input.connect(_on_catch_input)
	add_child(_catch)

	_box = UI.panel("PanelGold")
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	var m := UI.margin(6, 14, 6, 4)
	_box.add_child(m)
	_text = UI.label("", "", true)
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.custom_minimum_size = Vector2(0, 96)
	m.add_child(_text)
	_more = UI.icon_rect("down", UI.col("gold"))
	_more.size_flags_horizontal = Control.SIZE_SHRINK_END
	_more.size_flags_vertical = Control.SIZE_SHRINK_END
	_box.add_child(_more)

	_plaque = UI.panel("PanelPlaque")
	_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ph := UI.hbox(8)
	_plaque.add_child(ph)
	_speaker = UI.label("", "LabelHead")
	ph.add_child(_speaker)
	add_child(_plaque)
	_role = UI.tag("", "gold")
	add_child(_role)

	_skip = PixelButton.make("건너뛰기", "skip", "ButtonGhost")
	_skip.pressed.connect(func() -> void: skipped.emit())
	add_child(_skip)

	_hint = UI.panel("PanelGold")
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_text = UI.label("", "LabelSmall", true)
	_hint.add_child(_hint_text)
	add_child(_hint)

	resized.connect(_place)
	_box.minimum_size_changed.connect(_place, CONNECT_DEFERRED)
	_hint.minimum_size_changed.connect(_place, CONNECT_DEFERRED)
	set_process(false)


func say(speaker: String, text: String, role: String = "") -> void:
	_mode = "say"
	visible = true
	_catch.visible = true
	_box.visible = true
	_hint.visible = false
	_speaker.text = speaker
	_plaque.visible = speaker != ""
	(_role.get_child(0) as Label).text = role
	_role.visible = role != "" and speaker != ""
	_text.text = UI.keep(text)
	_text.visible_characters = 0
	_chars = 0.0
	_typing = true
	_more.visible = false
	set_process(true)
	_place()
	_box.modulate.a = 1.0


func hint(text: String) -> void:
	_mode = "hint"
	visible = true
	_catch.visible = false
	_box.visible = false
	_plaque.visible = false
	_role.visible = false
	_hint.visible = text != ""
	_hint_text.text = UI.keep(text)
	_typing = false
	set_process(false)
	_place()
	if text != "":
		_hint.modulate.a = 0.0
		_hint.create_tween().tween_property(_hint, "modulate:a", 1.0, 0.2)


func hide_box() -> void:
	visible = false
	_mode = ""
	set_process(false)


## 위쪽에 차지한 영역의 아래 끝(y). 위쪽에 아무것도 없으면 0 — 토스트가 그 아래로 비킨다.
func occupied_bottom() -> float:
	if not visible:
		return 0.0
	if _mode == "hint" and _hint.visible:
		return _skip.position.y + _skip.size.y
	if _mode == "say" and at_top:
		return _skip.position.y + _skip.size.y
	return 0.0


func is_typing() -> bool:
	return _typing


func _place() -> void:
	if _box == null:
		return
	var w := size.x
	var side := 10.0
	# 대화 상자: 화면 아래
	_box.custom_minimum_size = Vector2(w - side * 2, 0)
	_box.size = Vector2.ZERO
	var by := size.y - bottom_gap - _box.size.y - 12.0
	if at_top:
		by = top_offset + 30.0
	_box.position = UI.snap(Vector2(side, by))
	_plaque.reset_size()
	_plaque.position = _box.position + Vector2(14, -24)
	_role.reset_size()
	_role.position = _plaque.position + Vector2(_plaque.size.x + 6, 6)
	# 건너뛰기: say 는 상자 오른쪽 위, hint 는 띠 아래 오른쪽
	_skip.reset_size()
	_skip.size = Vector2(maxf(_skip.size.x, 132), 56)
	if _mode == "hint":
		_hint.custom_minimum_size = Vector2(w - 16 - 76, 0)
		_hint.size = Vector2.ZERO
		_hint.position = Vector2(8, top_offset)
		_skip.position = Vector2(8, top_offset + (_hint.size.y + 6 if _hint.visible else 0.0))
	else:
		# 위쪽 상자면 건너뛰기를 왼쪽 아래에(오른쪽 레일 버튼과 겹치지 않게)
		_skip.position = Vector2(side, _box.position.y + _box.size.y + 6) if at_top else Vector2(w - _skip.size.x - side, _box.position.y - 62)


func _process(delta: float) -> void:
	_t += delta
	if _typing:
		_chars += delta * CPS
		var total := _text.get_total_character_count()
		if _chars >= total:
			_finish_typing()
		else:
			_text.visible_characters = int(_chars)
	elif _mode == "say":
		# ▼ 깜빡임(2px 위아래)
		_more.position.y = _box.size.y - 26.0 + (2.0 if fmod(_t, 0.8) < 0.4 else 0.0)
		_more.position.x = _box.size.x - 36.0


func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	_more.visible = true


func _on_catch_input(ev: InputEvent) -> void:
	# 터치면 터치 누름으로 넘긴다(흉내 낸 마우스는 먹기만 한다) — 넘기는 손가락이 아래 도시까지 가지 않게.
	if ev is InputEventScreenTouch:
		if ev.pressed:
			advance()
		accept_event()
	elif ev is InputEventScreenDrag:
		accept_event()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed and ev.device != InputEvent.DEVICE_ID_EMULATION:
			advance()
		accept_event()


## 타자 중이면 다 보여 주고, 다 보였으면 다음으로.
func advance() -> void:
	if _mode != "say":
		return
	if _typing:
		_finish_typing()
	else:
		advanced.emit()
