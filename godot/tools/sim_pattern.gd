extends RefCounted
## sim_pattern — 접속 패턴 시뮬(브리프 §20.1). 두 시계를 함께 돌린다:
##  접속 중: 실제 600초 = 1경제일(×1), 봇은 act_s(기본 60초)마다 손을 댄다. 탐험은 실제 시계(sim.now_unix).
##  접속 사이: 실제 시간이 건너뛰고 경제는 미접속 규칙(Sim.catch_up — 0.25배, 최대 8시간, 유예 정지)으로 따라잡는다.
## 디버그 자재 없음. 결과 r = {sim, state, bot, rows(실제 하루마다), sessions, firsts, cash, ...} → report_md()/summary_row().

const T0 := 1_700_000_000
const SPD := 600.0


static func schedule(pat: Dictionary, pats: Dictionary, real_days: int) -> Array:
	var p := pat
	var away: Array = pat.get("away", [])
	if pat.has("base"):
		p = pats.get(str(pat["base"]), {})
	var out: Array = []
	for d: int in real_days:
		if not away.is_empty() and d >= int(away[0]) and d < int(away[1]):
			continue
		if p.has("every_min"):
			var t := float(p.get("from_h", 8)) * 3600.0
			while t < float(p.get("to_h", 22)) * 3600.0 - 1.0:
				out.append([d * 86400 + int(t), int(float(p.get("len_min", 5)) * 60.0)])
				t += float(p["every_min"]) * 60.0
		else:
			for s: Array in p.get("sessions", []):
				out.append([d * 86400 + int(float(s[0]) * 3600.0), int(float(s[1]) * 60.0)])
	return out


