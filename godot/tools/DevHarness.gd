extends Node
## DevHarness — 개발용: 사용자 인자로 메인 씬을 몰아 본다(통합 확인·스크린샷). 게임 규칙 없음.
## Main 이 인자를 보고 붙인다. tools/shot.sh "" <out> <frames> <WxH> key=value … 로 쓴다.
##   skiptut                오프닝 건너뛰기            tut=<n>          오프닝을 n단계부터
##   load=<early|mid|late|경로>  상태 스냅샷(tools/fixtures/<이름>.json 또는 CityState.to_json 파일)
##   bot=<id>  speed=<n>  pause=1
##   tod=<0..1>  cut=<n>  zoom=<i>  angle=<0..3>  lens=1          뷰 고정
##   dbg=<op[:n][,op…]>     디버그 명령: add_money:5000, mats:20(세 자재 +n), skip_days:1, skip_real:600, unlock_all, reveal_partners
##   do=<cmd>|<json>        Game.cmd 를 그대로(예: do=zone|{"cells":[[0,0,0],[1,0,0]]}) — 여러 개면 ;; 로 잇는다
##   open=<screen[:arg]>    화면 열기: build[:house|<시설 id>|<분류>] economy[:labor|utilities|finance|<상품>] expedition trade keep[:policy|research|log] upgrade(일괄)
##   inspect=x,y,z          그 칸 들여다보기       upgrade=x,y,z[,material]  그 집 승급 창
##   paint=x,y,z[;x,y,z…]   주거 칠하기 모드에서 칸 고르기(cell_dragged 흉내)
##   place=<시설>@x,y,z     시설 배치 모드 + 그 자리 후보
##   confirm=1              짓기 막대의 확정/짓기를 누른다(paint=/place= 뒤)
##   tap=x,y                화면 좌표 탭(뷰 pick → UI)
##   fakeexp=<json 경로>     탐험 질의 대신 이 파일(계약 모양 견본 — B 파트 데이터가 오기 전 지도 확인용)
##   fakekeep=<json 경로>    연구·정책 질의 대신 이 파일(견본)
##   offline=1              자리 비운 사이 창(견본 문장)
##   toast=1 banner=<unlock|milestone|floor|power>   피드백 견본
##   png=<절대 경로>         (무비 대신) 실제 창 크기 그대로 한 장 찍고 끝낸다 — 360x800 같은 화면비 확인용. png_wait=<초>
##   at=<초>                위 인자들을 적용할 시각(기본 0.6초)
##   script=<json 경로>     시간 순서 동작 목록을 진짜 입력(Input.parse_input_event)으로 몬다 — 아래 _run_script 참고.
##   out=<폴더>             script 의 shot 이 PNG 를 남길 곳(기본: script 파일 옆 shots/)
##   save_at=<경로>  ago=<초>  현재 상태를 last_saved_unix = 지금 - ago 로 저장하고 끝(미접속 시험용 세이브 만들기)
##   load_save=<경로>        Game.load_game 과 같은 길(미접속 정산 포함)로 그 파일을 읽는다. load_ago=<초> 면 마지막 정산을 그만큼 전으로

const FIX := "res://tools/fixtures/%s.json"

var args: Dictionary = {}
var ui: Node = null
var view: Node = null
var _bot: Bot = null
var _applied := false
var _t := 0.0


static func wanted() -> Dictionary:
	var out := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out.erase("nosave")
	return out


