extends SceneTree
## sim_run — 봇 하나에게 N경제일을 맡겨 헤드리스로 돌리고 리포트를 쓴다.
##   godot --headless --path godot -s res://tools/sim_run.gd -- bot=balanced days=30 seed=1 [out=<md 경로>] [quiet]
## 기본 출력: ../simulation/reports/core_<bot>.md (+ 같은 이름 .json: 일별 지표)
## 봇은 경제 1시간마다 한 번 손을 댄다(접속 중 계속 플레이 가정).


const Pattern := preload("res://tools/sim_pattern.gd")


## 기본: 접속 패턴 시뮬(실제 일수). mode=econ이면 옛 방식(계속 접속, 경제일 수 = days).
##   godot --headless --path godot -s res://tools/sim_run.gd -- bot=balanced real_days=7 seed=1 [out=<md>] [quiet]
##   godot --headless --path godot -s res://tools/sim_run.gd -- mode=econ bot=balanced days=30
## 출력: ../simulation/reports/<bot>.md + .json(요약 행·일별 행)
func _init() -> void:
	var args := {"bot": "balanced", "days": "30", "real_days": "7", "seed": "1", "out": "", "mode": "pattern"}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(args["out"])
	var ok := false
	if args["mode"] == "econ":
		if out == "":
			out = ProjectSettings.globalize_path("res://").path_join("../simulation/reports/core_%s.md" % args["bot"]).simplify_path()
		var r := run(str(args["bot"]), int(args["days"]), int(args["seed"]), not args.has("quiet"))
		ok = r["ok"]
		if ok:
			SimIO.write_text(out, report(r))
			SimIO.write_text(out.get_basename() + ".json", JSON.stringify({"rows": r["rows"], "timeline": r["timeline"], "blocked": r["bot"].blocked}, " "))
		(r["sim"] as Sim).systems.clear()
	else:
		if out == "":
			out = ProjectSettings.globalize_path("res://").path_join("../simulation/reports/%s.md" % args["bot"]).simplify_path()
		var r := Pattern.run(str(args["bot"]), int(args["real_days"]), int(args["seed"]), not args.has("quiet"))
		ok = r["ok"]
		if ok:
			SimIO.write_text(out, Pattern.report_md(r, per_cell(r["sim"], r["state"])))
			SimIO.write_text(out.get_basename() + ".json", JSON.stringify(Pattern.summary_row(r), " "))
		(r["sim"] as Sim).systems.clear()
	if ok:
		print("report: ", out)
	quit(0 if ok else 1)


static func run(bot_id: String, days: int, seed_value: int, verbose: bool = true, db_override: Dictionary = {}) -> Dictionary:
	var db := db_override if not db_override.is_empty() else SimIO.load_db()
	var sim := Sim.new()
	sim.setup(db)
	if not sim.errors.is_empty():
		for e: String in sim.errors:
			print("DATA ERROR ", e)
		return {"ok": false, "sim": sim}
	var bot := Bot.new(sim, bot_id)
	var state := CityState.new()
	sim.new_game(state, seed_value)
	var rows: Array = []
	var min_money := state.money
	var t0 := Time.get_ticks_msec()
	var hour := 1.0 / 24.0
	var day := state.day
	while state.econ_days < float(days) + 0.25 - 1e-9:
		bot.act(state)
		sim.tick(state, hour)
		state.events.clear()
		min_money = minf(min_money, state.money)
		if state.day != day:
			var row := daily(sim, state, day)
			rows.append(row)
			if verbose:
				print("%s d%02d pop %s money %d net %.0f hap %.0f floors %d" % [bot_id, day, row["pop"], int(state.money), float(row["net"]), state.happiness, state.floors_unlocked])
			day = state.day
	if verbose:
		print("ran %d days in %.1fs" % [days, float(Time.get_ticks_msec() - t0) / 1000.0])
	return {"ok": true, "sim": sim, "state": state, "bot": bot, "rows": rows, "timeline": timeline(state), "min_money": min_money, "days": days, "seed": seed_value}


