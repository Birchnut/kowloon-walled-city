class_name ZoneBar
extends Control
## ZoneBar — 긋기. 칩: 주거 / 일터 / 비움 / 지우기 / 철거.
##  - 칠하는 붓(주거·일터·비움·지우기): 칸을 누르거나 끌면 cmd("zone",{col,zone}). 끄는 동안은 화면이 안 움직인다
##    (UIRoot 의 PaintCatcher 가 터치를 받는다). "이동"을 켜면 붓을 잠깐 내려놓고 도시를 끌 수 있다.
##  - 철거: 칸을 누르면 무엇을 잃는지(query cell_info) 보여 주고 확인 → cmd("demolish",{pos}).
##
## 붓 목록을 바꾸려면 BRUSHES 만 고친다(zone 값은 계약의 문자열).

signal finished
signal mode_changed       # 붓이나 이동 토글이 바뀜 → UIRoot 가 PaintCatcher 를 켜고 끈다

const BRUSHES := [
	{"id": "housing", "name": "주거", "icon": "house", "zone": "housing", "hint": "여기엔 살아라. 끌어서 칠한다."},
	{"id": "work", "name": "일터", "icon": "work", "zone": "work", "hint": "여기선 일해라. 끌어서 칠한다."},
	{"id": "keep", "name": "비움", "icon": "keep", "zone": "keep", "hint": "여긴 비워 둔다. 볕이라도 들게."},
	{"id": "erase", "name": "지우기", "icon": "erase", "zone": "", "hint": "선을 지운다. 다시 제멋대로 자란다."},
	{"id": "demolish", "name": "철거", "icon": "wreck", "zone": null, "hint": "칸을 눌러 헌다. 위부터.", "variation": "ButtonChipRed"},
]

var ui: Node = null
var sheet: BottomSheet
var brush: String = "housing"
var pan_mode: bool = false
var _seg: Segmented
var _hint: Label
var _pan: PixelButton
var _stroke: Dictionary = {}       # 이번 획에서 이미 칠한 기둥
var bottom_gap: float = 78.0:
	set(v):
		bottom_gap = v
		if sheet != null:
			sheet.bottom_gap = v


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet = BottomSheet.new()
	sheet.title = "긋기"
	sheet.height_px = 150.0
	sheet.min_height = 150.0
	add_child(sheet)
	_hint = UI.label("", "LabelDim")
	_hint.clip_text = true
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.header.add_child(_hint)
	sheet.header.add_child(UI.spacer(false, Vector2(60, 0)))
	var row := UI.hbox(10)
	sheet.body.add_child(row)
	_seg = Segmented.new()
	_seg.vertical_chips = true
	_seg.small_text = true
	_seg.chip_min = Vector2(UI.TOUCH, 68)
	_seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_seg)
	_pan = PixelButton.make("이동", "move", "ButtonChip", true)
	_pan.small = true
	_pan.toggle_mode = true
	_pan.min_size = Vector2(72, 68)
	_pan.toggled.connect(_on_pan)
	row.add_child(_pan)
	var opts: Array = []
	for b in BRUSHES:
		opts.append({"id": b["id"], "name": b["name"], "icon": b["icon"], "variation": b.get("variation", "ButtonChip")})
	_seg.set_options(opts, brush)
	_seg.selected.connect(_on_brush)
	sheet.closed.connect(func() -> void: finished.emit())
	_sync_hint()


func _ready() -> void:
	sheet.bottom_gap = bottom_gap


func open() -> void:
	pan_mode = false
	_pan.set_pressed_no_signal(false)
	sheet.open()
	Q.vcall("show_zones", [true])
	mode_changed.emit()


func close() -> void:
	Q.vcall("show_zones", [false])
	if sheet.is_open:
		sheet.close()


func is_open() -> bool:
	return sheet.is_open


## 지금 손가락 끌기가 "칠하기"인가(= PaintCatcher 가 터치를 받아야 하나).
func wants_paint() -> bool:
	return sheet.is_open and not pan_mode and brush != "demolish"


func _brush_def() -> Dictionary:
	for b in BRUSHES:
		if b["id"] == brush:
			return b
	return BRUSHES[0]


func _on_brush(id: String) -> void:
	brush = id
	_sync_hint()
	mode_changed.emit()


func _on_pan(on: bool) -> void:
	pan_mode = on
	_sync_hint()
	mode_changed.emit()


func _sync_hint() -> void:
	_hint.text = "이동 중. 누르면 한 칸씩만 칠한다." if pan_mode else str(_brush_def().get("hint", ""))


# ------------------------------------------------------------------ 칠하기
func stroke_begin() -> void:
	_stroke.clear()


## 화면 좌표 한 점을 칠한다(PaintCatcher 가 누름·끌기마다 부른다).
func paint_at(screen_pos: Vector2) -> void:
	paint_info(Q.pick(screen_pos))


## view.cell_tapped 로 들어온 한 칸(이동 모드·철거).
func on_cell(info: Dictionary) -> void:
	if brush == "demolish":
		_ask_demolish(info)
	else:
		_stroke.clear()
		paint_info(info)


func paint_info(info: Dictionary) -> void:
	var col: Variant = info.get("col")
	if not (col is Vector2i) or ui == null:
		return
	if info.has("hit") and not bool(info["hit"]) and not (info.get("pos") is Vector3i and (info["pos"] as Vector3i).x >= 0):
		return
	if _stroke.has(col):
		return
	_stroke[col] = true
	var z: Variant = _brush_def().get("zone")
	if z == null:
		return
	var r: Dictionary = ui.cmd("zone", {"col": col, "zone": str(z)})
	if not bool(r.get("ok", false)) and str(r.get("reason", "")) != "" and _stroke.size() == 1:
		ui.toast(str(r["reason"]), "bad")


func _ask_demolish(info: Dictionary) -> void:
	if ui == null or not bool(info.get("hit", false)) or not (info.get("pos") is Vector3i):
		return
	var pos: Vector3i = info["pos"]
	var ci := Q.dict("cell_info", {"pos": pos})
	var chk := Q.can("demolish", {"pos": pos})
	if ci.is_empty() and not chk["ok"]:
		ui.toast(chk["reason"] if chk["reason"] != "" else "헐 게 없다.", "warn")
		return
	var lines: Array = []
	if str(ci.get("subtitle", "")) != "":
		lines.append(str(ci["subtitle"]))
	for l in UI.to_array(ci.get("lines", [])):
		lines.append(str(l))
	if not chk["ok"]:
		lines.append("")
		lines.append("헐 수 없다: " + (chk["reason"] if chk["reason"] != "" else "이유는 모른다."))
	ui.confirm({
		"title": "%s 헌다" % UI.josa(str(ci.get("title", "이 칸")), "를", "을"),
		"kicker": "철거 — 잃는 것",
		"lines": lines,
		"ok_text": "헌다",
		"danger": true,
		"ok_enabled": chk["ok"],
	}, func() -> void:
		var r: Dictionary = ui.cmd("demolish", {"pos": pos})
		if not bool(r.get("ok", false)):
			ui.toast(str(r.get("reason", "안 된다.")), "bad"))
