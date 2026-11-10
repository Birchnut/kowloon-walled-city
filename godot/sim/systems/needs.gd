extends SimSystem
## needs — 주민과 수요(GDD §3.1–3.3). 매 스텝 주거마다:
##  1) 수요별로 무엇을 쓸지 고른다(대체 묶음 = sticky: 끊기기 전까지 바꾸지 않는다, prefer 표시 유틸리티는 넉넉하면 갈아탄다).
##  2) 상품 수요: 도시 재고 + 범위 안에 "그 등급을 취급하는 가동 중 시장". 도시 전체 수요를 먼저 모은 뒤
##     재고/수요 비율로 공평하게 나눠 소비한다(시장 여러 개가 겹쳐도 한 번만, 시장별 물량 상한 없음, 재고는 0 밑으로 안 감).
##     서비스 수요: 범위 안 가동 중 서비스 시설. 물·전기: 도시 주민 몫 비율(utilities의 res_ratio).
##  3) 목표 인원 = Σ 기본 수요 몫 × 충족도. 모자라면 들어오고(행복이 높을수록 빨리), 넘치면 유예(3경제일, 수요별) 뒤 천천히 떠난다.
##  4) 행복 = 기본 + 여유 수요 충족 − 기본 부족 − 옆 칸 소음. 세수 = 주민 × 세율 × (1 + 승급·여유 보너스) × 행복 배수.
## 수치: needs.json, tiers.json, config population.*.
## 끄면: 주민이 들고 나지 않고 소비·세수 계산도 멈춘다(세수 0).

var by_tier: Dictionary = {}   # tier int -> [need def + "id", 옵션은 key/kind 붙임]
var _ok := 0.9
var _spare: Dictionary = {}    # 이번 스텝에 prefer 유틸리티로 갈아탈 수 있는 남는 공급


func setup(s: Sim) -> void:
	super.setup(s)
	_ok = float(sim.cfg("population.ok_ratio", 0.9))
	by_tier.clear()
	for id: String in sim.items("needs"):
		var n: Dictionary = sim.item("needs", id).duplicate(true)
		n["id"] = id
		var opts: Array = []
		for o: Dictionary in n.get("options", []):
			var oo := o.duplicate()
			if o.has("good"):
				oo["key"] = str(o["good"])
				oo["kind"] = "good"
			elif o.has("service"):
				oo["key"] = "svc:" + str(o["service"])
				oo["kind"] = "service"
			elif o.has("utility"):
				oo["key"] = "@" + str(o["utility"])
				oo["kind"] = "utility"
			else:
				oo["key"] = "mkt:%d" % int(o["market"])
				oo["kind"] = "market"
			opts.append(oo)
		n["options"] = opts
		var t := int(n["tier"])
		if not by_tier.has(t):
			by_tier[t] = []
		by_tier[t].append(n)


# ------------------------------------------------------------------ 접근 판정
## 시장: 이 주거에서 grade 이상을 취급하는 가동 시장이 있나. 반환 "" | range | grade | staff | power
func _market_cause(state: CityState, mk: Array, grade: int) -> String:
	if mk.is_empty():
		return "range"
	var any_grade := false
	var cause := "staff"
	for fb: int in mk:
		var f: Dictionary = state.buildings.get(fb, {})
		if f.is_empty() or int(sim.bdef(str(f["type"])).get("market", 0)) < grade:
			continue
		any_grade = true
		if f.get("active", false):
			return ""
		cause = "power" if str(f.get("cause", "")) == "power" else "staff"
	return cause if any_grade else "grade"


func _service_cause(state: CityState, sv: Dictionary, tag: String) -> String:
	var lst: Array = sv.get(tag, [])
	if lst.is_empty():
		return "range"
	var cause := "staff"
	for fb: int in lst:
		var f: Dictionary = state.buildings.get(fb, {})
		if f.get("active", false):
			return ""
		if str(f.get("cause", "")) == "power":
			cause = "power"
	return cause


func _util_ratio(state: CityState, u: String) -> float:
	if not state.util.has(u):
		return 1.0      # utilities 시스템이 꺼져 있음 = 늘 충분
	if float(state.util[u].get("supply", 0.0)) <= 1e-9:
		return 0.0
	return float(state.util[u].get("res_ratio", 1.0))