static func daily(sim: Sim, state: CityState, d: int) -> Dictionary:
	var m := Metrics.compute(sim, state)
	var pop: Array = []
	for t: int in range(1, 6):
		pop.append(int(m.get("pop.t%d" % t, 0)))
	var led: Dictionary = state.ledger["days"].back() if not (state.ledger["days"] as Array).is_empty() else {}
	var lab: Array = []
	for t: int in range(1, 6):
		var l: Dictionary = state.labor.get(t, {"have": 0, "need": 0.0})
		lab.append(int(l["have"]) - int(ceilf(float(l["need"]))))
	var basic_ok := 0
	var houses := 0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house":
			houses += 1
			if b["need_state"] == "ok":
				basic_ok += 1
	return {"day": d, "pop": pop, "money": int(state.money), "net": float(led.get("net", 0.0)), "tax": float(led.get("tax", 0.0)), "ledger": led,
		"labor_spare": lab, "houses": houses, "houses_ok": basic_ok, "happiness": snappedf(state.happiness, 0.1),
		"floors": state.floors_unlocked, "facilities": int(m.get("sites", 0)), "water": [snappedf(float(state.util.get("water", {}).get("supply", 0)), 1), snappedf(float(state.util.get("water", {}).get("demand", 0)), 1)],
		"power": [snappedf(float(state.util.get("power", {}).get("supply", 0)), 1), snappedf(float(state.util.get("power", {}).get("demand", 0)), 1)]}


static func timeline(state: CityState) -> Dictionary:
	var t := {}
	for k: String in ["first_resident_day", "first_upgrade_t2_day", "first_upgrade_t3_day", "first_upgrade_t4_day", "first_upgrade_t5_day",
			"floor_2_day", "floor_3_day", "first_power_day"]:
		t[k] = state.stats.get(k, -1.0)
	return t


static func _d(x: Variant) -> String:
	return "—" if float(x) < 0.0 else "%.2f일 (실제 %d분)" % [float(x), int(float(x) * 10.0)]


