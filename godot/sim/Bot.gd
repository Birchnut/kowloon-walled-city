class_name Bot
extends RefCounted
## Bot v4 — 자동 플레이어(data/sim/bots.json). 사람처럼 Sim.apply()/query()/can()만 쓴다(규칙을 건드리지 않는다).
## 한 번의 손길(act) = 탐험 보내고 받기 → 탄 건물 수리 → 물·전기 → 방재 범위(불·쓰레기·병) → 승급 → 시장·서비스 범위 →
##  생산(수요 추정 → 생산 시설, 2단 사슬은 원료도) → 교역(사치품 수입·남는 것 수출) → 주거 칠하기 → 연구·명소·음성·정책.
## 자리: 발자국·회전을 모두 시험하고, 범위 시설은 "아직 안 덮인 쓰이는 칸을 가장 많이 덮는 자리"에 놓는다.
## 주거는 층마다 2×2 구멍(시설 자리)을 남기며 가운데부터 칠한다. 구멍이 모자라면 낮은 계층 주거를 허문다(무료).
## 봇의 기억은 state.flags["bot"]. 명령 수는 cmds, 못 한 일은 blocked(리포트용). 진전 명령 시각은 acts — "빈 구간" 측정.

var sim: Sim
var id: String = ""
var conf: Dictionary = {}
var blocked: Dictionary = {}       # 이유 → 횟수(리포트용)
var cmds: Dictionary = {}          # 명령 이름 → 성공 횟수(리포트용)
var acts: Array = []               # [econ_days, 명령 이름] — 진전(짓기·승급·칠하기·수령·수리) 시각
var ctx: Dictionary = {}
var _save: float = 0.0             # 꼭 필요한 시설을 위해 모으는 돈(이번 손길 동안 덜 급한 지출을 막는다)
var recorded = null                # 시험용(sim_cache_fuzz): Array면 명령마다 [name, args, 결과]
var _dem: Dictionary = {}          # 이번 손길의 수요 추정(캐시)
var _builds: int = 0               # 이번 손길에 지은 시설 수
var _cnt: Dictionary = {}          # 이번 손길의 시설 수(종류별, 공사 포함) — 지을 때마다 갱신
var _sup: Dictionary = {}          # 이번 손길의 생산 능력 캐시(상품별) — 지을 때마다 비움

const MEAL_GOODS := ["cans", "wonton", "burger", "sushi", "veg"]


func _init(s: Sim, bot_id: String) -> void:
	sim = s
	id = bot_id
	conf = sim.item("bots", bot_id)


func c(key: String, def: Variant) -> Variant:
	return conf.get(key, def)


func _block(why: String) -> void:
	blocked[why] = int(blocked.get(why, 0)) + 1


# ------------------------------------------------------------------ 한 번의 손길
func act(state: CityState, context: Dictionary = {}) -> void:
	ctx = context
	if not state.flags.has("bot"):
		state.flags["bot"] = {}
	_builds = 0
	_recount(state)
	_dem = _demand(state)
	# 꼭 필요한데 돈이 모자라 미룬 시설(mem.want)은 다음 손길에도 그 돈을 남겨 둔다(하루 지나면 잊는다)
	var mem: Dictionary = state.flags["bot"]
	var want: Dictionary = mem.get("want", {})
	_save = 0.0
	for t: String in want.keys():
		if state.econ_days - float(want[t][1]) > 1.0 or _count(state, t) > int(want[t][2]):
			want.erase(t)
		else:
			_save = maxf(_save, float(want[t][0]))
	mem["want"] = want
	_t("explore", func() -> void: _explore(state))
	_t("repair", func() -> void: _repair(state))
	_t("utilities", func() -> void: _utilities(state))
	if bool(c("hazards", true)):
		_t("hazards", func() -> void: _hazards(state))
	_t("services", func() -> void: _markets_services(state))
	_t("upgrades", func() -> void: _upgrades(state))
	_t("production", func() -> void: _production(state))
	_t("contracts", func() -> void: _contracts(state))
	_t("zone", func() -> void: _zone(state))
	_t("late", func() -> void: _late(state))
	_t("explore", func() -> void: _explore(state))        # 한 바퀴 돈 뒤 남은 팀(새 거점·돈)도 보낸다


var prof: Dictionary = {}          # 손길 부분별 누적 ms(리포트용)


