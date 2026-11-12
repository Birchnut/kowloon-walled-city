extends SceneTree
var n := 0
func _init() -> void:
	root.add_child.call_deferred((load("res://scenes/Main.tscn") as PackedScene).instantiate())
func _process(_d: float) -> bool:
	n += 1
	var d: Node = root.get_node("/root/Sfx").director
	if d.build_done and not has_meta("p"):
		set_meta("p", 1)
		var s: Dictionary = d.debug_state()
		print("built at frame ", n, " busy ", s["build_ms"], " max frame ", s["max_frame_ms"], " at ", s["max_frame_at"])
	return n >= 400
