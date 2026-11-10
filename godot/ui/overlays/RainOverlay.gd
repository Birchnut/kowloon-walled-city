class_name RainOverlay
extends Control
## RainOverlay — 오프닝의 비. 화면을 잿빛으로 누르고 빗줄기를 긋는다. 표석("九龍城寨")도 여기서 띄운다.
## 뷰에 날씨가 없어서(MVP 제외) UI 층에서 싸게 흉내 낸다. 터치를 먹지 않는다.

const DROPS := 70

var _amount: float = 0.0       # 0 맑음 … 1 비
var _target: float = 0.0
var _drops: PackedVector3Array = PackedVector3Array()   # x, y, 속도
var _stone: PanelContainer = null
var _stone_tw: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in DROPS:
		_drops.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.7, 1.3)))


func set_rain(on: bool, instant: bool = false) -> void:
	_target = 1.0 if on else 0.0
	if instant:
		_amount = _target
	set_process(true)
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	_amount = move_toward(_amount, _target, delta * 0.8)
	for i in _drops.size():
		var d := _drops[i]
		d.y += delta * 1.5 * d.z
		d.x -= delta * 0.25 * d.z
		if d.y > 1.05:
			d.y -= 1.1
			d.x = fposmod(d.x + 0.37, 1.0)
		if d.x < -0.05:
			d.x += 1.1
		_drops[i] = d
	queue_redraw()
	if _amount <= 0.0 and _target <= 0.0:
		set_process(false)
		visible = _stone != null


func _draw() -> void:
	if _amount <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.19, 0.25, 0.5 * _amount))
	var c := Color(0.75, 0.82, 0.9, 0.5 * _amount)
	for d in _drops:
		var p := UI.snap(Vector2(d.x * size.x, d.y * size.y))
		var len: float = 10.0 * d.z
		# 픽셀 계단 빗줄기(2px씩)
		for k in int(len / 2.0):
			draw_rect(Rect2(p + Vector2(-k * 1.0, k * 2.0).snapped(Vector2(2, 2)), Vector2(2, 2)), c)


## 표석을 띄운다/거둔다.
func show_stone(on: bool) -> void:
	if on and _stone == null:
		_stone = UI.panel("PanelPlaqueInk")
		_stone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := UI.vbox(-6)
		_stone.add_child(v)
		for g in ["九", "龍", "城", "寨"]:
			var l := UI.label(g, "LabelStone")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(l)
		add_child(_stone)
		_stone.reset_size()
		_stone.position = UI.snap(Vector2((size.x - _stone.size.x) * 0.5, maxf(120.0, size.y * 0.16)))
		_stone.modulate.a = 0.0
		visible = true
		_stone_tw = create_tween()
		_stone_tw.tween_property(_stone, "modulate:a", 1.0, 0.9)
	elif not on and _stone != null:
		var s := _stone
		_stone = null
		if _stone_tw != null and _stone_tw.is_valid():
			_stone_tw.kill()
		var tw := create_tween()
		tw.tween_property(s, "modulate:a", 0.0, 0.5)
		tw.tween_callback(s.queue_free)
