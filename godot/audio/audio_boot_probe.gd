extends SceneTree
## 진짜 게임(Main.tscn)을 켜고 소리 만들기가 프레임에 어떻게 나뉘는지 본다.
## KOWLOON_AUDIO_PROBE=1 godot --headless --path godot -s res://audio/audio_boot_probe.gd   (리눅스: 프레임별 CPU 도)
## 출력: 다 만든 프레임, 일한 시간 합, 한 프레임에서 가장 오래 붙잡은 시간과 그때 만들던 것, 400 프레임 뒤 배경 상태.
var n := 0


func _init() -> void:
	root.add_child.call_deferred((load("res://scenes/Main.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	n += 1
	var d: Node = root.get_node("/root/Sfx").director
	if d.build_done and not has_meta("p"):
		set_meta("p", 1)
		var s: Dictionary = d.debug_state()
		print("[audio] 다 만듦: 프레임 %d · 일한 시간 %.0f ms · 가장 긴 프레임 벽시계 %.1f ms (%s) / CPU %.1f ms (%s)" % [n, s["build_ms"], s["max_frame_ms"], s["max_frame_at"], s["max_frame_cpu_ms"], s["max_frame_cpu_at"]])
	if n == 400:
		print("[audio] ", d.debug_state())
	return n >= 400
