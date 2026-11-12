extends Node
## DevHarness — 개발용(PC판 v0.4): 사용자 인자로 메인 씬을 몰아 본다(통합 확인·스크린샷). 게임 규칙 없음.
## Main 이 인자를 보고 붙인다. tools/shot.sh "" <out> <frames> 1920x1080 key=value … 로 쓴다.
##   skiptut                오프닝 건너뛰기            tut=<n>           오프닝을 n단계부터
##   load=<early|mid|late|경로>  상태 스냅샷(tools/fixtures/<이름>.json 또는 CityState.to_json 파일)
##   bot=<id>  speed=<n>  pause=1   tod=<0..1>  cut=<n>  zoom=<i>  angle=<0..3>
##   dbg=<op[:n][,op…]>     디버그 명령: add_money:5000, mats:20, skip_days:1, unlock_all, fill_floor:z, stock:good:n
##   do=<cmd>|<json>        Game.cmd 그대로(;; 로 잇는다)
##   open=<metrics|economy|trade|expedition|keep|upgrade|help>[:arg]   창 열기
##   inspect=x,y,z          그 칸 살피기(고정)        upgrade=x,y,z[,material]  그 집 승급 창
##   lens=<needs|market|fun|fire|trash|clinic|tier|happiness>
##   place=<시설 id>@x,y,z[@rot]   배치 모드 + 마우스를 그 칸으로(고스트·범위·커서 글)
##   zone=x0,y0,z;x1,y1     주거 칠하기 모드 + 네모 미리보기(뗄 때 짓지 않음 — 그림 확인용)
##   mouse=x,y              마우스를 그 화면 점으로(툴팁·살피기 미리보기)   hovertext=<글자>  그 글자를 품은 버튼 위로
##   hz=1                   V4Shim 불·병 견본 켜기      hazard_on=<fire|disease>  처음 켜짐 카드 견본
##   scale=<1|1.25|1.5>     UI 크기
##   png=<절대 경로>         실제 창 크기 그대로 한 장 찍고 끝. png_wait=<초>
##   at=<초>                위 인자들을 적용할 시각(기본 0.6초)
##   script=<json 경로>     시간 순서 동작을 진짜 입력(마우스·키보드, Input.parse_input_event)으로 몬다 — 아래 _step 참고
##   out=<폴더>             script 의 shot 이 PNG 를 남길 곳      trace=1  오프닝 단계·창 변화를 찍는다

const FIX := "res://tools/fixtures/%s.json"

var args: Dictionary = {}
var ui: Node = null
var view: Node = null
var _bot: Bot = null
var _applied := false
var _t := 0.0
var _mouse := Vector2(960, 540)
var _buttons_down := 0


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
	if args.has("hz"):
		V4Shim.sample_hazards = true
	if args.has("scale"):
		Settings.set_ui_scale(float(args["scale"]))


func _on_event(n: String, _p: Dictionary) -> void:
	if n == "hour" and _bot != null:
		_bot.act(Game.state)


var _tut_last := -99
var _scr_last := "?"


func _process(delta: float) -> void:
	_t += delta
	if args.has("trace") and ui != null:
		var si: int = ui.tutorial.step_index() if ui.tutorial.running else -1
		if si != _tut_last:
			_tut_last = si
			print("[trace] t=%.1f 오프닝 %d" % [_t, si])
		if str(ui.screen) != _scr_last:
			_scr_last = str(ui.screen)
			print("[trace] t=%.1f 창 '%s'" % [_t, _scr_last])
	if args.has("png") and _applied and _t >= float(args.get("at", 0.6)) + float(args.get("png_wait", 1.6)):
		var img := get_viewport().get_texture().get_image()
		img.save_png(str(args["png"]))
		print("[DevHarness] png ", args["png"], " ", img.get_size())
		args.erase("png")
		get_tree().quit()
	if _applied or _t < float(args.get("at", 0.6)):
		return
	_applied = true
	_apply()


