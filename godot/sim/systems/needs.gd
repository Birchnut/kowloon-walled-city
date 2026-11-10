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
var _c: Dictionary = {}        # config population.* 캐시(setup에서)
var _has_up: Dictionary = {}   # tier -> 다음 승급 비용 데이터가 있나
const DEF := {"grace_days": 3.0, "short_recover_mult": 2.0, "move_in_per_day": 8.0, "move_out_per_day": 2.0, "happiness_base": 50.0,
	"happiness_per_luxury": 12.0, "happiness_basic_short": -5.0, "noise_penalty": 6.0, "tax_mult_min": 0.85, "tax_mult_max": 1.15,
	"advance_tax_bonus": 0.1, "luxury_tax_bonus": 0.15}
var _spare: Dictionary = {}    # 이번 스텝에 prefer 유틸리티로 갈아탈 수 있는 남는 공급


func setup(s: Sim) -> void:
	super.setup(s)
	_ok = float(sim.cfg("population.ok_ratio", 0.9))
	var P := "population."
	for k: String in ["grace_days", "short_recover_mult", "move_in_per_day", "move_out_per_day", "happiness_base", "happiness_per_luxury",
			"happiness_basic_short", "noise_penalty", "tax_mult_min", "tax_mult_max", "advance_tax_bonus", "luxury_tax_bonus"]:
		_c[k] = float(sim.cfg(P + k, DEF[k]))
	_has_up.clear()
	for t: int in range(1, sim.max_tier() + 1):
		_has_up[t] = not sim.item("upgrade_costs", "%dto%d" % [t, t + 1]).is_empty()
	_grades.clear()
	_tags.clear()
	for id: String in sim.items("buildings"):
		var d := sim.bdef(id)
		if d.has("market") and not (int(d["market"]) in _grades):
			_grades.append(int(d["market"]))
		for tg: String in d.get("services", []):
			if not (tg in _tags):
				_tags.append(tg)
	_grades.sort()
	_acc_key = ""
	_pents.clear()
	_pacc = -1
	_dems.clear()
	_dem_of.clear()
	_last_used.clear()
	_ngoods.clear()
	_gidx.clear()
	for id: String in sim.items("needs"):
		for o: Dictionary in sim.item("needs", id).get("options", []):
			if o.has("good") and not (str(o["good"]) in _ngoods):
				_gidx[str(o["good"])] = _ngoods.size()
				_ngoods.append(str(o["good"]))
	_uidx = {"water": _ngoods.size(), "power": _ngoods.size() + 1}
	_food.clear()
	for id: String in sim.items("needs"):
		if id.ends_with("_meal"):
			for o: Dictionary in sim.item("needs", id).get("options", []):
				if o.has("good"):
					_food[str(o["good"])] = true
	_mrev = ""
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
		var bk := {}
		for o: Dictionary in opts:
			bk[o["key"]] = o
		n["_by_key"] = bk
		for o: Dictionary in opts:
			if o["kind"] == "good":
				o["_mkey"] = "mkt:%d" % int(sim.good(o["good"]).get("grade", 1))
		for o: Dictionary in opts:
			if o.get("prefer", false):
				n["_has_prefer"] = true
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


## 옵션 하나를 지금 쓸 수 있나. 반환 cause("" = 된다).
## 1단계(고르기) 동안 재고·가동 상태가 안 바뀌므로 "덮임 등급"(cls) × 옵션 단위로 한 스텝 캐시한다.
var _av: Dictionary = {}       # 지금 계산 중인 접근 등급의 옵션별 결과
var _tab: Dictionary = {}      # 지금 계산 중인 접근 등급의 시장·서비스 원인표


func _avail(state: CityState, o: Dictionary) -> String:
	var kd: String = o["kind"]
	if kd == "good":
		_deps[_gidx[o["good"]]] = true
	elif kd == "utility":
		_deps[_uidx[o["utility"]]] = true
	var k: String = o["key"]
	if _av.has(k):
		return _av[k]
	var r := _avail_raw(state, o)
	_av[k] = r
	return r


func _avail_raw(state: CityState, o: Dictionary) -> String:
	match str(o["kind"]):
		"good":
			var c: String = _tab.get(o["_mkey"], "grade")
			if c != "":
				return c
			return "" if float(state.stock.get(o["good"], 0.0)) > 1e-9 else "stock"
		"service", "market":
			return _tab.get(o["key"], "range")
		"utility":
			var u := str(o["utility"])
			return "" if _util_ratio(state, u) >= 0.5 else u
	return "range"


