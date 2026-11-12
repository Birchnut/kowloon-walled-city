class_name Validate
extends RefCounted
## Validate — 데이터를 읽을 때 검사한다. 오류는 한국어 문장 배열(비면 통과). Sim.setup이 부르고 시험이 확인한다.
## lock_check()는 "승급에 필요한 것을 만드는 시설이 그 승급 뒤에야 열리는" 순환 잠금을 정적으로 찾는다.

const ROLES := ["basic", "advance", "luxury"]
const UTILS := ["water", "power"]


static func _items(db: Dictionary, f: String) -> Dictionary:
	var r: Variant = db.get(f, {})
	return r.get("items", {}) if r is Dictionary else {}


static func check(db: Dictionary) -> Array:
	var e: Array = []
	for f: String in ["config", "tiers", "needs", "goods", "partners", "buildings", "upgrade_costs", "unlocks"]:
		if not db.has(f):
			e.append("데이터 파일이 없다: %s.json" % f)
	if not e.is_empty():
		return e
	var tiers := _items(db, "tiers")
	var goods := _items(db, "goods")
	var blds := _items(db, "buildings")
	var cfg: Dictionary = db["config"]
	# 계층
	var caps: Array = Sim.dig(cfg, "confirmed.tier_caps", [4, 8, 12, 8, 6])
	if tiers.size() != caps.size():
		e.append("계층 수가 %d이어야 한다(지금 %d)." % [caps.size(), tiers.size()])
	for i: int in caps.size():
		var t: Dictionary = tiers.get("t%d" % (i + 1), {})
		if t.is_empty():
			e.append("계층 t%d가 없다." % (i + 1))
		elif int(t.get("cap", 0)) != int(caps[i]):
			e.append("계층 t%d의 정원이 %d이어야 한다(확정 4-8-12-8-6). 지금 %d." % [i + 1, int(caps[i]), int(t.get("cap", 0))])
	# 서비스 태그·시장 등급
	var tags := {}
	var max_grade := 0
	var prio: Array = Sim.dig(cfg, "workforce.priority", [])
	var cats: Dictionary = db["buildings"].get("cats", {})
	for id: String in blds:
		var d: Dictionary = blds[id]
		for t: String in d.get("services", []):
			tags[t] = true
		if d.has("market"):
			max_grade = maxi(max_grade, int(d["market"]))
		if not (str(d.get("priority", "")) in prio):
			e.append("시설 %s의 priority '%s'가 config workforce.priority에 없다." % [id, d.get("priority", "")])
		if not cats.has(str(d.get("cat", ""))):
			e.append("시설 %s의 분류 '%s'가 buildings.cats에 없다." % [id, d.get("cat", "")])
		var fpv: Variant = d.get("footprint", [int(d.get("size", 1)), int(d.get("size", 1))])
		if not (fpv is Array) or (fpv as Array).size() != 2 or int(fpv[0]) < 1 or int(fpv[1]) < 1 or int(fpv[0]) > 4 or int(fpv[1]) > 4:
			e.append("시설 %s의 footprint는 [w, h](1~4)여야 한다." % id)
		if not (int(d.get("floors", 1)) in [1, 2]):
			e.append("시설 %s의 floors는 1 또는 2여야 한다." % id)
		var rgv: Variant = d.get("range", null)
		if rgv != null and not (rgv is Dictionary and (rgv as Dictionary).has("r")):
			e.append("시설 %s의 range는 {r, up, down}이어야 한다(v4 사각 범위)." % id)
		if str(d.get("sign", "")).length() > 4:
			e.append("시설 %s의 간판(sign)은 4자 이내여야 한다." % id)
		for fld: String in ["name", "sign", "desc"]:
			if _has_hanja(str(d.get(fld, ""))):
				e.append("시설 %s의 %s에 한자가 있다(한자 금지)." % [id, fld])
		for t: String in d.get("workforce", {}):
			if not tiers.has(t):
				e.append("시설 %s의 인력 계층 '%s'가 없다." % [id, t])
		var rec: Dictionary = d.get("recipe", {})
		for side: String in ["in", "out"]:
			for g: String in rec.get(side, {}):
				if not goods.has(g):
					e.append("시설 %s의 생산식에 없는 상품 '%s'." % [id, g])
		for g: String in d.get("cost", {}).get("goods", {}):
			if not goods.has(g):
				e.append("시설 %s의 건설 비용에 없는 상품 '%s'." % [id, g])
		for u: String in d.get("supply", {}):
			if not (u in UTILS):
				e.append("시설 %s의 공급 '%s'는 water/power만 된다." % [id, u])
	# 수요
	var share := {}
	for id: String in _items(db, "needs"):
		var n: Dictionary = _items(db, "needs")[id]
		var tk := "t%d" % int(n.get("tier", 0))
		if not tiers.has(tk):
			e.append("수요 %s의 계층이 없다." % id)
			continue
		if not (str(n.get("role", "")) in ROLES):
			e.append("수요 %s의 역할 '%s'는 basic/advance/luxury 중 하나여야 한다." % [id, n.get("role", "")])
		if n.get("role", "") == "basic":
			share[tk] = int(share.get(tk, 0)) + int(n.get("share", 0))
		var opts: Array = n.get("options", [])
		if opts.is_empty():
			e.append("수요 %s에 선택지가 없다." % id)
		if int(n.get("count", 1)) > opts.size():
			e.append("수요 %s: count(%d)가 선택지 수보다 크다." % [id, int(n.get("count", 1))])
		for o: Dictionary in opts:
			if o.has("good"):
				if not goods.has(o["good"]):
					e.append("수요 %s가 없는 상품 '%s'를 요구한다." % [id, o["good"]])
				elif str(goods[o["good"]].get("cat", "")) != "consumer" or not goods[o["good"]].has("grade"):
					e.append("수요 %s의 상품 '%s'는 등급 있는 소비재여야 한다." % [id, o["good"]])
				if float(n.get("amount", 0.0)) <= 0.0:
					e.append("수요 %s: 상품 수요는 amount > 0이어야 한다." % id)
			elif o.has("service"):
				if not tags.has(o["service"]):
					e.append("수요 %s의 서비스 '%s'를 주는 시설이 없다." % [id, o["service"]])
			elif o.has("utility"):
				if not (o["utility"] in UTILS):
					e.append("수요 %s의 유틸리티 '%s'는 water/power만 된다." % [id, o["utility"]])
			elif o.has("market"):
				if int(o["market"]) > max_grade:
					e.append("수요 %s의 시장 등급 %d을 주는 시장이 없다." % [id, int(o["market"])])
			else:
				e.append("수요 %s의 선택지 모양이 틀렸다(good/service/utility/market)." % id)
	for i: int in caps.size():
		var tk := "t%d" % (i + 1)
		if int(share.get(tk, 0)) != int(tiers.get(tk, {}).get("cap", -1)):
			e.append("계층 %s의 기본 수요 몫(share) 합 %d이 정원 %d과 같아야 한다." % [tk, int(share.get(tk, 0)), int(tiers.get(tk, {}).get("cap", -1))])
	# 승급 비용: 세 계열 자재는 하나의 qty를 공유
	var uc: Dictionary = db["upgrade_costs"]
	var fams: Array = []
	for g: String in goods:
		if goods[g].has("family"):
			fams.append(g)
	var mats: Array = uc.get("materials", [])
	if mats.size() != 3 or fams.size() != 3:
		e.append("승급 자재는 정확히 세 계열(목재·철제·콘크리트)이어야 한다.")
	for m: String in mats:
		if not (m in fams):
			e.append("승급 자재 '%s'는 family가 있는 상품이어야 한다." % m)
	for id: String in uc.get("items", {}):
		var u: Dictionary = uc["items"][id]
		if u.has("qty_by_material") or u.has("wood") or u.has("metal") or u.has("concrete"):
			e.append("승급 %s: 자재별 수량을 따로 쓰면 안 된다 — qty 하나만(세 계열 같은 수량, 확정)." % id)
		if int(u.get("qty", 0)) <= 0:
			e.append("승급 %s의 qty가 0보다 커야 한다." % id)
		if int(u.get("to", 0)) != int(u.get("from", 0)) + 1:
			e.append("승급 %s는 한 단계씩이어야 한다." % id)
		for g: String in u.get("extra", {}):
			if not goods.has(g):
				e.append("승급 %s의 추가 상품 '%s'가 없다." % [id, g])
	for t: int in range(1, caps.size()):
		if not uc.get("items", {}).has("%dto%d" % [t, t + 1]):
			e.append("승급 비용 %dto%d가 없다." % [t, t + 1])
	# 해금
	var seen := {}
	for id: String in _items(db, "unlocks"):
		for b: String in _items(db, "unlocks")[id].get("unlocks", []):
			if b != "house" and not blds.has(b):
				e.append("해금 %s가 없는 시설 '%s'를 연다." % [id, b])
			seen[b] = true
	for b: String in blds:
		if not seen.has(b):
			e.append("시설 %s는 어떤 해금 단계에도 없다(영영 못 짓는다)." % b)
	# 거래처
	var parts: Dictionary = db["partners"].get("partners", {})
	for id: String in _items(db, "partners"):
		var o: Dictionary = _items(db, "partners")[id]
		if not parts.has(str(o.get("partner", ""))):
			e.append("계약 제안 %s의 거래처가 없다." % id)
		if not goods.has(str(o.get("good", ""))):
			e.append("계약 제안 %s의 상품이 없다." % id)
		if not (str(o.get("dir", "")) in ["import", "export"]):
			e.append("계약 제안 %s의 방향은 import/export여야 한다." % id)
		if (o.get("sizes", []) as Array).is_empty():
			e.append("계약 제안 %s에 수량 단계가 없다." % id)
	for g: String in Sim.dig(cfg, "start.stock", {}):
		if not goods.has(g):
			e.append("시작 재고의 상품 '%s'가 없다." % g)
	e.append_array(check_b(db))
	if e.is_empty():
		e.append_array(lock_check(db))
	return e


