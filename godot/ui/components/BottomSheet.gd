class_name BottomSheet
extends Control
## BottomSheet — 아래에서 올라오는 판. 제목은 판 위로 삐져나온 옻칠 간판.
## 화면 전체를 덮지 않는다: 판 바깥은 터치가 그대로 도시로 간다(mouse_filter IGNORE).
##
##   var s := BottomSheet.new(); s.title = "심기"; s.height_ratio = 0.3
##   s.body.add_child(...)       # 내용
##   s.open() / s.close()

signal opened
signal closed

var title: String = "":
	set(v):
		title = v
		if _title_label != null:
			_title_label.text = v
			_plaque.visible = v != ""
var height_px: float = 320.0        # height_ratio 가 0이면 이 값
var height_ratio: float = 0.0       # 화면 높이 대비(0이면 고정 높이)
var min_height: float = 200.0
var max_height: float = 2000.0
var bottom_gap: float = 0.0:        # 화면 아래에서 띄울 거리(동사 바 높이)
	set(v):
		bottom_gap = v
		_place()
var top_limit: float = 110.0        # 이 위로는 올라가지 않는다(상단 띠)
var show_close: bool = true
var is_open: bool = false

var body: VBoxContainer
var header: HBoxContainer            # 제목 간판 오른쪽 빈 자리(부제·버튼용)
var _holder: Control
var _panel: PanelContainer
var _plaque: PanelContainer
var _title_label: Label
var _close: PixelButton
var _slide: float = 0.0             # 0 닫힘 … 1 열림
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_panel = UI.panel("PanelSheet")
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_holder.add_child(_panel)
	var m := UI.margin(12, 2, 12, 10)
	_panel.add_child(m)
	var v := UI.vbox(6)
	m.add_child(v)
	header = UI.hbox(8)
	header.custom_minimum_size = Vector2(0, 30)
	header.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(header)
	body = UI.vbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# 제목 간판(판 위로 걸친다)
	_plaque = UI.panel("PanelPlaque")
	_plaque.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_label = UI.label("", "LabelHead")
	_plaque.add_child(_title_label)
	_plaque.visible = false
	_holder.add_child(_plaque)
	# 닫기(판 위로 걸친 꼬리표). 터치 56
	_close = PixelButton.make("", "close", "ButtonRed")
	_close.pressed.connect(close)
	_holder.add_child(_close)


func _ready() -> void:
	_title_label.text = title
	_plaque.visible = title != ""
	_close.visible = show_close
	get_viewport().size_changed.connect(_place)
	resized.connect(_place)
	_place()


## 제목 간판만큼 header 왼쪽을 비워 둔다(겹침 방지).
func header_left_pad() -> float:
	return (_plaque.get_combined_minimum_size().x + 20.0) if _plaque.visible else 0.0


func sheet_height() -> float:
	var vh := size.y if size.y > 0 else 960.0
	var h := height_px if height_ratio <= 0.0 else vh * height_ratio
	h = clampf(h, min_height, max_height)
	return floorf(minf(h, vh - bottom_gap - top_limit) / UI.UNIT) * UI.UNIT


## 열린 판의 윗변 y(전역). 다른 요소가 판 위에 붙을 때 쓴다.
func top_y() -> float:
	return size.y - bottom_gap - sheet_height() * _slide


func _place() -> void:
	if _holder == null or not is_inside_tree():
		return
	var h := sheet_height()
	var w := size.x
	var y := size.y - bottom_gap - h * _slide
	_holder.position = Vector2(0, round(y / UI.UNIT) * UI.UNIT)
	_holder.size = Vector2(w, h)
	_panel.position = Vector2.ZERO
	_panel.size = Vector2(w, h + 8)
	_plaque.reset_size()
	_plaque.position = Vector2(12, -22)
	_close.size = Vector2(56, 56)
	_close.position = Vector2(w - 56 - 8, -30)


func _set_slide(v: float) -> void:
	_slide = v
	_place()


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_place()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_slide, _slide, 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_slide, _slide, 0.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: visible = false)
	closed.emit()


## 트윈 없이 즉시(스크린샷·테스트용).
func snap_open(v: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	is_open = v
	visible = v
	_set_slide(1.0 if v else 0.0)