static func run(bot_id: String, real_days: int, seed_value: int, verbose: bool = false, db_override: Dictionary = {}) -> Dictionary:
	var db := db_override if not db_override.is_empty() else SimIO.load_db()
	var sim := Sim.new()
	sim.setup(db)
	if not sim.errors.is_empty():
		for e: String in sim.errors:
			print("DATA ERROR ", e)
		return {"ok": false, "sim": sim}
	var bot := Bot.new(sim, bot_id)
	var pats: Dictionary = db.get("bots", {}).get("patterns", {})
	var pname := str(bot.conf.get("pattern", "regular"))
	var pat: Dictionary = pats.get(pname, {})
	var act_s := float(pat.get("act_s", pats.get(str(pat.get("base", "")), {}).get("act_s", 60)))
	var ses := schedule(pat, pats, real_days)
	var state := CityState.new()
	var now: int = T0 + int(ses[0][0])
	sim.now_unix = now
	sim.new_game(state, seed_value)
	state.last_saved_unix = now
	var start := now
	var r := {"ok": true, "sim": sim, "state": state, "bot": bot, "bot_id": bot_id, "pattern": pname, "pattern_name": str(pat.get("name", pname)),
		"real_days": real_days, "seed": seed_value, "rows": [], "sessions": [], "seg": [[state.econ_days, 0.0]], "cash": {}, "ledger_seen": 0,
		"firsts": {}, "min_money": state.money, "team_s": 0.0, "mat_wait": 0.0, "offline": [], "online_s": 0.0, "money_hist": []}
	var t_wall := Time.get_ticks_msec()
	var day_idx := 0
	for i: int in ses.size():
		var s_start: int = T0 + int(ses[i][0])
		var s_end: int = s_start + int(ses[i][1])
		var next_start: int = T0 + int(ses[i + 1][0]) if i + 1 < ses.size() else s_end
		# 접속 사이: 미접속 정산
		if s_start > now:
			_teams_integrate(r, state, now, s_start)
			now = s_start
			sim.now_unix = now
			var cu: Variant = sim.catch_up(state, now)
			state.events.clear()
			_after(r, sim, state, now - start)
			if cu != null and float(cu.get("real_hours", 0.0)) >= 4.0:
				r["offline"].append({"at_h": float(now - start) / 3600.0, "lines": cu["lines"]})
		var c0 := bot.cmds.duplicate()
		var acts := 0
		while now < s_end:
			var left := float(s_end - now)
			bot.act(state, {"now": now, "session_left": left, "next_gap": float(next_start - s_end), "leaving": left <= act_s + 0.5})
			acts += 1
			_mat_wait(r, sim, state, minf(act_s, left))
			var stp := int(minf(act_s, left))
			_teams_integrate(r, state, now, now + stp)
			now += stp
			sim.now_unix = now
			sim.tick(state, float(stp) / SPD)
			state.events.clear()
			r["online_s"] = float(r["online_s"]) + float(stp)
			_after(r, sim, state, now - start)
		state.last_saved_unix = now
		var dc := {}
		for k: String in bot.cmds:
			var n := int(bot.cmds[k]) - int(c0.get(k, 0))
			if n > 0:
				dc[k] = n
		r["sessions"].append({"start_h": float(s_start - start) / 3600.0, "len_s": int(ses[i][1]), "acts": acts, "cmds": dc})
		# 실제 하루가 끝나면(다음 접속이 다음 날이면) 한 줄
		var d_now := int(ses[i][0]) / 86400
		var d_next := int(ses[i + 1][0]) / 86400 if i + 1 < ses.size() else d_now + 1
		if d_next != d_now or i + 1 == ses.size():
			while day_idx <= d_now:
				r["rows"].append(row(sim, state, day_idx + 1, now - start, r))
				day_idx += 1
			if verbose:
				var rw: Dictionary = r["rows"].back()
				print("%s real day %d econ %.1f pop %s money %d net %.0f floors %d goals %d (%.1fs)" % [bot_id, rw["day"], rw["econ"], str(rw["pop"]), rw["money"], rw["net"], rw["floors"], rw["goals"], float(Time.get_ticks_msec() - t_wall) / 1000.0])
	# 남은 날(장기 부재 끝에 접속이 없는 날)
	while day_idx < real_days:
		var t_end: int = T0 + (day_idx + 1) * 86400
		if t_end > now:
			_teams_integrate(r, state, now, t_end)
			now = t_end
			sim.now_unix = now
			sim.catch_up(state, now)
			state.events.clear()
			_after(r, sim, state, now - start)
		r["rows"].append(row(sim, state, day_idx + 1, now - start, r))
		day_idx += 1
	r["end_s"] = now - start
	r["wall_s"] = float(Time.get_ticks_msec() - t_wall) / 1000.0
	return r


## 탐험 팀 가동 적분(팀 수 × 시간, 그중 나가 있던 시간).
static func _teams_integrate(r: Dictionary, state: CityState, a: int, b: int) -> void:
	var live := 0
	var busy := 0.0
	var waiting := 0.0
	for t: Dictionary in state.teams:
		if t.get("retired", false):
			continue
		live += 1
		if t["state"] == "out":
			var e := mini(b, int(t["completes_unix"]))
			busy += float(maxi(0, e - a))
			waiting += float(maxi(0, b - maxi(a, int(t["completes_unix"]))))
		elif t["state"] == "done":
			waiting += float(b - a)
	r["team_avail"] = float(r.get("team_avail", 0.0)) + float(live) * float(b - a)
	r["team_busy"] = float(r.get("team_busy", 0.0)) + busy
	r["team_wait"] = float(r.get("team_wait", 0.0)) + waiting


static func _mat_wait(r: Dictionary, sim: Sim, state: CityState, dt_s: float) -> void:
	var mats: Array = sim.db["upgrade_costs"]["materials"]
	var fam := str(r["bot"].conf.get("family", ""))
	var n := 0
	for b: Dictionary in sim.cover(state)["houses"]:
		if not b.get("ready", false):
			continue
		var cst := sim.item("upgrade_costs", "%dto%d" % [int(b["tier"]), int(b["tier"]) + 1])
		var ok := false
		for m: String in mats:
			if (fam == "" or m == fam) and float(state.stock.get(m, 0.0)) >= float(cst.get("qty", 0)):
				ok = true
		if not ok:
			n += 1
	r["mat_wait"] = float(r["mat_wait"]) + float(n) * dt_s


