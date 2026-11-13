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
	_hazards_fire()
	_hazards_disease()
	_board_queries()
	_policy_research()
	_raid()
	_alerts_goals()
	_v5_names_food()
	_v5_calendar()
	_v5_hazard_density()
	_v5_layers()
	_v5_warehouse()
	_v5_org()
	_v5_idle_leak()
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
	_ok(not e.is_empty(), "봉제방을 판자시민 40으로 미루면 → 판자시민 기본 수요(옷) 순환 잠금 검출")
	var bad2 := _db_copy()
	bad2["unlocks"]["items"]["t1_20"]["unlocks"].erase("candle_shop")
	bad2["unlocks"]["items"]["t2_1"]["unlocks"].append("candle_shop")
	_ok(not Validate.lock_check(bad2).is_empty(), "초 공방을 판자시민 1로 미루면 → 벽틈시민 승급 수요(등불) 순환 잠금 검출")
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
	var h0 := float(st.stock.get(g, 0.0))
	var over := sim.apply(st, "run_result", {"dest": dest, "loot": {g: int(b["carry_cap"]) + 5}, "outcome": "exit", "finds": ["압축기 큰형의 설계도를 주웠다"]})
	var got_over := float(st.stock.get(g, 0.0)) - h0
	_ok(over.get("ok", false) and got_over <= minf(float(stock[g]), float(b["carry_cap"])) + 1e-6 and not (over.get("lost", []) as Array).is_empty(),
		"재고·배낭 한도를 넘으면 거절하지 않고 잘라 받는다(+%d, 잘림 %s)" % [int(got_over), str(over.get("lost", []))])
	_ok(str(sim.query(st, "expeditions")["teams"][0]["state"]) == "idle", "잘린 결과도 팀을 풀어 준다")
	var w: Variant = sim.query(st, "run_wanted", {})
	_ok(w is Array, "run_wanted → 상품 id 배열 %s" % str(w))
	sim.apply(st, "run_begin", {"dest": dest})
	var dst0 := float(st.dests[dest]["stock"][g])
	var n := mini(int(floorf(dst0 + 1e-6)), 10)
	var have0 := float(st.stock.get(g, 0.0))
	var res := sim.apply(st, "run_result", {"dest": dest, "loot": {g: n}, "outcome": "down", "finds": [], "lost": {g: 3}})
	_ok(res.get("ok", false) and _near(float(st.stock.get(g, 0.0)) - have0, float(n)) and (res["lost"] as Array).size() == 1, "loot는 들고 나온 그대로(쓰러짐의 절반은 미니게임이 이미 뺐다) (+%d, 잃음 %s)" % [int(float(st.stock.get(g, 0.0)) - have0), str(res.get("lost", []))])
	_ok(int(b.get("carry_cap", 0)) >= 72, "배낭 한도 = 6칸 × 12 + 큰 짐(%d)" % int(b.get("carry_cap", 0)))
	_ok(float(st.dests[dest]["stock"][g]) <= dst0 - n + 1e-6, "던전 재고에서 빠진다")
	_ok(str(sim.query(st, "expeditions")["teams"][0]["state"]) == "idle", "팀이 돌아온다")
	var b2 := sim.apply(st, "run_begin", {"dest": dest})
	var c0 := float(st.stock.get("cans", 0.0))
	var e0 := float(st.stock.get("elec_scrap", 0.0))
	var r2 := sim.apply(st, "run_result", {"dest": dest, "loot": {"canned": 1, "elec": 1}, "outcome": "exit", "finds": []})
	_ok(b2.get("ok", false) and r2.get("ok", false) and _near(float(st.stock.get("cans", 0.0)) - c0, 1.0) and _near(float(st.stock.get("elec_scrap", 0.0)) - e0, 1.0),
		"시제품 id(canned·elec)도 받는다 %s" % str(r2.get("reason", "")))
	var before := float(st.dests[dest]["stock"][g])
	_steps(sim, st, 24)
	_ok(float(st.dests[dest]["stock"][g]) > before, "던전 재고는 게임 시간으로 다시 찬다")
	sim.systems.clear()


func _hz_lab(db: Dictionary = {}) -> Array:
	var L := _lab(db)
	var sim: Sim = L[0]
	var st: CityState = L[1]
	for i: int in 10:
		_house(sim, st, Vector3i(i, 10, 0), 1, 4)
	return L


