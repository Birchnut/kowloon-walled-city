class_name Sim
extends RefCounted
## Sim — 시스템들을 순서대로 돌리고 명령·질의를 나눠 준다. 노드 의존 없음.
## 규칙은 sim/systems/<id>.gd (config.json "systems" 순서대로 켠다). 여기엔 규칙이 없다:
## 시간 쪼개기, RNG, 데이터 읽기, 지표 캐시, 명령 배달만 한다. 계약은 docs/ARCHITECTURE.md.

const KIND_FILE := {"housing": "housing", "business": "businesses", "facility": "facilities"}

var db: Dictionary = {}              # Data.files (파일명 → JSON 루트). 헤드리스에서는 직접 읽어 주입.
var systems: Array[SimSystem] = []
var enabled: Dictionary = {}         # 시스템 id → true
var offline: bool = false            # fast_forward 중(성장 없음·재난 보류)
var W: int = 12
var H: int = 12
var F: int = 10
var gate: Vector2i = Vector2i(5, 11)
var _mcache: Dictionary = {}
var _mdirty: bool = true
var _mstate: int = 0
var _opts: Dictionary = {}           # axis → {option id → option}


func setup(data_files: Dictionary) -> void:
	db = data_files
	W = int(cfg("grid.width", 12))
	H = int(cfg("grid.height", 12))
	F = int(cfg("grid.max_floors", 10))
	var g: Array = cfg("grid.gate", [W / 2, H - 1])
	gate = Vector2i(int(g[0]), int(g[1]))
	_opts.clear()
	for a: Dictionary in db.get("policies", {}).get("axes", []):
		_opts[a["axis"]] = {}
		for o: Dictionary in a.get("options", []):
			_opts[a["axis"]][o["id"]] = o
	systems.clear()
	enabled.clear()
	for id: String in cfg("systems", []):
		var path := "res://sim/systems/%s.gd" % id
		if not ResourceLoader.exists(path):
			push_warning("[Sim] 시스템 파일 없음: %s" % path)
			continue
		var s: SimSystem = (load(path) as GDScript).new()
		s.setup(self)
		systems.append(s)
		enabled[id] = true
	touch()


# ------------------------------------------------------------------ 데이터
func cfg(path: String, default: Variant = null) -> Variant:
	return _dig(db.get("config", {}), path, default)


## 시스템 수치: data/economy.json 의 "<system>.<key>".
func tune(path: String, default: Variant = null) -> Variant:
	return _dig(db.get("economy", {}), path, default)


func num(path: String, default: float = 0.0) -> float:
	return float(_dig(db.get("economy", {}), path, default))


func pace(key: String) -> float:
	return float(cfg("pace." + key, 1.0))


func items(file: String) -> Dictionary:
	var root: Variant = db.get(file, {})
	return root.get("items", {}) if root is Dictionary else {}


func item(file: String, id: String) -> Dictionary:
	var it: Variant = items(file).get(id, {})
	return it if it is Dictionary else {}


## 셀의 콘텐츠 정의(공사 중이면 완공 후의 정의).
func def_of(cell: Dictionary) -> Dictionary:
	var c: Dictionary = cell.get("becomes", cell) if cell.get("kind", "") == "site" else cell
	return item(KIND_FILE.get(c.get("kind", ""), ""), str(c.get("type", "")))


func _dig(root: Variant, path: String, default: Variant) -> Variant:
	var cur: Variant = root
	for part: String in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default
	return cur


# ------------------------------------------------------------------ 정책·해금
## 지금 고른 정책 옵션들의 mods[key]를 전부 곱한 값(없으면 1).
func mod(state: CityState, key: String) -> float:
	var v := 1.0
	for axis: String in state.policies:
		var o: Dictionary = _opts.get(axis, {}).get(state.policies[axis], {})
		v *= float(o.get("mods", {}).get(key, 1.0))
	return v


func option(axis: String, id: String) -> Dictionary:
	return _opts.get(axis, {}).get(id, {})


func is_unlocked(state: CityState, id: Variant) -> bool:
	return id == null or str(id) == "" or state.unlocked.has(str(id)) or not enabled.has("unlocks")


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


