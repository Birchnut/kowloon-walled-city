class_name LastPageView
extends RefCounted
## 장부의 마지막 장 — 본문 만들기. 종이 창(LastPageWin)과 네모청의 '마지막 장' 탭이 같이 쓴다.
## 점수·등급·승리 같은 말은 쓰지 않는다. 다섯 축을 막대와 한 줄 글로 적고, 연표에서 고른 몇 줄을 붙인다.
## 읽는 것: last_page(축), chronicle(줄). 막대 눈금(높이 10층·위아래 ±20)은 임시값(v0.5).

const HEIGHT_FULL := 10.0
const UPDOWN_FULL := 20.0
const KEEP_MAX := 8


static func build(parent: Control, page: Dictionary, chron: Dictionary, width: float = 980.0) -> void:
	var head := UI.label("%s에 적는다" % str(page.get("date_text", "")), "LabelDim")
	parent.add_child(head)
	for a: Variant in UI.to_array(page.get("axes", [])):
		parent.add_child(_axis(UI.to_dict(a), width))
	PcWindow.section(parent, "연표에서")
	var picked := pick_lines(UI.to_array(chron.get("lines", [])))
	if picked.is_empty():
		parent.add_child(UI.label("적힌 줄이 없다.", "LabelDim"))
	for ln: Dictionary in picked:
		var l := UI.label("%s  %s" % [str(ln.get("date_text", "")), UI.no_hanja(str(ln.get("text", "")))], "LabelSmall", true)
		l.custom_minimum_size.x = width
		parent.add_child(l)


static func _axis(a: Dictionary, width: float) -> Control:
	var v := UI.vbox(3)
	var id := str(a.get("id", ""))
	v.add_child(UI.label(str(a.get("name", "")), "LabelGoldSmall"))
	var bar := ShareBar.new()
	bar.custom_minimum_size = Vector2(minf(width, 520.0), 14)
	var val := float(a.get("value", 0.0))
	match id:
		"tiers":
			var segs: Array = []
			var sh := UI.to_array(a.get("shares", []))
			for i in sh.size():
				segs.append([float(sh[i]), UI.ptier(i + 1)])
			bar.segs = segs
		"money_source":
			var d := UI.to_dict(a.get("shares", {}))
			bar.segs = [[float(d.get("tax", 0.0)), UI.pcol("jade_hi")], [float(d.get("org", 0.0)), UI.pcol("red_hi")], [float(d.get("export", 0.0)), UI.pcol("blue")]]
		"height":
			bar.segs = [[val / HEIGHT_FULL, UI.pcol("gold")]]
		"updown":
			bar.center = true
			bar.signed_value = val / UPDOWN_FULL
			bar.signed_col = UI.pcol("gold") if val >= 0.0 else UI.pcol("blue")
		_:
			bar.segs = [[val / 100.0, UI.pcol("red_hi")]]
	v.add_child(bar)
	var t := UI.label(UI.no_hanja(str(a.get("text", ""))), "LabelSmall", true)
	t.custom_minimum_size.x = width
	v.add_child(t)
	return v


## 연표 전체에서 몇 줄을 고른다: 갈래마다 첫 줄(층·목표는 마지막 줄), 최대 KEEP_MAX, 날짜 순.
static func pick_lines(lines: Array) -> Array:
	var first := {}
	var last := {}
	for i in lines.size():
		var k := str(UI.to_dict(lines[i]).get("kind", ""))
		if not first.has(k):
			first[k] = i
		last[k] = i
	var idx: Array = []
	for k: String in first:
		if k in ["last_page", "grade_reached"]:
			continue
		idx.append(int(last[k]) if k in ["floor", "goal"] else int(first[k]))
	idx.sort()
	while idx.size() > KEEP_MAX:
		idx.remove_at(int(idx.size() / 2))
	var out: Array = []
	for i: int in idx:
		out.append(UI.to_dict(lines[i]))
	return out