func _apply() -> void:
	if args.has("script"):
		_run_script.call_deferred()
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
		_apply_dbg(str(args["dbg"]))
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
				Q.vcall("rotate_view", [1])
		if args.has("zoom"):
			Q.vcall("set_zoom", [int(args["zoom"])])
		if args.has("cut"):
			Q.vcall("set_floor_cut", [int(args["cut"])])
		if args.has("tod"):
			Q.vcall("set_time_override", [float(args["tod"])])
	if ui == null:
		return
	if args.has("lens"):
		ui.set_lens(str(args["lens"]))
	if args.has("open"):
		var o := str(args["open"]).split(":", true, 1)
		match o[0]:
			"upgrade":
				ui.upgrade_all()
			"help":
				ui.help.toggle()
			_:
				ui.open_window(o[0], o[1] if o.size() > 1 else "")
	if args.has("inspect"):
		ui.inspector.select(_v3(str(args["inspect"])))
		ui._layout()
	if args.has("upgrade"):
		var u := str(args["upgrade"]).split(",")
		var info := Q.dict("info", {"pos": _v3(str(args["upgrade"]))})
		ui.open_upgrade(int(info.get("bid", -1)), info)
		if u.size() > 3:
			ui.upgrade.pick_material(u[3])
	if args.has("hazard_on"):
		ui._on_event("hazard_on", {"kind": str(args["hazard_on"]), "grace_days": 2.0})
	if args.has("place"):
		var pp := str(args["place"]).split("@")
		var it: Dictionary = ui.build.find(pp[0])
		ui.build.select_cat(ui.build.cat_of(pp[0]))
		ui.place.start_build(it)
		if pp.size() > 2 and int(pp[2]) == 1:
			ui.place.rotate()
		if pp.size() > 1:
			await get_tree().process_frame
			await _move(_floor_xy(_v3(pp[1])))
	if args.has("zone"):
		var zz := str(args["zone"]).split(";")
		ui.place.start_zone()
		await get_tree().process_frame
		var a0 := _v3(zz[0])
		var a1 := _v3(zz[1] + "," + str(a0.z)) if zz.size() > 1 else a0
		await _move(_floor_xy(a0))
		ui.place.on_cell_dragged({"pos": a0, "first": true, "ok": true})
		ui.place.on_cell_dragged({"pos": a1, "first": false, "ok": true})
		await _move(_floor_xy(a1))
	if args.has("mouse"):
		await _move(_xy(str(args["mouse"]).split(",")))
	if args.has("hovertext"):
		var c := _find_ctrl(str(args["hovertext"]), 0, null)
		if c != null:
			await _move(c.get_global_rect().get_center())


func _v3(s: String) -> Vector3i:
	var a := s.split(",")
	return Vector3i(int(a[0]), int(a[1]) if a.size() > 1 else 0, int(a[2]) if a.size() > 2 else 0)


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


func _apply_dbg(spec: String) -> void:
	for op: String in spec.split(","):
		var kv := op.split(":")
		match kv[0]:
			"mats":
				for g: String in ["wood", "metal", "concrete"]:
					Game.cmd("debug", {"op": "add_stock", "good": g, "n": float(kv[1]) if kv.size() > 1 else 20.0})
			"add_money":
				Game.cmd("debug", {"op": "add_money", "n": float(kv[1]) if kv.size() > 1 else 1000.0})
			"skip_days":
				Game.cmd("debug", {"op": "skip_days", "n": float(kv[1]) if kv.size() > 1 else 1.0})
			"stock":
				Game.cmd("debug", {"op": "add_stock", "good": kv[1], "n": float(kv[2]) if kv.size() > 2 else 10.0})
			"fill_floor":
				Game.cmd("debug", {"op": "fill_floor", "z": int(kv[1]) if kv.size() > 1 else 0, "count": int(kv[2]) if kv.size() > 2 else 9999})
			_:
				Game.cmd("debug", {"op": kv[0]})