## 접근 등급(acls): 덮임 등급(cls)마다 "시장 등급별·서비스별 원인"을 계산해 같은 것끼리 묶는다.
## 범위 시설의 가동 상태(active, 전기 원인)가 바뀌거나 배치가 바뀔 때만 다시 계산한다.
var _grades: Array = []
var _tags: Array = []
var _acc_key: String = ""
var _acc_sig: PackedByteArray = PackedByteArray()
var _acc_ver: int = 0
# 스텝을 넘어 재사용하는 묶음: 접근 등급 + "재고 있음/공급률 충분/물·전기 충분" 여부가 그대로일 때만.
var _pents: Dictionary = {}        # t*100000 + acls → {psig → Ent}
var _pacc: int = -1
var _last_used: Array = []
var _ngoods: Array = []            # 수요에 나오는 상품
var _pgen: int = 0                 # _pents를 비울 때마다 +1
var _stepno: int = 0
var _mrev: String = ""
var _food_k := 1.0                 # 수정치(연구·정책): 끼니 소비, 전체 소비, 행복 가산, 소음 배수, 세수, 입주
var _all_k := 1.0
var _hap_add := 0.0
var _noise_k := 1.0
var _tax_k := 1.0
var _movein_k := 1.0
var _food: Dictionary = {}         # 끼니 상품(수요 id가 _meal로 끝나는 수요의 상품)
var _env: PackedByteArray = PackedByteArray()   # 상품(재고 있음·공급률 충분) + 물·전기(0.5 이상·충분) 비트
var _gidx: Dictionary = {}
var _uidx: Dictionary = {}
var _deps: Dictionary = {}
var _dems: Array = []              # 서로 다른 소비 묶음(dem)
var _dem_of: Dictionary = {}
# 주거별(cover.houses 순서) 지난 스텝 기억 — 아무것도 안 변한 주거는 건너뛴다(결과는 같다).
var _cov_ref: Variant = null
var _hent: Array = []
var _hp2: Array = []
var _hres: PackedInt32Array = PackedInt32Array()
var _hset: PackedByteArray = PackedByteArray()
var _aff_last: Array = []
var _off_last := false
var _acls_of: PackedInt32Array = PackedInt32Array()   # cls → acls
var _acls_tab: Array = []                              # acls → {"mkt:g"/"svc:tag": cause}
var _acls_noise: PackedInt32Array = PackedInt32Array()


func _access(state: CityState, cov: Dictionary) -> void:
	var ranged: Array = cov["ranged"]
	var sig := PackedByteArray()
	sig.resize(ranged.size())
	for i: int in ranged.size():
		var f: Dictionary = ranged[i]
		sig[i] = (1 if f.get("active", false) else 0) + (2 if str(f.get("cause", "")) == "power" else 0)
	var key := "%d:%d" % [state.get_instance_id(), state.layout_rev()]
	if key == _acc_key and sig == _acc_sig:
		return
	_acc_key = key
	_acc_sig = sig
	_acc_ver += 1
	var cls_mk: Array = cov["cls_mk"]
	var cls_sv: Array = cov["cls_sv"]
	var cls_noise: Array = cov["cls_noise"]
	_acls_of.resize(cls_mk.size())
	_acls_tab.clear()
	_acls_noise.clear()
	var seen := {}
	for ci: int in cls_mk.size():
		var tab := {}
		var parts: PackedStringArray = []
		for g: int in _grades:
			var c := _market_cause(state, cls_mk[ci], g)
			tab["mkt:%d" % g] = c
			parts.append(c)
		for tg: String in _tags:
			var c := _service_cause(state, cls_sv[ci], tg)
			tab["svc:" + tg] = c
			parts.append(c)
		var k := "%s#%d" % ["|".join(parts), int(cls_noise[ci])]
		var a: int = seen.get(k, -1)
		if a < 0:
			a = _acls_tab.size()
			seen[k] = a
			_acls_tab.append(tab)
			_acls_noise.append(int(cls_noise[ci]))
		_acls_of[ci] = a


func _fillv(fills: Dictionary, g: String) -> float:
	_deps[_gidx[g]] = true
	return float(fills.get(g, 1.0))


## 지금 고른 상품 o보다 넉넉한(지난 스텝 공급률 ≥ ok, 재고 있음, 접근 가능) 대체품이 있나.
func _has_better(state: CityState, opts: Array, o: Dictionary, fills: Dictionary) -> bool:
	for a: Dictionary in opts:
		if a["key"] != o["key"] and a["kind"] == "good" and _fillv(fills, a["good"]) >= _ok and _avail(state, a) == "":
			return true
	return false


## 수요 하나의 선택. 주거마다 다른 것은 prefer 유틸리티(남는 공급 몫)뿐이라 그 판정은 mask 비트로 받는다:
## 판정에 닿으면 _hits에 [need 순번, 유틸리티, 1인 몫]을 남기고, 결과는 (mask >> idx) & 1.
var _hits: Array = []


var _volatile := false   # 이번 묶음 계산이 재고 "양"(정렬)에 기대었나 → 다음 스텝에 재사용 불가


