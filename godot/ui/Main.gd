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
