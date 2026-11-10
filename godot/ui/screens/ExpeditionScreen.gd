class_name ExpeditionScreen
extends Screen


func set_area(_top: float, _bar: float) -> void:
	pass


func target_rect(_t: String) -> Rect2:
	return Rect2()
var source: Callable = func() -> Dictionary: return Q.dict("expeditions")