# ------------------------------------------------------------------ script= (진짜 입력으로 몰기)
## JSON 배열. 각 항목은 동작 하나 + 선택 "after"(그 전에 기다릴 초, 기본 0.3). 좌표 대신 이름표·대상으로 쓴다.
##   {"wait": 초}
##   {"move": [x, y]}  {"move_cell": [x,y,z]}(그 칸 바닥)  {"move_target": "<대상>"}  {"hover": "글자"}(그 버튼 위, 툴팁 대기 0.6초)
##   {"click": [x, y], "button": "left|right|middle"}   {"click_cell": [x,y,z]}(바닥)  {"click_top": [x,y,z]}(건물 윗면)
##   {"press": "글자", "nth": 0, "region": [x0,y0,x1,y1]}   보이는 버튼 중 글자를 품은 것을 마우스로 누른다
##   {"target": "<UIRoot.target_rect 이름>"}             그 가운데를 누른다(tool:house · cat:market · card:<id> · win:metrics · speed …)
##   {"paint": [[x,y,z], [x,y,z]], "steps": n}            그 칸 바닥에서 바닥으로 왼쪽 끌기(칠하기)
##   {"drag": [[x,y],[x,y]], "button": "right"}          화면 점 끌기(카메라 이동 등)
##   {"wheel": n, "at": [x,y]}                           휠(+ 확대 / - 축소)
##   {"key": "R", "shift": false, "ctrl": false}         키 한 번(Space, Tab, Esc, F1, Enter, PageUp …)   {"hold": "W", "secs": 0.6}
##   {"place": "<시설 id 또는 분류:<cat>>", "cell": [x,y,z], "rotate": 1}   짓기 막대에서 분류 탭 → 카드 → 그 칸 → 클릭(진짜 마우스)
##   {"shot": "이름"}  {"q": "hud", "keys": [...]}  {"until": {"q","key","ge|le|eq|ne"}, "max": 초}
##   {"dbg": "…"}  {"speed": n}  {"say": "…"}  {"dump": "buttons|labels"}  {"expr": "…"}  {"cmd": 이름, "args": {}}  {"quit": 1}
var _out_dir := ""
var _fails := 0


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
	print("[script] 끝 (못 찾음 %d)" % _fails)
	get_tree().quit()


func _sleep(sec: float) -> void:
	if sec > 0.0:
		await get_tree().create_timer(sec, true, false, false).timeout


func _fail(i: int, what: String) -> void:
	_fails += 1
	print("[script] #%d 못 찾음: %s" % [i, what])


