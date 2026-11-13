extends SimSystem
## vice — 음성 산업과 단속 위험(GDD §11, 확정: 직설 풍자 유지. 플레이어 권한을 빼앗지 않는다).
##  단속 위험 state.heat(0~100): 가동 중인 음성 시설마다 buildings.json vice.heat × 가동률 × sim.mod("heat.gain")/경제일로 오르고,
##  config heat.decay_per_day로 식는다. 50에서 알림(alerts), 80에서 단속:
##   음성 시설 하나(기여만큼의 확률, 결정론 RNG)를 close_days(2경제일) 닫는다 — b.raided = true, b.raid_until, production의 cause "raid".
##   벌금 = max(fine_min, 그 시설 음성 수입 × fine_days_income) — 금고를 넘지 않는다(장부 'fine'). 그 뒤 위험 −after_raid_drop.
##   이벤트 raid{bid, type, until, fine}, 마른 한 줄 기록(vice.raid_line). 기간이 끝나면 다시 연다(raid_end{bid}).
##  닫힌 동안에도 플레이어는 그 시설을 멈추거나 허물 수 있다. 뒷돈 정책(heat.gain −70%, 음성 시설당 유지비)은 policies.
## 끄면: 위험이 오르지 않고 단속도 없다.


func _c(k: String, d: float) -> float:
	return float(sim.cfg("heat." + k, d))


func tick(state: CityState, dt: float) -> void:
	var cov := sim.cover(state)
	var gain := 0.0
	var contrib: Array = []
	for bid: int in cov.get("vice", []):
		var b: Dictionary = state.buildings.get(bid, {})
		if b.get("kind", "") != "facility":
			continue
		if b.get("raided", false):
			if state.econ_days + 1e-9 >= float(b.get("raid_until", 0.0)):
				b["raided"] = false
				b.erase("raid_until")
				state.emit("raid_end", {"bid": bid})
				state.emit("building_changed", {"bid": bid})
				sim.say(state, "%s이(가) 다시 문을 열었다." % sim.bdef(str(b["type"])).get("name", ""))
			continue
		var h := float(sim.bdef(str(b["type"])).get("vice", {}).get("heat", 0.0)) * float(b.get("eff", 0.0))
		if h > 0.0:
			gain += h
			contrib.append([b, h])
	gain *= maxf(0.0, sim.mod(state, "heat.gain"))
	var h0 := state.heat
	state.heat = clampf(state.heat + (gain - _c("decay_per_day", 6.0)) * dt, 0.0, 100.0)
	if h0 < _c("warn", 50.0) and state.heat >= _c("warn", 50.0):
		sim.say(state, "바깥의 시선이 골목에 닿는다. 바깥의 시선 %d." % int(state.heat), "warn")
	if state.heat >= _c("raid", 80.0) and not contrib.is_empty():
		_raid(state, contrib)


func _raid(state: CityState, contrib: Array) -> void:
	var tot := 0.0
	for c: Array in contrib:
		tot += float(c[1])
	var r := sim.roll(state) * tot
	var pick: Dictionary = contrib[contrib.size() - 1][0]
	for c: Array in contrib:
		r -= float(c[1])
		if r < 0.0:
			pick = c[0]
			break
	var d := sim.bdef(str(pick["type"]))
	var until := state.econ_days + _c("close_days", 2.0)
	pick["raided"] = true
	pick["raid_until"] = until
	var fine := maxf(_c("fine_min", 100.0), float(d.get("vice", {}).get("income", 0.0)) * _c("fine_days_income", 2.0))
	fine = minf(fine, state.money)
	state.money -= fine
	state.book("fine", -fine)
	state.stat_add("raids", 1.0)
	state.stat_add("fines", fine)
	state.heat = maxf(0.0, state.heat - _c("after_raid_drop", 40.0))
	state.emit("raid", {"bid": int(pick["id"]), "type": str(pick["type"]), "until": until, "fine": fine})
	state.emit("building_changed", {"bid": int(pick["id"])})
	sim.say(state, "%s 벌금 %s. %d일 뒤 다시 연다." % [str(d.get("vice", {}).get("raid_line", "바깥의 시선이 닿았다.")), Sim.won(fine), int(roundf(_c("close_days", 2.0)))], "bad")



func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "vice":
		return null
	var items: Array = []
	var gain := 0.0
	for bid: int in sim.cover(state).get("vice", []):
		var b: Dictionary = state.buildings.get(bid, {})
		var d := sim.bdef(str(b.get("type", "")))
		var h := float(d.get("vice", {}).get("heat", 0.0)) * float(b.get("eff", 0.0)) * maxf(0.0, sim.mod(state, "heat.gain"))
		if not b.get("raided", false):
			gain += h
		items.append({"bid": bid, "name": d.get("name", ""), "heat_per_day": snappedf(h, 0.1), "income": float(b.get("vice_rate", 0.0)),
			"raided": bool(b.get("raided", false)), "reopens_in_days": snappedf(maxf(0.0, float(b.get("raid_until", 0.0)) - state.econ_days), 0.01) if b.get("raided", false) else 0.0})
	return {"heat": snappedf(state.heat, 0.1), "warn": _c("warn", 50.0), "raid": _c("raid", 80.0), "gain_per_day": snappedf(gain, 0.1),
		"decay_per_day": _c("decay_per_day", 6.0), "items": items}
