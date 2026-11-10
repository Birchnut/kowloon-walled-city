class_name DataLoader
extends Node
## DataLoader (autoload `Data`) — res://data/*.json 전체를 부팅 시 로드·검증.
## - 필수 키 누락 시 "파일명 > 키 경로" 형식으로 에러 출력
## - F5(debug_reload_data) 로 핫리로드 → EventBus.data_reloaded
## - 접근: Data.config, Data.industries, ... (Dictionary)
##   편의 함수: Data.cfg("time/seconds_per_game_day", 600)

const DATA_DIR := "res://data/"

## 파일별 필수 키. 경로는 "a/b/c" 형식. 배열 요소는 검증하지 않음(얕은 검증).
const REQUIRED_KEYS := {
	"config": [
		"schema_version",
		"grid/width", "grid/height", "grid/max_floors",
		"iso/tile_width", "iso/tile_height", "iso/floor_height",
		"time/seconds_per_game_day", "time/hours_per_day", "time/start_hour", "time/offline_catchup_max_days",
		"seed",
		"day_night/gradient", "day_night/sky",
	],
	"industries": ["schema_version", "categories", "industries"],
	"policies": ["schema_version", "axes"],
	"materials": ["schema_version", "materials"],
	"residents": ["schema_version", "tastes", "household_types", "named_residents", "player_titles/default"],
	"visual_rules": ["schema_version", "layer_order", "age_bands", "utility_levels", "rules", "placeholder_layer_colors"],
	"economy": ["schema_version", "starting_treasury", "starting_prestige", "tax/rate_default", "harvest/ripe_after_hours", "harvest/spoil_after_hours", "growth/inflow_base_per_day"],
}

var config: Dictionary = {}
var industries: Dictionary = {}
var policies: Dictionary = {}
var materials: Dictionary = {}
var residents: Dictionary = {}
var visual_rules: Dictionary = {}
var economy: Dictionary = {}

var load_ok: bool = false
var errors: Array[String] = []

# 파생 인덱스 (id → entry)
var industry_by_id: Dictionary = {}
var material_by_id: Dictionary = {}
var policy_axis_by_id: Dictionary = {}
var resident_by_id: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_reload_data"):
		print("[Data] F5 → 핫리로드")
		reload()


## 전체 재로드. 성공 여부 반환. 실패 시 이전 데이터는 유지(부분 갱신 방지).
func reload() -> bool:
	errors.clear()
	var loaded := {}
	for name in REQUIRED_KEYS.keys():
		var dict := _load_json(name)
		if dict.is_empty():
			continue
		_validate(name, dict, REQUIRED_KEYS[name])
		loaded[name] = dict

	load_ok = errors.is_empty()
	if not load_ok:
		for e in errors:
			push_error(e)
			EventBus.data_error.emit(e.get_slice(" > ", 0), e)
		printerr("[Data] 로드 실패: %d개 오류. 기존 데이터 유지." % errors.size())
		return false

	config = loaded["config"]
	industries = loaded["industries"]
	policies = loaded["policies"]
	materials = loaded["materials"]
	residents = loaded["residents"]
	visual_rules = loaded["visual_rules"]
	economy = loaded["economy"]
	_build_indexes()
	print("[Data] 로드 완료: %d 파일, 산업 %d, 자재 %d, 정책축 %d, 대표인물 %d, 외형규칙 %d" % [
		loaded.size(), industry_by_id.size(), material_by_id.size(),
		policy_axis_by_id.size(), resident_by_id.size(), visual_rules.get("rules", []).size()])
	EventBus.data_reloaded.emit()
	return true


func _load_json(name: String) -> Dictionary:
	var path := DATA_DIR + name + ".json"
	if not FileAccess.file_exists(path):
		errors.append("%s.json > (파일 없음: %s)" % [name, path])
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s.json > (열기 실패: %s)" % [name, error_string(FileAccess.get_open_error())])
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		errors.append("%s.json > (JSON 문법 오류 %d행: %s)" % [name, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("%s.json > (최상위가 객체가 아님)" % name)
		return {}
	return json.data


func _validate(name: String, dict: Dictionary, keys: Array) -> void:
	for key_path in keys:
		if not _has_path(dict, key_path):
			errors.append("%s.json > 필수 키 누락: %s" % [name, key_path])


func _has_path(dict: Dictionary, path: String) -> bool:
	var cur: Variant = dict
	for part in path.split("/"):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(part):
			return false
		cur = cur[part]
	return true


func _build_indexes() -> void:
	industry_by_id.clear()
	for ind in industries.get("industries", []):
		industry_by_id[ind["id"]] = ind
	material_by_id.clear()
	for m in materials.get("materials", []):
		material_by_id[m["id"]] = m
	policy_axis_by_id.clear()
	for ax in policies.get("axes", []):
		policy_axis_by_id[ax["id"]] = ax
	resident_by_id.clear()
	for r in residents.get("named_residents", []):
		resident_by_id[r["id"]] = r


## "time/seconds_per_game_day" 같은 경로로 config 값 읽기. 없으면 default.
func cfg(path: String, default: Variant = null) -> Variant:
	return get_path_value(config, path, default)


## 임의 딕셔너리에서 경로로 값 읽기.
static func get_path_value(dict: Dictionary, path: String, default: Variant = null) -> Variant:
	var cur: Variant = dict
	for part in path.split("/"):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(part):
			return default
		cur = cur[part]
	return cur


## "#rrggbb" / "#rrggbbaa" → Color
static func hex_color(s: String, fallback := Color.MAGENTA) -> Color:
	if Color.html_is_valid(s):
		return Color.html(s)
	return fallback


## config.day_night.gradient 같은 [{t, color}] 배열 → Gradient 리소스
static func gradient_from_array(arr: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in arr:
		offsets.append(float(stop.get("t", 0.0)))
		colors.append(hex_color(str(stop.get("color", "#ffffff"))))
	if offsets.size() >= 1:
		g.offsets = offsets
		g.colors = colors
	return g