func _t(name: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	prof[name] = float(prof.get(name, 0.0)) + float(Time.get_ticks_usec() - t0) / 1000.0


func cmd(state: CityState, name: String, args: Dictionary) -> Dictionary:
	var a0: Dictionary = args.duplicate(true) if recorded is Array else {}
	var r := sim.apply(state, name, args)
	if recorded is Array:
		(recorded as Array).append([name, a0, r.duplicate(true)])
	if r.get("ok", false):
		cmds[name] = int(cmds.get(name, 0)) + 1
		if name in ["build", "upgrade", "zone", "expedition_claim", "repair", "research_start", "contract_sign"]:
			acts.append([state.econ_days, name])
	return r


# ------------------------------------------------------------------ 세기
var _nospot: Dictionary = {}       # 이번 손길에 빈 자리를 못 찾은 시설(다시 훑지 않는다)
var _carves: int = 0               # 이번 손길에 자리 내기(허물기)를 한 횟수


func _recount(state: CityState) -> void:
	_nospot.clear()
	_carves = 0
	_cnt.clear()
	_sup.clear()
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "facility" or b["kind"] == "site":
			_cnt[str(b["type"])] = int(_cnt.get(str(b["type"]), 0)) + 1


func _count(_state: CityState, type: String) -> int:
	return int(_cnt.get(type, 0))


func _sites_of(state: CityState, cat: String) -> int:
	var n := 0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "site" and str(sim.bdef(str(b["type"])).get("cat", "")) == cat:
			n += 1
	return n


func _houses(state: CityState) -> int:
	return (sim.cover(state)["houses"] as Array).size()


func _pop(state: CityState, t: int) -> float:
	var n := 0.0
	for b: Dictionary in sim.cover(state)["houses"]:
		if int(b["tier"]) == t:
			n += float(b["residents"])
	return n


func _center(_state: CityState) -> Vector3i:
	return Vector3i(sim.W / 2, sim.H / 2, 0)


# ------------------------------------------------------------------ 자리 찾기
func _free(state: CityState, p: Vector3i, k: Vector3i) -> bool:
	if p.z + k.z - 1 >= state.floors_unlocked or p.x + k.x > sim.W or p.y + k.y > sim.H:
		return false
	for dz: int in k.z:
		for dx: int in k.x:
			for dy: int in k.y:
				if state.cells.has(Vector3i(p.x + dx, p.y + dy, p.z + dz)):
					return false
	return true


## 층마다 2×2 시설 자리(구멍): x, y가 5로 나눈 나머지 3·4인 칸. 주거는 여기를 비워 둔다.
func _reserved(p: Vector3i) -> bool:
	return p.x % 5 >= 3 and p.y % 5 >= 3


func _gap(near: Vector3i, o: Vector3i, k: Vector3i) -> int:
	var dx := maxi(0, maxi(o.x - near.x, near.x - (o.x + k.x - 1)))
	var dy := maxi(0, maxi(o.y - near.y, near.y - (o.y + k.y - 1)))
	return maxi(dx, dy) + 4 * absi(near.z - o.z)


func _rots(type: String) -> Array:
	var k := sim.fp(type, 0)
	return [0, 1] if k.x != k.y else [0]


func _sky_open(state: CityState, o: Vector3i, k: Vector3i) -> bool:
	for dx: int in k.x:
		for dy: int in k.y:
			for z: int in range(o.z + k.z, sim.F):
				if state.cells.has(Vector3i(o.x + dx, o.y + dy, z)):
					return false
	return true


## 범위 없는 시설(생산 등): 구멍 칸을 먼저, 낮은 층을(하늘 시설은 높은 층을), 가운데에 가까운 곳을. [origin, rot] 또는 null.
func _spot(state: CityState, type: String, near: Vector3i) -> Variant:
	var best: Variant = null
	var bd := 1 << 30
	var d := sim.bdef(type)
	var mf := int(d.get("min_floor", 0))
	var sky := bool(d.get("needs_sky", false))
	# 빠른 길: 먼저 2×2 구멍 자리만(대부분의 시설이 여기 들어간다)
	if not sky:
		for z: int in range(mf, state.floors_unlocked):
			for rot: int in _rots(type):
				var k := sim.fp(type, rot)
				if k.x > 2 or k.y > 2:
					continue
				for hx: int in range(3, sim.W - 1, 5):
					for hy: int in range(3, sim.H - 1, 5):
						for ox: int in 3 - k.x:
							for oy: int in 3 - k.y:
								var p := Vector3i(hx + ox, hy + oy, z)
								if _free(state, p, k):
									return [p, rot]
	for rot: int in _rots(type):
		var k := sim.fp(type, rot)
		for z: int in range(mf, state.floors_unlocked):
			for x: int in sim.W - k.x + 1:
				for y: int in sim.H - k.y + 1:
					var p := Vector3i(x, y, z)
					if not _free(state, p, k):
						continue
					var g := _gap(near, Vector3i(p.x, p.y, near.z), k) + z * (3 if not sky else -6)
					for q: Vector3i in Cover.cells_of(p, k.x, k.y, 1):
						if not _reserved(q):
							g += 6
					if g >= bd:
						continue
					if sky and not _sky_open(state, p, k):
						continue
					bd = g
					best = [p, rot]
	return best


## 범위 시설: targets(주거·시설 dict)를 가장 많이 덮는 빈 자리. 첫 대상은 반드시 덮는다. [origin, rot, 덮는 수] 또는 null.
func _cover_spot(state: CityState, type: String, targets: Array) -> Variant:
	if targets.is_empty():
		return null
	var d := sim.bdef(type)
	var rg := Cover.rng_of(d)
	var first: Dictionary = targets[0]
	var fp0: Vector3i = first["pos"]
	# 성능: 첫 대상 근처(범위 두 배 안)의 대상만 센다
	var reach2 := int(rg.get("r", 0)) * 2 + 3
	var near: Array = []
	for t: Dictionary in targets:
		var tp: Vector3i = t["pos"]
		if absi(tp.x - fp0.x) <= reach2 and absi(tp.y - fp0.y) <= reach2 and absi(tp.z - fp0.z) <= int(rg.get("up", 0)) + int(rg.get("down", 0)) + 1:
			near.append(t)
			if near.size() >= 120:
				break
	targets = near
	var best: Variant = null
	var bs := -(1 << 30)
	var mf := int(d.get("min_floor", 0))
	var r := int(rg.get("r", 0))
	for rot: int in _rots(type):
		var k := sim.fp(type, rot)
		for z: int in range(maxi(mf, fp0.z - int(rg.get("up", 0)) - k.z + 1), mini(state.floors_unlocked, fp0.z + int(rg.get("down", 0)) + 1)):
			for x: int in range(maxi(0, fp0.x - r - k.x + 1), mini(sim.W - k.x + 1, fp0.x + r + 1)):
				for y: int in range(maxi(0, fp0.y - r - k.y + 1), mini(sim.H - k.y + 1, fp0.y + r + 1)):
					var p := Vector3i(x, y, z)
					if not _free(state, p, k):
						continue
					if not Cover.reach_b(p, k.x, k.y, k.z, rg, first):
						continue
					if bool(d.get("needs_sky", false)) and not _sky_open(state, p, k):
						continue
					var n := 0
					for t: Dictionary in targets:
						if Cover.reach_b(p, k.x, k.y, k.z, rg, t):
							n += 1
					var res := 0
					for q: Vector3i in Cover.cells_of(p, k.x, k.y, 1):
						if not _reserved(q):
							res += 1
					var score := n * 10 - res * 4 - z
					if score > bs:
						bs = score
						best = [p, rot, n]
	return best


## 자리 내기: 범위 안(또는 아무 데나)에서 낮은 계층 주거만 있는 자리를 허문다(주거 철거는 무료, 주민은 빈집을 찾는다).
func _carve(state: CityState, type: String, target: Variant) -> Variant:
	var d := sim.bdef(type)
	var rg := Cover.rng_of(d)
	var best: Variant = null
	var bs := 1 << 30
	var mf := int(d.get("min_floor", 0))
	var x0 := 0
	var y0 := 0
	var x1 := sim.W
	var y1 := sim.H
	var z0 := mf
	var z1 := state.floors_unlocked
	if target is Dictionary and not rg.is_empty():
		var tp: Vector3i = target["pos"]
		var r := int(rg["r"])
		x0 = maxi(0, tp.x - r - 3)
		x1 = mini(sim.W, tp.x + r + 2)
		y0 = maxi(0, tp.y - r - 3)
		y1 = mini(sim.H, tp.y + r + 2)
		z0 = maxi(mf, tp.z - int(rg["up"]) - 1)
		z1 = mini(state.floors_unlocked, tp.z + int(rg["down"]) + 1)
	for rot: int in _rots(type):
		var k := sim.fp(type, rot)
		for z: int in range(z0, mini(z1, state.floors_unlocked - k.z + 1)):
			for x: int in range(x0, mini(x1, sim.W - k.x + 1)):
				for y: int in range(y0, mini(y1, sim.H - k.y + 1)):
					var o := Vector3i(x, y, z)
					if target is Dictionary and not rg.is_empty() and not Cover.reach_b(o, k.x, k.y, k.z, rg, target):
						continue
					var score := z * 3
					var ok := true
					for q: Vector3i in Cover.cells_of(o, k.x, k.y, k.z):
						if not state.cells.has(q):
							continue
						var b: Dictionary = state.buildings.get(int(state.cells[q]["bid"]), {})
						if b.get("kind", "") != "house" or int(b["tier"]) > int(c("carve_max_tier", 2)) or b.get("upgrading") != null:
							ok = false
							break
						score += 10 * int(b["tier"]) + int(b["residents"])
					if ok and score < bs and (not bool(d.get("needs_sky", false)) or _sky_open(state, o, k)):
						bs = score
						best = [o, rot]
	if best == null:
		return null
	var k2 := sim.fp(type, int(best[1]))
	for q: Vector3i in Cover.cells_of(best[0], k2.x, k2.y, k2.z):
		if state.cells.has(q):
			cmd(state, "demolish", {"pos": q})
	_block("자리 내려고 주거를 허묾")
	return best


func _labor_ok(state: CityState, type: String) -> bool:
	for tk: String in sim.bdef(type).get("workforce", {}):
		var t := int(tk.substr(1))
		var l: Dictionary = state.labor.get(t, {"have": 0, "need": 0.0})
		if float(l["have"]) - float(l["need"]) < float(sim.bdef(type)["workforce"][tk]):
			return false
	return true


func _afford(state: CityState, type: String, critical: bool) -> bool:
	var d := sim.bdef(type)
	var cost := float(d.get("cost", {}).get("money", 0))
	if state.money - (0.0 if critical else _save) < cost + float(c("money_reserve", 40)):
		_block("돈 부족으로 %s 보류" % d.get("name", type))
		if critical:
			_save = maxf(_save, cost + float(c("money_reserve", 40)))
			var want: Dictionary = state.flags["bot"].get("want", {})
			if not want.has(type):
				want[type] = [cost + float(c("money_reserve", 40)), state.econ_days, float(_count(state, type))]
			state.flags["bot"]["want"] = want
		return false
	for g: String in d.get("cost", {}).get("goods", {}):
		var keep := 0.0 if d.get("landmark", false) or critical else _keep(state, g)   # 꼭 필요한 시설은 명소 몫을 남기지 않는다
		if float(state.stock.get(g, 0.0)) < float(d["cost"]["goods"][g]) + keep:
			if g == "parts" or g == "scrap":
				_buy_extra(state, g)
			_block("%s 부족으로 %s 보류" % [sim.gname(g), d.get("name", type)])
			return false
	return true


## 짓기. targets가 있으면 그것을 덮는 자리, 없으면 일반 자리. 반환 = 성공.
func _try_build(state: CityState, type: String, critical: bool = true, targets: Array = [], labor_check: bool = true) -> bool:
	if not sim.is_unlocked(state, type):
		return false
	var d := sim.bdef(type)
	if d.has("blueprint") and not state.flags.get("blueprints", {}).has(str(d["blueprint"])):
		return false
	if labor_check and not _labor_ok(state, type):
		_block("인력 부족으로 %s 보류" % d.get("name", type))
		# 어느 계층 일손이 모자라 못 지었는지 기억 → 승급이 그 계층을 채우게(교착 방지)
		var lw: Dictionary = state.flags["bot"].get("labor_want", {})
		for tk: String in d.get("workforce", {}):
			var t := int(tk.substr(1))
			var l: Dictionary = state.labor.get(t, {"have": 0, "need": 0.0})
			if float(l["have"]) - float(l["need"]) < float(d["workforce"][tk]):
				lw[str(t)] = state.econ_days
		state.flags["bot"]["labor_want"] = lw
		return false
	if not _afford(state, type, critical):
		return false
	var p: Variant = null
	if targets.is_empty() and _nospot.has(type):
		p = null
	else:
		p = _cover_spot(state, type, targets) if not targets.is_empty() else _spot(state, type, _center(state))
	if p == null and targets.is_empty():
		_nospot[type] = true
	if p == null and critical and bool(c("carve", true)) and _carves < 2:
		_carves += 1
		p = _carve(state, type, targets[0] if not targets.is_empty() else null)
	if p == null:
		_block("자리 부족으로 %s 보류" % d.get("name", type))
		return false
	var r := cmd(state, "build", {"type": type, "pos": p[0], "rot": p[1]})
	if not r.get("ok", false):
		_block(str(r.get("reason", "")))
		return false
	_builds += 1
	_cnt[type] = int(_cnt.get(type, 0)) + 1
	_sup.clear()
	return true


# ------------------------------------------------------------------ 탐험
func _explore(state: CityState) -> void:
	if not sim.enabled.has("expeditions"):
		return
	var need_q := _count(state, "expedition_base") < int(c("teams", 3))
	for t: Dictionary in state.teams:
		if t["state"] == "idle" or t["state"] == "done" or (t["state"] == "out" and state.econ_days + 1e-9 >= float(t.get("completes_at", 0.0))):
			need_q = true
	if not need_q:
		return
	var bases := _count(state, "expedition_base")
	if bases < int(c("teams", 3)):
		var need_money := 120.0 if bases == 0 else float(c("base_money", 600)) * float(bases)
		if state.money - _save >= need_money:
			_try_build(state, "expedition_base", bases == 0)
	var q: Dictionary = sim.query(state, "expeditions")
	for t: Dictionary in q["teams"]:
		if t["state"] == "done":
			cmd(state, "expedition_claim", {"team": int(t["id"])})
	q = sim.query(state, "expeditions")
	for t: Dictionary in q["teams"]:
		if t["state"] != "idle" or t.get("retired", false):
			continue
		var dest := _choose_dest(state, q)
		if dest.is_empty():
			continue
		var prov := _meal_rich(state) and bool(c("provision", true))
		var args := {"team": int(t["id"]), "dest": dest["id"], "provision": prov}
		if not (dest["picks"] as Array).is_empty():
			args["pick"] = _family_need(state, dest)
		var r := cmd(state, "expedition_send", args)
		if not r.get("ok", false) and prov:
			args["provision"] = false
			r = cmd(state, "expedition_send", args)
		if not r.get("ok", false):
			_block("탐험 못 보냄: %s" % r.get("reason", ""))
		q = sim.query(state, "expeditions")


func _meal_rich(state: CityState) -> bool:
	var have := 0.0
	for g: String in ["cans", "wonton", "burger"]:
		have += float(state.stock.get(g, 0.0))
	return have > 80.0


## 세 계열 중 지금 가장 필요한 것(집중형은 자기 계열, 단 명소 몫은 모은다).
func _family_need(state: CityState, dest: Dictionary = {}) -> String:
	var fam := str(c("family", ""))
	var mats: Array = sim.db["upgrade_costs"]["materials"]
	for m: String in mats:
		if _keep(state, m) > float(state.stock.get(m, 0.0)) and (fam == "" or m != fam):
			if dest.is_empty() or _pickable(dest, m):
				return m
	if fam != "" and (dest.is_empty() or _pickable(dest, fam)):
		return fam
	var best := ""
	for m: String in mats:
		if (dest.is_empty() or _pickable(dest, m)) and (best == "" or float(state.stock.get(m, 0.0)) < float(state.stock.get(best, 0.0))):
			best = m
	return best if best != "" else str(mats[0])


func _pickable(dest: Dictionary, m: String) -> bool:
	for p: Dictionary in dest.get("picks", []):
		if str(p["good"]) == m:
			return true
	return false


## 상품 하나의 가치(지금 필요한 정도).
func _value(state: CityState, g: String) -> float:
	var fam := str(c("family", ""))
	var have := float(state.stock.get(g, 0.0))
	match g:
		"wood", "metal", "concrete":
			if _keep(state, g) > have:
				return 1.6
			if fam != "":
				return 1.2 if g == fam else 0.15
			return 1.0 if g == _family_need(state) else 0.7
		"parts":
			return float(c("parts_value", 40)) if have < _parts_want(state) else 3.0
		"elec_scrap":
			var need := float(_dem.get("elec_scrap", 0.0))
			if need > 0.0 and have < need * 3.0:
				return 1.5
			return 0.9 if have < 60.0 and _pop(state, 3) > 0.0 else 0.25
		"scrap":
			return 0.4 if have < 80.0 else 0.08
	return 0.1


func _parts_want(state: CityState) -> float:
	var w := 4.0
	if _pop(state, 3) > 0.0:
		w = 10.0
	if _pop(state, 4) > 0.0:
		w = 24.0
	return w + _keep(state, "parts")


func _choose_dest(state: CityState, q: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_v := -1.0
	var taken := {}
	for t: Dictionary in q["teams"]:
		if t["state"] == "out":
			taken[str(t["dest"])] = true
	for d: Dictionary in q["dests"]:
		if not d["known"] or float(d["cost"]["money"]) > state.money - _save - 60.0:
			continue
		var days := maxf(0.05, float(d["days"]))
		var pct := float(d.get("stock_pct", 1.0))
		var amt := (float(d["primary"]["min"]) + float(d["primary"]["max"])) * 0.5 * clampf(pct * 1.5, 0.2, 1.0)
		var pg := str(d["primary"]["good"])
		if pg == "" or pg == "고른 자재":
			pg = _family_need(state, d)
		var v := amt * _value(state, pg)
		if str(d["band"]) == "far":
			v += _value(state, "parts") * 2.5
		elif str(d["band"]) == "mid":
			v += _value(state, "elec_scrap") * 10.0
		elif str(d["id"]) == "junk_yard":
			v += _value(state, "elec_scrap") * 3.0
		v = v / days
		if int(d["visits"]) == 0 and str(d["band"]) != "near":
			v += 30.0     # 처음 가 보는 곳: 거래처·새 던전 발견
		if taken.has(str(d["id"])):
			v *= 0.6      # 같은 던전에 몰리지 않게(재고)
		if v > best_v:
			best_v = v
			best = d
	return best


# ------------------------------------------------------------------ 수리(불)
func _repair(state: CityState) -> void:
	if not sim.enabled.has("hazards"):
		return
	var n := 0
	for b: Dictionary in sim.cover(state)["all"]:
		if str(b.get("burn", "")) == "burnt" and b.get("repair") == null:
			var r := cmd(state, "repair", {"bid": int(b["id"])})
			if not r.get("ok", false):
				_block("수리 못 함: %s" % r.get("reason", ""))
				if str(r.get("code", "")) == "goods":
					_buy_extra(state, "scrap")
				break
			n += 1
			if n >= int(c("repairs_per_act", 6)):
				break


# ------------------------------------------------------------------ 물·전기
func _utilities(state: CityState) -> void:
	if _houses(state) == 0:
		return
	var w: Dictionary = state.util.get("water", {})
	var proj_w := float(w.get("demand", 0.0)) * 1.15 + 4.0
	var sw := float(w.get("supply", 0.0)) + _site_supply(state, "water")
	# 모자라는 만큼 한 손길에 여러 개(큰 도시는 하루에 수백씩 는다). 돈이 넉넉하면 자리 적게 먹는 외부 연결부터.
	var order: Array = c("water_order", ["water_plant", "water_tank", "rain_catcher", "water_pipe"]).duplicate()
	if state.money > float(c("ext_money", 6000)):
		order.erase("water_pipe")
		order.insert(1, "water_pipe")
	for _i: int in 4:
		if sw >= proj_w:
			break
		var built := false
		for t: String in order:
			if _try_build(state, t):
				sw += float(sim.bdef(t).get("supply", {}).get("water", 0))
				built = true
				break
		if not built:
			break
	var p: Dictionary = state.util.get("power", {})
	# 꼭 필요한 전기 = 계층 1인 전기(박힌 돌부터) + 시설 부하. 월세 전사의 "등불 대신 전기"는 남을 때만 쓰는 것이라 세지 않는다.
	var pdem := float(p.get("fac_demand", 0.0))
	for b: Dictionary in sim.cover(state)["houses"]:
		pdem += float(b["residents"]) * float(sim.tier(int(b["tier"])).get("power", 0.0))
	if _pop(state, 2) >= float(c("power_at_t2", 30)) or sim.is_unlocked(state, "market_hall"):
		pdem = maxf(pdem, 30.0)
	var sp := float(p.get("supply", 0.0)) + _site_supply(state, "power")
	var porder: Array = c("power_order", ["power_waste", "power_plant", "gen_small", "power_tap"]).duplicate()
	if state.money > float(c("ext_money", 6000)):
		porder.erase("power_tap")
		porder.insert(2, "power_tap")
	for _i: int in 4:
		if pdem <= 0.0 or sp >= pdem * 1.15 + 2.0:
			break
		var built := false
		for t: String in porder:
			if _try_build(state, t):
				sp += float(sim.bdef(t).get("supply", {}).get("power", 0))
				built = true
				break
		if not built:
			break


func _site_supply(state: CityState, u: String) -> float:
	var s := 0.0
	for bid: int in sim.cover(state)["sites"]:
		s += float(sim.bdef(str(state.buildings[bid]["type"])).get("supply", {}).get(u, 0))
	return s


# ------------------------------------------------------------------ 방재: 쓰이는 칸을 소방·수거·의원 범위로 덮는다
func _hazards(state: CityState) -> void:
	if not sim.enabled.has("hazards"):
		return
	var fire_on := state.floors_unlocked >= 2
	var dis_on := state.floors_unlocked >= 3
	var hzc: Dictionary = sim.cover(state).get("hz", {})
	if fire_on:
		_cover_tag(state, "fire", hzc.get("fire", {}), c("fire_order", ["fire_station", "fire_bucket"]), true)
	if dis_on:
		_cover_tag(state, "trash", hzc.get("trash", {}), ["trash_guild"], false)
		_cover_tag(state, "clinic", hzc.get("clinic", {}), ["clinic"], false)


func _cover_tag(state: CityState, tag: String, covered: Dictionary, order: Array, all_buildings: bool) -> void:
	var targets: Array = []
	var cov := sim.cover(state)
	for b: Dictionary in (cov["all"] if all_buildings else cov["houses"]):
		if covered.has(int(b["id"])):
			continue
		if b["kind"] == "house" and int(b["residents"]) == 0:
			continue
		targets.append(b)
	# 공사 중인 같은 종류 시설이 덮을 대상은 빼고 본다
	for bid: int in cov["sites"]:
		var s: Dictionary = state.buildings[bid]
		if tag in sim.bdef(str(s["type"])).get("services", []):
			targets = _minus(targets, s)
	if targets.is_empty():
		return
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector3i = a["pos"]
		var pb: Vector3i = b["pos"]
		return pa.z * 1000 + pa.x * 20 + pa.y < pb.z * 1000 + pb.x * 20 + pb.y)
	for i: int in int(c("cover_per_act", 2)):
		if targets.is_empty():
			break
		var done := false
		for t: String in order:
			if not sim.is_unlocked(state, t):
				continue
			if _try_build(state, t, true, targets):
				done = true
				break
		if not done:
			return
		var last: Dictionary = {}
		for b: Dictionary in state.buildings.values():
			if b["kind"] == "site" and tag in sim.bdef(str(b["type"])).get("services", []):
				if last.is_empty() or int(b["id"]) > int(last["id"]):
					last = b
		if last.is_empty():
			return
		targets = _minus(targets, last)


func _minus(targets: Array, s: Dictionary) -> Array:
	var k := Cover.dims(s)
	var rg := Cover.rng_of(sim.bdef(str(s["type"])))
	var out: Array = []
	for t: Dictionary in targets:
		if not Cover.reach_b(s["pos"], k.x, k.y, k.z, rg, t):
			out.append(t)
	return out


# ------------------------------------------------------------------ 시장·서비스: 원인이 "범위 밖/등급 부족"인 주거를 덮는다
func _markets_services(state: CityState) -> void:
	var want := {}     # 시설 type → [주거…]
	var crit := {}
	var sup_of := {}   # 수요 id → 채울 시설(이번 손길 캐시)
	for b: Dictionary in sim.cover(state)["houses"]:
		for nid: String in b.get("needs", {}):
			var rec: Dictionary = b["needs"][nid]
			var cause := str(rec.get("cause", ""))
			if cause != "range" and cause != "grade":
				continue
			var n := sim.item("needs", nid)
			if n.get("role", "") == "luxury" and not bool(c("luxury", true)):
				continue
			if not sup_of.has(nid):
				sup_of[nid] = _supplier_for(state, n)
			var type: String = sup_of[nid]
			if type == "":
				continue
			if not want.has(type):
				want[type] = []
			want[type].append(b)
			if n.get("role", "") != "luxury":
				crit[type] = true
	var built := 0
	var order: Array = want.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return (want[a] as Array).size() > (want[b] as Array).size())
	for type: String in order:
		if built >= int(c("services_per_act", 3)):
			break
		if not crit.has(type) and (state.money < float(c("luxury_money", 2500)) or (want[type] as Array).size() < 6):
			continue
		var tg: Array = want[type]
		for bid: int in sim.cover(state)["sites"]:
			if str(state.buildings[bid]["type"]) == type:
				tg = _minus(tg, state.buildings[bid])
		if tg.is_empty():
			continue
		if _try_build(state, type, crit.has(type), tg):
			built += 1