func _ready() -> void:
	if args.has("load_save"):
		var s0 := CityState.new()
		if s0.from_json(FileAccess.get_file_as_string(str(args["load_save"]))):
			# Game.load_game 과 같은 순서: 상태 → 미접속 정산 → 교체 알림
			Game.state = s0
			if args.has("load_ago"):
				s0.last_saved_unix = Game._now() - int(args["load_ago"])
			Game.sim.now_unix = Game._now()
			Game._last_frame_unix = Game.sim.now_unix
			Game._offline_catch_up()
			Game.replace_state(s0)
		else:
			push_warning("[DevHarness] 세이브를 읽지 못함: " + str(args["load_save"]))
	if args.has("load"):
		var p := str(args["load"])
		if not p.contains("/"):
			p = FIX % p
		var text := FileAccess.get_file_as_string(p)
		if text != "":
			var s := CityState.new()
			if s.from_json(text):
				Game.replace_state(s)
			else:
				push_warning("[DevHarness] 상태를 읽지 못함: " + p)
	if args.has("speed"):
		Game.speed = float(args["speed"])
	if args.has("bot"):
		_bot = Bot.new(Game.sim, str(args["bot"]))
		Game.event.connect(_on_event)
	if args.has("fakeexp") and ui != null:
		var j := JSON.new()
		var p2 := str(args["fakeexp"])
		if not p2.contains("/"):
			p2 = FIX % p2
		if j.parse(FileAccess.get_file_as_string(p2)) == OK and j.data is Dictionary:
			var data: Dictionary = j.data
			ui.expedition.source = func() -> Dictionary: return data


	if args.has("fakekeep") and ui != null:
		var j2 := JSON.new()
		var p3 := str(args["fakekeep"])
		if not p3.contains("/"):
			p3 = FIX % p3
		if j2.parse(FileAccess.get_file_as_string(p3)) == OK and j2.data is Dictionary:
			var kd: Dictionary = j2.data
			ui.keep.research_source = func() -> Dictionary: return UI.to_dict(kd.get("research", {}))
			ui.keep.policy_source = func() -> Dictionary: return UI.to_dict(kd.get("policies", {}))


func _on_event(n: String, _p: Dictionary) -> void:
	if n == "hour" and _bot != null:
		_bot.act(Game.state)


var _tut_last := -99
var _scr_last := "?"