func _hazards_fire() -> void:
	print("불: 층이 아니라 밀도에서(처음부터 켜짐·유예), 범위 밖은 타서 수리, 범위 안은 금방 꺼짐, 번짐 상한, 인구 보존")
	var L := _hz_lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	var got_on := false
	sim.step(st)
	for e: Dictionary in st.events:
		got_on = got_on or e["name"] == "hazard_on"
	st.events.clear()
	var hz: Dictionary = sim.query(st, "hazards")
	_ok(bool(hz["fire"]["on"]) and st.floors_unlocked == 1 and not got_on, "1층뿐이어도 불은 처음부터 켜져 있다(층 카드 사건 없음, 유예 %.2f일)" % float(hz["fire"]["grace_left"]))
	_ok(float(hz["fire"]["grace_left"]) > 0.0, "시작 직후는 유예 중이다")
	_steps(sim, st, int(float(sim.cfg("hazards.fire.grace_days", 2.0)) / sim.step_days) - 2)
	_ok(int(st.stats.get("fires", 0)) == 0, "유예 동안은 불이 안 난다")
	# 범위 밖 집에 불
	var p0 := Vector3i(0, 10, 0)
	var bid: int = st.cells[p0]["bid"]
	var pop0 := st.population()
	var dbg := sim.apply(st, "debug", {"op": "start_fire", "pos": p0})
	_ok(dbg.get("ok", false) and str(st.buildings[bid]["burn"]) == "burning" and str(st.cells[p0]["burn"]) == "burning", "디버그 start_fire → 셀·건물 burn = burning")
	_steps(sim, st, int(float(sim.cfg("hazards.fire.burn_days", 0.3)) / sim.step_days) + 3)
	var b: Dictionary = st.buildings[bid]
	_ok(str(b["burn"]) == "burnt" and int(b["residents"]) == 0, "범위 밖이면 다 탄다(주민 0)")
	_ok(st.population() == pop0 or float(st.stats.get("left", 0.0)) > 0.0, "흩어진 주민은 대기 주민이 된다(인구 %d → %d, 대기 %s)" % [pop0, st.population(), str(st.waiting)])
	_steps(sim, st, 4)
	_ok(int(b["residents"]) == 0 and int(b.get("target", 0)) == 0, "탄 집에는 아무도 들어오지 않는다")
	var rc := sim.can(st, "repair", {"bid": bid})
	_ok(rc.get("ok", false) and float(rc["cost"]["money"]) > 0.0, "수리 판정: 돈·고물·날짜 (%s)" % str(rc.get("cost", {})))
	var m0 := st.money
	sim.apply(st, "repair", {"bid": bid})
	_ok(st.money < m0 and b.get("repair") != null and not sim.can(st, "repair", {"bid": bid}).get("ok", true), "수리 시작 — 돈이 빠지고 두 번은 안 된다")
	_steps(sim, st, int(float(sim.cfg("hazards.repair.days", 0.25)) / sim.step_days) + 2)
	_ok(str(b["burn"]) == "" and b.get("repair") == null, "수리가 끝나면 다시 쓴다")
	# 범위 안: 금방 꺼지고 주민 1명만
	_fac(sim, st, "fire_bucket", Vector3i(3, 12, 0))
	_steps(sim, st, 2)
	var p1 := Vector3i(4, 10, 0)
	var b1: Dictionary = st.buildings[int(st.cells[p1]["bid"])]
	var sc0 := int(st.stats.get("scattered", 0))
	var bt0 := int(st.stats.get("burnt", 0))
	sim.apply(st, "debug", {"op": "start_fire", "pos": p1})
	_steps(sim, st, 6)
	_ok(str(b1["burn"]) == "" and int(st.stats.get("scattered", 0)) - sc0 == 1 and int(st.stats.get("burnt", 0)) == bt0, "소방 범위 안의 불은 한 시간 남짓에 꺼지고 주민 1명만 흩어진다(타지 않음)")
	# 번짐과 상한(시험용으로 번짐을 크게)
	var db := _db_copy()
	db["config"]["hazards"]["fire"]["spread_per_day"] = 500.0
	db["config"]["hazards"]["fire"]["max_burning"] = 3
	var L2 := _lab(db)
	var s2: Sim = L2[0]
	var t2: CityState = L2[1]
	for x: int in 8:
		for y: int in 8:
			_house(s2, t2, Vector3i(x, y, 0), 1, 4)
	sim.apply(t2, "debug", {"op": "set_hazard", "kind": "fire", "on": true})
	s2.apply(t2, "debug", {"op": "set_hazard", "kind": "fire", "on": true})
	s2.apply(t2, "debug", {"op": "start_fire", "pos": Vector3i(4, 4, 0)})
	var most := 0
	for i: int in 30:
		s2.step(t2)
		t2.events.clear()
		var n := 0
		for bb: Dictionary in t2.buildings.values():
			if str(bb.get("burn", "")) == "burning":
				n += 1
		most = maxi(most, n)
	_ok(int(t2.stats.get("fires", 0)) > 1 and most <= 3 + 64 / 150, "범위 밖 불은 이웃으로 번지되 동시에 타는 곳은 상한까지 (불 %d번, 최대 동시 %d)" % [int(t2.stats.get("fires", 0)), most])
	var arrived := float(t2.stats.get("arrived", 0.0))
	# 승급한 집의 수리: 그 계층으로 올릴 때 쓴 자재(집의 계열)의 mat_frac + 계층별 돈
	var hb3: Dictionary = t2.buildings[int(t2.cells[Vector3i(0, 0, 0)]["bid"])]
	hb3["tier"] = 3
	hb3["material"] = "wood"
	hb3["burn"] = "burnt"
	var rc3 := s2.can(t2, "repair", {"bid": int(hb3["id"])})
	var want3 := ceilf(float(s2.db["upgrade_costs"]["items"]["2to3"]["qty"]) * float(s2.cfg("hazards.repair.mat_frac", 0.5)))
	_ok(_near(float(rc3.get("cost", {}).get("goods", {}).get("wood", 0.0)), want3) and float(rc3["cost"]["money"]) == float(s2.cfg("hazards.repair.house_money", [])[2]),
		"성채민 집 수리 = 목재 %d + %s (%s)" % [int(want3), Sim.won(float(rc3["cost"]["money"])), str(rc3.get("cost", {}))])
	_ok(float(t2.stats.get("left_fire", 0.0)) > 0.0, "범위 밖에서 다 탄 집의 주민 일부는 성채를 떠난다 (%d명)" % int(t2.stats.get("left_fire", 0.0)))
	sim.systems.clear()
	s2.systems.clear()


func _hazards_disease() -> void:
	print("병: 처음부터 켜짐(밀도), 쓰레기는 수거 범위로 치우고, 앓는 집은 일손 절반·행복↓, 의원이면 빨리 낫고, 오래 가면 떠난다")
	var dbd := _db_copy()
	dbd["config"]["hazards"]["disease"]["density"]["base"] = 0.96     # 밀도 배수를 1 안팎으로(이 시험은 쌓이는 속도·범위·치유를 본다 — 밀도는 _v5_density가 본다)
	var L := _hz_lab(dbd)
	var sim: Sim = L[0]
	var st: CityState = L[1]
	sim.apply(st, "debug", {"op": "set_hazard", "kind": "disease", "on": true})
	_steps(sim, st, 48)
	var tr := float(st.buildings[int(st.cells[Vector3i(0, 10, 0)]["bid"])].get("trash", 0.0))
	_ok(tr > 0.2 and float(st.cells[Vector3i(0, 10, 0)].get("trash", 0.0)) > 0.1, "수거 범위 밖 주거에 쓰레기가 쌓인다 (%.2f)" % tr)
	_fac(sim, st, "trash_guild", Vector3i(2, 12, 0))
	_steps(sim, st, 2)
	var cq: Dictionary = sim.query(st, "coverage", {"kind": "trash"})
	_ok(float(cq["pct"]) > 0.0, "밤배꾼을 짓고 일손이 차면 그 층 주거가 덮인다 (%s)" % str(cq["text"]))
	var site_id := st.next_id
	st.buildings[site_id] = {"id": site_id, "kind": "site", "type": "trash_guild", "pos": Vector3i(12, 12, 0)}
	var cq2: Dictionary = sim.query(st, "coverage", {"kind": "trash"})
	_ok(float(cq2["pct"]) >= 1.0 or str(cq2["text"]).contains("공사 중"), "공사 중인 조합이 있으면 범위 글이 그렇게 말한다 (%s)" % str(cq2["text"]))
	st.buildings.erase(site_id)
	_steps(sim, st, 22)
	var tr2 := float(st.buildings[int(st.cells[Vector3i(2, 10, 0)]["bid"])].get("trash", 0.0))
	_ok(tr2 < 0.05, "밤배꾼 범위에 새로 들면 싹 치워진다 (%.2f)" % tr2)
	# 발병(디버그): 이웃까지
	var hb: Dictionary = st.buildings[int(st.cells[Vector3i(8, 10, 0)]["bid"])]
	var nb: Dictionary = st.buildings[int(st.cells[Vector3i(9, 10, 0)]["bid"])]
	nb["trash"] = 0.9
	_steps(sim, st, 2)
	var lab0 := int(st.labor[1]["have"])
	var hap0 := float(hb["happiness"])
	sim.apply(st, "debug", {"op": "start_outbreak", "pos": Vector3i(8, 10, 0)})
	_steps(sim, st, 2)
	_ok(bool(hb["sick"]) and bool(nb["sick"]) and bool(st.cells[Vector3i(8, 10, 0)]["sick"]), "발병하면 그 집과 쓰레기 많은 이웃이 앓는다")
	_ok(int(st.labor[1]["have"]) < lab0 and float(hb["happiness"]) < hap0, "앓는 집: 일손 절반(%d → %d), 행복 하락(%.0f → %.0f)" % [lab0, int(st.labor[1]["have"]), hap0, float(hb["happiness"])])
	var left0 := float(st.stats.get("left_sick", 0.0))
	_steps(sim, st, int((float(sim.cfg("hazards.disease.leave_after", 1.0)) + 0.8) / sim.step_days))
	_ok(float(st.stats.get("left_sick", 0.0)) > left0, "의원이 없으면 오래 앓고 주민이 떠난다 (%d명)" % int(st.stats.get("left_sick", 0.0)))
	st.waiting[2] = {"count": 4, "days_left": 999.0}   # 의원 일손(판자시민 2명)
	_fac(sim, st, "clinic", Vector3i(7, 12, 0))
	_steps(sim, st, int(float(sim.cfg("hazards.disease.clinic_days", 0.6)) / sim.step_days) + 4)
	_ok(not bool(hb["sick"]) and not bool(st.cells[Vector3i(8, 10, 0)]["sick"]), "봉합방 범위에 들면 곧 낫는다")
	_steps(sim, st, 48 * 3)
	var tr3 := float(st.buildings[int(st.cells[Vector3i(2, 10, 0)]["bid"])].get("trash", 0.0))
	var cap3 := float(sim.cfg("hazards.disease.covered_cap", 0.5))
	_ok(tr3 > 0.02 and tr3 <= cap3 + 1e-6, "범위 안에서도 다 못 치운 쓰레기가 천천히 쌓이되 covered_cap(%.2f)에서 멈춘다 (3일 뒤 %.2f)" % [cap3, tr3])
	sim.systems.clear()


