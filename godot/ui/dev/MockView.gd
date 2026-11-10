class_name MockView
extends Control
## MockView — CityView 자리표시자. 계약의 API·시그널을 전부 갖춘 납작한 아이소 그림.
## 진짜 뷰(res://view/CityView.tscn)가 없을 때 Main 이 대신 끼운다. UI 개발·스크린샷용.
## 뷰이므로 Game.state 를 읽기만 한다.

signal cell_tapped(info: Dictionary)
signal view_changed

const GRID := 12
const TW := 20.0     # 타일 반폭
const TH := 10.0     # 타일 반높이
const FH := 18.0     # 층 높이

var floor_cut: int = -1
var rot: int = 0
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var time_override: float = -1.0
var zones_on: bool = false
var spots: Array = []
var ghost: Dictionary = {}

var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _dragging: bool = false
var _t: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Game.register_view(self)
	Game.event.connect(_on_event)
	Game.state_replaced.connect(queue_redraw)
	resized.connect(_emit_changed)


func _process(delta: float) -> void:
	_t += delta
	if not spots.is_empty() or not ghost.is_empty():
		queue_redraw()


func _on_event(n: String, _p: Dictionary) -> void:
	if n in ["cell_changed", "zone_changed", "hour", "power_changed"]:
		queue_redraw()
	if n == "cell_changed":
		view_changed.emit.call_deferred()


func _emit_changed() -> void:
	queue_redraw()
	view_changed.emit()


# ------------------------------------------------------------------ CityView API
func set_floor_cut(n: int) -> void:
	floor_cut = n
	_emit_changed()


func rotate_view(dir: int) -> void:
	rot = posmod(rot + dir, 4)
	_emit_changed()


func zoom_step(dir: int) -> void:
	set_zoom(zoom + 0.25 * signf(dir))


func set_zoom(level: float) -> void:
	zoom = clampf(level, 0.5, 2.5)
	_emit_changed()


func pick(screen_pos: Vector2) -> Dictionary:
	var st: CityState = Game.state
	var cells: Array = _sorted_cells(st)
	cells.reverse()
	var tw := TW * zoom
	var th := TH * zoom
	var fh := FH * zoom
	for p in cells:
		var top := project(p)
		var d: Vector2 = screen_pos - top
		if absf(d.x) > tw:
			continue
		var edge := th * (1.0 - absf(d.x) / tw)
		if d.y >= -edge and d.y <= fh + edge:
			return {"hit": true, "pos": p, "col": Vector2i(p.x, p.y), "above": p + Vector3i(0, 0, 1)}
	# 바닥
	var o := _origin()
	var u := (screen_pos.x - o.x) / tw
	var v := (screen_pos.y - o.y) / th
	var rx := int(round((v + u) * 0.5))
	var ry := int(round((v - u) * 0.5))
	var g := _unrot(Vector2i(rx, ry))
	if g.x < 0 or g.y < 0 or g.x >= GRID or g.y >= GRID:
		return {"hit": false, "pos": Vector3i(-1, -1, 0), "col": Vector2i(-1, -1), "above": Vector3i(-1, -1, 0)}
	var gp := Vector3i(g.x, g.y, 0)
	return {"hit": true, "ground": true, "pos": gp, "col": g, "above": gp}


## 셀 윗면 가운데의 화면 좌표.
func project(pos: Vector3i) -> Vector2:
	var r := _rot(Vector2i(pos.x, pos.y))
	var o := _origin()
	return Vector2(o.x + (r.x - r.y) * TW * zoom, o.y + (r.x + r.y) * TH * zoom - float(pos.z + 1) * FH * zoom)


func show_ghost(pos: Vector3i, facility_id: String, ok: bool) -> void:
	ghost = {"pos": pos, "id": facility_id, "ok": ok}
	queue_redraw()


func show_spots(cells: Array) -> void:
	spots = cells
	queue_redraw()


func clear_overlay() -> void:
	spots = []
	ghost = {}
	queue_redraw()


func show_zones(on: bool) -> void:
	zones_on = on
	queue_redraw()


func set_time_override(t: float) -> void:
	time_override = t
	queue_redraw()


## (계약 밖, 있으면 UI가 쓴다) 지금 가장 높은 층 수.
func get_max_floor() -> int:
	var top := 0
	for p in Game.state.cells:
		top = maxi(top, p.z + 1)
	return top


# ------------------------------------------------------------------ 입력
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_pressing = true
				_dragging = false
				_press_pos = ev.position
			elif _pressing:
				_pressing = false
				if not _dragging:
					cell_tapped.emit(pick(ev.position))
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_step(1)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_step(-1)
	elif ev is InputEventMouseMotion and _pressing:
		if not _dragging and ev.position.distance_to(_press_pos) > 10.0:
			_dragging = true
		if _dragging:
			pan += ev.relative
			_emit_changed()


