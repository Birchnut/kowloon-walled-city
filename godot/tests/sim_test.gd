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
	_exp_claim_rules()
	_exp_teams_follow_posts()
	_exp_save_load()
	_labor_separate()
	_structure_v4()
	_run_commands()
	_policy_research()
	_raid()
	_alerts_goals()
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
func _fac(sim: Sim, st: CityState, type: String, p: Vector3i, rot: int = 0) -> int:
	var r := sim.apply(st, "build", {"type": type, "pos": p, "rot": rot})
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
	bad2["needs"]["items"]["t1_food"]["options"].append({"good": "caviar"})
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
		_fac(sim, st, "rain_catcher", Vector3i(11, 2 * i, 0))
	_fac(sim, st, "mahjong", Vector3i(8, 4, 0))
	_fac(sim, st, "market_mat", Vector3i(2, 2, 0), 1)
	if n_stalls > 1:
		_fac(sim, st, "market_mat", Vector3i(2, 1, 0), 1)
	st.stock["cans"] = veg
	_steps(sim, st, 2)          # 공사 마무리·가동
	st.stats.clear()
	_steps(sim, st, 24)         # 반나절
	return [sim, st]


func _markets() -> void:
	print("시장: 겹침·재고·범위")
	var a := _market_city(4, 1, 500.0)
	var b := _market_city(4, 2, 500.0)
	var ca := float(a[1].stats.get("cons.cans", 0.0))
	var cb := float(b[1].stats.get("cons.cans", 0.0))
	_ok(ca > 0.0 and _near(ca, cb), "겹친 시장 2개도 소비는 그대로 (%.3f vs %.3f)" % [ca, cb])
	_ok(_near(float(a[1].stats.get("tax_total", 0.0)), float(b[1].stats.get("tax_total", 0.0))), "겹친 시장 2개도 세수는 그대로")
	var z := _market_city(4, 1, 0.0)
	var h: Dictionary = {}
	for x: Dictionary in z[1].buildings.values():
		if x["kind"] == "house":
			h = x
			break
	var rec: Dictionary = h["needs"].get("t1_food", {})
	_ok(float(rec.get("ratio", 1.0)) == 0.0 and str(rec.get("cause", "")) == "stock", "시장이 있어도 재고 0이면 끼니 미충족(원인 재고 없음)")
	var many := _market_city(10, 1, 5000.0)
	var cm := float(many[1].stats.get("cons.cans", 0.0))
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
		st.stock["elec_scrap"] = 100.0
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
	_ok(not sim.can(st, "contract_sign", {"offer": "ws_fish", "size": 1}).get("ok", true), "뒷문 무역관이 없으면 계약 자리 0(중반 시스템)")
	_fac(sim, st, "trade_post", Vector3i(8, 8, 0))
	st.waiting[2] = {"count": 4, "days_left": 999.0}
	_steps(sim, st, 2)
	st.money = 1000.0
	st.ledger["today"] = {}
	st.stats.erase("tax_total")
	var r := sim.apply(st, "contract_sign", {"offer": "ws_fish", "size": 1})
	_ok(r.get("ok", false), "무역관 자리로 서명 %s" % str(r.get("reason", "")))
	var c: Dictionary = st.contracts[0]
	var m0 := st.money
	var upk0 := float(st.stats.get("upkeep_total", 0.0))
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
			_ok(_near(float(st.stock.get("fish", 0.0)), float(c["qty"])), "상품이 qty만큼 들어옴")
			var led := 0.0
			for d: Dictionary in st.ledger["days"]:
				led += float(d.get("import", 0.0))
			led += float(st.ledger["today"].get("import", 0.0))
			_ok(_near(led, -pay), "장부 import 줄에 한 번(−%.1f)" % pay)
			var upk := float(st.stats.get("upkeep_total", 0.0)) - upk0
			_ok(_near(m0 - st.money - upk, pay, 1e-3), "금고에서 결제액(+무역관 유지비 %.1f)만 빠짐" % upk)
	var interval := float(c["interval_h"]) / 24.0
	_ok(rounds == int(floorf((2.0 - float(sim.cfg("contracts.first_delay_h", 1)) / 24.0) / interval)) + 1, "2일 동안 회차 수 = 주기대로 (%d)" % rounds)
	st.money = 0.0
	var fl := float(st.stock.get("fish", 0.0))
	c["next_at"] = st.econ_days
	sim.step(st)
	_ok(not c["last"]["ok"] and _near(float(st.stock.get("fish", 0.0)), fl) and st.money >= 0.0, "돈이 없으면 그 회차를 건너뜀(벌금 없음): %s" % c["last"]["reason"])
	# 수출: reserve 위만
	st.stock["moonshine"] = 30.0
	var r2 := sim.apply(st, "contract_cancel", {"id": int(c["id"])})
	r2 = sim.apply(st, "contract_sign", {"offer": "ws_moonshine_sell", "size": 1, "reserve": 25.0})
	var e: Dictionary = st.contracts[0]
	e["next_at"] = st.econ_days
	sim.step(st)
	_ok(_near(float(st.stock["moonshine"]), 25.0), "수출은 최소 보유량 위만 보낸다(30 − 5 → 25)")


