class_name Queries
extends RefCounted
## Queries — 공용 질의의 뼈대(읽기 전용, 규칙 없음). 시스템은 augment()로 자기 몫을 보탠다.
## 시스템이 꺼져 있어도 모양은 그대로(빈 값) — UI가 null을 받지 않는다. 계약은 docs/ARCHITECTURE.md "질의".


static func run(sim: Sim, state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"hud": return _hud(sim, state)
		"build_menu": return _build_menu(sim, state)
		"info": return _info(sim, state, args)
		"economy": return _economy(sim, state)
		"log": return state.logbook.slice(maxi(0, state.logbook.size() - int(args.get("n", 20))))
		"metrics": return Board.metrics(sim, state)
		"metrics_raw": return Metrics.compute(sim, state)
		"hazards":
			return {"fire": {"on": false, "since_day": -1.0, "grace_left": 0.0, "covered_pct": 0.0, "burning": [], "burnt": [], "text": "불은 꺼져 있다."},
				"disease": {"on": false, "since_day": -1.0, "grace_left": 0.0, "covered_pct": 0.0, "trash_covered_pct": 0.0, "sick": [], "trash_pct": 0.0, "text": "병은 꺼져 있다."}}
		"coverage": return {"covered": [], "uncovered": [], "pct": 0.0, "text": ""}
		"range_preview": return {"cells": [], "houses": 0, "text": ""}
		"contracts": return {"slots": {"used": 0, "max": 0}, "active": [], "offers": [], "no_post": true}
		"expeditions":   # [B 파트]
			var mats: Array = []
			for m: String in sim.db.get("upgrade_costs", {}).get("materials", []):
				mats.append({"id": m, "name": sim.gname(m), "have": int(state.stock.get(m, 0.0))})
			return {"teams": [], "slots": {"have": 0, "max": 3}, "dests": [], "provision": {"good_text": "", "bonus_text": "", "enough": false}, "materials": mats}
		"research":      # [B 파트]
			return {"can": false, "hint": "연구는 아직 준비 중이다.", "active": {}, "nodes": []}
		"policies":      # [B 파트]
			return {"slots": {"used": 0, "max": 0}, "items": []}
		"goals":
			return _goals(sim, state)
		"upgradable":     # upgrades 시스템이 꺼져 있을 때의 빈 모양
			return []
		"upgrade_preview":
			return {"ok": false, "blockers": ["승급 시스템이 꺼져 있다."], "cost": {"money": 0, "qty": 0, "extra": {}}, "cap_from": 0, "cap_to": 0,
				"movers": 0, "vacancies": 0, "labor": [], "tax_now": 0.0, "tax_after_now": 0.0, "tax_full": 0.0, "tax_delta": 0.0, "demand_text": []}
		"offline_summary":
			return null   # G1: 보여 줄 것이 없으면 null(Game이 정산 직후 한 번만 실제 요약을 돌려준다)
	return null


## 해금 조건을 문장으로.
static func cond_text(sim: Sim, cond: Variant) -> String:
	var parts: Array = []
	if cond is Array:
		for c: Variant in cond:
			if c is Array and c.size() == 3:
				var k := str(c[0])
				if k.begins_with("pop.t"):
					parts.append("%s %d명" % [sim.tname(int(k.substr(5))), int(c[2])])
				elif k.begins_with("count."):
					parts.append("%s 완공" % sim.bdef(k.substr(6)).get("name", k))
				elif k.begins_with("happy_held."):
					parts.append("행복도 %s 이상을 %s일 유지" % [k.substr(11), _n(c[2])])
				elif k == "floors":
					parts.append("%d층 받침이 오름" % int(c[2]))
				else:
					parts.append("%s %s %s" % [k, c[1], c[2]])
	return " + ".join(parts) if not parts.is_empty() else "처음부터"


static func _next_step(sim: Sim, state: CityState) -> Dictionary:
	var done: Dictionary = state.flags.get("unlock_steps", {})
	var best := {}
	for id: String in sim.items("unlocks"):
		var u := sim.item("unlocks", id)
		if done.has(id):
			continue
		if best.is_empty() or int(u.get("order", 0)) < int(best.get("order", 0)):
			best = u.duplicate()
			best["id"] = id
	return best


static func _progress(sim: Sim, state: CityState, u: Dictionary) -> float:
	var m := Metrics.compute(sim, state)
	var p := 1.0
	for c: Variant in u.get("cond", []):
		if c is Array and c.size() == 3 and float(c[2]) > 0.0:
			p = minf(p, clampf(float(m.get(str(c[0]), 0.0)) / float(c[2]), 0.0, 1.0))
	return p


static func _hud(sim: Sim, state: CityState) -> Dictionary:
	var m := Metrics.compute(sim, state)
	var pop := {}
	for t: int in range(1, sim.max_tier() + 1):
		pop["t%d" % t] = int(m.get("pop.t%d" % t, 0))
	var z := state.floors_unlocked - 1
	var need := Cover.floor_need(sim)
	var nx := _next_step(sim, state)
	var goal := {"text": "", "progress": 1.0}
	if not nx.is_empty():
		var names: Array = []
		for b: String in nx.get("unlocks", []):
			names.append(sim.bdef(b).get("name", b))
		goal = {"text": "%s → %s" % [cond_text(sim, nx.get("cond", [])), ", ".join(names) if not names.is_empty() else str(nx.get("grade_name", ""))],
			"progress": snappedf(_progress(sim, state, nx), 0.01)}
	var h := {"day": state.day, "hour": state.hour, "money": state.money, "net_per_day": 0.0, "pop_total": state.population(), "pop": pop,
		"happiness": snappedf(state.happiness, 0.1), "title": state.identity.get("title", "방백"), "grade_name": state.identity.get("grade_name", "공터"),
		"floors_unlocked": state.floors_unlocked,
		"floor_progress": _floor_progress(sim, state, z, need),
		"water": {"supply": 0.0, "demand": 0.0}, "power": {"supply": 0.0, "demand": 0.0}, "labor": [], "alerts": [],
		"teams_done": 0, "teams_idle": 0, "contracts_failed": 0, "next_goal": goal, "tutorial": int(state.flags.get("tutorial", 0)),
		"heat": snappedf(state.heat, 0.1), "grid": {"w": sim.W, "h": sim.H, "floors": sim.F}, "speed": 1, "paused": false,
		"signals": [], "hazards": {"fire": {"on": false, "burning": 0, "burnt": 0, "covered_pct": 0.0}, "disease": {"on": false, "sick_houses": 0, "covered_pct": 0.0}}}
	var sk := "%d:%d:%d:%d" % [state.get_instance_id(), roundi(state.econ_days / sim.step_days), state.layout_rev(), state.next_id]
	if sk != str(sim.cover_cache.get("_sig_key", "")):
		sim.cover_cache["_sig"] = Board.signals(sim, state)
		sim.cover_cache["_sig_key"] = sk
	h["signals"] = sim.cover_cache["_sig"]
	var tl: Array = []
	for t: int in range(1, sim.max_tier() + 1):
		tl.append({"tier": t, "name": sim.tname(t), "pop": int(pop["t%d" % t])})
	h["tiers"] = tl
	var wait := 0
	for t: Variant in state.waiting:
		wait += int(state.waiting[t].get("count", 0))
	if wait > 0:
		h["alerts"].append({"id": "waiting", "text": "빈집을 기다리는 주민 %d명" % wait, "tone": "warn", "jump": {"screen": "build", "arg": "house"}})
	var up := 0
	for b: Dictionary in state.buildings.values():
		if b["kind"] == "house" and b.get("upgradable", false):
			up += 1
	if up > 0:
		h["alerts"].append({"id": "upgradable", "text": "승급할 수 있는 주거 %d채" % up, "tone": "good", "jump": {"screen": "upgrade", "arg": ""}})
	return h


## G2: 층 진행 + 문장.
static func _arriving_text(b: Dictionary) -> String:
	var res := int(b.get("residents", 0))
	var tgt := int(b.get("target", 0))
	if str(b.get("burn", "")) != "":
		return "불에 타 아무도 살 수 없다"
	if res < tgt:
		return "%d명이 짐을 들고 오는 중(%d/%d) — 행복할수록 빨리 온다" % [tgt - res, res, tgt]
	if res < int(b.get("cap", 0)):
		return "수요가 채워지면 더 들어온다(%d/%d)" % [res, int(b.get("cap", 0))]
	return "만실"


static func _floor_progress(sim: Sim, state: CityState, z: int, need: int) -> Dictionary:
	var used := Cover.used_cells_fast(sim, state, z)
	var text := ""
	if state.floors_unlocked >= sim.F:
		text = "받침이 모두 올랐다"
	elif used >= need:
		text = "%d층 받침이 곧 오른다" % (z + 2)
	else:
		text = "%d층 받침까지 %d층에 쓰이는 칸 %d개 더(빈집 제외)" % [z + 2, z + 1, need - used]
	return {"z": z, "used": used, "need": need, "text": text}


static func _effect_text(sim: Sim, d: Dictionary) -> String:
	var parts: Array = []
	var rec: Dictionary = d.get("recipe", {})
	if not rec.is_empty():
		var a: Array = []
		for g: String in rec.get("in", {}):
			a.append("%s %s" % [sim.gname(g), _n(rec["in"][g])])
		var b: Array = []
		for g: String in rec.get("out", {}):
			b.append("%s %s" % [sim.gname(g), _n(rec["out"][g])])
		parts.append(("%s → %s /일" % [", ".join(a), ", ".join(b)]) if not a.is_empty() else ("%s /일" % ", ".join(b)))
	for u: String in d.get("supply", {}):
		parts.append("%s +%s/일" % ["물" if u == "water" else "전기", _n(d["supply"][u])])
	var rg := Cover.rng_of(d)
	if d.has("market"):
		parts.append("%d등급 이하 상품 취급, %s" % [int(d["market"]), Cover.range_text(rg)])
	elif d.has("services"):
		parts.append("범위 %s" % Cover.range_text(rg))
	if float(d.get("water", 0)) > 0:
		parts.append("물 %s/일 사용" % _n(d["water"]))
	if float(d.get("power", 0)) > 0:
		parts.append("전기 %s 필요" % _n(d["power"]))
	if d.get("storage", false):
		parts.append("상품마다 저장 한도 +%d(소비재·원료) / +%d(건축자재)" % [int(sim.cfg("storage.goods_per_warehouse", 300)), int(sim.cfg("storage.material_per_warehouse", 200))])
	if d.has("contract_slots"):
		parts.append("계약 자리 +%d" % int(d["contract_slots"]))
	if d.has("vice"):
		parts.append("층세 %s/일" % Sim.won(float(d["vice"].get("income", 0))))
	if "noise" in d.get("tags", []):
		parts.append("시끄럽다(옆 칸 주거 행복 −)")
	if d.get("open_sky", false) or d.get("needs_sky", false):
		parts.append("위가 뚫린 자리만(위에 지으면 멈춤)")
	if int(d.get("min_floor", 0)) > 0:
		parts.append("%d층 이상" % (int(d["min_floor"]) + 1))
	return " · ".join(parts)


const CAUSE_TEXT := {"": "가동 중", "staff": "인력 부족", "input": "원료 부족", "water": "물 부족", "power": "전기 부족",
	"money": "돈이 없어 멈춤", "storage": "창고가 가득", "paused": "일시 정지", "raid": "바깥의 시선으로 폐쇄", "sky": "위가 막혀 해가 안 듦",
	"fire": "불이 났다", "burnt": "타 버림 — 수리 필요", "repair": "수리 중"}


## 경제일 → "0.4일(약 4분)"처럼 ×1 실제 시간과 함께.
static func day_text(days: float) -> String:
	var mins := days * 10.0
	if days >= 1.0:
		return "%.1f일" % days
	return "%.1f일(×1로 약 %d분)" % [days, maxi(1, int(roundf(mins)))]


static func _n(x: Variant) -> String:
	var f := float(x)
	return str(int(f)) if f == floorf(f) else str(snappedf(f, 0.01))


static func _wf(sim: Sim, wf: Dictionary) -> Array:
	var out: Array = []
	for tk: String in wf:
		out.append({"tier": int(tk.substr(1)), "name": sim.tname(int(tk.substr(1))), "n": int(wf[tk])})
	return out


static func _lock_hint(sim: Sim, id: String) -> String:
	for uid: String in sim.items("unlocks"):
		var u := sim.item("unlocks", uid)
		if id in u.get("unlocks", []):
			return cond_text(sim, u.get("cond", []))
	return ""


static func _build_menu(sim: Sim, state: CityState) -> Array:
	var cats: Dictionary = sim.db.get("buildings", {}).get("cats", {})
	var out: Array = []
	var by := {}
	var house_cost := float(sim.cfg("zone.shack_cost", 5))
	var hl := not sim.is_unlocked(state, "house")
	by["house"] = [{"id": "house", "name": "주거 구역", "desc": "칠한 칸마다 판잣집이 선다(1칸 = 1주거, %s %d명)." % [sim.tname(1), int(sim.tier(1).get("cap", 4))],
		"sign": "집", "size": 1, "footprint": [1, 1], "floors": 1, "rotatable": false, "build_days": 0.0, "needs_sky": false, "min_floor": 0,
		"look": "house", "cost": {"money": house_cost, "goods": {}}, "workforce": [], "upkeep": 0, "range": null,
		"effect_text": "주민이 살며 세금을 낸다(판잣집은 바로 서고 주민은 조금씩 들어온다)", "locked": hl, "lock_hint": "", "affordable": state.money >= house_cost}]
	for id: String in sim.items("buildings"):
		var d := sim.bdef(id)
		var c := str(d.get("cat", "infra"))
		if not by.has(c):
			by[c] = []
		var locked := not sim.is_unlocked(state, id)
		var hint := ""
		if locked:
			hint = _lock_hint(sim, id)
		elif d.has("blueprint") and not state.flags.get("blueprints", {}).has(str(d["blueprint"])):
			locked = true
			hint = "도면 필요(회색 띠)"
		var cost: Dictionary = d.get("cost", {})
		var aff := state.money + 1e-9 >= float(cost.get("money", 0))
		for g: String in cost.get("goods", {}):
			aff = aff and float(state.stock.get(g, 0.0)) + 1e-9 >= float(cost["goods"][g])
		var k := sim.fp(id)
		var rg := Cover.rng_of(d)
		by[c].append({"id": id, "name": d.get("name", id), "desc": d.get("desc", ""), "sign": d.get("sign", ""), "size": maxi(k.x, k.y),
			"footprint": [k.x, k.y], "floors": k.z, "rotatable": k.x != k.y, "build_days": snappedf(sim.build_days(id), 0.01),
			"needs_sky": bool(d.get("needs_sky", d.get("open_sky", false))), "min_floor": int(d.get("min_floor", 0)), "look": str(d.get("look", "")),
			"cost": {"money": float(cost.get("money", 0)), "goods": cost.get("goods", {})}, "workforce": _wf(sim, d.get("workforce", {})),
			"upkeep": float(d.get("upkeep", 0)), "range": null if rg.is_empty() else rg, "range_text": Cover.range_text(rg) if not rg.is_empty() else "",
			"effect_text": _effect_text(sim, d), "locked": locked, "lock_hint": hint, "affordable": aff})
	for c: String in ["house"] + cats.keys():
		if by.has(c) and not (c == "house" and out.size() > 0):
			out.append({"cat": c, "cat_name": cats.get(c, "주거"), "items": by[c]})
	return out


static func _info(sim: Sim, state: CityState, args: Dictionary) -> Dictionary:
	var b: Dictionary = {}
	var pos: Variant = args.get("pos", null)
	if args.has("bid"):
		b = state.buildings.get(int(args["bid"]), {})
	elif pos is Vector3i and state.cells.has(pos):
		b = state.buildings.get(int(state.cells[pos]["bid"]), {})
	if b.is_empty():
		if pos is Vector3i and state.supports.has(pos):
			return {"kind": "support", "title": "골조", "lines": ["위층을 받치는 골조. 이 칸에도 지을 수 있다."]}
		return {"kind": "empty", "title": "빈 칸", "lines": ["%d층" % ((pos.z if pos is Vector3i else 0) + 1)]}
	var bid := int(b["id"])
	if b["kind"] == "house":
		var t := int(b["tier"])
		var mn: Dictionary = sim.db.get("upgrade_costs", {}).get("material_names", {})
		return {"bid": bid, "kind": "house", "pos": b["pos"], "title": "%s의 집" % sim.tname(t), "tier": t, "tier_name": sim.tname(t),
			"material": b["material"], "material_name": mn.get(b["material"], b["material"]), "residents": int(b["residents"]), "cap": int(b["cap"]),
			"target": int(b.get("target", 0)), "happiness": snappedf(float(b.get("happiness", 50)), 0.1), "tax_per_day": snappedf(float(b.get("tax", 0)), 0.01),
			"need_state": b["need_state"], "upgradable": b["upgradable"], "scaffold": b.get("upgrading") != null, "needs": [], "upgrade": {},
			"arriving": snappedf(float(b.get("arriving", 0.0)), 0.01), "arriving_text": _arriving_text(b),
			"burn": str(b.get("burn", "")), "sick": bool(b.get("sick", false)), "repair": {"ok": false, "cost_text": "", "days": 0.0}}
	var d := sim.bdef(str(b["type"]))
	if b["kind"] == "site":
		var left := float(b.get("build_left", 0.0))
		return {"bid": bid, "kind": "site", "pos": b["pos"], "title": "공사 중 — %s" % d.get("name", b["type"]), "type": b["type"],
			"w": int(b.get("w", 1)), "h": int(b.get("h", 1)), "d": int(b.get("d", 1)), "rot": int(b.get("rot", 0)), "footprint": Cover.bcells(b),
			"progress": snappedf(float(b["progress"]), 0.01), "build_progress": snappedf(float(b["progress"]), 0.01), "build_left_text": "완공까지 %s" % day_text(left),
			"lines": ["대나무 비계가 올라가는 중 (%d%%) — 완공까지 %s" % [int(float(b["progress"]) * 100.0), day_text(left)]],
			"actions": [{"id": "demolish", "label": "공사 취소(환불 없음)", "enabled": true, "reason": ""}]}
	var staff_lines: Array = []
	for w: Dictionary in _wf(sim, d.get("workforce", {})):
		staff_lines.append("%s %d명 필요" % [w["name"], w["n"]])
	var io: Array = []
	var eff := float(b.get("eff", 0.0))
	var rec: Dictionary = d.get("recipe", {})
	for g: String in rec.get("in", {}):
		io.append("들어감: %s %s/일 (지금 %s)" % [sim.gname(g), _n(rec["in"][g]), _n(snappedf(float(rec["in"][g]) * eff, 0.1))])
	for g: String in rec.get("out", {}):
		io.append("나옴: %s %s/일 (지금 %s)" % [sim.gname(g), _n(rec["out"][g]), _n(snappedf(float(rec["out"][g]) * eff, 0.1))])
	for u: String in d.get("supply", {}):
		io.append("%s 공급 %s/일 (지금 %s)" % ["물" if u == "water" else "전기", _n(d["supply"][u]), _n(snappedf(float(d["supply"][u]) * eff, 0.1))])
	if d.has("vice"):
		# 단속 위험: 기본값 + "지금"(가동률 × 정책 heat.gain 반영 — vice 질의의 heat_per_day와 같은 값)
		var hn := snappedf(float(d["vice"].get("heat", 0.0)) * float(b.get("eff", 0.0)) * maxf(0.0, sim.mod(state, "heat.gain")), 0.1)
		io.append("층세 %s/일 (지금 %s) · 바깥의 시선 +%s/일 (지금 +%s)" % [Sim.won(float(d["vice"].get("income", 0))), Sim.won(float(b.get("vice_rate", 0.0))), _n(d["vice"].get("heat", 0)), _n(hn)])
	var cause := str(b.get("cause", ""))
	var ct: String = CAUSE_TEXT.get(cause, cause)
	var served := int(sim.cover(state).get("served", {}).get(bid, 0))
	var k := Cover.dims(b)
	var rg := Cover.rng_of(d)
	return {"bid": bid, "kind": "facility", "pos": b["pos"], "size": maxi(k.x, k.y), "footprint": Cover.bcells(b),
		"w": k.x, "h": k.y, "d": k.z, "rot": int(b.get("rot", 0)), "look": str(d.get("look", "")),
		"build_left_text": "", "build_progress": 1.0, "front": int(b.get("front", int(b.get("rot", 0)))), "range_text": Cover.range_text(rg) if not rg.is_empty() else "",
		"interior": {"staff_ratio": snappedf(sim.staff_of(b), 0.01), "active": bool(b.get("active", false))},
		"burn": str(b.get("burn", "")),
		"title": d.get("name", b["type"]), "type": b["type"], "desc": d.get("desc", ""), "sign": d.get("sign", ""),
		"active": b.get("active", false), "paused": b.get("paused", false),
		"staff": {"ratio": snappedf(sim.staff_of(b), 0.01), "lines": staff_lines}, "io_lines": io, "eff": snappedf(eff, 0.01),
		"cause": cause, "cause_text": ct, "upkeep": float(d.get("upkeep", 0)), "range": null if rg.is_empty() else rg, "served_houses": served,
		"actions": [{"id": "pause", "label": "다시 돌리기" if b.get("paused", false) else "일시 정지", "enabled": true, "reason": ""},
			{"id": "demolish", "label": "철거(환불 없음)", "enabled": true, "reason": ""}]}


static func _economy(sim: Sim, state: CityState) -> Dictionary:
	var cats: Dictionary = sim.db.get("goods", {}).get("cats", {})
	var rows: Array = []
	for g: String in sim.items("goods"):
		var gd := sim.good(g)
		var f: Dictionary = state.flow.get(g, {})
		var st := float(state.stock.get(g, 0.0))
		var prod := float(f.get("prod", 0.0))
		var cons := float(f.get("cons", 0.0))
		var imp := float(f.get("imp", 0.0))
		var exp := float(f.get("exp", 0.0))
		var net := prod + imp - cons - exp
		var cap := sim.cap_of(state, g)
		var days_left := -1.0
		if net < -1e-6:
			days_left = snappedf(st / -net, 0.1)
		var s := "ok"
		if st >= cap - 0.5:
			s = "full"
		elif st < 0.5 and cons > 0.01:
			s = "out"
		elif days_left >= 0.0 and days_left < 1.0:
			s = "low"
		rows.append({"id": g, "name": gd.get("name", g), "cat": gd.get("cat", ""), "cat_name": cats.get(gd.get("cat", ""), ""),
			"stock": snappedf(st, 0.1), "cap": cap, "prod": snappedf(prod, 0.1), "cons": snappedf(cons, 0.1), "imp": snappedf(imp, 0.1),
			"exp": snappedf(exp, 0.1), "net": snappedf(net, 0.1), "days_left": days_left, "state": s})
	var m := Metrics.compute(sim, state)
	var tiers: Array = []
	for t: int in range(1, sim.max_tier() + 1):
		var up := 0
		for b: Dictionary in state.buildings.values():
			if b["kind"] == "house" and int(b["tier"]) == t and b.get("upgradable", false):
				up += 1
		tiers.append({"tier": t, "name": sim.tname(t), "pop": int(m.get("pop.t%d" % t, 0)), "houses": int(m.get("houses.t%d" % t, 0)),
			"full_houses": int(m.get("full.t%d" % t, 0)), "upgradable": up})
	return {"goods": rows, "labor": [], "utilities": [], "finance": {"today": {}, "avg": {}, "lines": [], "net": 0.0}, "tiers": tiers}


static func _goals(sim: Sim, state: CityState) -> Dictionary:
	var done: Dictionary = state.flags.get("unlock_steps", {})
	var steps: Array = []
	var ids: Array = sim.items("unlocks").keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(sim.item("unlocks", a).get("order", 0)) < int(sim.item("unlocks", b).get("order", 0)))
	for id: String in ids:
		var u := sim.item("unlocks", id)
		if int(u.get("order", 0)) == 0:
			continue
		var rw: Array = []
		for b: String in u.get("unlocks", []):
			rw.append(str(sim.bdef(b).get("name", b)))
		if u.has("grade_name"):
			rw.append("성채 등급: " + str(u["grade_name"]))
		steps.append({"id": id, "text": cond_text(sim, u.get("cond", [])), "done": done.has(id),
			"progress": 1.0 if done.has(id) else snappedf(_progress(sim, state, u), 0.01), "rewards": rw})
	return {"grade": state.milestone, "grade_name": state.identity.get("grade_name", ""), "title": state.identity.get("title", ""), "steps": steps}
