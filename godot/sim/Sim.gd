class_name Sim
extends RefCounted
## Sim — 시스템들을 순서대로 돌리고 명령·질의를 나눠 준다. 노드 의존 없음. Time.* 호출 없음.
## 규칙은 sim/systems/<id>.gd (data/rules/config.json "systems" 순서대로 켠다). 여기엔 규칙이 없다:
## 고정 스텝 시계, RNG, 데이터 읽기, 배치 캐시, 명령·질의 배달만 한다. 계약은 docs/ARCHITECTURE.md.
## 경제 시간은 tick(state, dt_econ_days)로만, 실제 시간은 now_unix로만 들어온다.

var db: Dictionary = {}
var systems: Array[SimSystem] = []
var sys_ids: Array[String] = []
var enabled: Dictionary = {}
var offline: bool = false          # fast_forward 중
var now_unix: int = 0              # Game이 매 프레임 넣는다(시스템 시각 + state.clock_offset)
var W: int = 12
var H: int = 12
var F: int = 10
var step_days: float = 1.0 / 48.0
var errors: Array = []             # 데이터 검증 오류(한국어)
var cover_cache: Dictionary = {}   # Cover.gd가 만든 배치 파생 캐시(저장 안 함)
var _cover_key: String = ""
var _fa: Dictionary = {}            # 이번 스텝의 상품 흐름 누적(스텝 끝에 state.flow로 접는다)
var _cfgc: Dictionary = {}          # cfg() 경로 캐시(setup마다 비움)
var _defs: Dictionary = {}          # 건물 id → 정의(bdef 빠른 길)
var _tiers: Array = []              # tier int → tiers.json 항목(0번은 빈 칸)
var _goods: Dictionary = {}         # 상품 id → 정의


func setup(data_files: Dictionary) -> void:
	db = data_files
	W = int(cfg("grid.width", 12))
	H = int(cfg("grid.height", 12))
	F = int(cfg("grid.max_floors", 10))
	_cfgc.clear()
	step_days = float(cfg("time.step_days", 1.0 / 48.0))
	_defs = items("buildings")
	_goods = items("goods")
	_tiers = [{}]
	for i: int in range(1, items("tiers").size() + 1):
		var td: Variant = items("tiers").get("t%d" % i, {})
		_tiers.append(td if td is Dictionary else {})
	errors = Validate.check(db)
	for e: String in errors:
		push_error("[데이터] " + e)
	systems.clear()
	sys_ids.clear()
	enabled.clear()
	for id: String in cfg("systems", []):
		var path := "res://sim/systems/%s.gd" % id
		if not ResourceLoader.exists(path):
			push_error("[Sim] 시스템 파일 없음: %s" % path)
			continue
		var s: SimSystem = (load(path) as GDScript).new()
		s.setup(self)
		systems.append(s)
		sys_ids.append(id)
		enabled[id] = true
	_cover_key = ""


# ------------------------------------------------------------------ 데이터
func cfg(path: String, default: Variant = null) -> Variant:
	var v: Variant
	if _cfgc.has(path):
		v = _cfgc[path]
	else:
		v = dig(db.get("config", {}), path, null)
		_cfgc[path] = v
	return default if v == null else v


func items(file: String) -> Dictionary:
	var root: Variant = db.get(file, {})
	return root.get("items", {}) if root is Dictionary else {}


func item(file: String, id: String) -> Dictionary:
	var it: Variant = items(file).get(id, {})
	return it if it is Dictionary else {}


func bdef(type: String) -> Dictionary:
	var d: Variant = _defs.get(type)
	return d if d is Dictionary else {}


func good(id: String) -> Dictionary:
	var d: Variant = _goods.get(id)
	return d if d is Dictionary else {}


func gname(id: String) -> String:
	return str(good(id).get("name", id))


## tier int(1..5) → tiers.json 항목.
func tier(t: int) -> Dictionary:
	if t > 0 and t < _tiers.size():
		return _tiers[t]
	return item("tiers", "t%d" % t)


func tname(t: int) -> String:
	return str(tier(t).get("name", "t%d" % t))


func max_tier() -> int:
	return _tiers.size() - 1 if _tiers.size() > 1 else items("tiers").size()


static func dig(root: Variant, path: String, default: Variant) -> Variant:
	var cur: Variant = root
	for part: String in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default
	return cur


## 상품 하나의 저장 한도(창고 수 반영).
func cap_of(state: CityState, g: String) -> float:
	var cat := str(good(g).get("cat", "consumer"))
	var key := "material" if cat == "material" else "goods"
	var base := float(cfg("storage.%s_base" % key, 200))
	var per := float(cfg("storage.%s_per_warehouse" % key, 300))
	return base + per * float(cover(state).get("warehouses", 0))


## 시설의 인력 비율. workforce 시스템이 꺼져 있으면 1(노동 제약 없음). 일시정지·파산 정지면 0.
func staff_of(b: Dictionary) -> float:
	if b.get("paused", false) or b.get("money_stop", false):
		return 0.0
	return float(b.get("staff", 0.0)) if enabled.has("workforce") else 1.0