func _supports() -> void:
	print("자동 골조")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	st.floors_unlocked = 4
	var c := sim.can(st, "build", {"type": "shrine", "pos": Vector3i(3, 3, 3)})
	_ok(c["ok"] and int(c["support_count"]) == (c["cells"] as Array).size() * 3 and (c["supports"] as Array).size() == int(c["support_count"]), "빈 땅 위 4층 시설: can()이 발자국 아래 골조(%d칸)를 미리 알려줌" % int(c["support_count"]))
	st.money = 1.0
	var r := sim.apply(st, "build", {"type": "shrine", "pos": Vector3i(3, 3, 3)})
	_ok(not r["ok"] and st.supports.is_empty() and not st.cells.has(Vector3i(3, 3, 3)), "돈이 모자라면 건물도 골조도 안 생김(원자적)")
	st.money = 100000.0
	var bid := _fac(sim, st, "shrine", Vector3i(3, 3, 3))
	_ok(bid > 0 and st.supports.has(Vector3i(3, 3, 0)) and st.supports.has(Vector3i(3, 3, 1)) and st.supports.has(Vector3i(3, 3, 2)), "골조가 땅까지 한 번에 생김")
	_steps(sim, st, 1)
	sim.apply(st, "demolish", {"pos": Vector3i(3, 3, 3)})
	_steps(sim, st, 1)
	sim.apply(st, "build", {"type": "mahjong", "pos": Vector3i(3, 3, 3), "rot": 1})
	for bb: Dictionary in st.buildings.values():
		if bb["kind"] == "site":
			bb["progress"] = 0.999999
	_steps(sim, st, 1)
	var z := sim.apply(st, "zone", {"cells": [Vector3i(3, 3, 1)]})
	_ok(z["ok"] and int(z["built"]) == 1, "골조 칸에도 주거를 지을 수 있다")
	_steps(sim, st, 2)
	var d := sim.apply(st, "demolish", {"pos": Vector3i(3, 3, 1)})
	_ok(d["ok"] and st.cells.has(Vector3i(3, 3, 3)) and st.supports.has(Vector3i(3, 3, 1)), "아래를 철거해도 위 건물은 남고 그 칸에 골조")
	sim.apply(st, "demolish", {"pos": Vector3i(4, 3, 3)})
	_ok(not st.supports.has(Vector3i(3, 3, 0)) and not st.supports.has(Vector3i(3, 3, 2)) and not st.supports.has(Vector3i(4, 3, 0)), "위가 없어진 골조는 정리됨(발자국 전체)")
	# 2층 주거 칠하기도 골조
	var z2 := sim.apply(st, "zone", {"cells": [Vector3i(7, 7, 2), Vector3i(8, 7, 2)]})
	_ok(z2["ok"] and int(z2["supports"]) == 4, "주거 칠하기(2칸, 3층)도 골조 4칸")