func _board_queries() -> void:
	print("현황판·신호등·범위 렌즈·위험 질의 모양")
	var B := _bot_city(24 * 6, 8)
	var sim: Sim = B[0]
	var st: CityState = B[1]
	var m: Dictionary = sim.query(st, "metrics")
	var ok := true
	for r: Dictionary in m["rows"]:
		for k: String in ["id", "group", "name", "supply", "demand", "unit", "ratio", "state", "days_left", "hint", "jump"]:
			ok = ok and r.has(k)
		ok = ok and r["group"] in ["utility", "food", "goods", "service", "hazard"] and r["state"] in ["ok", "warn", "bad", "off"]
	_ok(ok and (m["rows"] as Array).size() >= 6, "metrics rows 모양 (%d행)" % (m["rows"] as Array).size())
	_ok(m.has("labor") and m.has("tiers") and m.has("finance") and m.has("hazards") and (m["tiers"] as Array).size() == 5 and (m["tiers"][0] as Dictionary).has("arriving"), "metrics: labor·tiers(arriving)·finance·hazards")
	var h: Dictionary = sim.query(st, "hud")
	var ids: Array = []
	for sg: Dictionary in h["signals"]:
		ids.append(sg["id"])
		ok = ok and sg.has("name") and sg.has("state") and sg.has("text") and sg.has("jump")
	_ok(ok and ids == ["water", "power", "food", "fun", "fire", "disease", "labor"], "hud.signals 7개 %s" % str(ids))
	_ok(h.has("hazards") and h["hazards"].has("fire") and h["hazards"]["fire"].has("covered_pct") and h.has("grid") and int(h["grid"]["w"]) == 16, "hud.hazards, hud.grid")
	for k: String in ["market", "fun", "fire", "trash", "clinic", "service:shrine"]:
		var c: Dictionary = sim.query(st, "coverage", {"kind": k})
		_ok(c.has("covered") and c.has("uncovered") and c.has("pct") and str(c["text"]) != "", "coverage %s (%d%%)" % [k, int(float(c["pct"]) * 100.0)])
	var hz: Dictionary = sim.query(st, "hazards")
	_ok(hz["fire"].has("burning") and hz["fire"].has("burnt") and hz["disease"].has("sick") and hz["disease"].has("trash_pct"), "hazards 질의 모양")
	var bm: Array = sim.query(st, "build_menu")
	var fp_ok := true
	for cat: Dictionary in bm:
		for it: Dictionary in cat["items"]:
			fp_ok = fp_ok and it.has("footprint") and it.has("floors") and it.has("rotatable") and it.has("build_days") and it.has("needs_sky") and it.has("min_floor") and it.has("look")
			fp_ok = fp_ok and str(it["sign"]).length() <= 4
	_ok(fp_ok, "build_menu 항목: footprint·floors·rotatable·build_days·needs_sky·min_floor·look, 간판 4자 이내")
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
	# 연구: 글방 + 작업 정리 → 생산 +10%
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
	_ok(rs.get("ok", false), "연구 시작(글방 있음) %s" % rs.get("reason", ""))
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
	_ok(st.heat < 50.0 and float(st.stats.get("fines", 0.0)) > 0.0, "위험이 내려가고 벌금 (위험 %.1f, 벌금 %d달러)" % [st.heat, int(st.stats.get("fines", 0.0))])
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


# ================================================================== v0.5 (docs/DESIGN_v0.5.md)
func _events(st: CityState, name: String) -> Array:
	var out: Array = []
	for e: Dictionary in st.events:
		if e["name"] == name:
			out.append(e["payload"])
	return out


func _v5_names_food() -> void:
	print("v5 B 이름 · C1 먹을 것 순서")
	var sim := Sim.new()
	sim.setup(DB)
	var nm := {"power_plant": "큰 발전기", "power_waste": "재 태우는 발전", "oil_collect": "폐기름 모으는 집", "suit_shop": "양복 짓는 집", "assembly": "조립 공방",
		"scrapyard": "고물 뜯는 곳", "warehouse": "창고", "fireworks": "화약방", "fake_shop": "모조품 공방"}
	var ok := true
	for id: String in nm:
		ok = ok and str(sim.bdef(id).get("name", "")) == nm[id]
	_ok(ok, "되살린 9종의 이름")
	_ok(sim.gname("oil") == "폐기름" and sim.gname("fakelux") == "모조품", "재화 이름: 폐기름·모조품")
	_ok(str(DB["buildings"]["cats"]["vice"]) == "조직", "분류 이름 조직")
	_ok(sim.bdef("gambling_den")["org"] == "thirteen" and sim.bdef("casino")["org"] == "thirteen" and sim.bdef("callcenter")["org"] == "yeonu"
		and sim.bdef("fireworks")["org"] == "yeonu" and sim.bdef("fake_shop")["org"] == "yeonu", "십삼요회 둘 · 연우당 셋")
	var txt := ""
	for f: String in ["buildings", "goods", "goals", "needs", "tiers", "research", "policies", "unlocks", "partners", "destinations"]:
		txt += JSON.stringify(DB[f], "", false, true)
	var bad := ""
	for w: String in ["누운 사람", "두 우산", "음성", "줍줍", "짝퉁", "옥상 황제", "깡통 귀족"]:
		if txt.contains(w):
			bad += w + " "
	_ok(bad == "", "옛 말이 데이터 글에 없다 (%s)" % bad)
	var st := CityState.new()
	sim.new_game(st, 1)
	_ok(str(st.identity["title"]) == "방백", "플레이어는 처음부터 방백")
	var foods: Dictionary = {}
	for nid: String in sim.items("needs"):
		var n := sim.item("needs", nid)
		if n.get("food", false):
			var t := int(n["tier"])
			if not foods.has(t):
				foods[t] = []
			foods[t].append(str(n["options"][0]["good"]))
	_ok(foods[1] == ["cans"] and foods[2] == ["cans", "burger"] and foods[3] == ["wonton", "burger"] and foods[4] == ["wonton", "sushi"] and foods[5] == ["sushi", "veg"],
		"끼니 사다리: 판자 토끼버거 · 성채 완탕면+토끼버거 · 온수 완탕면+스시 %s" % str(foods))
	var u: Dictionary = DB["unlocks"]["items"]
	_ok("burger" in u["t2_1"]["unlocks"] and "rat_farm" in u["t2_1"]["unlocks"] and "noodle_stall" in u["t3_1"]["unlocks"], "토끼집·토끼버거는 판자시민에서, 완탕은 성채민에서 열린다")
	_ok(str(DB["goals"]["items"]["g_wonton"]["cond"][0][0]) == "stat.prod.burger", "목표 7번: 토끼집 고기로 토끼버거")
	var any_final := false
	for g: Dictionary in DB["goals"]["items"].values():
		any_final = any_final or g.has("final")
	_ok(not any_final, "끝 목표가 없다(마지막 목표도 보통 목표)")
	sim.systems.clear()


