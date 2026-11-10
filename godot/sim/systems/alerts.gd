extends SimSystem
## alerts — hud.alerts를 모은다. 각 {id, text, tone, jump{screen, arg}} (한국어).
##  경제 2스텝(1경제시간)마다 조건을 보고 state.flags.alerts에 기억한다: 조건이 꺼져도 1경제시간 동안은 남긴다(깜빡임 방지).
##  새로 뜬 알림은 alert{id, text, tone} 이벤트. 실제 시간에 따르는 것(탐험 귀환)은 질의 때 바로 본다.
##  hud에서는 다른 시스템이 붙인 알림과 합쳐(같은 id는 이쪽 것) 급한 순(bad → warn → good, 같은 tone은 ORDER 순)으로 최대 config alerts.max(4)개.
##  jump 화면: build[:id|cat] · economy[:tab|good] · expedition · trade · keep[:tab] · upgrade · inspect:<bid> (ARCHITECTURE 파트 B 추가).
## 끄면: 다른 시스템이 붙인 알림만 그대로 나온다(정렬·상한 없음).

const ORDER := ["broke", "power", "water", "labor", "needs_bad", "leaving", "stockout", "raid", "heat", "contracts", "needs_warn",
	"waiting", "exp_done", "upgradable", "floor", "research_done", "goal"]
const TONE_RANK := {"bad": 0, "warn": 1, "good": 2, "": 3}


func tick(state: CityState, dt: float) -> void:
	if not sim.every(state, 2, dt):
		return
	var raw := _compute(state)
	var mem: Dictionary = state.flags.get("alerts", {})
	var keep := float(sim.cfg("alerts.linger_days", 1.0 / 24.0))
	var out := {}
	for id: String in raw:
		var a: Dictionary = raw[id]
		if not mem.has(id):
			state.emit("alert", {"id": id, "text": a["text"], "tone": a["tone"]})
		a["off"] = -1.0
		out[id] = a
	for id: String in mem:
		if out.has(id):
			continue
		var a: Dictionary = mem[id]
		var off := float(a.get("off", -1.0))
		if off < 0.0:
			off = state.econ_days
		if state.econ_days - off < keep - 1e-9:
			a["off"] = off
			out[id] = a
	state.flags["alerts"] = out


func _al(id: String, text: String, tone: String, screen: String, arg: Variant = "") -> Dictionary:
	return {"id": id, "text": text, "tone": tone, "jump": {"screen": screen, "arg": arg}}


