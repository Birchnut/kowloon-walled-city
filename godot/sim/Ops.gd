class_name Ops
extends RefCounted
## Ops — 여러 시스템이 같이 쓰는 "상태 고치기" 묶음(가구·사업체·셀을 넣고 빼기). 규칙은 없다:
## 연결(집↔가구, 일터↔일꾼, 셀↔사업체)을 깨지지 않게 잇고 끊고, 이벤트를 쌓기만 한다.


# ------------------------------------------------------------------ 가구
## 새 가구를 대문 앞에 세운다(home = null). extra로 named·kin·size를 덮어쓸 수 있다.
static func add_household(sim: Sim, state: CityState, type: String, extra: Dictionary = {}) -> int:
	var d := sim.item("households", type)
	var sz: Array = d.get("size", [1, 2])
	var id := state.new_id()
	var h := {
		"id": id, "type": type, "size": sim.roll_range(state, int(sz[0]), int(sz[1])),
		"home": null, "job": 0, "named": "", "arrived_day": state.day, "kin": 0,
	}
	h.merge(extra, true)
	state.households[id] = h
	state.emit("household_arrived", {"id": id})
	return id


static func remove_household(state: CityState, id: int, reason: String) -> void:
	if not state.households.has(id):
		return
	vacate(state, id)
	quit_job(state, id)
	state.households.erase(id)
	state.stats["left_" + reason] = int(state.stats.get("left_" + reason, 0)) + 1
	state.stats["left_total"] = int(state.stats.get("left_total", 0)) + 1
	state.emit("household_left", {"id": id, "reason": reason})


static func capacity(sim: Sim, cell: Dictionary) -> int:
	if cell.get("kind", "") != "housing":
		return 0
	return int(sim.item("housing", str(cell.get("type", ""))).get("capacity", 1))


static func free_slots(sim: Sim, cell: Dictionary) -> int:
	return capacity(sim, cell) - (cell.get("residents", []) as Array).size()


static func move_in(state: CityState, id: int, pos: Vector3i) -> void:
	var h: Dictionary = state.households[id]
	var c: Dictionary = state.cells[pos]
	if not c.has("residents"):
		c["residents"] = []
	c["residents"].append(id)
	if int(c.get("owner", 0)) == 0:
		c["owner"] = id
	h["home"] = pos
	h.erase("wait_since")
	state.emit("cell_changed", {"pos": pos})


## 집에서 나온다(대문 앞으로). 가구는 남는다.
static func vacate(state: CityState, id: int) -> void:
	var h: Dictionary = state.households.get(id, {})
	var home: Variant = h.get("home")
	if home == null:
		return
	var c: Dictionary = state.cells.get(home, {})
	if c.has("residents"):
		c["residents"].erase(id)
		if int(c.get("owner", 0)) == id:
			c["owner"] = int(c["residents"][0]) if not c["residents"].is_empty() else 0
		state.emit("cell_changed", {"pos": home})
	h["home"] = null


static func quit_job(state: CityState, id: int) -> void:
	var h: Dictionary = state.households.get(id, {})
	var job := int(h.get("job", 0))
	if job != 0 and state.businesses.has(job):
		state.businesses[job]["workers"].erase(id)
	if not h.is_empty():
		h["job"] = 0


# ------------------------------------------------------------------ 사업체(= 일자리 장부. 앵커 시설도 여기 한 줄씩 가진다)
static func open_business(sim: Sim, state: CityState, type: String, pos: Vector3i, anchor: bool) -> int:
	var d := sim.item("facilities" if anchor else "businesses", type)
	var id := state.new_id()
	state.businesses[id] = {
		"id": id, "type": type, "group": str(d.get("group", "public")), "cells": [pos], "workers": [],
		"opened_day": state.day, "jobs": int(d.get("jobs", 0)), "facility": anchor,
	}
	if not anchor:
		state.emit("business_opened", {"id": id, "pos": pos})
	return id


## 폐업. 일꾼은 실업자가 되고, 자리는 빈 방으로 남는다(위에 얹힌 셀이 무너지지 않게 셀은 안 지운다).
static func close_business(sim: Sim, state: CityState, id: int, why: String) -> void:
	if not state.businesses.has(id):
		return
	var b: Dictionary = state.businesses[id]
	for w: int in (b["workers"] as Array).duplicate():
		quit_job(state, w)
	for pos: Vector3i in b["cells"]:
		var c: Dictionary = state.cells.get(pos, {})
		if c.get("kind", "") == "business":
			c["kind"] = "housing"
			c["type"] = str(sim.tune("growth.vacated_becomes", "room"))
			c["owner"] = 0
			c["residents"] = []
			c["why"] = why
			state.emit("cell_changed", {"pos": pos})
	state.businesses.erase(id)
	state.stats["closed_total"] = int(state.stats.get("closed_total", 0)) + 1
	state.emit("business_closed", {"id": id})


static func business_at(state: CityState, pos: Vector3i) -> int:
	var c: Dictionary = state.cells.get(pos, {})
	var id := int(c.get("owner", 0)) if c.get("kind", "") == "business" else int(c.get("anchor", 0))
	return id if state.businesses.has(id) else 0


# ------------------------------------------------------------------ 셀
static func set_cell(state: CityState, pos: Vector3i, cell: Dictionary) -> void:
	state.cells[pos] = cell
	state.emit("cell_changed", {"pos": pos})


## 셀을 없앤다(철거). 살던 가구는 대문 앞으로, 사업체·앵커 장부는 닫는다.
static func remove_cell(state: CityState, pos: Vector3i) -> void:
	var c: Dictionary = state.cells.get(pos, {})
	if c.is_empty():
		return
	for id: int in (c.get("residents", []) as Array).duplicate():
		vacate(state, id)
	var biz := business_at(state, pos)
	if biz != 0:
		for w: int in (state.businesses[biz]["workers"] as Array).duplicate():
			quit_job(state, w)
		state.businesses.erase(biz)
		if c.get("kind", "") == "business":
			state.emit("business_closed", {"id": biz})
	state.cells.erase(pos)
	state.emit("cell_changed", {"pos": pos})


## 요청 큐(state.flags[name])를 통째로 꺼내 비운다.
static func take_queue(state: CityState, name: String) -> Array:
	var q: Array = state.flags.get(name, [])
	if not q.is_empty():
		state.flags[name] = []
	return q
