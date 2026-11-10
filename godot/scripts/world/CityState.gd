class_name CityState
extends RefCounted
## CityState — 렌더링 없는 순수 시뮬레이션 모델.
## 엔진 노드에 의존하지 않으므로 headless 밸런스 스크립트에서 그대로 사용 가능.
## 사용:
##   var city := CityState.new()
##   city.configure(Data.config, Data.economy, Data.industries, Data.policies, Data.residents)
##   city.new_game()
##   city.tick(dt_game_hours)
##
## 모든 수치는 데이터 파일(PLACEHOLDER)에서 읽는다. 여기서는 공식 골격만 정의.

signal changed                         # 요약 수치 변경(HUD)
signal cell_changed(cell: Vector3i)
signal harvest_ready(cell: Vector3i)
signal harvest_spoiled(cell: Vector3i)
signal household_arrived(household: Dictionary)
signal log_line(text: String)          # 기록 탭용 한 줄 로그

# --- 설정(주입) ---
var cfg: Dictionary = {}
var eco: Dictionary = {}
var ind_data: Dictionary = {}
var pol_data: Dictionary = {}
var res_data: Dictionary = {}

# --- 상태(저장 대상) ---
var treasury: int = 0
var prestige: int = 0
var day_count: int = 0
var elapsed_hours: float = 0.0
var rng_seed: int = 0
var rng_state: int = 0

## 셀: key "x,y,z" → Dictionary
##   { material:String, use:String("empty"|"housing"|"workplace"|"public"), industry_id:String,
##     occupant_id:int(-1 none), age_days:float, utility_level:int, taste:String,
##     pending_income:float, pending_since_hours:float, condition:float(0..100) }
var cells: Dictionary = {}

## 가구/사업체: id → { id, type, size, workers, taste, cell:"x,y,z", named_id }
var households: Dictionary = {}
var _next_household_id: int = 1

## 정책: axis_id → 선택값 (multi_select면 Array[String])
var policies: Dictionary = {}

## 누적 통계
var stats: Dictionary = { "total_income": 0, "total_spoiled": 0, "arrivals": 0 }

var _rng := RandomNumberGenerator.new()
var _inflow_accum: float = 0.0


# ------------------------------------------------------------------ 설정
func configure(config: Dictionary, economy: Dictionary, industries: Dictionary, policies_data: Dictionary, residents: Dictionary) -> void:
	cfg = config
	eco = economy
	ind_data = industries
	pol_data = policies_data
	res_data = residents


func new_game(seed_override: int = -1) -> void:
	rng_seed = seed_override if seed_override >= 0 else int(cfg.get("seed", 0))
	_rng.seed = rng_seed
	treasury = int(eco.get("starting_treasury", 0))
	prestige = int(eco.get("starting_prestige", 0))
	day_count = 0
	elapsed_hours = 0.0
	cells.clear()
	households.clear()
	_next_household_id = 1
	stats = { "total_income": 0, "total_spoiled": 0, "arrivals": 0 }
	_init_policies()
	_init_grid()
	# 오프닝: 황량한 부지에 첫 가옥 1칸 (튜토리얼 스토리는 후속 작업)
	var center := Vector3i(int(_grid_w() / 2), int(_grid_h() / 2), 0)
	_build_cell(center, _preferred_material(), "housing")
	_log("황량한 재개발 부지에 첫 가옥이 세워졌다.")
	changed.emit()


func _init_policies() -> void:
	policies.clear()
	for ax in pol_data.get("axes", []):
		policies[ax["id"]] = ax.get("default")


func _init_grid() -> void:
	# 지면(z=0)은 모두 'empty' 셀로 존재. 상층은 지어질 때 생성.
	for y in _grid_h():
		for x in _grid_w():
			cells[_key(Vector3i(x, y, 0))] = _empty_cell()


