class_name Metrics
extends RefCounted
## Metrics — 상태에서 이름 붙은 숫자를 한 번에 뽑는다(조건식·가중합·UI·디버그·봇이 전부 이걸 본다).
## 시스템은 SimSystem.metrics()로 자기 지표를 보탠다. "_"로 시작하는 키는 숫자가 아닌 도우미(식에서는 못 씀).
##
## 주요 이름: population households waiting dependents workers unemployed jobs jobs_open jobs_open.<group>
##   hh.<가구유형> named.<인물> cells sites cells.<kind> count.<type> group.<group> biz.<group> mat.<자재>
##   housing.<유형> tag_count.<태그> sum.prestige|notoriety|morale max_height footprint avg_height keep_columns
##   sun_housing noise_housing quality_housing cage_ratio unemployed_ratio waiting_ratio dependent_ratio
##   family_share crowd_over food_days dominant(문자) policy.<axis>(문자) policy.<axis>.<값>=1
##   permit.<group>(문자) permit_level.<group> unlocked.<id>=1 flag.<이름> stat.<이름>

const PERMIT_LEVEL := {"ban": 0.0, "allow": 1.0, "promote": 2.0}
const GROUPS := ["farm", "make", "fun", "vice"]


static func _add(m: Dictionary, key: String, x: float = 1.0) -> void:
	m[key] = float(m.get(key, 0.0)) + x


static func compute(sim: Sim, state: CityState) -> Dictionary:
	var m := {
		"day": float(state.day), "hour": state.hour, "money": state.money, "food": state.food,
		"materials": state.materials, "prestige": state.prestige, "notoriety": state.notoriety,
		"morale": state.morale, "alley_fund": state.alley_fund, "power_level": float(state.power_level),
		"water_cap": float(state.water_cap),
	}
	for axis: String in state.policies:
		var v := str(state.policies[axis])
		m["policy." + axis] = v
		m["policy.%s.%s" % [axis, v]] = 1.0
		if axis.begins_with("permit."):
			m[axis] = v
			m["permit_level." + axis.substr(7)] = PERMIT_LEVEL.get(v, 0.0)
	for id: Variant in state.unlocked:
		m["unlocked." + str(id)] = 1.0
	for src: Array in [["flag.", state.flags], ["stat.", state.stats]]:
		for k: Variant in src[1]:
			var x: Variant = src[1][k]
			if x is float or x is int or x is bool:
				m[src[0] + str(k)] = float(x)
			elif x is String:
				m[src[0] + str(k)] = x
	_people(sim, state, m)
	_cells(sim, state, m)
	var pop: float = maxf(float(m["population"]), 1.0)
	m["crowd_over"] = maxf(0.0, float(m["population"]) - state.water_cap) / pop if sim.enabled.has("utilities") else 0.0
	m["food_days"] = state.food / pop
	return m


static func _people(sim: Sim, state: CityState, m: Dictionary) -> void:
	var defs := sim.items("households")
	var pop := 0.0
	var family := 0.0
	for k: String in ["households", "waiting", "dependents", "workers", "unemployed", "jobs", "jobs_open"]:
		m[k] = 0.0
	for h: Dictionary in state.households.values():
		var d: Dictionary = defs.get(h.get("type", ""), {})
		pop += float(h.get("size", 1))
		m["households"] += 1.0
		_add(m, "hh." + str(h.get("type", "")))
		family += float(d.get("family", 0.0))
		if h.get("home") == null:
			m["waiting"] += 1.0
		if str(h.get("named", "")) != "":
			m["named." + str(h["named"])] = 1.0
		if not d.get("works", true):
			m["dependents"] += 1.0
		else:
			m["workers"] += 1.0
			if int(h.get("job", 0)) == 0 and h.get("home") != null:
				m["unemployed"] += 1.0
	m["population"] = pop
	var hh: float = maxf(float(m["households"]), 1.0)
	m["family_share"] = family / hh
	m["waiting_ratio"] = float(m["waiting"]) / hh
	m["dependent_ratio"] = float(m["dependents"]) / hh
	m["unemployed_ratio"] = float(m["unemployed"]) / maxf(float(m["workers"]), 1.0)
	for b: Dictionary in state.businesses.values():
		var group := str(b.get("group", ""))
		var jobs := int(b.get("jobs", 0))
		var open: int = maxi(0, jobs - (b.get("workers", []) as Array).size())
		m["jobs"] += float(jobs)
		m["jobs_open"] += float(open)
		_add(m, "jobs_open." + group, float(open))
		if not b.get("facility", false):
			_add(m, "biz." + group)


