extends SceneTree
## 헤드리스 스모크 테스트.
##   godot --headless -s res://tests/smoke.gd
## 검사: 데이터 로드 → 새 게임 → 게임 2일 틱 → 저장 → 로드 → 상태 일치 → 오프라인 보상 계산 → 핫리로드.
## 실패 시 종료 코드 1.

const TEST_SAVE := "user://smoke_test_save.json"

var _fails: Array[String] = []
var _day_ended_count := 0
var _hour_changed_count := 0

# -s 모드에서는 오토로드가 컴파일 타임 전역으로 안 잡히므로 루트에서 가져온다.
var Data: Node
var Clock: Node
var Save: Node


var _ran := false
var _result := 0


func _initialize() -> void:
	print("=== 구룡성채 smoke test ===")
	print("Godot %s" % Engine.get_version_info()["string"])
	# 오토로드 _ready 는 _initialize 이후 첫 프레임에 돈다 → 테스트 본문은 _process 첫 호출에서 실행


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true  # true = SceneTree 종료


func _finalize() -> void:
	# quit() 호출 전 결과 코드 보존 (에러로 중간 중단되면 1)
	pass


func _run() -> void:
	Data = root.get_node("Data")
	Clock = root.get_node("Clock")
	Save = root.get_node("Save")
	_check(Data != null and Clock != null and Save != null, "오토로드 Data/Clock/Save 존재")

	# --- 1. 데이터 로드
	_check(Data.load_ok, "Data.load_ok (JSON 로드/검증)")
	_check(Data.industry_by_id.size() >= 1, "industries 최소 1개")
	_check(Data.policy_axis_by_id.size() == 4, "정책 축 4개 (DECISIONS)")
	_check(int(Data.cfg("grid/width")) == 12 and int(Data.cfg("grid/height")) == 12, "격자 12x12 (DECISIONS)")
	var mf := int(Data.cfg("grid/max_floors"))
	_check(mf >= 8 and mf <= 10, "max_floors 8~10 (DECISIONS)")

	# --- 2. 새 게임
	Save.autosave_enabled = false
	var city: CityState = Save.new_game(12345)
	_check(city != null, "CityState 생성")
	_check(city.built_cell_count() == 1, "오프닝: 첫 가옥 1칸")
	_check(city.treasury == int(Data.economy["starting_treasury"]), "초기 금고")
	_check(Clock.day == 0, "시작 일차 0")

	Clock.day_ended.connect(func(_d): _day_ended_count += 1)
	Clock.hour_changed.connect(func(_h): _hour_changed_count += 1)

	# --- 3. 게임 2일 전진 (시작 06시 → 2일 후 06시)
	var hpd := int(Data.cfg("time/hours_per_day", 24))
	city.treasury += 2000  # 성장 비용이 막히지 않도록 (테스트용)
	Clock.advance(hpd * 2.0)
	_check(Clock.day == 2, "2일 뒤 Clock.day == 2 (실제 %d)" % Clock.day)
	_check(_day_ended_count == 2, "day_ended 2회 (실제 %d)" % _day_ended_count)
	_check(_hour_changed_count == hpd * 2, "hour_changed %d회 (실제 %d)" % [hpd * 2, _hour_changed_count])
	_check(city.day_count == 2, "CityState.day_count 2 (실제 %d)" % city.day_count)
	_check(abs(city.elapsed_hours - hpd * 2.0) < 0.01, "CityState.elapsed_hours 48 (실제 %.2f)" % city.elapsed_hours)
	_check(city.population() >= 1, "2일 후 인구 ≥ 1 (실제 %d)" % city.population())
	print("  2일 후 요약: ", city.summary())

	# --- 4. 징수 경로
	var harvested := city.harvest_all()
	_check(harvested >= 0, "harvest_all 실행 (징수 %d)" % harvested)

	# --- 5. 저장 → 로드 → 비교
	var snapshot := city.to_save()
	var clock_snapshot: float = Clock.total_hours
	_check(Save.save_game(TEST_SAVE), "저장 %s" % TEST_SAVE)
	_check(FileAccess.file_exists(TEST_SAVE), "세이브 파일 존재")
	var ok: bool = Save.load_game(TEST_SAVE, false)  # catchup 없이 순수 복원
	_check(ok, "로드 성공")
	var city2: CityState = Save.city
	_check(city2 != city, "로드 후 새 CityState 인스턴스")
	_check(city2.treasury == snapshot["treasury"], "금고 일치 (%d vs %d)" % [city2.treasury, snapshot["treasury"]])
	_check(city2.prestige == snapshot["prestige"], "위신 일치")
	_check(city2.cells.size() == snapshot["cells"].size(), "셀 수 일치 (%d vs %d)" % [city2.cells.size(), snapshot["cells"].size()])
	_check(city2.households.size() == snapshot["households"].size(), "가구 수 일치")
	_check(JSON.stringify(city2.policies) == JSON.stringify(snapshot["policies"]), "정책 일치 (%s vs %s)" % [JSON.stringify(city2.policies), JSON.stringify(snapshot["policies"])])
	_check(abs(Clock.total_hours - clock_snapshot) < 0.001, "시계 복원 일치")
	for k in city2.households.keys():
		_check(typeof(k) == TYPE_INT, "가구 키 int 복원 (%s)" % str(k))
		break

	# --- 6. 오프라인 보상 계산 (적용은 cap 검증만)
	var spd := float(Data.cfg("time/seconds_per_game_day"))
	var cap_days := int(Data.cfg("time/offline_catchup_max_days"))
	var summary: Dictionary = Clock.compute_catchup(spd * (cap_days + 5))
	_check(summary["capped"] == true, "오프라인 보상 cap 적용")
	_check(abs(float(summary["simulated_days"]) - cap_days) < 0.001, "cap = %d일" % cap_days)
	var summary2: Dictionary = Clock.compute_catchup(spd * 0.5)
	_check(abs(float(summary2["simulated_hours"]) - hpd * 0.5) < 0.001, "반나절 경과 → %d시간" % (hpd / 2))
	var day_before: int = Clock.day
	Clock.apply_catchup(summary2)
	_check(Clock.day >= day_before, "catchup 적용 후 시간 전진")
	_check(Save.city.elapsed_hours > city2.elapsed_hours - 0.001, "catchup이 CityState.tick 까지 전달")

	# --- 7. 핫리로드
	_check(Data.reload(), "Data.reload() 재로드 성공")

	# --- 8. 스키마 마이그레이션 훅 (v0 세이브 흉내)
	var f := FileAccess.open(TEST_SAVE, FileAccess.READ)
	var payload: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	payload["schema_version"] = 0
	payload.erase("clock")
	var f2 := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f2.store_string(JSON.stringify(payload))
	f2.close()
	_check(Save.load_game(TEST_SAVE, false), "v0 세이브 마이그레이션 로드")

	# --- 9. 시각 규칙 해석 (렌더 없이 로직만)
	# CellRenderer 는 Data 전역을 참조하므로 -s 모드에선 런타임 load (컴파일 순서 문제 회피)
	var cr: Node2D = load("res://scripts/world/CellRenderer.gd").new()
	var layers: Dictionary = cr.resolve_layers({ "material": "neon", "industry_id": "mahjong_parlor", "utility_level": 2, "taste": "neon", "age_days": 30.0 })
	_check(layers.has("wall") and layers.has("sign") and layers.has("utility") and layers.has("wear"), "visual_rules 레이어 합성 (%s)" % str(layers))
	cr.free()

	# 정리
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

	# --- 결과
	print("")
	if _fails.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		for f_msg in _fails:
			printerr("FAIL: " + f_msg)
		print("SMOKE TEST FAILED (%d)" % _fails.size())
		quit(1)
	_result = 1


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_fails.append(label)
