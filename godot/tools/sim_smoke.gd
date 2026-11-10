extends SceneTree
## 개발용 연기 시험: 데이터를 읽고 며칠 돌려 본다. godot --headless --path godot -s res://tools/sim_smoke.gd


func _init() -> void:
	var db := SimIO.load_db()
	var sim := Sim.new()
	sim.setup(db)
	var state := CityState.new()
	sim.new_game(state, 1)
	print(sim.apply(state, "plant", {"facility": "garden", "pos": Vector3i(5, 8, 0)}))
	for i: int in 240 * 5:
		sim.tick(state, 0.1)
		state.events.clear()
		if i % 240 == 239:
			var m := sim.metrics(state)
			print("day ", state.day, " pop ", m["population"], " hh ", m["households"], " wait ", m["waiting"], " cells ", m["cells"],
				" money ", snappedf(state.money, 0.1), " food ", snappedf(state.food, 0.1), " mat ", snappedf(state.materials, 0.1),
				" morale ", snappedf(state.morale, 0.1))
			sim.apply(state, "collect", {})
	for l: Dictionary in state.logbook:
		print("  [", l["day"], "] ", l["text"])
	print(sim.query(state, "cell_info", {"pos": Vector3i(5, 8, 0)}))
	quit()
