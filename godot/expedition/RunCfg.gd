extends RefCounted
## 직접 줍기 설정 — data/run/run_*.json 을 직접 읽는다(Data 오토로드 없이도, -s 배치에서도 돈다).
## 수치는 RunCfg.f("player_speed") 처럼. 없으면 기본값.

const DIR := "res://data/run/"

static var _files: Dictionary = {}
static var overrides: Dictionary = {}   # 배치 실험용: {"rat_damage": 2}


static func file(name: String) -> Dictionary:
	if not _files.has(name):
		var path := DIR + name + ".json"
		var d: Variant = null
		if FileAccess.file_exists(path):
			d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d == null or not (d is Dictionary):
			push_error("RunCfg: %s 를 읽지 못함" % path)
			d = {}
		_files[name] = d
	return _files[name]


static func reload() -> void:
	_files.clear()


static func f(key: String, def: float = 0.0) -> float:
	if overrides.has(key):
		return float(overrides[key])
	return float(file("run_tuning").get(key, def))


static func i(key: String, def: int = 0) -> int:
	return int(round(f(key, float(def))))


static func v(key: String, def: Variant = null) -> Variant:
	if overrides.has(key):
		return overrides[key]
	return file("run_tuning").get(key, def)


static func goods() -> Dictionary:
	return file("run_goods").get("items", {})


static func good(id: String) -> Dictionary:
	return goods().get(id, {"name": id, "short": id, "bundle": 1, "cap": 3, "value": 1.0, "color": "#cccccc"})


static func good_name(id: String) -> String:
	return str(good(id).get("name", id))


static func good_color(id: String) -> Color:
	return Color.from_string(str(good(id).get("color", "#cccccc")), Color.WHITE)


static func rooms() -> Dictionary:
	return file("run_rooms").get("items", {})


static func bot(profile: String) -> Dictionary:
	return file("run_bots").get("items", {}).get(profile, file("run_bots").get("items", {}).get("average", {}))