## 옵션 하나를 지금 쓸 수 있나. 반환 [cause, ratio_hint]
func _avail(state: CityState, o: Dictionary, mk: Array, sv: Dictionary) -> String:
	match str(o["kind"]):
		"good":
			var c := _market_cause(state, mk, int(sim.good(o["good"]).get("grade", 1)))
			if c != "":
				return c
			return "" if float(state.stock.get(o["good"], 0.0)) > 1e-9 else "stock"
		"service":
			return _service_cause(state, sv, str(o["service"]))
		"market":
			return _market_cause(state, mk, int(o["market"]))
		"utility":
			var u := str(o["utility"])
			return "" if _util_ratio(state, u) >= 0.5 else u
	return "range"


## 지금 고른 상품 o보다 넉넉한(지난 스텝 공급률 ≥ ok, 재고 있음, 접근 가능) 대체품이 있나.
func _has_better(state: CityState, opts: Array, o: Dictionary, mk: Array, sv: Dictionary, fills: Dictionary) -> bool:
	for a: Dictionary in opts:
		if a != o and a["kind"] == "good" and float(fills.get(a["good"], 1.0)) >= _ok and _avail(state, a, mk, sv) == "":
			return true
	return false


func _pick(state: CityState, n: Dictionary, rec: Dictionary, mk: Array, sv: Dictionary, r: float) -> Array:
	var count := int(n.get("count", 1))
	var opts: Array = n["options"]
	if opts.size() <= count:
		return opts
	var by_key := {}
	for o: Dictionary in opts:
		by_key[o["key"]] = o
	var keep: Array = []
	var failed: Array = []
	var fills: Dictionary = state.flags.get("fill", {})
	for k: String in str(rec.get("pick", "")).split(",", false):
		if by_key.has(k):
			var o: Dictionary = by_key[k]
			var bad := _avail(state, o, mk, sv) != ""
			# 재고가 조금씩만 들어와 매 스텝 바닥나는 상품(지난 스텝 공급률 < ok)도 끊긴 것으로 본다 — 넉넉한 대체품이 있으면 갈아탄다
			if not bad and o["kind"] == "good" and float(fills.get(o["good"], 1.0)) < _ok:
				bad = _has_better(state, opts, o, mk, sv, fills)
			if not bad:
				keep.append(o)
			else:
				failed.append(o)
	for o: Dictionary in opts:
		if o.get("prefer", false) and not (o in keep) and _avail(state, o, mk, sv) == "":
			if o["kind"] == "utility":
				var u := str(o["utility"])
				var need := r * float(o.get("amount", 0.0))
				if _util_ratio(state, u) < _ok or float(_spare.get(u, 0.0)) < need:
					continue
				_spare[u] = float(_spare.get(u, 0.0)) - need
			keep.push_front(o)
	# 새로 고를 때는 재고가 가장 많은 상품부터(같은 묶음 안에서 소비가 한 품목에 몰리지 않게)
	var cand: Array = []
	for o: Dictionary in opts:
		if not (o in keep) and not (o in failed) and not (o.get("prefer", false) and o["kind"] == "utility") and _avail(state, o, mk, sv) == "" \
				and (o["kind"] != "good" or float(fills.get(o["good"], 1.0)) >= _ok):
			cand.append(o)
	if cand.size() > 1:
		cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (float(state.stock.get(a.get("good", ""), 0.0)) if a["kind"] == "good" else 0.0) > (float(state.stock.get(b.get("good", ""), 0.0)) if b["kind"] == "good" else 0.0))
	for o: Dictionary in cand:
		if keep.size() >= count:
			break
		keep.append(o)
	for o: Dictionary in opts:
		if keep.size() >= count:
			break
		if not (o in keep) and not (o in failed) and not (o.get("prefer", false) and o["kind"] == "utility") and _avail(state, o, mk, sv) == "":
			keep.append(o)
	for o: Dictionary in failed + opts:
		if keep.size() >= count:
			break
		if not (o in keep):
			keep.append(o)
	return keep.slice(0, count)