func _step(i: int, s: Dictionary) -> void:
	if s.has("wait"):
		await _sleep(float(s["wait"]))
	elif s.has("move"):
		await _move(_xy(s["move"]))
	elif s.has("move_cell"):
		await _move(_floor_xy(_v3arr(s["move_cell"])))
	elif s.has("move_target"):
		var r0: Rect2 = ui.target_rect(str(s["move_target"]))
		if r0.size.x > 0:
			await _move(r0.get_center())
		else:
			_fail(i, str(s["move_target"]))
	elif s.has("hover"):
		var c0 := _find_ctrl(str(s["hover"]), int(s.get("nth", 0)), s.get("region"))
		if c0 == null:
			_fail(i, "hover " + str(s["hover"]))
			return
		await _move(c0.get_global_rect().get_center())
		await _sleep(0.6)
	elif s.has("click"):
		await _click(_xy(s["click"]), _btn(s))
	elif s.has("click_cell"):
		await _click(_floor_xy(_v3arr(s["click_cell"])), _btn(s))
	elif s.has("click_top"):
		await _click(_top_xy(_v3arr(s["click_top"])), _btn(s))
	elif s.has("press"):
		var c := _find_ctrl(str(s["press"]), int(s.get("nth", 0)), s.get("region"))
		if c == null:
			_fail(i, "press " + str(s["press"]))
			if bool(s.get("must", false)):
				_dump()
			return
		var at := c.get_global_rect().get_center()
		print("[script] #%d press '%s' @ %s" % [i, s["press"], at])
		await _click(at, MOUSE_BUTTON_LEFT)
	elif s.has("target"):
		var r: Rect2 = ui.target_rect(str(s["target"]))
		print("[script] #%d target %s → %s" % [i, s["target"], r])
		if r.size.x > 0:
			await _click(r.get_center(), MOUSE_BUTTON_LEFT)
		else:
			_fail(i, "target " + str(s["target"]))
	elif s.has("paint"):
		var pts: Array = []
		for p: Variant in s["paint"]:
			pts.append(_floor_xy(_v3arr(p)))
		print("[script] #%d paint %s" % [i, s["paint"]])
		await _drag(pts, int(s.get("steps", 4)), MOUSE_BUTTON_LEFT)
	elif s.has("drag"):
		var pts2: Array = []
		for p2: Variant in s["drag"]:
			pts2.append(_xy(p2))
		await _drag(pts2, int(s.get("steps", 8)), _btn(s))
	elif s.has("wheel"):
		var n := int(s["wheel"])
		var at2 := _xy(s.get("at", [_mouse.x, _mouse.y]))
		for k in absi(n):
			await _wheel(at2, n > 0)
	elif s.has("key"):
		await _key(str(s["key"]), bool(s.get("shift", false)), bool(s.get("ctrl", false)))
		print("[script] #%d key %s" % [i, s["key"]])
	elif s.has("hold"):
		await _hold(str(s["hold"]), float(s.get("secs", 0.5)))
	elif s.has("place"):
		await _place(i, s)
	elif s.has("shot"):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var f := _out_dir.path_join(str(s["shot"]) + ".png")
		img.save_png(f)
		print("[script] #%d shot %s" % [i, f])
	elif s.has("cmd"):
		var a: Dictionary = _vecs(UI.to_dict(s.get("args", {})).duplicate(true))
		var rr: Dictionary = ui.cmd(str(s["cmd"]), a)
		print("[script] #%d cmd %s → %s (진짜 UI 길 아님)" % [i, s["cmd"], JSON.stringify(rr)])
	elif s.has("dbg"):
		_apply_dbg(str(s["dbg"]))
		print("[script] #%d dbg %s" % [i, s["dbg"]])
	elif s.has("q"):
		var v: Variant = Q.raw(str(s["q"]), _vecs(UI.to_dict(s.get("args", {})).duplicate(true)))
		if s.has("keys") and v is Dictionary:
			var o := {}
			for k2: Variant in s["keys"]:
				o[k2] = _path(v, str(k2))
			v = o
		print("[script] #%d q %s = %s" % [i, s["q"], JSON.stringify(v).substr(0, 600)])
	elif s.has("until"):
		var u: Dictionary = s["until"]
		var t0 := 0.0
		var mx := float(s.get("max", 60.0))
		while t0 < mx:
			var v2: Variant = _path(Q.raw(str(u.get("q", "hud"))), str(u.get("key", "")))
			if _cond(v2, u):
				break
			await _sleep(0.5)
			t0 += 0.5
		print("[script] #%d until %s → %s (%.1f초)" % [i, JSON.stringify(u), "됨" if t0 < mx else "시간 초과", t0])
		if t0 >= mx:
			_fails += 1
	elif s.has("speed"):
		Game.speed = float(s["speed"])
	elif s.has("expr"):
		var e := Expression.new()
		if e.parse(str(s["expr"]), ["ui", "view", "game"]) == OK:
			print("[script] #%d expr %s = %s" % [i, s["expr"], e.execute([ui, view, Game], self)])
		else:
			print("[script] #%d expr 해석 실패: %s" % [i, e.get_error_text()])
	elif s.has("say"):
		print("[script] #%d %s" % [i, s["say"]])
	elif s.has("dump"):
		_dump(str(s["dump"]) == "labels")
	elif s.has("quit"):
		get_tree().quit()


## 짓기 막대로 시설 하나를 진짜 마우스로 놓는다: 분류 탭 → 카드 → (R) → 그 칸으로 → 클릭.
func _place(i: int, s: Dictionary) -> void:
	var id := str(s["place"])
	var cat := ""
	if id.begins_with("분류:"):
		cat = id.substr(3)
		id = ""
		for c: Variant in Q.list("build_menu"):
			if str(UI.to_dict(c).get("cat", "")) == cat:
				for it: Variant in UI.to_array(UI.to_dict(c).get("items", [])):
					if not bool(UI.to_dict(it).get("locked", false)):
						id = str(UI.to_dict(it).get("id", ""))
						break
	else:
		cat = ui.build.cat_of(id)
	if id == "":
		_fail(i, "place " + str(s["place"]))
		return
	if ui.build.cat != cat:
		var cr: Rect2 = ui.target_rect("cat:" + cat)
		if cr.size.x <= 0:
			_fail(i, "cat:" + cat)
			return
		await _click(cr.get_center(), MOUSE_BUTTON_LEFT)
		await _sleep(0.2)
	var kr: Rect2 = ui.target_rect("card:" + id)
	if kr.size.x <= 0:
		_fail(i, "card:" + id)
		return
	await _click(kr.get_center(), MOUSE_BUTTON_LEFT)
	await _sleep(0.2)
	for k in int(s.get("rotate", 0)):
		await _key("R")
	var cell := _v3arr(s.get("cell", [0, 0, 0]))
	var fp: Vector2i = ui.place._fp()
	# 마우스는 발자국 가운데(Placement._origin 이 되돌린다)
	var hv := Vector3i(cell.x + (fp.x - 1) / 2, cell.y + (fp.y - 1) / 2, cell.z)
	await _move(_floor_xy(hv))
	await _sleep(0.25)
	if s.has("shot_before"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out_dir.path_join(str(s["shot_before"]) + ".png"))
	var n0: int = Game.state.buildings.size()
	await _click(_floor_xy(hv), MOUSE_BUTTON_LEFT)
	print("[script] #%d place %s @ %s rot %d → 건물 %d → %d (%s)" % [i, id, cell, ui.place.rot, n0, Game.state.buildings.size(), ui.tips.cursor_text.replace("\n", " / ")])


