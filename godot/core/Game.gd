extends Node
## Game — UI와 View가 보는 유일한 진입점 (오토로드).
## 상태 변경은 cmd(), 표시용 정보는 query(), 검증은 can(). 계약은 docs/ARCHITECTURE.md.
## 시계 주입: 매 프레임 sim.now_unix = 시스템 시각 + state.clock_offset, 경제 dt = delta × speed / seconds_per_day.

signal event(name: String, payload: Dictionary)
signal state_replaced

const SAVE_PATH := "user://save_v3.json"   # 옛 save.json(v2)은 읽지도 지우지도 않는다

var state: CityState
var sim: Sim
var view: Node = null
var paused: bool = false
var speed: float = 1.0
var autosave: bool = true
var _offline_summary: Variant = null


func _ready() -> void:
	sim = Sim.new()
	sim.setup(Data.files)
	Data.reloaded.connect(func() -> void: sim.setup(Data.files))
	state = CityState.new()
	if "nosave" in OS.get_cmdline_user_args() or OS.get_environment("KOWLOON_NOSAVE") == "1":
		autosave = false
		new_game()
	elif not load_game():
		new_game()


func _now() -> int:
	return int(Time.get_unix_time_from_system()) + (state.clock_offset if state != null else 0)


func _process(delta: float) -> void:
	if state == null:
		return
	sim.now_unix = _now()
	if paused:
		return
	var spd: float = float(Data.cfg("time.seconds_per_day", 600.0))
	sim.tick(state, delta * speed / maxf(spd, 1.0))
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
		seed_value = int(Time.get_unix_time_from_system()) & 0x7fffffff
	sim.now_unix = int(Time.get_unix_time_from_system())
	sim.new_game(state, seed_value)
	_offline_summary = null
	state.events.clear()
	state_replaced.emit()


func replace_state(s: CityState) -> void:
	state = s
	state.events.clear()
	state_replaced.emit()


func cmd(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	if cmd_name == "debug" and str(args.get("op", "")) == "set_speed":
		speed = float(args.get("speed", 1.0))
		return {"ok": true, "reason": ""}
	sim.now_unix = _now()
	var r: Dictionary = sim.apply(state, cmd_name, args)
	_drain()
	return r


func can(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	return sim.can(state, cmd_name, args)


func query(q_name: String, args: Dictionary = {}) -> Variant:
	if q_name == "offline_summary" and _offline_summary != null:
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
	state.last_saved_unix = _now()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(state.to_json())
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var s := CityState.new()
	if not s.from_json(FileAccess.get_file_as_string(SAVE_PATH)):
		push_warning("[Game] save_v3.json을 읽을 수 없거나 버전이 다르다 — 새 게임.")
		return false
	state = s
	sim.now_unix = _now()
	_offline_catch_up()
	state.events.clear()
	state_replaced.emit()
	return true


## ── [B 파트 이음새] 미접속 따라잡기 ──────────────────────────────────────────
## 지금은 최소 구현: 실제 경과(최대 config time.offline_max_real_hours) × offline_speed → 경제일, sim.fast_forward 한 번.
## B 파트가 할 일: 보호 장치(유예 시계 정지·재고 0이면 그 소비만 정지), 복귀 요약(생산·소비·계약·부족 시점·탐험 완료),
## 음수 시간·과도한 도약 방어. 결과는 _offline_summary {real_hours, econ_days, lines[]}로 둔다(query offline_summary가 한 번 돌려줌).
func _offline_catch_up() -> void:
	if state.last_saved_unix <= 0:
		return
	var real_s := clampf(float(sim.now_unix - state.last_saved_unix), 0.0, float(Data.cfg("time.offline_max_real_hours", 8)) * 3600.0)
	var econ := real_s * float(Data.cfg("time.offline_speed", 0.25)) / maxf(float(Data.cfg("time.seconds_per_day", 600)), 1.0)
	if econ < sim.step_days:
		return
	var r := sim.fast_forward(state, econ)
	_offline_summary = {"real_hours": snappedf(real_s / 3600.0, 0.01), "econ_days": snappedf(econ, 0.01), "lines": r.get("lines", [])}


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ------------------------------------------------------------------ 내부
func _drain() -> void:
	if state.events.is_empty():
		return
	var evs: Array = state.events
	state.events = []
	for e: Dictionary in evs:
		var n: String = e.get("name", "")
		if n == "day_ended" and autosave:
			save_game()
		event.emit(n, e.get("payload", {}))
