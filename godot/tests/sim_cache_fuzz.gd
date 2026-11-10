extends SceneTree
## sim_cache_fuzz — 캐시 차등 퍼즈(파트 C). 같은 씨앗의 두 시뮬(캐시 켬 / sim.no_cache)에 같은 무작위 명령을 넣고
## N스텝마다 CityState JSON 전체를 비교한다(주거 캐시 필드 psig·nsig·sdm·sdc만 뺀다).
## 실행: godot --headless --path godot -s res://tests/sim_cache_fuzz.gd -- [mode=short|long] [seeds=N] [days=D] [seed0=S] [every=K]
##   short(기본, sim_test.sh): 씨앗 3 × 4경제일. long: 씨앗 20 × 30경제일.
## 끝줄: "FUZZ: PASS …" 또는 "FUZZ: FAIL …"(첫 차이 경로·명령 기록과 함께).

const IGNORE := ["psig", "nsig", "sdm", "sdc"]

var DB: Dictionary
var rs: int = 1               # 퍼즈 자신의 RNG(시뮬 RNG와 무관)
var trail: Array = []         # 최근 명령(실패 보고용)
var counts: Dictionary = {}   # 명령 종류 → 성공 횟수
var houses_first := false     # 씨앗 홀수: 첫 경제일은 주거만 칠하고(+돈) 시설은 그 뒤에 — 통합에서 찾은 캐시 버그의 순서


func _init() -> void:
	var a := {}
	for s: String in OS.get_cmdline_user_args():
		var kv := s.split("=", true, 1)
		if kv.size() == 2:
			a[kv[0]] = kv[1]
	var mode := str(a.get("mode", "short"))
	var seeds := int(a.get("seeds", 20 if mode == "long" else 3))
	var days := float(a.get("days", 30 if mode == "long" else 4))
	var seed0 := int(a.get("seed0", 1))
	var every := int(a.get("every", 6))
	DB = SimIO.load_db()
	var t0 := Time.get_ticks_msec()
	var bad: Array = []
	for i: int in seeds:
		var r := run_seed(seed0 + i, days, every)
		print("  seed %d: %s" % [seed0 + i, r])
		if not str(r).begins_with("ok"):
			bad.append("seed %d: %s" % [seed0 + i, r])
	var keys := counts.keys()
	keys.sort()
	var cs: PackedStringArray = []
	for k: String in keys:
		cs.append("%s %d" % [k, counts[k]])
	print("  명령(성공): ", ", ".join(cs))
	var sec := float(Time.get_ticks_msec() - t0) / 1000.0
	if bad.is_empty():
		print("FUZZ: PASS (%s, 씨앗 %d × %.0f경제일, %.1f초)" % [mode, seeds, days, sec])
	else:
		print("FUZZ: FAIL %d/%d" % [bad.size(), seeds])
		for b: String in bad:
			print("  - ", b)
	quit(0 if bad.is_empty() else 1)


func rnd() -> int:
	var x := rs & 0xffffffff
	if x == 0:
		x = 0x9E3779B9
	x ^= (x << 13) & 0xffffffff
	x ^= x >> 17
	x ^= (x << 5) & 0xffffffff
	rs = x
	return x


func ri(n: int) -> int:
	return int(rnd() % maxi(1, n))


func rf() -> float:
	return float(rnd()) / 4294967296.0


func pick(arr: Array) -> Variant:
	return arr[ri(arr.size())] if not arr.is_empty() else null


# ------------------------------------------------------------------ 비교
func _clean(st: CityState) -> Dictionary:
	# 전체 정밀도(settle 없이): 저장 글의 자릿수 밑에 숨은 끝자리 차이까지 잡는다
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_dict(), "", false, true))
	for b: Variant in (d.get("buildings", {}) as Dictionary).values():
		if b is Dictionary:
			for k: String in IGNORE:
				b.erase(k)
	return d