func _btn(s: Dictionary) -> int:
	match str(s.get("button", "left")):
		"right":
			return MOUSE_BUTTON_RIGHT
		"middle":
			return MOUSE_BUTTON_MIDDLE
	return MOUSE_BUTTON_LEFT


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


# ------------------------------------------------------------------ 좌표
## 칸 바닥(그 층 평면)의 화면 좌표(논리 px).
func _floor_xy(p: Vector3i) -> Vector2:
	if view != null and view.has_method("project_world") and view.get("cfg") != null:
		var fh: float = view.cfg.floor_h
		return view.project_world(Vector3(p.x + 0.5, p.z * fh, p.y + 0.5))
	return Q.project(Vector3i(p.x, p.y, p.z - 1))


func _top_xy(p: Vector3i) -> Vector2:
	return Q.project(p)


func _xy(p: Variant) -> Vector2:
	return Vector2(float(p[0]), float(p[1])) if (p is Array or p is PackedStringArray) and p.size() >= 2 else Vector2.ZERO


func _v3arr(p: Variant) -> Vector3i:
	return Vector3i(int(p[0]), int(p[1]), int(p[2])) if p is Array and p.size() >= 3 else Vector3i.ZERO


## 논리 좌표 → 창 픽셀(UI 크기·창 크기 배율).
func _win(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


# ------------------------------------------------------------------ 진짜 입력
func _move(to: Vector2, steps: int = 6) -> void:
	var from := _mouse
	for n in range(1, steps + 1):
		var p := from.lerp(to, float(n) / steps)
		var m := InputEventMouseMotion.new()
		m.position = _win(p)
		m.global_position = m.position
		m.relative = _win(p) - _win(_mouse)
		m.button_mask = _buttons_down
		_mouse = p
		Input.warp_mouse(m.position)
		Input.parse_input_event(m)
		await get_tree().process_frame


func _mb(at: Vector2, button: int, pressed: bool) -> void:
	var m := InputEventMouseButton.new()
	m.button_index = button
	m.position = _win(at)
	m.global_position = m.position
	m.pressed = pressed
	var mask: int = {MOUSE_BUTTON_LEFT: MOUSE_BUTTON_MASK_LEFT, MOUSE_BUTTON_RIGHT: MOUSE_BUTTON_MASK_RIGHT, MOUSE_BUTTON_MIDDLE: MOUSE_BUTTON_MASK_MIDDLE}.get(button, 0)
	if pressed:
		_buttons_down |= mask
	else:
		_buttons_down &= ~mask
	m.button_mask = _buttons_down
	Input.parse_input_event(m)


func _click(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await _move(at, 3)
	_mb(at, button, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_mb(at, button, false)
	await get_tree().process_frame


func _drag(pts: Array, steps: int, button: int) -> void:
	if pts.is_empty():
		return
	await _move(pts[0], 3)
	_mb(pts[0], button, true)
	await get_tree().process_frame
	for k in range(1, pts.size()):
		for n in range(1, steps + 1):
			var p: Vector2 = (pts[k - 1] as Vector2).lerp(pts[k], float(n) / steps)
			await _move(p, 1)
	await get_tree().process_frame
	_mb(pts[pts.size() - 1], button, false)
	await get_tree().process_frame


func _wheel(at: Vector2, up: bool) -> void:
	await _move(at, 1)
	for pressed: bool in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		m.position = _win(at)
		m.global_position = m.position
		m.pressed = pressed
		m.factor = 1.0
		Input.parse_input_event(m)
		await get_tree().process_frame


func _keycode(kname: String) -> int:
	var named := {"Space": KEY_SPACE, "Tab": KEY_TAB, "Esc": KEY_ESCAPE, "Escape": KEY_ESCAPE, "Enter": KEY_ENTER, "Delete": KEY_DELETE,
		"PageUp": KEY_PAGEUP, "PageDown": KEY_PAGEDOWN, "Up": KEY_UP, "Down": KEY_DOWN, "Left": KEY_LEFT, "Right": KEY_RIGHT,
		"F1": KEY_F1, "F2": KEY_F2, "F3": KEY_F3, "F4": KEY_F4, "F6": KEY_F6, "F11": KEY_F11, ",": KEY_COMMA, ".": KEY_PERIOD, "/": KEY_SLASH}
	if named.has(kname):
		return named[kname]
	return OS.find_keycode_from_string(kname)


func _key(kname: String, shift: bool = false, ctrl: bool = false) -> void:
	var code := _keycode(kname)
	for pressed: bool in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		k.shift_pressed = shift
		k.ctrl_pressed = ctrl
		Input.parse_input_event(k)
		await get_tree().process_frame


func _hold(kname: String, secs: float) -> void:
	var code := _keycode(kname)
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = true
	Input.parse_input_event(k)
	await _sleep(secs)
	var k2 := k.duplicate() as InputEventKey
	k2.pressed = false
	Input.parse_input_event(k2)
	await get_tree().process_frame


# ------------------------------------------------------------------ 찾기
func _find_ctrl(text: String, nth: int, region: Variant) -> Control:
	var buttons: Array = []
	var labels: Array = []
	_collect(get_tree().root, text, buttons, labels, region)
	var pool := buttons if not buttons.is_empty() else labels
	return pool[nth] if nth < pool.size() else null


func _collect(n: Node, text: String, buttons: Array, labels: Array, region: Variant) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c: Control = n
		var t := ""
		if c is PcButton:
			t = (c as PcButton).label_text
		elif c is Button:
			t = (c as Button).text
			if t == "":
				t = _child_text(c)
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


## 글자 없는 Button(카드·띠 칸)은 안의 라벨 글자를 이어 붙인 것으로 찾는다.
func _child_text(n: Node) -> String:
	var out := ""
	for ch in n.get_children():
		if ch is Label:
			out += (ch as Label).text + " "
		elif ch is Control:
			out += _child_text(ch)
	return out


static func _plain(t: String) -> String:
	for z: String in ["​", "⁠", "‍", "﻿", " "]:
		t = t.replace(z, "" if z != " " else " ")
	return t


func _in_region(c: Control, region: Variant) -> bool:
	if not (region is Array) or region.size() < 4:
		return true
	var p := c.get_global_rect().get_center()
	return p.x >= float(region[0]) and p.y >= float(region[1]) and p.x <= float(region[2]) and p.y <= float(region[3])


func _dump(with_labels: bool = false) -> void:
	var b: Array = []
	var l: Array = []
	_collect(get_tree().root, "", b, l, null)
	var vs := get_viewport().get_visible_rect().size
	if with_labels:
		for c: Control in l:
			var r := c.get_global_rect()
			var flag := " <<잘림?" if r.end.x > vs.x + 0.5 or r.position.x < -0.5 or r.end.y > vs.y + 0.5 else ""
			print("  [lbl] '%s' %s%s" % [_plain((c as Label).text).replace("\n", "/").substr(0, 40), r, flag])
	for c2: Control in b:
		var t: String = _plain((c2 as PcButton).label_text if c2 is PcButton else ((c2 as Button).text if (c2 as Button).text != "" else _child_text(c2)))
		var r2 := c2.get_global_rect()
		var flag2 := " <<잘림?" if r2.end.x > vs.x + 0.5 or r2.end.y > vs.y + 0.5 else ""
		if t.strip_edges() != "":
			print("  [btn] '%s' %s%s" % [t.replace("\n", "/").substr(0, 40), r2, flag2])
