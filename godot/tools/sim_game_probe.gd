extends Node
## Game 오토로드가 UI 없이 부팅되는지 본다: godot --headless --path godot res://tools/sim_game_probe.tscn  (KOWLOON_NOSAVE=1)
func _ready() -> void:
	var g: Node = get_node("/root/Game")
	var data: Node = get_node("/root/Data")
	print("data errors: ", data.errors, " sim errors: ", g.sim.errors)
	print("zone: ", g.cmd("zone", {"cells": [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)]}).get("ok"))
	print("build: ", g.cmd("build", {"type": "stall", "pos": Vector3i(1, 1, 0)}).get("ok"))
	var events := {}
	g.event.connect(func(n: String, _p: Dictionary) -> void: events[n] = int(events.get(n, 0)) + 1)
	g.speed = 600.0   # 1초 = 1경제일
	await get_tree().create_timer(1.2).timeout
	var hud: Dictionary = g.query("hud")
	print("hud day ", hud["day"], " pop ", hud["pop_total"], " money ", int(hud["money"]), " now_unix>0 ", g.sim.now_unix > 0)
	print("events ", events)
	for q: String in ["build_menu", "economy", "contracts", "expeditions", "research", "policies", "goals", "offline_summary", "upgradable"]:
		print(q, " -> ", typeof(g.query(q)) != TYPE_NIL)
	print("PROBE OK")
	get_tree().quit()
