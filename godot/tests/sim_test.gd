extends SceneTree
## sim_test — 시뮬 계층 헤드리스 시험.  실행: godot/tests/sim_test.sh
## 스크립트 오류는 GDScript 안에서 잡을 수 없으므로 sim_test.sh가 출력의 "SCRIPT ERROR"를 실패로 친다.

const Run := preload("res://tools/sim_run.gd")

var fails: Array = []
var DB: Dictionary


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	DB = SimIO.load_db()
	_data()
	_t1_labor()
	_family_qty()
	_markets()
	_power_scaling()
	_contract_once()
	_supports()
	_floor_boundary()
	_shrink_upgrade()
	_batch_atomic()
	_bot_invariants()
	_determinism()
	_round_trip()
	_disable_each()
	_circular()
	print("")
	if fails.is_empty():
		print("SIM TEST: ALL PASS (%.1f초)" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	else:
		print("SIM TEST: %d FAIL" % fails.size())
		for f: String in fails:
			print("  - ", f)
	quit(0 if fails.is_empty() else 1)


func _ok(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", label])
	if not cond:
		fails.append(label)


func _near(a: float, b: float, eps: float = 1e-6) -> bool:
	return absf(a - b) <= eps * maxf(1.0, maxf(absf(a), absf(b)))


# ------------------------------------------------------------------ 실험실
func _db_copy() -> Dictionary:
	return DB.duplicate(true)


func _lab(db: Dictionary = {}) -> Array:
	var sim := Sim.new()
	sim.setup(db if not db.is_empty() else DB)
	var st := CityState.new()
	sim.new_game(st, 7)
	sim.apply(st, "debug", {"op": "unlock_all"})
	st.money = 100000.0
	st.stock = {"scrap": 1000.0, "parts": 100.0}
	return [sim, st]


func _house(sim: Sim, st: CityState, p: Vector3i, tier: int, res: int) -> int:
	var cap := int(sim.tier(tier)["cap"])
	var bid := st.new_id()
	st.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": tier, "material": "common" if tier == 1 else "wood",
		"residents": res, "cap": cap, "happiness": 50.0, "needs": {}, "need_state": "warn", "upgradable": false, "upgrading": null,
		"grow": 0.0, "leave": 0.0, "target": cap, "tax": 0.0, "util_extra": {}}
	st.cells[p] = {"kind": "house", "bid": bid, "type": "house", "tier": tier, "material": "common", "seed": 1, "origin": p, "size": 1, "scaffold": false}
	st.layout_changed()
	return bid


## 시설을 짓고 공사를 끝낸다(경제 시간 0.3일 진행 — 짧은 시험에만).
func _fac(sim: Sim, st: CityState, type: String, p: Vector3i) -> int:
	var r := sim.apply(st, "build", {"type": type, "pos": p})
	if not r.get("ok", false):
		print("    build fail ", type, " ", r)
		return -1
	var b: Dictionary = st.buildings[int(r["bid"])]
	b["progress"] = 0.999999
	return int(r["bid"])


func _steps(sim: Sim, st: CityState, n: int) -> void:
	for i: int in n:
		sim.step(st)
	st.events.clear()


# ------------------------------------------------------------------ 시험들
func _data() -> void:
	print("데이터 검증")
	var sim := Sim.new()
	sim.setup(DB)
	_ok(sim.errors.is_empty(), "data/** 검증 오류 없음 %s" % str(sim.errors.slice(0, 3)))
	var caps: Array = []
	for t: int in range(1, 6):
		caps.append(int(sim.tier(t)["cap"]))
	_ok(caps == [4, 8, 12, 8, 6], "정원 4-8-12-8-6")
	var bad := _db_copy()
	bad["tiers"]["items"]["t4"]["cap"] = 10
	_ok(not Validate.check(bad).is_empty(), "정원을 바꾸면 검증 오류(확정값 보호)")
	var bad2 := _db_copy()
	bad2["needs"]["items"]["t1_meal"]["options"].append({"good": "caviar"})
	_ok(not Validate.check(bad2).is_empty(), "없는 상품을 요구하는 수요 → 검증 오류")


func _t1_labor() -> void:
	print("노동력: 떠돌이 4명 → 3")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	_house(sim, st, Vector3i(0, 0, 0), 1, 4)
	_steps(sim, st, 1)
	_ok(int(st.labor[1]["have"]) == 3, "T1 정원 4 → 노동력 3 (지금 %d)" % int(st.labor[1]["have"]))
	_house(sim, st, Vector3i(1, 0, 0), 1, 1)
	_house(sim, st, Vector3i(2, 0, 0), 1, 1)
	_steps(sim, st, 1)
	_ok(int(st.labor[1]["have"]) == int(floorf(float(st.population()) * 0.75)), "떠돌이 노동력은 도시 합계에서 한 번만 내림(4+1+1 → 4)")
	var L2 := _lab()
	_house(L2[0], L2[1], Vector3i(0, 0, 0), 3, 12)
	_steps(L2[0], L2[1], 1)
	_ok(int(L2[1].labor[3]["have"]) == 12, "T3 12명 → 노동력 12")


func _family_qty() -> void:
	print("세 계열 자재 수량 동일")
	var uc: Dictionary = DB["upgrade_costs"]
	_ok((uc["materials"] as Array) == ["wood", "metal", "concrete"], "자재 목록은 목재·철제·콘크리트")
	var all_one := true
	for id: String in uc["items"]:
		all_one = all_one and uc["items"][id].has("qty") and not uc["items"][id].has("wood")
	_ok(all_one, "승급 단계마다 qty 하나(계열별 수량 필드 없음)")
	var bad := _db_copy()
	bad["upgrade_costs"]["items"]["2to3"]["wood"] = 5
	_ok(not Validate.check(bad).is_empty(), "계열별 수량을 따로 쓰면 검증 오류")
	# 실제로 고른 한 계열에서 qty만큼 빠진다(셋 다 같은 양)
	for m: String in ["wood", "metal", "concrete"]:
		var L := _lab()
		var sim: Sim = L[0]
		var st: CityState = L[1]
		var bid := _house(sim, st, Vector3i(0, 0, 0), 1, 4)
		st.buildings[bid]["upgradable"] = true
		st.stock = {"wood": 50.0, "metal": 50.0, "concrete": 50.0}
		var r := sim.apply(st, "upgrade", {"bids": [bid], "material": m})
		_ok(r.get("ok", false) and _near(float(st.stock[m]), 50.0 - float(uc["items"]["1to2"]["qty"])), "%s 승급: %s만 qty 차감" % [m, m])


## 시장 겹침·재고 0·범위 안 인구 증가.
func _market_city(n_houses: int, n_stalls: int, veg: float) -> Array:
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	for i: int in n_houses:
		_house(sim, st, Vector3i(i % 6, 4 + i / 6, 0), 1, 4)
	for i: int in 4:
		_fac(sim, st, "rain_catcher", Vector3i(11, i, 0))
	_fac(sim, st, "stall", Vector3i(3, 3, 0))
	if n_stalls > 1:
		_fac(sim, st, "stall", Vector3i(4, 3, 0))
	st.stock["veg"] = veg
	_steps(sim, st, 2)          # 공사 마무리·가동
	st.stats.clear()
	_steps(sim, st, 24)         # 반나절
	return [sim, st]


func _markets() -> void:
	print("시장: 겹침·재고·범위")
	var a := _market_city(4, 1, 500.0)
	var b := _market_city(4, 2, 500.0)
	var ca := float(a[1].stats.get("cons.veg", 0.0))
	var cb := float(b[1].stats.get("cons.veg", 0.0))
	_ok(ca > 0.0 and _near(ca, cb), "겹친 시장 2개도 소비는 그대로 (%.3f vs %.3f)" % [ca, cb])
	_ok(_near(float(a[1].stats.get("tax_total", 0.0)), float(b[1].stats.get("tax_total", 0.0))), "겹친 시장 2개도 세수는 그대로")
	var z := _market_city(4, 1, 0.0)
	var h: Dictionary = {}
	for x: Dictionary in z[1].buildings.values():
		if x["kind"] == "house":
			h = x
			break
	var rec: Dictionary = h["needs"].get("t1_meal", {})
	_ok(float(rec.get("ratio", 1.0)) == 0.0 and str(rec.get("cause", "")) == "stock", "시장이 있어도 재고 0이면 끼니 미충족(원인 재고 없음)")
	var many := _market_city(10, 1, 5000.0)
	var cm := float(many[1].stats.get("cons.veg", 0.0))
	_ok(_near(cm, ca * 2.5, 1e-3), "범위 안 인구 2.5배 → 도시 소비 2.5배, 시장별 상한 없음 (%.3f vs %.3f)" % [cm, ca])
	var neg := true
	for g: String in many[1].stock:
		neg = neg and float(many[1].stock[g]) >= 0.0
	_ok(neg, "재고는 0 밑으로 안 간다")


func _power_scaling() -> void:
	print("전기 필수 시설: 부족하면 비율만큼, 0이면 0")
	var out := []
	for sup: float in [6.0, 3.0, 0.0]:
		var db := _db_copy()
		db["buildings"]["items"]["test_gen"] = {"name": "시험 발전기", "cat": "power", "priority": "utility", "size": 1,
			"cost": {"money": 0, "goods": {}}, "upkeep": 0, "workforce": {}, "build_days": 0.01, "supply": {"power": sup}}
		db["progression"] = {}
		db["unlocks"]["items"]["start"]["unlocks"].append("test_gen")
		var L := _lab(db)
		var sim: Sim = L[0]
		var st: CityState = L[1]
		st.waiting[3] = {"count": 10, "days_left": 99.0}
		_fac(sim, st, "radio_shop", Vector3i(0, 0, 0))
		if sup > 0.0:
			_fac(sim, st, "test_gen", Vector3i(2, 0, 0))
		st.stock["elec"] = 100.0
		_steps(sim, st, 2)
		st.stats.clear()
		_steps(sim, st, 12)
		out.append(float(st.stats.get("prod.radio", 0.0)))
	_ok(out[0] > 0.0 and _near(out[1], out[0] * 0.5, 1e-3), "전기 절반 → 생산 절반 (%.3f / %.3f)" % [out[1], out[0]])
	_ok(out[2] == 0.0, "전기 0 → 생산 0(공짜 생산 없음)")


func _contract_once() -> void:
	print("계약: 한 회차 = 돈·상품 정확히 한 번")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	st.money = 1000.0
	st.ledger["today"] = {}
	var r := sim.apply(st, "contract_sign", {"offer": "ws_flour", "size": 1})
	_ok(r.get("ok", false), "기본 계약 자리 1개로 서명 %s" % str(r.get("reason", "")))
	var c: Dictionary = st.contracts[0]
	var m0 := st.money
	var rounds := 0
	var day0 := st.day
	for i: int in 48 * 2:
		var before := float(st.stats.get("contract_rounds", 0.0))
		sim.step(st)
		for e: Dictionary in st.events:
			if e["name"] == "contract_done":
				rounds += 1
		st.events.clear()
		if rounds == 1 and float(st.stats.get("contract_rounds", 0.0)) == 1.0 and before == 0.0:
			var pay := float(c["qty"]) * float(c["price"]) + float(c.get("transport", 0.0))
			_ok(_near(float(st.stock.get("flour", 0.0)), float(c["qty"])), "상품이 qty만큼 들어옴")
			var led := 0.0
			for d: Dictionary in st.ledger["days"]:
				led += float(d.get("import", 0.0))
			led += float(st.ledger["today"].get("import", 0.0))
			_ok(_near(led, -pay), "장부 import 줄에 한 번(−%.1f)" % pay)
			_ok(_near(m0 - st.money, pay), "금고에서 정확히 결제액만 빠짐(집·시설 없음 → 세수·유지비 0)")
	var interval := float(c["interval_h"]) / 24.0
	_ok(rounds == int(floorf((2.0 - float(sim.cfg("contracts.first_delay_h", 1)) / 24.0) / interval)) + 1, "2일 동안 회차 수 = 주기대로 (%d)" % rounds)
	st.money = 0.0
	var fl := float(st.stock.get("flour", 0.0))
	c["next_at"] = st.econ_days
	sim.step(st)
	_ok(not c["last"]["ok"] and _near(float(st.stock.get("flour", 0.0)), fl) and st.money >= 0.0, "돈이 없으면 그 회차를 건너뜀(벌금 없음): %s" % c["last"]["reason"])
	# 수출: reserve 위만
	st.stock["noodles"] = 30.0
	var r2 := sim.apply(st, "contract_cancel", {"id": int(c["id"])})
	r2 = sim.apply(st, "contract_sign", {"offer": "ws_noodles_sell", "size": 1, "reserve": 25.0})
	var e: Dictionary = st.contracts[0]
	e["next_at"] = st.econ_days
	sim.step(st)
	_ok(_near(float(st.stock["noodles"]), 25.0), "수출은 최소 보유량 위만 보낸다(30 − 5 → 25)")


func _supports() -> void:
	print("자동 골조")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	st.floors_unlocked = 4
	var c := sim.can(st, "build", {"type": "shrine", "pos": Vector3i(3, 3, 3)})
	_ok(c["ok"] and int(c["supports"]) == 3, "빈 땅 위 4층 시설: can()이 골조 3칸을 미리 알려줌")
	st.money = 1.0
	var r := sim.apply(st, "build", {"type": "shrine", "pos": Vector3i(3, 3, 3)})
	_ok(not r["ok"] and st.supports.is_empty() and not st.cells.has(Vector3i(3, 3, 3)), "돈이 모자라면 건물도 골조도 안 생김(원자적)")
	st.money = 100000.0
	var bid := _fac(sim, st, "shrine", Vector3i(3, 3, 3))
	_ok(bid > 0 and st.supports.has(Vector3i(3, 3, 0)) and st.supports.has(Vector3i(3, 3, 1)) and st.supports.has(Vector3i(3, 3, 2)), "골조가 땅까지 한 번에 생김")
	var z := sim.apply(st, "zone", {"cells": [Vector3i(3, 3, 1)]})
	_ok(z["ok"] and int(z["built"]) == 1, "골조 칸에도 주거를 지을 수 있다")
	_steps(sim, st, 2)
	var d := sim.apply(st, "demolish", {"pos": Vector3i(3, 3, 1)})
	_ok(d["ok"] and st.cells.has(Vector3i(3, 3, 3)) and st.supports.has(Vector3i(3, 3, 1)), "아래를 철거해도 위 건물은 남고 그 칸에 골조")
	sim.apply(st, "demolish", {"pos": Vector3i(3, 3, 3)})
	_ok(not st.supports.has(Vector3i(3, 3, 0)) and not st.supports.has(Vector3i(3, 3, 2)), "위가 없어진 골조는 정리됨")
	# 2층 주거 칠하기도 골조
	var z2 := sim.apply(st, "zone", {"cells": [Vector3i(7, 7, 2), Vector3i(8, 7, 2)]})
	_ok(z2["ok"] and int(z2["supports"]) == 4, "주거 칠하기(2칸, 3층)도 골조 4칸")


func _floor_boundary() -> void:
	print("80% 층 해금 경계")
	var cases := [[115, "", 1, "115칸 = 잠김"], [116, "", 2, "116칸 = 열림"], [112, "big", 2, "2×2 시설은 4칸(112+4)"],
		[115, "support", 1, "골조만 있는 칸은 0"], [115, "empty", 1, "빈 판잣집은 0"], [115, "site", 1, "공사 중은 0"]]
	for cs: Array in cases:
		var L := _lab()
		var sim: Sim = L[0]
		var st: CityState = L[1]
		match str(cs[1]):
			"big":
				_fac(sim, st, "market2", Vector3i(10, 10, 0))
			"support":
				for i: int in 6:
					st.supports[Vector3i(i, 11, 0)] = true
			"empty":
				_house(sim, st, Vector3i(11, 11, 0), 1, 0)
			"site":
				var rs := sim.apply(st, "build", {"type": "shrine", "pos": Vector3i(11, 11, 0)})
				st.buildings[int(rs["bid"])]["progress"] = -100.0
		_steps(sim, st, 1)
		sim.apply(st, "debug", {"op": "fill_floor", "z": 0, "count": int(cs[0])})
		_steps(sim, st, 1)
		_ok(st.floors_unlocked == int(cs[2]), "%s (쓰이는 칸 %d, 열린 층 %d)" % [cs[3], Cover.used_cells(st, 0), st.floors_unlocked])
	var L2 := _lab()
	L2[0].apply(L2[1], "debug", {"op": "fill_floor", "z": 0, "count": 116})
	_steps(L2[0], L2[1], 1)
	for b: Dictionary in L2[1].buildings.values():
		b["residents"] = 0
	_steps(L2[0], L2[1], 1)
	_ok(L2[1].floors_unlocked == 2, "한 번 열린 층은 점유가 줄어도 닫히지 않음")


func _shrink_upgrade() -> void:
	print("정원 감소 승급(12 → 8): 이주·대기·떠남")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	var a := _house(sim, st, Vector3i(0, 0, 0), 3, 12)
	var b := _house(sim, st, Vector3i(5, 5, 0), 3, 9)
	var p0 := st.population()
	st.buildings[a]["upgrading"] = {"to": 4, "material": "metal", "done_at": st.econ_days}
	_steps(sim, st, 1)
	_ok(int(st.buildings[a]["tier"]) == 4 and int(st.buildings[a]["residents"]) == 8, "8명은 유지가 됨")
	_ok(int(st.buildings[b]["residents"]) == 12 and st.waiting.get(3, {}).get("count", 0) == 1, "넘친 4명 중 3명은 같은 계층 빈집으로, 1명은 대기")
	_ok(st.population() == p0, "총인구 보존(대기 포함) %d → %d" % [p0, st.population()])
	var info: Dictionary = sim.query(st, "info", {"bid": b})
	_ok(info.has("upgrade") and info["upgrade"].has("preview"), "info에 승급 미리보기")
	_steps(sim, st, 48 * 3 + 2)
	_ok(not st.waiting.has(3) and int(st.stats.get("left_waiting", 0)) == 1, "빈집이 끝내 없으면 3일 뒤 떠남(기록됨)")
	var logged := false
	for e: Dictionary in st.logbook:
		logged = logged or str(e["text"]).find("빈집을 끝내 못 찾은") >= 0
	_ok(logged, "떠남이 기록에 남음")
	# 미리보기 수치
	var L2 := _lab()
	var c := _house(L2[0], L2[1], Vector3i(0, 0, 0), 3, 12)
	_house(L2[0], L2[1], Vector3i(4, 4, 0), 3, 10)
	var pv: Dictionary = L2[0].query(L2[1], "info", {"bid": c})["upgrade"]["preview"]
	_ok(int(pv["cap_from"]) == 12 and int(pv["cap_to"]) == 8 and int(pv["movers"]) == 4 and int(pv["vacancies"]) == 2, "미리보기: 12→8, 이주 4, 빈자리 2")
	var d := _house(L2[0], L2[1], Vector3i(6, 6, 0), 3, 12)
	L2[1].buildings[c]["upgradable"] = true
	L2[1].buildings[d]["upgradable"] = true
	var ug: Array = L2[0].query(L2[1], "upgradable", {})
	_ok(ug.size() == 1 and int(ug[0]["count"]) == 2, "upgradable 질의: 토박이 2채")
	var bp: Dictionary = L2[0].query(L2[1], "upgrade_preview", {"bids": [c, d], "material": "wood"})
	_ok(int(bp["movers"]) == 8 and int(bp["cap_to"]) == 16 and int(bp["vacancies"]) == 2 and bp.has("ok") and bp["cost"]["qty"] == 32, "upgrade_preview 합산: 이주 8, 정원 16, 빈자리 2, 자재 32")


func _batch_atomic() -> void:
	print("일괄 승급은 원자적")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	var a := _house(sim, st, Vector3i(0, 0, 0), 1, 4)
	var b := _house(sim, st, Vector3i(1, 0, 0), 1, 4)
	st.buildings[a]["upgradable"] = true
	st.stock = {"wood": 100.0}
	var m0 := st.money
	var r := sim.apply(st, "upgrade", {"bids": [a, b], "material": "wood"})
	_ok(not r["ok"] and st.money == m0 and float(st.stock["wood"]) == 100.0 and st.buildings[a]["upgrading"] == null, "하나라도 안 되면 아무것도 안 함")
	st.buildings[b]["upgradable"] = true
	st.stock = {"wood": 7.0}
	r = sim.apply(st, "upgrade", {"bids": [a, b], "material": "wood"})
	_ok(not r["ok"] and float(st.stock["wood"]) == 7.0, "자재가 묶음 전체에 모자라면 취소(12 필요, 7 있음)")


func _invariants(st: CityState) -> Array:
	var bad: Array = []
	if st.money < 0.0 or is_nan(st.money):
		bad.append("돈 음수 %f" % st.money)
	for g: String in st.stock:
		if float(st.stock[g]) < -1e-9 or is_nan(float(st.stock[g])):
			bad.append("재고 음수 %s %f" % [g, st.stock[g]])
	for b: Dictionary in st.buildings.values():
		if b["kind"] == "house" and (int(b["residents"]) < 0 or int(b["residents"]) > int(b["cap"])):
			bad.append("주민 수 범위 밖 %d/%d" % [b["residents"], b["cap"]])
	for t: Variant in st.labor:
		if int(st.labor[t]["have"]) < 0 or float(st.labor[t]["used"]) > float(st.labor[t]["have"]) + 1e-6:
			bad.append("노동력 이상 T%d" % int(t))
	var arrived := float(st.stats.get("arrived", 0.0))
	var left := float(st.stats.get("left", 0.0))
	if int(arrived - left) != st.population():
		bad.append("인구 보존 위반: 들어옴 %d − 떠남 %d ≠ 인구 %d" % [int(arrived), int(left), st.population()])
	for p: Vector3i in st.cells:
		if p.z > 0 and not st.cells.has(p - Vector3i(0, 0, 1)) and not st.supports.has(p - Vector3i(0, 0, 1)):
			bad.append("허공에 뜬 칸 %s" % p)
	return bad


func _bot_invariants() -> void:
	print("균형형 봇 8일: 매시 불변식")
	var sim := Sim.new()
	sim.setup(DB)
	var bot := Bot.new(sim, "balanced")
	var st := CityState.new()
	sim.new_game(st, 3)
	var bad: Array = []
	for h: int in 24 * 8:
		bot.act(st)
		sim.tick(st, 1.0 / 24.0)
		st.events.clear()
		var v := _invariants(st)
		if not v.is_empty() and bad.is_empty():
			bad = v
			bad.push_front("%d시간째" % h)
	_ok(bad.is_empty(), "돈·재고·주민·노동력 음수 없음, 인구 보존(들어옴−떠남), 뜬 칸 없음 %s" % str(bad.slice(0, 3)))
	_ok(int(st.stats.get("upgrades_t2", 0)) > 0, "8일 안에 승급이 일어남")


func _hash(st: CityState) -> int:
	return st.to_json().hash()


func _determinism() -> void:
	print("결정론")
	var h: Array = []
	for i: int in 2:
		var r := Run.run("balanced", 3, 11, false)
		h.append(_hash(r["state"]))
		(r["sim"] as Sim).systems.clear()
	_ok(h[0] == h[1], "같은 씨앗 + 같은 봇 → 같은 지문")


func _round_trip() -> void:
	print("저장/불러오기 왕복")
	var sim := Sim.new()
	sim.setup(DB)
	var bot := Bot.new(sim, "balanced")
	var st := CityState.new()
	sim.new_game(st, 5)
	for h: int in 24 * 3 + 7:
		bot.act(st)
		sim.tick(st, 1.0 / 24.0)
		st.events.clear()
	var saved := st.to_json()
	var st2 := CityState.new()
	_ok(st2.from_json(saved), "from_json 성공")
	_ok(st2.to_json() == saved, "읽은 상태를 다시 쓰면 같은 글")
	var sim2 := Sim.new()
	sim2.setup(DB)
	var bot2 := Bot.new(sim2, "balanced")
	for h: int in 24 * 2:
		bot.act(st)
		sim.tick(st, 1.0 / 24.0)
		st.events.clear()
		bot2.act(st2)
		sim2.tick(st2, 1.0 / 24.0)
		st2.events.clear()
	_ok(_hash(st) == _hash(st2), "중간 저장 → 불러와 이어 돌린 결과 = 계속 돌린 결과")
	var old := CityState.new()
	_ok(not old.from_json(JSON.stringify({"version": 2, "money": 5})), "옛 버전(v2) 저장은 거부")


func _disable_each() -> void:
	print("시스템을 하나씩 꺼도 돈다")
	for id: String in DB["config"]["systems"]:
		var db := _db_copy()
		var lst: Array = db["config"]["systems"].duplicate()
		lst.erase(id)
		db["config"]["systems"] = lst
		var sim := Sim.new()
		sim.setup(db)
		var bot := Bot.new(sim, "balanced")
		var st := CityState.new()
		sim.new_game(st, 2)
		for h: int in 24 * 2:
			bot.act(st)
			sim.tick(st, 1.0 / 24.0)
			st.events.clear()
		for q: String in ["hud", "build_menu", "economy", "contracts", "expeditions", "research", "policies", "goals", "offline_summary"]:
			if sim.query(st, q) == null:
				_ok(false, "%s 끔: 질의 %s가 null" % [id, q])
		var v := _invariants(st)
		v = v.filter(func(x: String) -> bool: return not x.begins_with("인구 보존") or id != "needs")
		_ok(v.is_empty() and st.econ_days > 2.0, "%s 끔: 2일 진행, 불변식 유지 %s" % [id, str(v.slice(0, 2))])
		sim.systems.clear()


func _circular() -> void:
	print("순환 잠금 정적 검사")
	_ok(Validate.lock_check(DB).is_empty(), "지금 데이터에 순환 잠금 없음 %s" % str(Validate.lock_check(DB).slice(0, 2)))
	var bad := _db_copy()
	bad["unlocks"]["items"]["t1_50"]["unlocks"].erase("tailor")
	bad["unlocks"]["items"]["t2_60"]["unlocks"].append("tailor")
	var e := Validate.lock_check(bad)
	_ok(not e.is_empty(), "봉제방을 세입자 60으로 미루면 → 세입자 기본 수요(옷) 순환 잠금 검출")
	var bad2 := _db_copy()
	bad2["unlocks"]["items"]["t1_20"]["unlocks"].erase("candle_shop")
	bad2["unlocks"]["items"]["t2_1"]["unlocks"].append("candle_shop")
	_ok(not Validate.lock_check(bad2).is_empty(), "초 공방을 세입자 1로 미루면 → 떠돌이 승급 수요(등불) 순환 잠금 검출")
