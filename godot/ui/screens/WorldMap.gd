class_name WorldMap
extends Control
## WorldMap — 탐험 지도(UI 층에서 직접 그리는 픽셀 지도). 값은 전부 query("expeditions") 그대로.
##  가운데 성채, 거리 띠 세 개(근·중·원), 목적지는 질의의 map[x,y](0..1) 자리에. 지형 힌트는 목적지의 주력 자재로 고른 그림
##  (목재 = 철거 골목의 판재, 철제 = 고철 야적장, 콘크리트 = 공사장 블록, 고물 = 부두, 설비 부품 = 옛 발전소 굴뚝).
##  모르는 곳은 안개와 "?"(locked_hint). 길은 점선, 나간 팀은 seconds_left/total_seconds 만큼 길 위를 걷는다.
##  focus_good: 고른(부족한) 자재를 주는 곳을 비취색으로 맥박, 나머지는 흐리게.

signal dest_pressed(id: String)

const PX := 2.0

var dests: Array = []
var teams: Array = []
var selected: String = ""
var focus_good: String = ""
var _t: float = 0.0
var _hits: Array = []           # [{rect, id}]
var _deco_seed: int = 7


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func set_data(d: Array, t: Array) -> void:
	dests = d
	teams = t
	queue_redraw()


func center() -> Vector2:
	return (size * 0.5).floor()


func dest_point(d: Dictionary) -> Vector2:
	var m := UI.to_array(d.get("map", [0.5, 0.5]))
	var mx := float(m[0]) if m.size() > 0 else 0.5
	var my := float(m[1]) if m.size() > 1 else 0.5
	var pad := Vector2(40, 44)
	return (pad + Vector2(mx, my) * (size - pad * 2.0)).snapped(Vector2(PX, PX))


func dest_rect(id: String) -> Rect2:
	for h: Dictionary in _hits:
		if h["id"] == id:
			var r: Rect2 = h["rect"]
			return Rect2(global_position + r.position, r.size)
	return Rect2()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		for h: Dictionary in _hits:
			if (h["rect"] as Rect2).has_point(ev.position):
				dest_pressed.emit(h["id"])
				accept_event()
				return
		dest_pressed.emit("")
		accept_event()


