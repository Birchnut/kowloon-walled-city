extends SimSystem
## utilities — 물·전기: 도시 전체 공급 대 수요(확정 구조).
##  주민 수요 = Σ 계층 인구 × 1인 수요(tiers.json water/power) + 주거가 고른 유틸리티 대체품(예: 등불 대신 전기 0.5/인).
##  시설 수요 = Σ 가동 시설의 water/power × 인력 비율(빈 시설은 안 쓴다).
##  공급 = Σ 공급 시설 × 인력 비율 × (그 시설이 전기를 쓰면 직전 전기 비율). 외부 연결도 같은 공급 시설이다.
##  배분: 주민 먼저(res_ratio) → 남는 것을 시설 순위대로, 같은 순위 안에서는 비율로(b.w_ratio, b.p_ratio).
##  단위: 물 = 물 단위/경제일, 전기 = 부하 단위(용량). 저장 없음.
## 이벤트: power_changed{on} — 도시 전기 공급이 처음 생기거나 끊길 때.
## 끄면: 물·전기가 늘 충분한 것으로 본다(res_ratio 1, 시설 비율 1).

const U := ["water", "power"]


func tick(state: CityState, _dt: float) -> void:
	var res := {"water": 0.0, "power": 0.0}
	for b: Dictionary in state.buildings.values():
		if b["kind"] != "house":
			continue
		var r := float(b["residents"])
		if r <= 0.0:
			continue
		var td := sim.tier(int(b["tier"]))
		res["water"] += r * float(td.get("water", 0.0))
		res["power"] += r * float(td.get("power", 0.0))
		var ex: Dictionary = b.get("util_extra", {})
		for u: String in ex:
			res[u] = float(res.get(u, 0.0)) + r * float(ex[u])
	var cov := sim.cover(state)
	var supply := {"water": 0.0, "power": 0.0}
	var groups := {}
	var order: Array = []
	var fac_dem := {"water": 0.0, "power": 0.0}
	for bid: int in cov["by_prio"]:
		if not state.buildings.has(bid):
			continue
		var b: Dictionary = state.buildings[bid]
		var d := sim.bdef(str(b["type"]))
		var staff := sim.staff_of(b)
		var sup: Dictionary = d.get("supply", {})
		for u: String in sup:
			var k := staff
			if float(d.get("power", 0.0)) > 0.0:
				k = minf(k, float(b.get("p_ratio", 0.0)))
			supply[u] += float(sup[u]) * k
		var p := str(d.get("priority", "other"))
		if not groups.has(p):
			groups[p] = []
			order.append(p)
		var want := {}
		for u: String in U:
			var amt := float(d.get(u, 0.0)) * staff
			if amt > 0.0:
				want[u] = amt
				fac_dem[u] += amt
		groups[p].append([b, want])
	var out := {}
	for u: String in U:
		var s: float = supply[u]
		var rd: float = res[u]
		var rr := 1.0 if rd <= 1e-9 else minf(1.0, s / rd)
		var left := maxf(0.0, s - rd)
		for p: String in order:
			var tot := 0.0
			for pair: Array in groups[p]:
				tot += float(pair[1].get(u, 0.0))
			var fr := 1.0 if tot <= 1e-9 else minf(1.0, left / tot)
			left = maxf(0.0, left - tot * fr)
			for pair: Array in groups[p]:
				var b: Dictionary = pair[0]
				var d := sim.bdef(str(b["type"]))
				if float(d.get(u, 0.0)) > 0.0:
					b["w_ratio" if u == "water" else "p_ratio"] = fr
		var fd: float = fac_dem[u]
		out[u] = {"supply": s, "demand": rd + fd, "res_demand": rd, "fac_demand": fd, "res_ratio": rr,
			"fac_ratio": 1.0 if fd <= 1e-9 else clampf((s - rd) / fd, 0.0, 1.0)}
	state.util = out
	var on: bool = float(out["power"]["supply"]) > 1e-6
	if on != bool(state.flags.get("power_on", false)):
		state.flags["power_on"] = on
		state.emit("power_changed", {"on": on})
		if on and not state.stats.has("first_power_day"):
			state.stats["first_power_day"] = state.econ_days
		sim.say(state, "성채에 처음 전기가 들어왔다. 창마다 불이 켜진다." if on and not state.flags.has("power_seen") else ("전기가 다시 들어왔다." if on else "전기가 끊겼다."), "good" if on else "warn")
		state.flags["power_seen"] = true


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name == "hud":
		for u: String in U:
			var x: Dictionary = state.util.get(u, {})
			out[u] = {"supply": snappedf(float(x.get("supply", 0.0)), 0.1), "demand": snappedf(float(x.get("demand", 0.0)), 0.1)}
	elif name == "economy":
		var rows: Array = []
		for u: String in U:
			var x: Dictionary = state.util.get(u, {})
			var srcs: Array = []
			var by := {}
			for b: Dictionary in state.buildings.values():
				if b["kind"] == "facility" and sim.bdef(str(b["type"])).get("supply", {}).has(u):
					by[b["type"]] = int(by.get(b["type"], 0)) + 1
			for t: String in by:
				srcs.append("%s ×%d (+%d)" % [sim.bdef(t).get("name", t), by[t], int(sim.bdef(t)["supply"][u]) * int(by[t])])
			var s := float(x.get("supply", 0.0))
			var dmd := float(x.get("demand", 0.0))
			rows.append({"id": u, "name": "물" if u == "water" else "전기", "supply": snappedf(s, 0.1), "demand": snappedf(dmd, 0.1),
				"ratio": 1.0 if dmd <= 0.0 else snappedf(minf(1.0, s / dmd), 0.01), "sources": srcs})
		out["utilities"] = rows