func _pick(state: CityState, n: Dictionary, pick_str: String, idx: int, mask: int) -> Array:
	var count := int(n.get("count", 1))
	var opts: Array = n["options"]
	if opts.size() <= count:
		return opts
	var by_key: Dictionary = n["_by_key"]
	var keep: Array = []
	var inkeep := {}
	var infail := {}
	var failed: Array = []
	var fills: Dictionary = state.flags.get("fill", {})
	for k: String in pick_str.split(",", false):
		if by_key.has(k) and not inkeep.has(k) and not infail.has(k):
			var o: Dictionary = by_key[k]
			var bad := _avail(state, o) != ""
			# 재고가 조금씩만 들어와 매 스텝 바닥나는 상품(지난 스텝 공급률 < ok)도 끊긴 것으로 본다 — 넉넉한 대체품이 있으면 갈아탄다
			if not bad and o["kind"] == "good" and _fillv(fills, o["good"]) < _ok:
				bad = _has_better(state, opts, o, fills)
			if not bad:
				keep.append(o)
				inkeep[k] = true
			else:
				failed.append(o)
				infail[k] = true
	# 대부분의 스텝: 고른 것이 그대로 유효하면 바로 끝(갈아탈 prefer 선택지가 없을 때)
	if failed.is_empty() and keep.size() == count and (not n.get("_has_prefer", false) or keep[0].get("prefer", false)):
		return keep
	for o: Dictionary in opts:
		if o.get("prefer", false) and not inkeep.has(o["key"]) and _avail(state, o) == "":
			if o["kind"] == "utility":
				if _util_ratio(state, str(o["utility"])) < _ok:
					continue
				_hits.append([idx, str(o["utility"]), float(o.get("amount", 0.0))])
				if ((mask >> idx) & 1) == 0:
					continue
			keep.push_front(o)
			inkeep[o["key"]] = true
	# 새로 고를 때는 재고가 가장 많은 상품부터(같은 묶음 안에서 소비가 한 품목에 몰리지 않게)
	var cand: Array = []
	var ngood := 0
	for o: Dictionary in opts:
		var k: String = o["key"]
		if not inkeep.has(k) and not infail.has(k) and not (o.get("prefer", false) and o["kind"] == "utility") and _avail(state, o) == "" \
				and (o["kind"] != "good" or _fillv(fills, o["good"]) >= _ok):
			cand.append(o)
			if o["kind"] == "good":
				ngood += 1
	if cand.size() > 1 and keep.size() < count:
		if ngood > 1:
			_volatile = true
		cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (float(state.stock.get(a.get("good", ""), 0.0)) if a["kind"] == "good" else 0.0) > (float(state.stock.get(b.get("good", ""), 0.0)) if b["kind"] == "good" else 0.0))
	for o: Dictionary in cand:
		if keep.size() >= count:
			break
		keep.append(o)
		inkeep[o["key"]] = true
	for o: Dictionary in opts:
		if keep.size() >= count:
			break
		var k: String = o["key"]
		if not inkeep.has(k) and not infail.has(k) and not (o.get("prefer", false) and o["kind"] == "utility") and _avail(state, o) == "":
			keep.append(o)
			inkeep[k] = true
	for o: Dictionary in failed + opts:
		if keep.size() >= count:
			break
		if not inkeep.has(o["key"]):
			keep.append(o)
			inkeep[o["key"]] = true
	return keep.slice(0, count)


# ------------------------------------------------------------------ 묶음 계산(성능)
## 같은 계층 + 같은 덮임 등급(cls) + 같은 현재 선택(psig) + 같은 prefer 판정(mask)인 주거는 1단계 결과가 같다.
## 그래서 그 묶음(Ent)을 스텝마다 한 번만 계산하고, 주거마다는 주민 수만 더한다. 결과는 주거별 계산과 같다
## (소비 합계의 덧셈 순서만 달라 부동소수 끝자리만 다를 수 있다).
class Ent:
	var t: int = 0
	var ci: int = 0
	var picks: Array = []        # need 순번 → [옵션 dict…]
	var causes: Array = []       # need 순번 → [cause…]
	var pick_strs: Array = []    # need 순번 → "키,키"
	var psig: String = ""
	var dem: Dictionary = {}     # 상품 → 1인·1경제일 소비(원인 ""인 상품만)
	var extra: Dictionary = {}   # 유틸리티 → 1인 추가 수요
	var hits: Array = []         # [[idx, u, amount]] — 주거마다 판정할 prefer
	var vars: Dictionary = {}    # mask → Ent
	var rsum: float = 0.0
	var listed: bool = false
	var volatile: bool = false   # 재고 양에 따른 정렬로 골랐다 → 이번 스텝에만 유효
	var stable: bool = false     # 들어간 선택 = 나온 선택(다음 스텝에도 같은 묶음)
	var fast: bool = false       # stable이고 prefer 판정이 없다 → 주거가 그대로면 바로 재사용
	var skip: PackedInt32Array = PackedInt32Array()   # 이번 스텝에 2단계를 건너뛸 수 있는 후보 주거(순번)
	var skip_r: float = 0.0
	var hr0: float = 0.0         # 2단계 뒤 주민 수 합(주민 0명으로 시작한 주거 / 1명 이상) — 도시 행복 평균용
	var hr1: float = 0.0
	var dem_id: int = -1         # 같은 소비 묶음(dem)끼리 주민 합을 모은다
	var p2: Array = [null, null] # 주민 0 / 1명 이상일 때의 2단계 결과
	var deps: PackedInt32Array = PackedInt32Array()   # 기댄 환경 칸(_env 순번)
	var depv: PackedByteArray = PackedByteArray()    # 그때의 값
	var vstep: int = -1
	var vok: bool = true


