extends RefCounted
## 도시(규칙 층)와 만나는 유일한 파일. 통합할 때는 이 파일만 보면 된다.
##   begin(dest)  → Game.cmd("run_begin", {dest})  → {ok, reason, stock:{good:n}, danger:int, seed:int}
##   result(r)    → Game.cmd("run_result", {dest, loot:{good:n}, outcome:"boss"|"exit"|"down", finds:[String]})
## Game에 명령이 아직 없으면(다른 작업자가 추가 중) data/run/run_goods.json 의 견본을 쓰고 결과는 출력만 한다.

const RunCfg = preload("res://expedition/RunCfg.gd")

static var last_sent: Dictionary = {}
static var use_city: bool = true        # 배치·시험에서는 false(도시를 건드리지 않는다)


static func _game() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Game")
	return null


static func _has_cmd(r: Dictionary, name: String) -> bool:
	# Sim.apply는 모르는 명령에 "지금은 할 수 없는 일이다 (name)"를 돌려준다.
	if r.get("ok", false):
		return true
	return not str(r.get("reason", "")).contains("(%s)" % name)


## 줍기 시작. seed_override >= 0 이면 지도 번호를 바꾼다(다른 지도 / 시험용).
static func begin(dest: String, seed_override: int = -1) -> Dictionary:
	var sample: Dictionary = RunCfg.file("run_goods").get("sample_begin", {})
	var out := {"ok": true, "reason": "", "stock": (sample.get("stock", {}) as Dictionary).duplicate(), "danger": int(sample.get("danger", 2)), "seed": 1, "source": "sample"}
	var g := _game()
	if use_city and g != null and g.has_method("cmd"):
		var r: Dictionary = g.cmd("run_begin", {"dest": dest})
		if _has_cmd(r, "run_begin"):
			if not r.get("ok", false):
				return r
			out = r.duplicate()
			out["source"] = "city"
			out["stock"] = from_city(out.get("stock", {}))
	var st: Dictionary = {}
	for gid in (out.get("stock", {}) as Dictionary):
		st[gid] = int(out["stock"][gid])
	out["stock"] = st
	out["danger"] = int(out.get("danger", 2))
	if seed_override >= 0:
		out["seed"] = seed_override
	elif out["source"] == "sample":
		out["seed"] = int(Time.get_unix_time_from_system()) % 100000
	return out


## 줍기 id → 도시 id (run_goods.json 의 city_id). 통합 때 여기만 맞춘다.
static func to_city(loot: Dictionary) -> Dictionary:
	var out := {}
	for g in loot:
		var cid := str(RunCfg.good(g).get("city_id", g))
		out[cid] = int(out.get(cid, 0)) + int(loot[g])
	return out


static func from_city(stock: Dictionary) -> Dictionary:
	var back := {}
	for g in RunCfg.goods():
		back[str(RunCfg.good(g).get("city_id", g))] = g
	var out := {}
	for cid in stock:
		var g: String = back.get(cid, cid)
		out[g] = int(out.get(g, 0)) + int(stock[cid])
	return out


static func result(r: Dictionary) -> Dictionary:
	var args := {"dest": r.get("dest", ""), "loot": to_city(r.get("loot", {})), "outcome": r.get("outcome", "exit"), "finds": r.get("finds", [])}
	last_sent = args
	var g := _game()
	if use_city and g != null and g.has_method("cmd"):
		var res: Dictionary = g.cmd("run_result", args)
		if _has_cmd(res, "run_result"):
			return res
	print("[CityLink] run_result (도시에 명령이 아직 없어 출력만): ", JSON.stringify(args))
	return {"ok": true, "reason": "", "rewards": [], "finds": args["finds"], "lost": []}


## 오른쪽 위 "성채 소식"에 띄울 줄. 진짜 게임에서는 도시가 줍는 동안에도 돈다.
static func ticker() -> Array:
	var g := _game()
	if use_city and g != null and g.has_method("query"):
		var q: Variant = g.query("run_ticker", {})
		if q is Array and not (q as Array).is_empty():
			return q
	return [
		"3층 완탕집에 김이 오른다",
		"굴러온 돌 2명이 입주 신청서를 냈다",
		"전기 계량기가 또 거꾸로 돈다",
		"월세 전사 1명이 월세를 미뤘다. 이유는 묻지 않았다",
		"옥상 비둘기 협회 정기 총회 중",
		"물탱크 수위 보통. 맛은 묻지 말 것",
		"봉제방 재봉틀 4대 가동 중",
		"관리사무소: 복도에 짐 두지 마세요(무시됨)",
	]
