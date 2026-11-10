extends SimSystem
## 명물 — 도시 타입(템플릿)은 없다. 쌓인 것에서 별명과 호칭이 나온다(D5). 하루 끝에 다시 본다.
##  · 태그: 가게·시설·주거의 tags를 칸 수만큼 센다(metrics의 tag_count.*). data/identity.json "tags"에 있는 것만 명물 후보,
##    점수 = 칸 수 × weight, min 미만이면 탈락. 지금 별명에 쓰인 태그는 sticky배 유리(하루 만에 뒤집히지 않게).
##  · 별명: "patterns"를 위에서부터 보고 조건(cond)이 맞는 첫 문형을 쓴다. {noun1} {noun2} {adj1} = 상위 태그의 말,
##    {mat} = 가장 많은 자재의 말("materials"), {form} = 덩어리 모양의 말("forms" 중 조건이 맞는 첫 번째).
##  · 호칭: "titles"를 위에서부터 보고 조건이 맞는 첫 호칭. 윗선이 정해 준 호칭(flags.forced_title)이 있으면 그게 먼저다.
## 바뀌면 `identity_changed{title, epithet}` + 기록. 이 시스템을 꺼도 게임은 돈다(호칭은 '대장'에 머문다).


func _conf() -> Dictionary:
	return sim.db.get("identity", {})


func on_new_game(state: CityState) -> void:
	state.identity = {"title": str(_conf().get("default_title", "대장")), "epithet": "", "tags": []}


func on_day_end(state: CityState) -> void:
	var m: Dictionary = sim.metrics(state).duplicate()
	var conf := _conf()
	var old_tags: Array = state.identity.get("tags", [])
	var scored: Array = []
	var tags: Dictionary = conf.get("tags", {})
	for tag: String in tags:
		var n := float(m.get("tag_count." + tag, 0.0))
		var s := n * float(tags[tag].get("weight", 1.0)) * (float(conf.get("sticky", 1.15)) if tag in old_tags else 1.0)
		if n >= float(tags[tag].get("min", 2)):
			scored.append([s, tag])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] if a[0] != b[0] else str(a[1]) < str(b[1]))
	m["id.top1"] = float(scored[0][0]) if scored.size() > 0 else 0.0
	m["id.top2"] = float(scored[1][0]) if scored.size() > 1 else 0.0
	m["id.lead"] = float(m["id.top1"]) / maxf(float(m["id.top2"]), 1.0)
	var words := {"noun1": "", "noun2": "", "adj1": "", "mat": "", "form": ""}
	if scored.size() > 0:
		words["noun1"] = str(tags[scored[0][1]].get("noun", scored[0][1]))
		words["adj1"] = str(tags[scored[0][1]].get("adj", ""))
	if scored.size() > 1:
		words["noun2"] = str(tags[scored[1][1]].get("noun", scored[1][1]))
	var top_mat := ""
	var top_n := 0.0
	for mat: String in conf.get("materials", {}):
		if float(m.get("mat." + mat, 0.0)) > top_n:
			top_n = m["mat." + mat]
			top_mat = mat
	words["mat"] = str(conf.get("materials", {}).get(top_mat, ""))
	m["id.mat_share"] = top_n / maxf(float(m.get("cells", 0.0)), 1.0)
	for f: Dictionary in conf.get("forms", []):
		if Expr.test(f.get("cond"), m):
			words["form"] = str(f.get("word", ""))
			break
	var epithet := ""
	if float(m.get("cells", 0.0)) >= float(conf.get("min_cells", 12)):
		for p: Dictionary in conf.get("patterns", []):
			var text := str(p.get("text", ""))
			var ok := Expr.test(p.get("cond"), m)
			for key: String in words:
				if text.contains("{%s}" % key) and words[key] == "":
					ok = false
			if ok:
				epithet = Sim.kr(text.format(words))
				break
	var title := str(state.flags.get("forced_title", ""))
	if title == "":
		title = str(conf.get("default_title", "대장"))
		for t: Dictionary in conf.get("titles", []):
			if Expr.test(t.get("cond"), m):
				title = str(t.get("title", title))
				break
	var was_title := str(state.identity.get("title", ""))
	var was_epithet := str(state.identity.get("epithet", ""))
	var names: Array = []
	for s: Array in scored.slice(0, 3):
		names.append(s[1])
	state.identity = {"title": title, "epithet": epithet, "tags": names}
	if title != was_title or epithet != was_epithet:
		state.emit("identity_changed", {"title": title, "epithet": epithet})
		if title != was_title:
			state.add_log("사람들이 이제 %s 대신 '%s'(이)라고 부른다." % [was_title, title], "identity")
		if epithet != was_epithet and epithet != "":
			state.add_log("바깥에서는 이곳을 '%s'(이)라 부르기 시작했다." % epithet, "identity")
		state.stats["identity_changes"] = int(state.stats.get("identity_changes", 0)) + 1


func query(state: CityState, name: String, _args: Dictionary) -> Variant:
	if name != "identity":
		return null
	var m := sim.metrics(state)
	var counts := {}
	for tag: String in _conf().get("tags", {}):
		if float(m.get("tag_count." + tag, 0.0)) > 0.0:
			counts[tag] = int(m["tag_count." + tag])
	return {"title": state.identity.get("title", "대장"), "epithet": state.identity.get("epithet", ""),
		"tags": state.identity.get("tags", []), "tag_counts": counts}