class P2:
	var dk: Array = []           # 기댄 값: 상품 id 또는 "@water"/"@power"
	var dv: Array = []
	var vstep: int = -1
	var vok: bool = true
	var ratios: Array = []
	var dcauses: Array = []      # 표시용 cause(충족이면 "")
	var met: Array = []
	var nsig: int = 0
	var target: int = 0
	var all_ok: bool = true      # 여유를 뺀 모든 수요 충족
	var any_unmet: bool = false
	var basic_all: bool = true
	var adv_all: bool = true
	var hp: float = 50.0
	var taxk: float = 0.0
	var nonlux: Array = []       # 여유가 아닌 수요 순번(부족 일수를 센다)
	var basic: Array = []        # 순번 → 기본 수요인가
	var unmet_mask: int = 0      # 안 채워진 비여유 수요 비트
	var met_mask: int = 0        # 채워진 비여유 수요 비트
	var basic_mask: int = 0      # 기본 수요 비트


func _psig_of(t: int, b: Dictionary) -> String:
	var needs: Dictionary = b["needs"]
	var parts: PackedStringArray = []
	for n: Dictionary in by_tier.get(t, []):
		var rec: Variant = needs.get(n["id"])
		if not (rec is Dictionary):
			rec = {"ratio": 0.0, "short_days": 0.0, "pick": ""}
			needs[n["id"]] = rec
		parts.append(str(rec.get("pick", "")))
	return "%d:%s" % [t, "|".join(parts)]


var dbg_made := 0      # 성능 탐침용 계수: 묶음을 새로 계산한 횟수
var dbg_slow := 0      # 성능 탐침용 계수: 2단계를 건너뛴 주거 수


func _make_ent(state: CityState, t: int, ci: int, psig: String, mask: int) -> Ent:
	dbg_made += 1
	var e := Ent.new()
	e.t = t
	e.ci = ci
	var cur := psig.substr(psig.find(":") + 1).split("|")
	var parts: PackedStringArray = []
	_hits.clear()
	_volatile = false
	_deps.clear()
	var i := 0
	for n: Dictionary in by_tier.get(t, []):
		var ps: String = cur[i] if i < cur.size() else ""
		var picks := _pick(state, n, ps, i, mask)
		var keys: PackedStringArray = []
		var causes: Array = []
		var per := float(n.get("amount", 0.0)) / float(maxi(1, int(n.get("count", 1))))
		for o: Dictionary in picks:
			keys.append(o["key"])
			var c := _avail(state, o)
			causes.append(c)
			if o["kind"] == "good" and c == "":
				e.dem[o["good"]] = float(e.dem.get(o["good"], 0.0)) + per
			if o["kind"] == "utility" and o.has("amount"):
				e.extra[o["utility"]] = float(e.extra.get(o["utility"], 0.0)) + float(o["amount"])
		var js := ",".join(keys)
		e.picks.append(picks)
		e.causes.append(causes)
		e.pick_strs.append(js)
		parts.append(js)
		i += 1
	e.psig = "%d:%s" % [t, "|".join(parts)]
	e.stable = e.psig == psig
	e.hits = _hits.duplicate()
	e.volatile = _volatile
	e.fast = e.stable and e.hits.is_empty() and not e.volatile
	var dk := str(e.dem)
	if not _dem_of.has(dk):
		_dem_of[dk] = _dems.size()
		_dems.append(e.dem)
	e.dem_id = _dem_of[dk]
	for d: int in _deps:
		e.deps.append(d)
		e.depv.append(_env[d])
	e.vstep = _stepno
	e.vok = true
	return e


## 이 묶음이 이번 스텝에도 맞나(기댄 환경 값이 그대로인가). 스텝마다 한 번만 본다.
func _valid(e: Ent) -> bool:
	if e.vstep == _stepno:
		return e.vok
	e.vstep = _stepno
	var ok := not e.volatile
	if ok:
		for k: int in e.deps.size():
			if _env[e.deps[k]] != e.depv[k]:
				ok = false
				break
	e.vok = ok
	return ok


func _p2valid(p: P2, fill: Dictionary, state: CityState) -> bool:
	if p.vstep == _stepno:
		return p.vok
	p.vstep = _stepno
	var ok := true
	for k: int in p.dk.size():
		var key: String = p.dk[k]
		var v := _util_ratio(state, key.substr(1)) if key.begins_with("@") else float(fill.get(key, 1.0))
		if v != float(p.dv[k]):
			ok = false
			break
	p.vok = ok
	return ok


