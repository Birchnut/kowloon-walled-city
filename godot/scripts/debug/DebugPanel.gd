extends CanvasLayer
## DebugPanel — 백틱(`)으로 토글. FPS, 시간 스크럽(감상 모드), 배속, 데이터 리로드, 돈 추가, 하루 넘기기, 징수, 저장/로드.
## 키: ` 토글 / F5 데이터 리로드 / [ ] 시간 스크럽 / N 하루 넘기기

var _root: PanelContainer
var _fps: Label
var _info: Label
var _scrub: HSlider
var _speed: HSlider
var _speed_label: Label
var _override_check: CheckBox


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = bool(Data.cfg("debug/enabled", true)) and false  # 시작 시 숨김


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		_root.visible = not _root.visible
	elif event.is_action_pressed("debug_time_back"):
		_nudge_scrub(-1.0 / 24.0)
	elif event.is_action_pressed("debug_time_forward"):
		_nudge_scrub(1.0 / 24.0)
	elif event.is_action_pressed("debug_skip_day"):
		Clock.debug_skip_to_next_day()


func _process(_d: float) -> void:
	if not _root.visible:
		return
	_fps.text = "FPS %d" % Engine.get_frames_per_second()
	if Save.city:
		var s := Save.city.summary()
		_info.text = "%s | 금고 %d 인구 %d 위신 %d 건물 %d 일터 %d\nsim tod %.3f  view %.3f  ×%.1f" % [
			Clock.clock_text(), s["treasury"], s["population"], s["prestige"], s["cells"], s["workplaces"],
			Clock.sim_time_of_day, Clock.time_of_day, Clock.time_scale]
	if not _scrub.has_focus() and Clock.view_override < 0.0:
		_scrub.set_value_no_signal(Clock.sim_time_of_day)


func _nudge_scrub(delta: float) -> void:
	_override_check.button_pressed = true
	Clock.set_view_override(fposmod(Clock.time_of_day + delta, 1.0))
	_scrub.set_value_no_signal(Clock.time_of_day)


func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.anchor_left = 0.0; _root.anchor_right = 1.0
	_root.anchor_top = 0.0; _root.anchor_bottom = 0.0
	_root.offset_top = 60; _root.offset_left = 8; _root.offset_right = -8
	add_child(_root)
	var v := VBoxContainer.new()
	_root.add_child(v)

	_fps = Label.new(); v.add_child(_fps)
	_info = Label.new(); v.add_child(_info)

	var h1 := HBoxContainer.new(); v.add_child(h1)
	_override_check = CheckBox.new()
	_override_check.text = "감상 모드(시각 고정)"
	_override_check.toggled.connect(func(on):
		if on: Clock.set_view_override(_scrub.value)
		else: Clock.clear_view_override())
	h1.add_child(_override_check)
	_scrub = HSlider.new()
	_scrub.min_value = 0.0; _scrub.max_value = 1.0; _scrub.step = 0.001
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.value_changed.connect(func(val):
		if _override_check.button_pressed: Clock.set_view_override(val))
	h1.add_child(_scrub)

	var h2 := HBoxContainer.new(); v.add_child(h2)
	_speed_label = Label.new(); _speed_label.text = "배속 ×1.0"; h2.add_child(_speed_label)
	_speed = HSlider.new()
	_speed.min_value = 0.0; _speed.max_value = 60.0; _speed.step = 0.5; _speed.value = 1.0
	_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed.value_changed.connect(func(val):
		Clock.time_scale = val
		_speed_label.text = "배속 ×%.1f" % val)
	h2.add_child(_speed)

	var grid := GridContainer.new(); grid.columns = 3; v.add_child(grid)
	_btn(grid, "데이터 리로드 (F5)", func(): Data.reload())
	_btn(grid, "+₩500", func(): Save.city.treasury += 500; Save.city.changed.emit())
	_btn(grid, "하루 넘기기 (N)", func(): Clock.debug_skip_to_next_day())
	_btn(grid, "+1시간", func(): Clock.debug_skip_hours(1.0))
	_btn(grid, "전체 징수", func():
		var got := Save.city.harvest_all()
		print("[Debug] 징수 %d" % got))
	_btn(grid, "일시정지 토글", func(): Clock.paused = not Clock.paused)
	_btn(grid, "저장", func(): Save.save_game(); print("[Debug] 저장됨"))
	_btn(grid, "로드", func(): Save.load_game())  # Main/HUD는 EventBus.game_loaded로 재바인딩
	_btn(grid, "새 게임(세이브 삭제)", func():
		Save.delete_save()
		get_tree().reload_current_scene())
	_btn(grid, "좌표 표시 토글", func():
		Data.config["debug"]["show_grid_coords"] = not Data.cfg("debug/show_grid_coords", false)
		EventBus.data_reloaded.emit())


func _btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