func _process(delta: float) -> void:
	_t += delta
	if args.has("trace") and ui != null:
		# 오프닝 단계·화면이 바뀔 때마다 한 줄(통합 확인용)
		var si: int = ui.tutorial.step_index() if ui.tutorial.running else -1
		if si != _tut_last:
			_tut_last = si
			var st: Dictionary = UI.to_dict(ui.tutorial._steps[si]) if si >= 0 and si < ui.tutorial._steps.size() else {}
			print("[trace] t=%.1f 오프닝 %d %s %s" % [_t, si, st.get("type", ""), str(st.get("text", st.get("hint", st.get("cmd", "")))).substr(0, 24)])
		if str(ui.screen) != _scr_last:
			_scr_last = str(ui.screen)
			print("[trace] t=%.1f 화면 '%s'" % [_t, _scr_last])
	if args.has("png") and _applied and _t >= float(args.get("at", 0.6)) + float(args.get("png_wait", 1.6)):
		var img := get_viewport().get_texture().get_image()
		img.save_png(str(args["png"]))
		print("[DevHarness] png ", args["png"], " ", img.get_size())
		args.erase("png")
		get_tree().quit()
	if _applied or _t < float(args.get("at", 0.6)):
		return
	_applied = true
	if args.has("script"):
		_run_script.call_deferred()
	if args.has("save_at"):
		_save_at.call_deferred()
	if args.has("skiptut") and ui != null:
		ui.tutorial.skip()
		ui.toasts.clear()
	if args.has("tut") and ui != null:
		ui.tutorial.start(int(args["tut"]))
	if args.has("speed"):
		Game.speed = float(args["speed"])
	if args.has("pause"):
		Game.paused = true
	if args.has("dbg"):
		_apply_dbg()
	if args.has("do"):
		for part: String in str(args["do"]).split(";;"):
			var cv := part.split("|", true, 1)
			var a := {}
			if cv.size() > 1:
				var j := JSON.new()
				if j.parse(cv[1]) == OK and j.data is Dictionary:
					a = _vecs(j.data)
			var r: Dictionary = ui.cmd(cv[0], a) if ui != null else Game.cmd(cv[0], a)
			print("[DevHarness] do ", cv[0], " → ", r.get("ok"), " ", r.get("reason", ""))
	if view != null:
		if args.has("angle"):
			for i: int in int(args["angle"]):
				view.rotate_view(1)
		if args.has("zoom"):
			view.set_zoom(int(args["zoom"]))
		if args.has("cut"):
			view.set_floor_cut(int(args["cut"]))
			if ui != null:
				ui.rail.set_cut(int(args["cut"]))
		if args.has("tod"):
			view.set_time_override(float(args["tod"]))
		if args.has("lens") and ui != null:
			ui.rail.set_lens(true)
			view.set_lens("needs")
	if ui == null:
		return
	if args.has("open"):
		var o := str(args["open"]).split(":", true, 1)
		if o[0] == "upgrade":
			ui.upgrade_all()
		else:
			ui.open_screen(o[0], o[1] if o.size() > 1 else "")
	if args.has("inspect"):
		var p := _v3(str(args["inspect"]))
		ui.open_screen("inspect")
		ui.inspect.show_cell(p)
	if args.has("upgrade"):
		var u := str(args["upgrade"]).split(",")
		var p2 := _v3(str(args["upgrade"]))
		var info := Q.dict("info", {"pos": p2})
		ui.open_upgrade(int(info.get("bid", -1)), info)
		if u.size() > 3:
			ui.upgrade.mat = u[3]
			ui.upgrade._refresh()
	if args.has("paint"):
		ui.open_screen("build", "house")
		var first := true
		for c: String in str(args["paint"]).split(";"):
			ui.build.on_drag({"ok": true, "in_grid": true, "pos": _v3(c), "first": first})
			first = false
	if args.has("place"):
		var pp := str(args["place"]).split("@")
		ui.open_screen("build", pp[0])
		var it: Dictionary = ui.build._find(pp[0])
		if not it.is_empty():
			ui.build._start(it)
			if pp.size() > 1:
				ui.build.on_drag({"ok": true, "in_grid": true, "pos": _v3(pp[1]), "first": true})
	if args.has("go"):
		var n0 := 0
		for b: Variant in Game.state.buildings.values():
			if b.get("upgrading") != null:
				n0 += 1
		ui.upgrade._on_go()
		var n1 := 0
		for b: Variant in Game.state.buildings.values():
			if b.get("upgrading") != null:
				n1 += 1
		print("[DevHarness] upgrade go → 공사 중 ", n0, " → ", n1, " dialog ", ui.upgrade.visible)
	if args.has("confirm"):
		ui.build._on_confirm()
		print("[DevHarness] confirm → money ", int(Game.state.money), " cells ", Game.state.cells.size())
	if args.has("tap") and view != null:
		var xy := str(args["tap"]).split(",")
		var info2: Dictionary = view.pick(Vector2(float(xy[0]), float(xy[1])))
		ui._on_cell_tapped(info2)
	if args.has("offline"):
		ui._show_offline({"real_hours": 3.4, "econ_days": 5.1, "lines": [
			"자리를 비운 사이 경제 시간으로 5.1일이 흘렀다.", "국수 52개를 만들고 61개를 먹었다 — 2일째 저녁에 바닥났다.",
			"계약 4회 이행, 1회 건너뜀(돈이 모자랐다).", "탐험대 1팀이 돌아와 수령을 기다린다."]})
	if args.has("toast"):
		ui.toast("국수 공장 완공.", "")
		ui.toast("계약 회차를 건너뛰었다 — 밀가루가 모자란다(20 필요).", "warn")
		ui.toast("탐험대가 돌아왔다. 탐험에서 수령하자.", "good", "mat")
		ui.toast("돈이 없어 시설 2곳이 멈췄다.", "bad")
	if args.has("banner"):
		match str(args["banner"]):
			"unlock":
				ui._banner_unlock({"id": "noodle_mill", "name": "제면소"})
			"milestone":
				ui._banner_milestone({"grade": 3, "grade_name": "성채", "title": "성주"})
			"floor":
				ui._on_event("floor_unlocked", {"z": 2})
			"power":
				ui._last_dim_ms = -100000
				ui._lights_on()


func _v3(s: String) -> Vector3i:
	var a := s.split(",")
	return Vector3i(int(a[0]), int(a[1]) if a.size() > 1 else 0, int(a[2]) if a.size() > 2 else 0)


## JSON 의 [x,y,z] 배열을 Vector3i 로(pos·cells).
func _vecs(d: Dictionary) -> Dictionary:
	for k: String in d.keys():
		var v: Variant = d[k]
		if k == "pos" and v is Array and v.size() == 3:
			d[k] = Vector3i(int(v[0]), int(v[1]), int(v[2]))
		elif k == "cells" and v is Array:
			var out: Array = []
			for c: Variant in v:
				if c is Array and c.size() == 3:
					out.append(Vector3i(int(c[0]), int(c[1]), int(c[2])))
			d[k] = out
	return d