# ------------------------------------------------------------------ 틱
## dt_game_hours 만큼 시뮬레이션 전진. GameClock.ticked에 연결하거나 headless에서 직접 호출.
func tick(dt_game_hours: float) -> void:
	if dt_game_hours <= 0.0:
		return
	elapsed_hours += dt_game_hours
	var dt_days := dt_game_hours / float(cfg.get("time", {}).get("hours_per_day", 24))

	_tick_income(dt_game_hours)
	_tick_aging(dt_days)
	_tick_inflow(dt_days)
	_tick_prestige(dt_days)

	var new_day := int(floor(elapsed_hours / float(cfg.get("time", {}).get("hours_per_day", 24))))
	if new_day != day_count:
		day_count = new_day
	changed.emit()


## 하루 끝 처리 — GameClock.day_ended에서 호출. (제안 카드 생성 지점; 지금은 로그만)
func on_day_ended(day: int) -> void:
	_log("%d일차가 끝났다. 금고 %d, 인구 %d, 위신 %d" % [day + 1, treasury, population(), prestige])


# --- 수입: 일터 셀마다 pending_income 축적 → ripe 후 징수 가능 → spoil 후 손실
func _tick_income(dt_hours: float) -> void:
	var harvest: Dictionary = eco.get("harvest", {})
	var ripe_h := float(harvest.get("ripe_after_hours", 8))
	var spoil_h := float(harvest.get("spoil_after_hours", 20))
	var spoil_ratio := float(harvest.get("spoil_loss_ratio", 0.5))
	var hpd := float(cfg.get("time", {}).get("hours_per_day", 24))

	for key in cells.keys():
		var c: Dictionary = cells[key]
		if c["use"] != "workplace":
			continue
		var income_day := _industry_income_per_day(c["industry_id"])
		var was_ripe: bool = float(c["pending_since_hours"]) >= ripe_h
		c["pending_income"] += income_day * (dt_hours / hpd)
		c["pending_since_hours"] += dt_hours
		var cell := _unkey(key)
		if not was_ripe and c["pending_since_hours"] >= ripe_h:
			harvest_ready.emit(cell)
		if c["pending_since_hours"] >= spoil_h and c["pending_income"] > 0.0:
			var lost: float = float(c["pending_income"]) * spoil_ratio
			c["pending_income"] -= lost
			c["pending_since_hours"] = ripe_h  # 남은 절반은 다시 징수 가능 상태로
			stats["total_spoiled"] += int(lost)
			harvest_spoiled.emit(cell)
			_log("%s 의 수확이 방치되어 %d 상했다." % [_industry_name(c["industry_id"]), int(lost)])


## 플레이어 행동: 특정 셀 징수. ripe 전이면 0 반환.
func harvest_cell(cell: Vector3i) -> int:
	var c: Dictionary = cells.get(_key(cell), {})
	if c.is_empty() or c["use"] != "workplace":
		return 0
	var ripe_h := float(eco.get("harvest", {}).get("ripe_after_hours", 8))
	if c["pending_since_hours"] < ripe_h:
		return 0
	var gross := int(c["pending_income"])
	var tax_rate := float(eco.get("tax", {}).get("rate_default", 0.2))
	var to_treasury := int(round(gross * tax_rate * _price_mult()))
	treasury += to_treasury
	stats["total_income"] += to_treasury
	c["pending_income"] = 0.0
	c["pending_since_hours"] = 0.0
	cell_changed.emit(cell)
	changed.emit()
	return to_treasury


## 모든 ripe 셀 일괄 징수(디버그/편의).
func harvest_all() -> int:
	var total := 0
	for key in cells.keys():
		total += harvest_cell(_unkey(key))
	return total


func _tick_aging(dt_days: float) -> void:
	for key in cells.keys():
		var c: Dictionary = cells[key]
		if c["use"] == "empty":
			continue
		c["age_days"] += dt_days


## 유입: 하루 기본 확률 × 정책 보정. 누적치가 1 넘으면 가구 1개 도착 → 빈 셀/신규 셀에 입주.
func _tick_inflow(dt_days: float) -> void:
	var base := float(eco.get("growth", {}).get("inflow_base_per_day", 1.0))
	var mult := float(_policy_effect("inflow_mult", 1.0))
	mult *= 1.0 + prestige / 10.0 * float(eco.get("prestige", {}).get("inflow_quality_per_10", 0.1))
	_inflow_accum += base * mult * dt_days
	while _inflow_accum >= 1.0:
		_inflow_accum -= 1.0
		_spawn_household()


