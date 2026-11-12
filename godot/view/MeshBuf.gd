class_name MeshBuf
extends RefCounted
## MeshBuf — 쿼드/상자를 배열에 쌓아 ArrayMesh 하나로 만든다.
## 정점 속성: COLOR.rgb = 색조, COLOR.a = 흔들림 가중치 / UV2.x = 칸 번호 + 난수(소수부), UV2.y = 종류(K_*).

const INV := 1.0 / 1024.0
const K_PLAIN := 0.0
const K_WINDOW := 1.0     # 유리 텍셀이 밤에 켜질 수 있음
const K_NEON := 2.0       # 전기가 있으면 밤에 통째로 발광
const K_SWAY := 3.0       # 빨래: 정점 흔들림
const K_GROUND := 4.0     # 지면(멀어지면 디더로 사라짐, 웅덩이 반사)
const K_INTERIOR := 5.0   # 층 컷 실내(해 그림자 없음, 밤엔 방 불빛)
const K_WINDOW_OFF := 6.0 # 빈 방 창(안 켜짐)
const K_BIZ := 7.0        # 가게 창(영업 시간에 켜짐)
const K_SHAKE := 8.0      # 발전기: 덜덜 떨림
const K_CANDLE := 9.0     # 전기 없는 집의 창(밤에 촛불만)

var v := PackedVector3Array()
var n := PackedVector3Array()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var col := PackedColorArray()
var idx := PackedInt32Array()
## 지금 짓는 칸의 번호(0 = 없음). UV2.x = owner + rnd(0..1) → 셰이더가 셀 상태 텍스처를 읽는다.
var owner := 0

const UP := Vector3(0, 1, 0)
const WHITE := Color(1, 1, 1, 1)


func is_empty() -> bool:
	return v.is_empty()


## p0=좌상 p1=우상 p2=우하 p3=좌하 (앞에서 봤을 때). r = 아틀라스 텍셀 사각형.
func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, r: Rect2, c: Color = WHITE, rnd: float = 0.0, kind: float = 0.0) -> void:
	var b := v.size()
	v.append(p0)
	v.append(p1)
	v.append(p2)
	v.append(p3)
	n.append(nrm)
	n.append(nrm)
	n.append(nrm)
	n.append(nrm)
	var x0 := r.position.x * INV
	var y0 := r.position.y * INV
	var x1 := (r.position.x + r.size.x) * INV
	var y1 := (r.position.y + r.size.y) * INV
	uv.append(Vector2(x0, y0))
	uv.append(Vector2(x1, y0))
	uv.append(Vector2(x1, y1))
	uv.append(Vector2(x0, y1))
	var u2 := Vector2(float(owner) + clampf(rnd, 0.0, 0.999), kind)
	uv2.append(u2)
	uv2.append(u2)
	uv2.append(u2)
	uv2.append(u2)
	col.append(c)
	col.append(c)
	col.append(c)
	col.append(c)
	idx.append(b)
	idx.append(b + 1)
	idx.append(b + 2)
	idx.append(b)
	idx.append(b + 2)
	idx.append(b + 3)


## 양면 쿼드(안테나·빨래·철망처럼 얇은 것). 뒷면은 좌우를 뒤집어 글자가 바로 읽히게 할 수도 있다.
func quad2(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, r: Rect2, c: Color = WHITE, rnd: float = 0.0, kind: float = 0.0, mirror_back: bool = false) -> void:
	quad(p0, p1, p2, p3, nrm, r, c, rnd, kind)
	if mirror_back:
		quad(p1, p0, p3, p2, -nrm, r, c, rnd, kind)
	else:
		var rb := Rect2(r.position.x + r.size.x, r.position.y, -r.size.x, r.size.y)
		quad(p1, p0, p3, p2, -nrm, rb, c, rnd, kind)


## 흔들리는 천: 위쪽 두 정점은 고정(a=0), 아래 두 정점이 흔들림(a=1). 양면.
func cloth(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, r: Rect2, c: Color, rnd: float) -> void:
	for side in 2:
		var b := v.size()
		var nn := nrm if side == 0 else -nrm
		if side == 0:
			v.append(p0); v.append(p1); v.append(p2); v.append(p3)
		else:
			v.append(p1); v.append(p0); v.append(p3); v.append(p2)
		for i in 4:
			n.append(nn)
			uv2.append(Vector2(float(owner) + clampf(rnd, 0.0, 0.999), K_SWAY))
		var x0 := r.position.x * INV
		var y0 := r.position.y * INV
		var x1 := (r.position.x + r.size.x) * INV
		var y1 := (r.position.y + r.size.y) * INV
		if side == 0:
			uv.append(Vector2(x0, y0)); uv.append(Vector2(x1, y0)); uv.append(Vector2(x1, y1)); uv.append(Vector2(x0, y1))
		else:
			uv.append(Vector2(x1, y0)); uv.append(Vector2(x0, y0)); uv.append(Vector2(x0, y1)); uv.append(Vector2(x1, y1))
		var top := Color(c.r, c.g, c.b, 0.0)
		var bot := Color(c.r, c.g, c.b, 1.0)
		col.append(top); col.append(top); col.append(bot); col.append(bot)
		idx.append(b); idx.append(b + 1); idx.append(b + 2)
		idx.append(b); idx.append(b + 2); idx.append(b + 3)


## 축 정렬 상자. side_r / top_r = 타일 사각형(왼쪽 위에서부터 크기에 맞게 잘라 쓴다).
## faces 비트: 1=+x 2=+z 4=-x 8=-z 16=위 32=아래. fh = 한 층 높이(세로 텍셀 밀도용).
func box(a: Vector3, b: Vector3, side_r: Rect2, top_r: Rect2, fh: float, c: Color = WHITE, faces: int = 31, rnd: float = 0.0, kind: float = 0.0, top_c: Color = Color(-1, 0, 0)) -> void:
	var sx := b.x - a.x
	var sy := b.y - a.y
	var sz := b.z - a.z
	var vh := minf(sy / fh * 16.0, side_r.size.y)
	var tc := c if top_c.r < 0.0 else top_c
	if faces & 1:
		var r := Rect2(side_r.position, Vector2(minf(sz * 16.0, side_r.size.x), vh))
		quad(Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(1, 0, 0), r, c, rnd, kind)
	if faces & 2:
		var r2 := Rect2(side_r.position, Vector2(minf(sx * 16.0, side_r.size.x), vh))
		quad(Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z), Vector3(0, 0, 1), r2, c, rnd, kind)
	if faces & 4:
		var r3 := Rect2(side_r.position, Vector2(minf(sz * 16.0, side_r.size.x), vh))
		quad(Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z), Vector3(a.x, a.y, a.z), Vector3(-1, 0, 0), r3, c, rnd, kind)
	if faces & 8:
		var r4 := Rect2(side_r.position, Vector2(minf(sx * 16.0, side_r.size.x), vh))
		quad(Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z), Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(0, 0, -1), r4, c, rnd, kind)
	if faces & 16:
		var rt := Rect2(top_r.position, Vector2(minf(sx * 16.0, top_r.size.x), minf(sz * 16.0, top_r.size.y)))
		quad(Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), UP, rt, tc, rnd, kind)
	if faces & 32:
		var rb := Rect2(top_r.position, Vector2(minf(sx * 16.0, top_r.size.x), minf(sz * 16.0, top_r.size.y)))
		quad(Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z), -UP, rb, c, rnd, kind)


func commit() -> ArrayMesh:
	if v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
