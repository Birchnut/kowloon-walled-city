extends SimSystem
## 성장 — 사람들이 스스로 짓는다. 대장은 방을 놓지 않는다.
##  · 건축 품(budget)이 날마다 쌓인다: budget_base + 가구 수 × budget_per_household (투자 정책 growth.budget 배율, 상한 budget_cap_days일치).
##  · 사업 수요도 쌓인다: 남는 일손이 많을수록, 허가가 장려일수록(permit_weight), 같은 업종 앵커·가게·그 일을 하려는 가구가 많을수록.
##  · 품은 "접속 중"에만 쓴다. site_interval_min(도시 분)마다 공사 1건: 대문 앞 가구의 집, 또는 수요가 찬 업종의 가게.
##    자리는 Placement가 점수로 고르고, 자재는 정책·재고·이웃을 보고 고른다(재고가 없으면 폐자재 → 낮게 깔린다).
##    공사 칸(site)은 자재별 build_hours 뒤 방/가게가 된다. 미접속 중에는 품과 수요만 쌓이고 셀은 하나도 안 바뀐다.
##  · 살다 보면 고친다(upgrade): 판잣집→단칸방→살림집, 기둥을 못 올리게 막는 약한 자재는 보강.
##  · 쪽방(cage): 줄이 길고(cage.pressure) 일꾼 우선이거나, 악명이 높고 음성이 허가돼 있거나, 카드로 허락했으면 방을 쪼갠다.
## 수치: data/economy.json "growth" (+ "growth.score" 자리 점수, "growth.why" 설명 문장) · 자재는 materials.json.


func _g(state: CityState) -> Dictionary:
	if not state.flags.has("growth"):
		state.flags["growth"] = {"budget": 0.0, "timer": 0.0, "upg": 0.0, "demand": {}, "sites": [], "forced": [], "cage_today": 0}
	return state.flags["growth"]


func on_new_game(state: CityState) -> void:
	_g(state)["budget"] = sim.num("growth.budget_start", 3.0)


func on_day_start(state: CityState) -> void:
	_g(state)["cage_today"] = 0


func on_hour(state: CityState, _hour: int) -> void:
	var g := _g(state)
	for r: Dictionary in Ops.take_queue(state, "build_requests"):
		if not sim.item("businesses", str(r.get("type", ""))).is_empty():
			g["forced"].append(str(r["type"]))
	var m := sim.metrics(state)
	var hh := float(m.get("households", 0.0))
	var k := sim.pace("growth_mult") / 24.0
	var per_day := (sim.num("growth.budget_base", 5.0) + hh * sim.num("growth.budget_per_household", 0.09)) * sim.mod(state, "growth.budget")
	g["budget"] = minf(float(g["budget"]) + per_day * k, per_day * sim.num("growth.budget_cap_days", 1.5))
	# 사업 수요
	var gap := maxf(0.0, float(m.get("unemployed", 0.0)) + 0.5 * float(m.get("waiting", 0.0)) - float(m.get("jobs_open", 0.0)))
	var rate := (sim.num("growth.biz_base", 0.6) + sim.num("growth.biz_per_slack", 0.45) * gap) * sim.mod(state, "growth.biz") * k
	var weights := {}
	var total := 0.0
	for grp: String in Metrics.GROUPS:
		var w := float(sim.tune("growth.permit_weight", {}).get(str(state.policies.get("permit." + grp, "allow")), 1.0))
		if w > 0.0:
			var people := 0.0
			for t: String in sim.items("households"):
				people += float(m.get("hh." + t, 0.0)) * float(sim.item("households", t).get("job_pref", {}).get(grp, 0.0)) / 4.0
			var anchors := 0.0
			for a: Dictionary in m.get("_anchors", []):
				if a["group"] == grp:
					anchors += 1.0
			w *= float(sim.tune("growth.group_base", {}).get(grp, 1.0)) + sim.num("growth.group_anchor", 1.5) * anchors \
				+ sim.num("growth.group_existing", 0.25) * sqrt(float(m.get("biz." + grp, 0.0))) + sim.num("growth.group_people", 0.15) * people
			w *= sim.mod(state, "growth.biz." + grp)
		weights[grp] = w
		total += w
	for grp: String in weights:
		var cur := float(g["demand"].get(grp, 0.0))
		if total > 0.0 and weights[grp] > 0.0:
			cur = minf(cur + rate * float(weights[grp]) / total, sim.num("growth.biz_demand_cap", 6.0))
		elif weights[grp] <= 0.0:
			cur = 0.0
		g["demand"][grp] = cur
	if not sim.offline:
		g["upg"] = float(g["upg"]) + (sim.num("growth.upgrade_base", 1.0) + hh * sim.num("growth.upgrade_per_household", 0.03)) * sim.mod(state, "growth.upgrade") * k
		while float(g["upg"]) >= 1.0:
			g["upg"] = float(g["upg"]) - 1.0
			GrowthUpgrade.one(sim, state)