# ------------------------------------------------------------------ 틱
func tick(state: CityState, dt: float) -> void:
	var cov := sim.cover(state)
	var demand := {}
	var work: Array = []
	_spare.clear()
	for u: String in state.util:
		_spare[u] = float(state.util[u].get("supply", 0.0)) - float(state.util[u].get("demand", 0.0))
	# 1단계: 고르기 + 도시 수요 합산
	for b: Dictionary in state.buildings.values():
		if b["kind"] != "house":
			continue
		var hb := int(b["id"])
		var mk: Array = cov["markets"].get(hb, [])
		var sv: Dictionary = cov["services"].get(hb, {})
		var r := float(b["residents"])
		var rows: Array = []
		var extra := {}
		for n: Dictionary in by_tier.get(int(b["tier"]), []):
			var rec: Dictionary = b["needs"].get(n["id"], {"ratio": 0.0, "short_days": 0.0, "pick": ""})
			b["needs"][n["id"]] = rec
			var picks := _pick(state, n, rec, mk, sv, r)
			var keys: Array = []
			var causes: Array = []
			var per := float(n.get("amount", 0.0)) / float(maxi(1, int(n.get("count", 1))))
			for o: Dictionary in picks:
				keys.append(o["key"])
				var c := _avail(state, o, mk, sv)
				causes.append(c)
				if o["kind"] == "good" and c == "" and r > 0.0:
					demand[o["good"]] = float(demand.get(o["good"], 0.0)) + r * per * dt
				if o["kind"] == "utility" and o.has("amount"):
					extra[o["utility"]] = float(extra.get(o["utility"], 0.0)) + float(o["amount"])
			rec["pick"] = ",".join(keys)
			rows.append([n, rec, picks, causes])
		b["util_extra"] = extra
		work.append([b, rows])
	# 재고/수요 비율로 공평하게 나눠 소비
	var fill := {}
	var fills_saved := {}
	for g: String in demand:
		var dmd: float = demand[g]
		var have := float(state.stock.get(g, 0.0))
		var f := 1.0 if have >= dmd else have / dmd
		fill[g] = f
		fills_saved[g] = snappedf(f, 0.0001)
		var used := dmd * f
		state.stock[g] = maxf(0.0, have - used)
		sim.flow_add(g, "cons", used)
		state.stat_add("cons." + g, used)
	state.flags["fill"] = fills_saved
	# 2단계: 충족도 · 인원 · 행복 · 세수
	var P := "population."
	var grace := float(sim.cfg(P + "grace_days", 3))
	var rec_mult := float(sim.cfg(P + "short_recover_mult", 2.0))
	var mi := float(sim.cfg(P + "move_in_per_day", 8))
	var mo := float(sim.cfg(P + "move_out_per_day", 2))
	var hap_sum := 0.0
	var hap_w := 0.0
	for wk: Array in work:
		var b: Dictionary = wk[0]
		var t := int(b["tier"])
		var td := sim.tier(t)
		var target_f := 0.0
		var adv_met := 0
		var lux_met := 0
		var basic_short := 0
		var any_unmet := false
		var bad := false
		var adv_all := true
		var basic_all := true
		for row: Array in wk[1]:
			var n: Dictionary = row[0]
			var rec: Dictionary = row[1]
			var picks: Array = row[2]
			var causes: Array = row[3]
			var count := maxi(1, int(n.get("count", 1)))
			var sum := 0.0
			var cause := ""
			for i: int in picks.size():
				var o: Dictionary = picks[i]
				var c: String = causes[i]
				var x := 0.0
				if c == "":
					match str(o["kind"]):
						"good":
							x = float(fill.get(o["good"], 1.0)) if float(b["residents"]) > 0.0 else 1.0
							if x < _ok:
								c = "stock"
						"utility":
							x = _util_ratio(state, str(o["utility"]))
							if x < _ok:
								c = str(o["utility"])
						_:
							x = 1.0
				if cause == "" and c != "":
					cause = c
				sum += x
			var ratio := clampf(sum / float(count), 0.0, 1.0)
			rec["ratio"] = ratio
			rec["cause"] = cause if ratio < _ok else ""
			var met := ratio >= _ok - 1e-9
			var role := str(n["role"])
			if role == "luxury":
				if met:
					lux_met += 1
				continue
			if met:
				rec["short_days"] = maxf(0.0, float(rec.get("short_days", 0.0)) - rec_mult * dt)
			else:
				rec["short_days"] = float(rec.get("short_days", 0.0)) + dt
				any_unmet = true
			if role == "basic":
				target_f += float(n.get("share", 0)) * clampf(ratio / _ok, 0.0, 1.0)
				if not met:
					basic_short += 1
					basic_all = false
					if float(rec["short_days"]) >= grace:
						bad = true
			else:
				if met:
					adv_met += 1
				else:
					adv_all = false
		var cap := int(b["cap"])
		var target := mini(cap, int(floorf(target_f + 1e-6)))
		b["target"] = target
		# 행복
		var hp := float(sim.cfg(P + "happiness_base", 50)) + float(lux_met) * float(sim.cfg(P + "happiness_per_luxury", 12)) \
			+ float(basic_short) * float(sim.cfg(P + "happiness_basic_short", -5)) \
			- float(cov["noise"].get(int(b["id"]), 0)) * float(sim.cfg(P + "noise_penalty", 6))
		hp = clampf(hp, 0.0, 100.0)
		b["happiness"] = hp
		# 입주·퇴거
		var old_res := int(b["residents"])
		var res := old_res
		if res < target:
			b["leave"] = 0.0
			b["grow"] = float(b.get("grow", 0.0)) + mi * (0.5 + hp / 100.0) * dt
			while float(b["grow"]) >= 1.0 and res < target:
				res += 1
				b["grow"] = float(b["grow"]) - 1.0
			if res >= target:
				b["grow"] = 0.0
		elif res > target and bad:
			b["grow"] = 0.0
			b["leave"] = float(b.get("leave", 0.0)) + mo * dt
			while float(b["leave"]) >= 1.0 and res > target:
				res -= 1
				b["leave"] = float(b["leave"]) - 1.0
		else:
			b["grow"] = 0.0
			b["leave"] = 0.0
		if res != old_res:
			b["residents"] = res
			if res > old_res:
				state.stat_add("arrived", float(res - old_res))
				if not state.stats.has("first_resident_day"):
					state.stats["first_resident_day"] = state.econ_days
			else:
				state.stat_add("left", float(old_res - res))
				var lt: Dictionary = state.flags.get("left_today", {})
				lt[str(t)] = int(lt.get(str(t), 0)) + (old_res - res)
				state.flags["left_today"] = lt
		# 세수(₩/경제일)
		var hm := lerpf(float(sim.cfg(P + "tax_mult_min", 0.85)), float(sim.cfg(P + "tax_mult_max", 1.15)), hp / 100.0)
		b["tax"] = float(res) * float(td.get("tax", 0.0)) * (1.0 + float(adv_met) * float(sim.cfg(P + "advance_tax_bonus", 0.1)) \
			+ float(lux_met) * float(sim.cfg(P + "luxury_tax_bonus", 0.15))) * hm
		hap_sum += hp * float(res)
		hap_w += float(res)
		var ns := "bad" if bad else ("warn" if any_unmet else "ok")
		var up: bool = t < sim.max_tier() and res >= cap and basic_all and adv_all and b.get("upgrading") == null \
			and not sim.item("upgrade_costs", "%dto%d" % [t, t + 1]).is_empty()
		if res != old_res or ns != str(b["need_state"]) or up != bool(b["upgradable"]):
			b["need_state"] = ns
			b["upgradable"] = up
			state.emit("building_changed", {"bid": int(b["id"])})
	state.happiness = hap_sum / hap_w if hap_w > 0.0 else 50.0


