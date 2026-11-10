extends SceneTree
## make_fixtures — UI 스크린샷용 상태 스냅샷을 만든다(UI 담당 소유, 규칙 없음: 봇·디버그 명령만 쓴다).
##   godot --headless --path godot -s res://tools/fixtures/make_fixtures.gd -- [dump]
## 결과: res://tools/fixtures/{early,mid,late}.json  (+ dump면 각 질의 모양을 stdout으로)

const OUT := "res://tools/fixtures/"


func _init() -> void:
	var dump := "dump" in OS.get_cmdline_user_args()
	var db := SimIO.load_db()
	var plan := [["early", 2], ["mid", 10], ["late", 40]]
	for p: Array in plan:
		var sim := Sim.new()
		sim.setup(db)
		sim.now_unix = 1_800_000_000
		var bot := Bot.new(sim, "balanced")
		var st := CityState.new()
		sim.new_game(st, 7)
		var hour := 1.0 / 24.0
		# 실제 시계도 ×1 접속처럼 함께 흐른다(경제 1시간 = 실제 25초) → 탐험이 돌아오고 팀·목적지·연구·목표가 상태에 든다
		var real_per_hour := float(sim.cfg("time.seconds_per_day", 600.0)) / 24.0
		var acc := 0.0
		while st.econ_days < float(p[1]):
			bot.act(st)
			acc += real_per_hour
			sim.now_unix += int(acc)
			acc -= float(int(acc))
			sim.tick(st, hour)
			st.events.clear()
		if p[0] == "late":
			sim.apply(st, "debug", {"op": "add_money", "n": 5000})
			for g: String in ["wood", "metal", "concrete"]:
				sim.apply(st, "debug", {"op": "add_stock", "good": g, "n": 60})
			st.events.clear()
		var f := FileAccess.open(OUT + str(p[0]) + ".json", FileAccess.WRITE)
		f.store_string(st.to_json())
		f.close()
		st.last_saved_unix = sim.now_unix
		var g: Dictionary = sim.query(st, "goals", {})
		var h: Dictionary = sim.query(st, "hud", {})
		print("== ", p[0], " day ", st.day, " pop ", st.population(), " ", h.get("pop"), " floors ", st.floors_unlocked, " money ", int(st.money),
			" goals ", g.get("done_count"), "/", g.get("total"), " teams ", st.teams.size(), " research ", st.research.get("done", {}).size())
		if dump:
			_dump(sim, st)
		sim.systems.clear()
	quit(0)


func _dump(sim: Sim, st: CityState) -> void:
	var house := -1
	var fac := -1
	for b: Dictionary in st.buildings.values():
		if b["kind"] == "house" and house < 0:
			house = int(b["id"])
		if b["kind"] == "facility" and fac < 0:
			fac = int(b["id"])
	var qs := {"hud": {}, "build_menu": {}, "economy": {}, "contracts": {}, "expeditions": {}, "goals": {}, "research": {}, "policies": {},
		"upgradable": {}, "log": {"n": 5}, "info_house": {"bid": house}, "info_fac": {"bid": fac}}
	for q: String in qs:
		var name := q.split("_")[0] if q.begins_with("info") else q
		var r: Variant = sim.query(st, name, qs[q])
		var s := JSON.stringify(r, " ")
		print("--- ", q, "\n", s.substr(0, 3500))
	print("--- can zone ", sim.can(st, "zone", {"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]}))
	print("--- can build ", sim.can(st, "build", {"type": "stall", "pos": Vector3i(5, 5, 1)}))
	print("--- range ", sim.query(st, "range_preview", {"type": "stall", "pos": Vector3i(5, 5, 0)}))
	var ups: Array = sim.query(st, "upgradable", {})
	if not ups.is_empty():
		print("--- upgrade_preview ", JSON.stringify(sim.query(st, "upgrade_preview", {"bids": ups[0]["bids"], "material": "wood"}), " "))
