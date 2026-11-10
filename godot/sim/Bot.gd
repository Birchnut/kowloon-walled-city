class_name Bot
extends RefCounted
## Bot — 자동 플레이어(data/sim/bots.json). 사람처럼 Sim.apply()/query()만 쓴다(규칙을 건드리지 않는다).
## "balanced": 주거를 칠하고, 물·전기·시장·서비스·생산·계약을 수요에 맞춰 붙이고, 노동력이 남는 만큼 승급한다.
## 탐험(B 파트)이 아직 없으므로 세 계열 자재는 debug add_stock으로 "탐험 수확"을 흉내 낸다(expedition_per_day, 리포트에 표시).
## 봇의 기억은 state.flags["bot"].

var sim: Sim
var id: String = ""
var conf: Dictionary = {}
var blocked: Dictionary = {}       # 이유 → 횟수(리포트용)
var _save: float = 0.0             # 꼭 필요한 시설을 위해 모으는 돈(이번 손길 동안 덜 급한 지출을 막는다)


func _init(s: Sim, bot_id: String) -> void:
	sim = s
	id = bot_id
	conf = sim.item("bots", bot_id)


func c(key: String, def: Variant) -> Variant:
	return conf.get(key, def)


func _block(why: String) -> void:
	blocked[why] = int(blocked.get(why, 0)) + 1


# ------------------------------------------------------------------ 한 번의 손길(경제 1시간마다)
func act(state: CityState) -> void:
	var mem: Dictionary = state.flags.get("bot", {"exp_acc": 0.0})
	state.flags["bot"] = mem
	_save = 0.0
	_expedition(state, mem)
	_utilities(state)
	_upgrades(state)       # 승급 버튼이 뜨면 먼저 누른다(사람처럼)
	_production(state)
	_markets_services(state)
	_contracts(state)
	_zone(state)


func cmd(state: CityState, name: String, args: Dictionary) -> Dictionary:
	var r := sim.apply(state, name, args)
	return r


# ------------------------------------------------------------------ 탐험 흉내
func _expedition(state: CityState, mem: Dictionary) -> void:
	var per_day := float(c("expedition_per_day", 30))
	var now := state.econ_days
	var last := float(mem.get("exp_t", now))
	mem["exp_t"] = now
	mem["exp_acc"] = float(mem.get("exp_acc", 0.0)) + per_day * (now - last)
	var mats: Array = sim.db["upgrade_costs"]["materials"]
	while float(mem["exp_acc"]) >= 6.0:
		# 가장 적은 자재를 채운다(근거리 탐험 한 번 ≈ 10~12개)
		var best := str(mats[0])
		for m: String in mats:
			if float(state.stock.get(m, 0.0)) < float(state.stock.get(best, 0.0)):
				best = m
		cmd(state, "debug", {"op": "add_stock", "good": best, "n": 6})
		mem["exp_acc"] = float(mem["exp_acc"]) - 6.0


# ------------------------------------------------------------------ 자리 찾기
func _free(state: CityState, p: Vector3i, size: int) -> bool:
	for dx: int in size:
		for dy: int in size:
			var q := Vector3i(p.x + dx, p.y + dy, p.z)
			if q.x >= sim.W or q.y >= sim.H or state.cells.has(q):
				return false
	return p.z < state.floors_unlocked


## near 가까운 빈 자리(origin). 낮은 층을 선호. 주거 예약 칸(_reserved)은 시설에 내주되 맨 나중.
func _spot(state: CityState, size: int, near: Vector3i) -> Variant:
	var best: Variant = null
	var bd := 1 << 30
	for z: int in state.floors_unlocked:
		for x: int in sim.W - size + 1:
			for y: int in sim.H - size + 1:
				var p := Vector3i(x, y, z)
				if not _free(state, p, size):
					continue
				var d := Cover.dist(sim, near, p, size)
				if d >= (1 << 19):
					continue
				d = d * 4 + z
				if size == 1 and _reserved(p):
					d += 1000
				if d < bd:
					bd = d
					best = p
	return best


func _labor_ok(state: CityState, type: String) -> bool:
	for tk: String in sim.bdef(type).get("workforce", {}):
		var t := int(tk.substr(1))
		var l: Dictionary = state.labor.get(t, {"have": 0, "need": 0.0})
		if float(l["have"]) - float(l["need"]) < float(sim.bdef(type)["workforce"][tk]):
			return false
	return true


