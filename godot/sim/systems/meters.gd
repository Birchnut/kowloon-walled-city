extends SimSystem
## 지표 — 위신·악명·민심. 서로 다른 축이다(위신도 악명도 높은 라스베이거스가 가능해야 한다).
## 각 지표는 "목표값"을 향해 하루에 rate만큼 따라간다. 목표값 = base + Σ(지표 이름 × 가중치[, 상한]) — data/meters.json.
##  · 위신: 공공 시설, 비워 둔 터, 돌봄, 녹화, 볕 ↑ / 제조 밀도, 쪽방, 대문 앞 줄 ↓
##  · 악명: 음성 가게, 뒷골목 금고 ↑ / 자경단 초소 ↓ (수금원이 떼먹을 때·깨끗이 거둘 때의 즉시 변화는 collection이 직접 준다)
##  · 민심: 먹을 것, 집의 질, 볕, 돌봄, 사당·부엌·회관 ↑ / 소음 이웃, 실업, 대문 앞 줄, 높은 세금, 쪽방, 물 부족 ↓
## 다른 시스템이 준 즉시 변화(카드·추방 등)는 그대로 남고, 시간이 지나며 목표값 쪽으로 다시 끌려간다.


func on_new_game(state: CityState) -> void:
	for id: String in _defs():
		if _defs()[id].has("start"):
			state.set(id, float(_defs()[id]["start"]))


func _defs() -> Dictionary:
	return sim.items("meters")


func _target(state: CityState, d: Dictionary) -> float:
	return clampf(Expr.linear(d.get("terms", []), sim.metrics(state), float(d.get("base", 0.0))),
		float(d.get("min", 0.0)), float(d.get("max", 100.0)))


func on_hour(state: CityState, _hour: int) -> void:
	for id: String in _defs():
		var d: Dictionary = _defs()[id]
		var v := float(state.get(id))
		state.set(id, clampf(v + (_target(state, d) - v) * float(d.get("rate", 0.3)) / 24.0, 0.0, 100.0))


func metrics(state: CityState, m: Dictionary) -> void:
	for id: String in _defs():
		m["target." + id] = clampf(Expr.linear(_defs()[id].get("terms", []), m, float(_defs()[id].get("base", 0.0))), 0.0, 100.0)


func fast_forward(state: CityState, _hours: float, before: Dictionary, lines: Array) -> void:
	for pair: Array in [["notoriety", "악명"], ["prestige", "위신"], ["morale", "민심"]]:
		var diff := float(state.get(pair[0])) - float(before.get(pair[0], 0.0))
		if absf(diff) >= 3.0:
			lines.append("%s이 %d만큼 %s." % [pair[1], int(absf(diff)), "올랐다" if diff > 0.0 else "내렸다"])
