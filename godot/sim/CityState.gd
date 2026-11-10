class_name CityState
extends RefCounted
## CityState — 저장되는 도시 상태 전부. 데이터만. 규칙은 sim/systems/* 에 있다.
## 필드 이름은 docs/ARCHITECTURE.md의 계약이다. 바꾸려면 문서를 먼저 고친다.
## 좌표: Vector3i(x, y, z) — x,y = 부지 칸, z = 층(0 = 지상).

const SAVE_VERSION := 2

# ── 시간 ──
var rng_seed: int = 0
var rng_state: int = 0
var day: int = 1            # 1부터
var hour: float = 6.0       # 0.0 ~ 24.0

# ── 재고 ──
var money: float = 0.0
var food: float = 0.0
var materials: float = 0.0

# ── 지표 0..100 ──
var prestige: float = 0.0   # 위신
var notoriety: float = 0.0  # 악명
var morale: float = 50.0    # 민심

# ── 기반 ──
var power_level: int = 0    # 0 없음 / 1 발전기 / 2 외부 계약
var water_cap: int = 0      # 물이 감당하는 인구

# ── 플레이어 설정 ──
var policies: Dictionary = {}        # axis id -> option id
var zones: Dictionary = {}           # Vector2i -> "housing" | "work" | "keep"

# ── 공간 ──
var cells: Dictionary = {}           # Vector3i -> Dictionary (셀 계약은 ARCHITECTURE.md)

# ── 사람·사업 ──
var households: Dictionary = {}      # int -> {id,type,size,home,job,named,arrived_day,...}
var businesses: Dictionary = {}      # int -> {id,type,group,cells,workers,opened_day,...}
var next_id: int = 1

# ── 수금 ──
var collect_points: Dictionary = {}  # int -> {id,pos,amount,cap,skimmed}
var alley_fund: float = 0.0          # 뒷골목 금고

# ── 진행 ──
var pending_cards: Array = []        # [{uid,card,title,body,speaker,choices:[{label,hint}],day}]
var unlocked: Dictionary = {}        # id -> day
var flags: Dictionary = {}           # 시스템별 자유 메모
var identity: Dictionary = {"title": "대장", "epithet": "", "tags": []}
var logbook: Array = []              # [{day,hour,text,tone}]
var stats: Dictionary = {}           # 누적 통계(자유)
var last_saved_unix: int = 0

# ── 저장 안 함 ──
var events: Array = []               # [{name, payload}] — Game이 매 틱 비운다


# ------------------------------------------------------------------ 도우미
func emit(name: String, payload: Dictionary = {}) -> void:
	events.append({"name": name, "payload": payload})


func new_id() -> int:
	var id := next_id
	next_id += 1
	return id


func has_cell(pos: Vector3i) -> bool:
	return cells.has(pos)


func cell(pos: Vector3i) -> Dictionary:
	return cells.get(pos, {})


## 기둥의 높이 = 가장 높은 셀의 z + 1. 비어 있으면 0.
func column_height(col: Vector2i, max_floors: int = 32) -> int:
	for z in range(max_floors - 1, -1, -1):
		if cells.has(Vector3i(col.x, col.y, z)):
			return z + 1
	return 0


func population() -> int:
	var n := 0
	for h in households.values():
		n += int(h.get("size", 1))
	return n


func add_log(text: String, tone: String = "") -> void:
	logbook.append({"day": day, "hour": hour, "text": text, "tone": tone})
	if logbook.size() > 200:
		logbook = logbook.slice(logbook.size() - 200)
	emit("log", {"text": text, "tone": tone})


# ------------------------------------------------------------------ 직렬화
static func key3(p: Vector3i) -> String:
	return "%d,%d,%d" % [p.x, p.y, p.z]


static func key2(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]


static func parse3(s: String) -> Vector3i:
	var a := s.split(",")
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))


static func parse2(s: String) -> Vector2i:
	var a := s.split(",")
	return Vector2i(int(a[0]), int(a[1]))


## Vector3i/Vector2i가 값으로 들어간 구조를 JSON 가능한 형태로(재귀).
static func _enc(v: Variant) -> Variant:
	if v is Vector3i:
		return {"_v3": [v.x, v.y, v.z]}
	if v is Vector2i:
		return {"_v2": [v.x, v.y]}
	if v is Dictionary:
		var d := {}
		for k in v:
			var kk: Variant = k
			if k is Vector3i:
				kk = "v3:" + key3(k)
			elif k is Vector2i:
				kk = "v2:" + key2(k)
			elif k is int:
				kk = "i:" + str(k)
			d[kk] = _enc(v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_enc(x))
		return a
	return v


static func _dec(v: Variant) -> Variant:
	if v is Dictionary:
		if v.size() == 1 and v.has("_v3"):
			var a: Array = v["_v3"]
			return Vector3i(int(a[0]), int(a[1]), int(a[2]))
		if v.size() == 1 and v.has("_v2"):
			var b: Array = v["_v2"]
			return Vector2i(int(b[0]), int(b[1]))
		var d := {}
		for k in v:
			var kk: Variant = k
			if k is String:
				if k.begins_with("v3:"):
					kk = parse3(k.substr(3))
				elif k.begins_with("v2:"):
					kk = parse2(k.substr(3))
				elif k.begins_with("i:"):
					kk = int(k.substr(2))
			d[kk] = _dec(v[k])
		return d
	if v is Array:
		var out := []
		for x in v:
			out.append(_dec(x))
		return out
	return v


const _FIELDS := [
	"rng_seed", "rng_state", "day", "hour", "money", "food", "materials",
	"prestige", "notoriety", "morale", "power_level", "water_cap",
	"policies", "zones", "cells", "households", "businesses", "next_id",
	"collect_points", "alley_fund", "pending_cards", "unlocked", "flags",
	"identity", "logbook", "stats", "last_saved_unix",
]

const _INT_FIELDS := ["rng_seed", "rng_state", "day", "power_level", "water_cap", "next_id", "last_saved_unix"]


func to_dict() -> Dictionary:
	var d := {"version": SAVE_VERSION}
	for f in _FIELDS:
		d[f] = _enc(get(f))
	return d


## 모르는 필드는 무시, 없는 필드는 기본값 유지 → 세이브 호환이 느슨하다(피봇 친화).
func from_dict(d: Dictionary) -> void:
	for f in _FIELDS:
		if d.has(f):
			var v: Variant = _dec(d[f])
			if f in _INT_FIELDS:
				v = int(v)
			set(f, v)
	_fix_ints()


## JSON 왕복 후 float가 된 정수 필드를 되돌린다(셀·가구·사업체의 알려진 정수 키).
func _fix_ints() -> void:
	for c in cells.values():
		for k in ["owner", "built_day", "seed"]:
			if c.has(k):
				c[k] = int(c[k])
	for coll in [households, businesses, collect_points]:
		for e in coll.values():
			for k in ["id", "size", "job", "arrived_day", "opened_day"]:
				if e.has(k):
					e[k] = int(e[k])
			if e.has("workers"):
				var w := []
				for x in e["workers"]:
					w.append(int(x))
				e["workers"] = w
	for c in pending_cards:
		if c.has("uid"):
			c["uid"] = int(c["uid"])
