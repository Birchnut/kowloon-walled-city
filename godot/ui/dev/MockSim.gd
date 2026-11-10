class_name MockSim
extends Sim
## MockSim — UI 개발용 가짜 시뮬. 계약(docs/ARCHITECTURE.md)의 질의·명령·이벤트를 전부 흉내 낸다.
## 숫자와 규칙은 전부 지어낸 것이며 진짜 게임과 무관하다. UISandbox 에서만 쓴다.
##
##   Game.sim = MockSim.new(); Game.sim.setup(Data.files); Game.new_game()
##   (Game.sim as MockSim).preset(Game.state, "mid")     # 조금 자란 도시

const GRID := 12
const MAX_FLOORS := 10

const FAC := {
	"garden": {"money": 0, "materials": 5},
	"scrapyard": {"money": 10, "materials": 0},
	"stall": {"money": 15, "materials": 5},
	"well": {"money": 30, "materials": 10},
	"water_tank": {"money": 40, "materials": 20, "lock": "인구 20명부터. 올릴 물이 있어야 탱크도 있다."},
	"kitchen": {"money": 25, "materials": 10},
	"generator": {"money": 120, "materials": 40},
	"clinic": {"money": 80, "materials": 20, "lock": "돌봄을 '공동부조'로 정하면 의사가 온다. 면허는 안 온다."},
	"shrine": {"money": 50, "materials": 15},
	"watch_post": {"money": 60, "materials": 20, "lock": "악명 20부터. 지킬 게 생겨야 지킨다."},
	"hall": {"money": 100, "materials": 30, "lock": "인구 40명부터."},
}
const STARTERS := ["garden", "scrapyard", "stall"]

const POLICIES := [
	{"axis": "ind_farm", "name": "농업", "default": "allow", "options": [
		{"id": "ban", "name": "금지", "desc": "화분도 뽑는다. 볕은 빨래가 차지한다."},
		{"id": "allow", "name": "허가", "desc": "옥상마다 상추와 파. 식량이 느리게 는다."},
		{"id": "push", "name": "장려", "desc": "농사꾼이 몰려온다. 옥상이 남아나지 않는다."}]},
	{"axis": "ind_make", "name": "제조", "default": "allow", "options": [
		{"id": "ban", "name": "금지", "desc": "조용하다. 가난하게 조용하다."},
		{"id": "allow", "name": "허가", "desc": "망치 소리와 자재. 이웃은 귀마개를 산다."},
		{"id": "push", "name": "장려", "desc": "공장이 방을 밀어낸다. 돈은 된다."}]},
	{"axis": "ind_fun", "name": "오락", "default": "ban", "options": [
		{"id": "ban", "name": "금지", "desc": "밤이 일찍 끝난다."},
		{"id": "allow", "name": "허가", "desc": "국숫집, 찻집, 마작방. 현금이 돈다."},
		{"id": "push", "name": "장려", "desc": "네온이 늘고 잠이 준다. 악명이 따라온다."}]},
	{"axis": "ind_vice", "name": "음성", "default": "ban", "options": [
		{"id": "ban", "name": "금지", "desc": "금지한다고 없어지진 않는다. 안 보일 뿐."},
		{"id": "allow", "name": "눈감기", "desc": "간판 없는 가게가 생긴다. 수입은 장부에 안 남는다."},
		{"id": "push", "name": "장려", "desc": "돈이 쏟아진다. 호칭은 윗선이 정해 준다.", "locked": true, "lock_hint": "뒷골목 금고가 먼저 차야 한다."}]},
	{"axis": "intake", "name": "입주", "default": "anyone", "options": [
		{"id": "anyone", "name": "누구나", "desc": "오는 대로 받는다. 일 못 하는 사람도 온다."},
		{"id": "capacity", "name": "여력만큼", "desc": "먹일 수 있는 만큼만. 문 앞에 줄이 선다."},
		{"id": "workers", "name": "일꾼 우선", "desc": "손 멀쩡한 사람부터. 민심이 식는다."}]},
	{"axis": "care", "name": "돌봄", "default": "alone", "options": [
		{"id": "alone", "name": "각자도생", "desc": "돈이 안 든다. 아픈 사람은 알아서 아프다."},
		{"id": "mutual", "name": "공동부조", "desc": "식량이 더 든다. 할매가 애들을 본다."},
		{"id": "evict", "name": "추방", "desc": "일 못 하면 나간다. 다들 기억한다."}]},
	{"axis": "tax", "name": "세금 쓰임", "default": "build", "options": [
		{"id": "build", "name": "증축", "desc": "방이 빨리 는다. 나머지는 나중에."},
		{"id": "living", "name": "생활환경", "desc": "물, 계단, 빨랫줄. 민심이 오른다."},
		{"id": "infra", "name": "설비", "desc": "전기와 배관. 공장이 좋아한다."}]},
	{"axis": "material", "name": "자재·외관", "default": "wood", "options": [
		{"id": "wood", "name": "목재", "desc": "따뜻하고 가볍다. 불에 약하다."},
		{"id": "sheet", "name": "함석", "desc": "싸고 빠르다. 비 오면 북소리."},
		{"id": "neon", "name": "네온", "desc": "밤이 낮보다 밝다.", "locked": true, "lock_hint": "전기가 들어와야 한다."},
		{"id": "green", "name": "녹화", "desc": "외벽에 덩굴. 여름이 덜 덥다."}]},
]