# ------------------------------------------------------------------ 그리기
func _origin() -> Vector2:
	var c := (GRID - 1) * 0.5
	return Vector2(size.x * 0.5, size.y * 0.52 - c * 2.0 * TH * zoom) + pan + Vector2(0, 40.0 * zoom)


func _rot(p: Vector2i) -> Vector2i:
	match rot:
		1:
			return Vector2i(p.y, GRID - 1 - p.x)
		2:
			return Vector2i(GRID - 1 - p.x, GRID - 1 - p.y)
		3:
			return Vector2i(GRID - 1 - p.y, p.x)
	return p


func _unrot(p: Vector2i) -> Vector2i:
	match rot:
		1:
			return Vector2i(GRID - 1 - p.y, p.x)
		2:
			return Vector2i(GRID - 1 - p.x, GRID - 1 - p.y)
		3:
			return Vector2i(p.y, GRID - 1 - p.x)
	return p


func _sorted_cells(st: CityState) -> Array:
	var out: Array = []
	for p in st.cells:
		if floor_cut >= 0 and p.z > floor_cut:
			continue
		out.append(p)
	out.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var ra := _rot(Vector2i(a.x, a.y))
		var rb := _rot(Vector2i(b.x, b.y))
		var da := ra.x + ra.y
		var db := rb.x + rb.y
		if da != db:
			return da < db
		if a.z != b.z:
			return a.z < b.z
		return ra.x < rb.x)
	return out


func _tod() -> float:
	return time_override if time_override >= 0.0 else Game.time_of_day()


func _daylight() -> float:
	# 0 = 한밤, 1 = 한낮
	var t := _tod()
	return clampf(sin((t - 0.25) * TAU) * 1.6 + 0.35, 0.0, 1.0)


func _diamond(c: Vector2, tw: float, th: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -th), c + Vector2(tw, 0), c + Vector2(0, th), c + Vector2(-tw, 0)])


func _draw() -> void:
	var st: CityState = Game.state
	var day := _daylight()
	var sky_top := Color("141a33").lerp(Color("8aa3b8"), day)
	var sky_bot := Color("2a2540").lerp(Color("d9c9a8"), day)
	draw_rect(Rect2(Vector2.ZERO, size), sky_top)
	var bands := 12
	for i in bands:
		var f := float(i) / float(bands - 1)
		draw_rect(Rect2(0, size.y * (0.25 + 0.75 * f / 1.0) , size.x, size.y / bands * 0.8 + 2), sky_top.lerp(sky_bot, f))
	# 먼 "합법 도시" 실루엣
	var far := sky_bot.darkened(0.25)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var x := -10.0
	while x < size.x:
		var w := rng.randf_range(18, 46)
		var h := rng.randf_range(40, 150)
		draw_rect(Rect2(x, size.y * 0.42 - h, w, h + 40), far)
		x += w + rng.randf_range(0, 6)
	draw_rect(Rect2(0, size.y * 0.42, size.x, size.y), Color("3b3a40").lerp(Color("8f8a78"), day))

	var tw := TW * zoom
	var th := TH * zoom
	var fh := FH * zoom
	var o := _origin()
	# 부지 바닥
	for gy in GRID:
		for gx in GRID:
			var r := _rot(Vector2i(gx, gy))
			var c := Vector2(o.x + (r.x - r.y) * tw, o.y + (r.x + r.y) * th)
			var base := Color("4a4a46").lerp(Color("a39d86"), day)
			if (gx + gy) % 2 == 0:
				base = base.darkened(0.06)
			draw_colored_polygon(_diamond(c, tw, th), base)
			if zones_on:
				var z := str(st.zones.get(Vector2i(gx, gy), ""))
				var zc := {"housing": Color("3fb090"), "work": Color("e8b54a"), "keep": Color("c9362e")}.get(z, Color(0, 0, 0, 0)) as Color
				if zc.a > 0.0:
					draw_colored_polygon(_diamond(c, tw * 0.92, th * 0.92), Color(zc, 0.55))
				draw_polyline(_diamond(c, tw, th) + PackedVector2Array([c + Vector2(0, -th)]), Color(1, 1, 1, 0.18), 1.0)
	# 심을 수 있는 자리
	if not spots.is_empty():
		var a := 0.35 + 0.25 * sin(_t * 5.0)
		for sp in spots:
			if sp is Vector3i and (floor_cut < 0 or sp.z <= floor_cut + 1):
				if sp.z == 0:
					var c2: Vector2 = project(sp) + Vector2(0, fh)
					draw_colored_polygon(_diamond(c2, tw * 0.6, th * 0.6), Color(UI.col("jade_hi"), a))
	# 셀
	var night := 1.0 - day
	for p in _sorted_cells(st):
		_draw_cell(p, st.cells[p], tw, th, fh, day, night, floor_cut >= 0 and p.z == floor_cut)
	if not spots.is_empty():
		var a2 := 0.45 + 0.3 * sin(_t * 5.0)
		for sp in spots:
			if sp is Vector3i and sp.z > 0 and (floor_cut < 0 or sp.z <= floor_cut + 1):
				draw_colored_polygon(_diamond(project(sp) + Vector2(0, fh), tw * 0.6, th * 0.6), Color(UI.col("jade_hi"), a2))
	# 고스트
	if not ghost.is_empty():
		var gp: Vector3i = ghost["pos"]
		var gc := UI.col("jade_hi") if bool(ghost["ok"]) else UI.col("red_hi")
		var top := project(gp)
		var al := 0.55 + 0.2 * sin(_t * 6.0)
		draw_colored_polygon(_diamond(top, tw, th), Color(gc, al))
		draw_colored_polygon(PackedVector2Array([top + Vector2(-tw, 0), top + Vector2(0, th), top + Vector2(0, th + fh), top + Vector2(-tw, fh)]), Color(gc.darkened(0.3), al))
		draw_colored_polygon(PackedVector2Array([top + Vector2(tw, 0), top + Vector2(0, th), top + Vector2(0, th + fh), top + Vector2(tw, fh)]), Color(gc.darkened(0.5), al))
	if floor_cut >= 0:
		draw_string(UI.font("small"), Vector2(10, size.y * 0.42 + 24), "단면: %d층까지" % (floor_cut + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.5))