func on_day_end(state: CityState, ended: int) -> void:
	var lt: Dictionary = state.flags.get("left_today", {})
	for t: String in lt:
		sim.say(state, "%d일: 공급이 끊긴 채 유예가 지나 %s %d명이 성채를 떠났다." % [ended, sim.tname(int(t)), int(lt[t])], "warn")
	state.flags["left_today"] = {}


# ------------------------------------------------------------------ 표시
const CAUSE_TEXT := {"stock": "재고 없음", "range": "시장 범위 밖", "grade": "취급 등급 부족", "staff": "인력 부족",
	"water": "물 부족", "power": "전기 부족"}
const ROLE_NAME := {"basic": "기본", "advance": "승급 조건", "luxury": "여유"}


func _jump(n: Dictionary, rec: Dictionary) -> Dictionary:
	var c := str(rec.get("cause", ""))
	var first := str(rec.get("pick", "")).split(",", false)
	var key := first[0] if first.size() > 0 else ""
	match c:
		"stock":
			return {"screen": "economy", "arg": key}
		"staff":
			return {"screen": "economy", "arg": "labor"}
		"water", "power":
			return {"screen": "build", "arg": c}
		"range", "grade":
			for o: Dictionary in n["options"]:
				if o["key"] == key:
					return {"screen": "build", "arg": _supplier(o)}
			return {"screen": "build", "arg": ""}
	return {}