func roll_range(state: CityState, a: int, b: int) -> int:
	return a if b <= a else a + _next(state) % (b - a + 1)


func rand_seed(state: CityState) -> int:
	return _next(state) & 0x7fffffff


## 가중치 배열에서 하나 뽑는다. 전부 0 이하면 -1.
func pick(state: CityState, weights: Array) -> int:
	var total := 0.0
	for w: Variant in weights:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return -1
	var r := roll(state) * total
	for i: int in weights.size():
		r -= maxf(float(weights[i]), 0.0)
		if r < 0.0:
			return i
	return weights.size() - 1


# ------------------------------------------------------------------ 지표·식
func touch() -> void:
	_mdirty = true


func metrics(state: CityState) -> Dictionary:
	if _mdirty or _mstate != state.get_instance_id():
		_mcache = Metrics.compute(self, state)
		for s: SimSystem in systems:
			s.metrics(state, _mcache)
		_mdirty = false
		_mstate = state.get_instance_id()
	return _mcache


func test(state: CityState, cond: Variant) -> bool:
	return Expr.test(cond, metrics(state))


func run(state: CityState, effects: Variant) -> void:
	Expr.apply(self, state, effects)


## 글 속의 {t}를 지금 호칭으로, "이(가)" 같은 조사를 앞말 받침에 맞게.
func fmt(state: CityState, text: String) -> String:
	return kr(text.replace("{t}", str(state.identity.get("title", "대장"))))


## 기록 한 줄(fmt를 거친다).
func say(state: CityState, text: String, tone: String = "") -> void:
	state.add_log(fmt(state, text), tone)


const _JOSA := [["이(가)", "이", "가"], ["을(를)", "을", "를"], ["은(는)", "은", "는"], ["과(와)", "과", "와"],
	["와(과)", "과", "와"], ["으로(로)", "으로", "로"], ["(이)라", "이라", "라"], ["(이)", "이", ""]]


static func kr(text: String) -> String:
	if text.find("(") < 0:
		return text
	for j: Array in _JOSA:
		var at := text.find(j[0])
		while at >= 0:
			var back := at - 1
			while back > 0 and text[back] in ["'", "\"", ")", "」", "’", "”", " "]:
				back -= 1
			var code := (text.unicode_at(back) - 0xAC00) if back >= 0 else -1
			var fin := code >= 0 and code < 11172 and code % 28 != 0
			if j[0] == "으로(로)" and code >= 0 and code % 28 == 8:
				fin = false
			text = text.substr(0, at) + (j[1] if fin else j[2]) + text.substr(at + (j[0] as String).length())
			at = text.find(j[0])
	return text


# ------------------------------------------------------------------ 진행
func new_game(state: CityState, seed_value: int) -> void:
	seed_state(state, seed_value)
	state.day = 1
	state.hour = float(cfg("time.start_hour", 6))
	for s: SimSystem in systems:
		s.on_new_game(state)
	touch()
	state.emit("day_started", {"day": state.day})


## dt_hours 만큼 도시 시간을 진행. 정시마다 끊어서 on_hour / on_day_end 를 돌린다.
func tick(state: CityState, dt_hours: float) -> void:
	var left := dt_hours
	while left > 1e-9:
		var step := minf(left, floorf(state.hour) + 1.0 - state.hour)
		left -= step
		var h0 := int(state.hour)
		var d0 := state.day
		for s: SimSystem in systems:
			s.tick(state, step)
		if state.hour >= 24.0:
			touch()
			for s: SimSystem in systems:
				s.on_day_end(state)
			for s: SimSystem in systems:
				s.on_day_start(state)
		if int(state.hour) != h0 or state.day != d0:
			touch()
			for s: SimSystem in systems:
				s.on_hour(state, int(state.hour))
			if state.day != d0:
				state.settle()