func _floor_boundary() -> void:
	print("80% 층 해금 경계(16×16 → 205칸)")
	var need := Cover.floor_need(Sim.new() if false else _lab()[0])
	_ok(need == 205, "16×16의 80%% = 205칸 (%d)" % need)
	var cases := [[204, "", 1, "204칸 = 잠김"], [205, "", 2, "205칸 = 열림"], [201, "big", 2, "2×2 시설은 4칸(201+4)"],
		[204, "support", 1, "골조만 있는 칸은 0"], [204, "empty", 1, "빈 판잣집은 0"], [204, "site", 1, "공사 중은 0"]]
	for cs: Array in cases:
		var L := _lab()
		var sim: Sim = L[0]
		var st: CityState = L[1]
		match str(cs[1]):
			"big":
				_fac(sim, st, "market_alley", Vector3i(14, 14, 0))
			"support":
				for i: int in 6:
					st.supports[Vector3i(i, 15, 0)] = true
			"empty":
				_house(sim, st, Vector3i(15, 15, 0), 1, 0)
			"site":
				var rs := sim.apply(st, "build", {"type": "mahjong", "pos": Vector3i(14, 15, 0), "rot": 1})
				st.buildings[int(rs["bid"])]["progress"] = -100.0
		_steps(sim, st, 1)
		sim.apply(st, "debug", {"op": "fill_floor", "z": 0, "count": int(cs[0])})
		_steps(sim, st, 1)
		_ok(st.floors_unlocked == int(cs[2]), "%s (쓰이는 칸 %d, 열린 층 %d)" % [cs[3], Cover.used_cells(st, 0), st.floors_unlocked])
	var L2 := _lab()
	L2[0].apply(L2[1], "debug", {"op": "fill_floor", "z": 0, "count": 205})
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
	_ok(int(bp["movers"]) == 8 and int(bp["cap_to"]) == 16 and int(bp["vacancies"]) == 2 and bp.has("ok") and int(bp["cost"]["qty"]) == 2 * int(DB["upgrade_costs"]["items"]["3to4"]["qty"]), "upgrade_preview 합산: 이주 8, 정원 16, 빈자리 2, 자재 2채분")


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
		for q: String in ["hud", "build_menu", "economy", "contracts", "expeditions", "research", "policies", "goals"]:
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
	bad["unlocks"]["items"]["t2_1"]["unlocks"].erase("tailor")
	bad["unlocks"]["items"]["t2_40"]["unlocks"].append("tailor")
	var e := Validate.lock_check(bad)
	_ok(not e.is_empty(), "봉제방을 월세 전사 40으로 미루면 → 월세 전사 기본 수요(옷) 순환 잠금 검출")
	var bad2 := _db_copy()
	bad2["unlocks"]["items"]["t1_20"]["unlocks"].erase("candle_shop")
	bad2["unlocks"]["items"]["t2_1"]["unlocks"].append("candle_shop")
	_ok(not Validate.lock_check(bad2).is_empty(), "초 공방을 월세 전사 1로 미루면 → 굴러온 돌 승급 수요(등불) 순환 잠금 검출")
	var bad3 := _db_copy()
	bad3["buildings"]["items"]["food_cans"]["recipe"]["in"] = {"fish": 5}
	bad3["buildings"]["items"]["food_pilgrims"]["recipe"]["in"] = {"fish": 5}
	bad3["partners"]["items"].erase("ws_fish")
	_ok(not Validate.lock_check(bad3).is_empty(), "통조림에 수입 원료가 필요하면 → 순환 잠금 검출(성채식 조달)")


# ------------------------------------------------------------------ 파트 B
func _base_lab() -> Array:
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	sim.now_unix = 2_000_000
	return L