func _phase2(state: CityState, e: Ent, rpos: bool, fill: Dictionary, noise: int) -> P2:
	var p := P2.new()
	var t := e.t
	var target_f := 0.0
	var adv_met := 0
	var lux_met := 0
	var basic_short := 0
	var i := 0
	for n: Dictionary in by_tier.get(t, []):
		var picks: Array = e.picks[i]
		var causes: Array = e.causes[i]
		var count := maxi(1, int(n.get("count", 1)))
		var sum := 0.0
		var cause := ""
		for j: int in picks.size():
			var o: Dictionary = picks[j]
			var c: String = causes[j]
			var x := 0.0
			if c == "":
				match str(o["kind"]):
					"good":
						x = float(fill.get(o["good"], 1.0)) if rpos else 1.0
						if rpos:
							p.dk.append(o["good"])
							p.dv.append(x)
						if x < _ok:
							c = "stock"
					"utility":
						x = _util_ratio(state, str(o["utility"]))
						p.dk.append("@" + str(o["utility"]))
						p.dv.append(x)
						if x < _ok:
							c = str(o["utility"])
					_:
						x = 1.0
			if cause == "" and c != "":
				cause = c
			sum += x
		var ratio := clampf(sum / float(count), 0.0, 1.0)
		var met := ratio >= _ok - 1e-9
		p.ratios.append(ratio)
		p.dcauses.append(cause if ratio < _ok else "")
		p.met.append(met)
		var role := str(n["role"])
		p.basic.append(role == "basic")
		if role == "basic":
			p.basic_mask |= 1 << i
		i += 1
		if role == "luxury":
			if met:
				lux_met += 1
			continue
		p.nonlux.append(i - 1)
		if met:
			p.met_mask |= 1 << (i - 1)
		else:
			p.unmet_mask |= 1 << (i - 1)
		if not met:
			p.all_ok = false
			p.any_unmet = true
		if role == "basic":
			target_f += float(n.get("share", 0)) * clampf(ratio / _ok, 0.0, 1.0)
			if not met:
				basic_short += 1
				p.basic_all = false
		else:
			if met:
				adv_met += 1
			else:
				p.adv_all = false
	p.nsig = [p.ratios, p.dcauses].hash()
	var td := sim.tier(t)
	p.target = mini(int(td.get("cap", 4)), int(floorf(target_f + 1e-6)))
	var hp: float = _c["happiness_base"] + _hap_add + float(lux_met) * _c["happiness_per_luxury"] \
		+ float(basic_short) * _c["happiness_basic_short"] - float(noise) * _c["noise_penalty"] * maxf(0.0, _noise_k)
	p.hp = clampf(hp, 0.0, 100.0)
	var hm := lerpf(_c["tax_mult_min"], _c["tax_mult_max"], p.hp / 100.0)
	p.taxk = float(td.get("tax", 0.0)) * (1.0 + float(adv_met) * _c["advance_tax_bonus"] + float(lux_met) * _c["luxury_tax_bonus"]) * hm * _tax_k
	return p


## 계층별 "지금 승급 비용을 낼 수 있나"(돈 + 세 계열 중 하나 이상 + 추가 상품). 승급 표시(▲)는 이것까지 본다.
func _affordable(state: CityState) -> Array:
	var out: Array = [false]
	var mats: Array = sim.db.get("upgrade_costs", {}).get("materials", [])
	for t: int in range(1, sim.max_tier() + 1):
		var ok := bool(_has_up.get(t, false))
		if ok:
			var c := sim.item("upgrade_costs", "%dto%d" % [t, t + 1])
			ok = state.money + 1e-9 >= float(c.get("money", 0))
			var anym := false
			for m: String in mats:
				if float(state.stock.get(m, 0.0)) + 1e-9 >= float(c.get("qty", 0)):
					anym = true
			ok = ok and anym
			for g: String in c.get("extra", {}):
				ok = ok and float(state.stock.get(g, 0.0)) + 1e-9 >= float(c["extra"][g])
		out.append(ok)
	return out