func is_unlocked(state: CityState, id: String) -> bool:
	return not enabled.has("progression") or state.unlocked.has(id)


# ------------------------------------------------------------------ 수정치(연구·정책) — 하나의 접근자
## 다른 시스템은 숫자를 읽을 때 이것만 부른다: 값 × sim.mod(state, "prod.all"). 효과는 research.json·policies.json의 effects{키: 비율}.
## mod = 1 + Σ(켜진 정책 + 끝난 연구의 그 키 값). 키 목록은 docs/SIM_NOTES.md. 연구·정책이 바뀌면 state.flags.mods_rev가 오른다.
var _mods: Dictionary = {}
var _mods_key: String = ""


func mod(state: CityState, key: String) -> float:
	return 1.0 + mod_sum(state, key)


func mod_sum(state: CityState, key: String) -> float:
	var k := "%d:%d" % [state.get_instance_id(), int(state.flags.get("mods_rev", 0))]
	if k != _mods_key:
		_mods_key = k
		_mods = {}
		if enabled.has("research"):
			for id: String in state.research.get("done", {}):
				_add_effects(item("research", id).get("effects", {}))
		if enabled.has("policies"):
			for id: String in state.policies:
				if state.policies[id]:
					_add_effects(item("policies", id).get("effects", {}))
	return float(_mods.get(key, 0.0))


func _add_effects(fx: Dictionary) -> void:
	for key: String in fx:
		_mods[key] = float(_mods.get(key, 0.0)) + float(fx[key])


static func mods_changed(state: CityState) -> void:
	state.flags["mods_rev"] = int(state.flags.get("mods_rev", 0)) + 1


# ------------------------------------------------------------------ 배치 캐시
## 배치(건물·완공)가 바뀔 때만 다시 계산: 주거별 시장·서비스 접근 목록, 소음 이웃, 창고 수 등.
func cover(state: CityState) -> Dictionary:
	var key := "%d:%d" % [state.get_instance_id(), state.layout_rev()]
	if key != _cover_key:
		cover_cache = Cover.build(self, state)
		_cover_key = key
	return cover_cache


# ------------------------------------------------------------------ RNG (xorshift32, 상태는 state.rng_state)
func seed_state(state: CityState, seed_value: int) -> void:
	state.rng_seed = seed_value
	state.rng_state = ((seed_value & 0x7fffffff) * 2654435761 + 0x9E3779B9) & 0xffffffff
	for i: int in 8:
		_next(state)


func _next(state: CityState) -> int:
	var x: int = state.rng_state & 0xffffffff
	if x == 0:
		x = 0x9E3779B9
	x ^= (x << 13) & 0xffffffff
	x ^= x >> 17
	x ^= (x << 5) & 0xffffffff
	state.rng_state = x
	return x


func roll(state: CityState) -> float:
	return float(_next(state)) / 4294967296.0


func rand_seed(state: CityState) -> int:
	return _next(state) & 0x7fffffff


# ------------------------------------------------------------------ 글
func say(state: CityState, text: String, tone: String = "") -> void:
	state.add_log(kr(text), tone)


const _JOSA := [["이(가)", "이", "가"], ["을(를)", "을", "를"], ["은(는)", "은", "는"], ["과(와)", "과", "와"],
	["으로(로)", "으로", "로"], ["(이)라", "이라", "라"]]


## "이(가)" 같은 조사를 앞말 받침에 맞춘다.
static func kr(text: String) -> String:
	if text.find("(") < 0:
		return text
	for j: Array in _JOSA:
		var at := text.find(j[0])
		while at >= 0:
			var back := at - 1
			while back > 0 and text[back] in ["'", "\"", ")", "」", " "]:
				back -= 1
			var code := (text.unicode_at(back) - 0xAC00) if back >= 0 else -1
			var fin := code >= 0 and code < 11172 and code % 28 != 0
			if code < 0 and back >= 0 and text[back] >= "0" and text[back] <= "9":
				fin = text[back] in ["0", "1", "3", "6", "7", "8"]
			if j[0] == "으로(로)" and code >= 0 and code % 28 == 8:
				fin = false
			text = text.substr(0, at) + (j[1] if fin else j[2]) + text.substr(at + (j[0] as String).length())
			at = text.find(j[0])
	return text


# ------------------------------------------------------------------ 진행
func new_game(state: CityState, seed_value: int) -> void:
	seed_state(state, seed_value)
	state.econ_days = float(cfg("time.start_hour", 6)) / 24.0
	_derive_clock(state)
	state.money = float(cfg("start.money", 500))
	var st: Dictionary = cfg("start.stock", {})
	for g: String in st:
		state.stock[g] = float(st[g])
	state.ledger = {"today": {}, "days": []}
	for s: SimSystem in systems:
		s.on_new_game(state)
	state.emit("day_started", {"day": state.day})


