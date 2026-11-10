extends SimSystem
## 시계 — 도시 시간을 흘린다. 정시마다 `hour`, 자정마다 `day_ended` → `day_started` 이벤트.
## 수치: config.json time.start_hour(새 게임 시작 시각). 하루 길이(초)는 Game이 dt로 환산해 넘긴다.
## 이 시스템을 끄면 시간이 멈춘다(다른 시스템의 시간·일 단위 규칙도 같이 멈춘다).


func tick(state: CityState, dt: float) -> void:
	var h := state.hour + dt
	if absf(h - roundf(h)) < 1e-9:
		h = roundf(h)
	state.hour = h


func on_day_end(state: CityState) -> void:
	state.emit("day_ended", {"day": state.day})


func on_day_start(state: CityState) -> void:
	state.hour = maxf(0.0, state.hour - 24.0)
	state.day += 1
	state.emit("day_started", {"day": state.day})


func on_hour(state: CityState, hour: int) -> void:
	state.emit("hour", {"hour": hour})


func metrics(state: CityState, m: Dictionary) -> void:
	m["night"] = 1.0 if (state.hour < 6.0 or state.hour >= 19.0) else 0.0


func fast_forward(_state: CityState, hours: float, _before: Dictionary, lines: Array) -> void:
	var d := int(hours / 24.0)
	var h := int(hours) % 24
	var span := ("%d일 %d시간" % [d, h]) if d > 0 else ("%d시간" % h)
	lines.push_front("자리를 비운 사이 성채의 시간으로 %s이 흘렀다." % span)