func _supplier_for(state: CityState, n: Dictionary) -> String:
	var grade := 0
	var tags: Array = []
	for o: Dictionary in n.get("options", []):
		if o.has("market"):
			grade = maxi(grade, int(o["market"]))
		elif o.has("good"):
			grade = maxi(grade, int(sim.good(o["good"]).get("grade", 1)))
		elif o.has("service"):
			tags.append(str(o["service"]))
	for tag: String in tags:
		var s := _unlocked_service(state, tag)
		if s != "":
			return s
	if grade > 0:
		for gr: int in range(grade, 5):
			for bid: String in sim.items("buildings"):
				if int(sim.bdef(bid).get("market", 0)) == gr and sim.is_unlocked(state, bid):
					return bid
	return ""


func _unlocked_service(state: CityState, tag: String) -> String:
	for bid: String in sim.items("buildings"):
		var d := sim.bdef(bid)
		if tag in d.get("services", []) and sim.is_unlocked(state, bid) and float(d.get("vice", {}).get("income", 0.0)) <= 0.0 \
				and not d.get("landmark", false):
			return bid
	return ""


# ------------------------------------------------------------------ 생산: 상품별 수요 추정 → 생산 시설
## 상품별 경제일당 수요(정원 기준 주민 수요 + 시설 원료). 승급 직전인 집은 다음 계층 수요도 절반(대비).
func _demand(state: CityState) -> Dictionary:
	var dem := {}
	var pop := {}
	var ahead := {}
	for b: Dictionary in sim.cover(state)["houses"]:
		var t := int(b["tier"])
		pop[t] = float(pop.get(t, 0.0)) + float(b["cap"])
		if b.get("ready", false) and t < sim.max_tier() and int(ahead.get(t, 0)) < int(c("ahead_houses", 8)):
			ahead[t] = int(ahead.get(t, 0)) + 1     # 곧 승급할 집 몇 채만 미리 센다(전부 세면 과잉 건설)
			pop[t + 1] = float(pop.get(t + 1, 0.0)) + float(sim.tier(t + 1).get("cap", 0)) * 0.5
	for nid: String in sim.items("needs"):
		var n := sim.item("needs", nid)
		var r := float(pop.get(int(n["tier"]), 0.0))
		if r <= 0.0 or not n.has("amount"):
			continue
		if n.get("role", "") == "luxury" and not bool(c("luxury", true)):
			continue
		for o: Dictionary in n["options"]:
			if o.has("good"):
				dem[str(o["good"])] = float(dem.get(str(o["good"]), 0.0)) + r * float(n["amount"]) / float(maxi(1, (n["options"] as Array).size()))
	if bool(c("provision", true)):
		dem["cans"] = float(dem.get("cans", 0.0)) + 10.0
	for _pass: int in 2:
		var cap := {}
		for b: Dictionary in state.buildings.values():
			if b["kind"] == "facility" or b["kind"] == "site":
				for g: String in sim.bdef(str(b["type"])).get("recipe", {}).get("out", {}):
					cap[g] = float(cap.get(g, 0.0)) + float(sim.bdef(str(b["type"]))["recipe"]["out"][g])
		var raw := {}
		for b: Dictionary in state.buildings.values():
			if b["kind"] != "facility" and b["kind"] != "site":
				continue
			var rec: Dictionary = sim.bdef(str(b["type"])).get("recipe", {})
			var u := 0.0
			for g: String in rec.get("out", {}):
				u = maxf(u, minf(1.0, float(dem.get(g, 0.0)) * 1.2 / maxf(float(cap.get(g, 1.0)), 1e-6)))
			for g: String in rec.get("in", {}):
				raw[g] = float(raw.get(g, 0.0)) + float(rec["in"][g]) * u
		for g: String in raw:
			dem["raw:" + g] = raw[g]
	for k: String in dem.keys():
		if k.begins_with("raw:"):
			dem[k.substr(4)] = float(dem.get(k.substr(4), 0.0)) + float(dem[k])
			dem.erase(k)
	return dem


