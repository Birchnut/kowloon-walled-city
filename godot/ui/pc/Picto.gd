class_name Picto
extends Control
## Picto — 가는 선 그림문자(시안 '다'). 24×24 칸에 선 굵기 1.6으로 코드로 그린다. 이모지·그림 파일 없음.
## 모양은 아래 P: 한 줄 = 한 획.  "M x y L x y …(Z)" 선·닫힌 선, "C x1 y1 x2 y2 x y" 굽은 선, "O cx cy r" 동그라미,
## "F cx cy r" 채운 점, "A cx cy r 시작각 끝각" 호(0도 = 동쪽, 90도 = 남쪽).
##   var p := Picto.make("water", UI.col("blue"))     # 24px
##   p.px = 3                                         # 36px (px 하나 = 12칸 가로 세로: 크기 = 12 × px)

const P := {
	"coin": ["O 12 12 8.5", "O 12 12 4.5"],
	"pop": ["O 12 8 3.6", "M 5 20.5 A 12 20.5 7 180 360"],
	"smile": ["O 12 12 8.8", "F 9 10 1", "F 15 10 1", "A 12 12.5 4.5 25 155"],
	"frown": ["O 12 12 8.8", "F 9 10 1", "F 15 10 1", "A 12 17.5 4.5 205 335"],
	"water": ["M 12 3 C 12 3 5.5 10 5.5 14.5 C 5.5 18 8.4 21 12 21 C 15.6 21 18.5 18 18.5 14.5 C 18.5 10 12 3 12 3 Z"],
	"power": ["M 13.5 3 L 6 13.5 L 11.5 13.5 L 10.5 21 L 18 10 L 12.5 10 Z"],
	"food": ["M 4 12 L 20 12 C 20 17 16.5 20 12 20 C 7.5 20 4 17 4 12 Z", "M 9 4 C 8 6 10 7 9 9", "M 14 4 C 13 6 15 7 14 9"],
	"fun": ["M 5.5 5 L 18.5 5 L 18.5 19 L 5.5 19 Z", "M 9 9 L 15 9", "O 12 14.5 1.8"],
	"fire": ["M 12 3 C 13 8 18 10 18 15 C 18 18.5 15.3 21 12 21 C 8.7 21 6 18.5 6 15 C 6 12.5 7.5 11 8.5 9.5 C 9.3 11 10 11.5 11 11.5 C 11.5 9 11 6 12 3 Z"],
	"disease": ["O 12 12 4", "M 12 3 L 12 7", "M 12 17 L 12 21", "M 3 12 L 7 12", "M 17 12 L 21 12", "M 5.6 5.6 L 8.6 8.6", "M 15.4 15.4 L 18.4 18.4", "M 18.4 5.6 L 15.4 8.6", "M 8.6 15.4 L 5.6 18.4"],
	"labor": ["O 12 8 3.6", "M 5 20.5 A 12 20.5 7 180 360", "M 8.2 6 L 15.8 6"],
	"house": ["M 3 11.5 L 12 3.8 L 21 11.5", "M 5.5 9.5 L 5.5 20 L 18.5 20 L 18.5 9.5", "M 10 20 L 10 14 L 14 14 L 14 20"],
	"market": ["M 3.5 9 L 5 4 L 19 4 L 20.5 9 Z", "M 5 9 L 5 20 L 19 20 L 19 9", "M 9.5 20 L 9.5 14 L 14.5 14 L 14.5 20"],
	"service": ["M 5 8 L 5 13.5 C 5 17 8 19 11 19 C 14 19 17 17 17 13.5 L 17 8 Z", "M 17 9.5 C 21.5 9.5 21.5 15 17 15", "M 9 3.5 L 9 5.5", "M 13 3.5 L 13 5.5"],
	"goods": ["M 4 8 L 12 4 L 20 8 L 20 17 L 12 21 L 4 17 Z", "M 4 8 L 12 12 L 20 8", "M 12 12 L 12 21"],
	"electronics": ["M 3.5 5.5 L 20.5 5.5 L 20.5 16.5 L 3.5 16.5 Z", "M 8.5 20.5 L 15.5 20.5", "M 12 16.5 L 12 20.5"],
	"vice": ["M 7 4 L 17 4 L 16 10 C 15.5 13 13.5 14.5 12 14.5 C 10.5 14.5 8.5 13 8 10 Z", "M 12 14.5 L 12 20", "M 8.5 20 L 15.5 20"],
	"infra": ["O 12 12 3.2", "O 12 12 7.2", "M 12 2.8 L 12 4.8", "M 12 19.2 L 12 21.2", "M 2.8 12 L 4.8 12", "M 19.2 12 L 21.2 12"],
	"landmark": ["M 12 3.5 L 21 10 L 3 10 Z", "M 6 10 L 6 20", "M 18 10 L 18 20", "M 12 10 L 12 20", "M 3.5 20.5 L 20.5 20.5"],
	"demolish": ["M 4.5 7 L 19.5 7", "M 9 7 L 9 4 L 15 4 L 15 7", "M 6.5 7 L 7.5 20.5 L 16.5 20.5 L 17.5 7", "M 10.3 11 L 10.3 16.5", "M 13.7 11 L 13.7 16.5"],
	"pick": ["M 4 20 L 4.8 15 L 15.5 4.3 L 19.7 8.5 L 9 19.2 Z", "M 13.2 6.6 L 17.4 10.8"],
	"rotate": ["A 12 12 7.5 40 330", "M 18.5 3.5 L 18.5 8.3 L 13.7 8.3"],
	"metrics": ["M 5.5 3.5 L 18.5 3.5 L 18.5 20.5 L 5.5 20.5 Z", "M 9 8.5 L 15 8.5", "M 9 12.5 L 15 12.5", "M 9 16.5 L 12.5 16.5"],
	"economy": ["M 12 4 L 12 20", "M 7 20.5 L 17 20.5", "M 4 7.5 L 20 7.5", "M 4 7.5 L 1.8 14.5 L 6.2 14.5 Z", "M 20 7.5 L 17.8 14.5 L 22.2 14.5 Z"],
	"trade": ["M 4 8 L 19 8", "M 15 4 L 19 8 L 15 12", "M 20 16 L 5 16", "M 9 12 L 5 16 L 9 20"],
	"expedition": ["M 2.5 20 L 9 8 L 13 14.5 L 15.5 10.5 L 21.5 20 Z"],
	"keep": ["M 4 4 L 20 4 L 20 20 L 4 20 Z", "M 8.5 8.5 L 15.5 8.5 L 15.5 15.5 L 8.5 15.5 Z"],
	"help": ["O 12 12 9", "M 9.3 9.5 C 9.3 6.2 14.7 6.2 14.7 9.5 C 14.7 12 12 12 12 14.8", "F 12 17.8 1"],
	"pause": ["M 8.5 5 L 8.5 19", "M 15.5 5 L 15.5 19"],
	"play": ["M 7.5 4.5 L 19 12 L 7.5 19.5 Z"],
	"ff": ["M 3.5 5.5 L 11.5 12 L 3.5 18.5 Z", "M 12.5 5.5 L 20.5 12 L 12.5 18.5 Z"],
	"eye": ["M 2.5 12 C 6 6 18 6 21.5 12 C 18 18 6 18 2.5 12 Z", "O 12 12 3.2"],
	"floor": ["M 12 3 L 21 8 L 12 13 L 3 8 Z", "M 3 12 L 12 17 L 21 12", "M 3 16 L 12 21 L 21 16"],
	"alert": ["O 12 12 3.2"],
	"warn": ["M 12 3.5 L 21.5 20 L 2.5 20 Z", "M 12 9.5 L 12 14.5", "F 12 17.3 1"],
	"goal": ["M 6 21 L 6 3.5", "M 6 4.5 L 18.5 4.5 L 15 9 L 18.5 13.5 L 6 13.5"],
	"lock": ["M 5.5 11 L 18.5 11 L 18.5 20.5 L 5.5 20.5 Z", "M 8.5 11 L 8.5 7.5 A 12 7.5 3.5 180 360 L 15.5 11"],
	"check": ["M 4.5 12.5 L 9.8 17.5 L 19.5 6.5"],
	"close": ["M 6 6 L 18 18", "M 18 6 L 6 18"],
	"up": ["M 12 20 L 12 5", "M 6 11 L 12 5 L 18 11"],
	"down": ["M 12 4 L 12 19", "M 6 13 L 12 19 L 18 13"],
	"right": ["M 9 5 L 16 12 L 9 19"],
	"left": ["M 15 5 L 8 12 L 15 19"],
	"gear": ["O 12 12 3.2", "O 12 12 7", "M 12 2.8 L 12 5", "M 12 19 L 12 21.2", "M 2.8 12 L 5 12", "M 19 12 L 21.2 12", "M 5.5 5.5 L 7 7", "M 17 17 L 18.5 18.5", "M 18.5 5.5 L 17 7", "M 7 17 L 5.5 18.5"],
	"clock": ["O 12 12 9", "M 12 6.5 L 12 12 L 15.8 14.2"],
	"trash": ["M 4.5 7 L 19.5 7", "M 9 7 L 9 4 L 15 4 L 15 7", "M 6.5 7 L 7.5 20.5 L 16.5 20.5 L 17.5 7", "M 10.3 11 L 10.3 16.5", "M 13.7 11 L 13.7 16.5"],
	"clinic": ["M 9 4 L 15 4 L 15 9 L 20 9 L 20 15 L 15 15 L 15 20 L 9 20 L 9 15 L 4 15 L 4 9 L 9 9 Z"],
	"sick": ["M 10.3 13.5 L 10.3 5.5 A 12 5.5 1.7 180 360 L 13.7 13.5", "O 12 16.8 3.8"],
	"repair": ["M 20.5 6.5 L 16.8 10.2 L 13.8 7.2 L 17.5 3.5 C 13.5 2.5 10 6 11.5 10 L 3.8 17.7 L 6.3 20.2 L 14 12.5 C 18 14 21.5 10.5 20.5 6.5 Z"],
	"range": ["O 12 12 3", "O 12 12 8.5", "M 12 1.8 L 12 5", "M 12 19 L 12 22.2", "M 1.8 12 L 5 12", "M 19 12 L 22.2 12"],
	"tier": ["M 3 20.5 L 21 20.5", "M 3 20.5 L 3 15.5 L 8 15.5 L 8 11 L 13 11 L 13 6.5 L 18 6.5 L 18 20.5"],
	"mat": ["M 3 5 L 21 5 L 21 19 L 3 19 Z", "M 3 9.7 L 21 9.7", "M 3 14.3 L 21 14.3", "M 12 5 L 12 9.7", "M 8 9.7 L 8 14.3", "M 16 9.7 L 16 14.3", "M 12 14.3 L 12 19"],
	"calendar": ["M 4 6 L 20 6 L 20 20 L 4 20 Z", "M 4 10.5 L 20 10.5", "M 8.5 3.5 L 8.5 7.5", "M 15.5 3.5 L 15.5 7.5"],
	"layers2": ["M 12 3 L 21 8 L 12 13 L 3 8 Z", "M 3 12 L 12 17 L 21 12", "M 3 16 L 12 21 L 21 16"],
	"dot": ["F 12 12 3"],
	"plus": ["M 12 5 L 12 19", "M 5 12 L 19 12"],
	"minus": ["M 5 12 L 19 12"],
	"save": ["M 4 4 L 17 4 L 20 7 L 20 20 L 4 20 Z", "M 8 4 L 8 9 L 15 9 L 15 4", "M 7.5 20 L 7.5 14 L 16.5 14 L 16.5 20"],
	"burnt": ["M 12 3 C 13 8 18 10 18 15 C 18 18.5 15.3 21 12 21 C 8.7 21 6 18.5 6 15 C 6 12.5 7.5 11 8.5 9.5 C 9.3 11 10 11.5 11 11.5 C 11.5 9 11 6 12 3 Z", "M 4.5 4.5 L 19.5 19.5"],
}

