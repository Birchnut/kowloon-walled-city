extends Node
## Main — 조립만 한다: 도시 뷰 + UI.
##  - res://view/CityView.tscn 이 있으면(합친 뒤) 그걸, 없으면 자리표시자(MockView)를 끼운다.
##  - UI는 Game.query() 가 무엇에 null 을 돌려줘도 빈 화면으로 버틴다.

const VIEW_SCENE := "res://view/CityView.tscn"
const UI_SCENE := "res://ui/UIRoot.tscn"
const MOCK_VIEW := "res://ui/dev/MockView.gd"


func _ready() -> void:
	var view: Node = null
	if ResourceLoader.exists(VIEW_SCENE):
		var ps: Variant = load(VIEW_SCENE)
		if ps is PackedScene:
			view = ps.instantiate()
	if view == null and ResourceLoader.exists(MOCK_VIEW):
		view = (load(MOCK_VIEW) as GDScript).new()
	if view != null:
		view.name = "CityView"
		add_child(view)
	var ui: Node = (load(UI_SCENE) as PackedScene).instantiate()
	add_child(ui)
	# 개발용 인자(skiptut, bot=, load= …)가 있으면 몰이 도구를 붙인다. tools/DevHarness.gd 참고.
	var dev: Dictionary = DevHarnessLoader.wanted()
	if not dev.is_empty():
		var h: Node = DevHarnessLoader.make(dev, ui, view)
		add_child(h)


class DevHarnessLoader:
	const PATH := "res://tools/DevHarness.gd"

	static func wanted() -> Dictionary:
		if not ResourceLoader.exists(PATH):
			return {}
		return (load(PATH) as GDScript).call("wanted")

	static func make(dev: Dictionary, ui: Node, view: Node) -> Node:
		var h: Node = (load(PATH) as GDScript).new()
		h.set("args", dev)
		h.set("ui", ui)
		h.set("view", view)
		return h
