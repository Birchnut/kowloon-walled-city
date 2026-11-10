extends SceneTree
## sim_test — 시뮬 계층 헤드리스 시험.  실행: godot/tests/sim_test.sh  (또는 godot --headless --path godot -s res://tests/sim_test.gd)
##  1 결정론        같은 씨앗 + 같은 봇 → 마지막 상태의 지문이 같다
##  2 저장/불러오기  도중에 JSON으로 저장 → 새 Sim에 불러와 이어 돌린 결과 = 저장한 쪽을 계속 돌린 결과 = 저장 없이 돌린 결과
##  3 불변식(매일)   허공에 뜬 셀 없음 / 비운 터에 셀 없음 / 집 있는 가구의 집이 실제 주거 셀 / 사업체의 셀·일꾼이 실제로 있음 /
##                  재고가 NaN·음수 아님(돈은 허용된 빚까지) / 지표 0..100 / 수금함이 앵커 위에 있음
##  4 시스템 끄기    config.systems에서 하나씩 빼고 5일치 틱 → 오류 없이 돌고 불변식 유지
##  5 미접속        fast_forward는 셀을 하나도 바꾸지 않는다(요약 줄은 나온다)
## 스크립트 오류는 GDScript 안에서 잡을 수 없으므로 sim_test.sh가 출력의 "SCRIPT ERROR"를 실패로 친다.

const Run := preload("res://tools/sim_run.gd")

