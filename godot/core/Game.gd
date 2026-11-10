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
# 자동 저장: 명령 뒤 SAVE_AFTER_CMD초 조용하면 한 번, 아무 일 없어도 SAVE_EVERY초마다, 창이 뒤로 갈 때.
# (웹·폰에서는 탭을 닫을 때 알림이 오지 않는다 — 자정 저장만으로는 방금 보낸 탐험이 사라진다.)
const SAVE_AFTER_CMD := 2.0
const SAVE_EVERY := 60.0
var _dirty_t: float = -1.0      # 마지막 명령 뒤 지난 실제 초(-1 = 저장할 변화 없음)
var _since_save: float = 0.0


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


var _last_frame_unix: int = 0


func _process(delta: float) -> void:
	if state == null:
		return
	_autosave_tick(delta)
	sim.now_unix = _now()
	# 앱이 백그라운드에 있다 돌아오면(프레임 사이 실제 공백이 길면) 접속 중 속도가 아니라 미접속 규칙으로 정산한다.
	var gap := sim.now_unix - _last_frame_unix
	_last_frame_unix = sim.now_unix
	if gap > int(Data.cfg("time.offline_min_gap_seconds", 60)) and state.last_saved_unix > 0:
		state.last_saved_unix = sim.now_unix - gap
		_offline_catch_up()
		_drain()
		return
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
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if autosave and state != null:
			save_game()


func _autosave_tick(delta: float) -> void:
	if not autosave:
		return
	_since_save += delta
	if _dirty_t >= 0.0:
		_dirty_t += delta
	if _dirty_t >= SAVE_AFTER_CMD or _since_save >= SAVE_EVERY:
		save_game()


# ------------------------------------------------------------------ 공개 API
func new_game(seed_value: int = -1) -> void:
	state = CityState.new()
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) & 0x7fffffff
	sim.now_unix = int(Time.get_unix_time_from_system())
	_last_frame_unix = sim.now_unix
	sim.new_game(state, seed_value)
	state.last_saved_unix = sim.now_unix
	_offline_summary = null
	state.events.clear()
	if autosave:
		_dirty_t = 0.0          # 새 도시도 곧 저장
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
	_last_frame_unix = _now()   # 디버그 skip_real 같은 시계 이동을 "앱이 멈췄다 돌아옴"으로 오해하지 않게
	if autosave and bool(r.get("ok", false)):
		_dirty_t = 0.0          # 조용해지면 저장(_autosave_tick)
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
	_dirty_t = -1.0
	_since_save = 0.0
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
	_last_frame_unix = sim.now_unix
	_offline_catch_up()
	state.events.clear()
	state_replaced.emit()
	return true


## ── 미접속 따라잡기(파트 B) ─────────────────────────────────────────────
## 규칙은 Sim.catch_up(느리게 + 보호, 시계 방어, 요약). 불러올 때 + 앱이 오래 멈췄다 돌아올 때(_process의 큰 공백) 부른다.
## 결과는 _offline_summary {real_hours, econ_days, lines[]} — query("offline_summary")가 한 번 돌려주고 비운다(없으면 null).
func _offline_catch_up() -> void:
	var r: Variant = sim.catch_up(state, _now())
	if r != null:
		_offline_summary = r


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