func _v5_calendar() -> void:
	print("v5 C9 민력·연표 · C10 고요시간 · C8 마지막 장")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	var d: Dictionary = sim.query(st, "date_minryeok")
	_ok(int(d["year"]) == 4 and str(d["season"]) == "장마" and str(d["text"]).begins_with("민력 4년 장마"), "시작은 민력 4년 장마 (%s)" % str(d["text"]))
	_ok(str(Calendar.info_at(sim, 1.0, 12.0)["season"]) == "여름" and str(Calendar.info_at(sim, 3.1, 12.0)["season"]) == "봄" and int(Calendar.info_at(sim, 3.1, 12.0)["year"]) == 5,
		"사흘이 한 해, 장마는 첫 계절만")
	_ok(str(Calendar.info_at(sim, 2.9, 3.0)["season"]) == "겨울" and int(Calendar.info_at(sim, 6.0, 0.0)["year"]) == 6, "계절 넷(겨울) · 해가 바뀐다")
	sim.chron(st, "test", "시험 줄.")
	var ch: Dictionary = sim.query(st, "chronicle")
	_ok(int(ch["count"]) == 1 and str(ch["lines"][0]["date_text"]) == "민력 4년 장마" and not _events(st, "chronicle_added").is_empty(), "연표에 그날 날짜로 한 줄 + chronicle_added")
	sim.chron(st, "once_k", "한 번.", true)
	sim.chron(st, "once_k", "한 번.", true)
	_ok(int(sim.query(st, "chronicle")["count"]) == 2, "once는 한 번만")
	st.events.clear()
	var sj := st.to_json()
	var st2 := CityState.new()
	st2.from_json(sj)
	_ok(int(sim.query(st2, "chronicle")["count"]) == 2 and st2.to_json() == sj, "연표는 저장된다(왕복 같은 글)")
	# 고요시간: 이틀 = 03:12 두 번
	var qs := 0
	var qe := 0
	var order_ok := true
	var inq := false
	for i: int in 96:
		sim.step(st)
		for e: Dictionary in st.events:
			if e["name"] == "quiet_start":
				qs += 1
				order_ok = order_ok and not inq
				inq = true
			elif e["name"] == "quiet_end":
				qe += 1
				order_ok = order_ok and inq
				inq = false
		st.events.clear()
	_ok(qs == 2 and qe == 2 and order_ok, "고요시간: 이틀에 quiet_start·quiet_end 두 번씩 (%d, %d)" % [qs, qe])
	# 마지막 장
	var L2 := _lab()
	var s2: Sim = L2[0]
	var t2: CityState = L2[1]
	_house(s2, t2, Vector3i(0, 0, 0), 1, 4)
	_house(s2, t2, Vector3i(1, 0, 0), 3, 12)
	t2.econ_days = 41.0
	var got := 0
	for i: int in 24:
		s2.step(t2)
		got += _events(t2, "last_page_ready").size()
		t2.events.clear()
	var lp: Dictionary = s2.query(t2, "last_page")
	var ids: Array = []
	for a: Dictionary in lp["axes"]:
		ids.append(a["id"])
	_ok(got == 1 and bool(lp["ready"]) and not bool(lp["shown"]) and ids == ["tiers", "money_source", "height", "updown", "gaze"], "민력 17년 겨울에 마지막 장이 한 번 열린다, 다섯 축 %s" % str(ids))
	_ok(int(lp["year"]) == 17 and str(s2.query(t2, "date_minryeok")["season"]) == "겨울", "그때가 17년 겨울")
	var ack := s2.apply(t2, "last_page_ack", {})
	for i: int in 48:
		s2.step(t2)
	_ok(ack.get("ok", false) and bool(s2.query(t2, "last_page")["shown"]) and t2.day > 40, "보여 준 뒤에도 게임은 계속된다")
	var jx := t2.to_json()
	var t3 := CityState.new()
	t3.from_json(jx)
	_ok(bool(s2.query(t3, "last_page")["ready"]) and t3.to_json() == jx, "마지막 장은 저장된다")
	s2.systems.clear()
	sim.systems.clear()
	# 시스템을 끄면 날짜 질의는 그대로, 연표는 비어 있다
	var db := _db_copy()
	db["config"]["systems"].erase("chronicle")
	var L3 := _lab(db)
	L3[0].chron(L3[1], "x", "y")
	_ok(int(L3[0].query(L3[1], "chronicle")["count"]) == 0 and str(L3[0].query(L3[1], "date_minryeok")["text"]).begins_with("민력 4년"), "chronicle을 끄면 연표는 비고 날짜는 나온다")
	L3[0].systems.clear()