func _supply(state: CityState, g: String) -> float:
	if _sup.has(g):
		return float(_sup[g])
	var s := 0.0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "facility" or b["kind"] == "site":
			if str(b.get("burn", "")) == "burnt":
				continue
			s += float(sim.bdef(str(b["type"])).get("recipe", {}).get("out", {}).get(g, 0.0)) * 0.9
	for k: Dictionary in state.contracts:
		if k["good"] == g and not k.get("paused", false):
			s += (1.0 if k["dir"] == "import" else -1.0) * float(k["qty"]) * 24.0 / float(k["interval_h"])
	_sup[g] = s
	return s


func _producer(state: CityState, g: String) -> String:
	var best := ""
	var best_v := -1.0
	for t: String in c("producer_order", []):
		if sim.bdef(t).get("recipe", {}).get("out", {}).has(g) and sim.is_unlocked(state, t):
			return t
	for t: String in sim.items("buildings"):
		var d := sim.bdef(t)
		if d.get("recipe", {}).get("out", {}).has(g) and sim.is_unlocked(state, t) and not d.has("blueprint"):
			if d.has("vice") and not bool(c("vice", true)):
				continue
			var v := float(d["recipe"]["out"][g]) / maxf(1.0, float(d.get("cost", {}).get("money", 1)))
			if t == "scrapyard" and g != "scrap":
				v *= 0.01
			if v > best_v:
				best_v = v
				best = t
	return best