func _try_build(state: CityState, type: String, near: Vector3i, critical: bool = true) -> bool:
	if not sim.is_unlocked(state, type):
		return false
	if not _labor_ok(state, type):
		_block("인력 부족으로 %s 보류" % sim.bdef(type).get("name", type))
		return false
	var d := sim.bdef(type)
	var cost := float(d.get("cost", {}).get("money", 0))
	if state.money - (0.0 if critical else _save) < cost + float(c("money_reserve", 40)):
		_block("돈 부족으로 %s 보류" % d.get("name", type))
		if critical:
			_save = maxf(_save, cost + float(c("money_reserve", 40)))
		return false
	for g: String in d.get("cost", {}).get("goods", {}):
		if float(state.stock.get(g, 0.0)) < float(d["cost"]["goods"][g]):
			if g == "parts" or g == "scrap":
				_buy_extra(state, g)
			_block("%s 부족으로 %s 보류" % [sim.gname(g), d.get("name", type)])
			return false
	var p: Variant = _spot(state, int(d.get("size", 1)), near)
	if p != null and d.has("range") and Cover.dist(sim, near, p, int(d.get("size", 1))) > int(d["range"]):
		p = null
	if p == null:
		_block("자리 부족으로 %s 보류" % d.get("name", type))
		return false
	var r := cmd(state, "build", {"type": type, "pos": p})
	if not r.get("ok", false):
		_block(str(r.get("reason", "")))
		return false
	return true


func _count(state: CityState, type: String) -> int:
	var n := 0
	for b: Dictionary in state.buildings.values():
		if (b["kind"] == "facility" or b["kind"] == "site") and str(b.get("type", "")) == type:
			n += 1
	return n


func _sites(state: CityState) -> int:
	var n := 0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "site":
			n += 1
	return n


func _center(state: CityState) -> Vector3i:
	return Vector3i(sim.W / 2, sim.H / 2, maxi(0, state.floors_unlocked - 1))


# ------------------------------------------------------------------ 물·전기
func _utilities(state: CityState) -> void:
	var w: Dictionary = state.util.get("water", {})
	var houses := _houses(state)
	if houses == 0:
		return
	var proj_w := float(w.get("demand", 0.0)) * 1.15 + 4.0
	if float(w.get("supply", 0.0)) < proj_w and _sites_of(state, "water") == 0:
		for t: String in c("water_order", ["water_plant", "water_ext", "water_tower", "rain_catcher"]):
			if _try_build(state, t, _center(state)):
				break
	var p: Dictionary = state.util.get("power", {})
	var pdem := float(p.get("demand", 0.0))
	# 토박이가 오기 전(세입자가 늘면) 미리 전기를 깐다
	var t2 := _pop(state, 2)
	if t2 >= float(c("power_before_t3_at_t2", 40)):
		pdem = maxf(pdem, 24.0)
	if pdem > 0.0 and float(p.get("supply", 0.0)) < pdem * 1.15 + 2.0 and _sites_of(state, "power") == 0:
		for t: String in c("power_order", ["power_plant", "generator", "power_ext"]):
			if _try_build(state, t, _center(state)):
				break


func _sites_of(state: CityState, cat: String) -> int:
	var n := 0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "site" and str(sim.bdef(str(b["type"])).get("cat", "")) == cat:
			n += 1
	return n


func _houses(state: CityState) -> int:
	var n := 0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house":
			n += 1
	return n


func _pop(state: CityState, t: int) -> float:
	var n := 0.0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house" and int(b["tier"]) == t:
			n += float(b["residents"])
	return n