# ------------------------------------------------------------------ 그리기
func _draw() -> void:
	_hits.clear()
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("1c1a22"))
	_ground()
	var c := center()
	var unit := minf(size.x, size.y)
	# 거리 띠(점선 원)
	var bands := [[0.2, "근거리 · 몇 분"], [0.33, "중거리 · 한 시간쯤"], [0.47, "원거리 · 몇 시간"]]
	for b: Array in bands:
		_dotted_circle(c, unit * float(b[0]), Color(UI.col("dim"), 0.35))
		var f := UI.font("small")
		var fs := UI.font_size("small")
		var tp := c + Vector2(-f.get_string_size(b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, -unit * float(b[0]) + 4.0 + f.get_ascent(fs))
		_text(tp, b[1], UI.col("mute"))
	# 길
	for d: Variant in dests:
		if d is Dictionary and bool(d.get("known", true)):
			_dotted_line(c, dest_point(d), Color(UI.col("paper3"), 0.45 if not _is_focus(d) else 0.9))
	# 목적지 장식 → 표지
	for d: Variant in dests:
		if d is Dictionary:
			_deco(d)
	for d: Variant in dests:
		if d is Dictionary:
			_marker(d)
	_fortress(c)
	# 팀
	for tm: Variant in teams:
		if tm is Dictionary:
			_team(tm, c)


func _ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _deco_seed
	# 흙·자갈 점
	for i in int(size.x * size.y / 900.0):
		var p := Vector2(rng.randi_range(0, int(size.x / PX)), rng.randi_range(0, int(size.y / PX))) * PX
		draw_rect(Rect2(p, Vector2(PX, PX)), Color("2a2730") if rng.randf() < 0.7 else Color("34303a"))
	# 바다(오른쪽 아래 귀퉁이) — 부두 쪽
	var sea := Color("17304a")
	for y in range(int(size.y * 0.62), int(size.y), int(PX)):
		var w := (float(y) - size.y * 0.62) * 0.9 + 20.0 + sin(float(y) * 0.08) * 6.0
		draw_rect(Rect2(size.x - w, y, w, PX), sea)
	for i in 30:
		var y2 := rng.randf_range(size.y * 0.7, size.y)
		var x2 := size.x - rng.randf_range(4.0, (y2 - size.y * 0.62) * 0.8)
		draw_rect(Rect2(Vector2(x2, y2).snapped(Vector2(PX, PX)), Vector2(PX * 3, PX)), Color("2b4f6e"))
	# 언덕(위쪽)
	for i in 6:
		var hx := rng.randf_range(0.0, size.x)
		var hw := rng.randf_range(60.0, 140.0)
		var hh := rng.randf_range(14.0, 30.0)
		for k in range(0, int(hh), int(PX)):
			var ww := hw * (1.0 - float(k) / hh)
			draw_rect(Rect2(Vector2(hx - ww * 0.5, 18.0 + hh - k).snapped(Vector2(PX, PX)), Vector2(ww, PX)), Color("2c3328"))
	# 큰길 두 줄(성채에서 바깥으로)
	var c := center()
	draw_rect(Rect2(0, c.y - PX, size.x, PX * 2), Color("25222b"))
	draw_rect(Rect2(c.x - PX, 0, PX * 2, size.y), Color("25222b"))


func _fortress(c: Vector2) -> void:
	var s := 52.0
	var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
	draw_rect(r.grow(4), UI.col("out"))
	draw_rect(r.grow(2), Color("6b5f4a"))
	draw_rect(r, Color("3b3640"))
	# 덩어리 지붕들
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 14:
		var w := rng.randi_range(6, 14) * 2.0
		var h := rng.randi_range(5, 12) * 2.0
		var p := r.position + Vector2(rng.randi_range(0, int((s - w) / 2)), rng.randi_range(0, int((s - h) / 2))) * 2.0
		draw_rect(Rect2(p, Vector2(w, h)), [Color("5d5560"), Color("6f6550"), Color("4f5a63"), Color("7a6a5a")][i % 4])
		if fmod(_t * 0.7 + float(i) * 0.37, 3.0) < 2.4:
			draw_rect(Rect2(p + Vector2(2, 2), Vector2(2, 2)), UI.col("gold"))
	var title := "九龍城寨"
	var f := UI.font("small")
	var fs := UI.font_size("small")
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var plate := Rect2(c.x - tw * 0.5 - 6, r.end.y + 6, tw + 12, 26)
	draw_rect(plate, UI.col("red_dd"))
	draw_rect(plate.grow(-2), UI.col("red_d"))
	_text(Vector2(plate.position.x + 6, plate.position.y + 3 + f.get_ascent(fs)), title, UI.col("gold_hi"))


func _is_focus(d: Dictionary) -> bool:
	if focus_good == "":
		return false
	if str(UI.to_dict(d.get("primary", {})).get("good", "")) == focus_good:
		return true
	for pk: Variant in UI.to_array(d.get("picks", [])):
		if pk is Dictionary and str(pk.get("good", "")) == focus_good:
			return true
	return false


func _deco(d: Dictionary) -> void:
	var p := dest_point(d)
	var g := str(UI.to_dict(d.get("primary", {})).get("good", ""))
	var known := bool(d.get("known", true))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(d.get("id", "")))
	if not known:
		# 안개
		for i in 9:
			var o := Vector2(rng.randf_range(-34, 34), rng.randf_range(-20, 20)).snapped(Vector2(PX, PX))
			var w := rng.randi_range(8, 16) * 2.0
			draw_rect(Rect2(p + o - Vector2(w * 0.5, 4), Vector2(w, 8)), Color(0.55, 0.55, 0.62, 0.22))
		return
	match g:
		"wood":   # 철거 골목: 판재 더미
			for i in 6:
				var o2 := Vector2(rng.randf_range(-26, 26), rng.randf_range(-16, 16)).snapped(Vector2(PX, PX))
				draw_rect(Rect2(p + o2, Vector2(12, 4)), Color("7a5232"))
				draw_rect(Rect2(p + o2 + Vector2(2, -2), Vector2(10, 2)), Color("9b6a40"))
		"metal":  # 고철 야적장: 녹슨 더미
			for i in 5:
				var o3 := Vector2(rng.randf_range(-26, 26), rng.randf_range(-14, 14)).snapped(Vector2(PX, PX))
				for k in 4:
					draw_rect(Rect2(p + o3 + Vector2(k * 2, -k * 2), Vector2(14 - k * 4, 2)), Color("7d4a33") if k % 2 == 0 else Color("5f6670"))
		"concrete":  # 공사장 블록과 기중기
			for i in 5:
				var o4 := Vector2(rng.randf_range(-26, 26), rng.randf_range(-12, 14)).snapped(Vector2(PX, PX))
				draw_rect(Rect2(p + o4, Vector2(10, 8)), Color("8a8a86"))
				draw_rect(Rect2(p + o4, Vector2(10, 2)), Color("b0b0aa"))
			draw_rect(Rect2(p + Vector2(18, -34), Vector2(2, 30)), UI.col("gold_d"))
			draw_rect(Rect2(p + Vector2(4, -34), Vector2(26, 2)), UI.col("gold_d"))
		"scrap":  # 부두: 상자와 기둥
			for i in 6:
				var o5 := Vector2(rng.randf_range(-24, 24), rng.randf_range(-10, 14)).snapped(Vector2(PX, PX))
				draw_rect(Rect2(p + o5, Vector2(8, 6)), [Color("8c3a2e"), Color("2f6b5a"), Color("8a6a2c")][i % 3])
		"parts":  # 옛 발전소: 굴뚝
			draw_rect(Rect2(p + Vector2(-22, -10), Vector2(30, 18)), Color("4a4650"))
			draw_rect(Rect2(p + Vector2(10, -40), Vector2(8, 48)), Color("5a5560"))
			draw_rect(Rect2(p + Vector2(10, -40), Vector2(8, 4)), UI.col("red_d"))
			var puff := fmod(_t * 6.0, 20.0)
			draw_rect(Rect2(p + Vector2(12 + puff * 0.4, -46 - puff), Vector2(6, 4)), Color(0.7, 0.7, 0.7, 0.4 * (1.0 - puff / 20.0)))
		_:
			for i in 5:
				var o6 := Vector2(rng.randf_range(-20, 20), rng.randf_range(-12, 12)).snapped(Vector2(PX, PX))
				draw_rect(Rect2(p + o6, Vector2(4, 4)), Color("4d4a55"))


