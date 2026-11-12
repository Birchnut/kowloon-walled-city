extends SceneTree
## 자동 플레이 몇 판의 맞은 곳·나간 이유를 찍는다: -s res://tests/run_diag.gd -- profile=average runs=10
const RB = preload("res://expedition/run_batch.gd")
func _initialize() -> void:
	var prof := "average"
	var runs := 10
	for a in OS.get_cmdline_user_args():
		if a.begins_with("profile="): prof = a.substr(8)
		if a.begins_with("runs="): runs = int(a.substr(5))
	var tot := {}
	for k in runs:
		var r: Dictionary = RB.run_one(prof, 1 + k, 1.0 / 30.0)
		print("%s seed=%d %s(%s) t=%.0f bosshp=%d@%.0f hp=%d rooms=%d depth=%d hurt=%s kills=%s" % [prof, 1 + k, r["outcome"], r["leave_reason"], r["time"], r["hp_at_boss"], r["time_at_boss"], r["hp"], r["rooms_visited"], r["max_depth"], r["hurt_log"], r["kills"]])
		for h in r["hurt_log"]:
			tot[h] = int(tot.get(h, 0)) + int(r["hurt_log"][h])
	print("total hurt: ", tot)
	quit()
