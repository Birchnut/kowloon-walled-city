extends SceneTree
## make_v05 — v0.5 최종 확인용 상태 스냅샷(통합 담당). 봇이 지은 도시에 조직·창고를 더하고 시계를 민력 17년 겨울 가까이까지 돌린다.
##   godot --headless --path godot -s res://tools/fixtures/make_v05.gd
## 결과: res://tools/fixtures/v05_mid.json (12일) · v05_late.json (40일 + 조직·창고) · v05_last.json (41.2일, 마지막 장 직전)

const OUT := "res://tools/fixtures/"


func _init() -> void:
	var db := SimIO.load_db()
	var sim := Sim.new()
	sim.setup(db)
	sim.now_unix = 1_800_000_000
	var bot := Bot.new(sim, "balanced")
	var st := CityState.new()
	sim.new_game(st, 7)
	var hour := 1.0 / 24.0
	var real_per_hour := float(sim.cfg("time.seconds_per_day", 600.0)) / 24.0
	var acc := 0.0
	var plan := [["v05_mid", 12.0], ["v05_late", 40.0], ["v05_last", 41.2]]
	for p: Array in plan:
		while st.econ_days < float(p[1]):
			bot.act(st)
			acc += real_per_hour
			sim.now_unix += int(acc)
			acc -= float(int(acc))
			sim.tick(st, hour)
			st.events.clear()
		if p[0] == "v05_late":
			sim.apply(st, "debug", {"op": "unlock_all"})
			sim.apply(st, "debug", {"op": "add_money", "n": 60000})
			for g: String in ["wood", "metal", "concrete", "scrap", "parts"]:
				sim.apply(st, "debug", {"op": "add_stock", "good": g, "n": 200})
			# 봇 도시는 아래 네 층이 꽉 차 있다 → 위 두 층에 두고, 2층(z2)은 시설 하나를 허물어 자리를 만든다
			_put(sim, st, "gambling_den", 5)
			_clear_one(sim, st, 2)
			_put(sim, st, "callcenter", 2)
			_put(sim, st, "warehouse_small", 5)
			_put(sim, st, "warehouse", 4)
			_put(sim, st, "warehouse_big", 4)
			st.events.clear()
		var f := FileAccess.open(OUT + str(p[0]) + ".json", FileAccess.WRITE)
		f.store_string(st.to_json())
		f.close()
		var h: Dictionary = sim.query(st, "hud", {})
		print("== ", p[0], " day ", st.day, " pop ", h.get("pop"), " floors ", st.floors_unlocked, " money ", int(st.money), " date ", h.get("date", {}).get("date_text"))
	sim.systems.clear()
	quit(0)


func _put(sim: Sim, st: CityState, type: String, z: int) -> void:
	for y in 16:
		for x in 16:
			var pos := Vector3i(x, y, z)
			for rot in [0, 1]:
				var c: Variant = sim.can(st, "build", {"type": type, "pos": pos, "rot": rot})
				if c is Dictionary and bool(c.get("ok", false)):
					var r: Variant = sim.apply(st, "build", {"type": type, "pos": pos, "rot": rot})
					print("  put ", type, " z", z, " ", pos, " ", r.get("ok") if r is Dictionary else r)
					return
	print("  자리 없음 ", type, " z", z)


## z층의 시설(주거 아님) 하나를 허문다(자리 만들기). 위가 비어 있어 받침 값은 들지 않는다.
func _clear_one(sim: Sim, st: CityState, z: int) -> void:
	for b: Dictionary in st.buildings.values():
		if str(b.get("kind", "")) == "facility" and (b["pos"] as Vector3i).z == z:
			var r: Variant = sim.apply(st, "demolish", {"pos": b["pos"]})
			print("  demolish ", b["type"], " ", b["pos"], " ", r.get("ok") if r is Dictionary else r)
			if r is Dictionary and bool(r.get("ok", false)):
				return
