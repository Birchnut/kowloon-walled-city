class_name CityState
extends RefCounted
## CityState v3 — 저장되는 도시 상태 전부. 데이터만. 규칙은 sim/systems/* 에 있다.
## 필드 이름은 docs/ARCHITECTURE.md의 계약이다(SIM이 보탠 필드는 docs/SIM_NOTES.md "상태 추가 필드").
## 좌표: Vector3i(x, y, z) — x,y = 부지 칸, z = 층(0 = 지상).

const SAVE_VERSION := 3

# ── 시간·RNG ──
var rng_seed: int = 0
var rng_state: int = 0
var econ_days: float = 0.0      # 시작부터의 경제일
var day: int = 1                # 파생: floor(econ_days) + 1
var hour: float = 6.0           # 파생: 0~24

# ── 금고·재고 ──
var money: float = 0.0
var stock: Dictionary = {}      # good -> float

# ── 공간 ──
var cells: Dictionary = {}      # Vector3i -> 셀(ARCHITECTURE 셀 계약)
var supports: Dictionary = {}   # Vector3i -> true (골조)
var buildings: Dictionary = {}  # int -> 건물 인스턴스
var floors_unlocked: int = 1

# ── 사람 ──
var waiting: Dictionary = {}    # tier(int) -> {count:int, days_left:float}

# ── 교역·탐험(B) ──
var contracts: Array = []
var partners: Dictionary = {}   # id -> true
var teams: Array = []
var dests: Dictionary = {}

# ── 진행 ──
var research: Dictionary = {"done": {}, "active": {}}
var policies: Dictionary = {}
var unlocked: Dictionary = {}   # id -> econ_day
var milestone: int = 0
var heat: float = 0.0
var happiness: float = 50.0

# ── 회계·흐름 ──
var ledger: Dictionary = {"today": {}, "days": []}
var flow: Dictionary = {}       # good -> {prod, cons, imp, exp} (경제일당, 지수 이동 평균)

# ── SIM 추가 필드(파생이지만 표시·결정론용으로 저장) ──
var util: Dictionary = {}       # "water"/"power" -> {supply, demand, res_demand, fac_demand, res_ratio, fac_ratio}
var labor: Dictionary = {}      # tier(int) -> {have:int, need:float, used:float}
var next_id: int = 1

# ── 기타 ──
var clock_offset: int = 0
var flags: Dictionary = {}
var logbook: Array = []
var stats: Dictionary = {}
var identity: Dictionary = {"title": "대장", "grade_name": "공터"}
var last_saved_unix: int = 0

# ── 저장 안 함 ──
var events: Array = []


# ------------------------------------------------------------------ 도우미
func emit(name: String, payload: Dictionary = {}) -> void:
	events.append({"name": name, "payload": payload})


func new_id() -> int:
	var id := next_id
	next_id += 1
	return id


func cell(pos: Vector3i) -> Dictionary:
	return cells.get(pos, {})


func has_cell(pos: Vector3i) -> bool:
	return cells.has(pos)


func add_log(text: String, tone: String = "") -> void:
	logbook.append({"day": day, "hour": snappedf(hour, 0.01), "text": text, "tone": tone})
	if logbook.size() > 300:
		logbook = logbook.slice(logbook.size() - 300)
	emit("log", {"text": text, "tone": tone})


## 장부 한 줄(부호 있는 금액: 수입 +, 지출 −).
func book(line: String, amount: float) -> void:
	var t: Dictionary = ledger.get("today", {})
	t[line] = float(t.get(line, 0.0)) + amount
	ledger["today"] = t


func stat_add(key: String, x: float) -> void:
	stats[key] = float(stats.get(key, 0.0)) + x


func layout_changed() -> void:
	flags["layout_rev"] = int(flags.get("layout_rev", 0)) + 1


func layout_rev() -> int:
	return int(flags.get("layout_rev", 0))


## 총인구 = 주거 주민 + 대기 주민.
func population() -> int:
	var n := 0
	for b: Dictionary in buildings.values():
		if b.get("kind", "") == "house":
			n += int(b.get("residents", 0))
	for t: Variant in waiting:
		n += int(waiting[t].get("count", 0))
	return n


# ------------------------------------------------------------------ 직렬화
static func key3(p: Vector3i) -> String:
	return "%d,%d,%d" % [p.x, p.y, p.z]