func _marker(d: Dictionary) -> void:
	var p := dest_point(d)
	var id := str(d.get("id", ""))
	var known := bool(d.get("known", true))
	var foc := _is_focus(d)
	var dim := focus_good != "" and not foc and known
	var band := str(d.get("band", "near"))
	var base: Color = {"near": UI.col("jade"), "mid": UI.col("gold"), "far": UI.col("red_hi")}.get(band, UI.col("paper"))
	if not known:
		base = UI.col("mute")
	if dim:
		base = base.darkened(0.55)
	# 맥박 고리
	if foc:
		var pr := 14.0 + fmod(_t * 18.0, 12.0)
		_ring(p, pr, Color(UI.col("jade_hi"), 1.0 - fmod(_t * 18.0, 12.0) / 12.0))
	if id == selected:
		_ring(p, 15.0, UI.col("gold_hi"))
		_ring(p, 17.0, UI.col("out"))
	# 표지판(마름모)
	for k in 7:
		var w := (7 - absi(k - 3)) * 2.0 + 2.0
		draw_rect(Rect2(p + Vector2(-w, (k - 3) * 2.0 - 1.0) , Vector2(w * 2.0, 2)), UI.col("out"))
	for k in 5:
		var w2 := (5 - absi(k - 2)) * 2.0
		draw_rect(Rect2(p + Vector2(-w2, (k - 2) * 2.0 - 1.0), Vector2(w2 * 2.0, 2)), base)
	if bool(d.get("new", false)):
		draw_rect(Rect2(p + Vector2(8, -14), Vector2(6, 6)), UI.col("red_hi"))
	# 이름
	var nm := str(d.get("name", "?")) if known else "?"
	var f := UI.font("small")
	var fs := UI.font_size("small")
	var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lp := (p + Vector2(-tw * 0.5, 14)).floor()
	lp.x = clampf(lp.x, 4.0, size.x - tw - 4.0)
	var plate := Rect2(lp - Vector2(4, 0), Vector2(tw + 8, 24))
	draw_rect(plate, Color(UI.col("out"), 0.75 if not dim else 0.5))
	_text(lp + Vector2(0, 2 + f.get_ascent(fs)), nm, (UI.col("paper") if known else UI.col("dim")) if not dim else UI.col("mute"))
	var hit := Rect2(p - Vector2(24, 20), Vector2(48, 32)).merge(plate).grow(4)
	_hits.append({"rect": hit, "id": id})