## 매 손길·정산 뒤: 실제 시각 기록(경제일 ↔ 실제 시간), 장부 누적, 처음 일어난 일.
static func _after(r: Dictionary, sim: Sim, state: CityState, real_s: int) -> void:
	r["seg"].append([state.econ_days, float(real_s)])
	if real_s <= 3600:
		var mb := 0
		for k: String in r["bot"].blocked:
			if k.find("돈") >= 0:
				mb += int(r["bot"].blocked[k])
		r["money_hist"].append([real_s, int(state.money), mb, int(Metrics.compute(sim, state).get("pop", 0))])
	r["min_money"] = minf(float(r["min_money"]), state.money)
	for row: Dictionary in state.ledger.get("days", []):
		if int(row["day"]) > int(r["ledger_seen"]):
			for k: String in row:
				if k != "day":
					r["cash"][k] = float(r["cash"].get(k, 0.0)) + float(row[k])
			r["ledger_seen"] = int(row["day"])
	var f: Dictionary = r["firsts"]
	var keys := {"first_resident_day": "첫 주민", "first_send_unix": "첫 탐험 파견", "first_claim_unix": "첫 수령",
		"first_upgrade_t2_day": "첫 세입자", "first_upgrade_t3_day": "첫 토박이", "first_upgrade_t4_day": "첫 유지", "first_upgrade_t5_day": "첫 거물",
		"first_power_day": "첫 전기", "floor_2_day": "2층", "floor_3_day": "3층", "floor_4_day": "4층", "floor_5_day": "5층", "floor_6_day": "6층",
		"goal_g_hall_day": "성채 회관", "goal_g_final_day": "구룡성채(최종 목표)"}
	for k: String in keys:
		if f.has(k) or not state.stats.has(k):
			continue
		var v := float(state.stats[k])
		var rs := real_of(r, v) if k.ends_with("_day") else v - float(state.stats.get("start_unix", 0.0))
		f[k] = {"name": keys[k], "real_s": rs, "econ": v if k.ends_with("_day") else -1.0}


## 경제일 → 실제 초(기록한 구간을 선형으로).
static func real_of(r: Dictionary, econ: float) -> float:
	var seg: Array = r["seg"]
	for i: int in range(1, seg.size()):
		var a: Array = seg[i - 1]
		var b: Array = seg[i]
		if econ <= float(b[0]) + 1e-9:
			if float(b[0]) - float(a[0]) < 1e-9:
				return float(b[1])
			return float(a[1]) + (econ - float(a[0])) / (float(b[0]) - float(a[0])) * (float(b[1]) - float(a[1]))
	return float(seg.back()[1])


static func row(sim: Sim, state: CityState, d: int, real_s: int, r: Dictionary) -> Dictionary:
	var m := Metrics.compute(sim, state)
	var pop: Array = []
	var score := 0.0
	for t: int in range(1, 6):
		pop.append(int(m.get("pop.t%d" % t, 0)))
		score += float(m.get("pop.t%d" % t, 0)) * float(sim.tier(t).get("tax", 1.0))
	var lab: Array = []
	for t: int in range(1, 6):
		var l: Dictionary = state.labor.get(t, {"have": 0, "need": 0.0})
		lab.append(int(l["have"]) - int(ceilf(float(l["need"]))))
	var led: Dictionary = state.ledger["days"].back() if not (state.ledger["days"] as Array).is_empty() else {}
	var taxrate := 0.0
	var houses := 0
	for b: Dictionary in sim.cover(state)["houses"]:
		taxrate += float(b.get("tax", 0.0))
		houses += 1
	var mats := {}
	for g: String in ["wood", "metal", "concrete", "parts"]:
		mats[g] = int(state.stock.get(g, 0.0))
	return {"day": d, "real_h": float(real_s) / 3600.0, "econ": snappedf(state.econ_days, 0.01), "pop": pop, "money": int(state.money),
		"net": float(led.get("net", 0.0)), "tax_rate": snappedf(taxrate, 0.1), "score": snappedf(score, 0.1), "labor_spare": lab, "houses": houses,
		"happiness": snappedf(state.happiness, 0.1), "floors": state.floors_unlocked, "mats": mats,
		"goals": (state.flags.get("goals", {}) as Dictionary).size(), "research": state.research.get("done", {}).size(), "heat": snappedf(state.heat, 0.1),
		"teams": state.teams.size()}


