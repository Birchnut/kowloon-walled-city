extends Node
## GameClock (autoload `Clock`) — 도시 자체 시계.
## - 정규 시간축: total_hours (float, 게임 시작 이후 누적 게임 시간)
## - 하루 길이(실시간 초)는 config.time.seconds_per_game_day
## - 시그널: hour_changed(hour), day_ended(day), ticked(dt_game_hours)
## - time_of_day: 0..1 (0=00시, 0.5=12시). 감상 모드 오버라이드 지원(시뮬레이션은 계속 흐름)
## - 오프라인 보상: compute_catchup(elapsed_real_sec) → 요약 Dictionary, apply_catchup()으로 적용

signal hour_changed(hour: int)
signal day_ended(day: int)
signal ticked(dt_game_hours: float)

var total_hours: float = 0.0        # 누적 게임 시간(시). 저장 대상.
var paused: bool = false
var time_scale: float = 1.0         # 디버그 배속
var hours_per_day: int = 24
var seconds_per_game_day: float = 600.0

## 감상 모드: -1 이면 비활성, 0..1 이면 time_of_day를 이 값으로 고정(렌더만)
var view_override: float = -1.0

var _last_hour: int = -1
var _last_day: int = -1

## 오프라인 보상 마지막 요약 (UI가 읽음). 키: elapsed_real_seconds, simulated_hours, simulated_days, capped, day_before, day_after
var last_catchup: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_config()
	EventBus.data_reloaded.connect(_apply_config)
	if total_hours == 0.0:
		total_hours = float(Data.cfg("time/start_hour", 6))
	_last_hour = hour
	_last_day = day


func _apply_config() -> void:
	hours_per_day = int(Data.cfg("time/hours_per_day", 24))
	seconds_per_game_day = float(Data.cfg("time/seconds_per_game_day", 600.0))


func _process(delta: float) -> void:
	if paused or seconds_per_game_day <= 0.0:
		return
	var dt_hours := delta * time_scale * hours_per_day / seconds_per_game_day
	advance(dt_hours)


## 게임 시간을 dt_hours 만큼 전진. 시/일 경계마다 시그널 발행. 오프라인 보상도 이 함수로 처리.
func advance(dt_hours: float) -> void:
	if dt_hours <= 0.0:
		return
	# 큰 점프는 1시간 단위로 쪼개서 시뮬레이션 일관성 유지
	var remaining := dt_hours
	while remaining > 0.0:
		var step: float = min(remaining, 1.0)
		total_hours += step
		remaining -= step
		ticked.emit(step)
		_check_boundaries()


func _check_boundaries() -> void:
	var h := hour
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
		EventBus.hour_changed.emit(h)
	var d := day
	if d != _last_day:
		var ended := _last_day
		_last_day = d
		if ended >= 0:
			day_ended.emit(ended)
			EventBus.day_ended.emit(ended)


# --- 읽기 전용 속성 ---
var day: int:
	get: return int(floor(total_hours / hours_per_day))

var hour: int:
	get: return int(floor(fmod(total_hours, float(hours_per_day))))

var minute: int:
	get: return int(floor(fmod(total_hours * 60.0, 60.0)))

## 0..1. 감상 모드면 override 값.
var time_of_day: float:
	get:
		if view_override >= 0.0:
			return clampf(view_override, 0.0, 1.0)
		return fmod(total_hours, float(hours_per_day)) / float(hours_per_day)

var sim_time_of_day: float:
	get: return fmod(total_hours, float(hours_per_day)) / float(hours_per_day)


func clock_text() -> String:
	return "%d일차 %02d:%02d" % [day + 1, hour, minute]


# --- 감상 모드 / 디버그 스크럽 ---
func set_view_override(t: float) -> void:
	view_override = clampf(t, 0.0, 1.0)
	EventBus.time_scrubbed.emit(time_of_day)

func clear_view_override() -> void:
	view_override = -1.0
	EventBus.time_scrubbed.emit(time_of_day)

## 디버그: 시뮬레이션 시각을 직접 이동 (hours 양수만; 과거로는 못 감 — 시뮬 비가역)
func debug_skip_hours(hours: float) -> void:
	advance(hours)

func debug_skip_to_next_day() -> void:
	var to_go := float(hours_per_day) - fmod(total_hours, float(hours_per_day))
	advance(to_go + 0.001)


# --- 오프라인 보상 ---
## 실제 경과 초 → 시뮬레이션할 게임 시간 계산. 적용은 하지 않음.
func compute_catchup(elapsed_real_seconds: float) -> Dictionary:
	var max_days := int(Data.cfg("time/offline_catchup_max_days", 3))
	var raw_hours := 0.0
	if seconds_per_game_day > 0.0:
		raw_hours = elapsed_real_seconds / seconds_per_game_day * hours_per_day
	var cap_hours := float(max_days * hours_per_day)
	var sim_hours := minf(raw_hours, cap_hours)
	return {
		"elapsed_real_seconds": elapsed_real_seconds,
		"raw_hours": raw_hours,
		"simulated_hours": sim_hours,
		"simulated_days": sim_hours / hours_per_day,
		"capped": raw_hours > cap_hours,
		"day_before": day,
		"day_after": int(floor((total_hours + sim_hours) / hours_per_day)),
	}

## compute_catchup 결과를 실제로 적용(advance). 요약은 last_catchup에 보관.
func apply_catchup(summary: Dictionary) -> void:
	last_catchup = summary
	advance(float(summary.get("simulated_hours", 0.0)))


# --- 저장/복원 ---
func to_save() -> Dictionary:
	return { "total_hours": total_hours }

func from_save(d: Dictionary) -> void:
	total_hours = float(d.get("total_hours", float(Data.cfg("time/start_hour", 6))))
	_last_hour = hour
	_last_day = day

func reset() -> void:
	total_hours = float(Data.cfg("time/start_hour", 6))
	_last_hour = hour
	_last_day = day
	last_catchup = {}
	view_override = -1.0
