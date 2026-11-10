class_name SimIO
extends RefCounted
## SimIO — 헤드리스 도구용: 오토로드 없이 data/**/*.json을 읽어 Sim에 넣을 db를 만든다(Data.gd와 같은 모양:
## 하위 폴더까지, 파일 이름(확장자 제외)이 키).


static func load_db(dir_path: String = "res://data") -> Dictionary:
	var db := {}
	var paths: Array[String] = []
	_scan(dir_path, paths)
	paths.sort()
	for p: String in paths:
		var key := p.get_file().get_basename()
		if db.has(key):
			push_error("[SimIO] 데이터 파일 이름이 겹침: %s" % p)
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(p)) != OK:
			push_error("[SimIO] %s:%d JSON 오류: %s" % [p, json.get_error_line(), json.get_error_message()])
			continue
		db[key] = json.data
	return db


static func _scan(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f: String in dir.get_files():
		if f.ends_with(".json"):
			out.append("%s/%s" % [dir_path, f])
	for d: String in dir.get_directories():
		_scan("%s/%s" % [dir_path, d], out)


static func write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SimIO] 쓸 수 없음: %s" % path)
		return false
	f.store_string(text)
	return true
