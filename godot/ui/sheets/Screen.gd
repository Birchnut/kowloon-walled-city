class_name Screen
extends Control
## Screen — 화면 하나(짓기·경제·탐험·교역·성채·들여다보기)의 공통 모양. UIRoot 가 하나씩만 연다.
## 하단 시트형 화면은 sheet(BottomSheet)를 쓰고, 탐험처럼 전면 화면은 sheet 없이 자기가 그린다.
##   open(arg) / close() / is_open() / refresh()
##   on_tap(info) -> bool    도시를 눌렀을 때(먹었으면 true)
##   on_drag(info)           칠하기 모드에서 끌기
##   on_event(name, payload) Game.event
##   inset() -> float        도시 아래쪽을 얼마나 가리는지(뷰 set_bottom_inset)
## 값은 전부 Game.query/can 에서. 명령은 ui.cmd(...) (튜토리얼이 엿듣는다).

signal finished

const POLL := 1.0

var ui: Node = null
var sheet: BottomSheet = null
var arg: String = ""
var poll_sec: float = POLL
var _poll_t: float = 0.0
var _open: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func make_sheet(title: String, ratio: float, min_h: float = 220.0) -> BottomSheet:
	sheet = BottomSheet.new()
	sheet.title = title
	sheet.height_ratio = ratio
	sheet.min_height = min_h
	add_child(sheet)
	sheet.closed.connect(func() -> void:
		if _open:
			_open = false
			_on_closed()
			finished.emit())
	return sheet


func set_frame(bottom_gap: float, top_limit: float) -> void:
	if sheet != null:
		sheet.bottom_gap = bottom_gap
		sheet.top_limit = top_limit


func open(a: String = "") -> void:
	arg = a
	var was := _open
	_open = true
	_poll_t = poll_sec
	if sheet != null:
		sheet.open()
	visible = true
	_on_open(a, was)


func close() -> void:
	if not _open:
		return
	_open = false
	if sheet != null:
		sheet.close()
	_on_closed()


func is_open() -> bool:
	return _open


func inset() -> float:
	if sheet != null and sheet.is_open:
		return sheet.sheet_height()
	return 0.0


func _process(delta: float) -> void:
	if not _open:
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = poll_sec
		refresh()


# ------------------------------------------------------------------ 하위가 채운다
func _on_open(_a: String, _was_open: bool) -> void:
	refresh()


func _on_closed() -> void:
	pass


func refresh() -> void:
	pass


func on_tap(_info: Dictionary) -> bool:
	return false


func on_drag(_info: Dictionary) -> void:
	pass


func on_event(_n: String, _p: Dictionary) -> void:
	pass


# ------------------------------------------------------------------ 공용 도우미
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## 이름 — 값 한 줄(작은 글자).
static func kv(k: String, v: String, v_var: String = "LabelSmall") -> HBoxContainer:
	var h := UI.hbox(8)
	var a := UI.label(k, "LabelDim")
	h.add_child(a)
	var b := UI.label(v, v_var)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(b)
	return h


## 섹션 머리(금색 작은 글자 + 선).
static func section(text: String) -> Control:
	var h := UI.hbox(6)
	h.add_child(UI.label(text, "LabelGoldSmall"))
	var line := ColorRect.new()
	line.color = UI.col("line")
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	return h


## 세로 스크롤 본문(DragScroll + VBox). 반환: [scroll, vbox]
static func scroll_body(sep: int = 6) -> Array:
	var sc := DragScroll.new()
	var v := UI.vbox(sep)
	sc.set_content(v)
	return [sc, v]


static func money(v: Variant) -> String:
	return "₩" + UI.num(v)


static func signed(v: float, digits: int = 0) -> String:
	var s := UI.num(absf(v)) if digits == 0 else str(snappedf(absf(v), pow(10.0, -digits)))
	return ("+" if v >= 0.0 else "-") + s


## 상품 수량 사전 {id: n} → "목재 10 · 고물 2". 이름은 economy 질의의 goods 에서 찾는다.
static func goods_text(goods: Dictionary, names: Dictionary) -> String:
	var parts: Array = []
	for g in goods:
		parts.append("%s %s" % [str(names.get(g, g)), UI.num(float(goods[g]))])
	return " · ".join(parts)
