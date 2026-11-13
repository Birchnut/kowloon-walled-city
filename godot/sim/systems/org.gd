extends SimSystem
## org — 조직(v0.5, docs/DESIGN_v0.5.md C6). 십삼요회(탄환방·용궁)와 연우당(목소리방·화약방·모조품 공방). 시설의 조직은 buildings.json org.
##  층 규칙(space의 build can, code org_zone): 두 조직의 시설은 같은 층에도 맞닿은 층에도 둘 수 없다.
##  치안 0~100 = 가동 중인 조직 시설 수 × org.security_per_org. 낮으면(org.security_low 미만) 주민이 org.vagrant.min_pop 이상일 때 가끔
##   부랑자 사건(좌판 하나가 하루 쉼 / 돈을 조금 잃음 / 작은 불). 치안이 높으면 없다. 치안은 새는 돈도 줄인다(finance).
##  갈등: 두 조직이 다 가동 중이면 쌓인다(기본 + 한쪽이 클수록 더). 두 조직 시설 사이 층들의 중립 시설(buildings.json neutral)이 식힌다.
##   가득 차면 조직 시설 하나 근처에서 불(hazards의 점화 큐) 또는 파손(그 시설 wreck_days 정지) 뒤 0으로.
##  시민에게 닿는 것: 조직 시설과 같은 층, 가로·세로 org.effect_r칸 안의 집만 b.org_near("thirteen"|"yeonu"|"both"|"").
##   십삼요회 옆은 승급 공사가 길어지고(upgrades) 연우당 옆은 병이 더 잘 난다(hazards). 다른 층으로는 넘어가지 않는다.
##  선금: 건설비(돈) ×org.advance_mult — Sim.build_cost.
## 끄면: 조직 시설도 보통 시설처럼 돌고(층 규칙·선금·치안·갈등·부랑자 없음) 새는 돈은 치안 0으로 센다.


func _f(k: String, d: float) -> float:
	return float(sim.cfg("org." + k, d))


func tick(state: CityState, dt: float) -> void:
	if not sim.every(state, 2, dt):
		return
	var dth := sim.step_days * 2.0
	var cov := sim.cover(state)
	var act := {"thirteen": 0, "yeonu": 0}
	var list: Array = []           # 완공된 조직 시설
	for bid: int in cov["org"]:
		var b: Dictionary = state.buildings.get(bid, {})
		if b.get("kind", "") != "facility":
			continue
		list.append(b)
		if b.get("active", false) and Sim.off_reason(b) == "":
			act[str(cov["org"][bid])] += 1
	# 정지(파손·자리 비움) 끝내기
	for b: Dictionary in cov["facs"]:
		for key: String in ["wrecked", "resting"]:
			if b.get(key, false) and state.econ_days + 1e-9 >= float(b.get(key + "_until", 0.0)):
				b[key] = false
				b.erase(key + "_until")
				state.emit("building_changed", {"bid": int(b["id"])})
	if not list.is_empty():
		sim.chron(state, "first_org", "조직의 시설이 처음 문을 열었다.", true)
	# 치안
	var n_act: int = act["thirteen"] + act["yeonu"]
	var sec := minf(100.0, float(n_act) * _f("security_per_org", 15.0))
	var low := _f("security_low", 30.0)
	var was := float(state.flags.get("security", 0.0))
	state.flags["security"] = sec
	if was >= low and sec < low:
		state.emit("security_low", {"value": sec})
		sim.say(state, "치안이 떨어졌다. 골목이 어수선하다.", "warn")
	_near(state, cov, list)
	_conflict(state, cov, list, act, dth)
	_vagrants(state, cov, sec, dth)


## 조직 시설 옆 주거 표시(b.org_near).
func _near(state: CityState, cov: Dictionary, list: Array) -> void:
	var r := int(_f("effect_r", 4))
	var rg := {"r": r, "up": 0, "down": 0}
	for h: Dictionary in cov["houses"]:
		var t13 := false
		var yeo := false
		for f: Dictionary in list:
			if not f.get("active", false):
				continue
			var k := Cover.dims(f)
			if Cover.reach_b(f["pos"], k.x, k.y, k.z, rg, h) and (h["pos"] as Vector3i).z == (f["pos"] as Vector3i).z:
				if str(cov["org"][int(f["id"])]) == "thirteen":
					t13 = true
				else:
					yeo = true
		var v := "both" if (t13 and yeo) else ("thirteen" if t13 else ("yeonu" if yeo else ""))
		if str(h.get("org_near", "")) != v:
			h["org_near"] = v
			state.emit("building_changed", {"bid": int(h["id"])})


