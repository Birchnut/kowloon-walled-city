extends SceneTree
## 직접 줍기 스크립트를 전부 불러 문법 오류만 확인한다.
func _initialize() -> void:
	for f in ["RunCfg", "DungeonGen", "RunActor", "RunInput", "RunWorld", "RunArt", "RunView", "RunHud", "RunMenus", "RunSfx", "AutoPlayer", "CityLink", "RunScript", "RunSandbox"]:
		var s: Script = load("res://expedition/%s.gd" % f)
		print(f, " ", "ok" if s != null and s.can_instantiate() else "FAIL")
	quit()
