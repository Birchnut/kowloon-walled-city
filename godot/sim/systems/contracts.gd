extends SimSystem
## contracts — 정기 계약(확정: 교역은 정기 계약 중심). data/economy/partners.json.
##  자리: 완공 교역소 × contract_slots(+ config contracts.base_slots).
##  실행: 경제 시계로 next_at에(GDD §1: 계약은 경제 시계 — 소비와 같은 속도). 한 회차는 돈+상품이 원자적으로 정확히 한 번 움직인다.
##   수입: 돈과 저장 자리가 있어야. 모자라면 받을 수 있는 만큼만(부분 이행, 이유를 남김). 0이면 건너뜀.
##   수출: 최소 보유량(reserve) 위 재고만. 모자라면 있는 만큼, 0이면 건너뜀.
##   실패는 벌금 없이 그 회차를 건너뛰고 last.reason에 한국어 이유. 이벤트 contract_done{id, ok, reason}. 장부 import/export.
##  거래처: known=true는 처음부터. 나머지는 B 파트 탐험이 state.partners[id] = true로 연다(디버그 reveal_partners).
## 끄면: 계약이 실행되지 않는다(서명도 못 한다).


func on_new_game(state: CityState) -> void:
	var ps: Dictionary = sim.db.get("partners", {}).get("partners", {})
	for id: String in ps:
		if ps[id].get("known", false):
			state.partners[id] = true


func slots(state: CityState) -> int:
	return int(sim.cfg("contracts.base_slots", 0)) + int(sim.cover(state).get("posts", 0))


func _find(state: CityState, id: int) -> Dictionary:
	for c: Dictionary in state.contracts:
		if int(c["id"]) == id:
			return c
	return {}


