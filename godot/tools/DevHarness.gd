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
##   tap=x,y                화면 좌표 탭(뷰 pick → UI)
##   fakeexp=<json 경로>     탐험 질의 대신 이 파일(계약 모양 견본 — B 파트 데이터가 오기 전 지도 확인용)
##   offline=1              자리 비운 사이 창(견본 문장)
##   toast=1 banner=<unlock|milestone|floor|power>   피드백 견본
##   at=<초>                위 인자들을 적용할 시각(기본 0.6초)

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


func _on_event(n: String, _p: Dictionary) -> void:
	if n == "hour" and _bot != null:
		_bot.act(Game.state)


func _process(delta: float) -> void:
	_t += delta
	if _applied or _t < float(args.get("at", 0.6)):
		return
	_applied = true
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
				_:
					Game.cmd("debug", {"op": kv[0]})
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
