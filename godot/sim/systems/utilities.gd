extends SimSystem
## 물·전기 — 두 용량.
##  · 물(state.water_cap): 기본(utilities.water_base) + 공동수도·물탱크의 water 합. 인구가 이걸 넘으면 유입이 줄고 민심이 깎인다.
##  · 층 한도(state.flags.floor_cap): utilities.floor_base + 물탱크의 floors 합. 물이 안 올라가는 층에는 아무도 안 짓는다.
##  · 전기(state.power_level): 발전기가 있으면 1, 외부 계약(카드, flags.power_contract)이면 2. 전기가 필요한 가게(power)의 입점 조건.
##    단계가 바뀌면 `power_changed` 이벤트(첫 전기의 밤).
## 수치: data/economy.json "utilities" · 시설별 water/floors/power는 facilities.json.


func on_new_game(state: CityState) -> void:
	_refresh(state, true)


func on_hour(state: CityState, _hour: int) -> void:
	_refresh(state, false)


func on_command(state: CityState, name: String, _args: Dictionary, _result: Dictionary) -> void:
	if name in ["plant", "demolish", "card", "debug"]:
		_refresh(state, false)


func _refresh(state: CityState, silent: bool) -> void:
	var water := sim.num("utilities.water_base", 14.0)
	var floors := sim.num("utilities.floor_base", 4.0)
	var power := int(state.flags.get("power_contract", 0))
	for c: Dictionary in state.cells.values():
		if c.get("kind", "") != "facility":
			continue
		var d := sim.def_of(c)
		water += float(d.get("water", 0.0))
		floors += float(d.get("floors", 0.0))
		power = maxi(power, int(d.get("power", 0)))
	state.water_cap = int(water)
	state.flags["floor_cap"] = mini(int(floors) + int(state.flags.get("floor_bonus", 0)), sim.F)
	if power != state.power_level:
		var was := state.power_level
		state.power_level = power
		if not silent:
			state.emit("power_changed", {"level": power})
			if power > was and not state.flags.has("first_power_day"):
				state.flags["first_power_day"] = state.day
				sim.say(state, "첫 전기의 밤. 창문이 하나씩 켜진다.", "good")
			elif power > was:
				sim.say(state, "전기가 한 단계 올라갔다. 밤이 더 밝다.", "good")
			elif power < was:
				sim.say(state, "불이 꺼졌다. 골목이 다시 어둡다.", "bad")
		sim.touch()


func metrics(state: CityState, m: Dictionary) -> void:
	m["floor_cap"] = float(state.flags.get("floor_cap", sim.F))
	m["water_left"] = float(state.water_cap) - float(m.get("population", 0.0))


func describe(state: CityState, _pos: Vector3i, cell: Dictionary, info: Dictionary) -> void:
	if cell.get("kind", "") != "facility":
		return
	var d := sim.def_of(cell)
	if float(d.get("water", 0.0)) > 0.0:
		info["lines"].append("물: %d명분을 댄다 (성채 전체 %d명분, 지금 %d명)." % [int(d["water"]), state.water_cap, state.population()])
	if float(d.get("floors", 0.0)) > 0.0:
		info["lines"].append("물을 %d층 더 올려 준다 (지금 %d층까지)." % [int(d["floors"]), int(state.flags.get("floor_cap", sim.F))])
	if int(d.get("power", 0)) > 0:
		info["lines"].append("전기를 댄다. 전기가 필요한 가게가 들어올 수 있다.")