## 파트 B 데이터(탐험·연구·정책) 검사. 파일이 없으면 그 시스템이 빈 모양으로 돈다.
static func check_b(db: Dictionary) -> Array:
	var e: Array = []
	var goods := _items(db, "goods")
	var partners: Dictionary = db.get("partners", {}).get("partners", {})
	var dests := _items(db, "destinations")
	var blds := _items(db, "buildings")
	for id: String in dests:
		var d: Dictionary = dests[id]
		if not (str(d.get("band", "")) in ["near", "mid", "far"]):
			e.append("목적지 %s의 band는 near/mid/far여야 한다." % id)
		if float(d.get("days", 0)) <= 0.0:
			e.append("목적지 %s의 days(게임 시계)가 0 이하다." % id)
		for g: String in d.get("stock", {}):
			if not goods.has(g):
				e.append("목적지 %s의 던전 재고에 없는 상품 '%s'." % [id, g])
		var pg := str(d.get("primary", {}).get("good", ""))
		if pg != "" and not goods.has(pg):
			e.append("목적지 %s의 주력 상품 '%s'가 없다." % [id, pg])
		if pg == "" and (d.get("picks", []) as Array).is_empty():
			e.append("목적지 %s에 주력 상품도 고를 자재도 없다." % id)
		for g: String in d.get("picks", []):
			if not goods.has(g):
				e.append("목적지 %s의 고를 자재 '%s'가 없다." % [id, g])
		for b: Dictionary in d.get("bonus", []):
			if not goods.has(str(b.get("good", ""))):
				e.append("목적지 %s의 덤 상품 '%s'가 없다." % [id, b.get("good", "")])
		for f: Dictionary in d.get("finds", []):
			if f.get("type", "") == "partner" and not partners.has(str(f.get("id", ""))):
				e.append("목적지 %s가 모르는 거래처 '%s'를 발견한다." % [id, f.get("id", "")])
		for r: String in d.get("reveals", []):
			if not dests.has(r):
				e.append("목적지 %s가 없는 목적지 '%s'를 알려 준다." % [id, r])
	for f: String in ["research", "policies"]:
		for id: String in _items(db, f):
			var it: Dictionary = _items(db, f)[id]
			if not (it.get("effects", {}) is Dictionary):
				e.append("%s %s의 effects는 {키: 비율}이어야 한다." % [f, id])
			for r: String in it.get("reveals", []):
				if not dests.has(r):
					e.append("%s %s가 없는 목적지 '%s'를 알려 준다." % [f, id, r])
			for b: String in it.get("unlocks", []):
				if not blds.has(b):
					e.append("%s %s가 없는 시설 '%s'를 연다." % [f, id, b])
	return e