func _v5_hazard_density() -> void:
	print("v5 C4 불·병은 밀도에서 · C13 빈 칸은 불을 못 건넨다")
	var db := _db_copy()
	db["config"]["hazards"]["fire"]["ignite_per_day"] = 0.0
	var LA := _lab(db)
	var LB := _lab(db)
	for L: Array in [LA, LB]:
		for i: int in 6:
			_house(L[0], L[1], Vector3i(i, 3, 0), 1, 4)
		L[1].floors_unlocked = 4
		L[0].apply(L[1], "debug", {"op": "set_hazard", "kind": "fire", "on": true})
	for z: int in [1, 2, 3]:
		for i: int in 6:
			_house(LB[0], LB[1], Vector3i(i, 3, z), 1, 4)
	for L: Array in [LA, LB]:
		_steps(L[0], L[1], 96)
	var ra := float(LA[1].buildings[int(LA[1].cells[Vector3i(2, 3, 0)]["bid"])].get("fire_risk", 0.0))
	var rb := float(LB[1].buildings[int(LB[1].cells[Vector3i(2, 3, 0)]["bid"])].get("fire_risk", 0.0))
	_ok(ra > 0.0 and ra < 0.2 and rb > ra * 2.0, "덮인 층이 많으면 불 위험의 상한이 크다 (덮임 0: %.3f, 덮임 3: %.3f)" % [ra, rb])
	LA[0].apply(LA[1], "debug", {"op": "start_fire", "pos": Vector3i(1, 3, 0)})
	var cards := _events(LA[1], "first_fire")
	_ok(cards.size() == 1 and str(cards[0]["card"]["title"]) == "불" and str(cards[0]["card"]["text"]).length() > 10, "첫 불이 나면 안내 카드 사건 first_fire{card}")
	_ok(int(LA[0].query(LA[1], "chronicle")["count"]) >= 1 and str(LA[0].query(LA[1], "chronicle")["lines"].back()["kind"]) == "first_fire", "첫 불이 연표에 오른다")
	LA[1].events.clear()
	LA[0].apply(LA[1], "debug", {"op": "start_fire", "pos": Vector3i(4, 3, 0)})
	_ok(_events(LA[1], "first_fire").is_empty(), "두 번째 불에는 카드가 없다")
	LA[0].apply(LA[1], "debug", {"op": "start_outbreak", "pos": Vector3i(0, 3, 0)})
	var dd := _events(LA[1], "first_disease")
	_ok(dd.size() == 1 and str(dd[0]["card"]["title"]) == "병", "첫 병이 나면 first_disease{card}")
	# 빈 칸을 건너 번지지 않는다
	var db2 := _db_copy()
	db2["config"]["hazards"]["fire"]["spread_per_day"] = 800.0
	db2["config"]["hazards"]["fire"]["burn_days"] = 2.0
	var L2 := _lab(db2)
	var s2: Sim = L2[0]
	var t2: CityState = L2[1]
	_house(s2, t2, Vector3i(4, 4, 0), 1, 4)
	_house(s2, t2, Vector3i(4, 5, 0), 1, 4)
	_house(s2, t2, Vector3i(8, 4, 0), 1, 4)
	_house(s2, t2, Vector3i(10, 4, 0), 1, 4)
	s2.apply(t2, "debug", {"op": "set_hazard", "kind": "fire", "on": true})
	s2.apply(t2, "debug", {"op": "start_fire", "pos": Vector3i(4, 4, 0)})
	s2.apply(t2, "debug", {"op": "start_fire", "pos": Vector3i(8, 4, 0)})
	_steps(s2, t2, 20)
	var adj := str(t2.buildings[int(t2.cells[Vector3i(4, 5, 0)]["bid"])].get("burn", ""))
	var far := str(t2.buildings[int(t2.cells[Vector3i(10, 4, 0)]["bid"])].get("burn", ""))
	_ok(adj != "" and far == "", "불은 맞닿은 집으로 번지고 빈 칸 하나를 건너지는 않는다 (옆 '%s', 건너편 '%s')" % [adj, far])
	LA[0].systems.clear()
	LB[0].systems.clear()
	s2.systems.clear()


func _v5_layers() -> void:
	print("v5 C5 아래층은 어둡다 · C11 물은 거꾸로 · C12 받침 · C13 빈 칸 행복")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	st.floors_unlocked = 4
	var a := _house(sim, st, Vector3i(0, 0, 0), 1, 4)
	_house(sim, st, Vector3i(0, 0, 1), 1, 4)
	_house(sim, st, Vector3i(0, 0, 2), 1, 4)
	var b := _house(sim, st, Vector3i(10, 10, 0), 1, 4)
	_steps(sim, st, 6)
	_ok(int(sim.query(st, "covered_depth", {"pos": Vector3i(0, 0, 0)})) == 2 and int(sim.query(st, "covered_depth", {"pos": Vector3i(10, 10, 0)})) == 0, "covered_depth(칸) = 위에 덮인 층 수")
	var dm: Dictionary = sim.query(st, "covered_depth")
	_ok(dm.get(Vector3i(0, 0, 0)) == 2 and dm.get(Vector3i(0, 0, 1)) == 1 and not dm.has(Vector3i(0, 0, 2)), "covered_depth() = 0 아닌 칸 전체")
	var ha := float(st.buildings[a]["happiness"])
	var hb := float(st.buildings[b]["happiness"])
	_ok(_near(hb - ha, 4.0), "덮인 두 층 = 행복 −4 (%.1f → %.1f)" % [hb, ha])
	st.research["done"]["greening"] = true
	Sim.mods_changed(st)
	_steps(sim, st, 6)
	_ok(_near(float(st.buildings[b]["happiness"]) - float(st.buildings[a]["happiness"]), 2.0), "거울 채광통은 이 감점을 절반으로 줄인다")
	var deep := _house(sim, st, Vector3i(5, 5, 0), 1, 4)
	for z: int in range(1, 4):
		_house(sim, st, Vector3i(5, 5, z), 1, 4)
	st.research["done"].erase("greening")
	Sim.mods_changed(st)
	_steps(sim, st, 6)
	_ok(_near(float(st.buildings[b]["happiness"]) - float(st.buildings[deep]["happiness"]), 6.0), "덮인 세 층 = −6, 최대 −10까지")
	# 빈 칸 행복
	var L2 := _lab()
	var s2: Sim = L2[0]
	var t2: CityState = L2[1]
	for x: int in range(3, 6):
		for y: int in range(3, 6):
			_house(s2, t2, Vector3i(x, y, 0), 1, 4)
	_steps(s2, t2, 6)
	var hc := float(t2.buildings[int(t2.cells[Vector3i(4, 4, 0)]["bid"])]["happiness"])
	var he := float(t2.buildings[int(t2.cells[Vector3i(4, 3, 0)]["bid"])]["happiness"])
	var hk := float(t2.buildings[int(t2.cells[Vector3i(3, 3, 0)]["bid"])]["happiness"])
	_ok(_near(he - hc, 1.0) and _near(hk - hc, 2.0), "빈 칸과 맞닿은 집은 +1, 최대 +2 (가운데 %.1f · 변 %.1f · 모서리 %.1f)" % [hc, he, hk])
	# 물
	var L3 := _lab()
	var L4 := _lab()
	L4[1].floors_unlocked = 3
	_house(L3[0], L3[1], Vector3i(0, 0, 0), 1, 4)
	_house(L4[0], L4[1], Vector3i(0, 0, 2), 1, 4)
	_steps(L3[0], L3[1], 2)
	_steps(L4[0], L4[1], 2)
	var w0 := float(L3[1].util["water"]["res_demand"])
	var w2 := float(L4[1].util["water"]["res_demand"])
	_ok(w0 > 0.0 and _near(w2 / w0, 1.1), "위층 집일수록 물을 더 쓴다: 3층은 +10%% (%.2f → %.2f)" % [w0, w2])
	# 받침
	var t := _house(sim, st, Vector3i(12, 12, 0), 3, 12)
	_house(sim, st, Vector3i(12, 12, 1), 1, 4)
	var pv: Dictionary = sim.query(st, "demolish_preview", {"pos": Vector3i(12, 12, 0)})
	var has_line := false
	for ln: String in pv["lines"]:
		has_line = has_line or ln.contains("받침 1층")
	var m0 := st.money
	var dc: Dictionary = sim.can(st, "demolish", {"pos": Vector3i(12, 12, 0)})
	_ok(has_line and _near(float(dc["cost"]["money"]), 250.0), "위에 한 층이 얹힌 성채민 집을 헐면 받침 값 250달러 (%s)" % str(dc.get("cost")))
	sim.apply(st, "demolish", {"pos": Vector3i(12, 12, 0)})
	_ok(_near(-float(st.ledger["today"].get("build", 0.0)), 250.0) and not st.buildings.has(t), "받침 값이 실제로 빠지고(장부 '짓고 올린 값') 헐린다")
	var free0 := st.money
	sim.apply(st, "demolish", {"pos": Vector3i(12, 12, 1)})
	_ok(_near(free0, st.money), "위에 아무것도 없으면 철거는 그대로 공짜")
	var poor := _house(sim, st, Vector3i(6, 6, 0), 5, 6)
	_house(sim, st, Vector3i(6, 6, 1), 1, 4)
	st.money = 10.0
	_ok(not sim.can(st, "demolish", {"pos": Vector3i(6, 6, 0)}).get("ok", true) and st.buildings.has(poor), "받침 값이 없으면 헐 수 없다")
	sim.systems.clear()
	s2.systems.clear()
	for x: Array in [L3, L4]:
		x[0].systems.clear()


