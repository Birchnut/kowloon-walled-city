class_name RunPanel
extends Node
## 직접 줍기(미니게임)를 도시 위에 띄우고 거두는 곳 — UI 쪽 진입점 하나(통합 v4).
##  start(dest): can run_begin 으로 이유를 먼저 보이고(팀 없음·이미 줍는 중·모르는 곳·재고 바닥), 되면
##   expedition/RunSandbox.tscn 을 화면 전체로 띄운다(standalone=false). 도시는 ×1 로 계속 돈다.
##   그동안: 도시 화면(UI·뷰)은 숨기고 입력을 끈다, 도시 소리는 끈다(Sfx.duck_city), Esc 는 줍기의 멈춤 메뉴.
##  run_finished(result): 줍기 쪽 CityLink 가 결과 화면에서 이미 run_result 를 보냈다 → 도시 창고·팀·던전 재고를
##   확인해 결과 카드를 띄운다. 결과가 거절됐으면(배낭 한도·재고·id 불일치) 줄여서 한 번 더 보내 팀이 묶이지 않게 한다.
## 물건·목적지 id 맞추기는 RUN_IDS 한 곳(줍기 쪽 run_goods.json 의 city_id 가 맞으면 아무 일도 하지 않는다).

signal opened
signal closed_run(result: Dictionary)

const SCENE := "res://expedition/RunSandbox.tscn"
## 줍기 id → 도시(SIM v4) goods id. 줍기 쪽이 city_id 로 맞추기 전·후 모두 안전하도록 별칭까지 받는다.
const RUN_IDS := {"canned": "cans", "elec": "elec_scrap", "ewaste": "elec_scrap", "e_waste": "elec_scrap"}
## 도시 id → 줍기 id(던전 재고를 줍기에 넘길 때).
const CITY_TO_RUN := {"cans": "canned", "elec_scrap": "elec"}


## Game.cmd 의 run_begin/run_result 를 지날 때 id 를 맞춘다(core/Game.gd 가 부른다 — 통합 접착, 줍기 쪽 city_id 가 맞으면 하는 일 없음).
static func map_args(cmd_name: String, args: Dictionary) -> Dictionary:
	if cmd_name != "run_result" or not (args.get("loot") is Dictionary):
		return args
	var a := args.duplicate()
	var loot := {}
	for g: Variant in args["loot"]:
		var cid: String = RUN_IDS.get(str(g), str(g))
		loot[cid] = int(loot.get(cid, 0)) + int(args["loot"][g])
	a["loot"] = loot
	return a


static func map_result(cmd_name: String, r: Dictionary) -> Dictionary:
	if cmd_name != "run_begin" or not (r.get("stock") is Dictionary):
		return r
	var st := {}
	for g: Variant in r["stock"]:
		var rid: String = CITY_TO_RUN.get(str(g), str(g))
		st[rid] = int(st.get(rid, 0)) + int(r["stock"][g])
	r["stock"] = st
	return r

var ui: Node = null
var run: Node = null
var layer: CanvasLayer = null
var dest: String = ""
var _prev_speed: float = 1.0
var _prev_paused: bool = false
var _money0: float = 0.0
var _stock0: Dictionary = {}


func is_open() -> bool:
	return run != null and is_instance_valid(run)


## 직접 줍기를 열 수 있나: {ok, reason}. 이유는 사람이 읽는 문장.
static func check(dest_id: String) -> Dictionary:
	if not ResourceLoader.exists(SCENE):
		return {"ok": false, "reason": "직접 줍기 화면이 이 빌드에 없다."}
	var c := Q.can_full("run_begin", {"dest": dest_id})
	if not bool(c.get("ok", false)):
		return c
	for d: Variant in UI.to_array(Q.dict("expeditions").get("dests", [])):
		var dd := UI.to_dict(d)
		if str(dd.get("id", "")) == dest_id and float(dd.get("stock_pct", 1.0)) <= 0.02:
			return {"ok": false, "reason": "%s은(는) 다 털렸다 — 게임 시간이 지나면 다시 찬다." % str(dd.get("name", dest_id))}
	return {"ok": true, "reason": ""}