func _exp_claim_rules() -> void:
	print("탐험: 완료 전 수령 불가 · 두 번 수령 없음 · 나가 있는 팀은 다시 못 보냄")
	var L := _base_lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	_fac(sim, st, "expedition_base", Vector3i(0, 0, 0))
	_steps(sim, st, 1)
	var q: Dictionary = sim.query(st, "expeditions")
	_ok((q["teams"] as Array).size() == 1, "거점 1 → 팀 1")
	var r := sim.apply(st, "expedition_send", {"team": 1, "dest": "junk_yard", "provision": false})
	_ok(r.get("ok", false), "근거리 파견")
	var wood0 := float(st.stock.get("metal", 0.0))
	var c := sim.apply(st, "expedition_claim", {"team": 1})
	_ok(not c.get("ok", false) and float(st.stock.get("metal", 0.0)) == wood0, "완료 전 수령 불가(재고 그대로)")
	var again := sim.apply(st, "expedition_send", {"team": 1, "dest": "landfill", "provision": false})
	_ok(not again.get("ok", false) and str(again.get("code", "")) == "busy", "나가 있는 팀은 다시 못 보냄(%s)" % again.get("reason", ""))
	var n_steps := int(ceilf(float(r["days"]) / sim.step_days - 1e-6))
	_steps(sim, st, n_steps - 1)
	_ok(not sim.apply(st, "expedition_claim", {"team": 1}).get("ok", false), "한 스텝 전에도 수령 불가(게임 시계)")
	_steps(sim, st, 1)
	var c1 := sim.apply(st, "expedition_claim", {"team": 1})
	var got := float(st.stock.get("metal", 0.0)) - wood0
	_ok(c1.get("ok", false) and got >= 7.0 and (c1["rewards"] as Array).size() >= 1, "완료 뒤 수령: 철제 +%d, 보상 목록 %s" % [int(got), str(c1.get("rewards", []))])
	var m1 := float(st.stock.get("metal", 0.0))
	var c2 := sim.apply(st, "expedition_claim", {"team": 1})
	_ok(not c2.get("ok", false) and float(st.stock.get("metal", 0.0)) == m1, "두 번째 수령은 아무것도 주지 않는다")
	_ok(bool(st.dests["old_factory"]["known"]), "첫 근거리 수령으로 중거리 목적지 공개")
	sim.systems.clear()


func _exp_teams_follow_posts() -> void:
	print("탐험: 팀 수 = 거점 수(최대 3), 나가 있는 팀의 거점을 허물면 수령 뒤 해산")
	var L := _base_lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	for i: int in 4:
		_fac(sim, st, "expedition_base", Vector3i(i, 0, 0))
	_steps(sim, st, 1)
	_ok(st.teams.size() == 3, "거점 4 → 팀 3(최대) (%d)" % st.teams.size())
	sim.apply(st, "demolish", {"pos": Vector3i(3, 0, 0)})
	_ok(st.teams.size() == 3, "거점 3 → 팀 3")
	sim.apply(st, "expedition_send", {"team": 3, "dest": "landfill", "provision": false})
	sim.apply(st, "demolish", {"pos": Vector3i(2, 0, 0)})
	var live := 0
	for t: Dictionary in st.teams:
		if not t.get("retired", false):
			live += 1
	_ok(live == 2 and st.teams.size() == 3, "거점 2 → 쉬는 팀 2 + 나가 있는 팀은 은퇴 표시")
	_steps(sim, st, 48)
	sim.apply(st, "expedition_claim", {})
	_ok(st.teams.size() == 2, "수령 뒤 은퇴 팀 해산 → 팀 2")
	sim.systems.clear()


func _exp_save_load() -> void:
	print("탐험: 나가 있는 중 저장·불러오기")
	var L := _base_lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	_fac(sim, st, "expedition_base", Vector3i(0, 0, 0))
	_steps(sim, st, 1)
	sim.apply(st, "expedition_send", {"team": 1, "dest": "demo_site", "provision": false})
	var js := st.to_json()
	var st2 := CityState.new()
	_ok(st2.from_json(js), "불러오기")
	var sim2 := Sim.new()
	sim2.setup(DB)
	_steps(sim, st, 48)
	_steps(sim2, st2, 48)
	var a := sim.apply(st, "expedition_claim", {})
	var b := sim2.apply(st2, "expedition_claim", {})
	_ok(a.get("ok", false) and JSON.stringify(a["rewards"]) == JSON.stringify(b["rewards"]), "불러온 상태의 보상 = 원래 보상(출발 때 굴림) %s" % str(b.get("rewards", [])))
	sim.systems.clear()
	sim2.systems.clear()


func _labor_separate() -> void:
	print("탐험대는 주민 노동력과 분리(한 주민이 두 곳에 배정되지 않음)")
	var L := _base_lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	for i: int in 6:
		_house(sim, st, Vector3i(i, 5, 0), 1, 4)
	_fac(sim, st, "food_cans", Vector3i(0, 7, 0))
	_steps(sim, st, 2)
	var before := JSON.stringify(st.labor)
	_fac(sim, st, "expedition_base", Vector3i(0, 0, 0))
	_steps(sim, st, 1)
	sim.apply(st, "expedition_send", {"team": 1, "dest": "landfill", "provision": false})
	_steps(sim, st, 1)
	_ok(JSON.stringify(st.labor) == before, "탐험대를 보내도 노동력 배분이 그대로")
	var ok := true
	for t: Variant in st.labor:
		ok = ok and float(st.labor[t]["used"]) <= float(st.labor[t]["have"]) + 1e-9
	_ok(ok, "계층마다 배정 ≤ 노동력")
	sim.systems.clear()


