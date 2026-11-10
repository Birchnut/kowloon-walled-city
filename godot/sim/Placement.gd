class_name Placement
extends RefCounted
## Placement — "어디에 지을까". 후보 칸마다 점수를 매겨 가장 높은 곳을 고른다(성장 시스템의 도우미, 순수 함수).
## 후보 = 비움(keep)이 아닌 기둥의 맨 위 칸(지상 또는 완공된 칸 바로 위, 층 한도·자재 강도 안쪽,
##        하늘을 열어 둬야 하는 칸 위는 제외) + (해금되면) 옆 건물에 매달리는 허공 증축 한 칸.
## 점수 = 앵커와의 거리 + 옆벽에 기대기 + 같은 업종 모이기 + 구획 맞춤 + 자리 취향(prefer) + 볕(주거)
##        − 소음·먼지 이웃 − 혼자 툭 튀어나오기 − 높이 + 무작위 흔들림.  가중치: data/economy.json "growth.score".
## 가장 크게 기여한 항이 그 칸의 "왜 여기에"(why)가 된다.

const N8: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(1, 1, 0), Vector3i(-1, 1, 0), Vector3i(1, -1, 0), Vector3i(-1, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const WHY_KEYS := ["anchor", "adjacent", "cluster", "zone", "sun", "dark", "ground", "gate", "high", "edge", "hidden", "water", "low"]


## spec = {kind, group, sun_pref, prefer{}, nuisance, cluster_w, cantilever(bool)} → {pos, why_key, near, cantilever} 또는 {}
static func best(sim: Sim, state: CityState, spec: Dictionary) -> Dictionary:
	var S: Dictionary = sim.tune("growth.score", {})
	var floor_cap: int = mini(sim.F, int(state.flags.get("floor_cap", sim.F)))
	var heights := {}
	for x: int in sim.W:
		for y: int in sim.H:
			heights[Vector2i(x, y)] = Grid.height(sim, state, x, y)
	var anchors: Array = []
	for b: Dictionary in state.businesses.values():
		if b.get("facility", false):
			var d := sim.item("facilities", str(b["type"]))
			anchors.append({"pos": b["cells"][0], "group": str(b["group"]), "name": str(d.get("name", "")), "water": float(d.get("water", 0.0)) > 0.0})
	var out := {}
	var top := -INF
	for x: int in sim.W:
		for y: int in sim.H:
			var col := Vector2i(x, y)
			var zone := str(state.zones.get(col, ""))
			if zone == "keep":
				continue
			var h: int = heights[col]
			var roof_locked := false
			if h > 0:
				var under: Dictionary = state.cells.get(Vector3i(x, y, h - 1), {})
				roof_locked = under.get("kind", "") == "site" or sim.def_of(under).get("open_sky", false)
			if not roof_locked and h < floor_cap and (h == 0 or h < Grid.load_cap(sim, state, x, y)):
				var r := _score(sim, state, spec, Vector3i(x, y, h), heights, anchors, S, zone)
				if float(r["score"]) > top:
					top = r["score"]
					out = r
			if spec.get("cantilever", false) and not roof_locked:
				for d: Vector3i in Grid.N4:
					var hn: int = heights.get(Vector2i(x + d.x, y + d.y), 0)
					var z := hn - 1
					if hn < h + 2 or z >= floor_cap:
						continue
					var side := Vector3i(x + d.x, y + d.y, z)
					if not Grid.solid(state, side) or not state.cells.has(side + Vector3i(0, 0, -1)) or state.cells[side].get("cantilever", false):
						continue
					var r := _score(sim, state, spec, Vector3i(x, y, z), heights, anchors, S, zone)
					r["score"] = float(r["score"]) - float(S.get("cantilever_penalty", 2.0))
					r["cantilever"] = true
					if float(r["score"]) > top:
						top = r["score"]
						out = r
	return out


static func _score(sim: Sim, state: CityState, spec: Dictionary, pos: Vector3i, heights: Dictionary, anchors: Array, S: Dictionary, zone: String) -> Dictionary:
	var housing: bool = spec["kind"] == "housing"
	var group := str(spec.get("group", ""))
	var parts := {}
	# 앵커: 가장 잘 끌어당기는 하나만 본다.
	var a_best := 0.0
	var a_name := ""
	var water := 0.0
	for a: Dictionary in anchors:
		var ap: Vector3i = a["pos"]
		var dist := absf(float(ap.x - pos.x)) + absf(float(ap.y - pos.y)) + float(S.get("anchor_dz", 0.6)) * absf(float(ap.z - pos.z))
		var w := 1.0
		if housing:
			w = float(S.get("anchor_public_housing", 1.3)) if a["group"] == "public" else 1.0
		else:
			w = float(S.get("anchor_same_group", 1.6)) if a["group"] == group else float(S.get("anchor_other", 0.6))
		var v := w / (1.0 + dist * float(S.get("anchor_falloff", 0.45)))
		if v > a_best:
			a_best = v
			a_name = a["name"]
		if a["water"]:
			water = maxf(water, 1.0 / (1.0 + dist))
	parts["anchor"] = float(S.get("anchor", 5.0)) * a_best
	# 이웃 훑기
	var adj := 0
	var same := 0
	var n_housing := 0
	var nuisance := 0.0
	var near := ""
	for i: int in N8.size():
		var c: Dictionary = state.cells.get(pos + N8[i], {})
		if c.is_empty():
			continue
		var orth := i < 4 or i >= 8
		if i < 4:
			adj += 1
		var d := sim.def_of(c)
		if c.get("becomes", c).get("kind", "") == "housing":
			if orth:
				n_housing += 1
			if housing:
				same += 1
		else:
			if orth:
				nuisance += float(d.get("noise", 0.0)) + float(d.get("dirt", 0.0))
				if near == "":
					near = str(d.get("name", ""))
			if str(d.get("group", "")) == group:
				same += 1
	parts["adjacent"] = float(S.get("adjacent", 0.7)) * float(adj)
	parts["cluster"] = float(S.get("cluster", 0.5)) * float(same) * float(spec.get("cluster_w", 1.0))
	if pos.z == 0 and adj == 0 and a_best < 0.4:
		parts["isolated"] = float(S.get("isolated", -2.5))
	# 주변보다 툭 튀어나오면 감점(계단식 덩어리가 되게), 높을수록 감점(업종별)
	var open_sides := 0
	var taller := 0
	var mean := 0.0
	var cnt := 0
	for d: Vector3i in Grid.N4:
		var q := Vector2i(pos.x + d.x, pos.y + d.y)
		if not Grid.inside(sim, q.x, q.y):
			open_sides += 1
			continue
		var hq: int = heights.get(q, 0)
		mean += float(hq)
		cnt += 1
		if hq <= pos.z:
			open_sides += 1
		if hq >= pos.z + 2:
			taller += 1
	mean = mean / float(cnt) if cnt > 0 else 0.0
	parts["step"] = -float(S.get("step", 0.9)) * maxf(0.0, float(pos.z) - mean)
	parts["height"] = -float(S.get("height", {}).get("housing" if housing else group, 0.3)) * float(pos.z)
	if zone != "":
		var fits: bool = (zone == "housing") == housing
		parts["zone"] = float(S.get("zone_match", 2.5)) if fits else -float(S.get("zone_clash", 5.0))
	var sun := Grid.sunlight(sim, state, pos)
	if housing:
		parts["sun"] = float(S.get("sun_housing", 2.0)) * float(spec.get("sun_pref", 0.5)) * sun
		parts["nuisance"] = -float(S.get("nuisance", 0.6)) * nuisance
	else:
		parts["repel"] = -float(S.get("repel", 0.5)) * float(spec.get("nuisance", 0.0)) * float(n_housing)
		var pf: Dictionary = spec.get("prefer", {})
		for key: String in pf:
			var f := 0.0
			match key:
				"ground": f = 1.0 if pos.z == 0 else 0.0
				"low": f = 1.0 / (1.0 + float(pos.z))
				"gate": f = 1.0 / (1.0 + Grid.gate_dist(sim, pos.x, pos.y) / 3.0)
				"sun": f = sun
				"dark": f = 0.6 * float(4 - open_sides) / 4.0 + 0.4 * float(taller) / 4.0
				"high": f = float(pos.z) / float(sim.F)
				"edge": f = 1.0 / (1.0 + float(Grid.edge_dist(sim, pos.x, pos.y)))
				"hidden": f = Grid.gate_dist(sim, pos.x, pos.y) / float(sim.W + sim.H)
				"water": f = water
			parts[key] = float(parts.get(key, 0.0)) + float(pf[key]) * f
	var score := float(S.get("noise", 1.2)) * sim.roll(state)
	var why := ""
	var why_v := 0.0
	for key: String in parts:
		score += float(parts[key])
		if key in WHY_KEYS and float(parts[key]) > why_v:
			why_v = parts[key]
			why = key
	return {"pos": pos, "score": score, "why_key": why, "near": near, "anchor": a_name, "zone": zone}