# ------------------------------------------------------------------ 틱
func tick(state: CityState, dt: float) -> void:
	var cov := sim.cover(state)
	var clsmap: Dictionary = cov["cls"]
	if sim.no_cache:
		_forget(cov)
	_access(state, cov)
	var houses: Array = cov["houses"]
	_spare.clear()
	for u: String in state.util:
		_spare[u] = float(state.util[u].get("supply", 0.0)) - float(state.util[u].get("demand", 0.0))
	# 1단계: 고르기(묶음 단위) + 묶음별 주민 합
	for e: Ent in _last_used:
		e.rsum = 0.0
		e.listed = false
		e.skip.clear()
		e.skip_r = 0.0
		e.hr0 = 0.0
		e.hr1 = 0.0
	_stepno += 1
	var mrev := "%d:%d" % [state.get_instance_id(), int(state.flags.get("mods_rev", 0))]
	if mrev != _mrev:      # 연구·정책이 바뀌면 묶음 캐시를 버린다(행복·세수·소비 수정치가 2단계 결과에 들어 있다)
		_mrev = mrev
		_pents.clear()
		_hent.fill(null)
		_hset.fill(0)
		_food_k = sim.mod(state, "cons.food")
		_all_k = sim.mod(state, "cons.all")
		_hap_add = sim.mod_sum(state, "happy.base")
		_noise_k = sim.mod(state, "happy.noise")
		_tax_k = sim.mod(state, "tax.all")
		_movein_k = sim.mod(state, "movein")
	var fills: Dictionary = state.flags.get("fill", {})
	_env.resize(_ngoods.size() + 2)
	for gi: int in _ngoods.size():
		var g: String = _ngoods[gi]
		_env[gi] = (1 if float(state.stock.get(g, 0.0)) > 1e-9 else 0) + (2 if float(fills.get(g, 1.0)) >= _ok else 0)
	for u: String in _uidx:
		var ur := _util_ratio(state, u)
		_env[_uidx[u]] = (1 if ur >= 0.5 else 0) + (2 if ur >= _ok else 0)
	if _pacc != _acc_ver:
		_pents.clear()
		_pacc = _acc_ver
		# 통합(INTEG_NOTES): 접근표(시설 가동)가 바뀌면 주거별 빠른 길 캐시도 버린다 — 안 버리면 집을 먼저 칠하고
		# 시설을 나중에 지은 첫 도시에서 "인력 부족"이 영영 남아 떠돌이가 집마다 1명에서 멈췄다.
		_hent.fill(null)
		_hset.fill(0)
	if not is_same(cov, _cov_ref) or _hent.size() != houses.size():
		_cov_ref = cov
		_hent.resize(houses.size())
		_hent.fill(null)
		_hp2.resize(houses.size())
		_hp2.fill(null)
		_hres.resize(houses.size())
		_hset.resize(houses.size())
		_hset.fill(0)
	var offline := sim.offline
	var aff := _affordable(state)
	var fast2 := aff == _aff_last and offline == _off_last
	_aff_last = aff
	_off_last = offline
	var todo2 := PackedInt32Array()   # 2단계를 돌릴 주거 순번(주거 순서 유지)
	var ents: Dictionary = _pents
	var avc: Dictionary = {}       # ci → {옵션 키 → cause}
	var used: Array = []           # 이번 스텝에 쓰인 Ent(주민 합 순서 고정)
	var went: Array = []           # 주거 순서대로 그 주거의 Ent
	went.resize(houses.size())
	var hi := 0
	var sn := _stepno
	for b: Dictionary in houses:
		var ri: int = b["residents"]
		var r := float(ri)
		var le: Ent = _hent[hi]
		if le != null and le.fast and ((le.vstep == sn and le.vok) or _valid(le)) and b.get("psig") == le.psig:
			if not le.listed:
				le.listed = true
				used.append(le)
			le.rsum += r
			went[hi] = le
			if fast2 and ri > 0 and _hset[hi] == 1 and _hres[hi] == ri:
				le.skip.append(hi)
				le.skip_r += r
			else:
				todo2.append(hi)
			hi += 1
			continue
		var t: int = b["tier"]
		var ci: int = _acls_of[clsmap[b["id"]]]
		var ps: Variant = b.get("psig")
		if not (ps is String):
			ps = _psig_of(t, b)
			b["psig"] = ps
		var gk := t * 100000 + ci
		var bucket: Dictionary
		if ents.has(gk):
			bucket = ents[gk]
		else:
			bucket = {}
			ents[gk] = bucket
		var e: Ent = bucket.get(ps)
		if e == null or not _valid(e):
			if not avc.has(ci):
				avc[ci] = {}
			_av = avc[ci]
			_tab = _acls_tab[ci]
			e = _make_ent(state, t, ci, ps, 0)
			bucket[ps] = e
		if not e.hits.is_empty():
			var mask := 0
			for h: Array in e.hits:
				var u: String = h[1]
				var need: float = r * float(h[2])
				if float(_spare.get(u, 0.0)) >= need:
					_spare[u] = float(_spare.get(u, 0.0)) - need
					mask |= 1 << int(h[0])
			if mask != 0:
				var v: Ent = e.vars.get(mask)
				if v == null or not _valid(v):
					if not avc.has(ci):
						avc[ci] = {}
					_av = avc[ci]
					_tab = _acls_tab[ci]
					v = _make_ent(state, t, ci, ps, mask)
					e.vars[mask] = v
				e = v
		if not e.listed:
			e.listed = true
			used.append(e)
		if r > 0.0:
			e.rsum += r
		if ps != e.psig:
			var needs: Dictionary = b["needs"]
			var i := 0
			for n: Dictionary in by_tier.get(t, []):
				var rec: Variant = needs.get(n["id"])
				if not (rec is Dictionary):
					rec = {"ratio": 0.0, "short_days": 0.0, "pick": ""}
					needs[n["id"]] = rec
				rec["pick"] = e.pick_strs[i]
				i += 1
			b["psig"] = e.psig
		b["util_extra"] = e.extra
		went[hi] = e
		_hent[hi] = e
		todo2.append(hi)
		hi += 1
	# 재고/수요 비율로 공평하게 나눠 소비
	var demand := {}
	var dsum := PackedFloat64Array()
	dsum.resize(_dems.size())
	dsum.fill(0.0)
	var dorder := PackedInt32Array()   # 주거 순서로 처음 나온 소비 묶음 순서(캐시 이력과 무관 → 결정론)
	var seen := PackedByteArray()
	seen.resize(_dems.size())
	seen.fill(0)
	for e: Ent in used:
		dsum[e.dem_id] += e.rsum
		if seen[e.dem_id] == 0:
			seen[e.dem_id] = 1
			dorder.append(e.dem_id)
	for di: int in dorder:
		if dsum[di] <= 0.0:
			continue
		var dd: Dictionary = _dems[di]
		for g: String in dd:
			demand[g] = float(demand.get(g, 0.0)) + dsum[di] * float(dd[g]) * dt
	var fill := {}
	var fills_saved := {}
	for g: String in _ngoods:     # 상품 순서를 데이터 순서로 고정(묶음 캐시 이력과 무관하게 같은 순서 → 저장·불러오기 결정론)
		if not demand.has(g):
			continue
		var dmd: float = demand[g] * _all_k * (_food_k if _food.has(g) else 1.0)
		var have := float(state.stock.get(g, 0.0))
		var f := 1.0 if have >= dmd else have / dmd
		fill[g] = f
		fills_saved[g] = snappedf(f, 0.0001)
		var use := dmd * f
		if sim.offline and f < _ok and not (sim.offline_log.get("short", {}) as Dictionary).has(g):
			sim.offline_log["short"][g] = state.econ_days
		state.stock[g] = maxf(0.0, have - use)
		sim.flow_add(g, "cons", use)
		state.stat_add("cons." + g, use)
	state.flags["fill"] = fills_saved
	_last_used = used
	# 2단계: 충족도 · 인원 · 행복 · 세수 (묶음 결과 + 주거별 부족 일수·입주·퇴거)
	var grace: float = _c["grace_days"]
	var rec_mult: float = _c["short_recover_mult"]
	var mi: float = _c["move_in_per_day"]
	var mo: float = _c["move_out_per_day"]
	var hap_sum := 0.0
	var hap_w := 0.0
	# 지난 스텝과 같은 묶음·같은 2단계 결과·같은 주민 수이고 "가라앉은"(아무것도 안 변하는) 주거는 건너뛴다.
	var extra2 := false
	for e: Ent in used:
		if e.skip.is_empty():
			continue
		var pp: P2 = e.p2[1]
		if pp != null and ((pp.vstep == sn and pp.vok) or _p2valid(pp, fill, state)):
			e.hr1 += e.skip_r
			dbg_slow += e.skip.size()
		else:
			todo2.append_array(e.skip)
			extra2 = true
	if extra2:
		todo2.sort()
	for hix: int in todo2:
		var b: Dictionary = houses[hix]
		var e: Ent = went[hix]
		var old_res: int = b["residents"]
		var rpos := old_res > 0
		var t: int = b["tier"]
		var p: P2 = e.p2[1 if rpos else 0]
		if p == null or not _p2valid(p, fill, state):
			p = _phase2(state, e, rpos, fill, _acls_noise[e.ci])
			p.vstep = _stepno
			e.p2[1 if rpos else 0] = p
		var tl: Array = by_tier.get(t, [])
		var needs: Dictionary = b["needs"]
		if b.get("nsig", -1) != p.nsig:
			for i: int in tl.size():
				var rec: Dictionary = needs[tl[i]["id"]]
				rec["ratio"] = p.ratios[i]
				rec["cause"] = p.dcauses[i]
			b["nsig"] = p.nsig
		# 부족 일수: 안 채워진 수요는 유예(grace)까지 늘고(미접속 중엔 멈춤), 채워진 수요는 0까지 줄어든다.
		# sdm = 부족 일수 > 0인 수요의 비트, sdc = 유예에 닿은(꽉 찬) 수요의 비트. 꽉 찬 수요는 더 늘지 않는다.
		var sdm: int = b.get("sdm", -1)
		var sdc: int = b.get("sdc", 0)
		var todo: int = (p.unmet_mask & ~sdc) | (sdm & p.met_mask)
		if todo != 0:
			var nm := sdm & ~todo if sdm >= 0 else 0
			var nc := sdc & ~todo
			for i: int in p.nonlux:
				if (todo >> i) & 1 == 0:
					continue
				var rec: Dictionary = needs[tl[i]["id"]]
				var sd := float(rec.get("short_days", 0.0))
				if p.met[i]:
					sd = maxf(0.0, sd - rec_mult * dt)
				elif not offline:
					sd = minf(grace, sd + dt)
				rec["short_days"] = sd
				if sd > 0.0:
					nm |= 1 << i
				if sd >= grace:
					nc |= 1 << i
			b["sdm"] = nm
			b["sdc"] = nc
			sdc = nc
		var bad := (p.unmet_mask & p.basic_mask & sdc) != 0
		var cap: int = b["cap"]
		var target := mini(cap, p.target)
		b["target"] = target
		var hp := p.hp
		b["happiness"] = hp
		# 입주·퇴거
		var res := old_res
		if res < target:
			b["leave"] = 0.0
			b["grow"] = float(b.get("grow", 0.0)) + mi * _movein_k * (0.5 + hp / 100.0) * dt
			while float(b["grow"]) >= 1.0 and res < target:
				res += 1
				b["grow"] = float(b["grow"]) - 1.0
			if res >= target:
				b["grow"] = 0.0
		elif res > target and bad and not offline:
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
		b["tax"] = float(res) * p.taxk
		if rpos:
			e.hr1 += float(res)
		else:
			e.hr0 += float(res)
		var ns := "bad" if bad else ("warn" if p.any_unmet else "ok")
		var upg: Variant = b.get("upgrading")
		var ready: bool = res >= cap and p.basic_all and p.adv_all and upg == null and bool(_has_up.get(t, false))
		var up: bool = ready and bool(aff[t])
		_hp2[hix] = p
		_hres[hix] = res
		_hset[hix] = 1 if ((p.unmet_mask & ~int(b.get("sdc", 0))) == 0 and (int(b.get("sdm", 0)) & p.met_mask) == 0 and res >= target and float(b["grow"]) == 0.0 \
			and float(b["leave"]) == 0.0 and upg == null) else 0
		if res != old_res or ns != str(b["need_state"]) or up != bool(b["upgradable"]) or ready != bool(b.get("ready", false)):
			b["need_state"] = ns
			b["upgradable"] = up
			b["ready"] = ready
			state.emit("building_changed", {"bid": int(b["id"])})
	# 도시 행복 = 주민 가중 평균. 묶음 순서(주거 순서로 처음 나온 순)로 더해 건너뛰기 여부와 무관하게 같은 값.
	for e: Ent in used:
		for k: int in 2:
			var w := e.hr0 if k == 0 else e.hr1
			if w > 0.0:
				hap_sum += (e.p2[k] as P2).hp * w
				hap_w += w
	state.happiness = hap_sum / hap_w if hap_w > 0.0 else 50.0


