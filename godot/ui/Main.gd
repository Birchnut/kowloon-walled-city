extends Node
## Main — 조립만 한다: 도시 뷰(view/CityView.tscn) + UI(ui/UIRoot.tscn) + (개발 인자가 있으면) DevHarness.
## UI는 Game.query() 가 무엇에 빈 값을 돌려줘도 빈 화면으로 버틴다.

const VIEW_SCENE := "res://view/CityView.tscn"
const UI_SCENE := "res://ui/UIRoot.tscn"
const HARNESS := "res://tools/DevHarness.gd"


func _ready() -> void:
	var view: Node = null
	if ResourceLoader.exists(VIEW_SCENE):
		var ps: Variant = load(VIEW_SCENE)
		if ps is PackedScene:
			view = ps.instantiate()
			view.name = "CityView"
			add_child(view)
	var ui: Node = (load(UI_SCENE) as PackedScene).instantiate()
	add_child(ui)
	# 개발용 인자(skiptut, load=, open= …)가 있으면 몰이 도구를 붙인다. tools/DevHarness.gd 참고.
	if ResourceLoader.exists(HARNESS):
		var script: GDScript = load(HARNESS)
		var dev: Dictionary = script.call("wanted")
		if not dev.is_empty():
			var h: Node = script.new()
			h.set("args", dev)
			h.set("ui", ui)
			h.set("view", view)
			add_child(h)
