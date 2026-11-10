class_name CellRenderer
extends Node2D
## CellRenderer — 셀 하나의 외형. visual_rules.json 으로 레이어 키 배열을 계산하고,
## 지금은 각 레이어를 PLACEHOLDER 색 폴리곤으로, 나중엔 Sprite2D(텍스처)로 그린다.
##
## 교체 지점: _draw_layer(). 레이어 키 → 텍스처 매핑(texture_for_layer)만 채우면
## 폴리곤 대신 Sprite2D가 쌓인다. 레이어 계산(resolve_layers)은 그대로.

var grid: IsoGrid
var cell: Vector3i
var layer_keys: Dictionary = {}   # layer_slot → layer_key
var _layer_nodes: Array[Node2D] = []
var _label: Label = null


func setup(g: IsoGrid, c: Vector3i) -> void:
	grid = g
	cell = c


## 셀 데이터로 외형 재계산 + 재그리기
func refresh(data: Dictionary) -> void:
	for n in _layer_nodes:
		n.queue_free()
	_layer_nodes.clear()
	if _label:
		_label.queue_free()
		_label = null
	if data.is_empty() or data.get("use", "empty") == "empty":
		layer_keys = {}
		return
	layer_keys = resolve_layers(data)
	var order: Array = Data.visual_rules.get("layer_order", [])
	for slot in order:
		if layer_keys.has(slot):
			_draw_layer(slot, layer_keys[slot], data)
	if Data.cfg("debug/show_grid_coords", false):
		_label = Label.new()
		_label.text = "%d,%d,%d" % [cell.x, cell.y, cell.z]
		_label.position = Vector2(-grid.tile_w * 0.25, -grid.floor_h)
		_label.scale = Vector2(0.4, 0.4)
		add_child(_label)


## visual_rules.rules 를 위에서부터 적용해 slot→key 맵 생성.
## 셀 컨텍스트: material, industry_category, utility_level, taste, age_band
func resolve_layers(data: Dictionary) -> Dictionary:
	var ctx := {
		"material": data.get("material", ""),
		"industry_category": _industry_category(data.get("industry_id", "")),
		"utility_level": int(data.get("utility_level", 0)),
		"taste": data.get("taste", "plain"),
		"age_band": _age_band(float(data.get("age_days", 0.0))),
	}
	var out := {}
	for rule in Data.visual_rules.get("rules", []):
		if _matches(rule.get("when", {}), ctx):
			for slot in rule.get("layers", {}).keys():
				out[slot] = rule["layers"][slot]
	return out


func _matches(when: Dictionary, ctx: Dictionary) -> bool:
	for k in when.keys():
		var want = when[k]
		if k == "utility_level_min":
			if ctx["utility_level"] < int(want):
				return false
		elif str(want) == "any":
			continue
		elif not ctx.has(k) or str(ctx[k]) != str(want):
			return false
	return true


func _industry_category(industry_id: String) -> String:
	if industry_id == "":
		return ""
	return str(Data.industry_by_id.get(industry_id, {}).get("category", ""))


func _age_band(age_days: float) -> String:
	for band in Data.visual_rules.get("age_bands", []):
		if age_days <= float(band.get("max_days", 0)):
			return band["id"]
	return "old"


# ------------------------------------------------------------------ 그리기 (교체 지점)
## 레이어 키에 대응하는 텍스처. 아직 없음 → null 반환 → 폴리곤 fallback.
func texture_for_layer(_layer_key: String) -> Texture2D:
	return null


func _draw_layer(slot: String, layer_key: String, _data: Dictionary) -> void:
	var tex := texture_for_layer(layer_key)
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(-grid.tile_w * 0.5, -grid.floor_h)
		add_child(s)
		_layer_nodes.append(s)
		return

	# PLACEHOLDER: 색 폴리곤. slot 별로 모양이 다르게 보이도록 단순 구분.
	var colors: Dictionary = Data.visual_rules.get("placeholder_layer_colors", {})
	var col := DataLoader.hex_color(str(colors.get(layer_key, "#777777")), Color(0.5, 0.5, 0.5))
	var hw := grid.tile_w * 0.5
	var th := grid.tile_h
	var fh := grid.floor_h
	var poly := Polygon2D.new()
	match slot:
		"base", "wall":
			# 큐브 외관: 좌측 면 + 우측 면 + 윗면(마름모)을 세 폴리곤으로
			var left := Polygon2D.new()
			left.polygon = PackedVector2Array([Vector2(-hw, th * 0.5), Vector2(0, th), Vector2(0, th - fh), Vector2(-hw, th * 0.5 - fh)])
			left.color = col.darkened(0.25)
			add_child(left); _layer_nodes.append(left)
			var right := Polygon2D.new()
			right.polygon = PackedVector2Array([Vector2(0, th), Vector2(hw, th * 0.5), Vector2(hw, th * 0.5 - fh), Vector2(0, th - fh)])
			right.color = col.darkened(0.45)
			add_child(right); _layer_nodes.append(right)
			poly.polygon = PackedVector2Array([Vector2(0, -fh), Vector2(hw, th * 0.5 - fh), Vector2(0, th - fh), Vector2(-hw, th * 0.5 - fh)])
			poly.color = col
		"window":
			poly.polygon = PackedVector2Array([Vector2(-hw * 0.6, th * 0.55 - fh * 0.3), Vector2(-hw * 0.3, th * 0.7 - fh * 0.3), Vector2(-hw * 0.3, th * 0.7 - fh * 0.75), Vector2(-hw * 0.6, th * 0.55 - fh * 0.75)])
			poly.color = col
		"sign":
			poly.polygon = PackedVector2Array([Vector2(hw * 0.15, th * 0.85 - fh * 0.9), Vector2(hw * 0.8, th * 0.55 - fh * 0.9), Vector2(hw * 0.8, th * 0.55 - fh * 0.6), Vector2(hw * 0.15, th * 0.85 - fh * 0.6)])
			poly.color = col
		"utility":
			poly.polygon = PackedVector2Array([Vector2(hw * 0.3, th * 0.8 - fh * 0.45), Vector2(hw * 0.55, th * 0.68 - fh * 0.45), Vector2(hw * 0.55, th * 0.68 - fh * 0.15), Vector2(hw * 0.3, th * 0.8 - fh * 0.15)])
			poly.color = col
		"decor":
			poly.polygon = PackedVector2Array([Vector2(-hw * 0.2, -fh - 3), Vector2(hw * 0.2, -fh - 3), Vector2(hw * 0.2, -fh + 2), Vector2(-hw * 0.2, -fh + 2)])
			poly.color = col
		"wear":
			poly.polygon = PackedVector2Array([Vector2(-hw, th * 0.5), Vector2(0, th), Vector2(hw, th * 0.5), Vector2(hw, th * 0.5 - fh), Vector2(0, -fh), Vector2(-hw, th * 0.5 - fh)])
			poly.color = col
		_:
			poly.polygon = grid.diamond_points()
			poly.color = col
	add_child(poly)
	_layer_nodes.append(poly)