func _between(cov: Dictionary, state: CityState) -> Dictionary:
	var za: Array = []
	var zb: Array = []
	for bid: int in cov["org"]:
		var b: Dictionary = state.buildings.get(bid, {})
		if b.get("kind", "") != "facility":
			continue
		(za if str(cov["org"][bid]) == "thirteen" else zb).append((b["pos"] as Vector3i).z)
	var fl := {}
	for a: int in za:
		for b: int in zb:
			for z: int in range(mini(a, b) + 1, maxi(a, b)):
				fl[z] = true
	return fl


func neutral_between(state: CityState) -> int:
	var cov := sim.cover(state)
	var fl := _between(cov, state)
	var n := 0
	for b: Dictionary in cov["facs"]:
		if sim.bdef(str(b["type"])).get("neutral", false) and fl.has((b["pos"] as Vector3i).z) and Sim.off_reason(b) == "":
			n += 1
	return n


func _conflict(state: CityState, cov: Dictionary, list: Array, act: Dictionary, dth: float) -> void:
	var c := float(state.flags.get("conflict", 0.0))
	var mx := float(sim.cfg("org.conflict.max", 100.0))
	var a: int = act["thirteen"]
	var y: int = act["yeonu"]
	var cc := "org.conflict."
	if a > 0 and y > 0:
		var rise := float(sim.cfg(cc + "base_per_day", 4.0)) + float(sim.cfg(cc + "imbalance_per_day", 3.0)) * float(absi(a - y))
		var cool := float(neutral_between(state)) * float(sim.cfg(cc + "cool_per_neutral", 2.0))
		c = clampf(c + (rise - cool) * dth, 0.0, mx)
	else:
		c = maxf(0.0, c - float(sim.cfg(cc + "decay_per_day", 5.0)) * dth)
	if c >= mx - 1e-9 and not list.is_empty():
		_clash(state, list)
		c = 0.0
	state.flags["conflict"] = c


func _clash(state: CityState, list: Array) -> void:
	var b: Dictionary = list[int(sim.roll(state) * list.size()) % list.size()]
	var org := str(sim.cover(state)["org"].get(int(b["id"]), ""))
	var nm := str(sim.bdef(str(b["type"])).get("name", ""))
	var fire := sim.roll(state) < 0.5 and sim.enabled.has("hazards")
	var kind := "fire" if fire else "damage"
	var text := ""
	if fire:
		var q: Array = state.flags.get("ignite_q", [])
		q.append({"bid": int(b["id"])})
		state.flags["ignite_q"] = q
		text = "두 조직의 다툼이 터졌다. %s 근처에서 불이 났다." % nm
	else:
		b["wrecked"] = true
		b["wrecked_until"] = state.econ_days + float(sim.cfg("org.conflict.wreck_days", 1.0))
		text = "두 조직의 다툼이 터졌다. %s이(가) 부서져 하루 멈춘다." % nm
		state.emit("building_changed", {"bid": int(b["id"])})
	state.stat_add("org_clashes", 1.0)
	state.emit("org_clash", {"kind": kind, "bid": int(b["id"]), "pos": b["pos"], "org": org, "text": text})
	sim.say(state, text, "bad")
	sim.chron(state, "org_clash", "십삼요회와 연우당의 다툼이 터졌다. %s" % ("불이 났다." if fire else "시설이 부서졌다."))


