extends SimSystem
## finance — 금고. 세금은 자동으로 계속 들어오고(확정), 유지비는 계속 빠진다. 금고는 음수가 되지 않는다.
##  세수 = Σ 주거 b.tax(needs가 계산, ₩/경제일) × dt → 장부 'tax'. 음성 수입 = Σ b.vice_rate × dt → 'vice'.
##  유지비 = Σ 완공 시설 upkeep × dt(일시정지·파산 정지는 0) → 'upkeep'.
##  돈이 모자라면: 우선순위가 가장 낮은 시설부터 b.money_stop(cause "money")으로 멈춰 이번 스텝 유지비를 낼 수 있을 때까지.
##  다시 켜기: 멈춘 시설까지 포함한 유지비 config finance.broke_resume_days 일치가 모이면 전부 다시 켠다(깜빡임 방지).
##  장부: ledger.today{tax, upkeep, import, export, build, vice}(부호 있음) → 자정에 ledger.days로(최근 14일).
##  내부 판매는 세수에 이미 들어 있으므로 매출로 따로 잡지 않는다(이중 수입 금지).
## 끄면: 세수·유지비가 없다(금고는 건설·교역으로만 움직인다).

const LINES := ["tax", "upkeep", "import", "export", "build", "vice", "reward", "fine"]


func tick(state: CityState, dt: float) -> void:
	var tax := 0.0
	var vice := 0.0
	var cov := sim.cover(state)
	var fac: Array = cov["facs"]
	for b: Dictionary in cov["houses"]:
		tax += float(b["tax"])
	for b: Dictionary in fac:
		vice += float(b.get("vice_rate", 0.0))
	state.money += tax * dt
	state.book("tax", tax * dt)
	state.stat_add("tax_total", tax * dt)
	if vice > 0.0:
		state.money += vice * dt
		state.book("vice", vice * dt)
	var due := 0.0
	var full := 0.0
	var stopped := false
	var uk := sim.mod(state, "upkeep.all")   # 연구: 시설 유지비 배수
	for b: Dictionary in fac:
		var u := float(sim.bdef(str(b["type"])).get("upkeep", 0.0)) * uk
		full += u
		if b.get("money_stop", false):
			stopped = true
		elif not b.get("paused", false):
			due += u * dt
	if stopped and state.money >= full * float(sim.cfg("finance.broke_resume_days", 1.0)):
		for b: Dictionary in fac:
			if b.get("money_stop", false):
				b["money_stop"] = false
				state.emit("building_changed", {"bid": int(b["id"])})
		sim.say(state, "금고가 다시 차서 멈췄던 시설을 다시 돌린다.")
	if due > state.money + 1e-9:
		var order: Array = sim.cover(state)["by_prio"].duplicate()
		order.reverse()
		var n := 0
		for bid: int in order:
			if due <= state.money + 1e-9:
				break
			var b: Dictionary = state.buildings.get(bid, {})
			if b.get("kind", "") != "facility" or b.get("paused", false) or b.get("money_stop", false):
				continue
			var u := float(sim.bdef(str(b["type"])).get("upkeep", 0.0)) * uk
			if u <= 0.0:
				continue
			b["money_stop"] = true
			due -= u * dt
			n += 1
			state.emit("building_changed", {"bid": bid})
		if n > 0:
			sim.say(state, "금고가 바닥나 시설 %d곳을 멈췄다(우선순위 낮은 것부터)." % n, "bad")
	due = minf(due, state.money)
	state.money = maxf(0.0, state.money - due)
	state.book("upkeep", -due)
	state.stat_add("upkeep_total", due)


func on_day_end(state: CityState, ended: int) -> void:
	var today: Dictionary = state.ledger.get("today", {})
	var row := {"day": ended}
	var net := 0.0
	for l: String in LINES:
		row[l] = float(today.get(l, 0.0))
		net += float(row[l])
	row["net"] = net
	var days: Array = state.ledger.get("days", [])
	days.append(row)
	var keep := int(sim.cfg("finance.ledger_days", 14))
	if days.size() > keep:
		days = days.slice(days.size() - keep)
	state.ledger["days"] = days
	state.ledger["today"] = {}


const LINE_NAME := {"tax": "세수", "upkeep": "유지비", "import": "수입(교역)", "export": "수출(교역)", "build": "건설·승급", "vice": "음성 수입", "reward": "목표 보상", "fine": "벌금·뒷돈"}


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name == "hud":
		var rate := 0.0
		for b: Dictionary in state.buildings.values():
			if b["kind"] == "house":
				rate += float(b.get("tax", 0.0))
			elif b["kind"] == "facility":
				rate += float(b.get("vice_rate", 0.0))
				if not b.get("paused", false) and not b.get("money_stop", false):
					rate -= float(sim.bdef(str(b["type"])).get("upkeep", 0.0)) * sim.mod(state, "upkeep.all")
		out["net_per_day"] = snappedf(rate, 0.1)
		var stopped := 0
		for b: Dictionary in state.buildings.values():
			if b.get("money_stop", false):
				stopped += 1
		if stopped > 0:
			out["alerts"].append({"id": "broke", "text": "돈이 없어 시설 %d곳이 멈췄다" % stopped, "tone": "bad", "jump": {"screen": "economy", "arg": "finance"}})
	elif name == "economy":
		var today: Dictionary = state.ledger.get("today", {})
		var days: Array = state.ledger.get("days", [])
		var avg := {}
		var t := {}
		var lines: Array = []
		for l: String in LINES:
			t[l] = snappedf(float(today.get(l, 0.0)), 0.1)
			var s := 0.0
			for r: Dictionary in days:
				s += float(r.get(l, 0.0))
			avg[l] = snappedf(s / float(maxi(1, days.size())), 0.1)
			lines.append({"id": l, "name": LINE_NAME[l], "amount": avg[l]})
		var net := 0.0
		var tnet := 0.0
		for l: String in LINES:
			net += float(avg[l])
			tnet += float(t[l])
		avg["net"] = snappedf(net, 0.1)
		t["net"] = snappedf(tnet, 0.1)
		out["finance"] = {"today": t, "avg": avg, "lines": lines, "net": snappedf(net, 0.1), "days": days.size()}
