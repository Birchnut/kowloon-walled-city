extends Node
func _ready() -> void:
	var g: Node = get_node("/root/Game")
	print("can plant: ", g.can("plant", {"facility": "garden", "pos": Vector3i(5, 8, 0)}))
	print("plant: ", g.cmd("plant", {"facility": "garden", "pos": Vector3i(5, 8, 0)}).get("ok"))
	g.speed = 2000.0
	await get_tree().create_timer(1.0).timeout
	var hud: Dictionary = g.query("hud")
	print("hud day ", hud["day"], " pop ", hud["population"], " cells ", g.state.cells.size(), " offline_h(8h) ", g.offline_game_hours(8 * 3600.0), " offline_h(99h) ", g.offline_game_hours(99 * 3600.0))
	print("facilities ", (g.query("facilities") as Array).size(), " policies ", (g.query("policies") as Array).size(), " points ", (g.query("collect_points") as Array).size())
	get_tree().quit()