const CARD_POOL := [
	{"card": "pigeon", "speaker": {"name": "복 할매", "role": "옥상 지킴이"}, "title": "옥상에 비둘기장",
		"body": "경주용이라는데, 가끔 식탁에도 오른답니다. 아랫집은 벌써 창문을 닫았습니다.",
		"choices": [{"label": "올려라", "hint": "식량 조금↑, 민심 조금↓. 옥상 한 칸이 찬다."}, {"label": "안 된다", "hint": "할매가 며칠 말을 안 한다."}]},
	{"card": "power_line", "speaker": {"name": "최 기사", "role": "전기·배선"}, "title": "옆 블록 전기를 '빌리자'",
		"body": "전봇대가 담장 바로 너머에 있습니다. 선 하나만 넘기면 됩니다. 들키면 제가 한 걸로 하죠.",
		"choices": [{"label": "넘겨라", "hint": "전기가 들어온다. 악명↑."}, {"label": "발전기를 사자", "hint": "돈 80. 시끄럽지만 떳떳하다."}, {"label": "아직은 촛불로", "hint": "아무 일도 없다. 밤은 어둡다."}]},
	{"card": "loan", "speaker": {"name": "린 언니", "role": "마작방"}, "title": "급전 좀 돌려도 될까",
		"body": "패 돌리다 보면 돈 급한 사람이 꼭 나와요. 이자는 좀 세게, 장부는 제가 씁니다.",
		"choices": [{"label": "모른 척한다", "hint": "뒷골목 금고가 찬다. 악명↑."}, {"label": "하지 마라", "hint": "민심↑. 린 언니 수입↓."}]},
	{"card": "stairs", "speaker": {"name": "3층 사람들", "role": "주민 일동"}, "title": "계단이 하나 더 필요합니다",
		"body": "지금은 남의 집 부엌을 지나야 올라갑니다. 부엌 주인이 통행료를 받기 시작했습니다.",
		"choices": [{"label": "자재를 내준다", "hint": "자재 10. 민심↑."}, {"label": "통행료도 장사다", "hint": "민심↓. 누군가는 돈을 번다."}]},
	{"card": "dentist", "speaker": {"name": "닥터 강", "role": "면허 미상"}, "title": "치과를 열겠습니다",
		"body": "본토 면허는 있습니다. 여기 건 없습니다. 값은 바깥의 삼분의 일. 마취는 됩니다, 대체로.",
		"choices": [{"label": "간판을 달아라", "hint": "수입↑, 악명 조금↑. 바깥 손님이 온다."}, {"label": "조용히 해라", "hint": "간판 없이 영업한다. 수입은 반."}, {"label": "다른 데 가서", "hint": "닥터 강이 떠난다."}]},
]

const FLAVOR := [
	["빨랫줄이 하나 더 걸렸다.", ""],
	["누가 계단에 화분을 내놨다.", "good"],
	["3층에서 싸움이 났다. 마작 때문이라고 한다.", "warn"],
	["비가 샌다는 민원. 늘 샌다.", ""],
	["고양이가 한 마리 늘었다. 주인은 없다.", ""],
	["국숫집 김이 4층 창문까지 올라온다.", ""],
	["담장 밖에서 누가 안을 한참 들여다보고 갔다.", "warn"],
]