func _bot_city(days_h: int, seed_v: int) -> Array:
	var sim := Sim.new()
	sim.setup(DB)
	var bot := Bot.new(sim, "balanced")
	var st := CityState.new()
	sim.now_unix = 3_000_000
	sim.new_game(st, seed_v)
	for h: int in days_h:
		bot.act(st)
		sim.now_unix += 25
		sim.tick(st, 1.0 / 24.0)
		st.events.clear()
	st.last_saved_unix = sim.now_unix
	return [sim, st]


func _structure_v4() -> void:
	print("v4 구조: 발자국·회전·사각 범위·하늘·층 조건·공사 시간·게임 시계")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	st.floors_unlocked = 4
	var c0 := sim.can(st, "build", {"type": "mahjong", "pos": Vector3i(0, 0, 0), "rot": 0})
	var c1 := sim.can(st, "build", {"type": "mahjong", "pos": Vector3i(0, 0, 0), "rot": 1})
	var k0 := sim.fp("mahjong", 0)
	var k1 := sim.fp("mahjong", 1)
	_ok(k0.x == k1.y and k0.y == k1.x and (c0["cells"] as Array).size() == k0.x * k0.y, "회전하면 w·h가 바뀐다 (%s → %s)" % [k0, k1])
	var edge := sim.can(st, "build", {"type": "mahjong", "pos": Vector3i(sim.W - 1, sim.H - 1, 0), "rot": 0})
	_ok(not edge["ok"] and str(edge["code"]) == "shape", "모서리에서 발자국이 부지 밖이면 code shape (%s)" % edge["code"])
	_house(sim, st, Vector3i(5, 5, 0), 1, 0)
	var occ := sim.can(st, "build", {"type": "mahjong", "pos": Vector3i(5, 4, 0), "rot": 0})
	_ok(not occ["ok"] and str(occ["code"]) == "shape", "발자국 한 칸이 막혀도 shape")
	# 사각 범위: 체비쇼프 r, 위·아래 층
	var rg := {"r": 2, "up": 1, "down": 0}
	_ok(Cover.reach(Vector3i(4, 4, 1), 1, 2, 1, rg, Vector3i(6, 7, 1)) and not Cover.reach(Vector3i(4, 4, 1), 1, 2, 1, rg, Vector3i(7, 4, 1)), "사각 범위: 대각 (2,2)는 닿고 가로 3칸은 안 닿음")
	_ok(Cover.reach(Vector3i(4, 4, 1), 1, 2, 1, rg, Vector3i(4, 4, 2)) and not Cover.reach(Vector3i(4, 4, 1), 1, 2, 1, rg, Vector3i(4, 4, 0)), "위 1층은 닿고 아래(down 0)는 안 닿음")
	_ok(Cover.reach(Vector3i(0, 0, 0), 2, 2, 2, {"r": 0, "up": 1, "down": 0}, Vector3i(0, 0, 2)), "2개 층 시설은 위층을 자기 층으로 친다(+up)")
	var rp: Dictionary = sim.query(st, "range_preview", {"type": "shrine", "pos": Vector3i(8, 8, 1), "rot": 0})
	_ok((rp["cells"] as Array).size() > 0 and (rp["by_floor"] as Dictionary).has(1) and (rp["by_floor"] as Dictionary).has(2), "range_preview: cells와 층별 by_floor")
	# 하늘·층 조건(시험용 시설)
	var db := _db_copy()
	db["buildings"]["items"]["test_roof"] = {"name": "시험 텃밭", "cat": "food", "priority": "food", "footprint": [1, 1], "needs_sky": true, "min_floor": 2,
		"cost": {"money": 1, "goods": {}}, "upkeep": 0, "workforce": {}, "recipe": {"in": {}, "out": {"radio": 10}}}
	db["unlocks"]["items"]["start"]["unlocks"].append("test_roof")
	var L2 := _lab(db)
	var s2: Sim = L2[0]
	var t2: CityState = L2[1]
	t2.floors_unlocked = 5
	_ok(str(s2.can(t2, "build", {"type": "test_roof", "pos": Vector3i(2, 2, 1)}).get("code", "")) == "floor", "min_floor 2: 2층(z=1)은 code floor")
	_house(s2, t2, Vector3i(3, 3, 4), 1, 0)
	t2.supports[Vector3i(3, 3, 0)] = true
	t2.supports[Vector3i(3, 3, 1)] = true
	t2.supports[Vector3i(3, 3, 2)] = true
	t2.supports[Vector3i(3, 3, 3)] = true
	_ok(str(s2.can(t2, "build", {"type": "test_roof", "pos": Vector3i(3, 3, 2)}).get("code", "")) == "sky", "위에 집이 있으면 code sky")
	var rb := s2.apply(t2, "build", {"type": "test_roof", "pos": Vector3i(6, 6, 2)})
	_ok(rb.get("ok", false), "위가 뚫린 3층 자리에는 지어진다")
	var days := float(rb.get("build_days", 0.0))
	_steps(s2, t2, int(ceilf(days / s2.step_days)) + 1)
	var gb: Dictionary = t2.buildings[int(rb["bid"])]
	_ok(gb["kind"] == "facility", "공사 %.2f일 뒤 완공" % days)
	var zw := s2.can(t2, "zone", {"cells": [Vector3i(6, 6, 4)]})
	var bw := s2.can(t2, "build", {"type": "shrine", "pos": Vector3i(6, 6, 4)})
	_ok(zw.get("ok", false) and str(bw.get("warn", "")) != "", "위에 지을 수는 있고 짓기 판정이 그늘 경고를 준다")
	s2.apply(t2, "zone", {"cells": [Vector3i(6, 6, 4)]})
	_steps(s2, t2, 2)
	_ok(str(gb.get("cause", "")) == "sky" and not gb.get("active", true), "위에 무언가가 서면 멈춘다(cause sky)")
	s2.apply(t2, "demolish", {"pos": Vector3i(6, 6, 4)})
	_steps(s2, t2, 2)
	_ok(gb.get("active", false), "위를 허물면 다시 돈다")
	# 2개 층 시설과 층 해금 칸 수
	db["buildings"]["items"]["test_tall"] = {"name": "시험 탑", "cat": "landmark", "priority": "other", "footprint": [2, 2], "floors": 2,
		"cost": {"money": 1, "goods": {}}, "upkeep": 0, "workforce": {}}
	db["unlocks"]["items"]["start"]["unlocks"].append("test_tall")
	var L3 := _lab(db)
	var s3: Sim = L3[0]
	var t3: CityState = L3[1]
	_ok(str(s3.can(t3, "build", {"type": "test_tall", "pos": Vector3i(0, 0, 0)}).get("code", "")) == "locked_floor", "2개 층짜리는 두 층 모두 열려야 한다")
	t3.floors_unlocked = 2
	var r3 := s3.apply(t3, "build", {"type": "test_tall", "pos": Vector3i(0, 0, 0)})
	t3.buildings[int(r3["bid"])]["progress"] = 0.999999
	_steps(s3, t3, 1)
	_ok(Cover.used_cells(t3, 0) == 4 and Cover.used_cells(t3, 1) == 4 and t3.cells.has(Vector3i(1, 1, 1)), "2개 층 2×2: 두 층에 4칸씩 쓰인다")
	s3.apply(t3, "demolish", {"pos": Vector3i(1, 1, 1)})
	_ok(t3.cells.is_empty(), "어느 칸을 눌러 허물어도 건물 전체가 사라진다")
	sim.systems.clear()
	s2.systems.clear()
	s3.systems.clear()


