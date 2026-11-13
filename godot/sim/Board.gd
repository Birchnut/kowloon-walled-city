class_name Board
extends RefCounted
## Board — 현황판(질의 metrics)과 위 띠 신호등(hud.signals). 읽기만, 규칙 없음. 모든 문장은 한국어로 여기서 만든다.
## 행 = 물·전기 / 먹을 것 단계별 / 그 밖 상품 / 서비스 범위(놀 거리·시장) / 불·병. 열 = 공급·수요·비율·상태·남은 날·할 일 한 줄·이동.
## 수요 추정 = 계층 인구 × 1인 소비(needs.json). 공급 = 최근 1경제일 생산 + 수입(state.flow). 상태: ok ≥ 수요, warn = 3일 안에 바닥, bad = 없음.

const TAB := {"water": "물", "power": "전기"}


static func _pop(sim: Sim, state: CityState) -> Dictionary:
	var pop := {}
	for b: Dictionary in sim.cover(state)["houses"]:
		pop[int(b["tier"])] = float(pop.get(int(b["tier"]), 0.0)) + float(b["residents"])
	for t: Variant in state.waiting:
		pop[int(t)] = float(pop.get(int(t), 0.0)) + float(state.waiting[t].get("count", 0))
	return pop


## 상품별 하루 수요(주민) — 수요 역할(기본·승급·여유) 모두. 시설 원료는 생산식으로 더한다.
static func good_demand(sim: Sim, state: CityState) -> Dictionary:
	var pop := _pop(sim, state)
	var dem := {}
	for nid: String in sim.items("needs"):
		var n := sim.item("needs", nid)
		var r := float(pop.get(int(n["tier"]), 0.0))
		if r <= 0.0 or not n.has("amount"):
			continue
		var goods: Array = []
		for o: Dictionary in n["options"]:
			if o.has("good"):
				goods.append(str(o["good"]))
		for g: String in goods:
			dem[g] = float(dem.get(g, 0.0)) + r * float(n["amount"]) / float(goods.size())
	for b: Dictionary in sim.cover(state)["facs"]:
		var rec: Dictionary = sim.bdef(str(b["type"])).get("recipe", {})
		if rec.is_empty() or Sim.off_reason(b) != "":
			continue
		for g: String in rec.get("in", {}):
			dem[g] = float(dem.get(g, 0.0)) + float(rec["in"][g]) * maxf(float(b.get("eff", 0.0)), 0.5)
	return dem


static func _producers(sim: Sim, g: String) -> String:
	for id: String in sim.items("buildings"):
		if sim.bdef(id).get("recipe", {}).get("out", {}).has(g):
			return id
	return ""


static func _good_row(sim: Sim, state: CityState, g: String, d: float, group: String) -> Dictionary:
	var f: Dictionary = state.flow.get(g, {})
	var sup := float(f.get("prod", 0.0)) + float(f.get("imp", 0.0))
	var st := float(state.stock.get(g, 0.0))
	var net := sup - d - float(f.get("exp", 0.0))
	var days: Variant = null
	if net < -1e-6:
		days = snappedf(st / -net, 0.1)
	var s := "ok"
	if st < 0.5 and sup < d * 0.9:
		s = "bad"
	elif days != null and float(days) < 3.0:
		s = "warn"
	var name := sim.gname(g)
	var prod := _producers(sim, g)
	var hint := ""
	match s:
		"bad":
			hint = "%s이(가) 바닥났다 — %s" % [name, "%s을(를) 더 짓는다" % sim.bdef(prod).get("name", prod) if prod != "" else "회상회에서 들여오는 계약을 맺는다"]
		"warn":
			hint = "%s일 안에 바닥난다 — %s" % [str(days), "%s을(를) 하나 더 짓는다" % sim.bdef(prod).get("name", prod) if prod != "" else "들여오는 양을 늘린다"]
		_:
			hint = "넉넉하다" if net >= 0.0 else "재고로 버틴다(%s일)" % str(days)
	var jump := {"screen": "build", "arg": prod} if prod != "" and s != "ok" else {"screen": "economy", "arg": g}
	if prod == "" and s != "ok":
		jump = {"screen": "trade", "arg": g}
	return {"id": g, "group": group, "name": name, "supply": snappedf(sup, 0.1), "demand": snappedf(d, 0.1), "unit": "개/일",
		"stock": snappedf(st, 0.1), "ratio": 1.0 if d <= 1e-6 else snappedf(minf(9.99, sup / d), 0.01), "state": s, "days_left": days,
		"hint": Sim.kr(hint), "jump": jump}


