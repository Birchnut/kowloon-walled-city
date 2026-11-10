extends SceneTree
## sim_run — 봇 한 명에게 N일을 맡겨 헤드리스로 돌린다(합격 기준 D7).
##   godot --headless --path godot -s res://tools/sim_run.gd -- bot=farmer days=30 seed=1 out=/abs/dir [dt=0.125] [quiet]
## 결과(out 폴더):
##   daily.csv              하루 끝마다 한 줄(인구·칸 수·업종/자재별·재고·지표·호칭·별명 …)
##   heightmap_day_XX.txt   5일마다(와 마지막 날) 높이 지도 + 용도 지도(ASCII)
##   state_day_XX.json      하루 끝 상태 스냅샷(CityState.to_json) — 뷰로 타임랩스를 뽑는 재료. 00 = 시작 직후.
##   summary.json           마지막 날 지표·통계·별명·기록 꼬리
## 접속 중에는 dt(도시 시간) 틱 + 매시 봇의 손길, 봇이 자리를 비운 동안은 fast_forward.

const CSV_COLS := ["day", "population", "households", "waiting", "cells", "sites", "housing", "business", "facility",
	"farm", "make", "fun", "vice", "scrap", "wood", "sheet", "brick", "concrete", "shack", "room", "flat", "cage",
	"money", "food", "materials", "prestige", "notoriety", "morale", "alley_fund", "max_height", "avg_height",
	"footprint", "keep_columns", "power", "water_cap", "cards_pending", "dominant", "title", "epithet"]


func _init() -> void:
	var args := {"bot": "farmer", "days": "30", "seed": "1", "out": "user://sim_out", "dt": "0.125"}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var result := run(str(args["bot"]), int(args["days"]), int(args["seed"]), str(args["out"]), float(args["dt"]), not args.has("quiet"))
	if result.has("sim"):
		(result["sim"] as Sim).systems.clear()   # Sim ↔ 시스템 순환 참조를 끊고 나간다
	quit(0 if result["ok"] else 1)


static func run(bot_id: String, days: int, seed_value: int, out: String, dt: float = 0.125, verbose: bool = true, db_override: Dictionary = {}) -> Dictionary:
	var db := db_override if not db_override.is_empty() else SimIO.load_db()
	var sim := Sim.new()
	sim.setup(db)
	if sim.item("bots", bot_id).is_empty():
		push_error("모르는 봇: %s" % bot_id)
		return {"ok": false}
	var bot := Bot.new(sim, bot_id)
	var state := CityState.new()
	sim.new_game(state, seed_value)
	var rows: Array = [",".join(CSV_COLS)]
	var t0 := Time.get_ticks_msec()
	if out != "":
		SimIO.write_text("%s/state_day_00.json" % out, state.to_json())
	var last_act := -1.0
	while state.day <= days:
		var day := state.day
		if bot.online(state):
			if absf(state.hour - last_act) >= 1.0 or last_act < 0.0:
				last_act = floorf(state.hour)
				bot.act(state)
			sim.tick(state, dt)
		else:
			sim.fast_forward(state, minf(bot.hours_until_online(state), 24.0 - state.hour))
			last_act = -1.0
		state.events.clear()
		if state.day != day:
			last_act = -1.0
			var row := daily_row(sim, state, day)
			rows.append(row)
			if out != "":
				SimIO.write_text("%s/state_day_%02d.json" % [out, day], state.to_json())
				if day % 5 == 0 or day == days:
					SimIO.write_text("%s/heightmap_day_%02d.txt" % [out, day], ascii_maps(sim, state, day))
			if verbose and (day % 5 == 0 or day == 1 or day == days):
				var m := sim.metrics(state)
				print("%s d%02d  인구 %d  칸 %d  최고 %d층  돈 %d  위신 %d 악명 %d 민심 %d  %s / %s" % [bot_id, day, int(m["population"]), int(m["cells"]),
					int(m["max_height"]), int(state.money), int(state.prestige), int(state.notoriety), int(state.morale),
					state.identity.get("title", ""), state.identity.get("epithet", "")])
	if out != "":
		SimIO.write_text("%s/daily.csv" % out, "\n".join(rows) + "\n")
		var m: Dictionary = sim.metrics(state).duplicate()
		for k: String in m.keys():
			if k.begins_with("_"):
				m.erase(k)
		SimIO.write_text("%s/summary.json" % out, JSON.stringify({"bot": bot_id, "seed": seed_value, "days": days, "identity": state.identity,
			"metrics": m, "stats": state.stats, "policies": state.policies, "unlocked": state.unlocked,
			"log_tail": state.logbook.slice(maxi(0, state.logbook.size() - 40)), "hash": state_hash(state)}, "  "))
	if verbose:
		print("%s 끝: %d일, %.1f초, hash %s" % [bot_id, days, float(Time.get_ticks_msec() - t0) / 1000.0, state_hash(state)])
	return {"ok": true, "state": state, "sim": sim, "hash": state_hash(state)}