func _vagrants(state: CityState, cov: Dictionary, sec: float, dth: float) -> void:
	var low := _f("security_low", 30.0)
	var vg := "org.vagrant."
	if sec >= low or state.population() < int(sim.cfg(vg + "min_pop", 40)):
		return
	var p := float(sim.cfg(vg + "per_day", 0.25)) * (1.0 - sec / maxf(1.0, low)) * dth
	if sim.roll(state) >= p:
		return
	var w: Dictionary = sim.cfg(vg + "weights", {"rest": 3, "loss": 3, "fire": 1})
	var tot := 0.0
	for k: String in w:
		tot += float(w[k])
	var x := sim.roll(state) * tot
	var kind := "loss"
	for k: String in w:
		x -= float(w[k])
		if x < 0.0:
			kind = k
			break
	var text := ""
	var bid := -1
	var pos: Variant = null
	if kind == "rest":
		var stalls: Array = []
		for b: Dictionary in cov["facs"]:
			if sim.bdef(str(b["type"])).has("market") and not b.get("resting", false) and Sim.off_reason(b) == "":
				stalls.append(b)
		if stalls.is_empty():
			kind = "loss"
		else:
			var b: Dictionary = stalls[int(sim.roll(state) * stalls.size()) % stalls.size()]
			b["resting"] = true
			b["resting_until"] = state.econ_days + float(sim.cfg(vg + "rest_days", 1.0))
			bid = int(b["id"])
			pos = b["pos"]
			text = "부랑자가 판을 어지럽혀 %s이(가) 하루 쉰다." % sim.bdef(str(b["type"])).get("name", "")
			state.emit("building_changed", {"bid": bid})
	if kind == "fire":
		var used: Array = []
		for h: Dictionary in cov["houses"]:
			if int(h["residents"]) > 0 and str(h.get("burn", "")) == "":
				used.append(h)
		if used.is_empty() or not sim.enabled.has("hazards"):
			kind = "loss"
		else:
			var h: Dictionary = used[int(sim.roll(state) * used.size()) % used.size()]
			var q: Array = state.flags.get("ignite_q", [])
			q.append({"bid": int(h["id"])})
			state.flags["ignite_q"] = q
			bid = int(h["id"])
			pos = h["pos"]
			text = "부랑자가 피운 불이 번졌다(%d층)." % ((h["pos"] as Vector3i).z + 1)
	if kind == "loss":
		var amt := clampf(state.money * float(sim.cfg(vg + "loss_frac", 0.01)), float(sim.cfg(vg + "loss_min", 20)), float(sim.cfg(vg + "loss_max", 300)))
		amt = minf(amt, state.money)
		state.money -= amt
		state.book("fine", -amt)
		state.stat_add("vagrant_loss", amt)
		text = "부랑자가 금고를 건드렸다. %s을(를) 잃었다." % Sim.won(amt)
	state.stat_add("vagrant_incidents", 1.0)
	state.emit("vagrant_incident", {"kind": kind, "bid": bid, "pos": pos, "text": text})
	sim.say(state, text, "warn")
	sim.chron(state, "first_vagrant", "성채에 처음으로 부랑자 소동이 났다.", true)


# ------------------------------------------------------------------ 질의
func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	match name:
		"security":
			var v := float(state.flags.get("security", 0.0))
			var low := _f("security_low", 30.0)
			var cov := sim.cover(state)
			var n := 0
			for bid: int in cov["org"]:
				var b: Dictionary = state.buildings.get(bid, {})
				if b.get("kind", "") == "facility" and b.get("active", false):
					n += 1
			var risky := v < low and state.population() >= int(sim.cfg("org.vagrant.min_pop", 40))
			return {"value": snappedf(v, 0.1), "low": v < low, "threshold": int(low), "org_active": n, "vagrant_risk": risky,
				"text": "치안 %d — %s" % [int(v), "낮다. 가끔 부랑자 소동이 난다." if risky else ("낮다." if v < low else "넉넉하다.")]}
		"conflict":
			var cov2 := sim.cover(state)
			var a := 0
			var y := 0
			for bid: int in cov2["org"]:
				var b2: Dictionary = state.buildings.get(bid, {})
				if b2.get("kind", "") == "facility" and b2.get("active", false):
					if str(cov2["org"][bid]) == "thirteen":
						a += 1
					else:
						y += 1
			var c := float(state.flags.get("conflict", 0.0))
			var buf := neutral_between(state)
			var rising := a > 0 and y > 0
			return {"value": snappedf(c, 0.1), "max": float(sim.cfg("org.conflict.max", 100.0)), "thirteen": a, "yeonu": y, "buffer": buf, "rising": rising,
				"text": ("십삼요회와 연우당이 맞서 있다. 다툼 %d. 사이 층의 중립 시설 %d곳." % [int(c), buf]) if rising else "한 조직뿐이거나 조직이 없어 다툼이 없다."}
	return null


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name == "hud":
		var low := _f("security_low", 30.0)
		var v := float(state.flags.get("security", 0.0))
		out["security"] = {"value": snappedf(v, 0.1), "low": v < low}
		out["conflict"] = {"value": snappedf(float(state.flags.get("conflict", 0.0)), 0.1)}