func _tick_prestige(dt_days: float) -> void:
	var per_day := float(_policy_effect("prestige_per_day", 0.0))
	# 산업 위신 영향 (일터 셀마다)
	for key in cells.keys():
		var c: Dictionary = cells[key]
		if c["use"] == "workplace":
			var ind: Dictionary = _industry(c["industry_id"])
			per_day += float(ind.get("prestige_delta", 0)) * 0.1
	var p: Dictionary = eco.get("prestige", {})
	prestige = clampi(int(round(prestige + per_day * dt_days)), int(p.get("min", -50)), int(p.get("max", 100)))


# ------------------------------------------------------------------ 성장
func _spawn_household() -> void:
	var types: Array = res_data.get("household_types", [])
	if types.is_empty():
		return
	var t: Dictionary = types[_rng.randi_range(0, types.size() - 1)]
	var size := _rng.randi_range(int(t.get("size_min", 1)), int(t.get("size_max", 1)))
	var nonworker_ratio := float(_policy_effect("nonworker_ratio", 0.2))
	var workers := int(round(size * float(t.get("worker_ratio", 1.0)) * (1.0 - nonworker_ratio)))
	var tastes: Array = res_data.get("tastes", [])
	var taste: String = tastes[_rng.randi_range(0, tastes.size() - 1)]["id"] if not tastes.is_empty() else "plain"

	var hh := {
		"id": _next_household_id, "type": t["id"], "size": size, "workers": workers,
		"taste": taste, "cell": "", "named_id": "",
	}
	_next_household_id += 1

	# 대표인물 도착(날짜 조건) — 아직 미등장인 인물 중 arrives_day <= 현재 day
	for r in res_data.get("named_residents", []):
		if int(r.get("arrives_day", 9999)) <= day_count and not _named_present(r["id"]):
			hh["named_id"] = r["id"]
			hh["taste"] = r.get("taste", taste)
			break

	# 입주할 셀: 빈 지면 셀 우선, 없으면 증축(상층)
	var use := "workplace" if t["id"] == "business" else "housing"
	var cell := _find_or_build_cell(use)
	if cell == Vector3i(-1, -1, -1):
		_log("자리가 없어 가구가 발길을 돌렸다.")
		return
	var c: Dictionary = cells[_key(cell)]
	c["occupant_id"] = hh["id"]
	c["taste"] = hh["taste"]
	if use == "workplace":
		c["industry_id"] = _pick_permitted_industry()
	hh["cell"] = _key(cell)
	households[hh["id"]] = hh
	stats["arrivals"] += 1
	cell_changed.emit(cell)
	household_arrived.emit(hh)
	if hh["named_id"] != "":
		var r: Dictionary = _named(hh["named_id"])
		_log("%s(%s) 도착: %s" % [r.get("name", "?"), r.get("role", ""), r.get("intro", "")])
	else:
		_log("%s %d명이 들어왔다." % [t.get("name", "가구"), size])


func _find_or_build_cell(use: String) -> Vector3i:
	# 1) 이미 지어졌지만 비어 있는 셀
	for key in cells.keys():
		var c: Dictionary = cells[key]
		if c["use"] != "empty" and c["occupant_id"] == -1 and c["use"] == use:
			return _unkey(key)
	# 2) 기존 건물에 인접한 빈 지면 셀 → 신축 (비용)
	var cost := int(eco.get("growth", {}).get("new_cell_cost", 50))
	var growth_mult := float(_policy_effect("growth_mult", 1.0))
	cost = int(cost / growth_mult)
	var candidates: Array[Vector3i] = []
	for key in cells.keys():
		var c: Dictionary = cells[key]
		var v := _unkey(key)
		if v.z == 0 and c["use"] == "empty" and _has_built_neighbor(v):
			candidates.append(v)
	# 3) 지면 없으면 상층 증축
	if candidates.is_empty():
		for key in cells.keys():
			var v := _unkey(key)
			var above := Vector3i(v.x, v.y, v.z + 1)
			if cells[key]["use"] != "empty" and above.z < _max_floors() and not cells.has(_key(above)):
				candidates.append(above)
		cost = int(cost * float(eco.get("growth", {}).get("new_floor_cost_mult", 1.5)))
	if candidates.is_empty():
		return Vector3i(-1, -1, -1)
	if treasury < cost:
		return Vector3i(-1, -1, -1)
	treasury -= cost
	var pick := candidates[_rng.randi_range(0, candidates.size() - 1)]
	_build_cell(pick, _preferred_material(), use)
	return pick