# ------------------------------------------------------------------ script= (진짜 입력으로 몰기)
## JSON 배열. 각 항목은 동작 하나 + 선택 "after"(그 전에 기다릴 초, 기본 0.3).
##   {"wait": 초}                         기다림(게임 시간; 무비는 10fps 고정)
##   {"tap": [x, y]}                      화면 좌표 터치(누름 → 0.1초 → 뗌). 진짜 InputEventScreenTouch
##   {"click": [x, y]}                    마우스 왼쪽 클릭
##   {"drag": [[x,y],[x,y]…], "steps": n}  한 손가락 끌기(점 사이를 n등분)
##   {"press": "글자", "nth": 0, "region": [x0,y0,x1,y1]}   보이는 버튼(없으면 라벨) 중 글자를 품은 것의 가운데를 터치
##   {"target": "exp:dest:<id>"}         UIRoot.target_rect 이름의 가운데를 터치
##   {"cell": [x,y,z]}                    뷰가 그 칸을 그린 화면 좌표를 터치
##   {"paint": [[x,y,z]…]}                칸들의 화면 좌표를 잇는 끌기(칠하기 모드에서 쓴다)
##   {"shot": "이름"}                      out/이름.png
##   {"cmd": 이름, "args": {}}            ui.cmd(검증용 — 진짜 UI 길이 아님을 로그에 남긴다)
##   {"dbg": "skip_real:600,mats:20"}     디버그 명령(dbg= 와 같은 문법)
##   {"q": "hud", "keys": ["money", …]}   질의를 찍는다(keys 가 있으면 그 키만)
##   {"until": {"q":"hud","key":"pop_total","ge":5}, "max": 초}   조건까지 기다림(키는 a.b 점 경로)
##   {"speed": n}  {"key": "F5"}  {"say": "로그"}  {"dump": "buttons"}  {"quit": 1}
var _out_dir := ""


func _run_script() -> void:
	var path := str(args["script"])
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Array):
		push_error("[script] 읽지 못함: " + path)
		get_tree().quit()
		return
	_out_dir = str(args.get("out", path.get_base_dir().path_join("shots")))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var i := 0
	for st: Variant in j.data:
		i += 1
		if not (st is Dictionary):
			continue
		var s: Dictionary = st
		await _sleep(float(s.get("after", 0.3)))
		await _step(i, s)
	print("[script] 끝")
	get_tree().quit()


func _sleep(sec: float) -> void:
	if sec > 0.0:
		await get_tree().create_timer(sec, true, false, false).timeout