## 이 옵션을 채울 시설 id(짓기 화면 이동용).
func _supplier(o: Dictionary) -> String:
	var grade := 0
	if o["kind"] == "good":
		grade = int(sim.good(o["good"]).get("grade", 1))
	elif o["kind"] == "market":
		grade = int(o["market"])
	for id: String in sim.items("buildings"):
		var d := sim.bdef(id)
		if grade > 0 and int(d.get("market", 0)) == grade:
			return id
		if o["kind"] == "service" and str(o["service"]) in d.get("services", []):
			return id
	return ""


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name == "info" and out is Dictionary and out.get("kind", "") == "house":
		var b: Dictionary = state.buildings.get(int(out["bid"]), {})
		var rows: Array = []
		for n: Dictionary in by_tier.get(int(b.get("tier", 0)), []):
			var rec: Dictionary = b.get("needs", {}).get(n["id"], {})
			var ratio := float(rec.get("ratio", 0.0))
			var st := "ok" if ratio >= _ok else ("bad" if float(rec.get("short_days", 0.0)) >= float(sim.cfg("population.grace_days", 3)) and n["role"] == "basic" else "warn")
			if n["role"] == "luxury" and ratio < _ok:
				st = "off"
			var picks: Array = []
			for k: String in str(rec.get("pick", "")).split(",", false):
				picks.append(_opt_name(n, k))
			var c := str(rec.get("cause", ""))
			var ct := ""
			if c != "":
				ct = CAUSE_TEXT.get(c, c)
				if picks.size() > 0:
					ct = "%s — %s" % ["·".join(picks), ct]
			rows.append({"id": n["id"], "name": n.get("name", n["id"]), "role": n["role"], "role_name": ROLE_NAME[n["role"]],
				"ratio": snappedf(ratio, 0.01), "state": st, "cause": c, "cause_text": ct, "jump": _jump(n, rec),
				"using": "·".join(picks), "amount": float(n.get("amount", 0.0)), "share": int(n.get("share", 0))})
		out["needs"] = rows
	elif name == "hud":
		var bad := 0
		var warn := 0
		for b: Dictionary in state.buildings.values():
			if b["kind"] == "house":
				if b["need_state"] == "bad":
					bad += 1
				elif b["need_state"] == "warn" and int(b["residents"]) > 0:
					warn += 1
		if bad > 0:
			out["alerts"].append({"id": "needs_bad", "text": "주거 %d채가 공급 부족으로 주민을 잃고 있다" % bad, "tone": "bad", "jump": {"screen": "economy", "arg": ""}})
		elif warn > 0:
			out["alerts"].append({"id": "needs_warn", "text": "주거 %d채에 부족한 수요가 있다(유예 중)" % warn, "tone": "warn", "jump": {"screen": "economy", "arg": ""}})


func _opt_name(n: Dictionary, key: String) -> String:
	if key.begins_with("@"):
		return "물" if key == "@water" else "전기"
	if key.begins_with("svc:"):
		var tag := key.substr(4)
		for id: String in sim.items("buildings"):
			if tag in sim.bdef(id).get("services", []):
				return str(sim.bdef(id).get("name", tag))
		return tag
	if key.begins_with("mkt:"):
		return str(n.get("name", key))
	return sim.gname(key)