var shape: String = "dot":
	set(v):
		shape = v
		queue_redraw()
var color: Color = Color(0.95, 0.92, 0.85):
	set(v):
		color = v
		queue_redraw()
var accent: Color = Color(1.0, 0.88, 0.54):
	set(v):
		accent = v
		queue_redraw()
var px: int = 2:
	set(v):
		px = maxi(1, v)
		custom_minimum_size = Vector2(12 * px, 12 * px)
		queue_redraw()
var outline: bool = true
## 선 굵기(24칸 기준)
var weight: float = 1.6


static func make(n: String, c: Color = Color(0.95, 0.92, 0.85), scale: int = 2, acc: Variant = null) -> Picto:
	var p := Picto.new()
	p.shape = n
	p.color = c
	if acc is Color:
		p.accent = acc
	p.px = scale
	return p


static func has(n: String) -> bool:
	return P.has(n)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(24, 24)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var strokes: Array = P.get(shape, P["dot"])
	var u := minf(size.x, size.y) / 24.0
	var off := (size - Vector2(24, 24) * u) * 0.5
	var w := maxf(1.2, weight * u)
	for st: Variant in strokes:
		_stroke(str(st), off, u, w)


func _pt(a: PackedStringArray, i: int, off: Vector2, u: float) -> Vector2:
	return off + Vector2(float(a[i]), float(a[i + 1])) * u


