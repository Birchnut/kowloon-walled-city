extends SceneTree
## 던전 생성 결과를 글자 지도로 찍는다: godot --headless --path godot -s res://tests/run_gen_dump.gd -- seed=3
const DungeonGen = preload("res://expedition/DungeonGen.gd")
const RunCfg = preload("res://expedition/RunCfg.gd")

func _initialize() -> void:
	var seed_v := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			seed_v = int(a.substr(5))
	var g := DungeonGen.new()
	var d := g.generate(seed_v, RunCfg.file("run_goods")["sample_begin"]["stock"].duplicate(), 2)
	var ch := " .#CBTKjw=,~d_"
	var marks := {}
	for o in d["objects"]:
		var m := {"pile": "P", "throwable": "t", "rat": "r", "dog": "D", "guard": "G", "rival": "S", "exit": "X", "start": "@", "boss": "Q"}
		if m.has(o["type"]):
			marks[o["cell"]] = m[o["type"]]
	for y in d["h"]:
		var line := ""
		for x in d["w"]:
			var c := Vector2i(x, y)
			line += marks[c] if marks.has(c) else ch[d["tiles"][y * d["w"] + x]]
		if line.strip_edges() != "":
			print(line)
	for r in d["rooms"]:
		print(r["id"], " ", r["tmpl"], " depth=", r["depth"], " main=", r["main"], " links=", r["links"])
	print("stock_left=", d["stock_left"], " big=", d["big"])
	print(g.log_lines)
	quit()
