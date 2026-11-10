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
	f.store_string(JSON.stringify(state.to_dict()))
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SAVE_PATH)) != OK or not (json.data is Dictionary):
		return false
	var s := CityState.new()
	s.from_dict(json.data)
	state = s
	# 미접속 시간 → 도시 시간
	var now := int(Time.get_unix_time_from_system())
	var elapsed: float = maxf(0.0, float(now - state.last_saved_unix))
	var spd: float = float(Data.cfg("time.seconds_per_game_day", 600.0))
	var max_days: float = float(Data.cfg("time.offline_max_days", 3.0))
	var hours: float = minf(elapsed * 24.0 / maxf(spd, 1.0), max_days * 24.0)
	if state.last_saved_unix > 0 and hours >= 0.5:
		_offline_summary = sim.fast_forward(state, hours)
	state.events.clear()
	state_replaced.emit()
	return true


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
