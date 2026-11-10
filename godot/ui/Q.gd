class_name Q
extends RefCounted
## Q — Game/View 접근을 한곳에 모은 안전망. 무엇이 null 이어도 UI는 죽지 않는다.
## UI의 모든 질의·검증·뷰 호출은 여기를 거친다(명령만 UIRoot.cmd 를 거친다: 튜토리얼이 엿들어야 하므로).


static func dict(q_name: String, args: Dictionary = {}) -> Dictionary:
	var v: Variant = Game.query(q_name, args)
	return v if v is Dictionary else {}


static func list(q_name: String, args: Dictionary = {}) -> Array:
	var v: Variant = Game.query(q_name, args)
	return v if v is Array else []


static func raw(q_name: String, args: Dictionary = {}) -> Variant:
	return Game.query(q_name, args)


## 항상 {ok, reason} 을 돌려준다.
static func can(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	var v: Variant = Game.can(cmd_name, args)
	if v is Dictionary:
		return {"ok": bool(v.get("ok", false)), "reason": str(v.get("reason", ""))}
	return {"ok": false, "reason": ""}


static func view() -> Node:
	var v: Variant = Game.view
	if v != null and is_instance_valid(v):
		return v
	return null


## 뷰 메서드를 있으면 부른다. 없으면 fallback.
static func vcall(method: String, args: Array = [], fallback: Variant = null) -> Variant:
	var v := view()
	if v == null or not v.has_method(method):
		return fallback
	return v.callv(method, args)


static func project(pos: Variant) -> Vector2:
	if not (pos is Vector3i):
		return Vector2(-9999, -9999)
	var r: Variant = vcall("project", [pos])
	return r if r is Vector2 else Vector2(-9999, -9999)


static func pick(screen_pos: Vector2) -> Dictionary:
	var r: Variant = vcall("pick", [screen_pos])
	return r if r is Dictionary else {}