func _run_commands() -> void:
	print("직접 줍기 약속: run_begin / run_result 검사")
	var L := _base_lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	_fac(sim, st, "expedition_base", Vector3i(0, 0, 0))
	_steps(sim, st, 1)
	var dest := ""
	for id: String in st.dests:
		if st.dests[id]["known"] and not (st.dests[id].get("stock", {}) as Dictionary).is_empty():
			dest = id
			break
	_ok(not sim.apply(st, "run_result", {"dest": dest, "loot": {}, "outcome": "exit", "finds": []}).get("ok", true), "run_begin 없이 run_result는 거절")
	var b := sim.apply(st, "run_begin", {"dest": dest})
	_ok(b.get("ok", false) and b.has("stock") and b.has("danger") and b.has("seed"), "run_begin → {stock, danger, seed}")
	_ok(str(sim.query(st, "expeditions")["teams"][0]["state"]) == "run", "팀이 직접 줍는 중")
	var stock: Dictionary = b["stock"]
	var g: String = stock.keys()[0]
	var over := sim.apply(st, "run_result", {"dest": dest, "loot": {g: int(stock[g]) + 1}, "outcome": "exit", "finds": []})
	_ok(not over.get("ok", true) and str(over.get("code", "")) in ["stock", "carry"], "던전 재고보다 많이 들고 나오면 거절(%s)" % over.get("code", ""))
	var big := sim.apply(st, "run_result", {"dest": dest, "loot": {g: int(b["carry"]) + 1}, "outcome": "exit", "finds": []})
	_ok(not big.get("ok", true), "배낭 한도를 넘으면 거절")
	var n := mini(int(stock[g]), 10)
	var have0 := float(st.stock.get(g, 0.0))
	var res := sim.apply(st, "run_result", {"dest": dest, "loot": {g: n}, "outcome": "down", "finds": []})
	_ok(res.get("ok", false) and _near(float(st.stock.get(g, 0.0)) - have0, floorf(n * 0.5)) and (res["lost"] as Array).size() == (1 if n - n / 2 > 0 else 0), "쓰러지면 절반만 (+%d, 잃음 %s)" % [int(float(st.stock.get(g, 0.0)) - have0), str(res.get("lost", []))])
	_ok(float(st.dests[dest]["stock"][g]) <= float(stock[g]) - n + 1e-6, "던전 재고에서 빠진다")
	_ok(str(sim.query(st, "expeditions")["teams"][0]["state"]) == "idle", "팀이 돌아온다")
	var before := float(st.dests[dest]["stock"][g])
	_steps(sim, st, 24)
	_ok(float(st.dests[dest]["stock"][g]) > before, "던전 재고는 게임 시간으로 다시 찬다")
	sim.systems.clear()


