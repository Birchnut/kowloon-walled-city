class_name Settings
extends RefCounted
## 설정(UI 쪽): 창/전체 화면(F11), UI 크기 100/125/150%, 시작 배속, 빠른 저장. user://ui_settings.cfg(UISettings).
## UI 크기: 창 높이가 1080보다 작아도 글자가 0.8배 밑으로 줄지 않게 자동 보정한 뒤 고른 배율을 곱한다.
##   실효 배율 = UI 크기 × max(창 배율, 0.8)  (1280×720 → 논리 1600×900)

const SCALES := [1.0, 1.25, 1.5]
static var _hooked := false


static func ui_scale() -> float:
	return float(UISettings.get_value("ui_scale", 1.0))


static func set_ui_scale(s: float) -> void:
	UISettings.set_value("ui_scale", s)
	apply_scale()


static func apply_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var win := tree.root
	var base := Vector2(1920, 1080)
	var ws := Vector2(win.size)
	if ws.x <= 0 or ws.y <= 0:
		return
	var stretch := minf(ws.x / base.x, ws.y / base.y)
	var csf := ui_scale() * maxf(1.0, 0.8 / maxf(stretch, 0.01))
	if absf(win.content_scale_factor - csf) > 0.001:
		win.content_scale_factor = csf


static func apply_all(_ui: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not _hooked:
		_hooked = true
		tree.root.size_changed.connect(apply_scale)
	apply_scale()
	var spd := float(UISettings.get_value("start_speed", 1.0))
	if spd > 0.0 and not Game.paused:
		Game.speed = spd


static func toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


static func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func quick_save(ui: Node) -> void:
	if not Game.autosave:
		ui.toast("개발 실행(nosave)이라 저장하지 않는다.", "dim", "save")
		return
	if Game.save_game():
		ui.toast("저장했다.", "good", "save")
	else:
		ui.toast("저장하지 못했다.", "bad", "save")
