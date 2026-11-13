extends SimSystem
## chronicle — 민력 날짜 · 연표 · 고요시간 · 장부의 마지막 장(v0.5, docs/DESIGN_v0.5.md C8·C9·C10).
##  연표: 다른 규칙이 sim.chron(state, kind, text, once)로 한 줄씩 쌓는다(저장됨). 여기서는 읽기·마지막 장·고요시간만 한다.
##  고요시간: 게임 시계 quiet.start_hour(03:12)에 quiet_start, quiet.end_hour(03:30)에 quiet_end 사건 — 규칙에는 영향이 없다.
##  마지막 장: 민력 calendar.last_page_year년 겨울에 한 번 만들어 저장하고 last_page_ready 사건을 낸다. 점수가 아니라 다섯 축의 기록이다.
##   축: tiers(다섯 계층 비율) · money_source(세수·조직 수입·내보낸 값의 비율) · height(쓴 층 수) · updown(위쪽 절반 층 행복 − 아래쪽 절반) · gaze(바깥의 시선 최고).
##  끝이 아니다: last_page_ack 명령은 "보여 줬다"는 표시만 하고 게임은 계속된다.
## 끄면: 날짜 질의는 그대로 나오고 연표는 비며 마지막 장·고요시간 사건이 없다.


func tick(state: CityState, dt: float) -> void:
	_quiet(state, dt)
	if not state.flags.has("last_page"):
		var di := Calendar.info(sim, state)
		var ly := int(sim.cfg("calendar.last_page_year", 17))
		var ls := int(sim.cfg("calendar.last_page_season_idx", 3))
		if int(di["year"]) > ly or (int(di["year"]) == ly and int(di["season_idx"]) >= ls):
			var pg := _page(state)
			pg["year"] = int(di["year"])
			pg["date_text"] = str(di["date_text"])
			state.flags["last_page"] = pg
			state.emit("last_page_ready", {"page": pg})
			sim.chron(state, "last_page", "장부의 마지막 장이 펼쳐졌다.", true)
			sim.say(state, "장부의 마지막 장이 펼쳐졌다. 장은 넘어가도 도시는 계속된다.")


func _quiet(state: CityState, dt: float) -> void:
	var qs := float(sim.cfg("quiet.start_hour", 3.2)) / 24.0
	var qe := float(sim.cfg("quiet.end_hour", 3.5)) / 24.0
	var t0 := state.econ_days + 1e-9
	var t1 := t0 + dt
	if floorf(t1 - qs) != floorf(t0 - qs):
		state.flags["quiet_state"] = true
		state.emit("quiet_start", {})
	if floorf(t1 - qe) != floorf(t0 - qe):
		if bool(state.flags.get("quiet_state", false)):
			state.flags["quiet_state"] = false
			state.emit("quiet_end", {})


