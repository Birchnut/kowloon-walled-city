class_name Debug
extends RefCounted
## Debug — 개발용 명령(config debug.enabled). Game.cmd("debug", {op, …}).
##  add_money{n} · add_stock{good, n} · skip_days{n} · skip_real{seconds}(실제 시계 오프셋, 탐험용) · unlock_all
##  reveal_partners · fill_floor{z, tier=1, full=true}(빈 칸을 주민 찬 주거로, 비용 없음) · set{field, value}


static func run(sim: Sim, state: CityState, args: Dictionary) -> Dictionary:
	match str(args.get("op", "")):
		"add_money":
			state.money += float(args.get("n", args.get("amount", 1000)))
		"add_stock":
			var g := str(args.get("good", ""))
			if sim.good(g).is_empty():
				return {"ok": false, "reason": "모르는 상품: %s" % g}
			state.stock[g] = maxf(0.0, float(state.stock.get(g, 0.0)) + float(args.get("n", 10)))
			state.stat_add("debug_stock." + g, float(args.get("n", 10)))
		"skip_days":
			sim.tick(state, float(args.get("n", 1)))
		"skip_real":
			var sec := maxi(0, int(args.get("seconds", 600)))
			state.clock_offset += sec
			sim.now_unix += sec
		"unlock_all":
			for id: String in sim.items("buildings"):
				state.unlocked[id] = state.econ_days
			state.unlocked["house"] = state.econ_days
			var bp: Dictionary = state.flags.get("blueprints", {})
			for id: String in sim.items("buildings"):
				if sim.bdef(id).has("blueprint"):
					bp[str(sim.bdef(id)["blueprint"])] = true
			state.flags["blueprints"] = bp
		"reveal_partners":
			for p: String in sim.db.get("partners", {}).get("partners", {}):
				state.partners[p] = true
		"fill_floor":
			var z := int(args.get("z", 0))
			var t := int(args.get("tier", 1))
			var cap := int(sim.tier(t).get("cap", 4))
			var n := int(args.get("count", 9999))
			for x: int in sim.W:
				for y: int in sim.H:
					var p := Vector3i(x, y, z)
					if n <= 0 or state.cells.has(p):
						continue
					n -= 1
					var bid := state.new_id()
					state.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": t, "material": "common" if t == 1 else "wood",
						"residents": cap if args.get("full", true) else 0, "cap": cap, "happiness": 50.0, "needs": {}, "need_state": "warn",
						"upgradable": false, "upgrading": null, "grow": 0.0, "leave": 0.0, "target": cap, "tax": 0.0, "util_extra": {}}
					state.cells[p] = {"kind": "house", "bid": bid, "type": "house", "tier": t, "material": state.buildings[bid]["material"],
						"seed": sim.rand_seed(state), "origin": p, "size": 1, "scaffold": false}
					state.emit("cell_changed", {"pos": p})
			state.layout_changed()
		"set":
			state.set(str(args.get("field", "")), args.get("value"))
		_:
			return {"ok": false, "reason": "모르는 디버그 명령."}
	return {"ok": true, "reason": ""}