static func report(r: Dictionary) -> String:
	var sim: Sim = r["sim"]
	var state: CityState = r["state"]
	var rows: Array = r["rows"]
	var L: Array = []
	L.append("# 코어 경제 시뮬 — %s 봇 (%d경제일, seed %d)" % [sim.item("bots", r["bot"].id).get("name", r["bot"].id), int(r["days"]), int(r["seed"])])
	L.append("")
	L.append("자동 생성: `godot/tools/sim_run.gd`. 1경제일 = 접속 중 실제 10분. 봇은 경제 1시간마다 손을 댄다(계속 접속 가정).")
	L.append("탐험(B 파트)이 없으므로 세 계열 자재는 봇이 `debug add_stock`으로 하루 %d개씩 넣는다(근거리 2팀 상시 가동 흉내). 그 밖의 자원은 전부 규칙대로 얻었다." % int(sim.item("bots", r["bot"].id).get("expedition_per_day", 0)))
	L.append("")
	L.append("## 타임라인")
	var tl: Dictionary = r["timeline"]
	L.append("| 사건 | 경제일 |")
	L.append("|---|---|")
	var names := {"first_resident_day": "첫 주민", "first_upgrade_t2_day": "첫 승급 → 세입자", "first_upgrade_t3_day": "첫 승급 → 토박이",
		"first_upgrade_t4_day": "첫 승급 → 유지", "first_upgrade_t5_day": "첫 승급 → 거물", "floor_2_day": "2층 열림", "floor_3_day": "3층 열림", "first_power_day": "첫 전기"}
	for k: String in names:
		L.append("| %s | %s |" % [names[k], _d(tl.get(k, -1.0))])
	L.append("")
	L.append("최저 금고: ₩%d (음수 불가 규칙 — 0이면 파산 정지가 있었다는 뜻)." % int(r["min_money"]))
	L.append("")
	L.append("## 일별 계층 인구 · 노동 여유(배정 가능 − 필요) · 금고")
	L.append("| 일 | 떠돌이 | 세입자 | 토박이 | 유지 | 거물 | 노동 여유 T1/T2/T3/T4/T5 | 주거(충족/전체) | 행복 | 금고 | 순수지/일 | 물 공급/수요 | 전기 공급/수요 | 층 |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for row: Dictionary in rows:
		var p: Array = row["pop"]
		L.append("| %d | %d | %d | %d | %d | %d | %s | %d/%d | %.0f | %d | %.0f | %d/%d | %d/%d | %d |" % [row["day"], p[0], p[1], p[2], p[3], p[4],
			"/".join(PackedStringArray(row["labor_spare"].map(func(x: int) -> String: return str(x)))), row["houses_ok"], row["houses"], row["happiness"],
			row["money"], row["net"], row["water"][0], row["water"][1], row["power"][0], row["power"][1], row["floors"]])
	L.append("")
	# 수요 충족
	L.append("## 마지막 날 수요 충족(계층별 평균 충족률, 주민 가중)")
	var acc := {}
	for b: Dictionary in state.buildings.values():
		if b["kind"] != "house" or int(b["residents"]) == 0:
			continue
		for nid: String in b["needs"]:
			var a: Array = acc.get(nid, [0.0, 0.0])
			a[0] += float(b["needs"][nid].get("ratio", 0.0)) * float(b["residents"])
			a[1] += float(b["residents"])
			acc[nid] = a
	L.append("| 수요 | 역할 | 평균 충족 |")
	L.append("|---|---|---|")
	for nid: String in sim.items("needs"):
		if acc.has(nid):
			var n := sim.item("needs", nid)
			L.append("| %s %s | %s | %.0f%% |" % [sim.tname(int(n["tier"])), n["name"], n["role"], 100.0 * float(acc[nid][0]) / maxf(1.0, float(acc[nid][1]))])
	L.append("")
	# 재고 버팀
	L.append("## 마지막 날 재고와 버팀(경제일)")
	var eco: Dictionary = sim.query(state, "economy")
	L.append("| 상품 | 재고 | 한도 | 생산/일 | 소비/일 | 수입/일 | 수출/일 | 순 | 버팀 |")
	L.append("|---|---|---|---|---|---|---|---|---|")
	for g: Dictionary in eco["goods"]:
		if float(g["stock"]) > 0.0 or float(g["cons"]) > 0.0 or float(g["prod"]) > 0.0:
			L.append("| %s | %.0f | %.0f | %.1f | %.1f | %.1f | %.1f | %.1f | %s |" % [g["name"], g["stock"], g["cap"], g["prod"], g["cons"], g["imp"], g["exp"], g["net"],
				"늘어남" if float(g["days_left"]) < 0.0 else str(g["days_left"])])
	L.append("")
	L.append("## 장부(최근 %d일 평균, ₩/경제일)" % (state.ledger["days"] as Array).size())
	L.append("| 줄 | 금액 |")
	L.append("|---|---|")
	for l: Dictionary in eco["finance"]["lines"]:
		L.append("| %s | %.1f |" % [l["name"], l["amount"]])
	L.append("| **순** | **%.1f** |" % float(eco["finance"]["net"]))
	L.append("")
	L.append("## 마지막 날 시설(완공·공사 중)")
	var fc := {}
	var upk := 0.0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "facility" or b["kind"] == "site":
			var k := str(b["type"])
			var a: Array = fc.get(k, [0, 0, 0.0, {}])
			a[0] += 1
			if b.get("active", false):
				a[1] += 1
			var cz := str(b.get("cause", "site" if b["kind"] == "site" else ""))
			a[3][cz] = int(a[3].get(cz, 0)) + 1
			a[2] += float(sim.bdef(k).get("upkeep", 0))
			fc[k] = a
			upk += float(sim.bdef(k).get("upkeep", 0))
	L.append("| 시설 | 수 | 가동 | 유지비/일 | 상태(원인별 수) |")
	L.append("|---|---|---|---|---|")
	for k: String in fc:
		L.append("| %s | %d | %d | %.0f | %s |" % [sim.bdef(k).get("name", k), fc[k][0], fc[k][1], fc[k][2], JSON.stringify(fc[k][3])])
	L.append("| 합계 | | | %.0f | |" % upk)
	L.append("")
	L.append("## 마지막 날 계약")
	var cq: Dictionary = sim.query(state, "contracts")
	L.append("자리 %d/%d" % [int(cq["slots"]["used"]), int(cq["slots"]["max"])])
	for k: Dictionary in cq["active"]:
		L.append("- %s %s %s %d개/%d시간 @₩%s — 지난 회차: %s" % [k["partner_name"], k["good_name"], "수입" if k["dir"] == "import" else "수출", k["qty"], k["interval_h"], str(k["price"]), k["last_text"]])
	L.append("")
	L.append_array(per_cell(sim, state))
	L.append("")
	L.append("## 세 계열 자재(디렉터 수정 4 — 구역 단위 총량)")
	var acc_q := 0
	var row := "누적(떠돌이 판잣집 한 채를 그 계층까지): "
	var parts_q: Array = []
	var district: Array = []
	for t: int in range(1, sim.max_tier()):
		acc_q += int(sim.item("upgrade_costs", "%dto%d" % [t, t + 1])["qty"])
		parts_q.append("%s %d" % [sim.tname(t + 1), acc_q])
		district.append("%s 100채 = %d" % [sim.tname(t + 1), acc_q * 100])
	L.append(row + ", ".join(parts_q) + ".")
	L.append("한 층(약 100채)을 전부 그 계층으로: " + ", ".join(district) + ".")
	var got := 0.0
	var used := 0.0
	for m: String in sim.db["upgrade_costs"]["materials"]:
		got += float(state.stats.get("debug_stock." + m, 0.0))
		used += float(state.stats.get("used." + m, 0.0))
	L.append("이번 실행: 탐험 흉내로 받은 자재 %d, 승급·건설에 쓴 자재 %d, 남은 자재 %d (시작 36)." % [int(got), int(used), int(float(state.stock.get("wood", 0)) + float(state.stock.get("metal", 0)) + float(state.stock.get("concrete", 0)))])
	L.append("")
	L.append("## 막힌 것(봇이 하려다 못 한 일, 횟수)")
	var bl: Dictionary = r["bot"].blocked
	var keys: Array = bl.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(bl[a]) > int(bl[b]))
	for k: String in keys.slice(0, 25):
		L.append("- %s — %d" % [k, int(bl[k])])
	L.append("")
	L.append("## 기록(마지막 40줄)")
	for e: Dictionary in state.logbook.slice(maxi(0, state.logbook.size() - 40)):
		L.append("- %d일 %02d시 %s" % [int(e["day"]), int(e["hour"]), e["text"]])
	return "\n".join(L) + "\n"