func start(dest_id: String) -> bool:
	if is_open():
		ui.toast("이미 직접 줍는 중이다.", "warn")
		return false
	var c := check(dest_id)
	if not bool(c.get("ok", false)):
		ui.toast(str(c.get("reason", "지금은 들어갈 수 없다.")), "warn", "expedition")
		return false
	dest = dest_id
	_money0 = float(Game.state.money) if Game.state != null else 0.0
	_stock0 = (Game.state.stock as Dictionary).duplicate() if Game.state != null else {}
	_prev_speed = Game.speed
	_prev_paused = Game.paused
	Game.set_speed(1.0)
	Game.set_paused(false)
	ui.close_all_windows()
	ui.place.cancel()
	var ps: PackedScene = load(SCENE)
	run = ps.instantiate()
	run.set("dest", dest_id)
	run.set("standalone", false)
	run.connect("run_finished", _on_finished)
	# 줍기의 HUD·메뉴는 CanvasLayer 5·6 — 그 아래(2)에 화면을 깐다. 도시 UI·뷰(0층)는 숨긴다.
	layer = CanvasLayer.new()
	layer.layer = 2
	layer.name = "RunLayer"
	ui.get_parent().add_child(layer)
	layer.add_child(run)
	_after_ready.call_deferred()
	_set_city_visible(false)
	Sfx.duck_city(true)
	opened.emit()
	return true


## 줍기 장면은 _ready 에서 명령줄 인자(-- 뒤)를 읽는다. 도시를 몰던 인자(script=·speed=)가 줍기를 대본·배속으로
## 돌리지 않게 되돌린다(줍기에 넘길 것: standalone=false 면 인자를 읽지 말 것). run_auto=<성격> 이면 자동 플레이(하네스용).
func _after_ready() -> void:
	if not is_open():
		return
	var a: Dictionary = run.get("args") if run.get("args") is Dictionary else {}
	if a.has("script") and run.get("script_player") != null:
		run.set("script_player", null)
	if a.has("speed"):
		run.set("speed", 1.0)
	var auto := ""
	for s: String in OS.get_cmdline_user_args():
		if s.begins_with("run_auto="):
			auto = s.substr(9)
	if auto != "":
		var bot: Object = load("res://expedition/AutoPlayer.gd").new()
		bot.call("setup", auto, int(UI.to_dict(run.get("begin")).get("seed", 1)))
		run.set("bot", bot)
		run.set("auto_profile", auto)
	elif a.has("auto"):
		run.set("bot", null)
		run.set("auto_profile", "")


## 결과 화면의 "한 판 더"(R)는 run_begin 없이 새 판을 연다 — 도시에 다시 알린다(팀·던전 재고). 안 되면 다음 결과는
## _on_finished 의 안전망이 줄여 보낸다.
var _last_mode := ""


func _process(_dt: float) -> void:
	if not is_open():
		return
	var m := str(run.get("mode"))
	if m == "run" and _last_mode == "result" and Game.state != null and (Game.state.flags.get("run", {}) as Dictionary).is_empty():
		var r: Dictionary = Game.cmd("run_begin", {"dest": dest})
		if not bool(r.get("ok", false)):
			push_warning("[RunPanel] 한 판 더: " + str(r.get("reason", "")))
	_last_mode = m


func _set_city_visible(on: bool) -> void:
	var v := Q.view()
	if v != null:
		(v as CanvasItem).visible = on     # 숨기면 도시 3D 화면을 그리지 않는다(시뮬은 Game 이 계속 돌린다)
		Q.vcall("set_input_enabled", [on])
	(ui as CanvasItem).visible = on


func _on_finished(result: Dictionary) -> void:
	var r := result.duplicate(true)
	# CityLink 가 결과 화면에서 이미 run_result 를 보냈다. 거절됐으면(flags.run 이 남음) 줄여서 다시 보낸다.
	var still := Game.state != null and not (Game.state.flags.get("run", {}) as Dictionary).is_empty()
	var fixed_note := ""
	if still:
		fixed_note = _resend(r)
	_close()
	_report(r, fixed_note)
	closed_run.emit(r)


