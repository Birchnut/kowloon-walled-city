extends SceneTree
## 질의 탐침(개발용): godot --headless --path godot -s res://tools/q_probe.gd -- q=expeditions[,research…] [load=mid] [dbg=unlock_all]
func _init() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	await process_frame
	var game: Node = root.get_node("Game")
	if args.has("load"):
		var s := CityState.new()
		if s.from_json(FileAccess.get_file_as_string("res://tools/fixtures/%s.json" % args["load"])):
			game.replace_state(s)
	for op: String in str(args.get("dbg", "")).split(",", false):
		print("dbg ", op, " ", game.cmd("debug", {"op": op}))
	for q: String in str(args.get("q", "hud")).split(","):
		print("=== ", q)
		print(JSON.stringify(game.query(q), "  "))
	quit()
