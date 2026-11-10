class_name Expr
extends RefCounted
## Expr — JSON으로 쓰는 조건·가중합의 아주 작은 해석기(해금 조건 등). 지표는 Metrics.compute.
##
## 조건  : ["population", ">=", 40]  /  {"all":[..]}  {"any":[..]}  {"not": ..}  / 잎의 배열 = all
##         값 자리에 "$이름"을 쓰면 다른 지표와 비교. 없는 지표는 0(문자 비교면 "").
## 가중합: [["jobs_open", 0.3], ["prestige", 0.01, 2.0]]  → Σ 지표×가중치 (셋째 값 = 그 항의 절댓값 상한)



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
