extends SceneTree
## 자동 플레이어 묶음 실행 → simulation/reports/run_batch.md
##   godot --headless --path godot -s res://expedition/run_batch.gd -- runs=200 profile=average seed=1
##   profile=all 이면 세 성격 모두. dt=0.0333(기본, 30Hz) · out=경로 · set=key:value,key:value(수치 실험)

const RunWorld = preload("res://expedition/RunWorld.gd")
const AutoPlayer = preload("res://expedition/AutoPlayer.gd")
const RunCfg = preload("res://expedition/RunCfg.gd")
const CityLink = preload("res://expedition/CityLink.gd")

const MAX_TIME := 900.0


func _initialize() -> void:
	var args := {"runs": "200", "profile": "all", "seed": "1", "dt": "0.0333", "out": "", "set": "", "quiet": "0", "dest": "scrap_yard"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if args["set"] != "":
		for pair in str(args["set"]).split(","):
			var kv2 := pair.split(":")
			if kv2.size() == 2:
				RunCfg.overrides[kv2[0]] = float(kv2[1])
	CityLink.use_city = false
	var profiles: Array = ["careless", "average", "careful"] if args["profile"] == "all" else str(args["profile"]).split(",")
	var runs := int(args["runs"])
	var seed0 := int(args["seed"])
	var dt := float(args["dt"])
	var all: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	for prof in profiles:
		var rs: Array = []
		for k in runs:
			var r := run_one(prof, seed0 + k, dt, str(args["dest"]))
			rs.append(r)
			if args["quiet"] != "1" and (k % 25 == 24 or k == runs - 1):
				print("%s %d/%d  (%.1fs)" % [prof, k + 1, runs, (Time.get_ticks_msec() - t0) / 1000.0])
		all[prof] = rs
	var md := report(all, runs, seed0, dt, str(args["set"]))
	var out: String = args["out"]
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../simulation/reports/run_batch.md")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(md)
	f.close()
	print(md)
	print("wrote ", out, " in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


static func run_one(prof: String, seed_value: int, dt: float, dest: String = "scrap_yard") -> Dictionary:
	var sample: Dictionary = RunCfg.file("run_goods").get("sample_begin", {})
	var w := RunWorld.new()
	w.fx = false
	w.setup(dest, {"stock": (sample["stock"] as Dictionary).duplicate(), "danger": int(sample.get("danger", 2)), "seed": seed_value})
	var bot := AutoPlayer.new()
	bot.setup(prof, seed_value)
	while not w.finished and w.time < MAX_TIME:
		bot.fill(w.input, w, dt)
		w.step(dt)
	var r: Dictionary
	if w.finished:
		r = w.result
	else:
		w.give_up()
		r = w.result
		r["outcome"] = "timeout"
	r["profile"] = prof
	r["leave_reason"] = bot.leave_reason
	# 장부 검산: 들고 나온 것 + 두고 온 것 + 잃은 것 = 찾은 것 ≤ 재고
	var ok := true
	var stock: Dictionary = sample["stock"]
	for g in RunCfg.goods():
		var c := int(r["carried"].get(g, 0)) + int(r["left"].get(g, 0)) + int(r["lost"].get(g, 0))
		if c != int(r["found"].get(g, 0)) or int(r["found"].get(g, 0)) > int(stock.get(g, 0)):
			ok = false
	r["ledger_ok"] = ok
	return r


static func _pct(n: int, d: int) -> String:
	return "%d%%" % int(round(100.0 * n / maxf(1.0, d)))


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


static func _q(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[clampi(int(q * (b.size() - 1)), 0, b.size() - 1)])


static func report(all: Dictionary, runs: int, seed0: int, dt: float, sets: String) -> String:
	var L: Array[String] = []
	L.append("# 직접 줍기 자동 플레이 묶음 결과")
	L.append("")
	L.append("- 던전: %s" % RunCfg.skin().get("name", ""))
	L.append("- 판 수: 성격마다 %d판 (지도 번호 %d~%d), 시간 간격 %.4f초, 견본 재고(run_goods.json sample_begin)" % [runs, seed0, seed0 + runs - 1, dt])
	if sets != "":
		L.append("- 수치 덮어쓰기: `%s`" % sets)
	L.append("- 만든 것: `godot/expedition/run_batch.gd` · 날짜: %s" % Time.get_date_string_from_system())
	L.append("")
	L.append("## 결과 비율")
	L.append("")
	L.append("| 성격 | 두목 잡고 나옴(boss) | 그냥 나옴(exit) | 쓰러짐(down) | 시간 초과 | 두목 방 도착 | 두목 잡음 | 장부 맞음 |")
	L.append("|---|---|---|---|---|---|---|---|")
	for prof in all:
		var rs: Array = all[prof]
		var c := {"boss": 0, "exit": 0, "down": 0, "timeout": 0}
		var reached := 0
		var killed := 0
		var ledger := 0
		for r in rs:
			c[r["outcome"]] = int(c.get(r["outcome"], 0)) + 1
			if r["reached_boss"]:
				reached += 1
			if r["boss_killed"]:
				killed += 1
			if r["ledger_ok"]:
				ledger += 1
		L.append("| %s | %s | %s | %s | %s | %s | %s | %d/%d |" % [prof, _pct(c["boss"], rs.size()), _pct(c["exit"], rs.size()), _pct(c["down"], rs.size()), _pct(c["timeout"], rs.size()), _pct(reached, rs.size()), _pct(killed, rs.size()), ledger, rs.size()])
	L.append("")
	L.append("## 한 판 길이(게임 시간, 분)")
	L.append("")
	L.append("| 성격 | 10% | 25% | 가운데 | 75% | 90% | 최장 |")
	L.append("|---|---|---|---|---|---|---|")
	for prof in all:
		var ts: Array = []
		for r in all[prof]:
			ts.append(float(r["time"]) / 60.0)
		L.append("| %s | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |" % [prof, _q(ts, 0.1), _q(ts, 0.25), _median(ts), _q(ts, 0.75), _q(ts, 0.9), _q(ts, 1.0)])
	L.append("")
	L.append("## 한 판에 들고 나온 양(평균, 수량)")
	L.append("")
	var ids: Array = RunCfg.goods().keys()
	var hdr := "| 성격 |"
	var sep := "|---|"
	for g in ids:
		hdr += " %s |" % RunCfg.good_name(g)
		sep += "---|"
	hdr += " 합계 | 가운데 합계 | 값어치(평균) |"
	sep += "---|---|---|"
	L.append(hdr)
	L.append(sep)
	for prof in all:
		var rs: Array = all[prof]
		var line := "| %s |" % prof
		var tot := 0.0
		var totals: Array = []
		var val := 0.0
		for r in rs:
			var s := 0
			for g in ids:
				s += int(r["carried"].get(g, 0))
				val += int(r["carried"].get(g, 0)) * float(RunCfg.good(g).get("value", 1))
			totals.append(s)
		for g in ids:
			var sum := 0
			for r in rs:
				sum += int(r["carried"].get(g, 0))
			tot += sum
			line += " %.1f |" % (float(sum) / rs.size())
		line += " %.1f | %.0f | %.1f |" % [tot / rs.size(), _median(totals), val / rs.size()]
		L.append(line)
	L.append("")
	L.append("## 결과별 들고 나온 양 · 찾은 양 · 잃은 양(평균 합계)")
	L.append("")
	L.append("| 성격 | 결과 | 판 | 들고 나옴 | 찾음 | 두고 옴 | 잃음 | 가 본 방 | 소란 단계 | 받은 타격 | 구르기로 피함 |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|")
	for prof in all:
		for oc in ["boss", "exit", "down", "timeout"]:
			var n := 0
			var sc := 0.0
			var sf := 0.0
			var sl := 0.0
			var slo := 0.0
			var rv := 0.0
			var nl := 0.0
			var ht := 0.0
			var dg := 0.0
			for r in all[prof]:
				if r["outcome"] != oc:
					continue
				n += 1
				for g in ids:
					sc += int(r["carried"].get(g, 0))
					sf += int(r["found"].get(g, 0))
					sl += int(r["left"].get(g, 0))
					slo += int(r["lost"].get(g, 0))
				rv += int(r["rooms_visited"])
				nl += int(r["noise_level"])
				ht += int(r.get("hits_taken", 0))
				dg += int(r.get("dodges", 0))
			if n == 0:
				continue
			L.append("| %s | %s | %d | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |" % [prof, oc, n, sc / n, sf / n, sl / n, slo / n, rv / n, nl / n, ht / n, dg / n])
	L.append("")
	L.append("## 쓰러뜨린 것(쓰러진 판의 마지막 타격)")
	L.append("")
	L.append("| 성격 | 쥐 | 띠개 | 경비원 | 고물상 | 두목 | 무너진 더미 | 누전 |")
	L.append("|---|---|---|---|---|---|---|---|")
	for prof in all:
		var c2 := {}
		for r in all[prof]:
			if r["outcome"] == "down":
				c2[r["last_hurt_by"]] = int(c2.get(r["last_hurt_by"], 0)) + 1
		L.append("| %s | %d | %d | %d | %d | %d | %d | %d |" % [prof, c2.get("rat", 0), c2.get("dog", 0), c2.get("guard", 0), c2.get("rival", 0), c2.get("boss", 0), c2.get("junk", 0), c2.get("wire", 0)])
	L.append("")
	return "\n".join(L)