static func _has_hanja(t: String) -> bool:
	for i: int in t.length():
		var c := t.unicode_at(i)
		if (c >= 0x4E00 and c <= 0x9FFF) or (c >= 0x3400 and c <= 0x4DBF) or (c >= 0xF900 and c <= 0xFAFF):
			return true
	return false


# ------------------------------------------------------------------ 순환 잠금 정적 검사
## 해금 단계의 "계층 문턱" = (tier, pop). start = (0, 0).
static func _step_level(u: Dictionary) -> Array:
	var lv := [0, 0.0]
	for c: Variant in u.get("cond", []):
		if c is Array and c.size() == 3 and str(c[0]).begins_with("pop.t"):
			var t := int(str(c[0]).substr(5))
			if t > lv[0] or (t == lv[0] and float(c[2]) > lv[1]):
				lv = [t, float(c[2])]
	return lv


## role 수요를 tier k에서 쓸 때 이 해금 수준이 그 전에 올 수 있나.
##  기본(k): 더 낮은 계층 문턱 또는 k계층 1명(첫 승급 직후). 승급(k): k계층까지의 문턱(기본 수요만으로 채워짐).
static func _avail(lv: Array, k: int, role: String) -> bool:
	if role == "basic":
		return lv[0] < k or (lv[0] == k and lv[1] <= 1.0)
	return lv[0] <= k