func _step(i: int, s: Dictionary) -> void:
	if s.has("wait"):
		await _sleep(float(s["wait"]))
	elif s.has("tap"):
		await _touch(_xy(s["tap"]))
	elif s.has("click"):
		await _click(_xy(s["click"]))
	elif s.has("drag"):
		var pts: Array = []
		for p: Variant in s["drag"]:
			pts.append(_xy(p))
		await _drag(pts, int(s.get("steps", 6)))
	elif s.has("press_in"):
		# 글자 c 를 품은 라벨이 든 판(가장 가까운 PanelContainer) 안의 n번째 버튼. 끌기 목록이면 먼저 그 판이 보이게 굴린다.
		var lab := _find_ctrl(str(s["press_in"]), int(s.get("nth", 0)), s.get("region"), true)
		if lab == null:
			print("[script] #%d press_in 못 찾음: %s" % [i, s["press_in"]])
			return
		# 행 = 끌기 목록 내용(DragScroll 의 자식)의 바로 아래 자식. 목록 밖이면 가장 가까운 PanelContainer
		var panel: Node = lab
		while panel != null and panel.get_parent() != null and not (panel.get_parent().get_parent() is DragScroll):
			panel = panel.get_parent()
		if panel == null or panel.get_parent() == null:
			panel = lab
			while panel != null and not (panel is PanelContainer):
				panel = panel.get_parent()
		var ds: Node = panel
		while ds != null and not (ds is DragScroll):
			ds = ds.get_parent()
		if ds != null:
			var d: DragScroll = ds
			var rel := (panel as Control).get_global_rect().position.y - d.get_global_rect().position.y
			d.scroll_to(d.offset + rel - 8.0)
			await get_tree().process_frame
			await get_tree().process_frame
		var bs: Array = []
		_buttons_in(panel, bs)
		var want := str(s.get("button", ""))
		var pick: Control = null
		var k := 0
		for b: Control in bs:
			var bt := _plain((b as PixelButton).label_text if b is PixelButton else (b as Button).text)
			if want == "" or bt.contains(want):
				if k == int(s.get("bn", 0)):
					pick = b
					break
				k += 1
		if pick == null:
			print("[script] #%d press_in '%s' 안에 버튼 없음(%d개)" % [i, s["press_in"], bs.size()])
			return
		print("[script] #%d press_in '%s' → '%s' @ %s" % [i, s["press_in"], _plain((pick as PixelButton).label_text if pick is PixelButton else (pick as Button).text), pick.get_global_rect().get_center()])
		await _touch(pick.get_global_rect().get_center())
	elif s.has("press"):
		var c := _find_ctrl(str(s["press"]), int(s.get("nth", 0)), s.get("region"))
		if c == null:
			print("[script] #%d press 못 찾음: %s" % [i, s["press"]])
			if bool(s.get("must", false)):
				_dump()
			return
		var at := c.get_global_rect().get_center()
		print("[script] #%d press '%s' @ %s (%s)" % [i, s["press"], at, c.get_class()])
		await _touch(at)
	elif s.has("target"):
		# 튜토리얼 강조 대상 이름(UIRoot.target_rect)의 가운데를 터치: exp:dest:<id>, exp:claim, nav_build, alert …
		var r: Rect2 = ui.target_rect(str(s["target"]))
		print("[script] #%d target %s → %s" % [i, s["target"], r])
		if r.size.x > 0:
			await _touch(r.get_center())
	elif s.has("cell"):
		var p := _v3arr(s["cell"])
		var sp := _cell_xy(p, bool(s.get("top", true)))
		print("[script] #%d cell %s → %s" % [i, p, sp])
		await _touch(sp)
	elif s.has("paint"):
		var pts2: Array = []
		for p2: Variant in s["paint"]:
			pts2.append(_cell_xy(_v3arr(p2), false))
		print("[script] #%d paint %s" % [i, pts2])
		await _drag(pts2, int(s.get("steps", 3)))
	elif s.has("shot"):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var f := _out_dir.path_join(str(s["shot"]) + ".png")
		img.save_png(f)
		print("[script] #%d shot %s" % [i, f])
	elif s.has("cmd"):
		var a: Dictionary = _vecs(UI.to_dict(s.get("args", {})).duplicate(true))
		var r: Dictionary = ui.cmd(str(s["cmd"]), a)
		print("[script] #%d cmd %s → %s" % [i, s["cmd"], JSON.stringify(r)])
	elif s.has("dbg"):
		args["dbg"] = str(s["dbg"])
		_apply_dbg()
		print("[script] #%d dbg %s" % [i, s["dbg"]])
	elif s.has("q"):
		var v: Variant = Game.query(str(s["q"]), _vecs(UI.to_dict(s.get("args", {})).duplicate(true)))
		if s.has("keys") and v is Dictionary:
			var o := {}
			for k: Variant in s["keys"]:
				o[k] = _path(v, str(k))
			v = o
		print("[script] #%d q %s = %s" % [i, s["q"], JSON.stringify(v)])
	elif s.has("until"):
		var u: Dictionary = s["until"]
		var t0 := 0.0
		var mx := float(s.get("max", 60.0))
		while t0 < mx:
			var v2: Variant = _path(Game.query(str(u.get("q", "hud"))), str(u.get("key", "")))
			if _cond(v2, u):
				break
			await _sleep(0.5)
			t0 += 0.5
		print("[script] #%d until %s → %s (%.1f초)" % [i, JSON.stringify(u), "됨" if t0 < mx else "시간 초과", t0])
	elif s.has("speed"):
		Game.speed = float(s["speed"])
	elif s.has("expr"):
		# 개발 확인용: Expression 으로 값 찍기(입력 이름: ui, view, game)
		var e := Expression.new()
		if e.parse(str(s["expr"]), ["ui", "view", "game"]) == OK:
			print("[script] #%d expr %s = %s" % [i, s["expr"], e.execute([ui, view, Game], self)])
		else:
			print("[script] #%d expr 해석 실패: %s" % [i, e.get_error_text()])
	elif s.has("tod"):
		Q.vcall("set_time_override", [float(s["tod"])])
	elif s.has("view"):
		# 뷰 조작: {"view": "rotate", "n": 1} / {"view": "zoom", "n": 1} / {"view": "cut", "n": 2}
		match str(s["view"]):
			"rotate":
				Q.vcall("rotate_view", [int(s.get("n", 1))])
			"zoom":
				Q.vcall("zoom_step", [int(s.get("n", 1))])
			"cut":
				Q.vcall("set_floor_cut", [int(s.get("n", -1))])
				ui.rail.set_cut(int(s.get("n", -1)))
	elif s.has("jump"):
		# 알림 jump 와 같은 길(UIRoot.jump) — 알림 줄은 돌아가며 바뀌어 터치로 고르기 어렵다
		ui.jump(UI.to_dict(s["jump"]))
		print("[script] #%d jump %s → 화면 '%s'" % [i, JSON.stringify(s["jump"]), ui.screen])
	elif s.has("save"):
		# 지금 상태를 파일로(ago 초 전에 저장한 것처럼). load_save= 로 다시 연다
		var st: CityState = Game.state
		var keep := st.last_saved_unix
		st.last_saved_unix = Game._now() - int(s.get("ago", 0))
		var f := FileAccess.open(str(s["save"]), FileAccess.WRITE)
		f.store_string(st.to_json())
		f.close()
		st.last_saved_unix = keep
		print("[script] #%d save %s" % [i, s["save"]])
	elif s.has("say"):
		print("[script] #%d %s" % [i, s["say"]])
	elif s.has("dump"):
		_dump(str(s["dump"]) == "labels")
	elif s.has("quit"):
		get_tree().quit()