# ------------------------------------------------------------------ 시장·서비스: 원인이 "범위 밖/등급 부족"인 주거 근처에
func _markets_services(state: CityState) -> void:
	var want := {}     # building type -> 기준 주거 위치
	var crit := {}
	for b: Dictionary in state.buildings.values():
		if b["kind"] != "house":
			continue
		for nid: String in b.get("needs", {}):
			var rec: Dictionary = b["needs"][nid]
			var cause := str(rec.get("cause", ""))
			if cause != "range" and cause != "grade":
				continue
			var n := sim.item("needs", nid)
			if n.get("role", "") == "luxury" and not c("luxury", true):
				continue
			var type := _supplier_for(state, n, str(rec.get("pick", "")))
			if type != "" and not want.has(type):
				want[type] = b["pos"]
			if type != "" and n.get("role", "") != "luxury":
				crit[type] = true
	var built := 0
	for type: String in want:
		if built >= 2:
			break
		if not crit.has(type) and int(sim.bdef(type).get("size", 1)) == 2 and state.money < float(c("luxury_big_money", 3000)):
			continue
		if _try_build(state, type, want[type], crit.has(type)):
			built += 1


func _supplier_for(state: CityState, n: Dictionary, pick: String) -> String:
	var grade := 0
	var tag := ""
	for o: Dictionary in n.get("options", []):
		if o.has("market"):
			grade = maxi(grade, int(o["market"]))
		elif o.has("good"):
			if pick == "" or pick.split(",").has(str(o["good"])):
				grade = maxi(grade, int(sim.good(o["good"]).get("grade", 1)))
		elif o.has("service") and tag == "":
			if pick == "" or pick.split(",").has("svc:" + str(o["service"])) or true:
				if _unlocked_service(state, str(o["service"])) != "":
					tag = str(o["service"])
	if tag != "":
		return _unlocked_service(state, tag)
	if grade > 0:
		for g: int in range(grade, 5):
			for id: String in sim.items("buildings"):
				if int(sim.bdef(id).get("market", 0)) == g and sim.is_unlocked(state, id):
					return id
	return ""


func _unlocked_service(state: CityState, tag: String) -> String:
	for id: String in sim.items("buildings"):
		var d := sim.bdef(id)
		if tag in d.get("services", []) and sim.is_unlocked(state, id) and not d.has("vice") and id != "city_hall":
			return id
	return ""


# ------------------------------------------------------------------ 생산: 상품별 수요 추정 → 생산 시설 또는 수입 계약
## 상품별 경제일당 수요(주민 수요 + 시설 원료). meal은 끼니 묶음.
func _demand(state: CityState) -> Dictionary:
	var dem := {}
	var pop := {}
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house":
			pop[int(b["tier"])] = float(pop.get(int(b["tier"]), 0.0)) + float(b["cap"])
	for nid: String in sim.items("needs"):
		var n := sim.item("needs", nid)
		var r := float(pop.get(int(n["tier"]), 0.0))
		if r <= 0.0 or not n.has("amount"):
			continue
		var goods: Array = []
		for o: Dictionary in n["options"]:
			if o.has("good"):
				goods.append(str(o["good"]))
		if goods.size() == 1:
			dem[goods[0]] = float(dem.get(goods[0], 0.0)) + r * float(n["amount"])
		elif goods.size() > 1:
			dem["meal"] = float(dem.get("meal", 0.0)) + r * float(n["amount"])
	# 원료 수요 = 생산 시설 입력 × 가동 예상(그 출력의 최종 수요 / 생산 능력, 최대 1). 2단 체인은 두 번 돈다.
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
				var want := float(dem.get(g, 0.0))
				if g in ["veg", "noodles", "fishball"]:
					want = float(dem.get("meal", 0.0))
				u = maxf(u, minf(1.0, want * 1.2 / maxf(float(cap.get(g, 1.0)), 1e-6)))
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
	var s := 0.0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "facility" or b["kind"] == "site":
			s += float(sim.bdef(str(b["type"])).get("recipe", {}).get("out", {}).get(g, 0.0)) * 0.9
	for k: Dictionary in state.contracts:
		if k["good"] == g:
			s += (1.0 if k["dir"] == "import" else -1.0) * float(k["qty"]) * 24.0 / float(k["interval_h"])
	return s


