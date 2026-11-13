class_name PcTutorial
extends Control
## PC판 오프닝(마우스·키보드). 대본은 data/ui/tutorial_pc.json. 진행은 시뮬 tutorial{step} 로 세이브에 들어간다(끝 = 1000).
## 상자는 짓기 막대 위 가운데, 강조는 대상 둘레의 금색 테(깜박임). 상자는 클릭을 먹지 않는 곳에 둔다(버튼만 받는다).

const DONE := 1000

var ui: Node = null
var running: bool = false
var step: int = -1
var _steps: Array = []
var _speaker: String = ""
var _box: PanelContainer
var _who: Label
var _text: Label
var _keys: Label
var _count: Label
var _next: PcButton
var _skip: PcButton
var _hl: Control
var _hl_rect: Rect2 = Rect2()
var _t: float = 0.0
var _left: float = 0.0
var _cam_armed := false


func _init() -> void:
	theme = PcTheme.paper_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	var root := UI.to_dict(Data.file("tutorial_pc"))
	_steps = UI.to_array(root.get("steps", []))
	_speaker = str(root.get("speaker", ""))
	_hl = Control.new()
	_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hl.draw.connect(_draw_hl)
	add_child(_hl)
	_box = UI.panel("PanelGold")
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.custom_minimum_size = Vector2(620, 0)
	add_child(_box)
	var v := UI.vbox(6)
	_box.add_child(v)
	var h := UI.hbox(8)
	v.add_child(h)
	h.add_child(Picto.make("pop", UI.pcol("gold_hi")))
	_who = UI.label(_speaker, "LabelGoldSmall")
	h.add_child(_who)
	_count = UI.label("", "LabelMute")
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(_count)
	_text = UI.label("", "LabelBody", true)
	_text.custom_minimum_size.x = 590
	v.add_child(_text)
	_keys = UI.label("", "LabelKey")
	v.add_child(_keys)
	var row := UI.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	_skip = PcButton.make("오프닝 건너뛰기", "", "", "ButtonFlat")
	_skip.min_h = 32
	_skip.pressed.connect(skip)
	row.add_child(_skip)
	_next = PcButton.make("다음", "right", "Enter", "ButtonGold")
	_next.min_h = 34
	_next.pressed.connect(_advance)
	row.add_child(_next)


func saved_step() -> int:
	return int(Q.dict("hud").get("tutorial", 0))


func is_done() -> bool:
	var s := saved_step()
	if s >= DONE:
		return true
	# 이미 한참 한 도시(옛 세이브)는 본 것으로
	return s == 0 and int(Q.dict("hud").get("day", 1)) >= 2


func start(from: int = 0) -> void:
	if _steps.is_empty():
		return
	running = true
	visible = true
	_hook_camera()
	_go(clampi(from, 0, _steps.size() - 1))


func skip() -> void:
	running = false
	visible = false
	step = -1
	if ui != null:
		ui.cmd("tutorial", {"step": DONE})


func step_index() -> int:
	return step


func _go(i: int) -> void:
	if i >= _steps.size():
		skip()
		return
	step = i
	if ui != null and i > 0:
		Game.cmd("tutorial", {"step": i})
	var s := UI.to_dict(_steps[i])
	_text.text = UI.keep(UI.no_hanja(str(s.get("text", ""))))
	_keys.text = str(s.get("keys", ""))
	_keys.visible = _keys.text != ""
	_count.text = "%d / %d" % [i + 1, _steps.size()]
	var wait := str(s.get("wait", ""))
	_next.visible = wait == ""
	_next.label_text = "시작한다" if i == _steps.size() - 1 else "다음"
	_left = float(s.get("timeout", 0.0))
	_cam_armed = wait == "camera"
	# 이미 된 일(다시 연 세이브)은 넘긴다
	if _satisfied(s):
		_advance.call_deferred()
	_box.reset_size()


func _advance() -> void:
	if not running:
		return
	_go(step + 1)


func _satisfied(s: Dictionary) -> bool:
	match str(s.get("wait", "")):
		"houses_ge":
			var n := 0
			for t: Variant in UI.to_array(Q.dict("economy").get("tiers", [])):
				n += int(UI.to_dict(t).get("houses", 0))
			return n >= int(s.get("n", 8))
	return false


func _process(delta: float) -> void:
	if not running:
		return
	_t += delta
	var s := UI.to_dict(_steps[step]) if step >= 0 and step < _steps.size() else {}
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			_advance()
			return
	if str(s.get("wait", "")) == "houses_ge" and int(_t * 4.0) != int((_t - delta) * 4.0) and _satisfied(s):
		_advance()
		return
	# 상자 자리: 짓기 막대 위 가운데(왼쪽 기둥·살피기와 겹치지 않게)
	var vs := get_viewport_rect().size
	var br: Rect2 = ui.build.get_global_rect() if ui != null else Rect2(0, vs.y, 0, 0)
	_box.reset_size()
	var x := floorf(br.get_center().x - _box.size.x * 0.5)
	_box.position = Vector2(clampf(x, LeftColumn.W + 20, vs.x - _box.size.x - 20), br.position.y - _box.size.y - 16)
	var tgt := str(s.get("target", ""))
	var tr: Rect2 = ui.target_rect(tgt) if ui != null else Rect2()
	# 창이 떠 있으면 창 밑에 깔린 대상의 테두리는 그리지 않는다(창 위에 금테가 떠 보였다 — 통합 때 고침)
	if ui != null and ui.any_window() and not tgt.begins_with("win:"):
		tr = Rect2()
	if tr != _hl_rect or true:
		_hl_rect = tr
		_hl.queue_redraw()


func _draw_hl() -> void:
	if _hl_rect.size.x <= 0.0:
		return
	var a := 0.55 + 0.45 * sin(_t * 5.0)
	var r := _hl_rect.grow(6)
	var c := Color(UI.pcol("gold_hi"), a)
	_hl.draw_rect(r, c, false, 3.0)
	_hl.draw_rect(r.grow(4), Color(c, a * 0.35), false, 2.0)


func _unhandled_key_input(ev: InputEvent) -> void:
	if running and ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER] and _next.visible:
		get_viewport().set_input_as_handled()
		_advance()


# ------------------------------------------------------------------ 엿듣기
func _hook_camera() -> void:
	var v := Q.view()
	if v != null and v.has_signal("view_changed") and not v.is_connected("view_changed", _on_view_changed):
		v.connect("view_changed", _on_view_changed)


func _on_view_changed() -> void:
	if running and _cam_armed and _t > 0.5:
		_cam_armed = false
		# 한 번 움직인 걸 보고 조금 뒤에 넘긴다(둘러볼 시간)
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if running and str(UI.to_dict(_steps[step]).get("wait", "")) == "camera":
				_advance())


func on_cmd(cmd_name: String, args: Dictionary, r: Dictionary) -> void:
	if not running or step < 0 or not bool(r.get("ok", false)):
		return
	var s := UI.to_dict(_steps[step])
	match str(s.get("wait", "")):
		"build_cat":
			if cmd_name == "build" and ui != null and ui.build.cat_of(str(args.get("type", ""))) in UI.to_array(s.get("cats", [])):
				_advance()
		"houses_ge":
			if cmd_name == "zone" and _satisfied(s):
				_advance()


func on_signal(sig: String) -> void:
	if not running or step < 0:
		return
	var s := UI.to_dict(_steps[step])
	if str(s.get("wait", "")) == "signal" and str(s.get("signal", "")) == sig:
		_advance()


func on_event(_n: String, _p: Dictionary) -> void:
	pass