## 브리프 §20.2: 꽉 찬 한 칸(주거 1채)의 세수와 비용(계층별). 상품 비용 = 기준가 × 소비량(가장 싼 대체품), 물·전기 = 자체 설비의 공급 1당 유지비.
static func per_cell(sim: Sim, state: CityState) -> Array:
	var L: Array = []
	L.append("## 계층별 한 칸(만실 주거) 수지 — 브리프 §20.2")
	var wcost := 6.0 / 120.0
	var pcost := 25.0 / 40.0
	if sim.bdef("power_plant").size() > 0:
		pcost = float(sim.bdef("power_plant")["upkeep"]) / float(sim.bdef("power_plant")["supply"]["power"])
	L.append("가정: 물 ₩%.3f/단위(급수탑 유지비), 전기 ₩%.3f/부하(발전소 유지비), 상품 = goods.json 기준가 × 1인 소비량(대체 묶음은 가장 싼 것). 시장·서비스 유지비는 빠짐." % [wcost, pcost])
	L.append("세수(승급 충족) = 정원 × 세율 × (1 + 0.10 × 승급 수요 수), 행복 배수 1.0 기준. 여유 수요 보너스는 따로 표시.")
	L.append("")
	L.append("| 계층 | 정원 | 기본 세수/칸 | 승급 충족 세수/칸 | +여유 전부 | 상품 비용/칸 | 물·전기 비용/칸 | **순/칸(승급 충족)** | 노동력/칸 |")
	L.append("|---|---|---|---|---|---|---|---|---|")
	for t: int in range(1, sim.max_tier() + 1):
		var td := sim.tier(t)
		var cap := float(td["cap"])
		var adv := 0
		var lux := 0
		var goods := 0.0
		for nid: String in sim.items("needs"):
			var n := sim.item("needs", nid)
			if int(n["tier"]) != t:
				continue
			if n["role"] == "advance":
				adv += 1
			elif n["role"] == "luxury":
				lux += 1
			if n["role"] == "luxury" or not n.has("amount"):
				continue
			var cheapest := 1e9
			for o: Dictionary in n["options"]:
				if o.has("good"):
					cheapest = minf(cheapest, float(sim.good(o["good"]).get("price", 0)))
				elif o.has("utility"):
					cheapest = 0.0
			goods += cap * float(n["amount"]) * cheapest
		var base := cap * float(td["tax"])
		var adv_tax := base * (1.0 + 0.10 * float(adv if t < sim.max_tier() else 0))
		var all_tax := adv_tax + base * 0.15 * float(lux)
		var util := cap * (float(td["water"]) * wcost + float(td["power"]) * pcost)
		L.append("| %s | %d | %.1f | %.1f | %.1f | %.1f | %.1f | **%.1f** | %.1f |" % [sim.tname(t), int(cap), base, adv_tax, all_tax, goods, util, adv_tax - goods - util, cap * float(td["labor"])])
	L.append("")
	L.append("승급 회수(만실·승급 충족 기준 순/칸 증가로 승급 돈 비용을 갚는 데 걸리는 경제일; 실제 시간 = ×10분):")
	for t: int in range(1, sim.max_tier()):
		var c := sim.item("upgrade_costs", "%dto%d" % [t, t + 1])
		var net := func(k: int) -> float:
			var td2 := sim.tier(k)
			var cap2 := float(td2["cap"])
			var a := 0
			var g := 0.0
			for nid: String in sim.items("needs"):
				var n := sim.item("needs", nid)
				if int(n["tier"]) != k:
					continue
				if n["role"] == "advance":
					a += 1
				if n["role"] != "luxury" and n.has("amount"):
					var ch := 1e9
					for o: Dictionary in n["options"]:
						ch = minf(ch, float(sim.good(o["good"]).get("price", 0)) if o.has("good") else 0.0)
					g += cap2 * float(n["amount"]) * ch
			return cap2 * float(td2["tax"]) * (1.0 + 0.10 * float(a if k < sim.max_tier() else 0)) - g - cap2 * (float(td2["water"]) * wcost + float(td2["power"]) * pcost)
		var gain: float = net.call(t + 1) - net.call(t)
		var mat_val := float(c["qty"]) * 12.0
		L.append("- %s→%s: 돈 ₩%d + 자재 %d(기준가 ₩%d) / 순 증가 ₩%.1f/일 → %s" % [sim.tname(t), sim.tname(t + 1), int(c["money"]), int(c["qty"]), int(mat_val), gain,
			("%.1f경제일(실제 %.0f분)" % [(float(c["money"]) + mat_val) / gain, (float(c["money"]) + mat_val) / gain * 10.0]) if gain > 0.0 else "회수 불가(순 감소)"])
	L.append("")
	L.append("측정값(마지막 날): 계층별 실제 평균 세수/주거")
	var sum := {}
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house":
			var a: Array = sum.get(int(b["tier"]), [0.0, 0])
			a[0] += float(b["tax"])
			a[1] += 1
			sum[int(b["tier"])] = a
	for t: int in range(1, 6):
		if sum.has(t):
			L.append("- %s: 주거 %d채, 평균 세수 ₩%.1f/일" % [sim.tname(t), int(sum[t][1]), float(sum[t][0]) / float(sum[t][1])])
	return L