var _growth_acc: float = 0.0
var _flavor_acc: float = 0.0


# ------------------------------------------------------------------ 새 게임 / 프리셋
func new_game(state: CityState, seed_value: int) -> void:
	state.rng_seed = seed_value
	state.rng_state = seed_value
	state.day = 1
	state.hour = float(cfg("time.start_hour", 6))
	state.money = 40
	state.food = 20
	state.materials = 15
	state.morale = 50
	for p in POLICIES:
		state.policies[p["axis"]] = p["default"]
	state.identity = {"title": "대장", "epithet": "", "tags": []}
	state.flags["first_anchor_done"] = false
	state.add_log("비 내리는 빈터에 들어섰다.", "")
	state.emit("day_started", {"day": state.day})


## 테스트용 도시. "mid" = 며칠 자란 도시, "tall" = 층이 많은 도시.
func preset(state: CityState, name: String) -> void:
	if name == "" or name == "empty":
		return
	var tall := name == "tall"
	state.day = 9 if not tall else 21
	state.hour = 14.3
	state.money = 1240
	state.food = 86
	state.materials = 42
	state.prestige = 62
	state.notoriety = 18
	state.morale = 44
	state.alley_fund = 37
	state.flags["first_anchor_done"] = true
	state.identity = {"title": "대장", "epithet": "어묵 냄새 나는 함석 미궁", "tags": ["어묵", "함석", "마작", "텃밭", "고물"]}
	state.policies["ind_fun"] = "allow"
	var anchors := [[Vector3i(4, 5, 0), "stall"], [Vector3i(7, 6, 0), "scrapyard"], [Vector3i(5, 8, 0), "garden"], [Vector3i(8, 3, 0), "well"]]
	for a in anchors:
		_put(state, a[0], "facility", a[1], "wood")
		_add_point(state, a[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 46 if not tall else 120
	var guard := 0
	while n > 0 and guard < 4000:
		guard += 1
		var a: Array = anchors[rng.randi() % anchors.size()]
		var x: int = clampi(int(a[0].x) + rng.randi_range(-2, 2), 0, GRID - 1)
		var y: int = clampi(int(a[0].y) + rng.randi_range(-2, 2), 0, GRID - 1)
		var h := state.column_height(Vector2i(x, y))
		if h >= (5 if not tall else 9):
			continue
		var kind := "housing"
		var type: String = ["shack", "room", "room", "flat"][rng.randi() % 4]
		if rng.randf() < 0.22:
			kind = "business"
			type = ["noodle_shop", "mahjong", "fishball", "tailor", "teahouse", "repair_shop"][rng.randi() % 6]
		_put(state, Vector3i(x, y, h), kind, type, ["scrap", "wood", "sheet", "sheet", "brick"][rng.randi() % 5])
		if kind == "housing":
			var hid := state.new_id()
			state.households[hid] = {"id": hid, "type": "laborer", "size": 1 + rng.randi() % 4, "home": Vector3i(x, y, h), "job": 0, "named": ""}
		n -= 1
	state.cells[Vector3i(6, 4, state.column_height(Vector2i(6, 4)))] = {"kind": "site", "type": "room", "material": "wood",
			"owner": 0, "built_day": state.day, "seed": 99, "progress": 0.4, "becomes": {"kind": "housing", "type": "room", "material": "wood", "owner": 0}}
	state.zones[Vector2i(2, 2)] = "keep"
	state.zones[Vector2i(2, 3)] = "keep"
	state.zones[Vector2i(3, 2)] = "keep"
	state.zones[Vector2i(9, 8)] = "work"
	state.zones[Vector2i(9, 9)] = "work"
	state.zones[Vector2i(10, 8)] = "housing"
	var ids := state.collect_points.keys()
	var fills := [0.25, 0.7, 1.0, 1.0]
	for i in ids.size():
		var cp: Dictionary = state.collect_points[ids[i]]
		cp["amount"] = float(cp["cap"]) * fills[i % fills.size()]
		if i == 3:
			cp["skimmed"] = 6.0
	state.pending_cards = []
	for i in 3:
		_push_card(state, i)
	state.logbook.clear()
	var lines := [
		[7, 9.0, "린 언니가 마작판을 폈다. 패 섞는 소리가 자정까지.", ""],
		[7, 20.5, "자릿세 31 거둠.", "good"],
		[8, 7.2, "새 가구가 들어왔다: 일꾼 셋, 노인 하나.", "good"],
		[8, 13.0, "함석 지붕이 4층까지 올라갔다.", ""],
		[8, 22.0, "안 거둔 자릿세 6을 누가 챙겼다. 누군지는 다들 안다.", "warn"],
		[9, 6.5, "어묵 공장이 문을 열었다. 위생은 묻지 말 것.", ""],
		[9, 11.0, "사람들이 이곳을 '어묵 냄새 나는 함석 미궁'이라 부르기 시작했다.", "gold"],
		[9, 13.5, "3층에서 싸움이 났다. 마작 때문이라고 한다.", "warn"],
	]
	for l in lines:
		state.logbook.append({"day": l[0], "hour": l[1], "text": l[2], "tone": l[3]})
	state.unlocked = {"garden": 1, "scrapyard": 1, "stall": 1, "well": 3, "kitchen": 5}
	state.events.clear()


func _put(state: CityState, pos: Vector3i, kind: String, type: String, material: String) -> void:
	state.cells[pos] = {"kind": kind, "type": type, "material": material, "owner": 0,
			"built_day": state.day, "seed": (pos.x * 73856093) ^ (pos.y * 19349663) ^ (pos.z * 83492791)}


func _add_point(state: CityState, pos: Vector3i) -> int:
	var id := state.new_id()
	state.collect_points[id] = {"id": id, "pos": pos, "amount": 0.0, "cap": 40.0, "skimmed": 0.0, "ready_sent": false}
	return id


func _push_card(state: CityState, i: int) -> void:
	var src: Dictionary = CARD_POOL[(i + state.day) % CARD_POOL.size()].duplicate(true)
	src["uid"] = state.new_id()
	src["day"] = state.day
	state.pending_cards.append(src)


# ------------------------------------------------------------------ 시간
func tick(state: CityState, dt_hours: float) -> void:
	var prev_hour := int(state.hour)
	state.hour += dt_hours
	while state.hour >= 24.0:
		state.hour -= 24.0
		state.emit("day_ended", {"day": state.day})
		state.day += 1
		state.emit("day_started", {"day": state.day})
		prev_hour = -1
		if state.day == 2 and not state.unlocked.has("well"):
			state.unlocked["well"] = state.day
			state.emit("unlock", {"id": "well"})
	if int(state.hour) != prev_hour:
		var h := int(state.hour)
		state.emit("hour", {"hour": h})
		if h == 20 and state.pending_cards.is_empty() and bool(state.flags.get("first_anchor_done", false)):
			for i in 3:
				_push_card(state, i)
			state.emit("cards_ready", {"count": state.pending_cards.size()})
			state.add_log("서류 세 장이 올라왔다. 결재를 기다린다.", "gold")

	# 수금함이 찬다
	for id in state.collect_points:
		var cp: Dictionary = state.collect_points[id]
		var cap := float(cp["cap"])
		var before := float(cp["amount"])
		if before < cap:
			cp["amount"] = minf(cap, before + dt_hours * 14.0)
			if not bool(cp.get("ready_sent", false)) and float(cp["amount"]) >= cap * 0.25:
				cp["ready_sent"] = true
				state.emit("collect_ready", {"point": id})
		else:
			var skim := dt_hours * 3.0
			cp["skimmed"] = float(cp.get("skimmed", 0.0)) + skim
			state.alley_fund += skim

	if not bool(state.flags.get("first_anchor_done", false)):
		return
	# 성장: 사람들이 알아서 붙는다
	_growth_acc += dt_hours
	var first_wait := 0.12 if state.households.is_empty() else 1.4
	if _growth_acc >= first_wait:
		_growth_acc = 0.0
		_grow(state)
	_flavor_acc += dt_hours
	if _flavor_acc >= 2.5:
		_flavor_acc = 0.0
		var f: Array = FLAVOR[_rand(state) % FLAVOR.size()]
		state.add_log(f[0], f[1])


func fast_forward(state: CityState, hours: float) -> Dictionary:
	tick(state, hours)
	return offline_sample(hours)


static func offline_sample(hours: float = 31.0) -> Dictionary:
	return {"hours": hours, "lines": [
		"새 가구 둘이 들어왔다. 하나는 일을 못 한다.",
		"함석 지붕이 한 층 올라갔다.",
		"안 거둔 자릿세 14를 누가 챙겼다.",
		"서류 세 장이 결재를 기다린다.",
	]}


func _rand(state: CityState) -> int:
	state.rng_state = (state.rng_state * 1103515245 + 12345) & 0x7fffffff
	return state.rng_state >> 8


func _grow(state: CityState) -> void:
	var anchors: Array = []
	for p in state.cells:
		if state.cells[p].get("kind", "") == "facility":
			anchors.append(p)
	if anchors.is_empty() or state.cells.size() > 90:
		return
	for attempt in 12:
		var a: Vector3i = anchors[_rand(state) % anchors.size()]
		var x := clampi(a.x + (_rand(state) % 3) - 1, 0, GRID - 1)
		var y := clampi(a.y + (_rand(state) % 3) - 1, 0, GRID - 1)
		var col := Vector2i(x, y)
		if state.zones.get(col, "") == "keep":
			continue
		var h := state.column_height(col)
		if h >= 4 or (x == a.x and y == a.y):
			continue
		var pos := Vector3i(x, y, h)
		var first := state.households.is_empty()
		_put(state, pos, "housing", "shack" if h == 0 else "room", "scrap" if first else str(state.policies.get("material", "wood")))
		var hid := state.new_id()
		state.households[hid] = {"id": hid, "type": "laborer", "size": 2 + _rand(state) % 3, "home": pos, "job": 0, "named": ""}
		state.emit("cell_changed", {"pos": pos})
		state.emit("household_arrived", {"id": hid})
		state.add_log("판잣집이 하나 섰다. 누가 시킨 것도 아닌데." if first else "방이 하나 늘었다.", "good" if first else "")
		return


# ------------------------------------------------------------------ 검증 / 명령
func can(state: CityState, name: String, args: Dictionary) -> Dictionary:
	match name:
		"plant":
			var fid := str(args.get("facility", ""))
			if not FAC.has(fid):
				return _no("그런 건 못 심는다.")
			var f := _facility(state, fid)
			if bool(f["locked"]):
				return _no(str(f["lock_hint"]))
			var pos: Variant = args.get("pos")
			if not (pos is Vector3i):
				return _no("자리를 골라야 한다.")
			if not _spots(state).has(pos):
				return _no("거긴 안 된다. 빈 땅이나 지붕 위에.")
			if state.zones.get(Vector2i(pos.x, pos.y), "") == "keep":
				return _no("비워 두기로 한 자리다.")
			if state.money < float(f["cost"]["money"]):
				return _no("돈이 모자란다.")
			if state.materials < float(f["cost"]["materials"]):
				return _no("자재가 모자란다.")
			return _yes()
		"zone":
			var c: Variant = args.get("col")
			if not (c is Vector2i) or c.x < 0 or c.y < 0 or c.x >= GRID or c.y >= GRID:
				return _no("부지 밖이다.")
			return _yes()
		"demolish":
			var p: Variant = args.get("pos")
			if not (p is Vector3i) or not state.cells.has(p):
				return _no("헐 게 없다.")
			if state.cells.has(p + Vector3i(0, 0, 1)):
				return _no("위에 얹힌 게 있다. 위부터 헐어야 한다.")
			return _yes()
		"policy":
			for pol in POLICIES:
				if pol["axis"] == args.get("axis", ""):
					for o in pol["options"]:
						if o["id"] == args.get("value", ""):
							if bool(o.get("locked", false)) and not bool(state.flags.get("unlock_all", false)):
								return _no(str(o.get("lock_hint", "아직 못 고른다.")))
							return _yes()
			return _no("그런 선택지는 없다.")
		"collect":
			if args.has("point"):
				var cp: Dictionary = state.collect_points.get(int(args["point"]), {})
				if cp.is_empty():
					return _no("수금함이 없다.")
				if float(cp["amount"]) < 1.0:
					return _no("아직 거둘 게 없다.")
			return _yes()
		"card":
			for cd in state.pending_cards:
				if int(cd["uid"]) == int(args.get("uid", -1)):
					return _yes()
			return _no("이미 처리한 서류다.")
		"debug":
			return _yes()
	return _no("모르는 명령: " + name)


func apply(state: CityState, name: String, args: Dictionary) -> Dictionary:
	var chk := can(state, name, args)
	if not bool(chk["ok"]):
		return chk
	match name:
		"plant":
			var fid := str(args["facility"])
			var f := _facility(state, fid)
			var pos: Vector3i = args["pos"]
			state.money -= float(f["cost"]["money"])
			state.materials -= float(f["cost"]["materials"])
			_put(state, pos, "facility", fid, "wood")
			var first := not bool(state.flags.get("first_anchor_done", false))
			state.flags["first_anchor_done"] = true
			_add_point(state, pos)
			_growth_acc = 0.0
			state.emit("cell_changed", {"pos": pos})
			state.add_log("%s 심었다." % UI.josa(str(f["name"]), "를", "을"), "good")
			if fid == "generator" and state.power_level == 0:
				state.power_level = 1
				state.emit("power_changed", {"level": 1})
				state.add_log("전기가 들어왔다. 창이 하나씩 켜진다.", "gold")
			return {"ok": true, "reason": "", "first": first}
		"zone":
			var col: Vector2i = args["col"]
			var z := str(args.get("zone", ""))
			if z == "":
				state.zones.erase(col)
			else:
				state.zones[col] = z
			state.emit("zone_changed", {"col": col})
			return _yes()
		"demolish":
			var p: Vector3i = args["pos"]
			var c: Dictionary = state.cells[p]
			state.cells.erase(p)
			for hid in state.households.keys():
				if state.households[hid].get("home") == p:
					state.households.erase(hid)
					state.emit("household_left", {"id": hid, "reason": "demolish"})
			for id in state.collect_points.keys():
				if state.collect_points[id]["pos"] == p:
					state.collect_points.erase(id)
			state.morale = maxf(0.0, state.morale - 3.0)
			state.emit("cell_changed", {"pos": p})
			state.add_log("%s 헐었다. 살던 사람들은 말이 없다." % UI.josa(_cell_name(c), "를", "을"), "bad")
			return _yes()
		"policy":
			state.policies[str(args["axis"])] = str(args["value"])
			return _yes()
		"collect":
			var ids: Array = [int(args["point"])] if args.has("point") else state.collect_points.keys()
			var total := 0.0
			var skim_total := 0.0
			for id in ids:
				var cp: Dictionary = state.collect_points.get(id, {})
				if cp.is_empty() or float(cp["amount"]) < 1.0:
					continue
				var amt := floorf(float(cp["amount"]))
				var sk := floorf(float(cp.get("skimmed", 0.0)))
				cp["amount"] = 0.0
				cp["skimmed"] = 0.0
				cp["ready_sent"] = false
				total += amt
				skim_total += sk
				state.emit("collected", {"point": id, "amount": amt, "skimmed": sk})
			state.money += total
			var out := {"ok": true, "reason": "", "amount": total, "skimmed": skim_total}
			if total > 0.0 and _rand(state) % 4 == 0:
				state.materials += 3
				out["bonus"] = "수금함 바닥에서 쓸 만한 경첩이 나왔다. 자재 +3"
			return out
		"card":
			var uid := int(args["uid"])
			var ch := int(args.get("choice", 0))
			for i in state.pending_cards.size():
				if int(state.pending_cards[i]["uid"]) == uid:
					var cd: Dictionary = state.pending_cards[i]
					state.pending_cards.remove_at(i)
					var choices: Array = cd.get("choices", [])
					var label := str(choices[ch]["label"]) if ch < choices.size() else "?"
					var res := "「%s」— %s" % [cd.get("title", ""), label]
					state.prestige = clampf(state.prestige + (2.0 if ch == 1 else -1.0), 0, 100)
					state.notoriety = clampf(state.notoriety + (3.0 if ch == 0 else 0.0), 0, 100)
					state.add_log(res, "gold")
					return {"ok": true, "reason": "", "result": "도장을 찍었다. " + label + "."}
			return _no("이미 처리한 서류다.")
		"debug":
			return _debug(state, args)
	return _no("모르는 명령")


func _debug(state: CityState, args: Dictionary) -> Dictionary:
	match str(args.get("op", "")):
		"add_money":
			state.money += float(args.get("amount", 500))
		"add_materials":
			state.materials += float(args.get("amount", 50))
		"skip_hours":
			tick(state, float(args.get("hours", 6)))
		"unlock_all":
			state.flags["unlock_all"] = true
			state.emit("unlock", {"id": "generator"})
		"rename":      # 가짜 전용: 호칭 변화 연출 확인
			state.identity["title"] = str(args.get("title", "따거"))
			state.identity["epithet"] = str(args.get("epithet", state.identity.get("epithet", "")))
			state.emit("identity_changed", {"title": state.identity["title"], "epithet": state.identity["epithet"]})
		"power":       # 가짜 전용: 첫 전기 연출 확인
			state.power_level = int(args.get("level", 1))
			state.emit("power_changed", {"level": state.power_level})
		"cards":       # 가짜 전용
			if state.pending_cards.is_empty():
				for i in 3:
					_push_card(state, i)
			state.emit("cards_ready", {"count": state.pending_cards.size()})
		"fill":        # 가짜 전용: 수금함 채우기
			for id in state.collect_points:
				state.collect_points[id]["amount"] = state.collect_points[id]["cap"]
		_:
			return _no("모르는 디버그 명령")
	return _yes()


# ------------------------------------------------------------------ 질의
func query(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"hud":
			var top := 0
			for p in state.cells:
				top = maxi(top, p.z + 1)
			return {
				"day": state.day, "hour": state.hour, "money": state.money, "food": state.food,
				"materials": state.materials, "population": state.population(),
				"prestige": state.prestige, "notoriety": state.notoriety, "morale": state.morale,
				"title": state.identity.get("title", "대장"), "epithet": state.identity.get("epithet", ""),
				"power_level": state.power_level, "cards": state.pending_cards.size(),
				# ↓ 계약에 없는 추가 필드(UI_NOTES.md '계약 요청' 참고)
				"floors": top, "tags": state.identity.get("tags", []),
			}
		"facilities":
			var out: Array = []
			for fid in FAC:
				out.append(_facility(state, fid))
			return out
		"plant_spots":
			return _spots(state)
		"policies":
			var pl: Array = []
			for p in POLICIES:
				var d: Dictionary = p.duplicate(true)
				d["value"] = state.policies.get(p["axis"], p["default"])
				d.erase("default")
				if bool(state.flags.get("unlock_all", false)):
					for o in d["options"]:
						o["locked"] = false
				pl.append(d)
			return pl
		"cell_info":
			return _mock_cell_info(state, args.get("pos"))
		"collect_points":
			var cps: Array = []
			for id in state.collect_points:
				var cp: Dictionary = state.collect_points[id]
				var cap := maxf(1.0, float(cp["cap"]))
				cps.append({"id": id, "pos": cp["pos"], "amount": cp["amount"], "cap": cap,
						"ratio": float(cp["amount"]) / cap,
						# ↓ 계약에 없는 추가 필드
						"ready": float(cp["amount"]) >= cap * 0.25, "skimming": float(cp["amount"]) >= cap})
			return cps
		"cards":
			return state.pending_cards
		"log":
			var n := int(args.get("n", 50))
			return state.logbook.slice(maxi(0, state.logbook.size() - n))
		"stats":       # 계약에 없음(요청 사항)
			return [
				{"label": "가구", "value": str(state.households.size())},
				{"label": "칸", "value": str(state.cells.size())},
				{"label": "뒷골목 금고", "value": UI.num(state.alley_fund)},
				{"label": "전기", "value": ["없음", "발전기", "외부 계약"][clampi(state.power_level, 0, 2)]},
			]
	return null


func _facility(state: CityState, fid: String) -> Dictionary:
	var it: Dictionary = {}
	var items: Variant = db.get("facilities", {}).get("items", {}) if db.get("facilities", {}) is Dictionary else {}
	if items is Dictionary and items.get(fid) is Dictionary:
		it = items[fid]
	var f: Dictionary = FAC[fid]
	var free := not bool(state.flags.get("first_anchor_done", false)) and fid in STARTERS
	var locked := f.has("lock") and not bool(state.flags.get("unlock_all", false))
	if not bool(state.flags.get("first_anchor_done", false)) and not (fid in STARTERS):
		locked = true
	return {
		"id": fid, "name": it.get("name", fid), "desc": it.get("desc", ""),
		"cost": {"money": 0 if free else f["money"], "materials": 0 if free else f["materials"]},
		"locked": locked,
		"lock_hint": f.get("lock", "먼저 먹고살 길 하나부터.") if locked else "",
		"sign": it.get("sign", ""),     # 계약에 없는 추가 필드(간판 글자)
	}


func _spots(state: CityState) -> Array:
	var out: Array = []
	for y in GRID:
		for x in GRID:
			var h := state.column_height(Vector2i(x, y))
			if h < MAX_FLOORS and h < 6:
				if h == 0 or state.cells.get(Vector3i(x, y, h - 1), {}).get("kind", "") != "site":
					out.append(Vector3i(x, y, h))
	return out


func _cell_name(c: Dictionary) -> String:
	var file := {"housing": "housing", "business": "businesses", "facility": "facilities"}.get(c.get("kind", ""), "housing") as String
	var items: Variant = db.get(file, {}).get("items", {}) if db.get(file, {}) is Dictionary else {}
	var t := str(c.get("becomes", {}).get("type", c.get("type", ""))) if c.get("kind", "") == "site" else str(c.get("type", ""))
	if items is Dictionary and items.get(t) is Dictionary:
		return str(items[t].get("name", t))
	return t


func _mock_cell_info(state: CityState, pos: Variant) -> Variant:
	if not (pos is Vector3i):
		return null
	var col := Vector2i(pos.x, pos.y)
	if not state.cells.has(pos):
		if pos.z != 0 or pos.x < 0 or pos.y < 0 or pos.x >= GRID or pos.y >= GRID:
			return null
		var z := str(state.zones.get(col, ""))
		var zn := {"housing": "주거로 그어 둠", "work": "일터로 그어 둠", "keep": "비워 두기로 함", "": "아무 선도 없음"}.get(z, z) as String
		return {"title": "빈 땅", "subtitle": "%d-%d · %s" % [pos.x + 1, pos.y + 1, zn],
				"lines": ["잡초와 깨진 타일. 아직 아무도 탐내지 않았다.", "이유를 놓으면 누군가 온다."], "actions": []}
	var c: Dictionary = state.cells[pos]
	var kind := str(c.get("kind", ""))
	var name := _cell_name(c)
	var mat := str(db.get("materials", {}).get("items", {}).get(c.get("material", ""), {}).get("name", c.get("material", "")))
	var lines: Array = []
	var sub := "%d층 · %s · %d일차에 지음" % [pos.z + 1, mat, int(c.get("built_day", 1))]
	match kind:
		"facility":
			lines.append("당신이 심었다. 여기서부터 자릿세가 걷힌다.")
			for id in state.collect_points:
				var cp: Dictionary = state.collect_points[id]
				if cp["pos"] == pos:
					lines.append("수금함: %s / %s" % [UI.num(cp["amount"]), UI.num(cp["cap"])])
					if float(cp.get("skimmed", 0.0)) >= 1.0:
						lines.append("떼인 돈: %s. 수금원은 모르는 일이라고 한다." % UI.num(cp["skimmed"]))
		"housing":
			var who := ""
			for h in state.households.values():
				if h.get("home") == pos:
					who = "%d명이 산다." % int(h.get("size", 1))
			lines.append(who if who != "" else "비어 있다. 곧 누가 든다.")
			lines.append("왜 여기에: 일터가 두 칸 옆이라서.")
		"business":
			lines.append("허가했으니까 생겼다.")
			lines.append("왜 여기에: 사람이 지나다니는 자리라서.")
		"site":
			name += " (공사 중)"
			lines.append("대나무 비계. %d%% 올라갔다." % int(float(c.get("progress", 0.0)) * 100.0))
	var actions: Array = []
	var d := can(state, "demolish", {"pos": pos})
	actions.append({"label": "헐기", "cmd": "demolish", "args": {"pos": pos}, "danger": true,
			"confirm": "%s 헌다. 살던 사람은 나간다." % UI.josa(name, "를", "을"), "enabled": d["ok"], "reason": d["reason"]})
	return {"title": name, "subtitle": sub, "lines": lines, "actions": actions}


func _yes() -> Dictionary:
	return {"ok": true, "reason": ""}


func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