func _compute(state: CityState) -> Dictionary:
	var r := {}
	# 돈
	var stopped := 0
	for b: Dictionary in sim.cover(state)["facs"]:
		if b.get("money_stop", false):
			stopped += 1
	if stopped > 0:
		r["broke"] = _al("broke", "돈이 없어 시설 %d곳이 멈췄다" % stopped, "bad", "economy", "finance")
	# 물·전기
	for u: String in ["water", "power"]:
		var x: Dictionary = state.util.get(u, {})
		var s := float(x.get("supply", 0.0))
		var d := float(x.get("demand", 0.0))
		if d > 0.5 and s < d - 1e-6:
			r[u] = _al(u, "%s이(가) 모자란다(공급 %d / 수요 %d)" % ["물" if u == "water" else "전기", int(s), int(ceilf(d))], "bad", "build", u)
	# 일손
	var short: Array = []
	for t: Variant in state.labor:
		var l: Dictionary = state.labor[t]
		var gap := int(ceilf(float(l.get("need", 0.0)) - 1e-6)) - int(l.get("have", 0))
		if gap > 0:
			short.append("%s %d명" % [sim.tname(int(t)), gap])
	if not short.is_empty():
		r["labor"] = _al("labor", "일손이 모자란다: %s" % ", ".join(short), "bad", "economy", "labor")
	# 주거
	var bad := 0
	var warn := 0
	for b: Dictionary in sim.cover(state)["houses"]:
		if b["need_state"] == "bad":
			bad += 1
		elif b["need_state"] == "warn" and int(b["residents"]) > 0:
			warn += 1
	if bad > 0:
		r["needs_bad"] = _al("needs_bad", "주거 %d채가 공급 부족으로 주민을 잃고 있다" % bad, "bad", "economy", "")
	elif warn > 0:
		r["needs_warn"] = _al("needs_warn", "주거 %d채에 부족한 수요가 있다(유예 중)" % warn, "warn", "economy", "")
	# 대기 주민
	var wait := 0
	var soon := 0
	for t: Variant in state.waiting:
		var w: Dictionary = state.waiting[t]
		wait += int(w.get("count", 0))
		if float(w.get("days_left", 9.0)) < 1.0:
			soon += int(w.get("count", 0))
	if soon > 0:
		r["leaving"] = _al("leaving", "빈집을 못 찾은 주민 %d명이 곧 떠난다 — 주거를 칠하자" % soon, "bad", "build", "house")
	elif wait > 0:
		r["waiting"] = _al("waiting", "빈집을 기다리는 주민 %d명" % wait, "warn", "build", "house")
	# 하루 안에 바닥나는 상품(소비가 있는 상품만)
	var out_now: Array = []
	var out_soon: Array = []
	var first := ""
	for g: String in state.flow:
		var f: Dictionary = state.flow[g]
		var cons := float(f.get("cons", 0.0))
		if cons < 0.05:
			continue
		var net := float(f.get("prod", 0.0)) + float(f.get("imp", 0.0)) - cons - float(f.get("exp", 0.0))
		var st := float(state.stock.get(g, 0.0))
		if st < 0.5:
			out_now.append(sim.gname(g))
			if first == "":
				first = g
		elif net < -1e-6 and st / -net < 1.0:
			out_soon.append(sim.gname(g))
			if first == "":
				first = g
	if not out_now.is_empty():
		r["stockout"] = _al("stockout", "%s 재고가 없다" % "·".join(out_now.slice(0, 3)), "bad", "economy", first)
	elif not out_soon.is_empty():
		r["stockout"] = _al("stockout", "%s이(가) 하루 안에 바닥난다" % "·".join(out_soon.slice(0, 3)), "warn", "economy", first)
	# 계약
	var fl := 0
	for c: Dictionary in state.contracts:
		if not c.get("last", {}).get("ok", true):
			fl += 1
	if fl > 0:
		r["contracts"] = _al("contracts", "계약 %d건이 지난 회차를 건너뛰었다" % fl, "warn", "trade", "")
	# 승급
	var up := 0
	for b: Dictionary in sim.cover(state)["houses"]:
		if b.get("upgradable", false):
			up += 1
	if up > 0:
		r["upgradable"] = _al("upgradable", "승급할 수 있는 주거 %d채" % up, "good", "upgrade", "")
	# 층
	if state.floors_unlocked < sim.F:
		var z := state.floors_unlocked - 1
		var need := int(ceilf(float(sim.cfg("floors.threshold", 0.8)) * float(sim.cfg("floors.eligible_cells", 144)) - 1e-6))
		var used := Cover.used_cells_fast(sim, state, z)
		var left := need - used
		if left > 0 and left <= int(sim.cfg("alerts.floor_cells", 12)):
			r["floor"] = _al("floor", "%d층이 열리기까지 %d층에 %d칸" % [z + 2, z + 1, left], "good", "build", "house")
	# 단속 위험
	if state.heat >= float(sim.cfg("heat.warn", 50)):
		r["heat"] = _al("heat", "단속 위험 %d — 80이면 음성 시설 하나가 닫힌다" % int(state.heat), "warn", "keep", "policies")
	for b: Dictionary in sim.cover(state)["facs"]:
		if b.get("raid_until", -1.0) != null and float(b.get("raid_until", -1.0)) > state.econ_days:
			r["raid"] = _al("raid", "%s이(가) 단속으로 닫혀 있다" % sim.bdef(str(b["type"])).get("name", ""), "bad", "inspect", int(b["id"]))
			break
	return r


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name != "hud":
		return
	var mine: Dictionary = {}
	for id: String in state.flags.get("alerts", {}):
		var a: Dictionary = state.flags["alerts"][id]
		mine[id] = {"id": a["id"], "text": a["text"], "tone": a["tone"], "jump": a["jump"]}
	var done := int(out.get("teams_done", 0))
	if done > 0:
		mine["exp_done"] = _al("exp_done", "탐험대 %d팀이 돌아왔다 — 짐을 받자" % done, "good", "expedition", "")
	var all: Array = mine.values()
	for a: Dictionary in out.get("alerts", []):
		if not mine.has(str(a.get("id", ""))):
			all.append(a)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: int = TONE_RANK.get(str(a.get("tone", "")), 3)
		var tb: int = TONE_RANK.get(str(b.get("tone", "")), 3)
		if ta != tb:
			return ta < tb
		var oa := ORDER.find(str(a.get("id", "")))
		var ob := ORDER.find(str(b.get("id", "")))
		oa = oa if oa >= 0 else 99
		ob = ob if ob >= 0 else 99
		if oa != ob:
			return oa < ob
		return str(a.get("id", "")) < str(b.get("id", "")))
	out["alerts"] = all.slice(0, int(sim.cfg("alerts.max", 4)))
	out["alerts_total"] = all.size()
