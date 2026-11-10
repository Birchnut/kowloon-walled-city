class_name IsoGrid
extends Node2D
## IsoGrid — 12x12 아이소메트릭 격자 + 층(z) 렌더 컨테이너.
## - 셀 좌표 (x, y, z): x,y 는 격자, z 는 층(0=지면)
## - 2:1 아이소 타일. 크기는 config.iso (tile_width/tile_height/floor_height)
## - 정렬: y_sort_enabled + 셀별 z_index 로 "화면 아래쪽 셀과 높은 층이 앞에" 보장
## - 셀 하나 = CellRenderer 노드. 지금은 PLACEHOLDER 폴리곤, 나중에 레이어 스프라이트로 교체
##
## 좌표 규약 (PLACEHOLDER):
##   iso_to_screen(x,y,z) = ( (x - y) * tw/2 ,  (x + y) * th/2 - z * fh )
##   화면 원점은 격자 (0,0,0) 셀의 '윗꼭지점 중앙'.

const CellRendererScript := preload("res://scripts/world/CellRenderer.gd")

var tile_w: int = 32
var tile_h: int = 16
var floor_h: int = 12
var grid_w: int = 12
var grid_h: int = 12
var max_floors: int = 8

var city: CityState = null
var _renderers: Dictionary = {}   # "x,y,z" → CellRenderer
var _ground: Node2D
var _buildings: Node2D
var _selected: Vector3i = Vector3i(-1, -1, -1)
var _highlight: Polygon2D


func _ready() -> void:
	_apply_config()
	EventBus.data_reloaded.connect(_on_data_reloaded)
	_ground = Node2D.new()
	_ground.name = "Ground"
	add_child(_ground)
	_buildings = Node2D.new()
	_buildings.name = "Buildings"
	_buildings.y_sort_enabled = true
	add_child(_buildings)
	_highlight = Polygon2D.new()
	_highlight.name = "Highlight"
	_highlight.color = Color(1, 1, 0.3, 0.6)
	_highlight.z_index = 4000
	_highlight.visible = false
	add_child(_highlight)


func _apply_config() -> void:
	tile_w = int(Data.cfg("iso/tile_width", 32))
	tile_h = int(Data.cfg("iso/tile_height", 16))
	floor_h = int(Data.cfg("iso/floor_height", 12))
	grid_w = int(Data.cfg("grid/width", 12))
	grid_h = int(Data.cfg("grid/height", 12))
	max_floors = int(Data.cfg("grid/max_floors", 8))


func _on_data_reloaded() -> void:
	_apply_config()
	rebuild_all()


## CityState 연결. 셀 변경 시그널로 개별 갱신.
func bind_city(c: CityState) -> void:
	if city != null and city.cell_changed.is_connected(_on_cell_changed):
		city.cell_changed.disconnect(_on_cell_changed)
	city = c
	city.cell_changed.connect(_on_cell_changed)
	rebuild_all()


# ------------------------------------------------------------------ 좌표 변환
func iso_to_screen(cell: Vector3i) -> Vector2:
	return Vector2(
		(cell.x - cell.y) * tile_w * 0.5,
		(cell.x + cell.y) * tile_h * 0.5 - cell.z * floor_h
	)

## 화면(로컬) 좌표 → 지면(z=0) 격자 좌표. 층 선택은 pick_cell에서 처리.
func screen_to_iso_ground(p: Vector2) -> Vector2i:
	var fx := (p.x / (tile_w * 0.5) + p.y / (tile_h * 0.5)) * 0.5
	var fy := (p.y / (tile_h * 0.5) - p.x / (tile_w * 0.5)) * 0.5
	return Vector2i(int(floor(fx)), int(floor(fy)))

func in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.x < grid_w and c.y >= 0 and c.y < grid_h and c.z >= 0 and c.z < max_floors

## 탭 위치에서 셀 선택. 가장 높은 층부터 검사해 가려진 셀 문제를 1차 완화(PLACEHOLDER 로직).
## 단면/층별 보기 UX는 후속 과제.
func pick_cell(local_pos: Vector2) -> Vector3i:
	for z in range(max_floors - 1, -1, -1):
		var ground := screen_to_iso_ground(local_pos + Vector2(0, z * floor_h))
		var c := Vector3i(ground.x, ground.y, z)
		if not in_bounds(c):
			continue
		if z == 0:
			return c
		if city != null and not city.get_cell(c).is_empty():
			return c
	return Vector3i(-1, -1, -1)

## 정렬 키: 화면 아래쪽(x+y 큼) & 높은 층이 앞. y_sort와 함께 쓰므로 z_index는 층 보정용.
func sort_z_index(cell: Vector3i) -> int:
	return (cell.x + cell.y) * 10 + cell.z

## 타일 마름모 꼭지점(로컬, 셀 원점 기준)
func diamond_points() -> PackedVector2Array:
	var hw := tile_w * 0.5
	var hh := tile_h * 0.5
	return PackedVector2Array([Vector2(0, 0), Vector2(hw, hh), Vector2(0, tile_h), Vector2(-hw, hh)])


# ------------------------------------------------------------------ 렌더
func rebuild_all() -> void:
	for r in _renderers.values():
		r.queue_free()
	_renderers.clear()
	for ch in _ground.get_children():
		ch.queue_free()
	_draw_ground()
	if city == null:
		return
	for key in city.cells.keys():
		_ensure_renderer(CityState._unkey(key))


func _draw_ground() -> void:
	# 지면 전체를 체커보드 마름모로 그림 (PLACEHOLDER)
	for y in grid_h:
		for x in grid_w:
			var poly := Polygon2D.new()
			poly.polygon = diamond_points()
			poly.position = iso_to_screen(Vector3i(x, y, 0))
			poly.color = Color(0.22, 0.2, 0.18) if (x + y) % 2 == 0 else Color(0.25, 0.23, 0.2)
			poly.z_index = -1000
			_ground.add_child(poly)


func _ensure_renderer(cell: Vector3i) -> Node2D:
	var key := CityState._key(cell)
	if _renderers.has(key):
		return _renderers[key]
	var r: Node2D = CellRendererScript.new()
	r.name = "Cell_%s" % key.replace(",", "_")
	r.setup(self, cell)
	r.position = iso_to_screen(cell)
	r.z_index = sort_z_index(cell)
	_buildings.add_child(r)
	_renderers[key] = r
	r.refresh(city.get_cell(cell) if city else {})
	return r


func _on_cell_changed(cell: Vector3i) -> void:
	var r := _ensure_renderer(cell)
	r.refresh(city.get_cell(cell))


# ------------------------------------------------------------------ 선택
func select_cell(cell: Vector3i) -> void:
	_selected = cell
	if cell == Vector3i(-1, -1, -1):
		_highlight.visible = false
		EventBus.cell_deselected.emit()
		return
	_highlight.polygon = diamond_points()
	_highlight.position = iso_to_screen(cell)
	_highlight.visible = true
	EventBus.cell_selected.emit(cell)

func selected_cell() -> Vector3i:
	return _selected

## 격자 전체의 화면 바운딩(카메라 리밋용)
func bounds_rect() -> Rect2:
	var pts := [
		iso_to_screen(Vector3i(0, 0, 0)), iso_to_screen(Vector3i(grid_w, 0, 0)),
		iso_to_screen(Vector3i(0, grid_h, 0)), iso_to_screen(Vector3i(grid_w, grid_h, 0)),
		iso_to_screen(Vector3i(0, 0, max_floors)),
	]
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