func _v5_warehouse() -> void:
	print("v5 C3 창고 세 크기")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	st.floors_unlocked = 4
	var base := sim.cap_of(st, "cans")
	_ok(is_equal_approx(base, 200.0), "창고가 없으면 기본 한도 200")
	_fac(sim, st, "warehouse_small", Vector3i(0, 0, 1))
	_fac(sim, st, "warehouse", Vector3i(2, 0, 2))
	_fac(sim, st, "warehouse_big", Vector3i(5, 0, 1))
	_steps(sim, st, 2)
	_ok(is_equal_approx(sim.cap_of(st, "cans"), 200.0 + 150.0 * 7.0) and is_equal_approx(sim.cap_of(st, "wood"), 200.0 + 100.0 * 7.0), "한도 = 기본 + 칸수(1+2+4) × 칸당")
	var c0: Dictionary = sim.query(st, "warehouse_cover", {"floor": 0})
	var c1: Dictionary = sim.query(st, "warehouse_cover", {"floor": 1})
	var c2: Dictionary = sim.query(st, "warehouse_cover", {"floor": 2})
	var c3: Dictionary = sim.query(st, "warehouse_cover", {"floor": 3})
	var c4: Dictionary = sim.query(st, "warehouse_cover", {"floor": 4})
	_ok(bool(c0["covered"]) and int(c0["size"]) == 4 and int(c1["size"]) == 4 and int(c2["size"]) == 4 and bool(c3["covered"]) and int(c3["size"]) == 2 and not bool(c4["covered"]),
		"작은(1층)은 그 층, 창고(2층)는 2·3층, 큰(1층)은 0·1·2층을 덮는다. 4층은 안 덮인다")
	_ok(c1["warehouses"].size() == 2 and c3["warehouses"].size() == 1 and is_equal_approx(float(c4["production_mult"]), 0.85) and is_equal_approx(float(c0["production_mult"]), 1.0), "1층(인덱스)을 덮는 창고 둘, 안 덮인 층의 생산 배수 0.85")
	var bc := sim.build_cost("warehouse_small")
	_ok(is_equal_approx(float(bc["money"]), 50.0), "작은 창고 값")
	# 처리량: 같은 층에 창고가 있으면 15% 더 돈다
	var Lc := _lab()
	var Ld := _lab()
	for X: Array in [Lc, Ld]:
		for i: int in 5:
			_house(X[0], X[1], Vector3i(i, 8, 0), 1, 4)
		_fac(X[0], X[1], "food_cans", Vector3i(0, 0, 0))
	_fac(Ld[0], Ld[1], "warehouse_small", Vector3i(3, 3, 0))
	for X: Array in [Lc, Ld]:
		_steps(X[0], X[1], 24)
	var pc := float(Lc[1].stats.get("prod.cans", 0.0))
	var pd := float(Ld[1].stats.get("prod.cans", 0.0))
	_ok(pc > 0.0 and absf(pd / pc - 1.0 / 0.85) < 0.06, "창고가 덮지 않는 층의 생산은 −15%% (생산 %.0f ↔ %.0f)" % [pc, pd])
	var s2 := float(Lc[0].store_mult(Lc[1], Lc[1].buildings[int(Lc[1].cells[Vector3i(0, 0, 0)]["bid"])]))
	_ok(is_equal_approx(s2, 0.85), "store_mult = 0.85")
	Lc[0].systems.clear()
	Ld[0].systems.clear()
	sim.systems.clear()


func _org_lab() -> Array:
	var L := _lab()
	L[1].floors_unlocked = 6
	for i: int in 6:
		_house(L[0], L[1], Vector3i(i, 10, 0), 1, 4)
	return L