func _cond(v: Variant, u: Dictionary) -> bool:
	if u.has("ge"):
		return v != null and float(v) >= float(u["ge"])
	if u.has("le"):
		return v != null and float(v) <= float(u["le"])
	if u.has("eq"):
		return str(v) == str(u["eq"])
	if u.has("ne"):
		return str(v) != str(u["ne"])
	return v != null and bool(v)


func _path(v: Variant, key: String) -> Variant:
	if key == "":
		return v
	for k: String in key.split("."):
		if v is Dictionary:
			v = v.get(k)
		elif v is Array and k.is_valid_int() and int(k) < v.size():
			v = v[int(k)]
		else:
			return null
	return v


func _apply_dbg() -> void:
	for op: String in str(args["dbg"]).split(","):
		var kv := op.split(":")
		match kv[0]:
			"mats":
				for g: String in ["wood", "metal", "concrete"]:
					Game.cmd("debug", {"op": "add_stock", "good": g, "n": float(kv[1]) if kv.size() > 1 else 20.0})
			"add_money":
				Game.cmd("debug", {"op": "add_money", "n": float(kv[1]) if kv.size() > 1 else 1000.0})
			"skip_days":
				Game.cmd("debug", {"op": "skip_days", "n": float(kv[1]) if kv.size() > 1 else 1.0})
			"skip_real":
				Game.cmd("debug", {"op": "skip_real", "seconds": int(kv[1]) if kv.size() > 1 else 600})
			"stock":
				Game.cmd("debug", {"op": "add_stock", "good": kv[1], "n": float(kv[2]) if kv.size() > 2 else 10.0})
			"fill_floor":
				Game.cmd("debug", {"op": "fill_floor", "z": int(kv[1]) if kv.size() > 1 else 0, "count": int(kv[2]) if kv.size() > 2 else 9999})
			_:
				Game.cmd("debug", {"op": kv[0]})


## 칸의 화면 좌표. top=true 면 건물 윗면(누르기), false 면 그 층 바닥(칠하기 — 뷰의 pick_floor 와 같은 평면).
func _cell_xy(p: Vector3i, top: bool) -> Vector2:
	if view == null:
		return Q.project(p)
	var fh: float = view.cfg.floor_h
	return view.project_world(Vector3(p.x + 0.5, (p.z + (1 if top else 0)) * fh, p.y + 0.5))


func _xy(p: Variant) -> Vector2:
	return Vector2(float(p[0]), float(p[1])) if p is Array and p.size() >= 2 else Vector2.ZERO


func _v3arr(p: Variant) -> Vector3i:
	return Vector3i(int(p[0]), int(p[1]), int(p[2])) if p is Array and p.size() >= 3 else Vector3i.ZERO


func _touch(at: Vector2) -> void:
	var d := InputEventScreenTouch.new()
	d.index = 0
	d.position = at
	d.pressed = true
	Input.parse_input_event(d)
	await get_tree().process_frame
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = at
	u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame


