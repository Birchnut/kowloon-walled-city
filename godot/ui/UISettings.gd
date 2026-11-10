class_name UISettings
extends RefCounted
## UISettings — UI만의 자잘한 기억(튜토리얼 진행 등). user://ui_settings.cfg.
## `nosave`(사용자 인자) / KOWLOON_NOSAVE=1 이면 파일을 건드리지 않고 메모리에만 둔다.

const PATH := "user://ui_settings.cfg"

static var _cfg: ConfigFile = null
static var _mem_only: bool = false


static func _load() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	_mem_only = "nosave" in OS.get_cmdline_user_args() or OS.get_environment("KOWLOON_NOSAVE") == "1"
	if not _mem_only:
		_cfg.load(PATH)


static func get_value(key: String, default: Variant = null) -> Variant:
	_load()
	return _cfg.get_value("ui", key, default)


static func set_value(key: String, value: Variant) -> void:
	_load()
	_cfg.set_value("ui", key, value)
	if not _mem_only:
		_cfg.save(PATH)