var _starving: Dictionary = {}


func _production(state: CityState) -> void:
	_starving.clear()
	var order: Array = MEAL_GOODS.duplicate()
	for g: String in _dem:
		if not (g in order):
			order.append(g)
	var margin := 1.15 * (1.6 if bool(c("export_extra", false)) else 1.0)
	for g: String in order:
		if _builds >= int(c("builds_per_act", 4)):
			break
		if g in ["fish", "liquor"]:
			continue
		var need := float(_dem.get(g, 0.0))
		if need <= 0.05:
			continue
		if _supply(state, g) >= need * margin:
			continue
		var t := _producer(state, g)
		if t == "":
			continue
		# 이미 있는 같은 시설이 물·전기·일손 때문에 덜 돌면 더 짓지 않는다(원인을 먼저 — 물·전기·칠하기가 따로 맡는다)
		if _starving.is_empty():
			_starving["-"] = true
			for b: Dictionary in sim.cover(state)["facs"]:
				if str(b.get("cause", "")) in ["water", "power", "staff"] and float(b.get("eff", 1.0)) < 0.8:
					_starving[str(b["type"])] = true
		if _starving.has(t):
			_block("%s이(가) 물·전기·일손이 모자라 덜 돌아 더 짓지 않음" % sim.bdef(t).get("name", t))
			continue
		# 2단 사슬: 원료가 이미 모자라면 이 시설 대신 원료 시설을 먼저 짓는다
		var short_in := ""
		for gi: String in sim.bdef(t).get("recipe", {}).get("in", {}):
			if _supply(state, gi) < float(_dem.get(gi, 0.0)) * 1.05 + float(sim.bdef(t)["recipe"]["in"][gi]) * 0.5:
				short_in = gi
				break
		if short_in != "":
			if short_in in ["fish", "liquor"]:
				# 수입 원료: 시설을 먼저 지으면 교역(_contracts)이 그 수요를 보고 계약한다
				if _count(state, t) == 0:
					_try_build(state, t, g in MEAL_GOODS)
				continue
			var ti := _producer(state, short_in)
			if ti != "":
				_try_build(state, ti, g in MEAL_GOODS)
			continue
		_try_build(state, t, g in MEAL_GOODS)
	# 고물: 시설·수리 재료
	if float(state.stock.get("scrap", 0.0)) < 60.0 and _count(state, "scrapyard") < 1 + _houses(state) / 120:
		_try_build(state, "scrapyard")
	# 창고: 저장 한도가 3일치 소비보다 작으면
	var biggest := 0.0
	for g: String in _dem:
		biggest = maxf(biggest, float(_dem[g]))
	if biggest * 3.0 > sim.cap_of(state, "cans") * 0.9 and _sites_of(state, "infra") == 0:
		_try_build(state, "warehouse", false)