## 상태의 지문(결정론·왕복 시험용). JSON을 한 번 거쳐 int/float·키 순서 차이를 없앤 뒤 해시.
static func state_hash(state: CityState) -> String:
	var d: Dictionary = state.to_dict()
	d.erase("last_saved_unix")
	return JSON.stringify(JSON.parse_string(JSON.stringify(d, "", false))).md5_text()


static func daily_row(sim: Sim, state: CityState, day: int) -> String:
	var m := sim.metrics(state)
	var v := {
		"day": day, "population": int(m["population"]), "households": int(m["households"]), "waiting": int(m["waiting"]),
		"cells": int(m["cells"]), "sites": int(m["sites"]), "housing": int(m.get("cells.housing", 0)),
		"business": int(m.get("cells.business", 0)), "facility": int(m.get("cells.facility", 0)),
		"money": int(state.money), "food": int(state.food), "materials": int(state.materials),
		"prestige": snappedf(state.prestige, 0.1), "notoriety": snappedf(state.notoriety, 0.1), "morale": snappedf(state.morale, 0.1),
		"alley_fund": int(state.alley_fund), "max_height": int(m["max_height"]), "avg_height": snappedf(float(m["avg_height"]), 0.01),
		"footprint": int(m["footprint"]), "keep_columns": int(m["keep_columns"]), "power": state.power_level,
		"water_cap": state.water_cap, "cards_pending": state.pending_cards.size(), "dominant": m.get("dominant", ""),
		"title": state.identity.get("title", ""), "epithet": state.identity.get("epithet", ""),
	}
	for g: String in ["farm", "make", "fun", "vice"]:
		v[g] = int(m.get("group." + g, 0))
	for mat: String in ["scrap", "wood", "sheet", "brick", "concrete"]:
		v[mat] = int(m.get("mat." + mat, 0))
	for h: String in ["shack", "room", "flat", "cage"]:
		v[h] = int(m.get("housing." + h, 0))
	var out: Array = []
	for c: String in CSV_COLS:
		out.append(str(v.get(c, "")).replace(",", " "))
	return ",".join(out)


## 높이 지도(숫자 = 층 수, A = 10층, . = 빈 터, _ = 비워 둔 터) + 용도 지도(맨 위 칸: h 집, F 농업, M 제조, U 오락, V 음성, P 공공, # 공사).
static func ascii_maps(sim: Sim, state: CityState, day: int) -> String:
	var letter := {"farm": "F", "make": "M", "fun": "U", "vice": "V", "public": "P"}
	var lines: Array = ["day %d  (아래쪽 = 대문 쪽, y=%d)   높이 | 맨 위 칸 용도" % [day, sim.H - 1]]
	for y: int in sim.H:
		var a := ""
		var b := ""
		for x: int in sim.W:
			var h := Grid.height(sim, state, x, y)
			var keep: bool = state.zones.get(Vector2i(x, y), "") == "keep"
			a += ("_" if keep else ".") if h == 0 else ("A" if h >= 10 else str(h))
			var c: Dictionary = state.cells.get(Vector3i(x, y, h - 1), {})
			var kind := str(c.get("kind", ""))
			if h == 0:
				b += "_" if keep else "."
			elif kind == "site":
				b += "#"
			elif kind == "housing":
				b += "c" if c.get("type", "") == "cage" else "h"
			else:
				b += str(letter.get(sim.def_of(c).get("group", ""), "?"))
		lines.append(a + "   " + b)
	lines.append(" " .repeat(sim.gate.x) + "^ 대문")
	return "\n".join(lines) + "\n"