func _click(at: Vector2) -> void:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = at
	m.global_position = at
	m.pressed = true
	Input.parse_input_event(m)
	await get_tree().process_frame
	var m2 := m.duplicate() as InputEventMouseButton
	m2.pressed = false
	Input.parse_input_event(m2)
	await get_tree().process_frame


func _drag(pts: Array, steps: int) -> void:
	if pts.is_empty():
		return
	var d := InputEventScreenTouch.new()
	d.index = 0
	d.position = pts[0]
	d.pressed = true
	Input.parse_input_event(d)
	await get_tree().process_frame
	var last: Vector2 = pts[0]
	for k in range(1, pts.size()):
		for n in range(1, steps + 1):
			var p: Vector2 = (pts[k - 1] as Vector2).lerp(pts[k], float(n) / steps)
			var m := InputEventScreenDrag.new()
			m.index = 0
			m.position = p
			m.relative = p - last
			last = p
			Input.parse_input_event(m)
			await get_tree().process_frame
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = last
	u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame


## 보이는 컨트롤 중 글자를 품은 것(버튼 먼저, 그다음 라벨). region 이 있으면 그 안의 것만.
func _find_ctrl(text: String, nth: int, region: Variant, labels_only: bool = false) -> Control:
	var buttons: Array = []
	var labels: Array = []
	_collect(get_tree().root, text, buttons, labels, region)
	var pool := buttons if not buttons.is_empty() and not labels_only else labels
	return pool[nth] if nth < pool.size() else null


func _collect(n: Node, text: String, buttons: Array, labels: Array, region: Variant) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c: Control = n
		var t := ""
		if c is PixelButton:
			t = (c as PixelButton).label_text
		elif c is Button:
			t = (c as Button).text
		elif c is Label:
			t = (c as Label).text
		t = _plain(t)
		if t != "" and (text == "" or t.contains(text)) and _in_region(c, region):
			if c is Button:
				if not (c as Button).disabled:
					buttons.append(c)
			else:
				labels.append(c)
	for ch in n.get_children():
		_collect(ch, text, buttons, labels, region)


## 줄바꿈 방지용 폭 0 문자(UI.keep)를 걷어 낸 글자.
static func _plain(t: String) -> String:
	for z: String in ["\u200b", "\u2060", "\u200d", "\ufeff", "\u00a0"]:
		t = t.replace(z, "" if z != "\u00a0" else " ")
	return t


func _buttons_in(n: Node, out: Array) -> void:
	if n is BaseButton and not (n as BaseButton).disabled and (n as Control).is_visible_in_tree():
		out.append(n)
	for ch in n.get_children():
		_buttons_in(ch, out)


func _in_region(c: Control, region: Variant) -> bool:
	if not (region is Array) or region.size() < 4:
		return true
	var p := c.get_global_rect().get_center()
	return p.x >= float(region[0]) and p.y >= float(region[1]) and p.x <= float(region[2]) and p.y <= float(region[3])


func _dump(with_labels: bool = false) -> void:
	var b: Array = []
	var l: Array = []
	_collect(get_tree().root, "", b, l, null)
	if with_labels:
		for c: Control in l:
			var r := c.get_global_rect()
			# 화면 밖으로 삐져나간 글자만 표시(잘림 찾기)
			var flag := " <<잘림?" if r.end.x > get_viewport().get_visible_rect().size.x + 0.5 or r.position.x < -0.5 else ""
			print("  [lbl] '%s' %s%s" % [_plain((c as Label).text).replace("\n", "/").substr(0, 40), r, flag])
	for c: Control in b:
		var t: String = _plain((c as PixelButton).label_text if c is PixelButton else (c as Button).text)
		if t.strip_edges() != "":
			print("  [btn] '%s' %s" % [t.replace("\n", "/"), c.get_global_rect()])


## 미접속 시험용: 지금 상태를 "ago 초 전에 저장한 것"처럼 파일로 남기고 끝낸다.
func _save_at() -> void:
	await _sleep(float(args.get("save_wait", 0.5)))
	var st: CityState = Game.state
	st.last_saved_unix = Game._now() - int(args.get("ago", 3600))
	var f := FileAccess.open(str(args["save_at"]), FileAccess.WRITE)
	f.store_string(st.to_json())
	f.close()
	print("[DevHarness] save_at ", args["save_at"], " ago ", args.get("ago", 3600))
	get_tree().quit()