## 수요의 범위 부족(서비스·시장) — 그 수요를 가진 주거 중 범위 밖/등급 부족/인력 부족 비율.
static var _nk: Dictionary = {}
static var _nk_sim: int = -1


## 수요 id → [행 키, 행 이름] (서비스·시장 범위가 필요한 비여유 수요만). 데이터에서 한 번만.
static func _need_keys(sim: Sim) -> Dictionary:
	if _nk_sim == sim.get_instance_id():
		return _nk
	_nk = {}
	_nk_sim = sim.get_instance_id()
	for nid: String in sim.items("needs"):
		var n := sim.item("needs", nid)
		if n.get("role", "") == "luxury":
			continue
		for o: Dictionary in n.get("options", []):
			if o.has("service"):
				_nk[nid] = ["fun" if nid.ends_with("_fun") else "svc:" + str(o["service"]), "놀 거리 범위" if nid.ends_with("_fun") else "%s 범위" % n.get("name", "")]
				break
			if o.has("good"):
				var gr := int(sim.good(o["good"]).get("grade", 1))
				_nk[nid] = ["mkt:%d" % gr, "%d등급 시장 범위" % gr]
				break
	return _nk


static func _service_rows(sim: Sim, state: CityState) -> Array:
	var rows: Array = []
	var acc := {}     # key → [대상 집, 부족 집, 이름]
	var nk := _need_keys(sim)
	for b: Dictionary in sim.cover(state)["houses"]:
		if int(b["residents"]) == 0:
			continue
		var needs: Dictionary = b.get("needs", {})
		for nid: String in needs:
			var kk: Variant = nk.get(nid)
			if kk == null:
				continue
			var key: String = kk[0]
			var a: Array = acc.get(key, [0, 0, kk[1]])
			a[0] += 1
			var c := str(needs[nid].get("cause", ""))
			if c in ["range", "grade", "staff"]:
				a[1] += 1
			acc[key] = a
	for key: String in acc:
		var a: Array = acc[key]
		var ok := int(a[0]) - int(a[1])
		var ratio := float(ok) / float(maxi(1, int(a[0])))
		var s := "ok" if ratio >= 0.97 else ("warn" if ratio >= 0.8 else "bad")
		var arg := ""
		if key == "fun":
			arg = "mahjong"
		elif key.begins_with("mkt:"):
			for id: String in sim.items("buildings"):
				if int(sim.bdef(id).get("market", 0)) == int(key.substr(4)):
					arg = id
		else:
			for id: String in sim.items("buildings"):
				if key.substr(4) in sim.bdef(id).get("services", []):
					arg = id
					break
		rows.append({"id": key, "group": "service", "name": a[2], "supply": ok, "demand": int(a[0]), "unit": "채", "stock": null, "ratio": snappedf(ratio, 0.01),
			"state": s, "days_left": null, "hint": "모든 집에 닿는다" if s == "ok" else "%d채가 범위 밖이거나 일손이 없다 — %s 근처에 하나 더" % [int(a[1]), sim.bdef(arg).get("name", "시설")],
			"jump": {"screen": "lens", "arg": "fun" if key == "fun" else ("market" if key.begins_with("mkt:") else "service:" + arg)}})
	return rows