func _production(state: CityState) -> void:
	var dem := _demand(state)
	var builds := 0
	var meal := float(dem.get("meal", 0.0))
	if meal > 0.0:
		var have := _supply(state, "veg") + _supply(state, "noodles") + _supply(state, "fishball")
		if have < meal * 1.2:
			var order: Array = c("meal_order", ["noodle_mill", "garden", "fishball_factory"])
			# 2종 수요(토박이 이상)를 위해 가장 적은 품목부터
			if _pop(state, 3) + _pop(state, 4) + _pop(state, 5) > 0.0:
				order = ["veg", "noodles", "fishball"]
				order.sort_custom(func(a: String, b: String) -> bool: return _supply(state, a) < _supply(state, b))
				var map := {"veg": "garden", "noodles": "noodle_mill", "fishball": "fishball_factory"}
				var o2: Array = []
				for g: String in order:
					o2.append(map[g])
				order = o2 + ["garden"]
			for t: String in order:
				if _try_build(state, t, _center(state)):
					builds += 1
					break
	for g: String in c("produce", ["candle", "clothes", "soap", "moonshine", "radio", "suit", "appliance"]):
		if builds >= 2:
			break
		var need := float(dem.get(g, 0.0))
		if need <= 0.0:
			continue
		if _supply(state, g) >= need * 1.1:
			continue
		for t: String in sim.items("buildings"):
			if sim.bdef(t).get("recipe", {}).get("out", {}).has(g) and sim.is_unlocked(state, t):
				if _try_build(state, t, _center(state)):
					builds += 1
				break
	# 고물: 시설 건설 재료
	if float(state.stock.get("scrap", 0.0)) < 40.0 and _count(state, "scrapyard") < 1 + _houses(state) / 60:
		_try_build(state, "scrapyard", _center(state))
	# 창고: 저장 한도가 3일치 소비보다 작으면
	var biggest := 0.0
	for g: String in dem:
		if g != "meal":
			biggest = maxf(biggest, float(dem[g]))
	biggest = maxf(biggest, meal / 2.0)
	if biggest * 3.0 > sim.cap_of(state, "noodles") * 0.9 and _sites_of(state, "infra") == 0:
		_try_build(state, "warehouse", _center(state))


# ------------------------------------------------------------------ 계약
func _contracts(state: CityState) -> void:
	var q: Dictionary = sim.query(state, "contracts")
	var dem := _demand(state)
	var max_slots := int(q["slots"]["max"])
	var changed := false
	for g: String in c("imports", ["flour", "fat", "oldclothes", "cloth", "fishmeat", "elec", "liquor"]):
		var need := float(dem.get(g, 0.0)) * 1.15
		var mine: Array = []
		var have := 0.0
		for k: Dictionary in state.contracts:
			if k["good"] == g and k["dir"] == "import":
				mine.append(k)
				have += float(k["qty"]) * 24.0 / float(k["interval_h"])
		if need <= 0.5 and mine.is_empty():
			continue
		if have >= need and have <= need * 2.5 + 10.0:
			continue
		var best: Dictionary = {}
		for o: Dictionary in q["offers"]:
			if o["good"] == g and o["dir"] == "import" and o["known"]:
				if best.is_empty() or float(o["sizes"][0]["price"]) < float(best["sizes"][0]["price"]):
					best = o
		if best.is_empty():
			_block("수입처 없음: %s" % sim.gname(g))
			continue
		# 원하는 묶음: 가장 큰 단계 여러 개 + 나머지를 덮는 가장 작은 단계
		var sizes: Array = best["sizes"]
		var rate := func(i: int) -> float: return float(sizes[i]["qty"]) * 24.0 / float(sizes[i]["interval_h"])
		var plan: Array = []
		var left := need
		var big := sizes.size() - 1
		while left > float(rate.call(big)) and plan.size() < 4:
			plan.append(big)
			left -= float(rate.call(big))
		if left > 0.5:
			for i: int in sizes.size():
				if float(rate.call(i)) >= left or i == big:
					plan.append(i)
					break
		var used_other := state.contracts.size() - mine.size()
		if used_other + plan.size() > max_slots:
			if _sites_of(state, "infra") == 0 and _count(state, "trade_post") < int(c("max_trade_posts", 6)):
				_try_build(state, "trade_post", _center(state))
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
	if slots_free <= 1:
		return
	for o: Dictionary in q["offers"]:
		if o["dir"] != "export" or not o["known"]:
			continue
		var g := str(o["good"])
		var cap := sim.cap_of(state, g)
		if float(state.stock.get(g, 0.0)) > cap * 0.8:
			var dup := false
			for k: Dictionary in state.contracts:
				dup = dup or (k["good"] == g and k["dir"] == "export")
			if not dup:
				cmd(state, "contract_sign", {"offer": o["id"], "size": 1, "reserve": cap * 0.4})
				return


