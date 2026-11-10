class_name Metrics
extends RefCounted
## Metrics — 상태에서 이름 붙은 숫자를 뽑는다(해금 조건식·봇·리포트 공용). 규칙 없음, 읽기만.
## 이름: day, money, pop, pop.t1..t5(대기 주민 포함), houses.t1..t5, full.t1..t5, count.<시설 id>(완공),
##       sites, stock.<상품>, floors, happiness, power.supply, water.supply, contracts, research.done, policies.on, heat,
##       stat.<state.stats 키>(예: stat.exp_sent, stat.exp_claims, stat.exp_claims_mid/far)


static func compute(sim: Sim, state: CityState) -> Dictionary:
	var m := {"day": float(state.day), "econ_days": state.econ_days, "money": state.money,
		"floors": float(state.floors_unlocked), "happiness": state.happiness, "sites": 0.0, "pop": 0.0}
	var nt := sim.max_tier()
	var pop := PackedFloat64Array()
	pop.resize(nt + 1)
	pop.fill(0.0)
	var hs := pop.duplicate()
	var full := pop.duplicate()
	var cov := sim.cover(state)
	for b: Dictionary in cov["houses"]:
		var t: int = b["tier"]
		var r: int = b["residents"]
		if t < 0 or t > nt:
			continue
		pop[t] += float(r)
		hs[t] += 1.0
		if r >= int(b["cap"]):
			full[t] += 1.0
	var total := 0.0
	for t: int in range(1, nt + 1):
		m["pop.t%d" % t] = pop[t]
		m["houses.t%d" % t] = hs[t]
		m["full.t%d" % t] = full[t]
		total += pop[t]
	m["pop"] = total
	for b: Dictionary in cov["facs"]:
		var k := "count." + str(b["type"])
		m[k] = float(m.get(k, 0.0)) + 1.0
	m["sites"] = float((cov["sites"] as Array).size())
	for t: Variant in state.waiting:
		var n := float(state.waiting[t].get("count", 0))
		m["pop.t%d" % int(t)] = float(m.get("pop.t%d" % int(t), 0.0)) + n
		m["pop"] += n
	for g: String in state.stock:
		m["stock." + g] = float(state.stock[g])
	for u: String in ["water", "power"]:
		m[u + ".supply"] = float(state.util.get(u, {}).get("supply", 0.0))
	m["contracts"] = float(state.contracts.size())
	m["research.done"] = float(state.research.get("done", {}).size())
	var pol := 0.0
	for p: String in state.policies:
		if state.policies[p]:
			pol += 1.0
	m["policies.on"] = pol
	m["heat"] = state.heat
	for k: String in state.stats:
		var v: Variant = state.stats[k]
		if v is float or v is int:
			m["stat." + k] = float(v)
	return m
