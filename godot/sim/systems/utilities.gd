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
	var nt := sim.max_tier()
	var wt := PackedFloat64Array()
	var pt := PackedFloat64Array()
	wt.resize(nt + 1)
	pt.resize(nt + 1)
	for t: int in range(1, nt + 1):
		wt[t] = float(sim.tier(t).get("water", 0.0))
		pt[t] = float(sim.tier(t).get("power", 0.0))
	var rw := 0.0
	var rp := 0.0
	for b: Dictionary in sim.cover(state)["houses"]:
		var ri: int = b["residents"]
		if ri <= 0:
			continue
		var r := float(ri)
		var ti: int = b["tier"]
		rw += r * wt[ti]
		rp += r * pt[ti]
		var ex: Dictionary = b.get("util_extra", {})
		if not ex.is_empty():
			for u: String in ex:
				res[u] = float(res.get(u, 0.0)) + r * float(ex[u])
	res["water"] += rw
	res["power"] += rp
	res["water"] *= sim.mod(state, "water.demand")   # 연구: 주민 물 수요 배수
	var cov := sim.cover(state)
	var groups: Array = cov["groups"]
	var sw := 0.0
	var sp := 0.0
	var fdw := 0.0
	var fdp := 0.0
	var gtw := PackedFloat64Array()
	var gtp := PackedFloat64Array()
	for g: Array in groups:
		var tw := 0.0
		var tp := 0.0
		for f: Array in g[1]:
			var b: Dictionary = f[0]
			var staff := sim.staff_of(b)
			var k := staff
			if f[4] > 0.0:
				k = minf(k, float(b.get("p_ratio", 0.0)))
			if f[1] > 0.0:
				sw += float(f[1]) * k
			if f[2] > 0.0:
				sp += float(f[2]) * k
			var aw: float = float(f[3]) * staff
			if aw > 0.0:
				tw += aw
				fdw += aw
			var ap: float = float(f[4]) * staff
			if ap > 0.0:
				tp += ap
				fdp += ap
		gtw.append(tw)
		gtp.append(tp)
	var supply := {"water": sw, "power": sp * sim.mod(state, "power.supply")}   # 연구: 전기 공급 배수
	var fac_dem := {"water": fdw, "power": fdp}
	var out := {}
	for u: String in U:
		var s: float = supply[u]
		var rd: float = res[u]
		var rr := 1.0 if rd <= 1e-9 else minf(1.0, s / rd)
		var left := maxf(0.0, s - rd)
		var wi := 3 if u == "water" else 4
		var key := "w_ratio" if u == "water" else "p_ratio"
		var gt := gtw if u == "water" else gtp
		for gi: int in groups.size():
			var tot: float = gt[gi]
			var fr := 1.0 if tot <= 1e-9 else minf(1.0, left / tot)
			left = maxf(0.0, left - tot * fr)
			for f: Array in groups[gi][1]:
				if float(f[wi]) > 0.0:
					f[0][key] = fr
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
