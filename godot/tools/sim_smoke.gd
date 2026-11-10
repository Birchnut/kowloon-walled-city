extends SceneTree
## 개발용 연기 시험: godot --headless --path godot -s res://tools/sim_smoke.gd


func _init() -> void:
	var db := SimIO.load_db()
	var sim := Sim.new()
	sim.setup(db)
	print("data errors: ", sim.errors)
	var state := CityState.new()
	sim.new_game(state, 1)
	var cells: Array = []
	for x: int in 4:
		for y: int in 3:
			cells.append(Vector3i(x, y, 0))
	print(sim.apply(state, "zone", {"cells": cells}))
	print(sim.apply(state, "build", {"type": "stall", "pos": Vector3i(5, 1, 0)}))
	print(sim.apply(state, "build", {"type": "rain_catcher", "pos": Vector3i(5, 2, 0)}))
	print(sim.apply(state, "build", {"type": "garden", "pos": Vector3i(5, 0, 0)}))
	for d: int in 3:
		sim.tick(state, 1.0)
		state.events.clear()
		print("day ", state.day, " pop ", state.population(), " money ", snappedf(state.money, 0.1), " stock ", state.stock, " hap ", state.happiness)
	print(sim.query(state, "hud"))
	print(sim.query(state, "info", {"pos": Vector3i(0, 0, 0)}))
	for l: Dictionary in state.logbook:
		print("  ", l["day"], " ", l["text"])
	sim.systems.clear()
	quit()
