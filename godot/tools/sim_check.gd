extends SceneTree
## 개발용: sim 스크립트가 전부 컴파일되는지 본다.


func _init() -> void:
	var bad := 0
	for dir_path: String in ["res://sim", "res://sim/systems", "res://tests", "res://core"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for f: String in dir.get_files():
			if f.ends_with(".gd") and f != "sim_check.gd":
				var s: Variant = load("%s/%s" % [dir_path, f])
				if s == null or not (s as GDScript).can_instantiate():
					bad += 1
					print("FAIL ", dir_path, "/", f)
	print("check done, bad=", bad)
	quit(1 if bad > 0 else 0)
