extends Node
## Data — res://data/**/*.json 을 파일명(확장자 제외)으로 전부 읽는다(하위 폴더 포함, 이름은 겹치면 안 된다).
## 파일을 추가하면 자동으로 잡힌다. 코드 수정 불필요. F5로 핫리로드(Game이 호출).
##
## 콘텐츠 파일 형식: { "_comment": "...", "items": { "<id>": { "name": "...", ... } } }
## 설정 파일 형식: 자유 Dictionary. Data.cfg("time.seconds_per_game_day", 600) 처럼 점 경로로 읽는다.

signal reloaded

const DATA_DIR := "res://data"

var files: Dictionary = {}   # "config" -> Variant(JSON 루트)
var errors: Array[String] = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	files.clear()
	errors.clear()
	var paths: Array[String] = []
	_scan(DATA_DIR, paths)
	if paths.is_empty():
		_err("data 폴더가 비었거나 열 수 없음: %s" % DATA_DIR)
		return
	paths.sort()
	for path in paths:
		var key := path.get_file().get_basename()
		if files.has(key):
			_err("데이터 파일 이름이 겹침(폴더가 달라도 안 된다): %s" % path)
			continue
		var text := FileAccess.get_file_as_string(path)
		var json := JSON.new()
		var rc := json.parse(text)
		if rc != OK:
			_err("%s:%d JSON 오류: %s" % [path, json.get_error_line(), json.get_error_message()])
			continue
		files[key] = json.data
	reloaded.emit()


## data/ 아래를 하위 폴더까지 훑어 *.json 경로를 모은다.
func _scan(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append("%s/%s" % [dir_path, f])
	for d in dir.get_directories():
		_scan("%s/%s" % [dir_path, d], out)


## 파일 루트 통째로. 없으면 빈 Dictionary.
func file(file_name: String) -> Variant:
	return files.get(file_name, {})


## 콘텐츠 파일의 items(id → 항목). 없으면 빈 Dictionary.
func items(file_name: String) -> Dictionary:
	var root: Variant = files.get(file_name, {})
	if root is Dictionary and root.has("items") and root["items"] is Dictionary:
		return root["items"]
	return {}


## 콘텐츠 항목 하나. 없으면 빈 Dictionary(호출 측은 반드시 기본값 처리).
func item(file_name: String, id: String) -> Dictionary:
	var it: Variant = items(file_name).get(id, {})
	return it if it is Dictionary else {}


## config.json 점 경로 읽기. 다른 파일은 cfg_in("render", "pixel.scale", 3).
func cfg(path: String, default: Variant = null) -> Variant:
	return cfg_in("config", path, default)


func cfg_in(file_name: String, path: String, default: Variant = null) -> Variant:
	var cur: Variant = files.get(file_name, {})
	for part in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default
	return cur


func _err(msg: String) -> void:
	errors.append(msg)
	push_error("[Data] " + msg)
