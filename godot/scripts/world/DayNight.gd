class_name DayNight
extends Node
## DayNight — Clock.time_of_day(0..1) 를 Gradient 로 색조화해 CanvasModulate 와 하늘 배경에 적용.
## 그라디언트 색은 config.json day_night.* (PLACEHOLDER). 핫리로드 시 재생성.

@export var modulate_node: CanvasModulate
@export var sky_node: ColorRect

var _tint: Gradient
var _sky: Gradient


func _ready() -> void:
	_rebuild()
	EventBus.data_reloaded.connect(_rebuild)
	EventBus.time_scrubbed.connect(func(_t): _apply())


func _rebuild() -> void:
	_tint = DataLoader.gradient_from_array(Data.cfg("day_night/gradient", []))
	_sky = DataLoader.gradient_from_array(Data.cfg("day_night/sky", []))
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	var t: float = Clock.time_of_day
	if modulate_node and _tint:
		modulate_node.color = _tint.sample(t)
	if sky_node and _sky:
		sky_node.color = _sky.sample(t)
