class_name BubbleLayer
extends Control
## BubbleLayer — 수금 말풍선 층. query("collect_points") 의 항목마다 말풍선 하나를 view.project(pos) 에 붙인다.
## 도구가 켜졌거나 단면을 보는 중에는 숨는다(set_suppressed). "모두 거두기"는 준비된 게 3개 이상일 때.
##
## 준비/떼임 판정은 질의가 주면(ready / skimming) 그걸 쓰고, 없으면 amount>=1 / ratio>=1 로 본다.

signal collect_requested(point_id: int)     # -1 = 전부
const ALL_AT := 3

var top_guard: float = 110.0        # 이 위(상단 띠)로 올라간 말풍선은 숨긴다
var bottom_guard: float = 80.0      # 하단 바
var right_guard: float = 64.0
var coin_target: Vector2 = Vector2(300, 30)
var _bubbles: Dictionary = {}       # id -> Bubble
var _pos: Dictionary = {}           # id -> Vector3i
var _suppressed: bool = false
var _all_btn: PixelButton
var _ready_count: int = 0
var _fade: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_all_btn = PixelButton.make("모두 거두기", "coin", "ButtonGold")
	_all_btn.tint_icon = false
	_all_btn.visible = false
	_all_btn.pressed.connect(func() -> void: collect_requested.emit(-1))
	add_child(_all_btn)
	resized.connect(reposition)


## points = query("collect_points") (Array). null/빈 배열이면 전부 지운다.
func sync(points: Array) -> void:
	var seen: Dictionary = {}
	_ready_count = 0
	for e in points:
		if not (e is Dictionary) or not e.has("id"):
			continue
		var id := int(e["id"])
		var amount := float(e.get("amount", 0.0))
		var ratio := float(e.get("ratio", 0.0))
		var is_ready := bool(e.get("ready", amount >= 1.0))
		if amount < 1.0 and not is_ready:
			continue          # 빈 수금함은 말풍선 없음
		seen[id] = true
		var b: Bubble = _bubbles.get(id)
		if b == null:
			b = Bubble.new()
			b.point_id = id
			b.tapped.connect(func(pid: int) -> void: collect_requested.emit(pid))
			add_child(b)
			move_child(_all_btn, -1)
			_bubbles[id] = b
		_pos[id] = e.get("pos")
		b.ratio = ratio
		b.ready_now = is_ready
		b.hot = bool(e.get("skimming", ratio >= 0.999))
		if is_ready:
			_ready_count += 1
	for id in _bubbles.keys():
		if not seen.has(id):
			(_bubbles[id] as Bubble).queue_free()
			_bubbles.erase(id)
			_pos.erase(id)
	reposition()


func reposition() -> void:
	for id in _bubbles:
		var b: Bubble = _bubbles[id]
		var p := Q.project(_pos.get(id))
		var inside := p.x > 20.0 and p.x < size.x - right_guard and p.y > top_guard + 56.0 and p.y < size.y - bottom_guard
		b.visible = inside
		if inside:
			b.anchor = p
	_all_btn.visible = _ready_count >= ALL_AT and not _suppressed
	if _all_btn.visible:
		_all_btn.reset_size()
		_all_btn.position = UI.snap(Vector2((size.x - _all_btn.size.x) * 0.5, size.y - bottom_guard - _all_btn.size.y - 10.0))


func ready_count() -> int:
	return _ready_count


func set_suppressed(v: bool) -> void:
	if v == _suppressed:
		return
	_suppressed = v
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if v:
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 0.0, 0.12)
		_fade.tween_callback(func() -> void: visible = false)
	else:
		visible = true
		reposition()
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, 0.15)


## 튜토리얼 강조용: 준비된 첫 말풍선의 화면 영역.
func first_bubble_rect() -> Rect2:
	for id in _bubbles:
		var b: Bubble = _bubbles[id]
		if b.visible:
			return Rect2(b.global_position, b.size)
	return Rect2()


func bubble_origin(id: int) -> Vector2:
	var b: Bubble = _bubbles.get(id)
	if b != null and b.visible:
		return b.coin_origin()
	return Q.project(_pos.get(id)) if _pos.has(id) else Vector2(size.x * 0.5, size.y * 0.5)


## 동전이 말풍선에서 돈 카운터로 날아간다. amount 에 따라 3~8닢.
func fly_coins(from: Vector2, amount: float, on_arrive: Callable = Callable()) -> void:
	var coin := UI.icon("coin")
	if coin == null or not is_inside_tree():
		if on_arrive.is_valid():
			on_arrive.call()
		return
	var n := clampi(int(amount / 6.0) + 3, 3, 8)
	var host: Control = get_parent() if get_parent() is Control else self
	for i in n:
		var s := TextureRect.new()
		s.texture = coin
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.z_index = 20
		host.add_child(s)
		var start := from - Vector2(12, 12)
		var burst := start + Vector2(randf_range(-34, 34), randf_range(-40, -6))
		var target := coin_target - Vector2(12, 12)
		s.position = start
		s.scale = Vector2(0.4, 0.4)
		var tw := s.create_tween()
		tw.tween_interval(i * 0.035)
		tw.tween_property(s, "position", burst, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "scale", Vector2.ONE, 0.12)
		tw.tween_interval(0.05)
		tw.tween_property(s, "position", target, 0.32 + i * 0.01).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if i == 0 and on_arrive.is_valid():
			tw.tween_callback(on_arrive)
		tw.tween_callback(s.queue_free)
