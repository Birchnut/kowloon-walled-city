extends Node
## SaveManager (autoload `Save`) — user://save.json 저장/로드 + 활성 CityState 보유.
## - schema_version 필드 + _migrate() 훅
## - 자동 저장: 하루 끝(EventBus.day_ended), 앱 백그라운드(APPLICATION_PAUSED / WM_GO_BACK / WM_CLOSE)
## - 로드 시 오프라인 경과 → Clock.compute_catchup → 시뮬레이션 적용, 요약은 Clock.last_catchup
##
## 활성 도시: Save.city (CityState). Main/HUD/디버그는 이 인스턴스를 공유한다.

const SAVE_PATH := "user://save.json"
const SCHEMA_VERSION := 1

var city: CityState = null
var autosave_enabled: bool = true
var last_save_unix: int = 0

var _bound := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.day_ended.connect(_on_day_ended)
	EventBus.data_reloaded.connect(_on_data_reloaded)
	get_tree().auto_accept_quit = false  # WM_CLOSE_REQUEST에서 저장 후 종료


## 핫리로드 시 살아있는 도시에 새 데이터 참조 주입 (상태는 유지)
func _on_data_reloaded() -> void:
	if city != null:
		city.configure(Data.config, Data.economy, Data.industries, Data.policies, Data.residents)
		city.changed.emit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_GO_BACK_REQUEST:
			if autosave_enabled and city != null:
				save_game()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if autosave_enabled and city != null:
				save_game()
			get_tree().quit()


func _on_day_ended(day: int) -> void:
	if city != null:
		city.on_day_ended(day)
	if autosave_enabled and city != null:
		save_game()


## 새 CityState를 만들고 데이터 주입. 기존 도시는 폐기.
func new_game(seed_override: int = -1) -> CityState:
	city = CityState.new()
	city.configure(Data.config, Data.economy, Data.industries, Data.policies, Data.residents)
	city.new_game(seed_override)
	Clock.reset()
	_bind_clock()
	return city


## 저장 파일이 있으면 로드, 없으면 새 게임. 반환: 로드 성공 여부(false면 새 게임 시작됨).
func load_or_new() -> bool:
	if has_save():
		var ok := load_game()
		if ok:
			return true
		push_warning("[Save] 로드 실패 → 새 게임 시작")
	new_game()
	return false


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(path: String = SAVE_PATH) -> bool:
	if city == null:
		push_error("[Save] 저장할 도시가 없음")
		return false
	var payload := {
		"schema_version": SCHEMA_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"app_version": ProjectSettings.get_setting("application/config/version", "0"),
		"clock": Clock.to_save(),
		"city": city.to_save(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[Save] 열기 실패: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	last_save_unix = payload["saved_at_unix"]
	EventBus.game_saved.emit(path)
	return true


func load_game(path: String = SAVE_PATH, apply_catchup: bool = true) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[Save] 열기 실패: %s" % path)
		return false
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_error("[Save] JSON 오류 %d행: %s" % [json.get_error_line(), json.get_error_message()])
		return false
	f.close()
	var payload: Dictionary = json.data
	var ver := int(payload.get("schema_version", 0))
	if ver > SCHEMA_VERSION:
		push_error("[Save] 세이브 스키마 v%d 가 앱 지원 v%d 보다 높음" % [ver, SCHEMA_VERSION])
		return false
	if ver < SCHEMA_VERSION:
		payload = _migrate(payload, ver)

	city = CityState.new()
	city.configure(Data.config, Data.economy, Data.industries, Data.policies, Data.residents)
	city.from_save(payload.get("city", {}))
	Clock.from_save(payload.get("clock", {}))
	_bind_clock()

	var summary := {}
	if apply_catchup:
		var saved_at := int(payload.get("saved_at_unix", 0))
		var now := int(Time.get_unix_time_from_system())
		var elapsed := maxf(0.0, float(now - saved_at))
		summary = Clock.compute_catchup(elapsed)
		Clock.apply_catchup(summary)  # advance → ticked → city.tick 로 시뮬레이션
	EventBus.game_loaded.emit(summary)
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## 스키마 마이그레이션 훅. 버전별 변환을 순서대로 적용.
func _migrate(payload: Dictionary, from_version: int) -> Dictionary:
	var v := from_version
	while v < SCHEMA_VERSION:
		match v:
			0:
				# v0 → v1: 예시. 필드가 없으면 기본값 채움.
				if not payload.has("clock"):
					payload["clock"] = {}
			_:
				pass
		v += 1
	payload["schema_version"] = SCHEMA_VERSION
	print("[Save] 마이그레이션 v%d → v%d" % [from_version, SCHEMA_VERSION])
	return payload


func _bind_clock() -> void:
	if _bound:
		return
	Clock.ticked.connect(_on_clock_ticked)
	_bound = true


func _on_clock_ticked(dt_hours: float) -> void:
	if city != null:
		city.tick(dt_hours)
