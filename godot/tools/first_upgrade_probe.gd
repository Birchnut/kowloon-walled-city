extends SceneTree
## 첫 승급 탐침(개발용): 새 게임에서 교역·초 공방 없이 시작 재고만으로 첫 세입자 승급이 되는지 본다.
## godot --headless --path godot -s res://tools/first_upgrade_probe.gd
func _init() -> void:
	await process_frame
	var game: Node = root.get_node("Game")
	game.paused = true
	var cells: Array = []
	for x: int in 4:
		for y: int in 2:
			cells.append(Vector3i(x + 2, y + 2, 0))
	print("zone ", game.cmd("zone", {"cells": cells}).get("ok"))
	for b: Array in [["stall", Vector3i(6, 2, 0)], ["rain_catcher", Vector3i(6, 3, 0)], ["rain_catcher", Vector3i(6, 4, 0)], ["garden", Vector3i(2, 4, 0)], ["garden", Vector3i(3, 4, 0)]]:
		var r: Dictionary = game.cmd("build", {"type": b[0], "pos": b[1]})
		print("build ", b[0], " ", r.get("ok"), " ", r.get("reason", ""))
	for step: int in 12:
		game.sim.tick(game.state, 0.25)
		var hud: Dictionary = game.query("hud")
		var up: Variant = game.query("upgradable")
		var n := 0
		if up is Dictionary:
			n = int((up as Dictionary).get("count", ((up as Dictionary).get("bids", []) as Array).size()))
		elif up is Array:
			n = (up as Array).size()
		print("day %.2f pop %s money %d upgradable %d stock oldclothes %.1f candle %.1f" % [game.state.econ_days, str(hud.get("pop", hud.get("population", "?"))), int(game.state.money), n, float(game.state.stock.get("oldclothes", 0)), float(game.state.stock.get("candle", 0))])
		if n > 0:
			var bid := -1
			for c: Vector3i in cells:
				var info: Dictionary = game.query("info", {"pos": c})
				if info.get("upgradable", false):
					bid = int(info.get("bid", -1))
					break
			var r2: Dictionary = game.cmd("upgrade", {"bids": [bid], "material": "wood"})
			print("upgrade ", r2.get("ok"), " ", r2.get("reason", ""))
			game.sim.tick(game.state, 0.25)
			print("goal now: ", (game.query("hud") as Dictionary).get("next_goal", {}).get("text", ""))
			break
	quit()