static func metrics(sim: Sim, state: CityState) -> Dictionary:
	var rows: Array = []
	for u: String in ["water", "power"]:
		var x: Dictionary = state.util.get(u, {})
		var s := float(x.get("supply", 0.0))
		var d := float(x.get("demand", 0.0))
		var r := 1.0 if d <= 1e-6 else s / d
		var st := "ok" if r >= 1.0 - 1e-6 else ("warn" if r >= 0.9 else "bad")
		if d <= 1e-6 and s <= 1e-6:
			st = "off"
		rows.append({"id": u, "group": "utility", "name": TAB[u], "supply": snappedf(s, 0.1), "demand": snappedf(d, 0.1), "unit": "/일" if u == "water" else "부하", "stock": null,
			"ratio": snappedf(minf(9.99, r), 0.01), "state": st, "days_left": null,
			"hint": "넉넉하다" if st == "ok" or st == "off" else Sim.kr("%s이(가) %d 모자란다 — %s" % [TAB[u], int(ceilf(d - s)), "우물 펌프를 하나 더" if u == "water" else "발전기를 하나 더"]),
			"jump": {"screen": "build", "arg": u}})
	var dem := good_demand(sim, state)
	var food: Array = []
	for nid: String in sim.items("needs"):
		var n := sim.item("needs", nid)
		if n.get("food", false):
			for o: Dictionary in n["options"]:
				if o.has("good") and not (str(o["good"]) in food):
					food.append(str(o["good"]))
	for g: String in food:
		if float(dem.get(g, 0.0)) > 1e-6 or float(state.stock.get(g, 0.0)) > 0.0:
			rows.append(_good_row(sim, state, g, float(dem.get(g, 0.0)), "food"))
	for g: String in sim.items("goods"):
		if g in food or not dem.has(g) or float(dem[g]) <= 1e-6:
			continue
		rows.append(_good_row(sim, state, g, float(dem[g]), "goods"))
	rows.append_array(_service_rows(sim, state))
	var hz: Variant = sim.query(state, "hazards")
	var hz_rows: Array = []
	if hz is Dictionary:
		var f: Dictionary = hz["fire"]
		var d2: Dictionary = hz["disease"]
		var fs := "off" if not f["on"] else ("bad" if not (f["burning"] as Array).is_empty() else ("warn" if float(f["covered_pct"]) < 0.95 or not (f["burnt"] as Array).is_empty() else "ok"))
		var ds := "off" if not d2["on"] else ("bad" if not (d2["sick"] as Array).is_empty() else ("warn" if float(d2["trash_covered_pct"]) < 0.95 or float(d2["covered_pct"]) < 0.9 else "ok"))
		var fr := {"id": "fire", "group": "hazard", "name": "불", "supply": snappedf(float(f["covered_pct"]) * 100.0, 1), "demand": 100, "unit": "% 덮임", "stock": null,
			"ratio": f["covered_pct"], "state": fs, "days_left": f["grace_left"] if float(f["grace_left"]) > 0.0 else null, "hint": f["text"],
			"jump": {"screen": "lens", "arg": "fire"}}
		var dr := {"id": "disease", "group": "hazard", "name": "병", "supply": snappedf(float(d2["trash_covered_pct"]) * 100.0, 1), "demand": 100, "unit": "% 수거", "stock": null,
			"ratio": d2["trash_covered_pct"], "state": ds, "days_left": d2["grace_left"] if float(d2["grace_left"]) > 0.0 else null, "hint": d2["text"],
			"jump": {"screen": "lens", "arg": "trash"}}
		rows.append(fr)
		rows.append(dr)
		hz_rows = [{"id": "fire", "name": "불", "on": f["on"], "covered_pct": f["covered_pct"], "active": (f["burning"] as Array).size() + (f["burnt"] as Array).size(), "text": f["text"], "jump": fr["jump"]},
			{"id": "disease", "name": "병", "on": d2["on"], "covered_pct": d2["covered_pct"], "active": (d2["sick"] as Array).size(), "text": d2["text"], "jump": dr["jump"]}]
	var labor: Array = []
	for t: int in range(1, sim.max_tier() + 1):
		var l: Dictionary = state.labor.get(t, {"have": 0, "need": 0.0})
		labor.append({"tier": t, "name": sim.tname(t), "have": int(l["have"]), "need": int(ceilf(float(l["need"]) - 1e-6)),
			"spare": int(l["have"]) - int(ceilf(float(l["need"]) - 1e-6))})
	var tiers: Array = []
	var by := {}
	for b: Dictionary in sim.cover(state)["houses"]:
		var t := int(b["tier"])
		var a: Array = by.get(t, [0, 0, 0, 0, 0])
		a[0] += int(b["residents"])
		a[1] += 1
		if int(b["residents"]) >= int(b["cap"]):
			a[2] += 1
		if b.get("upgradable", false):
			a[3] += 1
		a[4] += maxi(0, int(b.get("target", 0)) - int(b["residents"]))
		by[t] = a
	for t: int in range(1, sim.max_tier() + 1):
		var a: Array = by.get(t, [0, 0, 0, 0, 0])
		tiers.append({"tier": t, "name": sim.tname(t), "pop": a[0], "houses": a[1], "full": a[2], "upgradable": a[3], "arriving": a[4]})
	var days: Array = state.ledger.get("days", [])
	var src: Dictionary = days.back() if not days.is_empty() else state.ledger.get("today", {})
	var income := 0.0
	var cost := 0.0
	var lines: Array = []
	const NAMES := {"tax": "물세·자리값", "vice": "층세", "export": "내보낸 값", "reward": "목표 보상", "upkeep": "유지비", "import": "들여온 값", "build": "짓고 올리고 고친 값", "fine": "벌금", "leak": "새는 돈"}
	for k: String in NAMES:
		var v := float(src.get(k, 0.0))
		if v > 0.0:
			income += v
		else:
			cost -= v
		if absf(v) > 0.05:
			lines.append({"name": NAMES[k], "amount": snappedf(v, 0.1)})
	return {"rows": rows, "labor": labor, "tiers": tiers,
		"finance": {"income": snappedf(income, 0.1), "cost": snappedf(cost, 0.1), "net": snappedf(income - cost, 0.1), "lines": lines,
			"day": int(src.get("day", state.day))},
		"hazards": hz_rows}


