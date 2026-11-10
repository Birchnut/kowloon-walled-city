class_name Metrics
extends RefCounted
## Metrics — 상태에서 이름 붙은 숫자를 뽑는다(해금 조건식·봇·리포트 공용). 규칙 없음, 읽기만.
## 이름: day, money, pop, pop.t1..t5(대기 주민 포함), houses.t1..t5, full.t1..t5, count.<시설 id>(완공),
##       sites, stock.<상품>, floors, happiness, power.supply, water.supply


static func compute(sim: Sim, state: CityState) -> Dictionary:
	var m := {"day": float(state.day), "econ_days": state.econ_days, "money": state.money,
		"floors": float(state.floors_unlocked), "happiness": state.happiness, "sites": 0.0, "pop": 0.0}
	for t: int in range(1, sim.max_tier() + 1):
		m["pop.t%d" % t] = 0.0
		m["houses.t%d" % t] = 0.0
		m["full.t%d" % t] = 0.0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house":
			var t := int(b["tier"])
			var r := float(b.get("residents", 0))
			m["pop.t%d" % t] += r
			m["houses.t%d" % t] += 1.0
			if int(b["residents"]) >= int(b["cap"]):
				m["full.t%d" % t] += 1.0
			m["pop"] += r
		elif b["kind"] == "facility":
			var k := "count." + str(b["type"])
			m[k] = float(m.get(k, 0.0)) + 1.0
		elif b["kind"] == "site":
			m["sites"] += 1.0
	for t: Variant in state.waiting:
		var n := float(state.waiting[t].get("count", 0))
		m["pop.t%d" % int(t)] = float(m.get("pop.t%d" % int(t), 0.0)) + n
		m["pop"] += n
	for g: String in state.stock:
		m["stock." + g] = float(state.stock[g])
	for u: String in ["water", "power"]:
		m[u + ".supply"] = float(state.util.get(u, {}).get("supply", 0.0))
	return m