static func parse3(s: String) -> Vector3i:
	var a := s.split(",")
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))


static func _enc(v: Variant) -> Variant:
	if v is Vector3i:
		return {"_v3": [v.x, v.y, v.z]}
	if v is Vector2i:
		return {"_v2": [v.x, v.y]}
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			var kk: Variant = k
			if k is Vector3i:
				kk = "v3:" + key3(k)
			elif k is int:
				kk = "i:" + str(k)
			d[kk] = _enc(v[k])
		return d
	if v is Array:
		var a := []
		for x: Variant in v:
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
		for k: Variant in v:
			var kk: Variant = k
			if k is String:
				if k.begins_with("v3:"):
					kk = parse3(k.substr(3))
				elif k.begins_with("i:"):
					kk = int(k.substr(2))
			d[kk] = _dec(v[k])
		return d
	if v is Array:
		var out := []
		for x: Variant in v:
			out.append(_dec(x))
		return out
	return v


const _FIELDS := [
	"rng_seed", "rng_state", "econ_days", "day", "hour", "money", "stock",
	"cells", "supports", "buildings", "floors_unlocked", "waiting",
	"contracts", "partners", "teams", "dests", "research", "policies", "unlocked", "milestone", "heat", "happiness",
	"ledger", "flow", "util", "labor", "next_id", "clock_offset", "flags", "logbook", "stats", "identity", "last_saved_unix",
]
const _INT_FIELDS := ["rng_seed", "rng_state", "day", "floors_unlocked", "milestone", "next_id", "clock_offset", "last_saved_unix"]
## JSON 왕복 후 float가 된 정수 값을 키 이름으로 되돌린다(재귀). 새 정수 키는 여기에 추가.
const _INT_KEYS := ["id", "bid", "tier", "residents", "cap", "size", "seed", "count", "day", "visits", "to", "have",
	"layout_rev", "milestone", "grade", "started_unix", "completes_unix", "built", "floor", "target", "nsig", "sdm", "sdc"]


func to_dict() -> Dictionary:
	var d := {"version": SAVE_VERSION}
	for f: String in _FIELDS:
		d[f] = _enc(get(f))
	return d


func from_dict(d: Dictionary) -> bool:
	if int(d.get("version", 0)) != SAVE_VERSION:
		return false
	for f: String in _FIELDS:
		if d.has(f):
			var v: Variant = _dec(d[f])
			if f in _INT_FIELDS:
				v = int(v)
			set(f, v)
	for coll: Variant in [cells, buildings, waiting, contracts, teams, dests, labor, flags, logbook, stats, ledger]:
		_fix_ints_in(coll)
	return true


static func _fix_ints_in(v: Variant) -> void:
	if v is Dictionary:
		for k: Variant in v:
			var x: Variant = v[k]
			if x is float and k is String and k in _INT_KEYS:
				v[k] = int(x)
			elif x is Dictionary or x is Array:
				_fix_ints_in(x)
	elif v is Array:
		for e: Variant in v:
			_fix_ints_in(e)


## 저장·스냅샷은 반드시 이 한 쌍으로. 키 순서 = 삽입 순서(결정론의 일부).
func to_json() -> String:
	settle()
	return JSON.stringify(to_dict(), "", false)


func from_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	return from_dict(parsed)


## 모든 float를 "JSON에 썼다 읽은 값"으로 제자리에서 맞춘다 → 저장 후 이어한 게임 = 불러와 이어한 게임.
func settle() -> void:
	for f: String in _FIELDS:
		var v: Variant = get(f)
		if v is float:
			set(f, _settle_f(v))
		elif v is Dictionary or v is Array:
			_settle_in(v)


static func _settle_f(x: float) -> float:
	if x == floorf(x) and absf(x) < 1.0e15:
		return x
	return float(JSON.parse_string(JSON.stringify(x)))


static func _settle_in(v: Variant) -> void:
	if v is Dictionary:
		for k: Variant in v:
			var x: Variant = v[k]
			if x is float:
				v[k] = _settle_f(x)
			elif x is Dictionary or x is Array:
				_settle_in(x)
	elif v is Array:
		for i: int in v.size():
			var x: Variant = v[i]
			if x is float:
				v[i] = _settle_f(x)
			elif x is Dictionary or x is Array:
				_settle_in(x)
