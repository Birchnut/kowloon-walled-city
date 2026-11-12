extends SceneTree
## sim_run — v4(PC) 시나리오: 봇 하나가 게임 시계로 N경제일을 계속 플레이한다(헤드리스, 결정론).
##   godot --headless --path godot -s res://tools/sim_run.gd -- bot=balanced days=40 seed=1 [out=<md 경로>] [quiet]
## 봇은 경제 act_every_h시간마다 손을 댄다(bots.json). 사람은 ×1~×2로 시간당 약 6경제일을 플레이한다(봇보다 약 2배 느리다).
## 출력: ../simulation/reports/<bot>.md + .json(요약 행 + 일별 행). 요약은 python3 simulation/make_summary.py.


func _init() -> void:
	var args := {"bot": "balanced", "days": "40", "seed": "1", "out": ""}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(args["out"])
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../simulation/reports/%s.md" % args["bot"]).simplify_path()
	var r := run(str(args["bot"]), float(args["days"]), int(args["seed"]), not args.has("quiet"))
	if r["ok"]:
		SimIO.write_text(out, report(r))
		SimIO.write_text(out.get_basename() + ".json", JSON.stringify({"summary": summary(r), "rows": r["rows"]}, " "))
		print("report: ", out)
	(r["sim"] as Sim).systems.clear()
	quit(0 if r["ok"] else 1)


static func run(bot_id: String, days: float, seed_value: int, verbose: bool = true, db_override: Dictionary = {}) -> Dictionary:
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
	var every := maxf(1.0, float(bot.c("act_every_h", 1))) / 24.0
	var day := state.day
	var errors := 0
	var next_act := state.econ_days
	var end := state.econ_days + days
	var step_ms := 0.0
	var steps := 0
	while state.econ_days < end - 1e-9:
		if state.econ_days + 1e-9 >= next_act:
			bot.act(state)
			next_act += every
		var ts := Time.get_ticks_usec()
		sim.step(state)
		step_ms += float(Time.get_ticks_usec() - ts) / 1000.0
		steps += 1
		state.events.clear()
		min_money = minf(min_money, state.money)
		if state.day != day:
			var row := daily(sim, state, day)
			rows.append(row)
			if verbose:
				var p: Array = row["pop"]
				print("%s d%02d pop %s money %d net %.0f hap %.0f fl %d houses %d burnt %d sick %d" % [bot_id, day, str(p), int(state.money), float(row["net"]),
					state.happiness, state.floors_unlocked, int(row["houses"]), int(row["burnt"]), int(row["sick"])])
			day = state.day
	if verbose:
		print("ran %.0f days in %.1fs (step avg %.2fms)" % [days, float(Time.get_ticks_msec() - t0) / 1000.0, step_ms / maxf(1.0, float(steps))])
	return {"ok": true, "sim": sim, "state": state, "bot": bot, "rows": rows, "min_money": min_money, "days": days, "seed": seed_value,
		"step_ms": step_ms / maxf(1.0, float(steps)), "errors": errors}


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
	var ok := 0
	var houses := 0
	var burnt := 0
	var sick := 0
	for b: Dictionary in sim.cover(state)["all"]:
		if str(b.get("burn", "")) != "":
			burnt += 1
		if b["kind"] == "house":
			houses += 1
			if b["need_state"] == "ok":
				ok += 1
			if b.get("sick", false):
				sick += 1
	return {"day": d, "pop": pop, "money": int(state.money), "net": float(led.get("net", 0.0)), "tax": float(led.get("tax", 0.0)),
		"upkeep": float(led.get("upkeep", 0.0)), "build": float(led.get("build", 0.0)), "ledger": led,
		"labor_spare": lab, "houses": houses, "houses_ok": ok, "happiness": snappedf(state.happiness, 0.1), "burnt": burnt, "sick": sick,
		"floors": state.floors_unlocked, "facilities": int((sim.cover(state)["facs"] as Array).size()),
		"water": [snappedf(float(state.util.get("water", {}).get("supply", 0)), 1), snappedf(float(state.util.get("water", {}).get("demand", 0)), 1)],
		"power": [snappedf(float(state.util.get("power", {}).get("supply", 0)), 1), snappedf(float(state.util.get("power", {}).get("demand", 0)), 1)],
		"goals": int((state.flags.get("goals", {}) as Dictionary).size()),
		"mats": [int(state.stock.get("wood", 0)), int(state.stock.get("metal", 0)), int(state.stock.get("concrete", 0)), int(state.stock.get("parts", 0))]}


const MILESTONES := [["first_upgrade_t2_day", "첫 승급(월세 전사)"], ["floor_2_day", "2층"], ["first_fire_day", "첫 불"], ["first_upgrade_t3_day", "첫 박힌 돌"],
	["floor_3_day", "3층"], ["first_outbreak_day", "첫 병"], ["first_upgrade_t4_day", "첫 깡통 귀족"], ["goal_g_tower_day", "네온 용탑"],
	["first_upgrade_t5_day", "첫 옥상 황제"], ["goal_g_hall_day", "무허가 구청"], ["goal_g_final_day", "마지막 목표"]]


