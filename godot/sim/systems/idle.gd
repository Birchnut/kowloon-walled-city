extends SimSystem
## idle — 쉬었음시민(일하지 않는 벽틈시민)의 소일(v0.5, docs/DESIGN_v0.5.md C7). 아주 약하게, 수에 비례한다.
##  쉬었음시민 = 벽틈시민(주민 + 대기) − floor(그 × 노동 참여율) — workforce의 노동력 풀과 같은 식. 넷 가운데 하나다.
##  효과(config idle.*): 행복 +(수 × happy_per, 최대 happy_max — 0.25 단위) · 오물이 쌓이는 속도 −(수 × trash_cut_per, 최대 trash_cut_max)
##   · 병이 날 확률 −(수 × disease_cut_per, 최대 disease_cut_max). 결과는 state.flags.idle_happy / idle_trash_cut / idle_disease_cut에 두고
##   needs·hazards가 읽는다(시스템끼리 부르지 않는다). 행복 값이 바뀔 때만 수정치 캐시를 비운다(Sim.mods_changed).
## 끄면: 쉬었음시민은 질의로만 세고 아무 효과도 없다.


## 쉬었음시민 수(질의·시험용 정적 계산).
static func count(sim_: Sim, state: CityState) -> int:
	var total := 0
	for b: Dictionary in sim_.cover(state)["houses"]:
		if int(b["tier"]) == 1:
			total += int(b["residents"])
	total += int(state.waiting.get(1, {}).get("count", 0))
	var have := int(floorf(float(total) * float(sim_.tier(1).get("labor", 1.0)) + 1e-9))
	return maxi(0, total - have)


func tick(state: CityState, dt: float) -> void:
	if not sim.every(state, 2, dt):
		return
	var n := count(sim, state)
	var hp := minf(float(sim.cfg("idle.happy_max", 2.0)), snappedf(float(n) * float(sim.cfg("idle.happy_per", 0.05)), 0.25))
	var tc := minf(float(sim.cfg("idle.trash_cut_max", 0.2)), snappedf(float(n) * float(sim.cfg("idle.trash_cut_per", 0.002)), 0.001))
	var dc := minf(float(sim.cfg("idle.disease_cut_max", 0.2)), snappedf(float(n) * float(sim.cfg("idle.disease_cut_per", 0.002)), 0.001))
	state.flags["idle_count"] = n
	state.flags["idle_trash_cut"] = tc
	state.flags["idle_disease_cut"] = dc
	if hp != float(state.flags.get("idle_happy", 0.0)):
		state.flags["idle_happy"] = hp
		Sim.mods_changed(state)


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "idle_citizens":
		return null
	var n := count(sim, state)
	var t1 := 0
	for b: Dictionary in sim.cover(state)["houses"]:
		if int(b["tier"]) == 1:
			t1 += int(b["residents"])
	return {"count": n, "t1": t1, "text": "쉬었음시민 %d명. 일하지 못하지만 골목에서 소일한다." % n if n > 0 else "쉬었음시민이 없다."}
