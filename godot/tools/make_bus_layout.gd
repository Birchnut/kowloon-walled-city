extends SceneTree
func _init() -> void:
	for b: String in ["SFX", "Ambience", "Music"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	for side: Array in [["AmbL", -0.55], ["AmbR", 0.55]]:
		if AudioServer.get_bus_index(side[0]) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, side[0])
			AudioServer.set_bus_send(i, "Ambience")
			var pan := AudioEffectPanner.new()
			pan.pan = float(side[1])
			AudioServer.add_bus_effect(i, pan)
	var err := ResourceSaver.save(AudioServer.generate_bus_layout(), "res://default_bus_layout.tres")
	print("saved ", err)
	quit()
