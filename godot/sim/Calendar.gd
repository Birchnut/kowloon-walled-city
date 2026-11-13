class_name Calendar
extends RefCounted
## Calendar — 민력(v0.5). 날짜는 민력으로 센다: 게임 사흘 = 한 해, 한 해 = 계절 넷. 시작은 민력 4년 장마.
## 순수 계산(상태를 바꾸지 않는다). 수치는 config calendar.*.


static func info(sim: Sim, state: CityState) -> Dictionary:
	return info_at(sim, state.econ_days, state.hour)


static func info_at(sim: Sim, econ_days: float, hour: float) -> Dictionary:
	var dpy := maxf(0.1, float(sim.cfg("calendar.days_per_year", 3.0)))
	var names: Array = sim.cfg("calendar.seasons", ["봄", "여름", "가을", "겨울"])
	var n := maxi(1, names.size())
	var y0 := int(sim.cfg("calendar.start_year", 4))
	var yidx := int(floorf((econ_days + 1e-9) / dpy))
	var ypos := fposmod(econ_days + 1e-9, dpy)
	var sidx := clampi(int(floorf(ypos / dpy * float(n))), 0, n - 1)
	var season := str(names[sidx])
	if yidx == 0 and sidx == 0:
		season = str(sim.cfg("calendar.first_season_name", "장마"))
	var h := int(floorf(hour + 1e-6))
	var m := int(floorf((hour - float(h)) * 60.0 + 1e-6))
	return {"year": y0 + yidx, "season": season, "season_idx": sidx, "year_day": snappedf(ypos, 0.001), "hour": h, "minute": m,
		"date_text": "민력 %d년 %s" % [y0 + yidx, season],
		"text": "민력 %d년 %s %02d:%02d" % [y0 + yidx, season, h, m],
		"quiet": false}