# ------------------------------------------------------------------ 승급
func _upgrades(state: CityState) -> void:
	var mats: Array = sim.db["upgrade_costs"]["materials"]
	var max_per := int(c("upgrades_per_hour", 3))
	var done := 0
	# 다음 계층 주거가 아직 안 차면(그 계층 기본 수요 미충족) 시범 몇 채만 올린다
	var hn := {}
	var hf := {}
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house":
			var t0 := int(b["tier"])
			hn[t0] = int(hn.get(t0, 0)) + 1
			if int(b["residents"]) >= int(b["cap"]) or b.get("upgrading") != null:
				hf[t0] = int(hf.get(t0, 0)) + 1
	# 높은 계층부터(자재를 위쪽 승급에 먼저 쓴다)
	var cands: Array = []
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house" and b.get("ready", false):
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
		var nt := int(b["tier"]) + 1
		var ln: Dictionary = state.labor.get(nt, {"have": 0, "need": 0.0})
		var short := float(ln["need"]) > float(ln["have"])
		# 다음 계층 주거가 아직 안 차 있으면(그 계층 수요 미충족) 더 올리지 않는다 — 단, 그 계층 노동력이 모자라면 올려서 채운다
		if not short and int(hn.get(nt, 0)) >= int(c("pilot_houses", 3)) and float(hf.get(nt, 0)) < 0.7 * float(hn.get(nt, 0)):
			_block("%s 주거가 아직 안 차서(그 계층 수요 미충족) 승급 보류" % sim.tname(nt))
			continue
		# 다음 계층 노동력이 이미 넉넉하면(그 계층 인력을 쓰는 시설이 있는 계층만) 자재를 아낀다
		var lo: Dictionary = state.labor.get(nt - 1, {"have": 0, "need": 0.0})
		var lower_spare := float(lo["have"]) - float(lo["need"])
		if labor_tiers.has(nt) and float(ln["have"]) - float(ln["need"]) >= float(c("spare_cap", 16)) and int(hn.get(nt + 1, 0)) > 0 \
				and _pop(state, nt) >= _goal_pop(state, nt) and lower_spare < 3.0 * float(c("spare_cap", 16)):
			_block("%s 노동력이 넉넉해 승급 보류(자재 아낌)" % sim.tname(nt))
			continue
		if b["kind"] != "house" or not b.get("ready", false):
			continue
		var t := int(b["tier"])
		# 하위 계층 노동력이 남을 때만(상위가 하위를 대신하지 않는다)
		var l: Dictionary = state.labor.get(t, {"have": 0, "need": 0.0})
		var loss := float(b["residents"]) * float(sim.tier(t).get("labor", 1.0))
		var keep := float(c("labor_margin", 2))
		if float(l["have"]) - loss - float(l["need"]) < keep:
			_block("%s 노동력이 모자라 승급 보류" % sim.tname(t))
			continue
		if t + 1 > int(c("max_tier", 5)):
			continue
		var cost := sim.item("upgrade_costs", "%dto%d" % [t, t + 1])
		if state.money - _save < float(cost.get("money", 0)) + float(c("money_reserve", 40)):
			_block("돈이 모자라 %s 승급 보류" % sim.tname(t))
			continue
		var best := ""
		for m: String in mats:
			if float(state.stock.get(m, 0.0)) >= float(cost["qty"]) and (best == "" or float(state.stock[m]) > float(state.stock[best])):
				best = m
		if best == "":
			_block("자재가 모자라 승급 보류(T%d→T%d)" % [t, t + 1])
			mat_wait = maxi(mat_wait, t)
			continue
		if mat_wait > t:
			_block("위 계층 승급을 위해 자재를 모으는 중(T%d→T%d 보류)" % [t, t + 1])
			continue
		for g: String in cost.get("extra", {}):
			if float(state.stock.get(g, 0.0)) < float(cost["extra"][g]):
				_buy_extra(state, g)
		var r := cmd(state, "upgrade", {"bids": [int(b["id"])], "material": best})
		if r.get("ok", false):
			done += 1
		else:
			_block(str(r.get("reason", "")))