# ------------------------------------------------------------------ 리포트
static func _hm(s: float) -> String:
	if s < 0.0:
		return "—"
	var h := int(s / 3600.0)
	var mm := int(fmod(s, 3600.0) / 60.0)
	if h >= 24:
		return "%d일 %d시간" % [h / 24, h % 24]
	return "%d시간 %02d분" % [h, mm] if h > 0 else "%d분" % mm


static func materials(sim: Sim, state: CityState) -> Dictionary:
	var out := {}
	for g: String in ["wood", "metal", "concrete", "parts", "scrap"]:
		out[g] = {"exp": float(state.stats.get("exp." + g, 0.0)), "imp": float(state.stats.get("imp." + g, 0.0)),
			"goal": float(state.stats.get("goal." + g, 0.0)), "used": float(state.stats.get("used." + g, 0.0)), "stock": float(state.stock.get(g, 0.0))}
	return out


static func summary_row(r: Dictionary) -> Dictionary:
	var sim: Sim = r["sim"]
	var state: CityState = r["state"]
	var rows: Array = r["rows"]
	var last: Dictionary = rows.back()
	var f: Dictionary = r["firsts"]
	var fs := {}
	for k: String in f:
		fs[k] = float(f[k]["real_s"])
	var nses: int = (r["sessions"] as Array).size()
	var dec := 0
	var allc := 0
	for s: Dictionary in r["sessions"]:
		for k: String in s["cmds"]:
			allc += int(s["cmds"][k])
			if k != "expedition_claim":
				dec += int(s["cmds"][k])
	var mats := materials(sim, state)
	var fam := {}
	for g: String in ["wood", "metal", "concrete"]:
		fam[g] = int(mats[g]["exp"] + mats[g]["imp"] + mats[g]["goal"])
	var ext := external_share(sim, state)
	return {"bot": r["bot_id"], "name": r["bot"].conf.get("name", r["bot_id"]), "pattern": r["pattern"], "real_days": r["real_days"],
		"econ_days": snappedf(state.econ_days, 0.1), "online_h": snappedf(float(r["online_s"]) / 3600.0, 0.01), "sessions": nses,
		"pop": last["pop"], "score": last["score"], "tax_rate": last["tax_rate"], "money": last["money"], "min_money": int(r["min_money"]),
		"floors": last["floors"], "goals": last["goals"], "research": last["research"], "firsts": fs,
		"dec_per_session": snappedf(float(dec) / float(maxi(1, nses)), 0.1), "cmds_per_session": snappedf(float(allc) / float(maxi(1, nses)), 0.1),
		"team_util": snappedf(float(r.get("team_busy", 0.0)) / maxf(1.0, float(r.get("team_avail", 0.0))), 0.01),
		"team_wait": snappedf(float(r.get("team_wait", 0.0)) / maxf(1.0, float(r.get("team_avail", 0.0))), 0.01),
		"mat_wait_h": snappedf(float(r["mat_wait"]) / 3600.0, 0.1), "family_got": fam, "mats": mats, "cash": r["cash"], "external": ext,
		"rows": rows, "blocked": _top_blocked(r["bot"].blocked, 6), "wall_s": r["wall_s"], "heat": state.heat, "raids": int(state.stats.get("raids", 0.0))}


static func _top_blocked(bl: Dictionary, n: int) -> Array:
	var keys: Array = bl.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(bl[a]) > int(bl[b]))
	var out: Array = []
	for k: String in keys.slice(0, n):
		out.append([k, int(bl[k])])
	return out