func _team(tm: Dictionary, c: Vector2) -> void:
	var st := str(tm.get("state", "idle"))
	if st == "idle":
		return
	var dest_id := str(tm.get("dest", ""))
	var target := c
	for d: Variant in dests:
		if d is Dictionary and str(d.get("id", "")) == dest_id:
			target = dest_point(d)
	var p := c
	if st == "out":
		var total := maxf(1.0, float(tm.get("total_seconds", 1)))
		var left := clampf(float(tm.get("seconds_left", 0)), 0.0, total)
		var k := 1.0 - left / total
		# 가는 길 절반, 오는 길 절반
		p = c.lerp(target, k * 2.0) if k < 0.5 else target.lerp(c, (k - 0.5) * 2.0)
	elif st == "done":
		p = c + Vector2(30, -30)
	p = p.snapped(Vector2(PX, PX))
	var bob := 2.0 if fmod(_t, 0.5) < 0.25 else 0.0
	# 짐꾼 셋
	for i in 3:
		var o := Vector2(i * 6 - 6, -bob if i == 1 else 0.0)
		draw_rect(Rect2(p + o + Vector2(0, -8), Vector2(4, 4)), Color("e6c9a0"))
		draw_rect(Rect2(p + o + Vector2(0, -4), Vector2(4, 6)), UI.col("red") if i != 1 else UI.col("jade"))
	draw_rect(Rect2(p + Vector2(-8, -14), Vector2(18, 4)), Color("7a5232"))
	if st == "done":
		var f := UI.font("body")
		_text(p + Vector2(-4, -22 - bob * 2.0), "!", UI.col("gold_hi"), f, UI.font_size("body"))


# ------------------------------------------------------------------ 도우미
func _text(p: Vector2, s: String, col: Color, f: Font = null, fs: int = -1) -> void:
	if f == null:
		f = UI.font("small")
	if fs < 0:
		fs = UI.font_size("small")
	draw_string(f, p + Vector2(2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.col("out"))
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _dotted_circle(c: Vector2, r: float, col: Color) -> void:
	var n := int(r * 1.2)
	for i in n:
		if i % 3 != 2:
			var a := TAU * float(i) / float(n)
			draw_rect(Rect2((c + Vector2(cos(a), sin(a)) * r).snapped(Vector2(PX, PX)), Vector2(PX, PX)), col)


func _ring(c: Vector2, r: float, col: Color) -> void:
	var n := int(r * 2.0)
	for i in n:
		var a := TAU * float(i) / float(n)
		draw_rect(Rect2((c + Vector2(cos(a), sin(a)) * r).snapped(Vector2(PX, PX)), Vector2(PX, PX)), col)


func _dotted_line(a: Vector2, b: Vector2, col: Color) -> void:
	var l := a.distance_to(b)
	var n := int(l / 6.0)
	for i in n:
		var p := a.lerp(b, float(i) / maxf(1.0, float(n)))
		draw_rect(Rect2(p.snapped(Vector2(PX, PX)), Vector2(PX, PX)), col)