func _build_cell(cell: Vector3i, material: String, use: String) -> void:
	var c := _empty_cell()
	c["material"] = material
	c["use"] = use
	c["utility_level"] = int(_policy_effect("utility_growth", 0))
	cells[_key(cell)] = c
	cell_changed.emit(cell)


func _has_built_neighbor(v: Vector3i) -> bool:
	for d: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
		var n: Vector3i = v + d
		if cells.has(_key(n)) and cells[_key(n)]["use"] != "empty":
			return true
	return false


func _pick_permitted_industry() -> String:
	var permitted: Array = policies.get("industry_permit", [])
	var pool: Array = []
	for ind in ind_data.get("industries", []):
		if ind["category"] in permitted and int(ind.get("unlock_day", 0)) <= day_count:
			pool.append(ind["id"])
	if pool.is_empty():
		return ""
	return pool[_rng.randi_range(0, pool.size() - 1)]


# ------------------------------------------------------------------ 정책
func set_policy(axis_id: String, value) -> void:
	policies[axis_id] = value
	_log("정책 변경: %s → %s" % [axis_id, str(value)])
	changed.emit()


## 현재 선택된 모든 정책 옵션의 effects에서 key를 모아 합산/곱산.
## *_mult 는 곱, 나머지는 합. 없으면 default.
func _policy_effect(key: String, default: Variant) -> Variant:
	var found := false
	var acc: float = 1.0 if key.ends_with("_mult") else 0.0
	var str_val := ""
	for ax in pol_data.get("axes", []):
		var sel = policies.get(ax["id"])
		var selected: Array = sel if typeof(sel) == TYPE_ARRAY else [sel]
		for opt in ax.get("options", []):
			if opt["id"] in selected and opt.get("effects", {}).has(key):
				found = true
				var v = opt["effects"][key]
				if typeof(v) == TYPE_STRING:
					str_val = v
				elif key.ends_with("_mult"):
					acc *= float(v)
				else:
					acc += float(v)
	if not found:
		return default
	if str_val != "":
		return str_val
	return acc


func _preferred_material() -> String:
	return str(_policy_effect("preferred_material", "wood"))


func _price_mult() -> float:
	return 1.0 + prestige / 10.0 * float(eco.get("prestige", {}).get("price_mult_per_10", 0.05))


# ------------------------------------------------------------------ 조회
func population() -> int:
	var n := 0
	for hh in households.values():
		n += int(hh["size"])
	return n

func workers() -> int:
	var n := 0
	for hh in households.values():
		n += int(hh["workers"])
	return n

func workplace_count() -> int:
	var n := 0
	for c in cells.values():
		if c["use"] == "workplace":
			n += 1
	return n

func built_cell_count() -> int:
	var n := 0
	for c in cells.values():
		if c["use"] != "empty":
			n += 1
	return n

func get_cell(cell: Vector3i) -> Dictionary:
	return cells.get(_key(cell), {})