## 아직 못 연 해금 단계가 요구하는 계층 인구(가장 큰 값).
func _goal_pop(state: CityState, t: int) -> float:
	var done: Dictionary = state.flags.get("unlock_steps", {})
	var g := 0.0
	for uid: String in sim.items("unlocks"):
		if done.has(uid):
			continue
		for cnd: Variant in sim.item("unlocks", uid).get("cond", []):
			if cnd is Array and str(cnd[0]) == "pop.t%d" % t:
				g = maxf(g, float(cnd[2]))
	return g


## 설비 부품 같은 추가 상품: 건재상 계약(작게) — 없으면 디버그로 "원거리 탐험" 흉내.
func _buy_extra(state: CityState, g: String) -> void:
	for k: Dictionary in state.contracts:
		if k["good"] == g:
			return
	var r := cmd(state, "contract_sign", {"offer": "bd_" + g, "size": 1 if g == "scrap" else 0})
	if not r.get("ok", false):
		_block("%s 구할 계약 자리 없음" % sim.gname(g))
		if _sites_of(state, "infra") == 0 and _count(state, "trade_post") < int(c("max_trade_posts", 6)):
			_try_build(state, "trade_post", _center(state))


# ------------------------------------------------------------------ 주거 칠하기
## 층마다 2×2 시설 자리 여섯 곳(24칸)을 비워 둔다.
func _reserved(p: Vector3i) -> bool:
	return (p.x % 4 == 1 or p.x % 4 == 2) and (p.y % 6 == 2 or p.y % 6 == 3)

func _zone(state: CityState) -> void:
	var vacant := 0
	var houses := 0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house":
			houses += 1
			vacant += maxi(0, int(b.get("target", b["cap"])) - int(b["residents"]))
			if int(b["residents"]) == 0:
				vacant += 2
	if vacant > int(c("zone_when_vacancy_below", 6)):
		return
	# 떠돌이 노동력이 이미 크게 남으면 더 칠하지 않는다(승급으로 쓰게)
	var l1: Dictionary = state.labor.get(1, {"have": 0, "need": 0.0})
	if houses > 40 and float(l1["have"]) - float(l1["need"]) > float(c("t1_spare_stop", 40)):
		_block("떠돌이 노동력이 남아 주거 확장 보류")
		return
	# 먹을 것이 모자라거나 돈이 없으면 칠하지 않는다
	var dem := _demand(state)
	var meal_sup := _supply(state, "veg") + _supply(state, "noodles") + _supply(state, "fishball")
	if houses > 0 and meal_sup < float(dem.get("meal", 0.0)) * 1.05:
		_block("끼니 생산이 모자라 주거 확장 보류")
		return
	if state.money - _save < float(c("zone_money", 120)):
		_block("돈이 모자라 주거 확장 보류")
		return
	var z := state.floors_unlocked - 1
	var per_floor := int(c("houses_per_floor", 100))
	var on_floor := 0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house" and (b["pos"] as Vector3i).z == z:
			on_floor += 1
	if on_floor >= per_floor:
		_block("층의 주거 목표를 채움 — 다음 층을 기다림")
		return
	var cells: Array = []
	var batch := int(c("zone_batch", 6))
	# 가운데부터 바깥으로 칠한다(시설은 그 사이 빈칸과 윗층에)
	var order: Array = []
	for x: int in sim.W:
		for y: int in sim.H:
			order.append(Vector3i(x, y, z))
	var cx := float(sim.W - 1) / 2.0
	var cy := float(sim.H - 1) / 2.0
	order.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var da := maxf(absf(a.x - cx), absf(a.y - cy))
		var db := maxf(absf(b.x - cx), absf(b.y - cy))
		if da != db:
			return da < db
		return a.x * 100 + a.y < b.x * 100 + b.y)
	for p: Vector3i in order:
		if cells.size() >= batch:
			break
		if not state.cells.has(p) and not _reserved(p):
			cells.append(p)
	if cells.is_empty():
		_block("칠할 칸이 없음")
		return
	var r := cmd(state, "zone", {"cells": cells})
	if not r.get("ok", false):
		_block(str(r.get("reason", "")))