# ------------------------------------------------------------------ 교역(중반): 사치품 수입 + 남는 것 수출
func _contracts(state: CityState) -> void:
	if not sim.enabled.has("contracts") or not bool(c("trade", true)):
		return
	var need_import := float(_dem.get("fish", 0.0)) + float(_dem.get("liquor", 0.0))
	if _count(state, "trade_post") == 0:
		if sim.is_unlocked(state, "trade_post") and (need_import > 0.0 or state.money > float(c("trade_money", 3000))):
			_try_build(state, "trade_post", need_import > 0.0)
		return
	var q: Dictionary = sim.query(state, "contracts")
	var max_slots := int(q["slots"]["max"])
	var changed := false
	for g: String in ["fish", "liquor"]:
		var need := float(_dem.get(g, 0.0)) * 1.15
		var mine: Array = []
		var have := 0.0
		for k: Dictionary in state.contracts:
			if k["good"] == g and k["dir"] == "import":
				mine.append(k)
				have += float(k["qty"]) * 24.0 / float(k["interval_h"])
		if need <= 0.05 and mine.is_empty():
			continue
		if have >= need and have <= need * 2.5 + 3.0:
			continue
		var best: Dictionary = {}
		for o: Dictionary in q["offers"]:
			if o["good"] == g and o["dir"] == "import" and o["known"]:
				if best.is_empty() or float(o["sizes"][0]["price"]) < float(best["sizes"][0]["price"]):
					best = o
		if best.is_empty():
			continue
		var sizes: Array = best["sizes"]
		var rate := func(i: int) -> float: return float(sizes[i]["qty"]) * 24.0 / float(sizes[i]["interval_h"])
		var plan: Array = []
		var left := need
		var big := sizes.size() - 1
		while left > float(rate.call(big)) and plan.size() < 3:
			plan.append(big)
			left -= float(rate.call(big))
		if left > 0.05:
			for i: int in sizes.size():
				if float(rate.call(i)) >= left or i == big:
					plan.append(i)
					break
		var used_other := state.contracts.size() - mine.size()
		if used_other + plan.size() > max_slots:
			if _sites_of(state, "infra") == 0 and _count(state, "trade_post") < int(c("max_trade_posts", 4)):
				_try_build(state, "trade_post")
			_block("계약 자리가 모자람(%s)" % sim.gname(g))
			continue
		for k: Dictionary in mine:
			cmd(state, "contract_cancel", {"id": int(k["id"])})
		for i: int in plan:
			cmd(state, "contract_sign", {"offer": best["id"], "size": i})
		changed = true
	if not changed:
		_exports(state, sim.query(state, "contracts"), max_slots - state.contracts.size())