var fails: Array = []


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var db := SimIO.load_db()
	_determinism(db)
	_round_trip(db)
	_disable_each(db)
	_fast_forward(db)
	print("")
	if fails.is_empty():
		print("SIM TEST: ALL PASS (%.1f초)" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	else:
		print("SIM TEST: %d FAIL" % fails.size())
		for f: String in fails:
			print("  - ", f)
	quit(0 if fails.is_empty() else 1)


func _ok(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", label])
	if not cond:
		fails.append(label)


func _start(db: Dictionary, bot_id: String, seed_value: int) -> Array:
	var sim := Sim.new()
	sim.setup(db)
	var state := CityState.new()
	sim.new_game(state, seed_value)
	return [sim, Bot.new(sim, bot_id), state]


## 불변식 위반 목록(비면 통과).
func _violations(sim: Sim, state: CityState) -> Array:
	var bad: Array = []
	for pos: Vector3i in state.cells:
		var c: Dictionary = state.cells[pos]
		if not Grid.supported(state, pos):
			bad.append("허공에 뜬 셀 %s" % pos)
		if state.zones.get(Vector2i(pos.x, pos.y), "") == "keep":
			bad.append("비운 터에 셀 %s" % pos)
		if pos.z < 0 or pos.z >= sim.F or not Grid.inside(sim, pos.x, pos.y):
			bad.append("부지 밖 셀 %s" % pos)
		if c.get("kind", "") == "housing":
			if (c.get("residents", []) as Array).size() > Ops.capacity(sim, c):
				bad.append("정원 초과 %s" % pos)
			for id: int in c.get("residents", []):
				if not state.households.has(id) or state.households[id].get("home") != pos:
					bad.append("거주자 장부 불일치 %s" % pos)
	for id: int in state.households:
		var h: Dictionary = state.households[id]
		var home: Variant = h.get("home")
		if home != null and (state.cells.get(home, {}).get("kind", "") != "housing" or not (id in state.cells[home].get("residents", []))):
			bad.append("가구 %d의 집이 주거 셀이 아님" % id)
		var job := int(h.get("job", 0))
		if job != 0 and (not state.businesses.has(job) or not (id in state.businesses[job]["workers"])):
			bad.append("가구 %d의 일터 불일치" % id)
	for bid: int in state.businesses:
		var b: Dictionary = state.businesses[bid]
		for pos: Vector3i in b["cells"]:
			if not (state.cells.get(pos, {}).get("kind", "") in ["business", "facility"]):
				bad.append("사업체 %d의 셀이 없음 %s" % [bid, pos])
		for w: int in b["workers"]:
			if not state.households.has(w) or int(state.households[w].get("job", 0)) != bid:
				bad.append("사업체 %d의 일꾼 불일치" % bid)
	for p: Dictionary in state.collect_points.values():
		if state.cells.get(p["pos"], {}).get("kind", "") != "facility":
			bad.append("앵커 없는 수금함 %s" % p["pos"])
	var debt := float(sim.tune("economy.max_debt", 200.0)) + 400.0
	for f: String in ["money", "food", "materials", "alley_fund", "prestige", "notoriety", "morale"]:
		var v := float(state.get(f))
		if is_nan(v) or is_inf(v) or (f != "money" and v < -1e-6) or (f == "money" and v < -debt):
			bad.append("재고 이상 %s = %s" % [f, v])
	for f: String in ["prestige", "notoriety", "morale"]:
		if float(state.get(f)) > 100.0001:
			bad.append("지표 범위 밖 %s" % f)
	return bad


func _days(sim: Sim, bot: Bot, state: CityState, until_day: int, label: String) -> void:
	while state.day <= until_day:
		Run.advance_day(sim, bot, state)
		var bad := _violations(sim, state)
		if not bad.is_empty():
			fails.append("%s: %d일 불변식 — %s" % [label, state.day - 1, ", ".join(bad.slice(0, 3))])
			print("  [FAIL] 불변식 ", label, " d", state.day - 1, " ", bad.slice(0, 3))
			return


func _determinism(db: Dictionary) -> void:
	print("1 결정론")
	for bot_id: String in ["merchant", "absent"]:
		var hashes: Array = []
		for i: int in 2:
			var r := _start(db, bot_id, 7)
			_days(r[0], r[1], r[2], 9, "결정론 " + bot_id)
			hashes.append(Run.state_hash(r[2]))
		_ok(hashes[0] == hashes[1], "%s 9일 × 2회 지문 일치 (%s)" % [bot_id, str(hashes[0]).substr(0, 8)])
	var a := _start(db, "merchant", 7)
	var b := _start(db, "merchant", 8)
	_days(a[0], a[1], a[2], 4, "씨앗 7")
	_days(b[0], b[1], b[2], 4, "씨앗 8")
	_ok(Run.state_hash(a[2]) != Run.state_hash(b[2]), "씨앗이 다르면 결과도 다르다")


func _round_trip(db: Dictionary) -> void:
	print("2 저장/불러오기 왕복 + 3 불변식(매일)")
	for bot_id: String in ["farmer", "merchant"]:
		var a := _start(db, bot_id, 3)
		_days(a[0], a[1], a[2], 6, "왕복A " + bot_id)
		var saved: String = (a[2] as CityState).to_json()
		_days(a[0], a[1], a[2], 11, "왕복A " + bot_id)
		var sim_b := Sim.new()
		sim_b.setup(db)
		var state_b := CityState.new()
		_ok(state_b.from_json(saved), "%s 저장본을 읽는다 (%d바이트)" % [bot_id, saved.length()])
		_days(sim_b, Bot.new(sim_b, bot_id), state_b, 11, "왕복B " + bot_id)
		var c := _start(db, bot_id, 3)
		_days(c[0], c[1], c[2], 11, "왕복C " + bot_id)
		_ok(Run.state_hash(a[2]) == Run.state_hash(state_b), "%s 6일에 저장 → 불러와 11일까지 = 저장한 쪽을 계속 돌린 것" % bot_id)
		_ok(Run.state_hash(a[2]) == Run.state_hash(c[2]), "%s 저장을 한 번도 안 한 것과도 같다" % bot_id)
		_ok((a[2] as CityState).cells.size() > 30, "%s 11일에 셀 %d칸(시험이 빈 도시를 돌린 게 아님)" % [bot_id, (a[2] as CityState).cells.size()])


func _disable_each(db: Dictionary) -> void:
	print("4 시스템을 하나씩 끄고 5일")
	var all: Array = db["config"]["systems"]
	for off: String in all:
		var db2: Dictionary = db.duplicate()
		db2["config"] = (db["config"] as Dictionary).duplicate(true)
		db2["config"]["systems"] = all.filter(func(s: String) -> bool: return s != off)
		var r := _start(db2, "merchant", 5)
		var sim: Sim = r[0]
		var bot: Bot = r[1]
		var state: CityState = r[2]
		for i: int in 5 * 192:
			if i % 8 == 0:
				bot.act(state)
				sim.query(state, "hud", {})
				sim.query(state, "cell_info", {"pos": Vector3i(5, 9, 0)})
				sim.query(state, "facilities", {})
				sim.query(state, "policies", {})
				sim.query(state, "collect_points", {})
			sim.tick(state, 0.125)
			state.events.clear()
		var ff: Dictionary = sim.fast_forward(state, 30.0)
		var bad := _violations(sim, state)
		var days_ok: bool = state.day >= 6 or off == "clock"
		_ok(bad.is_empty() and days_ok and ff.has("lines"), "%s 없이: %d일째, 셀 %d, 가구 %d%s" % [off, state.day, state.cells.size(),
			state.households.size(), "" if bad.is_empty() else " — " + str(bad.slice(0, 2))])


func _fast_forward(db: Dictionary) -> void:
	print("5 미접속(fast_forward)")
	var r := _start(db, "merchant", 2)
	var sim: Sim = r[0]
	var state: CityState = r[2]
	_days(sim, r[1], state, 6, "미접속 준비")
	var cells_before := JSON.stringify(CityState._enc(state.cells), "", false)
	var homes_before := {}
	for id: int in state.households:
		homes_before[id] = state.households[id].get("home")
	var day := state.day
	var cards := state.pending_cards.size()
	var budget := float(state.flags["growth"]["budget"])
	var ff: Dictionary = sim.fast_forward(state, 72.0)
	_ok(JSON.stringify(CityState._enc(state.cells), "", false) == cells_before, "72시간 빨리감기 뒤 셀이 글자 하나 안 바뀜 (%d칸)" % state.cells.size())
	var moved := 0
	for id: int in homes_before:
		if state.households.has(id) and state.households[id].get("home") != homes_before[id]:
			moved += 1
	_ok(moved == 0 and state.households.size() >= homes_before.size(), "아무도 이사하거나 떠나지 않음(줄만 길어짐: %d → %d가구)" % [homes_before.size(), state.households.size()])
	_ok(state.day == day + 3, "도시 시간은 3일 흐름")
	_ok(state.pending_cards.size() >= cards and state.pending_cards.size() <= int(sim.num("cards.max_pending", 9)), "결재는 상한까지만 쌓임 (%d → %d)" % [cards, state.pending_cards.size()])
	_ok(float(state.flags["growth"]["budget"]) >= budget, "건축 품은 쓰이지 않고 쌓임 (%.1f → %.1f)" % [budget, float(state.flags["growth"]["budget"])])
	_ok((ff.get("lines", []) as Array).size() >= 2, "요약 %d줄: %s" % [(ff["lines"] as Array).size(), " / ".join(ff["lines"])])
	_ok(_violations(sim, state).is_empty(), "빨리감기 뒤 불변식 유지")
	(r[0] as Sim).systems.clear()