func _derive_clock(state: CityState) -> void:
	state.day = int(floorf(state.econ_days + 1e-9)) + 1
	state.hour = (state.econ_days - float(state.day - 1)) * 24.0


## dt 경제일만큼 진행. 고정 스텝(config time.step_days)으로만 규칙을 돌린다. 남은 조각은 state.flags.step_acc.
func tick(state: CityState, dt_days: float) -> void:
	if dt_days <= 0.0:
		return
	var acc := float(state.flags.get("step_acc", 0.0)) + dt_days
	while acc >= step_days - 1e-12:
		acc -= step_days
		step(state)
	state.flags["step_acc"] = maxf(acc, 0.0)


## 한 스텝 = 모든 시스템 tick → 시계 전진 → 정시·자정 경계.
func step(state: CityState) -> void:
	var d0 := state.day
	var h0 := int(state.hour)
	_fa.clear()
	for s: SimSystem in systems:
		s.tick(state, step_days)
	_fold_flow(state)
	state.econ_days += step_days
	# 부동소수 누적 오차를 스텝 격자에 맞춘다(결정론·저장 왕복).
	state.econ_days = roundf(state.econ_days / step_days) * step_days
	_derive_clock(state)
	if int(state.hour) != h0 or state.day != d0:
		state.emit("hour", {"hour": int(state.hour)})
	if state.day != d0:
		for s: SimSystem in systems:
			s.on_day_end(state, d0)
		state.emit("day_ended", {"day": d0})
		for s: SimSystem in systems:
			s.on_day_start(state)
		state.emit("day_started", {"day": state.day})
		state.settle()


## 시스템이 상품 흐름을 보고한다. key = prod/cons/imp/exp, amt = 이번 스텝의 양.
func flow_add(g: String, key: String, amt: float) -> void:
	if amt == 0.0:
		return
	if not _fa.has(g):
		_fa[g] = {"prod": 0.0, "cons": 0.0, "imp": 0.0, "exp": 0.0}
	_fa[g][key] += amt


## state.flow = 지수 이동 평균(시간 상수 1경제일) → 단위: 경제일당. 규칙이 아니라 표시용 장부.
func _fold_flow(state: CityState) -> void:
	var k := 1.0 - step_days
	for g: String in state.flow.keys():
		var f: Dictionary = state.flow[g]
		for key: String in f:
			f[key] = float(f[key]) * k
	for g: String in _fa:
		if not state.flow.has(g):
			state.flow[g] = {"prod": 0.0, "cons": 0.0, "imp": 0.0, "exp": 0.0}
		for key: String in _fa[g]:
			state.flow[g][key] = float(state.flow[g][key]) + float(_fa[g][key])


## 미접속 경과(경제일). 같은 규칙을 offline 표시만 켜고 돈다. [B 파트 이음새: 보호 장치·요약]
func fast_forward(state: CityState, econ_days: float) -> Dictionary:
	var before := {"money": state.money, "pop": state.population(), "stock": state.stock.duplicate()}
	offline = true
	tick(state, econ_days)
	offline = false
	var lines: Array = ["자리를 비운 사이 경제 시간으로 %.1f일이 흘렀다." % econ_days]
	for s: SimSystem in systems:
		s.fast_forward(state, econ_days, before, lines)
	return {"econ_days": econ_days, "lines": lines}


# ------------------------------------------------------------------ 명령·질의
func can(state: CityState, name: String, args: Dictionary) -> Dictionary:
	if name == "debug":
		var on: bool = cfg("debug.enabled", false)
		return {"ok": on, "reason": "" if on else "디버그가 꺼져 있다."}
	for s: SimSystem in systems:
		var r: Variant = s.can(state, name, args)
		if r != null:
			return r
	return {"ok": false, "reason": "지금은 할 수 없는 일이다 (%s)" % name}


func apply(state: CityState, name: String, args: Dictionary) -> Dictionary:
	var c := can(state, name, args)
	if not c.get("ok", false):
		return c
	var res: Variant = null
	if name == "debug":
		res = Debug.run(self, state, args)
	else:
		for s: SimSystem in systems:
			res = s.apply(state, name, args)
			if res != null:
				break
	if res == null:
		return {"ok": false, "reason": "지금은 할 수 없는 일이다 (%s)" % name}
	if res.get("ok", false):
		for s: SimSystem in systems:
			s.on_command(state, name, args, res)
	return res


## 질의: 시스템이 소유한 질의 → 공용 Queries → 시스템의 augment()로 보탬.
func query(state: CityState, name: String, args: Dictionary = {}) -> Variant:
	if name == "can":
		return can(state, str(args.get("cmd", "")), args)
	var r: Variant = null
	for s: SimSystem in systems:
		r = s.query(state, name, args)
		if r != null:
			break
	if r == null:
		r = Queries.run(self, state, name, args)
	if r is Dictionary or r is Array:
		for s: SimSystem in systems:
			s.augment(state, name, args, r)
	return r
