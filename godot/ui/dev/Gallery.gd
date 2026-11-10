extends Control
## 컴포넌트 견본 — 스타일을 바꾼 뒤 한눈에 확인한다.
##   tools/shot.sh res://ui/dev/Gallery.tscn out 20 540x960


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("2a3350")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := UI.margin(12, 12, 12, 12)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var v := UI.vbox(10)
	m.add_child(v)

	v.add_child(UI.label("구룡성채 UI 견본 九龍城寨", "LabelHead"))
	var row := UI.hbox(8)
	v.add_child(row)
	for a in [["기본", ""], ["결재", "ButtonRed"], ["놓기", "ButtonJade"], ["금", "ButtonGold"], ["취소", "ButtonGhost"]]:
		row.add_child(PixelButton.make(a[0], "", a[1]))
	var off := PixelButton.make("잠김", "lock", "")
	off.disabled = true
	row.add_child(off)

	var seg := Segmented.new()
	seg.set_options([{"id": "a", "name": "금지"}, {"id": "b", "name": "허가"}, {"id": "c", "name": "장려"}, {"id": "d", "name": "밀어주기", "locked": true}], "b")
	v.add_child(seg)

	var verbs := UI.hbox(6)
	v.add_child(verbs)
	var i := 0
	for a in [["심기", "v_plant"], ["긋기", "v_zone"], ["허가", "v_policy"], ["결재", "v_cards"], ["기록", "v_record"]]:
		var b := PixelButton.make(a[0], a[1], "ButtonVerb", true)
		b.tint_icon = false
		b.toggle_mode = true
		b.button_pressed = i == 0
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.min_size = Vector2(0, 68)
		verbs.add_child(b)
		if i == 3:
			b.set_badge.call_deferred(3)
		i += 1

	var res := UI.hbox(16)
	v.add_child(res)
	for a in [["coin", 1240], ["food", 86], ["mat", 42], ["pop", 31]]:
		var il := IconLabel.make(a[0])
		res.add_child(il)
		il.set_value(a[1])
	var meters := UI.hbox(12)
	v.add_child(meters)
	for a in [["위신", "gold", 62], ["악명", "red", 18], ["민심", "jade", 44]]:
		var me := Meter.new()
		me.caption = a[0]
		me.tone = a[1]
		meters.add_child(me)
		me.set_value(a[2])

	var panels := UI.hbox(8)
	v.add_child(panels)
	for a in [["", "먹판"], ["PanelGold", "금테"], ["PanelDeep", "깊은"], ["PanelPlaque", "간판"], ["PanelPlaqueJade", "비취"], ["PanelPlaqueGold", "금"]]:
		var p := UI.panel(a[0])
		p.add_child(UI.label(a[1], "LabelInkBold" if a[0] == "PanelPlaqueGold" else ""))
		panels.add_child(p)

	var signs := UI.hbox(8)
	v.add_child(signs)
	for g in ["水", "麻雀", "收買", "福", "텃", "卡拉K"]:
		signs.add_child(SignTile.make(g))
	signs.add_child(SignTile.make("醫", true))
	signs.add_child(SignTile.make("龍", false, true))
	var tags := UI.vbox(4)
	v.add_child(tags)
	var tr := UI.hbox(4)
	tags.add_child(tr)
	for a in [["어묵", ""], ["함석", "gold"], ["치과", "red"], ["텃밭", "jade"], ["국숫집", "paper"]]:
		tr.add_child(UI.tag(a[0], a[1]))
	var sl := HSlider.new()
	sl.value = 40
	sl.custom_minimum_size = Vector2(160, 40)
	tags.add_child(sl)
