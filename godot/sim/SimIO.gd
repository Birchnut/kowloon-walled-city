class_name SimIO
extends RefCounted
## SimIO — 헤드리스 도구용: 오토로드 없이 data/*.json을 읽어 Sim에 넣을 db를 만든다(Data.gd와 같은 모양).


static func load_db(dir_path: String = "res://data") -> Dictionary:
	var db := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("[SimIO] data 폴더를 열 수 없음: %s" % dir_path)
		return db
	var names: Array = []
	for f: String in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	for f: String in names:
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string("%s/%s" % [dir_path, f])) != OK:
			push_error("[SimIO] %s:%d JSON 오류: %s" % [f, json.get_error_line(), json.get_error_message()])
			continue
		db[f.get_basename()] = json.data
	return db


static func write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SimIO] 쓸 수 없음: %s" % path)
		return false
	f.store_string(text)
	return true
