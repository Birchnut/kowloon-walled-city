extends SceneTree
## integ_v05_test — 통합 시험(v0.5): 메인 씬이 오류 없이 뜨고, 규칙의 사건이 화면·그림·소리에 실제로 닿는지 본다.
##   godot --headless --path godot -s res://tests/integ_v05_test.gd
## 본 것: quiet_start/quiet_end → 그림(_quiet)·소리(quiet_on) / 덮인 층 수 질의 연결 / last_page_ready → 종이 창 / 연표 쪽지 / 새 질의 모양.

var _fails := 0
var game: Node
var sfx: Node


func _ok(c: bool, what: String) -> void:
	print(("  [ok] " if c else "  [FAIL] ") + what)
	if not c:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	game = root.get_node("Game")
	sfx = root.get_node("Sfx")
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var view: Node = main.get_node("CityView")
	var ui: Node = null
	for c: Node in main.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("UIRoot.gd"):
			ui = c
	_ok(ui != null and view != null, "메인 씬에 그림과 화면이 있다")
	# 고요시간: 규칙 사건이 그림과 소리에 닿는다
	game.event.emit("quiet_start", {})
	await process_frame
	_ok(bool(view.get("_quiet")), "quiet_start → 그림의 고요시간이 켜진다")
	_ok(bool(sfx.director.get("quiet_on")), "quiet_start → 소리의 고요시간이 켜진다")
	game.event.emit("quiet_end", {})
	await process_frame
	_ok(not bool(view.get("_quiet")) and not bool(sfx.director.get("quiet_on")), "quiet_end → 둘 다 꺼진다")
	# 규칙이 실제로 사건을 내는가: 하루 반을 한 시간씩 돌려 상태의 사건 줄에서 센다(메인 씬 흐름과 따로 — 새 상태)
	var sim: Variant = game.sim
	var st := CityState.new()
	sim.new_game(st, 3)
	var qs := 0
	var qe := 0
	for i in 36:
		sim.tick(st, 1.0 / 24.0)
		for e: Dictionary in st.events:
			if e["name"] == "quiet_start":
				qs += 1
			elif e["name"] == "quiet_end":
				qe += 1
		st.events.clear()
	_ok(qs >= 1 and qe >= 1, "규칙이 고요시간 사건을 낸다(시작 %d·끝 %d)" % [qs, qe])
	# 덮인 층 수: 그림이 규칙의 질의를 쓴다
	_ok(str(view.get("cfg").r("cover.source", "local")) == "sim", "render.json cover.source = sim")
	var cd: Variant = game.query("covered_depth", {})
	_ok(cd is Dictionary, "covered_depth(질의, 인자 없음)가 사전을 준다")
	# 새 질의의 모양
	for q: String in ["date_minryeok", "chronicle", "security", "conflict", "leak_per_day", "last_page", "idle_citizens"]:
		_ok(game.query(q, {}) is Dictionary, "질의 %s 가 사전을 준다" % q)
	var h: Dictionary = game.query("hud", {})
	_ok(h.has("date") and str((h["date"] as Dictionary).get("date_text", "")).begins_with("민력"), "hud.date 가 민력 글이다")
	# 연표 쪽지·마지막 장 창
	ui.toasts.clear()
	game.event.emit("chronicle_added", {"text": "시험 줄.", "date_text": "민력 4년 장마", "kind": "first_org"})
	await process_frame
	_ok(ui.toasts._items.size() == 1, "연표에 새 줄 → 종이 쪽지 한 번")
	game.event.emit("last_page_ready", {"page": {}})
	await process_frame
	await process_frame
	_ok(bool((ui.wins["last_page"] as Control).visible), "last_page_ready → 마지막 장 창이 뜬다")
	_ok(ui.wins.has("keep") and (ui.wins["keep"].get("_tabs") as Dictionary).has("chronicle"), "네모청에 연표 탭이 있다")
	print("INTEG V05 TEST: ", "PASS" if _fails == 0 else "FAIL %d" % _fails)
	quit(0 if _fails == 0 else 1)
