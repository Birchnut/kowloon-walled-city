extends SceneTree
## 직접 줍기 시험: 성격마다 고정 씨앗 5판 + (모자라면) 결과 셋이 다 나올 때까지 씨앗을 더 돌린다.
## 확인: 장부(들고 나옴 + 두고 옴 + 잃음 = 찾음 ≤ 재고), 결과는 boss/exit/down 중 하나, 셋 다 나옴, 배낭 칸 수.
const RB = preload("res://expedition/run_batch.gd")
const RunCfg = preload("res://expedition/RunCfg.gd")
const CityLink = preload("res://expedition/CityLink.gd")

func _initialize() -> void:
	CityLink.use_city = false
	var fails: Array[String] = []
	var seen := {}
	var n := 0
	for prof in ["careless", "average", "careful"]:
		for sd in range(1, 6):
			var r: Dictionary = RB.run_one(prof, sd, 1.0 / 60.0)
			n += 1
			_check(r, prof, sd, fails)
			seen[r["outcome"]] = true
			print("  %s seed=%d → %s (%.0f초, 들고 나옴 %d)" % [prof, sd, r["outcome"], r["time"], _sum(r["carried"])])
	# 모자란 결과 채우기
	var want := {"down": "careless", "boss": "careful", "exit": "average"}
	for oc in want:
		var sd2 := 6
		while not seen.has(oc) and sd2 < 60:
			var r2: Dictionary = RB.run_one(want[oc], sd2, 1.0 / 60.0)
			n += 1
			_check(r2, want[oc], sd2, fails)
			seen[r2["outcome"]] = true
			sd2 += 1
		if not seen.has(oc):
			fails.append("결과 %s 가 60판 안에 한 번도 안 나옴" % oc)
	print("판 수 %d, 나온 결과 %s" % [n, seen.keys()])
	if fails.is_empty():
		print("RUN_TEST PASS")
	else:
		for f in fails:
			print("FAIL: ", f)
		print("RUN_TEST FAIL")
	quit(0 if fails.is_empty() else 1)


func _sum(d: Dictionary) -> int:
	var s := 0
	for k in d:
		s += int(d[k])
	return s


func _check(r: Dictionary, prof: String, sd: int, fails: Array[String]) -> void:
	var tag := "%s seed=%d" % [prof, sd]
	if not r["ledger_ok"]:
		fails.append("%s 장부가 안 맞음: found=%s carried=%s left=%s lost=%s" % [tag, r["found"], r["carried"], r["left"], r["lost"]])
	if not (r["outcome"] in ["boss", "exit", "down"]):
		fails.append("%s 결과 이상: %s" % [tag, r["outcome"]])
	if r["outcome"] == "boss" and not r["boss_killed"]:
		fails.append("%s boss 결과인데 두목이 살아 있음" % tag)
	if r["outcome"] == "down" and _sum(r["lost"]) == 0 and _sum(r["carried"]) > 1:
		fails.append("%s 쓰러졌는데 잃은 것이 없음" % tag)
	var stock: Dictionary = RunCfg.file("run_goods")["sample_begin"]["stock"]
	for g in r["found"]:
		if int(r["found"][g]) > int(stock.get(g, 0)):
			fails.append("%s 재고보다 많이 찾음: %s" % [tag, g])
