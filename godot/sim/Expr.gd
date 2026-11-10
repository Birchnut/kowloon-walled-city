class_name Expr
extends RefCounted
## Expr — JSON으로 쓰는 조건·가중합·효과의 아주 작은 해석기. 카드·해금·명물·유입·지표가 같이 쓴다.
##
## 조건  : ["population", ">=", 40]  /  {"all":[..]}  {"any":[..]}  {"not": ..}  / 잎의 배열 = all
##         값 자리에 "$이름"을 쓰면 다른 지표와 비교. 없는 지표는 0(문자 비교면 "").
## 가중합: [["jobs_open", 0.3], ["prestige", 0.01, 2.0]]  → Σ 지표×가중치 (셋째 값 = 그 항의 절댓값 상한)
## 효과  : [["money","+",200], ["unlock","night_market"], ["log","..."], ["spawn_business","loan_office"], …]
##         전체 목록은 apply() 아래 match 문을 볼 것. 시스템을 직접 부르지 않고 state.flags의 요청 큐에 쌓는다.

const FIELDS := ["money", "food", "materials", "prestige", "notoriety", "morale", "alley_fund"]
const METERS := ["prestige", "notoriety", "morale"]


static func value(m: Dictionary, key: Variant) -> Variant:
	if key is String:
		if key.begins_with("$"):
			return m.get(key.substr(1), 0.0)
		return key
	return key


static func test(cond: Variant, m: Dictionary) -> bool:
	if cond == null:
		return true
	if cond is Dictionary:
		if cond.has("all"):
			for c: Variant in cond["all"]:
				if not test(c, m):
					return false
			return true
		if cond.has("any"):
			for c: Variant in cond["any"]:
				if test(c, m):
					return true
			return false
		if cond.has("not"):
			return not test(cond["not"], m)
		return true
	if cond is Array:
		if cond.is_empty():
			return true
		if cond[0] is String and cond.size() == 3 and cond[1] is String and _is_op(cond[1]):
			return _leaf(cond, m)
		for c: Variant in cond:
			if not test(c, m):
				return false
		return true
	return bool(cond)


static func _is_op(s: String) -> bool:
	return s in [">=", "<=", ">", "<", "==", "!="]


static func _leaf(c: Array, m: Dictionary) -> bool:
	var rhs: Variant = value(m, c[2])
	var lhs: Variant = m.get(c[0], "" if rhs is String else 0.0)
	if rhs is String or lhs is String:
		var eq: bool = str(lhs) == str(rhs)
		return eq if c[1] == "==" else (not eq if c[1] == "!=" else false)
	var a := float(lhs)
	var b := float(rhs)
	match c[1]:
		">=": return a >= b
		"<=": return a <= b
		">": return a > b
		"<": return a < b
		"==": return is_equal_approx(a, b)
		"!=": return not is_equal_approx(a, b)
	return false


static func linear(terms: Variant, m: Dictionary, base: float = 0.0) -> float:
	var sum := base
	if not (terms is Array):
		return sum
	for t: Variant in terms:
		if not (t is Array) or t.size() < 2:
			continue
		var raw: Variant = m.get(t[0], 0.0)
		var x: float = (float(raw) if (raw is float or raw is int or raw is bool) else 0.0) * float(t[1])
		if t.size() >= 3:
			var cap := absf(float(t[2]))
			x = clampf(x, -cap, cap)
		sum += x
	return sum


## 효과 목록을 적용. sim은 RNG·지표·데이터 접근용(시스템을 부르지 않는다).
static func apply(sim: Sim, state: CityState, effects: Variant) -> void:
	if not (effects is Array):
		return
	for e: Variant in effects:
		if not (e is Array) or e.is_empty():
			continue
		var op := str(e[0])
		if op in FIELDS and e.size() >= 3:
			_field(state, op, str(e[1]), float(e[2]))
			continue
		match op:
			"unlock":
				if not state.unlocked.has(str(e[1])):
					state.unlocked[str(e[1])] = state.day
					state.emit("unlock", {"id": str(e[1])})
			"log":
				state.add_log(sim.fmt(state, str(e[1])), str(e[2]) if e.size() > 2 else "")
			"flag":
				state.flags[str(e[1])] = e[2] if e.size() > 2 else 1
			"flag+":
				state.flags[str(e[1])] = float(state.flags.get(str(e[1]), 0.0)) + float(e[2] if e.size() > 2 else 1)
			"policy":
				state.policies[str(e[1])] = str(e[2])
			"power":
				state.flags["power_contract"] = int(e[1])
			"title":
				state.flags["forced_title"] = str(e[1])
			"spawn_business":
				for i: int in int(e[2] if e.size() > 2 else 1):
					_push(state, "build_requests", {"type": str(e[1])})
			"spawn_household":
				for i: int in int(e[2] if e.size() > 2 else 1):
					_push(state, "arrival_requests", {"type": str(e[1])})
			"leave":
				_push(state, "leave_requests", {"type": str(e[1]), "count": int(e[2] if e.size() > 2 else 1),
					"reason": str(e[3]) if e.size() > 3 else "card"})
			"close_business":
				_push(state, "close_requests", {"match": str(e[1]), "count": int(e[2] if e.size() > 2 else 1)})
			"queue_card":
				_push(state, "card_queue", {"card": str(e[1]), "day": state.day + int(e[2] if e.size() > 2 else 0)})
			"mission":
				_push(state, "mission_requests", {"mission": str(e[1])})
			"zone_clear":
				_zone_clear(sim, state, str(e[1]), int(e[2] if e.size() > 2 else 1))
			"if":
				if test(e[1], sim.metrics(state)):
					apply(sim, state, e[2])
				elif e.size() > 3:
					apply(sim, state, e[3])
			"chance":
				if sim.randf(state) < float(e[1]):
					apply(sim, state, e[2])
				elif e.size() > 3:
					apply(sim, state, e[3])
			_:
				push_warning("[Expr] 모르는 효과: %s" % op)
	sim.touch()


static func _field(state: CityState, f: String, op: String, x: float) -> void:
	var v := float(state.get(f))
	match op:
		"+": v += x
		"-": v -= x
		"*": v *= x
		"=": v = x
	if f in METERS:
		v = clampf(v, 0.0, 100.0)
	elif f != "money":
		v = maxf(v, 0.0)
	state.set(f, v)


static func _push(state: CityState, queue: String, item: Dictionary) -> void:
	if not state.flags.has(queue):
		state.flags[queue] = []
	state.flags[queue].append(item)


static func _zone_clear(sim: Sim, state: CityState, zone: String, n: int) -> void:
	var cols: Array = []
	for c: Variant in state.zones:
		if state.zones[c] == zone:
			cols.append(c)
	for i: int in mini(n, cols.size()):
		var col: Vector2i = cols[sim.randi_range(state, 0, cols.size() - 1)]
		cols.erase(col)
		state.zones.erase(col)
		state.emit("zone_changed", {"col": col})