## 요약 행(make_summary.py가 읽는다).
static func summary(r: Dictionary) -> Dictionary:
	var state: CityState = r["state"]
	var bot: Bot = r["bot"]
	var tl := {}
	for m: Array in MILESTONES:
		tl[m[0]] = snappedf(float(state.stats.get(m[0], -1.0)), 0.01)
	# 빈 구간: 진전 명령(짓기·승급·칠하기·수령·수리·연구·계약) 사이 가장 긴 간격(경제일)
	var gaps: Array = []
	var last := float(sim_start(state))
	var longest := 0.0
	var longest_at := 0.0
	for a: Array in bot.acts:
		var g := float(a[0]) - last
		if g > longest:
			longest = g
			longest_at = last
		last = float(a[0])
	var hd := maxf(1e-6, float(state.stats.get("house_days", 0.0)))
	var rows: Array = r["rows"]
	var money_curve: Array = []
	for row: Dictionary in rows:
		money_curve.append(int(row["money"]))
	var spent := float(state.stats.get("spent_build", 0.0)) + float(state.stats.get("spent_repair", 0.0)) + float(state.stats.get("spent_upgrade", 0.0))
	return {"bot": bot.id, "name": bot.c("name", bot.id), "seed": int(r["seed"]), "days": float(r["days"]), "timeline": tl,
		"pop_end": rows.back()["pop"] if not rows.is_empty() else [], "money_end": int(state.money), "min_money": int(r["min_money"]),
		"floors": state.floors_unlocked, "goals_done": int((state.flags.get("goals", {}) as Dictionary).size()),
		"house_days": snappedf(hd, 0.1), "fire_house_days": snappedf(float(state.stats.get("hz_fire_house_days", 0.0)), 0.1),
		"sick_house_days": snappedf(float(state.stats.get("hz_sick_house_days", 0.0)), 0.1),
		"hazard_loss_pct": snappedf(100.0 * (float(state.stats.get("hz_fire_house_days", 0.0)) + float(state.stats.get("hz_sick_house_days", 0.0))) / hd, 0.01),
		"fires": int(state.stats.get("fires", 0)), "burnt": int(state.stats.get("burnt", 0)), "outbreaks": int(state.stats.get("outbreaks", 0)),
		"left_sick": int(state.stats.get("left_sick", 0)), "scattered": int(state.stats.get("scattered", 0)),
		"longest_gap": snappedf(longest, 0.01), "longest_gap_at": snappedf(longest_at, 0.01), "money_curve": money_curve,
		"tax_total": int(state.stats.get("tax_total", 0.0)), "spent_build": int(state.stats.get("spent_build", 0.0)),
		"spent_upgrade": int(state.stats.get("spent_upgrade", 0.0)), "spent_repair": int(state.stats.get("spent_repair", 0.0)),
		"spent_research": int(state.stats.get("spent_research", 0.0)), "spent_total": int(spent), "step_ms": snappedf(float(r["step_ms"]), 0.01),
		"cmds": bot.cmds}


static func sim_start(state: CityState) -> float:
	return float(state.stats.get("start_day", 0.25))


static func _d(x: Variant) -> String:
	return "—" if float(x) < 0.0 else "%.2f일" % float(x)


