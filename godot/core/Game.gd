extends Node
## Game — UI와 View가 보는 유일한 진입점 (오토로드).
## 상태 변경은 cmd(), 표시용 정보는 query(), 검증은 can(). 계약은 docs/ARCHITECTURE.md(v4 절).
## v4(PC): 모든 시간은 게임 시계. 실제 시계는 쓰지 않는다 — 불러올 때·긴 공백 뒤에도 정산하지 않는다(offline_summary는 늘 null).
## 경제 dt = delta × speed / seconds_per_day. speed ∈ {1, 2, 4}(디버그 16), paused면 시계가 멈춘다(명령은 된다).

signal event(name: String, payload: Dictionary)
signal state_replaced

const SAVE_PATH := "user://save_v4.json"   # 옛 save_v3.json(모바일판)은 읽지도 지우지도 않는다
const SPEEDS := [1.0, 2.0, 4.0]

var state: CityState
var sim: Sim
var view: Node = null
## UI가 Game.speed = 2 / Game.paused = true로 바로 써도 speed_changed가 나간다(세터).
var paused: bool = false:
	set(v):
		if v != paused:
			paused = v
			event.emit("speed_changed", {"speed": speed, "paused": paused})
var speed: float = 1.0:
	set(v):
		if v != speed:
			speed = v
			event.emit("speed_changed", {"speed": speed, "paused": paused})
var autosave: bool = true
# 자동 저장: 명령 뒤 SAVE_AFTER_CMD초 조용하면 한 번, 아무 일 없어도 SAVE_EVERY초마다, 창이 뒤로 갈 때, 자정마다.
const SAVE_AFTER_CMD := 2.0
const SAVE_EVERY := 60.0
var _dirty_t: float = -1.0      # 마지막 명령 뒤 지난 실제 초(-1 = 저장할 변화 없음)
var _since_save: float = 0.0
# 한 프레임에 너무 큰 dt(창을 끌던 동안 멈춘 프레임 등)가 들어와도 게임 시간은 이만큼만(×1 기준 실제 초) — 정산이 아니라 끊김 방지.
const MAX_FRAME_S := 0.25


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


func _process(delta: float) -> void:
	if state == null:
		return
	_autosave_tick(delta)
	if paused:
		return
	var spd: float = float(Data.cfg("time.seconds_per_day", 600.0))
	sim.tick(state, minf(delta, MAX_FRAME_S) * speed / maxf(spd, 1.0))
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
		seed_value = int(Time.get_unix_time_from_system()) & 0x7fffffff   # 씨앗만 실제 시계에서(규칙은 아님)
	sim.new_game(state, seed_value)
	state.events.clear()
	if autosave:
		_dirty_t = 0.0          # 새 도시도 곧 저장
	state_replaced.emit()


func replace_state(s: CityState) -> void:
	state = s
	state.events.clear()
	state_replaced.emit()


## 배속: 1·2·4(디버그 set_speed는 아무 값). 바뀌면 speed_changed{speed, paused}.
func set_speed(v: float) -> void:
	speed = v


func set_paused(on: bool) -> void:
	paused = on


func toggle_pause() -> void:
	set_paused(not paused)


func cmd(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	if cmd_name == "debug" and str(args.get("op", "")) == "set_speed":
		set_speed(float(args.get("speed", 1.0)))
		return {"ok": true, "reason": ""}
	if cmd_name == "debug" and str(args.get("op", "")) == "set_paused":
		set_paused(bool(args.get("on", true)))
		return {"ok": true, "reason": ""}
	var r: Dictionary = sim.apply(state, cmd_name, args)   # 멈춘 상태에서도 된다
	if autosave and bool(r.get("ok", false)):
		_dirty_t = 0.0          # 조용해지면 저장(_autosave_tick)
	_drain()
	return r


func can(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	return sim.can(state, cmd_name, args)


func query(q_name: String, args: Dictionary = {}) -> Variant:
	if q_name == "offline_summary":
		return null
	var r: Variant = sim.query(state, q_name, args)
	if q_name == "hud" and r is Dictionary:
		r["speed"] = int(speed) if speed == floorf(speed) else speed
		r["paused"] = paused
	return r


func time_of_day() -> float:
	return fposmod(state.hour, 24.0) / 24.0


func register_view(v: Node) -> void:
	view = v


# ------------------------------------------------------------------ 저장
func save_game() -> bool:
	_dirty_t = -1.0
	_since_save = 0.0
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
		push_warning("[Game] save_v4.json을 읽을 수 없거나 버전이 다르다 — 새 게임.")
		return false
	state = s
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
	for e: Dictionary in evs:
		var n: String = e.get("name", "")
		if n == "day_ended" and autosave:
			save_game()
		event.emit(n, e.get("payload", {}))
