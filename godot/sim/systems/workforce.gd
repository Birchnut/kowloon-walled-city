extends SimSystem
## workforce — 계층별 도시 노동력 풀과 시설 배분.
##  풀: 떠돌이 = floor((주민 + 대기 주민) × 0.75) — 도시 합계에서 한 번만 내림(건물마다 반올림 안 함). 그 밖 = 주민 + 대기.
##  배분: config workforce.priority 순위대로(물·전기 → 시장·서비스 → 식품 → 생활품 → 그 밖 → 음성), 같은 순위 안에서는 비율로.
##  결과: 시설 b.staff(0..1 = 계층별 배정/필요의 최솟값), state.labor[tier] = {have, need, used}.
##  일시정지·파산 정지 시설은 사람을 받지 않는다. 시장·서비스의 켜짐/꺼짐 이력은 production이 처리한다.
## 끄면: 모든 시설이 인력 100%로 돈다(노동 제약 없음).


func tick(state: CityState, _dt: float) -> void:
	var tiers := sim.max_tier()
	var raw := {}
	for t: int in range(1, tiers + 1):
		raw[t] = 0.0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house":
			raw[int(b["tier"])] += float(b["residents"])
	for t: Variant in state.waiting:
		raw[int(t)] = float(raw.get(int(t), 0.0)) + float(state.waiting[t].get("count", 0))
	var left := {}
	var labor := {}
	for t: int in range(1, tiers + 1):
		var have := int(floorf(raw[t] * float(sim.tier(t).get("labor", 1.0)) + 1e-9))
		left[t] = float(have)
		labor[t] = {"have": have, "need": 0.0, "used": 0.0}
	var cov := sim.cover(state)
	var prio: Array = sim.cfg("workforce.priority", [])
	# 순위별로 묶는다(cover.by_prio는 이미 순위 순서).
	var groups := {}
	var order: Array = []
	for bid: int in cov["by_prio"]:
		if not state.buildings.has(bid):
			continue
		var b: Dictionary = state.buildings[bid]
		var d := sim.bdef(str(b["type"]))
		var p := str(d.get("priority", "other"))
		if not groups.has(p):
			groups[p] = []
			order.append(p)
		groups[p].append(bid)
	for p: String in order:
		var members: Array = groups[p]
		var demand := {}
		for bid: int in members:
			var b: Dictionary = state.buildings[bid]
			var wf: Dictionary = sim.bdef(str(b["type"])).get("workforce", {})
			for tk: String in wf:
				var t := int(tk.substr(1))
				labor[t]["need"] += float(wf[tk])
				if b.get("paused", false) or b.get("money_stop", false):
					continue
				demand[t] = float(demand.get(t, 0.0)) + float(wf[tk])
		var frac := {}
		for t: int in demand:
			var give := minf(float(left.get(t, 0.0)), float(demand[t]))
			frac[t] = give / float(demand[t]) if demand[t] > 0.0 else 1.0
			left[t] = float(left.get(t, 0.0)) - give
			labor[t]["used"] += give
		for bid: int in members:
			var b: Dictionary = state.buildings[bid]
			var wf: Dictionary = sim.bdef(str(b["type"])).get("workforce", {})
			var s := 1.0
			if b.get("paused", false) or b.get("money_stop", false):
				s = 0.0
			else:
				for tk: String in wf:
					s = minf(s, float(frac.get(int(tk.substr(1)), 0.0)))
			b["staff"] = s
	state.labor = labor


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name == "hud" or name == "economy":
		var rows: Array = []
		for t: int in range(1, sim.max_tier() + 1):
			var l: Dictionary = state.labor.get(t, {"have": 0, "need": 0.0, "used": 0.0})
			rows.append({"tier": t, "name": sim.tname(t), "have": int(l["have"]), "need": int(ceilf(float(l["need"]) - 1e-6)),
				"spare": int(l["have"]) - int(ceilf(float(l["need"]) - 1e-6))})
		out["labor"] = rows