## sim.no_cache(시험): 스텝을 넘는 기억을 모두 버린다 — 묶음·2단계 결과·주거별 빠른 길·접근표·수정치·소비 묶음 목록,
## 그리고 주거에 적어 둔 캐시 필드(psig·nsig 지움, sdm=-1·sdc=0 → 모든 수요의 부족 일수를 다시 센다).
func _forget(cov: Dictionary) -> void:
	_pents.clear()
	_pacc = -1
	_acc_key = ""
	_mrev = ""
	_last_used.clear()
	_dems.clear()
	_dem_of.clear()
	_cov_ref = null
	_hent.clear()
	_hp2.clear()
	_hres.clear()
	_hset.clear()
	_aff_last = []
	for b: Dictionary in cov["houses"]:
		b.erase("psig")
		b.erase("nsig")
		b["sdm"] = -1
		b["sdc"] = 0


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
			var alt: Array = []
			if c == "stock":
				for k: String in str(rec.get("pick", "")).split(",", false):
					if not k.begins_with("@") and not k.begins_with("svc:") and not k.begins_with("mkt:"):
						alt.append_array(_sources(state, k))
			rows.append({"id": n["id"], "name": n.get("name", n["id"]), "role": n["role"], "role_name": ROLE_NAME[n["role"]],
				"ratio": snappedf(ratio, 0.01), "state": st, "cause": c, "cause_text": ct, "jump": _jump(n, rec), "jump_alt": alt,
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


## G7: 상품 g를 얻는 곳 — 만드는 시설(짓기) + 아는 거래처의 수입 계약(교역).
func _sources(state: CityState, g: String) -> Array:
	var out: Array = []
	for id: String in sim.items("buildings"):
		if sim.bdef(id).get("recipe", {}).get("out", {}).has(g):
			out.append({"screen": "build", "arg": id, "label": "%s 짓기" % sim.bdef(id).get("name", id)})
	var ps: Dictionary = sim.db.get("partners", {}).get("partners", {})
	for oid: String in sim.items("partners"):
		var o := sim.item("partners", oid)
		if str(o.get("good", "")) == g and str(o.get("dir", "")) == "import" and state.partners.has(str(o.get("partner", ""))):
			out.append({"screen": "trade", "arg": oid, "label": "%s에서 수입" % ps.get(o["partner"], {}).get("name", o["partner"])})
	return out


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