func _policy_research() -> void:
	print("정책·연구: 효과가 들어가고 정책을 끄면 되돌아간다")
	var B := _bot_city(24 * 4, 5)
	var sim: Sim = B[0]
	var st: CityState = B[1]
	st.unlocked["feature:policy_slot_1"] = 1.0
	var tax := func() -> float:
		var s := 0.0
		for b: Dictionary in st.buildings.values():
			if b["kind"] == "house":
				s += float(b["tax"])
		return s
	_steps(sim, st, 1)
	var twin := CityState.new()
	twin.from_json(st.to_json())
	var t0: float = tax.call()
	_ok(sim.apply(st, "policy_set", {"id": "tax_cut", "on": true}).get("ok", false), "감세 켬")
	_steps(sim, st, 1)
	var t1: float = tax.call()
	sim.apply(st, "policy_set", {"id": "tax_cut", "on": false})
	_steps(sim, st, 1)
	var t2: float = tax.call()
	_steps(sim, twin, 2)
	var tt := 0.0
	for b: Dictionary in twin.buildings.values():
		if b["kind"] == "house":
			tt += float(b["tax"])
	_ok(t1 < t0 * 0.85 and absf(t2 - tt) <= 0.005 * tt, "감세: 세수 %.1f → %.1f → 끄면 %.1f (안 켠 쌍둥이 %.1f)" % [t0, t1, t2, tt])
	st.unlocked.erase("feature:policy_slot_2")
	sim.apply(st, "policy_set", {"id": "rations", "on": true})
	_ok(not sim.can(st, "policy_set", {"id": "overtime", "on": true}).get("ok", true), "칸이 1개면 두 번째 정책은 거절")
	sim.apply(st, "policy_set", {"id": "rations", "on": false})
	# 연구: 공부방 + 작업 정리 → 생산 +10%
	var L := _lab()
	var s2: Sim = L[0]
	var c2: CityState = L[1]
	for i: int in 8:
		_house(s2, c2, Vector3i(i, 5, 0), 3, 12)
	_fac(s2, c2, "study", Vector3i(0, 0, 0))
	_fac(s2, c2, "candle_shop", Vector3i(2, 0, 0))
	c2.stock["oil"] = 5000.0
	for i: int in 6:
		_house(s2, c2, Vector3i(i, 7, 0), 1, 4)
	_steps(s2, c2, 2)
	var p0 := float(c2.stats.get("prod.candle", 0.0))
	_steps(s2, c2, 4)
	var base := float(c2.stats.get("prod.candle", 0.0)) - p0
	c2.money = 100000.0
	var rs := s2.apply(c2, "research_start", {"id": "workflow"})
	_ok(rs.get("ok", false), "연구 시작(공부방 있음) %s" % rs.get("reason", ""))
	_ok(not s2.can(c2, "research_start", {"id": "handcart"}).get("ok", true), "한 번에 하나")
	_steps(s2, c2, 52)
	_ok(c2.research["done"].has("workflow"), "1경제일 뒤 연구 완료")
	c2.stock["candle"] = 0.0
	var p1 := float(c2.stats.get("prod.candle", 0.0))
	_steps(s2, c2, 4)
	var after := float(c2.stats.get("prod.candle", 0.0)) - p1
	_ok(base > 0.0 and _near(after, base * 1.1, 1e-6), "작업 정리: 생산 +10%% (%.3f → %.3f)" % [base, after])
	sim.systems.clear()
	s2.systems.clear()