func _exports(state: CityState, q: Dictionary, slots_free: int) -> void:
	var extra := bool(c("export_extra", false))
	if slots_free <= (0 if extra else 1):
		if extra and _sites_of(state, "infra") == 0 and _count(state, "trade_post") < int(c("max_trade_posts", 4)) and state.money > 1500.0:
			_try_build(state, "trade_post", false)
		return
	for o: Dictionary in q["offers"]:
		if o["dir"] != "export" or not o["known"]:
			continue
		var g := str(o["good"])
		var cap := sim.cap_of(state, g)
		if float(state.stock.get(g, 0.0)) > cap * (0.35 if extra else 0.7):
			var dup := false
			for k: Dictionary in state.contracts:
				dup = dup or (k["good"] == g and k["dir"] == "export")
			if not dup:
				cmd(state, "contract_sign", {"offer": o["id"], "size": 2 if extra else 1, "reserve": cap * 0.3})
				return


## 설비 부품·고물 같은 추가 상품: 건재상 계약(작게, 무역관이 있을 때만).
func _buy_extra(state: CityState, g: String) -> void:
	if not bool(c("trade", true)) or _count(state, "trade_post") == 0:
		return
	if g == "parts" and state.money < float(c("parts_buy_money", 4000)):
		return
	for k: Dictionary in state.contracts:
		if k["good"] == g:
			return
	var r := cmd(state, "contract_sign", {"offer": "bd_" + g, "size": 1 if g == "scrap" else 0})
	if not r.get("ok", false):
		_block("%s 구할 계약 자리 없음" % sim.gname(g))


func _trim_builder(state: CityState) -> void:
	for k: Dictionary in state.contracts.duplicate():
		if str(k["partner"]) != "builder":
			continue
		var g := str(k["good"])
		var lim := 14.0 if g == "parts" else 120.0
		if g == "scrap":
			lim = 300.0
		if float(state.stock.get(g, 0.0)) > lim:
			cmd(state, "contract_cancel", {"id": int(k["id"])})


# ------------------------------------------------------------------ 승급
func _upgrades(state: CityState) -> void:
	var mats: Array = sim.db["upgrade_costs"]["materials"]
	var max_per := int(c("upgrades_per_act", 4))
	var done := 0
	var hn := {}
	var hf := {}
	for b: Dictionary in sim.cover(state)["houses"]:
		var t0 := int(b["tier"])
		hn[t0] = int(hn.get(t0, 0)) + 1
		if int(b["residents"]) >= int(b["cap"]) or b.get("upgrading") != null:
			hf[t0] = int(hf.get(t0, 0)) + 1
	var cands: Array = []
	for b: Dictionary in sim.cover(state)["houses"]:
		if b.get("ready", false) and str(b.get("burn", "")) == "" and not b.get("sick", false):
			cands.append(b)
	cands.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool:
		return int(a["tier"]) > int(b2["tier"]) if int(a["tier"]) != int(b2["tier"]) else int(a["id"]) < int(b2["id"]))
	var labor_tiers := {}
	for id2: String in sim.items("buildings"):
		for tk: String in sim.bdef(id2).get("workforce", {}):
			labor_tiers[int(tk.substr(1))] = true
	var mat_wait := 0
	for b: Dictionary in cands:
		if done >= max_per:
			break
		var t := int(b["tier"])
		var nt := t + 1
		if nt > int(c("max_tier", 5)):
			continue
		var ln: Dictionary = state.labor.get(nt, {"have": 0, "need": 0.0})
		var lw: Dictionary = state.flags["bot"].get("labor_want", {})
		var short := float(ln["need"]) > float(ln["have"]) or state.econ_days - float(lw.get(str(nt), -9.0)) < 0.5
		if not short and int(hn.get(nt, 0)) >= int(c("pilot_houses", 3)) and float(hf.get(nt, 0)) < float(c("next_full_ratio", 0.7)) * float(hn.get(nt, 0)):
			_block("%s 주거가 아직 안 차서 승급 보류" % sim.tname(nt))
			continue
		var l: Dictionary = state.labor.get(t, {"have": 0, "need": 0.0})
		var loss := float(b["residents"]) * float(sim.tier(t).get("labor", 1.0))
		if labor_tiers.has(t) and float(l["have"]) - loss - float(l["need"]) < float(c("labor_margin", 2)):
			_block("%s 노동력이 모자라 승급 보류" % sim.tname(t))
			continue
		var cost := sim.item("upgrade_costs", "%dto%d" % [t, t + 1])
		if state.money - _save < float(cost.get("money", 0)) + float(c("money_reserve", 40)):
			_block("돈이 모자라 %s 승급 보류" % sim.tname(t))
			continue
		var best := ""
		var fam := str(c("family", ""))
		for m: String in mats:
			if fam != "" and m != fam:
				continue
			if float(state.stock.get(m, 0.0)) >= float(cost["qty"]) + _keep(state, m) and (best == "" or float(state.stock[m]) > float(state.stock[best])):
				best = m
		if best == "":
			_block("자재가 모자라 승급 보류(T%d→T%d)" % [t, t + 1])
			mat_wait = maxi(mat_wait, t)
			continue
		if mat_wait > t:
			_block("위 계층 승급을 위해 자재를 모으는 중(T%d→T%d 보류)" % [t, t + 1])
			continue
		var ok := true
		for g: String in cost.get("extra", {}):
			if float(state.stock.get(g, 0.0)) < float(cost["extra"][g]) + _keep(state, g):
				_buy_extra(state, g)
				ok = false
		if not ok:
			_block("설비 부품을 모으는 중(T%d→T%d 보류)" % [t, t + 1])
			continue
		var r := cmd(state, "upgrade", {"bids": [int(b["id"])], "material": best})
		if r.get("ok", false):
			done += 1
		else:
			_block(str(r.get("reason", "")))