static func report(r: Dictionary) -> String:
	var sim: Sim = r["sim"]
	var state: CityState = r["state"]
	var rows: Array = r["rows"]
	var s := summary(r)
	var L: Array = []
	L.append("# v0.4 시나리오 — %s (%.0f경제일, seed %d)" % [s["name"], float(r["days"]), int(r["seed"])])
	L.append("")
	L.append("자동 생성: `godot/tools/sim_run.gd`. 1경제일 = ×1에서 실제 10분. 봇은 경제 %s시간마다 손을 댄다(계속 플레이). 사람은 약 2배 느리다고 본다." % str(sim.item("bots", r["bot"].id).get("act_every_h", 1)))
	L.append("")
	L.append("## 이정표")
	L.append("| 사건 | 경제일 | 사람(약 2배, ×1~×2로 시간당 6일) |")
	L.append("|---|---|---|")
	for m: Array in MILESTONES:
		var v := float(s["timeline"][m[0]])
		L.append("| %s | %s | %s |" % [m[1], _d(v), "—" if v < 0.0 else "약 %.1f시간" % (v * 2.0 / 6.0)])
	L.append("")
	L.append("- 목표 %d/%d · 층 %d · 마지막 금고 %s · 최저 금고 %s" % [int(s["goals_done"]), sim.items("goals").size(), int(s["floors"]), Sim.won(float(s["money_end"])), Sim.won(float(s["min_money"]))])
	L.append("- 불·병 손실: 주거-일 %.1f 중 불 %.1f · 병 %.1f = **%.2f%%** (불 %d번, 탐 %d, 병 %d번, 병으로 떠남 %d, 불로 흩어짐 %d)" % [float(s["house_days"]),
		float(s["fire_house_days"]), float(s["sick_house_days"]), float(s["hazard_loss_pct"]), int(s["fires"]), int(s["burnt"]), int(s["outbreaks"]), int(s["left_sick"]), int(s["scattered"])])
	L.append("- 가장 긴 빈 구간(진전 명령 사이): %.2f경제일(%.2f일째부터)" % [float(s["longest_gap"]), float(s["longest_gap_at"])])
	L.append("- 돈: 세수 합 %s · 건설 %s · 승급 %s · 수리 %s · 연구 %s · 스텝 평균 %.2fms" % [Sim.won(float(s["tax_total"])), Sim.won(float(s["spent_build"])),
		Sim.won(float(s["spent_upgrade"])), Sim.won(float(s["spent_repair"])), Sim.won(float(s["spent_research"])), float(s["step_ms"])])
	L.append("")
	L.append("## 일별")
	L.append("| 일 | 굴러온 돌 | 월세 전사 | 박힌 돌 | 깡통 귀족 | 옥상 황제 | 일손 여유 T1..T5 | 주거(충족/전체) | 탐/병 | 행복 | 금고 | 순/일 | 물 | 전기 | 층 | 목표 | 목·철·콘·부품 |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for row: Dictionary in rows:
		var p: Array = row["pop"]
		L.append("| %d | %d | %d | %d | %d | %d | %s | %d/%d | %d/%d | %.0f | %d | %.0f | %d/%d | %d/%d | %d | %d | %s |" % [row["day"], p[0], p[1], p[2], p[3], p[4],
			"/".join(PackedStringArray(row["labor_spare"].map(func(x: int) -> String: return str(x)))), row["houses_ok"], row["houses"], row["burnt"], row["sick"],
			row["happiness"], row["money"], row["net"], row["water"][0], row["water"][1], row["power"][0], row["power"][1], row["floors"], row["goals"],
			"/".join(PackedStringArray(row["mats"].map(func(x: int) -> String: return str(x))))])
	L.append("")
	L.append("## 마지막 날 수요 충족(계층별 평균, 주민 가중)")
	var acc := {}
	for b: Dictionary in sim.cover(state)["houses"]:
		if int(b["residents"]) == 0:
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
	L.append("## 마지막 날 재고")
	var eco: Dictionary = sim.query(state, "economy")
	L.append("| 상품 | 재고 | 한도 | 생산/일 | 소비/일 | 수입/일 | 수출/일 |")
	L.append("|---|---|---|---|---|---|---|")
	for g: Dictionary in eco["goods"]:
		if float(g["stock"]) > 0.0 or float(g["cons"]) > 0.0 or float(g["prod"]) > 0.0:
			L.append("| %s | %.0f | %.0f | %.1f | %.1f | %.1f | %.1f |" % [g["name"], g["stock"], g["cap"], g["prod"], g["cons"], g["imp"], g["exp"]])
	L.append("")
	L.append("## 장부(최근 평균, ₩/경제일)")
	for l: Dictionary in eco["finance"]["lines"]:
		L.append("- %s %.1f" % [l["name"], l["amount"]])
	L.append("")
	L.append("## 마지막 날 시설")
	var fc := {}
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "facility" or b["kind"] == "site":
			var k := str(b["type"])
			var a: Array = fc.get(k, [0, 0, {}])
			a[0] += 1
			if b.get("active", false):
				a[1] += 1
			var cz := str(b.get("cause", "site" if b["kind"] == "site" else ""))
			a[2][cz] = int(a[2].get(cz, 0)) + 1
			fc[k] = a
	L.append("| 시설 | 수 | 가동 | 상태 |")
	L.append("|---|---|---|---|")
	for k: String in fc:
		L.append("| %s | %d | %d | %s |" % [sim.bdef(k).get("name", k), fc[k][0], fc[k][1], JSON.stringify(fc[k][2])])
	L.append("")
	L.append("## 막힌 것(봇이 하려다 못 한 일, 횟수)")
	var bl: Dictionary = r["bot"].blocked
	var keys: Array = bl.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(bl[a]) > int(bl[b]))
	for k: String in keys.slice(0, 20):
		L.append("- %s — %d" % [k, int(bl[k])])
	L.append("")
	L.append("## 기록(마지막 30줄)")
	for e: Dictionary in state.logbook.slice(maxi(0, state.logbook.size() - 30)):
		L.append("- %d일 %02d시 %s" % [int(e["day"]), int(e["hour"]), e["text"]])
	return "\n".join(L) + "\n"