func _raid() -> void:
	print("단속: 위험 80에서 음성 시설 정확히 하나가 2일 닫히고 다시 연다")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	for i: int in 12:
		_house(sim, st, Vector3i(i, 5, 0), 1, 4)
	var ids: Array = []
	for i: int in 3:
		ids.append(_fac(sim, st, "gambling_den", Vector3i(i, 0, 0)))
	_steps(sim, st, 2)
	st.heat = 79.99
	_steps(sim, st, 1)
	var closed := 0
	for b: int in ids:
		if st.buildings[b].get("raided", false):
			closed += 1
	_ok(closed == 1, "하나만 닫힘 (%d)" % closed)
	_ok(st.heat < 50.0 and float(st.stats.get("fines", 0.0)) > 0.0, "위험이 내려가고 벌금 (위험 %.1f, 벌금 ₩%d)" % [st.heat, int(st.stats.get("fines", 0.0))])
	var rb := -1
	for b: int in ids:
		if st.buildings[b].get("raided", false):
			rb = b
	_steps(sim, st, 1)
	_ok(str(st.buildings[rb].get("cause", "")) == "raid" and float(st.buildings[rb].get("eff", 1.0)) == 0.0, "닫힌 시설은 cause raid, 가동 0")
	_ok(sim.can(st, "pause", {"bid": rb}).get("ok", false), "닫혀 있어도 플레이어는 멈추기·허물기를 할 수 있다")
	_steps(sim, st, 96)
	_ok(not st.buildings[rb].get("raided", false), "2일 뒤 다시 연다")
	sim.systems.clear()


func _alerts_goals() -> void:
	print("알림·목표: 최대 4개, 목표 진행, 셋째 질의 모양")
	var B := _bot_city(24 * 3, 6)
	var sim: Sim = B[0]
	var st: CityState = B[1]
	var h: Dictionary = sim.query(st, "hud")
	_ok((h["alerts"] as Array).size() <= 4, "알림 ≤ 4 (%d)" % (h["alerts"] as Array).size())
	var ok := true
	for a: Dictionary in h["alerts"]:
		ok = ok and a.has("id") and a.has("text") and a.has("tone") and a.has("jump")
	_ok(ok, "알림 모양 {id, text, tone, jump}")
	_ok(h.has("next_goal") and str(h["next_goal"].get("text", "")) != "", "다음 목표 문장")
	var g: Dictionary = sim.query(st, "goals")
	_ok((g["steps"] as Array).size() > 10 and str(g["steps"].back()["id"]) == "g_final", "목표 단계, 마지막은 구룡성채")
	_ok(int(g["done_count"]) >= 2, "3일 동안 목표 몇 개 달성 (%d)" % int(g["done_count"]))
	_ok(sim.query(st, "offline_summary") == null, "offline_summary: 보여 줄 것이 없으면 null")
	_ok(str(sim.can(st, "build", {"type": "market_mat", "pos": Vector3i(99, 0, 0)}).get("code", "")) == "bounds", "can build code: bounds")
	sim.systems.clear()