static func lock_check(db: Dictionary) -> Array:
	var e: Array = []
	var blds := _items(db, "buildings")
	var goods := _items(db, "goods")
	var level := {}
	for id: String in _items(db, "unlocks"):
		var u: Dictionary = _items(db, "unlocks")[id]
		for b: String in u.get("unlocks", []):
			level[b] = _step_level(u)
	var known_import := {}
	var parts: Dictionary = db["partners"].get("partners", {})
	for id: String in _items(db, "partners"):
		var o: Dictionary = _items(db, "partners")[id]
		if o.get("dir", "") == "import" and parts.get(o.get("partner", ""), {}).get("known", false):
			known_import[o["good"]] = true
	var ctx := {"blds": blds, "goods": goods, "level": level, "imp": known_import, "start": Sim.dig(db["config"], "start.stock", {})}
	for nid: String in _items(db, "needs"):
		var n: Dictionary = _items(db, "needs")[nid]
		var role := str(n.get("role", ""))
		if role == "luxury":
			continue
		var k := int(n.get("tier", 0))
		var ok_count := 0
		var why: Array = []
		for o: Dictionary in n.get("options", []):
			var r := _opt_ok(ctx, o, k, role)
			if r == "":
				ok_count += 1
			else:
				why.append(r)
		if ok_count < int(n.get("count", 1)):
			e.append("순환 잠금: %s(%s, 계층 %d)을(를) 그 전에 얻을 길이 없다 — %s" % [nid, n.get("name", ""), k, "; ".join(why)])
	for id: String in db["upgrade_costs"].get("items", {}):
		var u: Dictionary = db["upgrade_costs"]["items"][id]
		for g: String in u.get("extra", {}):
			var r := _good_ok(ctx, g, int(u["from"]), "advance", {})
			if r != "":
				e.append("순환 잠금: 승급 %s의 추가 상품 %s — %s" % [id, g, r])
	return e


static func _bld_ok(ctx: Dictionary, b: String, k: int, role: String) -> String:
	if not ctx["level"].has(b):
		return "%s는 해금되지 않는다" % b
	if not _avail(ctx["level"][b], k, role):
		return "%s는 계층 %d의 %s 수요보다 늦게 열린다" % [b, k, role]
	for t: String in ctx["blds"][b].get("workforce", {}):
		if int(t.substr(1)) > k:
			return "%s는 더 높은 계층(%s)의 인력이 필요하다" % [b, t]
	return ""


static func _good_ok(ctx: Dictionary, g: String, k: int, role: String, visiting: Dictionary) -> String:
	if ctx["imp"].has(g):
		return ""
	if visiting.has(g):
		return "%s 생산이 자기 자신을 필요로 한다" % g
	visiting[g] = true
	var last := "%s를 만드는 시설도, 아는 수입처도 없다" % g
	for b: String in ctx["blds"]:
		var d: Dictionary = ctx["blds"][b]
		if not d.get("recipe", {}).get("out", {}).has(g):
			continue
		var r := _bld_ok(ctx, b, k, role)
		if r == "":
			for gi: String in d["recipe"].get("in", {}):
				r = _good_ok(ctx, gi, k, role, visiting)
				if r != "":
					break
		if r == "":
			visiting.erase(g)
			return ""
		last = r
	visiting.erase(g)
	return last


static func _opt_ok(ctx: Dictionary, o: Dictionary, k: int, role: String) -> String:
	if o.has("good"):
		var r := _good_ok(ctx, o["good"], k, role, {})
		if r != "":
			return r
		return _opt_ok(ctx, {"market": int(ctx["goods"][o["good"]].get("grade", 1))}, k, role)
	var last := "공급하는 시설이 없다"
	for b: String in ctx["blds"]:
		var d: Dictionary = ctx["blds"][b]
		var fits := false
		if o.has("service"):
			fits = o["service"] in d.get("services", [])
		elif o.has("utility"):
			fits = d.get("supply", {}).has(o["utility"])
		elif o.has("market"):
			fits = int(d.get("market", 0)) >= int(o["market"])
		if fits:
			var r := _bld_ok(ctx, b, k, role)
			if r == "":
				return ""
			last = r
	return last
