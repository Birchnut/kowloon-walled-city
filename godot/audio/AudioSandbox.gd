extends Control
## AudioSandbox — 소리 미리 듣기. 효과음은 단추나 글쇠로, 배경은 상태 막대(시각·인구·공사장·불·멀리 보기·배속·멈춤·비)로 흉내 낸다.
## 열기: 편집기에서 res://audio/AudioSandbox.tscn 실행(F6). 게임 상태 대신 여기 막대 값이 감독(AudioDirector)에 들어간다.

const SB := preload("res://audio/SfxBank.gd")
const AB := preload("res://audio/AmbienceBank.gd")
const KEYS := "1234567890QWERTYUIOPASDFGHJKL"

var d: Node = null
var sfx: Node = null
var info: Label
var ov := {"tod": 13.0 / 24.0, "pop": 400, "sites": 1, "fires": 0, "zoom_out": 0.5, "speed": 1.0, "paused": false}
var names: Array = []


func _ready() -> void:
	sfx = get_node("/root/Sfx")
	d = sfx.director
	d.set("_started", true)
	d.call("set_state_override", ov)
	names = SB.names()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#1b1820")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 24)
	add_child(root)
	# 왼쪽: 효과음
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	left.add_child(_title("효과음 (글쇠 또는 누르기)"))
	var grid := GridContainer.new()
	grid.columns = 3
	left.add_child(grid)
	for i in names.size():
		var n: String = names[i]
		var b := Button.new()
		b.text = "%s  %s" % [KEYS[i] if i < KEYS.length() else " ", n]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: sfx.play(n))
		b.focus_mode = Control.FOCUS_NONE
		grid.add_child(b)
	left.add_child(_title("배경 한 번짜리"))
	var g2 := GridContainer.new()
	g2.columns = 4
	left.add_child(g2)
	for n: String in AB.SHOTS:
		var b := Button.new()
		b.text = n
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: d.call("play_shot", n, 6.0))
		g2.add_child(b)
	# 오른쪽: 배경 섞기·볼륨
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(460, 0)
	root.add_child(right)
	right.add_child(_title("배경 상태(흉내)"))
	_slider(right, "시각", 0.0, 24.0, ov["tod"] * 24.0, func(v: float) -> void: ov["tod"] = v / 24.0)
	_slider(right, "인구", 0.0, 2000.0, ov["pop"], func(v: float) -> void: ov["pop"] = int(v))
	_slider(right, "공사장", 0.0, 5.0, ov["sites"], func(v: float) -> void: ov["sites"] = int(v))
	_slider(right, "불", 0.0, 3.0, ov["fires"], func(v: float) -> void: ov["fires"] = int(v))
	_slider(right, "멀리 보기", 0.0, 1.0, ov["zoom_out"], func(v: float) -> void: ov["zoom_out"] = v)
	_slider(right, "배속", 1.0, 4.0, 1.0, func(v: float) -> void: ov["speed"] = v)
	_slider(right, "비", 0.0, 1.0, 0.0, func(v: float) -> void: sfx.set_rain(v))
	var pc := CheckBox.new()
	pc.text = "멈춤"
	pc.toggled.connect(func(on: bool) -> void: ov["paused"] = on)
	right.add_child(pc)
	right.add_child(_title("볼륨"))
	for bus: String in ["master", "sfx", "ambience", "music"]:
		_slider(right, bus, 0.0, 1.0, sfx.get_volume(bus), func(v: float) -> void: sfx.set_volume(bus, v))
	var mc := CheckBox.new()
	mc.text = "음악"
	mc.button_pressed = sfx.music_enabled()
	mc.toggled.connect(func(on: bool) -> void: sfx.set_music_enabled(on))
	right.add_child(mc)
	var ac := CheckBox.new()
	ac.text = "배경"
	ac.button_pressed = sfx.ambience_enabled()
	ac.toggled.connect(func(on: bool) -> void: sfx.set_ambience_enabled(on))
	right.add_child(ac)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 13)
	right.add_child(info)


func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color("#e8c170"))
	return l


func _slider(parent: Control, label: String, lo: float, hi: float, v: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 200.0
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	var val := Label.new()
	val.custom_minimum_size = Vector2(56, 0)
	val.text = String.num(v, 2)
	s.value_changed.connect(func(x: float) -> void:
		val.text = String.num(x, 2)
		cb.call(x)
		d.call("set_state_override", ov))
	row.add_child(s)
	row.add_child(val)
	parent.add_child(row)


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	var ch := OS.get_keycode_string((ev as InputEventKey).keycode)
	var i := KEYS.find(ch)
	if i >= 0 and i < names.size():
		sfx.play(names[i])


func _process(_dt: float) -> void:
	if Engine.get_process_frames() % 15 != 0:
		return
	var s: Dictionary = d.call("debug_state")
	var r: Dictionary = d.call("shot_rates")
	var rs: Array = []
	for k: String in r:
		if float(r[k]) > 0.05:
			rs.append("%s %.1f" % [k, r[k]])
	info.text = "만들기 끝: %s (%.0f ms)\n층 크기: %s\n목표: %s\n분위기: %s   멈춤 덕킹 %.1f dB\n한 번짜리/분: %s" % [
		s["built"], s["build_ms"], str(s["layers"]), _round(s["targets"]), s["mood"], s["duck_db"], ", ".join(rs)]


func _round(dd: Dictionary) -> String:
	var a: Array = []
	for k: String in dd:
		a.append("%s %.2f" % [k, dd[k]])
	return ", ".join(a)
