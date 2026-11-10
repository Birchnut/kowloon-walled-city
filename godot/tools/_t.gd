extends SceneTree
func _init():
	var sim := Sim.new()
	sim.setup(SimIO.load_db())
	print("errors ", sim.errors)
	var st := CityState.new()
	sim.now_unix = 1000000
	sim.new_game(st, 3)
	print(sim.apply(st, "build", {"type": "expedition_base", "pos": Vector3i(0,0,0)}))
	sim.tick(st, 0.1)
	print(sim.query(st, "expeditions")["teams"])
	print(sim.can(st, "expedition_send", {"team": 1, "dest": "furniture_alley"}))
	print(sim.apply(st, "expedition_send", {"team": 1, "dest": "furniture_alley", "provision": true}))
	print(sim.apply(st, "expedition_claim", {}))
	sim.now_unix += 299
	print(sim.query(st, "expeditions")["teams"])
	sim.now_unix += 1
	sim.tick(st, 0.05)
	print(sim.query(st, "hud")["teams_done"])
	print(sim.apply(st, "expedition_claim", {}))
	print(sim.apply(st, "expedition_claim", {}))
	var q = sim.query(st, "expeditions")
	for d in q["dests"]: print(d["id"], " ", d["known"], " ", d["per_hour"], " ", d["bonus_text"])
	print(q["provision"])
	sim.systems.clear()
	quit()