## 위 띠 신호등: 물·전기·먹을 것·놀 것·불·병·일손.
static func signals(sim: Sim, state: CityState, m: Dictionary = {}) -> Array:
	if m.is_empty():
		m = metrics(sim, state)
	var out: Array = []
	var by := {}
	for r: Dictionary in m["rows"]:
		by[r["id"]] = r
	for u: String in ["water", "power"]:
		var r: Dictionary = by.get(u, {})
		out.append({"id": u, "name": TAB[u], "state": r.get("state", "off"), "text": r.get("hint", ""), "jump": r.get("jump", {"screen": "build", "arg": u})})
	var worst := "off"
	var wt := "먹을 것이 아직 필요 없다"
	var wj := {"screen": "metrics", "arg": "food"}
	const RANK := {"off": 0, "ok": 1, "warn": 2, "bad": 3}
	for r: Dictionary in m["rows"]:
		if r["group"] == "food" and int(RANK[r["state"]]) >= int(RANK[worst]) and float(r["demand"]) > 0.0:
			if int(RANK[r["state"]]) > int(RANK[worst]) or worst == "off":
				wt = "%s: %s" % [r["name"], r["hint"]]
				wj = r["jump"]
			worst = r["state"]
	if worst == "ok":
		wt = "먹을 것이 넉넉하다"
	out.append({"id": "food", "name": "먹을 것", "state": worst, "text": wt, "jump": wj})
	var fun: Dictionary = by.get("fun", {})
	out.append({"id": "fun", "name": "놀 것", "state": fun.get("state", "off"), "text": fun.get("hint", "아직 아무도 안 산다"), "jump": fun.get("jump", {"screen": "build", "arg": "mahjong"})})
	for k: String in ["fire", "disease"]:
		var r: Dictionary = by.get(k, {})
		out.append({"id": k, "name": "불" if k == "fire" else "병", "state": r.get("state", "off"), "text": r.get("hint", ""), "jump": r.get("jump", {"screen": "lens", "arg": k})})
	var short: Array = []
	for l: Dictionary in m["labor"]:
		if int(l["spare"]) < 0:
			short.append("%s %d명" % [l["name"], -int(l["spare"])])
	out.append({"id": "labor", "name": "일손", "state": "ok" if short.is_empty() else "bad",
		"text": "일손이 맞는다" if short.is_empty() else "모자란다: " + ", ".join(short) + " — 그 계층 집을 더 짓거나 승급을 늦춘다",
		"jump": {"screen": "metrics", "arg": "labor"}})
	return out