func _draw_cell(p: Vector3i, c: Dictionary, tw: float, th: float, fh: float, day: float, night: float, open_top: bool) -> void:
	var top := project(p)
	var kind := str(c.get("kind", ""))
	var seed_v := int(c.get("seed", 0))
	var base := Color("8c7a66")
	match str(c.get("material", "")):
		"scrap":
			base = Color("7d6b58")
		"wood":
			base = Color("a8794f")
		"sheet":
			base = Color("7f93a0")
		"brick":
			base = Color("a45a48")
		"concrete":
			base = Color("9a9a94")
	if kind == "facility":
		base = Color("3f8f78")
	elif kind == "business":
		base = base.lerp(Color("c9362e"), 0.35)
	base = base.lightened(float(seed_v % 7) * 0.02)
	var lit := lerpf(0.42, 1.0, day)
	var c_top := (base.lightened(0.18) * lit)
	var c_l := (base * lit)
	var c_r := (base.darkened(0.25) * lit)
	c_top.a = 1.0
	c_l.a = 1.0
	c_r.a = 1.0
	if kind == "site":
		# 공사 중: 대나무 비계
		var bc := Color("d8c06a")
		for i in 3:
			var yy := fh * float(i) / 2.0
			draw_line(top + Vector2(-tw, yy), top + Vector2(0, th + yy), bc, 1.0)
			draw_line(top + Vector2(tw, yy), top + Vector2(0, th + yy), bc, 1.0)
		for xx in [-tw, 0.0, tw]:
			draw_line(top + Vector2(xx, (th if xx == 0.0 else 0.0)), top + Vector2(xx, (th if xx == 0.0 else 0.0) + fh), bc, 1.0)
		return
	draw_colored_polygon(PackedVector2Array([top + Vector2(-tw, 0), top + Vector2(0, th), top + Vector2(0, th + fh), top + Vector2(-tw, fh)]), c_l)
	draw_colored_polygon(PackedVector2Array([top + Vector2(tw, 0), top + Vector2(0, th), top + Vector2(0, th + fh), top + Vector2(tw, fh)]), c_r)
	if open_top:
		# 단면: 천장을 열고 방 안(어두운 바닥)을 보여 준다
		draw_colored_polygon(_diamond(top, tw, th), c_l.darkened(0.2))
		draw_colored_polygon(_diamond(top + Vector2(0, fh * 0.55), tw * 0.8, th * 0.8), Color("2a2430"))
	else:
		draw_colored_polygon(_diamond(top, tw, th), c_top)
	# 창
	var win_on := night > 0.45 and (seed_v % 3 != 0) and (Game.state.power_level > 0 or seed_v % 4 == 1)
	var wc := Color("ffd27a") if win_on else Color(0.08, 0.09, 0.14, 0.75)
	var s := maxf(2.0, round(3.0 * zoom))
	draw_rect(Rect2(top + Vector2(-tw * 0.62, fh * 0.42), Vector2(s, s + 1)), wc)
	draw_rect(Rect2(top + Vector2(tw * 0.38, fh * 0.42), Vector2(s, s + 1)), wc)
	if kind == "facility":
		draw_rect(Rect2(top + Vector2(-3, -th * 0.5 - 6), Vector2(6, 6)), Color("ffe08a"))
	elif kind == "business":
		draw_rect(Rect2(top + Vector2(-tw * 0.9, fh * 0.15), Vector2(s + 1, fh * 0.5)), Color("e2574a") if night < 0.45 else Color("ff7a8a"))