## 명소(용탑·구청)가 열렸는데 아직 없으면 그 자재를 남겨 둔다.
func _keep(state: CityState, g: String) -> float:
	var k := 0.0
	for lm: String in ["neon_tower", "city_hall"]:
		if sim.is_unlocked(state, lm) and _count(state, lm) == 0:
			k += float(sim.bdef(lm).get("cost", {}).get("goods", {}).get(g, 0))
	return k


# ------------------------------------------------------------------ 주거 칠하기
func _zone(state: CityState) -> void:
	var vacant := 0
	var houses := 0
	for b: Dictionary in sim.cover(state)["houses"]:
		houses += 1
		vacant += maxi(0, int(b.get("target", b["cap"])) - int(b["residents"]))
		if int(b["residents"]) == 0 and str(b.get("burn", "")) == "":
			vacant += 2
	var l1: Dictionary = state.labor.get(1, {"have": 0, "need": 0.0})
	var t1_short := float(l1["have"]) < float(l1["need"]) - 0.5
	if vacant > int(c("zone_when_vacancy_below", 10)) and not t1_short:
		return
	if houses > 40 and float(l1["have"]) - float(l1["need"]) > float(c("t1_spare_stop", 60)) and not t1_short:
		_block("굴러온 돌 일손이 남아 주거 확장 보류")
		return
	if houses > 0 and _supply(state, "cans") < float(_dem.get("cans", 0.0)) and not t1_short:
		_block("통조림이 모자라 주거 확장 보류")
		return
	if state.money - _save < float(c("zone_money", 60)):
		_block("돈이 모자라 주거 확장 보류")
		return
	for u: String in ["water", "power"]:
		var x: Dictionary = state.util.get(u, {})
		if float(x.get("demand", 0.0)) > 1.0 and float(x.get("supply", 0.0)) < float(x.get("demand", 0.0)) * 0.98 and not t1_short:
			_block("물·전기가 모자라 주거 확장 보류")
			return
	var per_floor := int(c("houses_per_floor", 190))
	var batch := int(c("zone_batch", 12))
	var cells: Array = []
	var cx := float(sim.W - 1) / 2.0
	var cy := float(sim.H - 1) / 2.0
	for z: int in state.floors_unlocked:
		var on_floor: int = (sim.cover(state)["floor_houses"].get(z, []) as Array).size()
		if on_floor >= per_floor:
			continue
		var order: Array = []
		for x: int in sim.W:
			for y: int in sim.H:
				var p := Vector3i(x, y, z)
				if not state.cells.has(p) and not _reserved(p):
					order.append(p)
		order.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			var da := maxf(absf(a.x - cx), absf(a.y - cy))
			var db := maxf(absf(b.x - cx), absf(b.y - cy))
			if da != db:
				return da < db
			return a.x * 100 + a.y < b.x * 100 + b.y)
		for p: Vector3i in order:
			if cells.size() >= batch or on_floor + cells.size() >= per_floor:
				break
			cells.append(p)
		if not cells.is_empty():
			break
	if cells.is_empty():
		_block("칠할 칸이 없음")
		return
	var r := cmd(state, "zone", {"cells": cells})
	if not r.get("ok", false):
		_block(str(r.get("reason", "")))


# ------------------------------------------------------------------ 후반: 연구·명소·음성·정책
func _late(state: CityState) -> void:
	_trim_builder(state)
	if sim.enabled.has("research") and bool(c("research", true)):
		var rq: Dictionary = sim.query(state, "research")
		if rq["can"]:
			var pick: Dictionary = {}
			for n: Dictionary in rq["nodes"]:
				if n["state"] == "ready" and (pick.is_empty() or float(n["cost"]) < float(pick["cost"])):
					pick = n
			if not pick.is_empty() and state.money - _save >= float(pick["cost"]) + float(c("research_reserve", 1500)):
				cmd(state, "research_start", {"id": pick["id"]})
		elif _count(state, "study") == 0 and sim.is_unlocked(state, "study") and state.money > 3000.0:
			_try_build(state, "study", false)
	for lm: String in ["neon_tower", "city_hall"]:
		if sim.is_unlocked(state, lm) and _count(state, lm) == 0:
			var d := sim.bdef(lm)
			var ok := true
			for g: String in d.get("cost", {}).get("goods", {}):
				if float(state.stock.get(g, 0.0)) < float(d["cost"]["goods"][g]):
					ok = false
					_block("%s: %s 모으는 중" % [d.get("name", lm), sim.gname(g)])
			if ok:
				_try_build(state, lm, true, [], false)
	if bool(c("vice", true)):
		for t: String in c("vice_order", ["gambling_den", "callcenter", "casino"]):
			if sim.is_unlocked(state, t) and _count(state, t) < int(c("vice_max", 1)) and state.money - _save > float(sim.bdef(t).get("cost", {}).get("money", 0)) * 2.0:
				_try_build(state, t, false)
		if sim.enabled.has("policies"):
			var pq: Dictionary = sim.query(state, "policies")
			if state.heat >= float(c("bribe_at", 60)) and int(pq["slots"]["used"]) < int(pq["slots"]["max"]) and not state.policies.has("bribes"):
				cmd(state, "policy_set", {"id": "bribes", "on": true})
			elif state.heat < 20.0 and state.policies.has("bribes"):
				cmd(state, "policy_set", {"id": "bribes", "on": false})
	for pid: String in c("policies", []):
		if not state.policies.has(pid) and sim.can(state, "policy_set", {"id": pid, "on": true}).get("ok", false):
			cmd(state, "policy_set", {"id": pid, "on": true})
