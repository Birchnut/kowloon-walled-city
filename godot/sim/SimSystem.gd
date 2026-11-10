class_name SimSystem
extends RefCounted
## SimSystem — 모든 규칙 묶음(sim/systems/<id>.gd)의 공통 모양. 전부 선택 구현(기본은 아무것도 안 함).
## 시스템끼리는 서로를 부르지 않는다. CityState만 읽고 쓴다. config.json "systems"에서 id를 빼면 그 규칙은 사라진다.

var sim: Sim


func setup(s: Sim) -> void:
	sim = s


func on_new_game(_state: CityState) -> void:
	pass


## 매 틱(도시 시간 dt). 접속 중에도, 미접속 빨리감기 중에도 불린다(sim.offline으로 구분).
func tick(_state: CityState, _dt: float) -> void:
	pass


func on_hour(_state: CityState, _hour: int) -> void:
	pass


## state.day = 방금 끝난 날.
func on_day_end(_state: CityState) -> void:
	pass


func on_day_start(_state: CityState) -> void:
	pass


## 빨리감기가 끝난 뒤 "자리를 비운 사이" 요약 줄을 lines에 덧붙인다. before = 떠나기 전 metrics.
func fast_forward(_state: CityState, _hours: float, _before: Dictionary, _lines: Array) -> void:
	pass


## 이름으로 찾을 수 있는 지표를 m에 보탠다(조건식·UI·디버그 공용).
func metrics(_state: CityState, _m: Dictionary) -> void:
	pass


## 아래 셋은 "내 명령/질의가 아니면 null".
func can(_state: CityState, _name: String, _args: Dictionary) -> Variant:
	return null


func apply(_state: CityState, _name: String, _args: Dictionary) -> Variant:
	return null


func query(_state: CityState, _name: String, _args: Dictionary) -> Variant:
	return null


## cell_info에 줄을 보탠다. info = {title, subtitle, lines[], actions[]}. cell이 비면 빈 칸.
func describe(_state: CityState, _pos: Vector3i, _cell: Dictionary, _info: Dictionary) -> void:
	pass