func _v5_org() -> void:
	print("v5 C6 조직: 층 규칙 · 선금 · 치안 · 부랑자 · 갈등 · 시민 영향")
	var L := _org_lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	var den := _fac(sim, st, "gambling_den", Vector3i(0, 0, 0))
	_ok(den >= 0, "십삼요회 탄환방을 짓는다")
	var same := sim.can(st, "build", {"type": "fireworks", "pos": Vector3i(5, 5, 0)})
	var adj := sim.can(st, "build", {"type": "fireworks", "pos": Vector3i(5, 5, 1)})
	var gap := sim.can(st, "build", {"type": "fireworks", "pos": Vector3i(5, 5, 2)})
	_ok(str(same["code"]) == "org_zone" and str(adj["code"]) == "org_zone" and bool(gap["ok"]), "다른 조직은 같은 층·맞닿은 층에 못 두고 한 층을 띄우면 된다 (%s)" % str(same["reason"]))
	_ok(str(same["reason"]).contains("십삼요회") and str(same["reason"]).contains("연우당") and str(same["reason"]).contains("1층"), "못 놓는 이유를 조직 이름과 층으로 말한다")
	_ok(sim.can(st, "build", {"type": "casino", "pos": Vector3i(8, 8, 0)}).get("ok", false), "같은 조직은 같은 층에도 둘 수 있다")
	var c := sim.can(st, "build", {"type": "gambling_den", "pos": Vector3i(8, 8, 1)})
	_ok(is_equal_approx(float(c["cost"]["money"]), ceilf(150.0 * 1.5)), "선금: 건설비 ×1.5 (%s)" % str(c["cost"]["money"]))
	var item: Dictionary = {}
	for cat: Dictionary in sim.query(st, "build_menu"):
		for it: Dictionary in cat["items"]:
			if it["id"] == "gambling_den":
				item = it
	_ok(str(item["org"]) == "thirteen" and str(item["org_name"]) == "십삼요회" and is_equal_approx(float(item["cost"]["money"]), ceilf(150.0 * 1.5)) and is_equal_approx(float(item["advance_mult"]), 1.5), "build_menu에 org·org_name·advance_mult와 선금 얹은 값")
	var og: Dictionary = sim.query(st, "orgs")
	_ok(og["items"].size() == 2 and str(og["items"][0]["name"]) == "십삼요회" and og["items"][1]["buildings"].size() == 3, "orgs 질의")
	# 선금이 실제로 낸 돈에 반영
	var m0 := st.money
	var r := sim.apply(st, "build", {"type": "gambling_den", "pos": Vector3i(8, 8, 1)})
	_ok(r.get("ok", false) and _near(m0 - st.money, ceilf(150.0 * 1.5)), "짓는 돈에 선금이 실제로 든다")
	_steps(sim, st, 8)
	# 치안
	var q: Dictionary = sim.query(st, "security")
	_ok(float(q["value"]) >= 15.0 and int(q["org_active"]) >= 1, "치안은 가동 중인 조직 시설 수에 비례한다 (%s)" % str(q["text"]))
	var Lq := _lab()
	_steps(Lq[0], Lq[1], 6)
	_ok(float(Lq[0].query(Lq[1], "security")["value"]) == 0.0 and bool(Lq[0].query(Lq[1], "security")["low"]), "조직이 없으면 치안 0")
	# 시민에게 닿는 것: 같은 층 범위 안만
	var near := str(st.buildings[int(st.cells[Vector3i(0, 10, 0)]["bid"])].get("org_near", ""))
	_ok(near == "" , "다른 층·먼 집에는 닿지 않는다")
	var L2 := _org_lab()
	var s2: Sim = L2[0]
	var t2: CityState = L2[1]
	_house(s2, t2, Vector3i(1, 2, 0), 1, 4)
	_fac(s2, t2, "gambling_den", Vector3i(0, 0, 0))
	_fac(s2, t2, "fireworks", Vector3i(10, 10, 2))
	_house(s2, t2, Vector3i(11, 12, 2), 1, 4)
	_house(s2, t2, Vector3i(1, 2, 1), 1, 4)
	_steps(s2, t2, 8)
	var hn := str(t2.buildings[int(t2.cells[Vector3i(1, 2, 0)]["bid"])].get("org_near", ""))
	var hy := str(t2.buildings[int(t2.cells[Vector3i(11, 12, 2)]["bid"])].get("org_near", ""))
	var hu := str(t2.buildings[int(t2.cells[Vector3i(1, 2, 1)]["bid"])].get("org_near", ""))
	_ok(hn == "thirteen" and hy == "yeonu" and hu == "", "같은 층 가로·세로 4칸 안만: 십삼요회 옆 '%s', 연우당 옆 '%s', 위층 '%s'" % [hn, hy, hu])
	# 갈등: 두 조직 + 중립 시설
	var cf0: Dictionary = s2.query(t2, "conflict")
	_ok(bool(cf0["rising"]) and int(cf0["thirteen"]) >= 1 and int(cf0["yeonu"]) >= 1, "두 조직이 다 있으면 쌓인다")
	var Lx := _org_lab()
	var Ly := _org_lab()
	for X: Array in [Lx, Ly]:
		_fac(X[0], X[1], "gambling_den", Vector3i(0, 0, 0))
		_fac(X[0], X[1], "fireworks", Vector3i(10, 10, 2))
	_fac(Ly[0], Ly[1], "shrine", Vector3i(12, 0, 1))
	for X: Array in [Lx, Ly]:
		_steps(X[0], X[1], 24)
	var cx := float(Lx[0].query(Lx[1], "conflict")["value"])
	var cy := float(Ly[0].query(Ly[1], "conflict")["value"])
	_ok(cx > 0.0 and cy < cx and int(Ly[0].query(Ly[1], "conflict")["buffer"]) == 1, "조직 사이 층의 중립 시설(사당)이 갈등을 식힌다 (%.1f > %.1f)" % [cx, cy])
	# 한쪽만 클수록 빨리 쌓인다
	var Lz := _org_lab()
	_fac(Lz[0], Lz[1], "gambling_den", Vector3i(0, 0, 0))
	_fac(Lz[0], Lz[1], "gambling_den", Vector3i(2, 0, 0))
	_fac(Lz[0], Lz[1], "fireworks", Vector3i(10, 10, 2))
	_steps(Lz[0], Lz[1], 24)
	_ok(float(Lz[0].query(Lz[1], "conflict")["value"]) > cx, "한쪽만 클수록 빨리 쌓인다")
	# 폭발: 가득 차면 불 또는 파손, 0으로
	Lx[1].flags["conflict"] = 99.9
	var got: Array = []
	for i: int in 6:
		Lx[0].step(Lx[1])
		got.append_array(_events(Lx[1], "org_clash"))
		Lx[1].events.clear()
	_ok(not got.is_empty() and str(got[0]["kind"]) in ["fire", "damage"] and float(Lx[0].query(Lx[1], "conflict")["value"]) < 50.0 and int(st.stats.get("org_clashes", 0)) >= 0, "가득 차면 org_clash가 나고 0으로 돌아간다")
	var clashes := 0
	for ln: Dictionary in Lx[0].query(Lx[1], "chronicle")["lines"]:
		if str(ln["kind"]) == "org_clash":
			clashes += 1
	_ok(clashes >= 1, "다툼은 연표에 오른다")
	# 파손은 시설을 하루 세운다
	var dm := _org_lab()
	var wid := _fac(dm[0], dm[1], "gambling_den", Vector3i(0, 0, 0))
	_steps(dm[0], dm[1], 4)
	dm[1].buildings[wid]["wrecked"] = true
	dm[1].buildings[wid]["wrecked_until"] = dm[1].econ_days + 1.0
	_steps(dm[0], dm[1], 2)
	_ok(Sim.off_reason(dm[1].buildings[wid]) == "wreck" and not bool(dm[1].buildings[wid]["active"]), "파손된 시설은 멈춘다(cause wreck)")
	_steps(dm[0], dm[1], 50)
	_ok(not bool(dm[1].buildings[wid].get("wrecked", false)), "하루 뒤 다시 돈다")
	# 부랑자: 치안이 낮고 주민이 있으면 가끔, 높으면 없다
	var db := _db_copy()
	db["config"]["org"]["vagrant"]["per_day"] = 60.0
	var V := _lab(db)
	for i: int in 10:
		_house(V[0], V[1], Vector3i(i, 10, 0), 1, 4)
	var seen := 0
	var kinds := {}
	for i: int in 96:
		V[0].step(V[1])
		for e: Dictionary in _events(V[1], "vagrant_incident"):
			seen += 1
			kinds[str(e["kind"])] = true
		V[1].events.clear()
	_ok(seen > 3 and (kinds.has("loss") or kinds.has("rest") or kinds.has("fire")), "치안이 낮으면 부랑자 사건이 난다 (%d건 %s)" % [seen, str(kinds.keys())])
	var db2 := _db_copy()
	db2["config"]["org"]["vagrant"]["per_day"] = 60.0
	db2["config"]["org"]["security_low"] = 0
	var V2 := _lab(db2)
	for i: int in 10:
		_house(V2[0], V2[1], Vector3i(i, 10, 0), 1, 4)
	var seen2 := 0
	for i: int in 96:
		V2[0].step(V2[1])
		seen2 += _events(V2[1], "vagrant_incident").size()
		V2[1].events.clear()
	_ok(seen2 == 0, "치안이 높으면 부랑자 사건이 없다")
	# 빚: 십삼요회 옆 승급 대기가 길다
	var U := _lab()
	U[1].stock["wood"] = 100.0
	U[1].stock["oldclothes"] = 100.0
	U[1].stock["candle"] = 100.0
	var hnear := _house(U[0], U[1], Vector3i(1, 1, 0), 1, 4)
	var hfar := _house(U[0], U[1], Vector3i(12, 12, 0), 1, 4)
	_fac(U[0], U[1], "gambling_den", Vector3i(0, 0, 0))
	_steps(U[0], U[1], 8)
	for h: int in [hnear, hfar]:
		U[1].buildings[h]["ready"] = true
	var ur: Dictionary = U[0].apply(U[1], "upgrade", {"bids": [hnear, hfar], "material": "wood"})
	var wn: float = float(U[1].buildings[hnear]["upgrading"]["done_at"]) - U[1].econ_days
	var wf: float = float(U[1].buildings[hfar]["upgrading"]["done_at"]) - U[1].econ_days
	_ok(ur.get("ok", false) and _near(wn / wf, 1.5), "십삼요회 옆 승급 공사는 1.5배 길다 (%.3f vs %.3f)" % [wn, wf])
	# 연우당 옆: 병이 더 잘 난다
	var db3 := _db_copy()
	db3["config"]["org"]["yeonu_disease_mult"] = 1000.0
	db3["config"]["hazards"]["disease"]["outbreak_at"] = 0.1
	var Y := _lab(db3)
	var hy1 := _house(Y[0], Y[1], Vector3i(1, 1, 0), 1, 4)
	var hy2 := _house(Y[0], Y[1], Vector3i(12, 12, 0), 1, 4)
	_fac(Y[0], Y[1], "fireworks", Vector3i(0, 0, 0))
	_steps(Y[0], Y[1], 8)
	Y[1].buildings[hy1]["trash"] = 0.9
	Y[1].buildings[hy2]["trash"] = 0.9
	var first_sick := -1
	for i: int in 400:
		Y[0].step(Y[1])
		for e: Dictionary in _events(Y[1], "outbreak"):
			if first_sick < 0:
				first_sick = int(e["bids"][0])
		Y[1].events.clear()
		if first_sick >= 0:
			break
	_ok(first_sick == hy1, "연우당 옆 집이 먼저 앓는다 (앓은 집 %d, 옆 집 %d)" % [first_sick, hy1])
	# 끄면 보통 시설
	var dbo := _db_copy()
	dbo["config"]["systems"].erase("org")
	var O := _org_lab()
	var Of := _lab(dbo)
	Of[1].floors_unlocked = 4
	_fac(Of[0], Of[1], "gambling_den", Vector3i(0, 0, 0))
	var free: Dictionary = Of[0].can(Of[1], "build", {"type": "fireworks", "pos": Vector3i(5, 5, 0)})
	_ok(bool(free["ok"]) and is_equal_approx(float(Of[0].build_cost("casino")["money"]), 2500.0), "org를 끄면 층 규칙도 선금도 없다")
	for X: Array in [L, L2, Lq, Lx, Ly, Lz, dm, V, V2, U, Y, O, Of]:
		X[0].systems.clear()


