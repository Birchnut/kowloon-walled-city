class_name Sim
extends RefCounted
## Sim — 시스템들을 순서대로 돌리고 명령을 적용한다. 노드 의존 없음.
## v0.2 스캐폴드: 시계만 돈다. 규칙은 SIM 담당이 sim/systems/* 로 채운다.
## 계약은 docs/ARCHITECTURE.md.

var db: Dictionary = {}     # Data.files (파일명 → JSON 루트). 헤드리스에서는 직접 읽어 주입.


func setup(data_files: Dictionary) -> void:
	db = data_files


func cfg(path: String, default: Variant = null) -> Variant:
	var cur: Variant = db.get("config", {})
	for part in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default
	return cur


func new_game(state: CityState, seed_value: int) -> void:
	state.rng_seed = seed_value
	state.rng_state = seed_value
	state.day = 1
	state.hour = float(cfg("time.start_hour", 6))
	state.emit("day_started", {"day": state.day})


## dt_hours 만큼 도시 시간을 진행.
func tick(state: CityState, dt_hours: float) -> void:
	var prev_hour := int(state.hour)
	state.hour += dt_hours
	while state.hour >= 24.0:
		state.hour -= 24.0
		state.emit("day_ended", {"day": state.day})
		state.day += 1
		state.emit("day_started", {"day": state.day})
		prev_hour = -1
	if int(state.hour) != prev_hour:
		state.emit("hour", {"hour": int(state.hour)})


## 미접속 시간 처리. 반환: {hours, lines[]} (UI의 "자리를 비운 사이" 요약).
func fast_forward(state: CityState, hours: float) -> Dictionary:
	tick(state, hours)
	return {"hours": hours, "lines": []}


func can(_state: CityState, _name: String, _args: Dictionary) -> Dictionary:
	return {"ok": false, "reason": "아직 구현되지 않음"}


func apply(_state: CityState, _name: String, _args: Dictionary) -> Dictionary:
	return {"ok": false, "reason": "아직 구현되지 않음"}


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name == "hud":
		return {
			"day": state.day, "hour": state.hour, "money": state.money, "food": state.food,
			"materials": state.materials, "population": state.population(),
			"prestige": state.prestige, "notoriety": state.notoriety, "morale": state.morale,
			"title": state.identity.get("title", "대장"), "epithet": state.identity.get("epithet", ""),
			"power_level": state.power_level, "cards": state.pending_cards.size(),
		}
	return null
