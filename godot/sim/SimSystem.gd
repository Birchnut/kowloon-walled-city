class_name SimSystem
extends RefCounted
## SimSystem — 모든 규칙 묶음(sim/systems/<id>.gd)의 공통 모양. 전부 선택 구현(기본은 아무것도 안 함).
## 시스템끼리는 서로를 부르지 않는다. CityState만 읽고 쓴다. config.json "systems"에서 id를 빼면 그 규칙은 사라진다.
## 시간 단위는 전부 경제일(econ day). 한 스텝 = config time.step_days.

var sim: Sim


func setup(s: Sim) -> void:
	sim = s


func on_new_game(_state: CityState) -> void:
	pass


## 매 고정 스텝(dt = 경제일).
func tick(_state: CityState, _dt: float) -> void:
	pass


## ended_day = 방금 끝난 날(1부터).
func on_day_end(_state: CityState, _ended_day: int) -> void:
	pass


func on_day_start(_state: CityState) -> void:
	pass


## 아래 셋은 "내 명령/질의가 아니면 null".
func can(_state: CityState, _name: String, _args: Dictionary) -> Variant:
	return null


func apply(_state: CityState, _name: String, _args: Dictionary) -> Variant:
	return null


func query(_state: CityState, _name: String, _args: Dictionary) -> Variant:
	return null


## 공용 질의(hud, info, economy, build_menu …)의 결과 out에 자기 몫을 보탠다.
func augment(_state: CityState, _name: String, _args: Dictionary, _out: Variant) -> void:
	pass


## 어느 시스템이든 명령을 성공적으로 처리한 직후 전부에게 알린다.
func on_command(_state: CityState, _name: String, _args: Dictionary, _result: Dictionary) -> void:
	pass