## 미접속 시간 처리(도시 시간 hours). 같은 규칙을 offline 표시만 켜고 1시간 단위로 돌린다.
## 반환: {hours, lines[]} — UI의 "자리를 비운 사이" 요약.
func fast_forward(state: CityState, hours: float) -> Dictionary:
	var before: Dictionary = metrics(state).duplicate()
	offline = true
	var left := hours
	while left > 1e-9:
		var step := minf(left, 1.0)
		tick(state, step)
		left -= step
	offline = false
	touch()
	var lines: Array = []
	for s: SimSystem in systems:
		s.fast_forward(state, hours, before, lines)
	return {"hours": hours, "lines": lines}


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
	var res: Variant = _debug(state, args) if name == "debug" else null
	for s: SimSystem in systems:
		if res != null:
			break
		res = s.apply(state, name, args)
	if res == null:
		return {"ok": false, "reason": "지금은 할 수 없는 일이다 (%s)" % name}
	touch()
	if res.get("ok", false):
		for s: SimSystem in systems:
			s.on_command(state, name, args, res)
		touch()
	return res


func query(state: CityState, name: String, args: Dictionary) -> Variant:
	for s: SimSystem in systems:
		var r: Variant = s.query(state, name, args)
		if r != null:
			return r
	match name:
		"hud": return _hud(state)
		"metrics": return metrics(state)
		"identity": return state.identity
		"cards": return state.pending_cards
		"log": return state.logbook.slice(maxi(0, state.logbook.size() - int(args.get("n", 20))))
		"cell_info": return _cell_info(state, args.get("pos", Vector3i.ZERO))
		"facilities", "plant_spots", "policies", "collect_points": return []
	return null


func _hud(state: CityState) -> Dictionary:
	var m := metrics(state)
	return {
		"day": state.day, "hour": state.hour, "money": state.money, "food": state.food,
		"materials": state.materials, "population": state.population(),
		"prestige": state.prestige, "notoriety": state.notoriety, "morale": state.morale,
		"title": state.identity.get("title", "대장"), "epithet": state.identity.get("epithet", ""),
		"power_level": state.power_level, "cards": state.pending_cards.size(),
		"water_cap": state.water_cap, "waiting": int(m.get("waiting", 0)), "alley_fund": state.alley_fund,
	}


## 셀(또는 빈 칸) 설명. 뼈대만 만들고 줄은 각 시스템의 describe()가 보탠다.
func _cell_info(state: CityState, pos: Vector3i) -> Dictionary:
	var cell: Dictionary = state.cell(pos)
	var info := {"title": "빈 터", "subtitle": "%d층" % (pos.z + 1), "lines": [], "actions": []}
	if not cell.is_empty():
		var d := def_of(cell)
		var mat: String = item("materials", str(cell.get("becomes", cell).get("material", ""))).get("name", "")
		info["title"] = str(d.get("name", cell.get("type", "?")))
		info["subtitle"] = "%d층 · %s" % [pos.z + 1, mat]
		if cell.get("kind", "") == "site":
			info["title"] = "공사 중 — " + info["title"]
			info["lines"].append("대나무 비계가 올라가는 중 (%d%%)" % int(float(cell.get("progress", 0.0)) * 100.0))
		elif d.has("desc"):
			info["lines"].append(str(d["desc"]))
		if str(cell.get("why", "")) != "":
			info["lines"].append("왜 여기에: " + str(cell["why"]))
	for s: SimSystem in systems:
		s.describe(state, pos, cell, info)
	return info


## 개발용 명령. op: add_money|add_food|add_materials {amount} · set {field,value} · skip_hours {hours}
##   unlock_all · unlock {id} · effects {effects:[...]} (Expr 효과를 그대로 실행 — 카드 강제, 가구·가게 소환 등)
func _debug(state: CityState, args: Dictionary) -> Dictionary:
	match str(args.get("op", "")):
		"add_money": state.money += float(args.get("amount", 100))
		"add_food": state.food += float(args.get("amount", 100))
		"add_materials": state.materials += float(args.get("amount", 100))
		"set": state.set(str(args.get("field", "")), args.get("value"))
		"skip_hours": tick(state, float(args.get("hours", 1)))
		"unlock": run(state, [["unlock", str(args.get("id", ""))]])
		"unlock_all":
			for file: String in ["unlocks"]:
				for id: String in items(file):
					run(state, [["unlock", id]])
		"effects": run(state, args.get("effects", []))
		_: return {"ok": false, "reason": "모르는 디버그 명령."}
	return {"ok": true, "reason": ""}