static func _cells(sim: Sim, state: CityState, m: Dictionary) -> void:
	var heights := {}
	var anchors: Array = []
	var sun := 0.0
	var noise := 0.0
	var quality := 0.0
	var housing := 0.0
	for k: String in ["cells", "sites", "max_height", "sum.prestige", "sum.notoriety", "sum.morale"]:
		m[k] = 0.0
	for pos: Vector3i in state.cells:
		var c: Dictionary = state.cells[pos]
		var col := Vector2i(pos.x, pos.y)
		heights[col] = maxi(int(heights.get(col, 0)), pos.z + 1)
		m["cells"] += 1.0
		var kind := str(c.get("kind", ""))
		if kind == "site":
			m["sites"] += 1.0
			continue
		var d := sim.def_of(c)
		_add(m, "cells." + kind)
		_add(m, "count." + str(c.get("type", "")))
		_add(m, "mat." + str(c.get("material", "")))
		for f: String in ["prestige", "notoriety", "morale"]:
			m["sum." + f] += float(d.get(f, 0.0))
		for t: Variant in d.get("tags", []):
			_add(m, "tag_count." + str(t))
		for t: Variant in sim.item("materials", str(c.get("material", ""))).get("tags", []):
			_add(m, "tag_count." + str(t))
		if kind == "housing":
			_add(m, "housing." + str(c.get("type", "")))
			housing += 1.0
			sun += Grid.sunlight(sim, state, pos)
			quality += float(d.get("quality", 0.0)) + float(sim.item("materials", str(c.get("material", ""))).get("quality", 0.0))
			for n: Vector3i in Grid.N6:
				var nc: Dictionary = state.cells.get(pos + n, {})
				if not nc.is_empty() and nc.get("kind", "") != "housing":
					var nd := sim.def_of(nc)
					noise += float(nd.get("noise", 0.0)) + float(nd.get("dirt", 0.0))
		else:
			var group := str(d.get("group", ""))
			if group in GROUPS:
				_add(m, "group." + group)
			if kind == "facility":
				anchors.append({"pos": pos, "type": str(c.get("type", "")), "group": group})
	var hn := maxf(housing, 1.0)
	m["sun_housing"] = sun / hn if housing > 0.0 else 0.5
	m["noise_housing"] = noise / hn
	m["quality_housing"] = quality / hn
	m["cage_ratio"] = float(m.get("housing.cage", 0.0)) / hn
	m["footprint"] = float(heights.size())
	for col: Vector2i in heights:
		m["max_height"] = maxf(float(m["max_height"]), float(heights[col]))
	m["avg_height"] = float(m["cells"]) / maxf(float(heights.size()), 1.0)
	m["keep_columns"] = 0.0
	for col: Variant in state.zones:
		_add(m, "zone." + str(state.zones[col]))
		if state.zones[col] == "keep":
			m["keep_columns"] += 1.0
	# 지배 업종: 1위가 3칸 이상이고 2위보다 2할 넘게 앞설 때만.
	var best := ""
	var top := 0.0
	var second := 0.0
	for g: String in GROUPS:
		var n := float(m.get("group." + g, 0.0))
		if n > top:
			second = top
			top = n
			best = g
		elif n > second:
			second = n
	m["dominant"] = best if (top >= 3.0 and top >= second * 1.2) else ""
	m["_heights"] = heights
	m["_anchors"] = anchors