func _diff(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: %s ≠ %s" % [path, str(a).left(80), str(b).left(80)]
	if a is Dictionary:
		var ks: Array = (a as Dictionary).keys()
		for k: Variant in (b as Dictionary).keys():
			if not (k in ks):
				ks.append(k)
		for k: Variant in ks:
			if not a.has(k) or not b.has(k):
				return "%s.%s: 한쪽에만 있음 (%s / %s)" % [path, str(k), str(a.get(k, "∅")).left(60), str(b.get(k, "∅")).left(60)]
			var r := _diff(a[k], b[k], "%s.%s" % [path, str(k)])
			if r != "":
				return r
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: 길이 %d ≠ %d" % [path, a.size(), b.size()]
		for i: int in a.size():
			var r := _diff(a[i], b[i], "%s[%d]" % [path, i])
			if r != "":
				return r
		return ""
	if a != b:
		return "%s: %s ≠ %s" % [path, String.num(a, 17), String.num(b, 17)] if a is float else "%s: %s ≠ %s" % [path, str(a).left(80), str(b).left(80)]
	return ""


func _compare(sa: CityState, sb: CityState) -> String:
	var ja := _clean(sa)
	var jb := _clean(sb)
	if JSON.stringify(ja, "", false, true) == JSON.stringify(jb, "", false, true):
		return ""
	var d := _diff(ja, jb, "state")
	return d if d != "" else "JSON 글이 다름(경로 못 찾음)"


# ------------------------------------------------------------------ 한 씨앗
func run_seed(seed_v: int, days: float, every: int) -> String:
	rs = (seed_v * 2654435761 + 12345) & 0xffffffff
	houses_first = seed_v % 2 == 1
	trail.clear()
	var A := Sim.new()
	A.setup(DB)
	var B := Sim.new()
	B.setup(DB)
	B.no_cache = true
	var sa := CityState.new()
	var sb := CityState.new()
	A.now_unix = 5_000_000
	B.now_unix = 5_000_000
	A.new_game(sa, seed_v)
	B.new_game(sb, seed_v)
	sa.last_saved_unix = A.now_unix
	sb.last_saved_unix = B.now_unix
	var bot: Bot = Bot.new(A, "balanced") if seed_v % 2 == 0 else null
	var sims := [A, B]
	var sts := [sa, sb]
	var end_days := sa.econ_days + days
	var since := 0
	var step_n := 0
	var unlocked_all := false
	while sa.econ_days < end_days - 1e-9:
		# 명령 0~3개
		var nc := ri(4)
		if step_n < 8:
			nc = 3        # 처음에는 칠하기·짓기를 많이
		for _k: int in nc:
			var cmd := _gen(A, sa, step_n, unlocked_all)
			if cmd.is_empty():
				continue
			if cmd["name"] == "debug" and cmd["args"].get("op", "") == "unlock_all":
				unlocked_all = true
			var r := _both(sims, sts, cmd)
			if r != "":
				return "명령 결과 다름 %s — %s | 최근: %s" % [str(cmd).left(120), r, str(trail.slice(-6))]
		# 봇 손길(씨앗 짝수): 괜찮은 플레이어의 명령을 A에서 받아 B에 그대로 넣는다 — 승급·층 해금까지 가게
		if bot != null and ri(3) == 0:
			bot.recorded = []
			bot.act(sa)
			sb.flags["bot"] = (sa.flags.get("bot", {}) as Dictionary).duplicate(true)
			for rec: Array in bot.recorded:
				var rb: Dictionary = B.apply(sb, rec[0], (rec[1] as Dictionary).duplicate(true))
				var ra: Dictionary = rec[2]
				counts["bot." + str(rec[0])] = int(counts.get("bot." + str(rec[0]), 0)) + (1 if ra.get("ok", false) else 0)
				trail.append("bot %s%s" % [rec[0], str(rec[1]).left(50)])
				if bool(ra.get("ok", false)) != bool(rb.get("ok", false)) or str(ra.get("reason", "")) != str(rb.get("reason", "")):
					return "봇 명령 결과 다름 %s %s — %s / %s" % [rec[0], str(rec[1]).left(80), str(ra).left(100), str(rb).left(100)]
			sa.events.clear()
			sb.events.clear()
			if trail.size() > 60:
				trail = trail.slice(-40)
		# 특수 동작
		var roll := ri(100)
		if roll < 3:
			sts = _reload(sts)
			sa = sts[0]
			sb = sts[1]
			trail.append("저장→불러오기")
			counts["~reload"] = int(counts.get("~reload", 0)) + 1
		elif roll < 5:
			var sec := 600 + ri(20000)
			for i: int in 2:
				(sims[i] as Sim).now_unix += sec
				(sims[i] as Sim).catch_up(sts[i], (sims[i] as Sim).now_unix)
			trail.append("catch_up %d초" % sec)
			counts["~catch_up"] = int(counts.get("~catch_up", 0)) + 1
		# 스텝 진행
		var k := 1 + ri(8)
		var secs: Array = []
		for _s: int in k:
			secs.append(12 + ri(2))
		for i: int in 2:
			var sm: Sim = sims[i]
			var st: CityState = sts[i]
			for s: int in k:
				sm.now_unix += int(secs[s])
				sm.tick(st, sm.step_days)
				st.events.clear()
		step_n += k
		since += k
		if since >= every:
			since = 0
			var d := _compare(sa, sb)
			if d != "" and d.begins_with("state.buildings.i:") and OS.get_environment("FUZZ_DUMP") != "":
				var bid := int(d.substr(18).split(".")[0])
				print("A: ", JSON.stringify(sa.buildings.get(bid, {}), "", false, true))
				print("B: ", JSON.stringify(sb.buildings.get(bid, {}), "", false, true))
			if d != "":
				return "%.3f일(스텝 %d)에서 다름: %s | 최근: %s" % [sa.econ_days, step_n, d, str(trail.slice(-8))]
	var d2 := _compare(sa, sb)
	if d2 != "":
		return "끝에서 다름: %s" % d2
	return "ok (%.1f일, 건물 %d, 인구 %d, 층 %d, ₩%d)" % [sa.econ_days, sa.buildings.size(), sa.population(), sa.floors_unlocked, int(sa.money)]


func _both(sims: Array, sts: Array, cmd: Dictionary) -> String:
	var ra: Dictionary = (sims[0] as Sim).apply(sts[0], cmd["name"], (cmd["args"] as Dictionary).duplicate(true))
	var rb: Dictionary = (sims[1] as Sim).apply(sts[1], cmd["name"], (cmd["args"] as Dictionary).duplicate(true))
	(sts[0] as CityState).events.clear()
	(sts[1] as CityState).events.clear()
	var ok := bool(ra.get("ok", false))
	if ok:
		var key := str(cmd["name"]) + ("." + str(cmd["args"].get("op", "")) if cmd["name"] == "debug" else "")
		counts[key] = int(counts.get(key, 0)) + 1
	trail.append("%s%s%s" % [cmd["name"], str(cmd["args"]).left(60), "" if ok else "✗"])
	if trail.size() > 40:
		trail.pop_front()
	if ok != bool(rb.get("ok", false)) or str(ra.get("reason", "")) != str(rb.get("reason", "")):
		return "%s / %s" % [str(ra).left(100), str(rb).left(100)]
	return ""


func _reload(sts: Array) -> Array:
	var out: Array = []
	for st: CityState in sts:
		var n := CityState.new()
		n.from_json(st.to_json())
		out.append(n)
	return out


# ------------------------------------------------------------------ 무작위 명령(지금 상태로 유효한 쪽으로 기울여)
func _gen(sim: Sim, st: CityState, step_n: int, unlocked_all: bool) -> Dictionary:
	var w := ri(100)
	if houses_first and step_n < 48:
		if w < 80:
			return _zone(sim, st)
		return {"name": "debug", "args": {"op": "add_money", "n": float(200 + ri(800))}}
	if not unlocked_all and step_n > 30 and ri(40) == 0:
		return {"name": "debug", "args": {"op": "unlock_all"}}
	if w < 22:
		return _zone(sim, st)
	if w < 42:
		return _build(sim, st)
	if w < 50:
		return _demolish(st, ri(3) == 0)
	if w < 56:
		var f := _facs(st)
		if f.is_empty():
			return {}
		var b: Dictionary = pick(f)
		return {"name": "pause", "args": {"bid": int(b["id"]), "on": not bool(b.get("paused", false))}}
	if w < 62:
		return _upgrade(sim, st)
	if w < 68:
		return _contract(sim, st)
	if w < 76:
		var goods: Array = sim.db.get("goods", {}).get("items", {}).keys()
		var n := 5.0 + float(ri(120))
		if ri(3) == 0:
			n = -float(ri(400))     # 재고를 빼서 바닥나게
		return {"name": "debug", "args": {"op": "add_stock", "good": pick(goods), "n": n}}
	if w < 80:
		return {"name": "debug", "args": {"op": "add_money", "n": float(200 + ri(5000))}}
	if w < 84:
		var pols: Array = sim.items("policies").keys()
		return {"name": "policy_set", "args": {"id": pick(pols), "on": ri(2) == 0}}
	if w < 87:
		if ri(4) == 0:
			return {"name": "research_cancel", "args": {}}
		return {"name": "research_start", "args": {"id": pick(sim.items("research").keys())}}
	if w < 93:
		return _expedition(sim, st)
	if w < 96:
		var z := ri(st.floors_unlocked)
		return {"name": "debug", "args": {"op": "fill_floor", "z": z, "tier": 1 + ri(2), "count": 3 + ri(20), "full": ri(2) == 0}}
	if w < 98:
		return {"name": "debug", "args": {"op": "reveal_partners"}}
	return _demolish(st, true)


func _facs(st: CityState) -> Array:
	var out: Array = []
	for b: Dictionary in st.buildings.values():
		if b["kind"] == "facility":
			out.append(b)
	return out


func _zone(sim: Sim, st: CityState) -> Dictionary:
	var z := ri(st.floors_unlocked)
	var cells: Array = []
	var shape := ri(3)
	var x0 := ri(sim.W)
	var y0 := ri(sim.H)
	if shape == 0:      # 사각형
		var w := 1 + ri(5)
		var h := 1 + ri(5)
		for x: int in range(x0, mini(sim.W, x0 + w)):
			for y: int in range(y0, mini(sim.H, y0 + h)):
				cells.append(Vector3i(x, y, z))
	elif shape == 1:    # 줄
		var n := 2 + ri(10)
		for i: int in n:
			cells.append(Vector3i(mini(sim.W - 1, x0 + i), y0, z) if ri(2) == 0 else Vector3i(x0, mini(sim.H - 1, y0 + i), z))
	else:               # 흩어진 칸
		for i: int in 1 + ri(8):
			cells.append(Vector3i(ri(sim.W), ri(sim.H), z))
	# 무작위 순서
	for i: int in range(cells.size() - 1, 0, -1):
		var j := ri(i + 1)
		var t: Variant = cells[i]
		cells[i] = cells[j]
		cells[j] = t
	return {"name": "zone", "args": {"cells": cells}}


func _build(sim: Sim, st: CityState) -> Dictionary:
	var types: Array = []
	for id: String in sim.items("buildings"):
		if id != "house" and sim.is_unlocked(st, id):
			types.append(id)
	if types.is_empty():
		return {}
	var type: String = pick(types)
	for _i: int in 12:
		var p := Vector3i(ri(sim.W), ri(sim.H), ri(st.floors_unlocked))
		if bool(sim.can(st, "build", {"type": type, "pos": p}).get("ok", false)):
			return {"name": "build", "args": {"type": type, "pos": p}}
	return {"name": "build", "args": {"type": type, "pos": Vector3i(ri(sim.W), ri(sim.H), 0)}}


func _demolish(st: CityState, fac: bool) -> Dictionary:
	var c: Array = []
	for b: Dictionary in st.buildings.values():
		if (b["kind"] != "house") == fac:
			c.append(b)
	if c.is_empty():
		return {}
	var b: Dictionary = pick(c)
	return {"name": "demolish", "args": {"pos": b["pos"]}}


func _upgrade(sim: Sim, st: CityState) -> Dictionary:
	var by_t := {}
	for b: Dictionary in st.buildings.values():
		if b["kind"] == "house" and bool(b.get("ready", false)) and b.get("upgrading") == null:
			var t := int(b["tier"])
			if not by_t.has(t):
				by_t[t] = []
			by_t[t].append(int(b["id"]))
	if by_t.is_empty():
		return {}
	var t: int = pick(by_t.keys())
	var lst: Array = by_t[t]
	var bids: Array = lst.slice(0, 1 + ri(lst.size()))
	var mats: Array = sim.db.get("upgrade_costs", {}).get("materials", [])
	return {"name": "upgrade", "args": {"bids": bids, "material": pick(mats)}}


func _contract(sim: Sim, st: CityState) -> Dictionary:
	if not st.contracts.is_empty() and ri(3) == 0:
		return {"name": "contract_cancel", "args": {"id": int((pick(st.contracts) as Dictionary)["id"])}}
	var offers: Array = []
	for oid: String in sim.items("partners"):
		if st.partners.has(str(sim.item("partners", oid).get("partner", ""))):
			offers.append(oid)
	if offers.is_empty():
		return {}
	var oid: String = pick(offers)
	return {"name": "contract_sign", "args": {"offer": oid, "size": ri((sim.item("partners", oid).get("sizes", []) as Array).size())}}


func _expedition(sim: Sim, st: CityState) -> Dictionary:
	for t: Dictionary in st.teams:
		if t["state"] == "done":
			return {"name": "expedition_claim", "args": {"team": int(t["id"])}}
	var idle: Array = []
	for t: Dictionary in st.teams:
		if t["state"] == "idle":
			idle.append(t)
	if idle.is_empty():
		return {}
	var known: Array = []
	for d: String in st.dests:
		if bool((st.dests[d] as Dictionary).get("known", false)):
			known.append(d)
	if known.is_empty():
		return {}
	return {"name": "expedition_send", "args": {"team": int((pick(idle) as Dictionary)["id"]), "dest": pick(known), "provision": ri(2) == 0}}