func tick(state: CityState, dt: float) -> void:
	if sim.offline:
		return
	var g := _g(state)
	var sites: Array = g["sites"]
	for pos: Vector3i in sites.duplicate():
		var c: Dictionary = state.cells.get(pos, {})
		if c.get("kind", "") != "site":
			sites.erase(pos)
			continue
		var hours := float(sim.item("materials", str(c.get("material", ""))).get("build_hours", 3.0))
		c["progress"] = float(c.get("progress", 0.0)) + dt / maxf(hours, 0.1) * sim.pace("growth_mult")
		if float(c["progress"]) >= 1.0:
			sites.erase(pos)
			_complete(state, pos, c)
	g["timer"] = float(g["timer"]) - dt
	if float(g["timer"]) > 0.0 or float(g["budget"]) < 1.0:
		return
	if sim.tune("growth.require_anchor", true) and int(state.stats.get("plants", 0)) == 0 and sim.enabled.has("plots"):
		return
	var max_sites := int(sim.num("growth.max_sites_base", 2.0) + float(state.households.size()) * sim.num("growth.max_sites_per_household", 0.04))
	if sites.size() >= max_sites:
		return
	g["timer"] = sim.num("growth.site_interval_min", 15.0) / 60.0
	if _next_build(state, g):
		g["budget"] = float(g["budget"]) - 1.0


func _complete(state: CityState, pos: Vector3i, site: Dictionary) -> void:
	var b: Dictionary = site["becomes"]
	var cell := {"kind": b["kind"], "type": b["type"], "material": b["material"], "owner": int(b.get("owner", 0)),
		"built_day": state.day, "seed": int(site.get("seed", 0)), "why": str(site.get("why", ""))}
	if site.get("cantilever", false):
		cell["cantilever"] = true
	if b["kind"] == "housing":
		cell["residents"] = []
	Ops.set_cell(state, pos, cell)
	if b["kind"] == "business":
		cell["owner"] = Ops.open_business(sim, state, str(b["type"]), pos, false)
		var key := "first_" + str(b["type"])
		if not state.flags.has(key):
			state.flags[key] = state.day
			sim.say(state, "%s이(가) 문을 열었다. 이 성채의 첫 번째다." % sim.def_of(cell).get("name", "가게"), "good")
	state.stats["built_total"] = int(state.stats.get("built_total", 0)) + 1


## 다음 공사 1건을 정해 시작한다. 시작했으면 true.
func _next_build(state: CityState, g: Dictionary) -> bool:
	if not (g["forced"] as Array).is_empty():
		var type := str(g["forced"][0])
		if _start_business(state, type, true):
			g["forced"].pop_front()
			return true
	# 집이 필요한 가구: 대문 앞에 있고, 자기 공사·빈 방이 아직 없는 가구
	var taken := {}
	var free := 0
	for c: Dictionary in state.cells.values():
		var kind := str(c.get("becomes", c).get("kind", ""))
		if kind != "housing":
			continue
		var owner := int(c.get("becomes", c).get("owner", 0))
		if c["kind"] == "site" or ((c.get("residents", []) as Array).is_empty() and state.households.has(owner) and state.households[owner].get("home") == null):
			taken[owner] = true
		elif c["kind"] == "housing":
			free += maxi(0, Ops.free_slots(sim, c))
	var need: Array = []
	for id: int in state.households:
		if state.households[id].get("home") == null and not taken.has(id):
			need.append(id)
	need.sort()
	need = need.slice(mini(free, need.size()))
	var demand: Dictionary = g["demand"]
	var groups: Array = []
	var gw: Array = []
	for grp: String in demand:
		if float(demand[grp]) >= 1.0:
			groups.append(grp)
			gw.append(float(demand[grp]))
	var biz_w := 0.0
	for x: float in gw:
		biz_w += floorf(x)
	var i := sim.pick(state, [float(need.size()) * sim.num("growth.housing_bias", 1.5), biz_w])
	if i == 0:
		if GrowthUpgrade.cage_wanted(sim, state, need.size()) and int(g["cage_today"]) < int(sim.num("growth.cage.per_day", 2)) and GrowthUpgrade.densify(sim, state):
			g["cage_today"] = int(g["cage_today"]) + 1
			return true
		return _start_housing(state, int(need[0]))
	if i == 1:
		var grp: String = groups[sim.pick(state, gw)]
		var type := _pick_type(state, grp)
		demand[grp] = float(demand[grp]) - 1.0
		return type != "" and _start_business(state, type, false)
	return false


