class_name CardView
extends PanelContainer
## CardView — 결재 서류 한 장. 누런 종이 위에 올린 사람(이름+역할), 제목, 본문, 선택지 2~3개.
## 선택하면 도장이 찍히고 chosen(index) 가 나간다.
##
## 카드 Dictionary(계약): {uid, title, body, speaker, choices:[{label, hint}]}
##  - speaker 는 String 또는 {name, role} 둘 다 받는다. role 은 card.role 도 본다.

signal chosen(index: int)

var card: Dictionary = {}
var _choices_box: VBoxContainer
var _stamp: Control
var _locked: bool = false


static func make(card_data: Dictionary, counter: String = "") -> CardView:
	var c := CardView.new()
	c._build(card_data, counter)
	return c


func _build(card_data: Dictionary, counter: String) -> void:
	card = card_data
	theme_type_variation = "PanelPaper"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(6)
	add_child(v)

	# 머리: 올린 사람 + 역할 + (n/m)
	var head := UI.hbox(8)
	v.add_child(head)
	var sp: Variant = card.get("speaker", "")
	var sp_name := ""
	var sp_role := str(card.get("role", ""))
	if sp is Dictionary:
		sp_name = str(sp.get("name", ""))
		sp_role = str(sp.get("role", sp_role))
	else:
		sp_name = str(sp)
	if sp_name == "":
		sp_name = "올린 사람 없음"
	head.add_child(UI.label(sp_name, "LabelInkBold"))
	if sp_role != "":
		var tag := UI.tag(sp_role, "paper")
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tag)
	head.add_child(UI.spacer(true))
	if counter != "":
		head.add_child(UI.label(counter, "LabelInkSmall"))
	var sep := HSeparator.new()
	sep.theme_type_variation = "SepPaper"
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sep)

	var title := UI.label(str(card.get("title", "제목 없는 서류")), "LabelHeadInk", true)
	v.add_child(title)
	var body := UI.label(str(card.get("body", "")), "LabelInk", true)
	body.visible = body.text != ""
	v.add_child(body)
	v.add_child(UI.spacer(false, Vector2(0, 4)))

	_choices_box = UI.vbox(6)
	v.add_child(_choices_box)
	var choices := UI.to_array(card.get("choices", []))
	if choices.is_empty():
		choices = [{"label": "알았다", "hint": ""}]
	var i := 0
	for ch in choices:
		var d := UI.to_dict(ch)
		var b := ChoiceButton.make(str(d.get("label", "선택 %d" % (i + 1))), str(d.get("hint", "")), "Button")
		b.disabled = bool(d.get("locked", false))
		b.pressed.connect(_on_choice.bind(i))
		_choices_box.add_child(b)
		i += 1


func _on_choice(i: int) -> void:
	if _locked:
		return
	_locked = true
	chosen.emit(i)


## 결과가 실패면 다시 고를 수 있게 푼다.
func unlock() -> void:
	_locked = false


## 도장 쾅. text 는 한 글자(准 / 駁 …).
func stamp(text: String = "准") -> void:
	if _stamp != null:
		return
	var s := UI.panel("PanelSeal")
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(text, "LabelSignBig")
	l.add_theme_color_override("font_color", UI.col("red"))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	s.add_child(l)
	_stamp = s
	# PanelContainer 의 배치를 피하려고 top_level 로 띄운다
	s.top_level = true
	add_child(s)
	s.reset_size()
	s.global_position = global_position + Vector2(size.x - s.size.x - 26, 44)
	s.pivot_offset = s.size * 0.5
	s.scale = Vector2(2.2, 2.2)
	s.modulate.a = 0.0
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(s, "modulate:a", 0.92, 0.08)