# ------------------------------------------------------------------ 마지막 장
func _page(state: CityState) -> Dictionary:
	var cov := sim.cover(state)
	var nt := sim.max_tier()
	var pop := []
	for t: int in nt:
		pop.append(0.0)
	var total := 0.0
	var fl_res := {}       # z → 주민
	var fl_hap := {}       # z → 행복×주민
	for b: Dictionary in cov["houses"]:
		var r := float(b["residents"])
		if r <= 0.0:
			continue
		pop[int(b["tier"]) - 1] += r
		total += r
		var z: int = (b["pos"] as Vector3i).z
		fl_res[z] = float(fl_res.get(z, 0.0)) + r
		fl_hap[z] = float(fl_hap.get(z, 0.0)) + float(b.get("happiness", 50.0)) * r
	var shares: Array = []
	var tx := []
	for t: int in nt:
		var s := 0.0 if total <= 0.0 else float(pop[t]) / total
		shares.append(snappedf(s, 0.001))
		tx.append("%s %d%%" % [sim.tname(t + 1), int(roundf(s * 100.0))])
	# 쓴 층: 주민이 있거나 시설이 선 층
	var used := {}
	for z: int in sim.F:
		if Cover.used_cells_fast(sim, state, z) > 0:
			used[z] = true
	var zs: Array = used.keys()
	zs.sort()
	var lo := 0.0
	var lo_w := 0.0
	var hi := 0.0
	var hi_w := 0.0
	var half := zs.size() / 2
	for i: int in zs.size():
		var z: int = zs[i]
		if not fl_res.has(z):
			continue
		if i < half:
			lo += float(fl_hap[z])
			lo_w += float(fl_res[z])
		elif i >= zs.size() - half:
			hi += float(fl_hap[z])
			hi_w += float(fl_res[z])
	var diff := 0.0
	if lo_w > 0.0 and hi_w > 0.0:
		diff = hi / hi_w - lo / lo_w
	var s_tax := float(state.stats.get("in.tax", 0.0))
	var s_org := float(state.stats.get("in.vice", 0.0))
	var s_exp := float(state.stats.get("in.export", 0.0))
	var s_all := maxf(1e-9, s_tax + s_org + s_exp)
	var gaze := float(state.flags.get("gaze_max", state.heat))
	var axes: Array = [
		{"id": "tiers", "name": "계층의 모양", "value": snappedf(_mean_tier(shares), 0.01), "shares": shares, "text": " · ".join(tx)},
		{"id": "money_source", "name": "돈의 출처", "value": snappedf(s_org / s_all, 0.01),
			"shares": {"tax": snappedf(s_tax / s_all, 0.01), "org": snappedf(s_org / s_all, 0.01), "export": snappedf(s_exp / s_all, 0.01)},
			"text": "세수 %d%% · 조직 수입 %d%% · 내보낸 값 %d%%" % [int(roundf(s_tax / s_all * 100.0)), int(roundf(s_org / s_all * 100.0)), int(roundf(s_exp / s_all * 100.0))]},
		{"id": "height", "name": "높이", "value": float(zs.size()), "text": "쓴 층 %d층" % zs.size()},
		{"id": "updown", "name": "위아래 행복 차이", "value": snappedf(diff, 0.1),
			"text": "위쪽 절반 층이 아래쪽 절반보다 %s" % (("%.1f 높다" % diff) if diff >= 0.0 else ("%.1f 낮다" % -diff))},
		{"id": "gaze", "name": "바깥의 시선", "value": snappedf(gaze, 0.1), "text": "바깥의 시선 최고 %d" % int(gaze)}]
	var lines: Array = []
	for a: Dictionary in axes:
		lines.append("%s: %s" % [a["name"], a["text"]])
	return {"axes": axes, "text": "\n".join(lines), "pop": int(total)}


func _mean_tier(shares: Array) -> float:
	var m := 0.0
	for i: int in shares.size():
		m += float(shares[i]) * float(i + 1)
	return m


# ------------------------------------------------------------------ 질의·명령
func can(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name == "last_page_ack":
		var ok := state.flags.has("last_page")
		return {"ok": ok, "reason": "" if ok else "마지막 장은 아직 펼쳐지지 않았다."}
	return null


func apply(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name == "last_page_ack":
		state.flags["last_page_shown"] = true
		return {"ok": true, "reason": ""}
	return null


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	match name:
		"date_minryeok":
			return date_q(sim, state)
		"chronicle":
			var lines: Array = state.flags.get("chronicle", [])
			return {"lines": lines.duplicate(true), "count": lines.size()}
		"last_page":
			var ready := state.flags.has("last_page")
			var pg: Dictionary = state.flags["last_page"] if ready else _page(state)
			var di := Calendar.info(sim, state)
			return {"ready": ready, "shown": bool(state.flags.get("last_page_shown", false)),
				"year": int(pg.get("year", di["year"])), "date_text": str(pg.get("date_text", di["date_text"])),
				"axes": (pg["axes"] as Array).duplicate(true), "text": str(pg.get("text", ""))}
	return null


static func date_q(sim_: Sim, state: CityState) -> Dictionary:
	var d := Calendar.info(sim_, state)
	d["quiet"] = bool(state.flags.get("quiet_state", false))
	return d


func augment(state: CityState, name: String, _args: Dictionary, out: Variant) -> void:
	if name == "hud":
		out["date"] = date_q(sim, state)