func _pick_type(state: CityState, grp: String) -> String:
	var m := sim.metrics(state)
	var ids: Array = []
	var w: Array = []
	var defs := sim.items("businesses")
	for id: String in defs:
		var d: Dictionary = defs[id]
		if d.get("group", "") != grp or not sim.is_unlocked(state, d.get("unlock")) or state.power_level < int(d.get("power", 0)) or not Expr.test(d.get("needs"), m):
			continue
		ids.append(id)
		w.append(float(d.get("weight", 1.0)) * (1.0 + float(d.get("cluster", 0.0)) * float(m.get("count." + id, 0.0))))
	var i := sim.pick(state, w)
	return str(ids[i]) if i >= 0 else ""


func _start_housing(state: CityState, hh: int) -> bool:
	var hd := sim.item("households", str(state.households[hh]["type"]))
	var spot := Placement.best(sim, state, {"kind": "housing", "group": "housing", "sun_pref": float(hd.get("sun", 0.5)),
		"cantilever": state.unlocked.has("cantilever")})
	if spot.is_empty():
		state.flags["growth_full"] = state.day
		return false
	var mat := GrowthUpgrade.material(sim, state, spot["pos"], "")
	var type := str(sim.tune("growth.housing_scrap", "shack")) if mat == "scrap" else str(sim.tune("growth.housing_new", "room"))
	_site(state, spot, {"kind": "housing", "type": type, "material": mat, "owner": hh}, str(hd.get("home_word", "집")))
	return true


func _start_business(state: CityState, type: String, forced: bool) -> bool:
	var d := sim.item("businesses", type)
	var spot := Placement.best(sim, state, {"kind": "business", "group": str(d.get("group", "")), "prefer": d.get("prefer", {}),
		"nuisance": float(d.get("noise", 0.0)) + float(d.get("dirt", 0.0)), "cluster_w": 1.0 + float(d.get("cluster", 0.0)),
		"cantilever": state.unlocked.has("cantilever")})
	if spot.is_empty():
		state.flags["growth_full"] = state.day
		return false
	if forced:
		spot["why_key"] = "forced"
	_site(state, spot, {"kind": "business", "type": type, "material": GrowthUpgrade.material(sim, state, spot["pos"], str(d.get("group", ""))), "owner": 0}, str(d.get("name", type)))
	return true


func _site(state: CityState, spot: Dictionary, becomes: Dictionary, what: String) -> void:
	var pos: Vector3i = spot["pos"]
	state.materials = maxf(0.0, state.materials - float(sim.item("materials", str(becomes["material"])).get("cost", 0.0)))
	var tpl: Dictionary = sim.tune("growth.why", {})
	var key := str(spot.get("why_key", ""))
	if key in ["anchor", "adjacent", "cluster"] and str(spot.get("near", "")) != "":
		key = "near"
	var why := str(tpl.get(key, tpl.get("default", "{what}이(가) 들어섰다."))).format({"what": what, "near": spot.get("near", ""),
		"anchor": spot.get("anchor", ""), "zone": {"housing": "주거", "work": "일터"}.get(spot.get("zone", ""), "")})
	var cell := {"kind": "site", "type": becomes["type"], "material": becomes["material"], "owner": int(becomes.get("owner", 0)),
		"built_day": state.day, "seed": sim.rand_seed(state), "progress": 0.0, "becomes": becomes, "why": sim.fmt(state, why)}
	if spot.get("cantilever", false):
		cell["cantilever"] = true
	Ops.set_cell(state, pos, cell)
	_g(state)["sites"].append(pos)


func metrics(state: CityState, m: Dictionary) -> void:
	var g := _g(state)
	m["build_budget"] = float(g["budget"])
	m["growth_full"] = 1.0 if int(state.flags.get("growth_full", -99)) >= state.day - 1 else 0.0
	for grp: String in g["demand"]:
		m["biz_demand." + grp] = float(g["demand"][grp])


func fast_forward(state: CityState, _hours: float, _before: Dictionary, lines: Array) -> void:
	var n := int(float(_g(state)["budget"]))
	if n >= 2:
		lines.append("지을 사람들은 %s을 기다렸다 — 공사 %d건이 밀려 있다." % [state.identity.get("title", "대장"), n])
