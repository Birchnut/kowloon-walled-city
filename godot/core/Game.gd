extends Node
## Game — UI와 View가 보는 유일한 진입점 (오토로드).
## 상태 변경은 cmd(), 표시용 정보는 query(), 검증은 can(). 계약은 docs/ARCHITECTURE.md.

signal event(name: String, payload: Dictionary)
signal state_replaced

const SAVE_PATH := "user://save.json"

var state: CityState
var sim: Sim
var view: Node = null            # CityView가 register_view()로 등록
var paused: bool = false
var speed: float = 1.0           # 배속(디버그·감상)
var autosave: bool = true        # 테스트/샌드박스에서는 끈다
var _offline_summary: Variant = null


func _ready() -> void:
	sim = Sim.new()
	sim.setup(Data.files)
	Data.reloaded.connect(func() -> void: sim.setup(Data.files))
	state = CityState.new()
	# 개발용: 사용자 인자 `nosave` 또는 환경변수 KOWLOON_NOSAVE=1 이면 저장/불러오기를 끈다.
	# (샌드박스·스크린샷·테스트가 서로의 세이브를 밟지 않게)
	if "nosave" in OS.get_cmdline_user_args() or OS.get_environment("KOWLOON_NOSAVE") == "1":
		autosave = false
		new_game()
	elif not load_game():
		new_game()


func _process(delta: float) -> void:
	if paused or state == null:
		return
	var spd: float = float(Data.cfg("time.seconds_per_game_day", 600.0))
	sim.tick(state, delta * speed * 24.0 / maxf(spd, 1.0))
	_drain()


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F5:
		Data.load_all()
		event.emit("log", {"text": "데이터 다시 읽음", "tone": "debug"})
		state_replaced.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if autosave and state != null:
			save_game()


# ------------------------------------------------------------------ 공개 API
func new_game(seed_value: int = -1) -> void:
	state = CityState.new()
	if seed_value < 0:
		seed_value = int(Data.cfg("seed", 0))
		if seed_value == 0:
			seed_value = int(Time.get_unix_time_from_system()) & 0x7fffffff
	sim.new_game(state, seed_value)
	_offline_summary = null
	state.events.clear()
	state_replaced.emit()


## 외부(샌드박스·도구)에서 만든 상태를 통째로 끼운다.
func replace_state(s: CityState) -> void:
	state = s
	state.events.clear()
	state_replaced.emit()


func cmd(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	var r: Dictionary = sim.apply(state, cmd_name, args)
	_drain()
	return r


func can(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	return sim.can(state, cmd_name, args)


func query(q_name: String, args: Dictionary = {}) -> Variant:
	if q_name == "offline_summary":
		var s: Variant = _offline_summary
		_offline_summary = null
		return s
	return sim.query(state, q_name, args)


func time_of_day() -> float:
	return fposmod(state.hour, 24.0) / 24.0


func register_view(v: Node) -> void:
	view = v


# ------------------------------------------------------------------ 저장
func save_game() -> bool:
	state.last_saved_unix = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	# to_json(): 키 순서를 그대로 두고(결정론), float를 왕복값으로 맞춘 뒤 쓴다 → 불러와 이어하면 저장 안 한 것과 똑같이 흘러간다.
	f.store_string(state.to_json())
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var s := CityState.new()
	if not s.from_json(FileAccess.get_file_as_string(SAVE_PATH)):
		return false
	state = s
	# 미접속 시간 → 도시 시간. 실제 1시간 = 도시 offline_game_hours_per_real_hour 시간, 최대 실제 offline_max_real_hours 시간분.
	var now := int(Time.get_unix_time_from_system())
	var hours := offline_game_hours(float(now - state.last_saved_unix))
	if state.last_saved_unix > 0 and hours >= 0.5:
		_offline_summary = sim.fast_forward(state, hours)
	state.events.clear()
	state_replaced.emit()
	return true


## 미접속 실제 초 → 흘려보낼 도시 시간(시간 단위).
func offline_game_hours(elapsed_real_seconds: float) -> float:
	var real_hours: float = clampf(elapsed_real_seconds / 3600.0, 0.0, float(Data.cfg("time.offline_max_real_hours", 24.0)))
	return real_hours * float(Data.cfg("time.offline_game_hours_per_real_hour", 3.0))


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ------------------------------------------------------------------ 내부
func _drain() -> void:
	if state.events.is_empty():
		return
	var evs: Array = state.events
	state.events = []
	for e in evs:
		var n: String = e.get("name", "")
		if n == "day_ended" and autosave:
			save_game()
		event.emit(n, e.get("payload", {}))
