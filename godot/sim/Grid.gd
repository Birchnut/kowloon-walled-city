class_name Grid
extends RefCounted
## Grid — 공간 도우미(순수 함수). 좌표 Vector3i(x, y, z), z = 층.
## 볕 수치는 data/economy.json "sun" (sky, side, canyon).

const N4: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
const N6: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


static func inside(sim: Sim, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < sim.W and y < sim.H


static func height(sim: Sim, state: CityState, x: int, y: int) -> int:
	for z: int in range(sim.F - 1, -1, -1):
		if state.cells.has(Vector3i(x, y, z)):
			return z + 1
	return 0


## 완공된 셀인가(공사 중인 칸 위에는 못 짓는다).
static func solid(state: CityState, pos: Vector3i) -> bool:
	return state.cells.has(pos) and state.cells[pos].get("kind", "") != "site"


## 지지 규칙: 지상이거나, 바로 아래에 셀이 있거나, (허공 증축 표시가 있고) 옆에 붙은 셀이 있거나.
static func supported(state: CityState, pos: Vector3i) -> bool:
	if pos.z == 0 or state.cells.has(pos + Vector3i(0, 0, -1)):
		return true
	if state.cells.get(pos, {}).get("cantilever", false):
		for d: Vector3i in N4:
			if state.cells.has(pos + d):
				return true
	return false


static func sky_open(sim: Sim, state: CityState, pos: Vector3i) -> bool:
	for z: int in range(pos.z + 1, sim.F):
		if state.cells.has(Vector3i(pos.x, pos.y, z)):
			return false
	return true


## 볕 0..1 — 머리 위가 열렸는가 + 옆이 트였는가 − 이웃이 훨씬 높아 골짜기인가.
static func sunlight(sim: Sim, state: CityState, pos: Vector3i) -> float:
	var open_sides := 0
	var taller := 0
	for d: Vector3i in N4:
		var p := pos + d
		if not inside(sim, p.x, p.y) or not state.cells.has(p):
			open_sides += 1
		if inside(sim, p.x, p.y) and state.cells.has(Vector3i(p.x, p.y, pos.z + 2)):
			taller += 1
	var s := float(open_sides) / 4.0 * sim.num("sun.side", 0.4)
	if sky_open(sim, state, pos):
		s += sim.num("sun.sky", 0.6) - sim.num("sun.canyon", 0.3) * float(taller) / 4.0
	return clampf(s, 0.0, 1.0)


## 이 기둥이 자재 강도로 버틸 수 있는 높이(층 수). 약한 자재가 아래 있으면 낮다.
static func load_cap(sim: Sim, state: CityState, x: int, y: int) -> int:
	var cap := sim.F
	for z: int in sim.F:
		var c: Dictionary = state.cells.get(Vector3i(x, y, z), {})
		if c.is_empty():
			continue
		var mat := str(c.get("becomes", c).get("material", ""))
		cap = mini(cap, z + 1 + int(sim.item("materials", mat).get("load", 99)))
	return cap


## 대문에서의 거리(칸).
static func gate_dist(sim: Sim, x: int, y: int) -> float:
	return absf(float(x - sim.gate.x)) + absf(float(y - sim.gate.y))


## 가장자리까지의 거리(0 = 담장 옆).
static func edge_dist(sim: Sim, x: int, y: int) -> int:
	return mini(mini(x, sim.W - 1 - x), mini(y, sim.H - 1 - y))