## 외부 공급 의존: 소비재 소비 중 수입 몫, 물·전기 중 외부 연결 몫.
static func external_share(sim: Sim, state: CityState) -> Dictionary:
	var imp := 0.0
	var prod := 0.0
	for g: String in sim.items("goods"):
		var cat := str(sim.good(g).get("cat", ""))
		if cat == "material":
			continue
		imp += float(state.stats.get("imp." + g, 0.0))
		prod += float(state.stats.get("prod." + g, 0.0))
	var ext := {"water": 0.0, "power": 0.0}
	var tot := {"water": 0.0, "power": 0.0}
	for b: Dictionary in sim.cover(state)["facs"]:
		var d := sim.bdef(str(b["type"]))
		for u: String in d.get("supply", {}):
			var v := float(d["supply"][u]) * float(b.get("staff", 1.0) if not d.get("workforce", {}).is_empty() else 1.0)
			tot[u] += v
			if str(b["type"]).ends_with("_ext"):
				ext[u] += v
	return {"goods_import_share": snappedf(imp / maxf(1.0, imp + prod), 0.01), "water_ext_share": snappedf(ext["water"] / maxf(1.0, tot["water"]), 0.01),
		"power_ext_share": snappedf(ext["power"] / maxf(1.0, tot["power"]), 0.01)}