## 받아들여질 만큼으로 줄여 run_result 를 다시 보낸다(도시 id 로 바꾸고, 던전 재고·배낭 한도 안으로). 남긴 것을 문장으로.
func _resend(r: Dictionary) -> String:
	var loot := {}
	for g: Variant in UI.to_dict(r.get("loot", {})):
		var cid: String = RUN_IDS.get(str(g), str(g))
		loot[cid] = int(loot.get(cid, 0)) + int(UI.to_dict(r.get("loot", {}))[g])
	var st: Dictionary = Game.state.dests.get(dest, {}).get("stock", {})
	var dropped := 0
	for g: String in loot.keys():
		var cap := int(floorf(float(st.get(g, 0.0)) + 1e-6))
		if not st.has(g):
			cap = 0
		if int(loot[g]) > cap:
			dropped += int(loot[g]) - cap
			loot[g] = cap
		if int(loot[g]) <= 0:
			loot.erase(g)
	var args := {"dest": dest, "loot": loot, "outcome": str(r.get("outcome", "exit")), "finds": r.get("finds", [])}
	var res: Dictionary = Game.cmd("run_result", args)
	if not bool(res.get("ok", false)) and str(res.get("code", "")) == "carry":
		# 배낭 한도: 많은 것부터 깎는다
		var carry := 0
		var m := str(res.get("reason", "")).split(" ")
		for w: String in m:
			if w.trim_suffix("칸을").is_valid_int():
				carry = int(w.trim_suffix("칸을"))
		var total := 0
		for g2: String in loot:
			total += int(loot[g2])
		while carry > 0 and total > carry:
			var big := ""
			for g3: String in loot:
				if big == "" or int(loot[g3]) > int(loot[big]):
					big = g3
			loot[big] = int(loot[big]) - 1
			total -= 1
			dropped += 1
		args["loot"] = loot
		res = Game.cmd("run_result", args)
	if not bool(res.get("ok", false)):
		# 마지막 안전망: 빈손으로라도 팀을 풀어 준다
		args["loot"] = {}
		res = Game.cmd("run_result", args)
		return "도시가 짐을 받지 못했다(%s) — 팀만 돌아왔다." % str(res.get("reason", ""))
	return "배낭·던전 한도를 넘은 %d개는 두고 왔다." % dropped if dropped > 0 else ""


func _close() -> void:
	if is_open():
		run.queue_free()
	run = null
	if layer != null and is_instance_valid(layer):
		layer.queue_free()
	layer = null
	_set_city_visible(true)
	Sfx.duck_city(false)
	Game.set_speed(_prev_speed)
	Game.set_paused(_prev_paused)
	ui.refresh_soon()


func _report(r: Dictionary, note: String) -> void:
	var oc := str(r.get("outcome", "exit"))
	var got: Array = []
	if Game.state != null:
		var names: Dictionary = ui.good_names()
		for g: Variant in Game.state.stock:
			var d := float(Game.state.stock[g]) - float(_stock0.get(g, 0.0))
			if d >= 0.5:
				got.append("%s +%s" % [str(names.get(g, g)), UI.num(roundf(d))])
	var title: String = {"boss": "두목을 쓰러뜨리고 나왔다", "exit": "무사히 빠져나왔다", "down": "쓰러져 실려 나왔다"}.get(oc, "돌아왔다")
	var body := ("창고에 들어온 것: " + " · ".join(got)) if not got.is_empty() else "건진 것이 없다."
	var lost := UI.to_dict(r.get("lost", {}))
	if oc == "down" and not lost.is_empty():
		body += "\n잃은 것 %d개(쓰러지면 절반)." % _sum(lost)
	if note != "":
		body += "\n" + note
	body += "\n탐험대가 다시 쉬는 중이다. 털린 만큼 던전 재고가 줄었다(게임 시간이 지나면 다시 찬다)."
	ui.toasts.card({"kicker": "직접 줍기 — " + _dest_name(), "title": title, "body": body,
		"tone": "jade" if oc != "down" else "red", "picto": "expedition", "life": 7.0})
	Sfx.play("expedition")


func _sum(d: Dictionary) -> int:
	var n := 0
	for k: Variant in d:
		n += int(d[k])
	return n


func _dest_name() -> String:
	for d: Variant in UI.to_array(Q.dict("expeditions").get("dests", [])):
		if str(UI.to_dict(d).get("id", "")) == dest:
			return str(UI.to_dict(d).get("name", dest))
	return dest