func _stroke(s: String, off: Vector2, u: float, w: float) -> void:
	var a := s.split(" ", false)
	if a.is_empty():
		return
	match a[0]:
		"O":
			draw_arc(_pt(a, 1, off, u), float(a[3]) * u, 0.0, TAU, 40, color, w, true)
		"F":
			draw_circle(_pt(a, 1, off, u), float(a[3]) * u, color)
		"A":
			_arc(_pt(a, 1, off, u), float(a[3]) * u, float(a[4]), float(a[5]), w)
		"M":
			_path(a, off, u, w)


func _arc(c: Vector2, r: float, a0: float, a1: float, w: float) -> void:
	draw_arc(c, r, deg_to_rad(a0), deg_to_rad(a1), 24, color, w, true)


func _path(a: PackedStringArray, off: Vector2, u: float, w: float) -> void:
	var pts := PackedVector2Array()
	var closed := false
	var i := 0
	while i < a.size():
		match a[i]:
			"M", "L":
				pts.append(_pt(a, i + 1, off, u))
				i += 3
			"C":
				var p0: Vector2 = pts[pts.size() - 1]
				var c1 := _pt(a, i + 1, off, u)
				var c2 := _pt(a, i + 3, off, u)
				var p1 := _pt(a, i + 5, off, u)
				for k in range(1, 13):
					var t := float(k) / 12.0
					var mt := 1.0 - t
					pts.append(p0 * mt * mt * mt + c1 * 3.0 * mt * mt * t + c2 * 3.0 * mt * t * t + p1 * t * t * t)
				i += 7
			"A":
				var c := _pt(a, i + 1, off, u)
				var r := float(a[i + 3]) * u
				var a0 := deg_to_rad(float(a[i + 4]))
				var a1 := deg_to_rad(float(a[i + 5]))
				for k in range(0, 13):
					var ang := lerpf(a0, a1, float(k) / 12.0)
					pts.append(c + Vector2(cos(ang), sin(ang)) * r)
				i += 6
			"Z":
				closed = true
				i += 1
			_:
				i += 1
	if pts.size() < 2:
		return
	if closed:
		pts.append(pts[0])
	draw_polyline(pts, color, w, true)
	# 꼭짓점이 뾰족하게 튀지 않도록 둥근 마감
	for p: Vector2 in [pts[0], pts[pts.size() - 1]]:
		draw_circle(p, w * 0.5, color)