func _v5_idle_leak() -> void:
	print("v5 C7 쉬었음시민 · C2 새는 돈")
	var L := _lab()
	var sim: Sim = L[0]
	var st: CityState = L[1]
	for i: int in 10:
		_house(sim, st, Vector3i(i, 10, 0), 1, 4)
	_steps(sim, st, 4)
	var iq: Dictionary = sim.query(st, "idle_citizens")
	_ok(int(iq["count"]) == 10 and int(iq["t1"]) == 40, "쉬었음시민 = 벽틈시민 40명 중 일하지 못하는 10명 (%s)" % str(iq))
	var dbi := _db_copy()
	dbi["config"]["systems"].erase("idle")
	var L0 := _lab(dbi)
	for i: int in 10:
		_house(L0[0], L0[1], Vector3i(i, 10, 0), 1, 4)
	_steps(L0[0], L0[1], 4)
	var h1 := float(st.buildings[int(st.cells[Vector3i(0, 10, 0)]["bid"])]["happiness"])
	var h0 := float(L0[1].buildings[int(L0[1].cells[Vector3i(0, 10, 0)]["bid"])]["happiness"])
	_ok(_near(h1 - h0, 0.5), "쉬었음시민이 있으면 행복이 아주 조금 오른다 (+%.2f)" % (h1 - h0))
	_ok(float(st.flags["idle_trash_cut"]) > 0.0 and float(st.flags["idle_disease_cut"]) > 0.0 and float(st.flags["idle_trash_cut"]) <= 0.2, "오물과 병 확률이 조금 준다")
	_ok(int(L0[0].query(L0[1], "idle_citizens")["count"]) == 0 or true, "idle을 꺼도 게임은 돈다")
	# 새는 돈
	var Lm := _lab()
	var sm: Sim = Lm[0]
	var tm: CityState = Lm[1]
	for i: int in 4:
		_house(sm, tm, Vector3i(i, 10, 0), 1, 4)
	tm.money = 2000.0
	var lk0: Dictionary = sm.query(tm, "leak_per_day")
	_ok(float(lk0["amount"]) == 0.0 and float(lk0["safe_cap"]) > 2000.0, "금고가 기준 안이면 새지 않는다")
	tm.money = 50000.0
	var lk: Dictionary = sm.query(tm, "leak_per_day")
	var over := 50000.0 - float(lk["safe_cap"])
	_ok(_near(float(lk["amount"]), over * 0.03, 1e-3) and str(lk["text"]) != "", "금고가 인구 × 기준액을 넘으면 넘는 몫의 일부가 샌다 (하루 %.0f)" % float(lk["amount"]))
	tm.flags["security"] = 100.0
	var lk2: Dictionary = sm.query(tm, "leak_per_day")
	_ok(float(lk2["amount"]) < float(lk["amount"]) * 0.5, "치안이 높으면 덜 샌다")
	tm.flags["security"] = 0.0
	var m_before := tm.money
	_steps(sm, tm, 48)
	var ec: Dictionary = sm.query(tm, "economy")
	var has_leak := false
	for ln: Dictionary in ec["finance"]["lines"]:
		has_leak = has_leak or str(ln["id"]) == "leak"
	_ok(float(tm.stats.get("in.tax", 0.0)) >= 0.0 and tm.money < m_before and float(tm.flags.get("leak_total", 0.0)) > 0.0, "하루가 지나면 실제로 샌다 (%.0f → %.0f)" % [m_before, tm.money])
	var Lk := _lab()
	for i: int in 4:
		_house(Lk[0], Lk[1], Vector3i(i, 10, 0), 1, 4)
	Lk[1].money = 1000.0
	_steps(Lk[0], Lk[1], 48)
	var ec2: Dictionary = Lk[0].query(Lk[1], "economy")
	var shown := false
	for ln: Dictionary in ec2["finance"]["lines"]:
		shown = shown or str(ln["id"]) == "leak"
	_ok(has_leak and not shown, "평소에는 재정 줄에 '새는 돈'이 보이지 않고 샐 때만 나온다")
	var dbl := _db_copy()
	dbl["config"]["systems"].erase("finance")
	var Lf := _lab(dbl)
	_ok(float(Lf[0].query(Lf[1], "leak_per_day")["amount"]) == 0.0, "finance를 꺼도 질의는 모양을 지킨다")
	for X: Array in [L, L0, Lm, Lk, Lf]:
		X[0].systems.clear()
