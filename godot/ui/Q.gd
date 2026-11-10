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


## can() 결과를 통째로(support_cells, cost, skipped …). 항상 ok·reason 이 있다.
static func can_full(cmd_name: String, args: Dictionary = {}) -> Dictionary:
	var v: Variant = Game.can(cmd_name, args)
	var d: Dictionary = (v as Dictionary).duplicate() if v is Dictionary else {}
	d["ok"] = bool(d.get("ok", false))
	d["reason"] = str(d.get("reason", ""))
	return d


## 지금 승급 가능한 주거 묶음 [{tier, tier_name, count, bids}].
## 계약 질의 upgradable 이 아직 없으면(null) 시뮬이 건물마다 계산해 둔 upgradable 표시를 읽어 계층별로 묶기만 한다
## (판정은 시뮬의 것 그대로 — UI는 세기만 한다). UI_NOTES 계약 빈틈 #U1.
static func upgradable() -> Array:
	var v: Variant = Game.query("upgradable", {})
	if v is Array:
		return v
	var by := {}
	var st: Variant = Game.state
	if st == null:
		return []
	for b: Variant in st.buildings.values():
		if b is Dictionary and str(b.get("kind", "")) == "house" and bool(b.get("upgradable", false)) and b.get("upgrading") == null:
			var t := int(b.get("tier", 1))
			if not by.has(t):
				by[t] = []
			by[t].append(int(b.get("id", -1)))
	var out: Array = []
	var keys := by.keys()
	keys.sort()
	var tiers := {}
	for row: Variant in UI.to_array(UI.to_dict(Game.query("economy")).get("tiers", [])):
		if row is Dictionary:
			tiers[int(row.get("tier", 0))] = str(row.get("name", ""))
	for t: int in keys:
		out.append({"tier": t, "tier_name": tiers.get(t, "t%d" % t), "count": (by[t] as Array).size(), "bids": by[t]})
	return out


## 화면 이동 요청을 정규화: {screen, arg}. 시뮬이 쓰는 이름(contracts, expeditions …)을 화면 id 로.
static func norm_jump(j: Variant) -> Dictionary:
	var d: Dictionary = j if j is Dictionary else {}
	var s := str(d.get("screen", ""))
	s = {"contracts": "trade", "contract": "trade", "expeditions": "expedition", "explore": "expedition",
		"goals": "keep", "research": "keep", "policies": "keep", "log": "keep"}.get(s, s)
	return {"screen": s, "arg": str(d.get("arg", ""))}