## 도시 성향에 따른 플레이어 호칭 (residents.json player_titles)
func player_title() -> String:
	var pt: Dictionary = res_data.get("player_titles", {})
	var counts := {}
	for c in cells.values():
		if c["use"] == "workplace" and c["industry_id"] != "":
			var cat: String = _industry(c["industry_id"]).get("category", "")
			counts[cat] = counts.get(cat, 0) + 1
	var dominant := ""
	var best := 0
	for k in counts:
		if counts[k] > best:
			best = counts[k]
			dominant = k
	for rule in pt.get("by_condition", []):
		var w: Dictionary = rule.get("when", {})
		if w.has("dominant_category") and w["dominant_category"] != dominant:
			continue
		if w.has("min_population") and population() < int(w["min_population"]):
			continue
		return rule["title"]
	return str(pt.get("default", "대장"))


func summary() -> Dictionary:
	return {
		"day": day_count, "treasury": treasury, "population": population(), "workers": workers(),
		"prestige": prestige, "cells": built_cell_count(), "workplaces": workplace_count(),
		"title": player_title(),
	}


# ------------------------------------------------------------------ 저장
func to_save() -> Dictionary:
	return {
		"treasury": treasury, "prestige": prestige, "day_count": day_count, "elapsed_hours": elapsed_hours,
		"rng_seed": rng_seed, "rng_state": _rng.state,
		"cells": cells.duplicate(true), "households": _households_for_save(), "next_household_id": _next_household_id,
		"policies": policies.duplicate(true), "stats": stats.duplicate(true), "inflow_accum": _inflow_accum,
	}

func from_save(d: Dictionary) -> void:
	treasury = int(d.get("treasury", 0))
	prestige = int(d.get("prestige", 0))
	day_count = int(d.get("day_count", 0))
	elapsed_hours = float(d.get("elapsed_hours", 0.0))
	rng_seed = int(d.get("rng_seed", 0))
	_rng.seed = rng_seed
	if d.has("rng_state"):
		_rng.state = int(d["rng_state"])
	cells = d.get("cells", {}).duplicate(true)
	# JSON은 정수 키를 문자열로 저장하므로 복원
	households.clear()
	for k in d.get("households", {}).keys():
		var hh: Dictionary = d["households"][k].duplicate(true)
		hh["id"] = int(hh["id"])
		households[int(k)] = hh
	_next_household_id = int(d.get("next_household_id", households.size() + 1))
	policies = d.get("policies", {}).duplicate(true)
	stats = d.get("stats", stats).duplicate(true)
	_inflow_accum = float(d.get("inflow_accum", 0.0))
	changed.emit()

func _households_for_save() -> Dictionary:
	var out := {}
	for k in households.keys():
		out[str(k)] = households[k]
	return out


# ------------------------------------------------------------------ 내부 유틸
static func _key(v: Vector3i) -> String:
	return "%d,%d,%d" % [v.x, v.y, v.z]

static func _unkey(k: String) -> Vector3i:
	var p := k.split(",")
	return Vector3i(int(p[0]), int(p[1]), int(p[2]))

func _empty_cell() -> Dictionary:
	return {
		"material": "", "use": "empty", "industry_id": "", "occupant_id": -1,
		"age_days": 0.0, "utility_level": 0, "taste": "plain",
		"pending_income": 0.0, "pending_since_hours": 0.0, "condition": 100.0,
	}

func _grid_w() -> int: return int(cfg.get("grid", {}).get("width", 12))
func _grid_h() -> int: return int(cfg.get("grid", {}).get("height", 12))
func _max_floors() -> int: return int(cfg.get("grid", {}).get("max_floors", 8))

func _industry(id: String) -> Dictionary:
	for ind in ind_data.get("industries", []):
		if ind["id"] == id:
			return ind
	return {}

func _industry_name(id: String) -> String:
	return str(_industry(id).get("name", id if id != "" else "미지정"))

func _industry_income_per_day(id: String) -> float:
	var ind := _industry(id)
	if ind.has("income_per_day"):
		return float(ind["income_per_day"])
	return float(eco.get("income", {}).get("base_per_workplace_per_day", 10))

func _named(id: String) -> Dictionary:
	for r in res_data.get("named_residents", []):
		if r["id"] == id:
			return r
	return {}

func _named_present(id: String) -> bool:
	for hh in households.values():
		if hh.get("named_id", "") == id:
			return true
	return false

func _log(text: String) -> void:
	log_line.emit(text)
