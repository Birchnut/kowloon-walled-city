extends SimSystem
## production — 시설의 가동 판정과 생산.
##  기준 x = min(인력, 물 비율, 전기 비율) — 해당 유틸리티를 쓰는 시설만. 같은 부족을 두 번 곱하지 않는다.
##  생산 시설: 효율 eff = min(x, 원료가 허락하는 비율, 저장 공간이 허락하는 비율). 입력 소비·출력 생산 = 기본량 × eff × dt.
##  시장·서비스: x ≥ 0.6이면 켜지고 0.5 밑으로 내려가야 꺼진다(깜빡임 방지, config workforce.service_on/off). 켜지면 eff 1.
##  공급 시설(물·전기): eff = x(공급량은 utilities가 같은 식으로 계산).
##  음성 시설: vice.income × x → b.vice_rate(₩/경제일, finance가 장부 'vice'로 넣는다). [단속·위험은 B 파트]
##  cause: "" | staff | input | water | power | money | storage | paused | raid(단속) | sky(위가 막힘) | fire | burnt | repair
## 끄면: 아무것도 생산하지 않는다(시장·서비스도 꺼진다).

## 원인 문장은 Queries.CAUSE_TEXT.


func tick(state: CityState, dt: float) -> void:
	var cov := sim.cover(state)
	var on_th := float(sim.cfg("workforce.service_on", 0.6))
	var off_th := float(sim.cfg("workforce.service_off", 0.5))
	for bid: int in cov["by_prio"]:
		if not state.buildings.has(bid):
			continue
		var b: Dictionary = state.buildings[bid]
		var d := sim.bdef(str(b["type"]))
		var was := bool(b.get("active", false))
		var old_cause := str(b.get("cause", ""))
		var staff := sim.staff_of(b)
		var fac := {"staff": staff}
		if float(d.get("water", 0.0)) > 0.0:
			fac["water"] = float(b.get("w_ratio", 1.0))
		if float(d.get("power", 0.0)) > 0.0:
			fac["power"] = float(b.get("p_ratio", 1.0))
		var x := 1.0
		var cause := ""
		for k: String in fac:
			if float(fac[k]) < x - 1e-9:
				x = float(fac[k])
				cause = k
		if x >= 1.0 - 1e-9:
			cause = ""
		var eff := x
		b["vice_rate"] = 0.0
		var off := Sim.off_reason(b)
		if off != "":
			eff = 0.0
			cause = off
		elif d.has("market") or d.has("services"):
			var on := x >= (off_th if was else on_th) - 1e-9
			eff = 1.0 if on else 0.0
			if on:
				cause = ""
		elif d.has("recipe"):
			eff = _produce(state, b, d, x, dt)
			if eff < x - 1e-9:
				cause = str(b.get("_lim", "input"))
			if eff >= 1.0 - 1e-9:
				cause = ""
		if d.has("vice") and eff > 0.0 and not d.has("recipe"):
			b["vice_rate"] = float(d["vice"].get("income", 0.0)) * eff
		b.erase("_lim")
		b["eff"] = eff
		b["active"] = eff > 1e-6
		b["cause"] = cause
		if bool(b["active"]) != was or cause != old_cause:
			state.emit("building_changed", {"bid": bid})


## 생산식 한 스텝. 반환 = 실제 효율.
func _produce(state: CityState, b: Dictionary, d: Dictionary, x: float, dt: float) -> float:
	var rec: Dictionary = d["recipe"]
	dt *= sim.mod(state, "prod.all")    # 연구·정책: 처리량(원료와 산출을 함께) 배수
	var sm := sim.store_mult(state, b)  # v0.5: 창고가 덮지 않는 층이면 조금 느리다
	b["wh_slow"] = sm < 1.0
	dt *= sm
	var eff := x
	if eff <= 0.0:
		return 0.0
	for g: String in rec.get("in", {}):
		var full := float(rec["in"][g]) * dt
		if full <= 0.0:
			continue
		var r := float(state.stock.get(g, 0.0)) / full
		if r < eff:
			eff = maxf(0.0, r)
			b["_lim"] = "input"
	for g: String in rec.get("out", {}):
		var full := float(rec["out"][g]) * dt
		if full <= 0.0:
			continue
		var room := sim.cap_of(state, g) - float(state.stock.get(g, 0.0))
		var r := maxf(0.0, room) / full
		if r < eff:
			eff = r
			b["_lim"] = "storage"
	if eff <= 1e-9:
		return 0.0
	for g: String in rec.get("in", {}):
		var amt := float(rec["in"][g]) * dt * eff
		state.stock[g] = maxf(0.0, float(state.stock.get(g, 0.0)) - amt)
		sim.flow_add(g, "cons", amt)
	for g: String in rec.get("out", {}):
		var amt := float(rec["out"][g]) * dt * eff
		state.stock[g] = float(state.stock.get(g, 0.0)) + amt
		sim.flow_add(g, "prod", amt)
		state.stat_add("prod." + g, amt)
	return eff