func can(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"contract_sign":
			var o := sim.item("partners", str(args.get("offer", "")))
			if o.is_empty():
				return {"ok": false, "reason": "모르는 계약 제안이다."}
			if not state.partners.has(str(o["partner"])):
				return {"ok": false, "reason": "아직 모르는 거래처다."}
			var sizes: Array = o.get("sizes", [])
			var si := int(args.get("size", 0))
			if si < 0 or si >= sizes.size():
				return {"ok": false, "reason": "수량 단계가 틀렸다."}
			if state.contracts.size() >= slots(state):
				return {"ok": false, "reason": "계약 자리가 없다(지금 %d자리 — 뒷문 무역관을 지으면 2자리씩 생긴다)." % slots(state)}
			return {"ok": true, "reason": ""}
		"contract_set", "contract_cancel":
			if _find(state, int(args.get("id", -1))).is_empty():
				return {"ok": false, "reason": "그런 계약이 없다."}
			return {"ok": true, "reason": ""}
	return null


func apply(state: CityState, name: String, args: Dictionary) -> Variant:
	match name:
		"contract_sign":
			var oid := str(args["offer"])
			var o := sim.item("partners", oid)
			var sz: Dictionary = o["sizes"][int(args.get("size", 0))]
			var c := {"id": state.new_id(), "offer": oid, "partner": str(o["partner"]), "good": str(o["good"]), "dir": str(o["dir"]),
				"qty": float(sz["qty"]), "interval_h": float(sz["interval_h"]), "price": float(sz["price"]),
				"transport": float(o.get("transport", 0.0)),
				"next_at": state.econ_days + float(sim.cfg("contracts.first_delay_h", 1)) / 24.0,
				"paused": false, "reserve": float(args.get("reserve", 0.0)), "last": {"ok": true, "reason": "아직 첫 회차 전", "at": -1.0}}
			state.contracts.append(c)
			sim.say(state, "%s과(와) 계약: %s %d개 / %d시간." % [_pname(c["partner"]), sim.gname(c["good"]), int(c["qty"]), int(c["interval_h"])])
			return {"ok": true, "reason": "", "id": int(c["id"])}
		"contract_set":
			var c := _find(state, int(args["id"]))
			if args.has("paused"):
				c["paused"] = bool(args["paused"])
				if not c["paused"]:
					c["next_at"] = maxf(float(c["next_at"]), state.econ_days)
			if args.has("reserve"):
				c["reserve"] = maxf(0.0, float(args["reserve"]))
			return {"ok": true, "reason": ""}
		"contract_cancel":
			state.contracts.erase(_find(state, int(args["id"])))
			return {"ok": true, "reason": ""}
	return null


func _pname(p: String) -> String:
	return str(sim.db.get("partners", {}).get("partners", {}).get(p, {}).get("name", p))


func tick(state: CityState, _dt: float) -> void:
	for c: Dictionary in state.contracts:
		if c.get("paused", false) or state.econ_days + 1e-9 < float(c["next_at"]):
			continue
		_run(state, c)
		c["next_at"] = float(c["next_at"]) + float(c["interval_h"]) / 24.0
		if float(c["next_at"]) <= state.econ_days:
			c["next_at"] = state.econ_days + float(c["interval_h"]) / 24.0


func _run(state: CityState, c: Dictionary) -> void:
	var g := str(c["good"])
	var qty := float(c["qty"])
	var price := float(c["price"]) * sim.mod(state, "trade.buy" if c["dir"] == "import" else "trade.sell")   # 연구: 단골 거래
	var tr := float(c.get("transport", 0.0))
	var ok := true
	var reason := ""
	var n := 0.0
	if c["dir"] == "import":
		var room := floorf(sim.cap_of(state, g) - float(state.stock.get(g, 0.0)) + 1e-6)
		var afford := floorf((state.money - tr) / price + 1e-9) if price > 0.0 else qty
		n = maxf(0.0, minf(qty, minf(room, afford)))
		if n <= 0.0:
			ok = false
			reason = "돈이 모자라 건너뜀" if afford < 1.0 else "창고가 가득 차 건너뜀"
		else:
			var pay := n * price + tr
			state.money -= pay
			state.stock[g] = float(state.stock.get(g, 0.0)) + n
			state.book("import", -pay)
			sim.flow_add(g, "imp", n)
			state.stat_add("imp." + g, n)
			if n < qty:
				reason = "%s로 %d/%d개만 받음" % ["창고 자리가 모자라" if room < afford else "돈이 모자라", int(n), int(qty)]
			else:
				reason = "%d개 받음 (%s)" % [int(n), Sim.won(pay)]
	else:
		var avail := floorf(float(state.stock.get(g, 0.0)) - float(c.get("reserve", 0.0)) + 1e-6)
		n = maxf(0.0, minf(qty, avail))
		if n <= 0.0:
			ok = false
			reason = "최소 보유량 위 재고가 없어 건너뜀"
		else:
			var got := n * price - tr
			state.stock[g] = float(state.stock.get(g, 0.0)) - n
			state.money = maxf(0.0, state.money + got)
			state.book("export", got)
			sim.flow_add(g, "exp", n)
			state.stat_add("exp." + g, n)
			reason = ("%d/%d개만 보냄" % [int(n), int(qty)]) if n < qty else ("%d개 보냄 (%s)" % [int(n), Sim.won(got)])
	c["last"] = {"ok": ok, "reason": reason, "at": state.econ_days, "n": n}
	state.stat_add("contract_rounds", 1.0)
	if not ok:
		state.stat_add("contract_skips", 1.0)
	state.emit("contract_done", {"id": int(c["id"]), "ok": ok, "reason": reason})
	if not ok:
		sim.say(state, "계약(%s %s): %s." % [_pname(c["partner"]), sim.gname(g), reason], "warn")



# ------------------------------------------------------------------ 질의
func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "contracts":
		return null
	var active: Array = []
	for c: Dictionary in state.contracts:
		var sign := -1.0 if c["dir"] == "import" else 1.0
		active.append({"id": int(c["id"]), "partner_name": _pname(c["partner"]), "good": c["good"], "good_name": sim.gname(c["good"]),
			"dir": c["dir"], "qty": int(c["qty"]), "interval_h": int(c["interval_h"]), "price": c["price"],
			"next_in_h": snappedf(maxf(0.0, (float(c["next_at"]) - state.econ_days) * 24.0), 0.1), "paused": c["paused"],
			"reserve": c.get("reserve", 0.0), "last_text": str(c["last"].get("reason", "")), "last_ok": bool(c["last"].get("ok", true)),
			"per_day_money": snappedf(sign * (float(c["qty"]) * float(c["price"]) + sign * float(c.get("transport", 0.0))) * 24.0 / float(c["interval_h"]), 0.1)})
	var offers: Array = []
	var ps: Dictionary = sim.db.get("partners", {}).get("partners", {})
	for oid: String in sim.items("partners"):
		var o := sim.item("partners", oid)
		var sizes: Array = []
		var sign := -1.0 if o["dir"] == "import" else 1.0
		for s: Dictionary in o["sizes"]:
			sizes.append({"qty": int(s["qty"]), "interval_h": int(s["interval_h"]), "price": s["price"],
				"per_day_money": snappedf(sign * float(s["qty"]) * float(s["price"]) * 24.0 / float(s["interval_h"]), 0.1)})
		var known := state.partners.has(str(o["partner"]))
		offers.append({"id": oid, "partner": o["partner"], "partner_name": _pname(o["partner"]), "good": o["good"], "good_name": sim.gname(o["good"]),
			"dir": o["dir"], "sizes": sizes, "known": known, "lock_hint": "" if known else str(ps.get(o["partner"], {}).get("reveal_hint", "탐험으로 발견"))})
	return {"slots": {"used": state.contracts.size(), "max": slots(state)}, "active": active, "offers": offers, "no_post": slots(state) == 0}


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name == "hud":
		var f := 0
		for c: Dictionary in state.contracts:
			if not c["last"].get("ok", true):
				f += 1
		out["contracts_failed"] = f
		if f > 0:
			out["alerts"].append({"id": "contracts", "text": "계약 %d건이 지난 회차를 건너뛰었다" % f, "tone": "warn", "jump": {"screen": "contracts", "arg": ""}})