static func report_md(r: Dictionary, per_cell: Array) -> String:
	var sim: Sim = r["sim"]
	var state: CityState = r["state"]
	var sr := summary_row(r)
	var L: Array = []
	L.append("# 시나리오 — %s (%s, 실제 %d일, seed %d)" % [sr["name"], r["pattern_name"], int(r["real_days"]), int(r["seed"])])
	L.append("")
	L.append("자동 생성: `godot/tools/sim_run.gd`(`tools/sim_pattern.gd`). 접속 중 실제 600초 = 1경제일, 봇은 %d초마다 손을 댄다. 접속 사이는 미접속 규칙(0.25배·최대 8시간·유예 정지). 탐험은 실제 시계. **디버그 자재 없음** — 세 계열 자재는 탐험과 건재상 계약으로만." % int(60))
	L.append("")
	L.append("- 접속 %d번, 접속 시간 합 %.1f시간, 경제 시간 %.1f일, 시뮬 %.0f초" % [sr["sessions"], sr["online_h"], sr["econ_days"], float(r["wall_s"])])
	L.append("- 끝: 인구 %s(떠돌이/세입자/토박이/유지/거물), 세수 ₩%.0f/일, 금고 ₩%d(최저 ₩%d), 층 %d, 목표 %d개, 연구 %d개, 단속 위험 %.0f(단속 %d번)" % [str(sr["pop"]), float(sr["tax_rate"]), int(sr["money"]), int(sr["min_money"]), int(sr["floors"]), int(sr["goals"]), int(sr["research"]), float(sr["heat"]), int(sr["raids"])])
	L.append("")
	L.append("## 처음 일어난 때(실제 시간, 게임 시작부터)")
	L.append("| 사건 | 실제 시간 | 경제일 |")
	L.append("|---|---|---|")
	var order := ["first_resident_day", "first_send_unix", "first_claim_unix", "first_upgrade_t2_day", "first_power_day", "first_upgrade_t3_day", "floor_2_day",
		"first_upgrade_t4_day", "floor_3_day", "first_upgrade_t5_day", "floor_4_day", "floor_5_day", "floor_6_day", "goal_g_hall_day", "goal_g_final_day"]
	var names := {"first_resident_day": "첫 주민", "first_send_unix": "첫 탐험 파견", "first_claim_unix": "첫 수령", "first_upgrade_t2_day": "첫 세입자 승급",
		"first_upgrade_t3_day": "첫 토박이 승급", "first_upgrade_t4_day": "첫 유지 승급", "first_upgrade_t5_day": "첫 거물 승급", "first_power_day": "첫 전기",
		"floor_2_day": "2층 열림", "floor_3_day": "3층 열림", "floor_4_day": "4층 열림", "floor_5_day": "5층 열림", "floor_6_day": "6층 열림",
		"goal_g_hall_day": "성채 회관", "goal_g_final_day": "구룡성채(최종 목표)"}
	for k: String in order:
		var f: Dictionary = r["firsts"].get(k, {})
		L.append("| %s | %s | %s |" % [names[k], _hm(float(f.get("real_s", -1.0))), ("%.2f" % float(f["econ"])) if float(f.get("econ", -1.0)) >= 0.0 else "—"])
	L.append("")
	L.append("## 첫 실제 1시간(금고 · 돈 때문에 미룬 일 누적 · 인구)")
	var mh: Array = r["money_hist"]
	var picks := [300, 600, 900, 1200, 1800, 2400, 3000, 3600]
	var cells: Array = []
	for t: int in picks:
		var best: Array = []
		for e: Array in mh:
			if int(e[0]) <= t:
				best = e
		if not best.is_empty():
			cells.append("%d분: ₩%d · 미룸 %d · %d명" % [t / 60, int(best[1]), int(best[2]), int(best[3])])
	L.append(" / ".join(cells))
	L.append("")
	L.append("## 실제 하루마다")
	L.append("| 실제일 | 경제일 | 떠돌이 | 세입자 | 토박이 | 유지 | 거물 | 노동 여유 T1/T2/T3/T4/T5 | 행복 | 금고 | 세수/일 | 순수지(전날) | 층 | 목표 | 연구 | 목재/철제/콘크리트/부품 재고 | 위험 |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for row: Dictionary in r["rows"]:
		var p: Array = row["pop"]
		var mt: Dictionary = row["mats"]
		L.append("| %d | %.1f | %d | %d | %d | %d | %d | %s | %.0f | %d | %.0f | %.0f | %d | %d | %d | %d/%d/%d/%d | %.0f |" % [row["day"], row["econ"], p[0], p[1], p[2], p[3], p[4],
			"/".join(PackedStringArray((row["labor_spare"] as Array).map(func(x: int) -> String: return str(x)))), row["happiness"], row["money"], row["tax_rate"], row["net"],
			row["floors"], row["goals"], row["research"], mt["wood"], mt["metal"], mt["concrete"], mt["parts"], row["heat"]])
	L.append("")
	L.append("## 현금 흐름(실행 전체 합, ₩)")
	var cn := {"tax": "세수", "upkeep": "유지비(시설·정책)", "import": "수입(교역)", "export": "수출(교역)", "build": "건설·승급·연구·탐험", "vice": "음성 수입", "reward": "목표 보상", "fine": "벌금"}
	L.append("| 줄 | 합계 | 경제일당 |")
	L.append("|---|---|---|")
	var cash: Dictionary = r["cash"]
	var ed := maxf(1.0, state.econ_days)
	for k: String in cn:
		L.append("| %s | %d | %.0f |" % [cn[k], int(cash.get(k, 0.0)), float(cash.get(k, 0.0)) / ed])
	L.append("| **순** | **%d** | **%.0f** |" % [int(cash.get("net", 0.0)), float(cash.get("net", 0.0)) / ed])
	L.append("")
	L.append("## 세 계열 자재와 설비 부품")
	L.append("| 자재 | 탐험 | 건재상 | 목표 보상 | 사용 | 남음 |")
	L.append("|---|---|---|---|---|---|")
	var mats: Dictionary = sr["mats"]
	for g: String in mats:
		var m: Dictionary = mats[g]
		L.append("| %s | %d | %d | %d | %d | %d |" % [sim.gname(g), int(m["exp"]), int(m["imp"]), int(m["goal"]), int(m["used"]), int(m["stock"])])
	L.append("")
	L.append("승급 준비가 끝났는데 자재가 없어 기다린 시간(주거·시간 합, 접속 중만): **%.1f시간**." % float(sr["mat_wait_h"]))
	L.append("")
	L.append("## 탐험")
	L.append("- 팀 가동률(나가 있던 시간 / 팀이 있던 시간): **%d%%**, 돌아와 수령을 기다린 시간: %d%%" % [int(float(sr["team_util"]) * 100.0), int(float(sr["team_wait"]) * 100.0)])
	L.append("- 파견: 근거리 %d · 중거리 %d · 원거리 %d, 수령 %d번" % [int(state.stats.get("exp_sent_near", 0.0)), int(state.stats.get("exp_sent_mid", 0.0)), int(state.stats.get("exp_sent_far", 0.0)), int(state.stats.get("exp_claims", 0.0))])
	L.append("")
	L.append("## 접속당 손길")
	var dec := float(sr["dec_per_session"])
	L.append("- 접속당 명령 %.1f개(그중 수령 빼고 결정 %.1f개)" % [float(sr["cmds_per_session"]), dec])
	var tot := {}
	for s: Dictionary in r["sessions"]:
		for k: String in s["cmds"]:
			tot[k] = int(tot.get(k, 0)) + int(s["cmds"][k])
	L.append("- 명령별 합: " + ", ".join(tot.keys().map(func(k: String) -> String: return "%s %d" % [k, tot[k]])))
	L.append("")
	L.append("## 외부 공급 의존")
	var ex: Dictionary = sr["external"]
	L.append("- 소비재·원료 중 수입 몫 %d%%, 물 중 외부 수도 %d%%, 전기 중 외부 전력 %d%%" % [int(float(ex["goods_import_share"]) * 100.0), int(float(ex["water_ext_share"]) * 100.0), int(float(ex["power_ext_share"]) * 100.0)])
	L.append("")
	L.append("## 마지막 날 재고 버팀")
	var eco: Dictionary = sim.query(state, "economy")
	L.append("| 상품 | 재고 | 생산/일 | 소비/일 | 수입/일 | 수출/일 | 버팀(일) |")
	L.append("|---|---|---|---|---|---|---|")
	for g: Dictionary in eco["goods"]:
		if float(g["cons"]) > 0.0:
			L.append("| %s | %.0f | %.1f | %.1f | %.1f | %.1f | %s |" % [g["name"], g["stock"], g["prod"], g["cons"], g["imp"], g["exp"], "늘어남" if float(g["days_left"]) < 0.0 else str(g["days_left"])])
	L.append("")
	L.append("## 마지막 날 수요 충족(계층별, 주민 가중)")
	var acc := {}
	for b: Dictionary in state.buildings.values():
		if b["kind"] != "house" or int(b["residents"]) == 0:
			continue
		for nid: String in b["needs"]:
			var a: Array = acc.get(nid, [0.0, 0.0])
			a[0] += float(b["needs"][nid].get("ratio", 0.0)) * float(b["residents"])
			a[1] += float(b["residents"])
			acc[nid] = a
	var by_t := {}
	for nid: String in sim.items("needs"):
		if acc.has(nid):
			var n := sim.item("needs", nid)
			var t := int(n["tier"])
			if not by_t.has(t):
				by_t[t] = []
			by_t[t].append("%s %d%%" % [n["name"], int(100.0 * float(acc[nid][0]) / maxf(1.0, float(acc[nid][1])))])
	for t: int in by_t:
		L.append("- %s: %s" % [sim.tname(t), ", ".join(by_t[t])])
	L.append("")
	if not (r["offline"] as Array).is_empty():
		L.append("## 긴 부재 뒤 복귀 요약(게임이 보여 준 문장)")
		for o: Dictionary in r["offline"]:
			L.append("- %.1f시간째 복귀:" % float(o["at_h"]))
			for l: String in o["lines"]:
				L.append("  - " + l)
		L.append("")
	L.append("## 막힌 것(봇이 하려다 못 한 일, 상위)")
	for b: Array in _top_blocked(r["bot"].blocked, 12):
		L.append("- %s — %d" % [b[0], b[1]])
	L.append("")
	L.append_array(per_cell)
	L.append("")
	L.append("## 기록(마지막 25줄)")
	for e: Dictionary in state.logbook.slice(maxi(0, state.logbook.size() - 25)):
		L.append("- %d일 %02d시 %s" % [int(e["day"]), int(e["hour"]), e["text"]])
	return "\n".join(L) + "\n"
