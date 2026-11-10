class_name Tutorial
extends Control
## Tutorial — data/ui/tutorial.json 을 한 단계씩 돌리는 진행기. 대본·순서는 전부 데이터.
## 단계: say / highlight / wait_cmd(cmd, match{인자}) / wait_event / wait_screen(screen) / camera / set(screens, build_only, open, close, paused, rain)
##
## 막히지 않게 하는 장치:
##  - 기다리는 단계(wait_cmd / wait_event)는 전부 timeout 이 있다(지나면 그냥 다음 단계).
##  - "건너뛰기"는 어느 단계에서든 보인다.
##  - 끝나거나 건너뛰면 멈춤·배속·동사 잠금·심기 제한·감상 시간을 반드시 되돌린다.
##
## 진행 저장: 시뮬이 query("tutorial") 을 Dictionary 로 주면 그쪽(cmd("tutorial",{step,done}))에,
##            아니면 user://ui_settings.cfg 에 도시 씨앗별로 둔다.

signal finished(skipped: bool)

var ui: Node = null                 # UIRoot
var dialog: DialogBox
var highlight: Highlight
var rain: RainOverlay
var running: bool = false
var _steps: Array = []
var _speakers: Dictionary = {}
var _i: int = -1
var _wait: Dictionary = {}          # 지금 기다리는 단계({}면 없음)
var _wait_t: float = 0.0
var _counts: Dictionary = {}        # 이벤트 이름 → 누적 횟수
var _mark: Dictionary = {}          # 직전 기다림이 끝났을 때의 _counts
var _last_args: Dictionary = {}     # 직전 wait_cmd 가 잡은 명령 인자
var _saved_speed: float = -1.0
var _use_sim_store: bool = false
var screens_on: Array = []          # 비면 전부 허용. ["none"] = 전부 잠금
var build_only: Array = []          # 비면 짓기 메뉴 전부. 아니면 이 id 들만 보인다


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rain = RainOverlay.new()
	add_child(rain)
	highlight = Highlight.new()
	add_child(highlight)
	dialog = DialogBox.new()
	add_child(dialog)
	set_process(false)


func _ready() -> void:
	dialog.advanced.connect(_next)
	dialog.skipped.connect(skip)
	Game.event.connect(_on_event)


# ------------------------------------------------------------------ 진행 저장
func _seed_key() -> String:
	var st: Variant = Game.state
	return str(st.rng_seed) if st != null else "0"


const DONE_STEP := 1000            # 시뮬 flags.tutorial 에 이 값 이상이면 끝난 것(건너뛰기 포함)


## 진행 저장(G11): 시뮬 cmd("tutorial",{step}) → hud.tutorial(int, 세이브에 들어간다). 세이브와 함께 움직이므로
## 다시 불러오면 그 단계부터, 다른 기기에서도 같다. hud 에 tutorial 이 없는 옛 시뮬이면 user://ui_settings.cfg(도시 씨앗별).
func _sim_step() -> Variant:
	var hud: Variant = Game.query("hud")
	if hud is Dictionary and (hud as Dictionary).has("tutorial"):
		return int(hud["tutorial"])
	return null


func is_done() -> bool:
	var st: Variant = _sim_step()
	if st != null:
		_use_sim_store = true
		if int(st) >= DONE_STEP:
			return true
		# 기록이 0인데 이미 며칠 지난 도시(오프닝 이전 세이브 등)면 본 것으로 친다
		var hud: Variant = Game.query("hud")
		if int(st) == 0 and hud is Dictionary and int(hud.get("day", 1)) > 1:
			return true
		return false
	_use_sim_store = false
	var rec: Variant = UISettings.get_value("tutorial", {})
	if rec is Dictionary and str(rec.get("seed", "")) == _seed_key():
		return bool(rec.get("done", false))
	var hud2: Variant = Game.query("hud")
	if hud2 is Dictionary and int(hud2.get("day", 1)) > 1:
		return true
	return false


func saved_step() -> int:
	if _use_sim_store:
		var st: Variant = _sim_step()
		return clampi(int(st), 0, DONE_STEP) if st != null else 0
	var rec: Variant = UISettings.get_value("tutorial", {})
	if rec is Dictionary and str(rec.get("seed", "")) == _seed_key():
		return int(rec.get("step", 0))
	return 0


func _save(done: bool) -> void:
	if _use_sim_store:
		Game.cmd("tutorial", {"step": DONE_STEP if done else maxi(_i, 0)})
	else:
		UISettings.set_value("tutorial", {"seed": _seed_key(), "step": maxi(_i, 0), "done": done})


# ------------------------------------------------------------------ 시작/끝
## from_step > 0 이면 그 앞의 set 단계만 조용히 다시 적용하고 이어서 한다.
func start(from_step: int = 0) -> void:
	is_done()          # 저장소(시뮬/설정 파일) 고르기
	var root: Variant = Data.file("tutorial")
	_steps = UI.to_array(root.get("steps", [])) if root is Dictionary else []
	_speakers = UI.to_dict(root.get("speakers", {})) if root is Dictionary else {}
	if _steps.is_empty():
		finished.emit(true)
		return
	running = true
	_counts.clear()
	_mark.clear()
	_last_args.clear()
	_wait = {}
	from_step = clampi(from_step, 0, _steps.size() - 1)
	for k in from_step:
		var s := UI.to_dict(_steps[k])
		if str(s.get("type", "")) == "set":
			_apply_set(s)
	_i = from_step - 1
	_next()


func skip() -> void:
	if not running:
		return
	_end(true)
	if ui != null:
		ui.toast("오프닝을 건너뛰었다. 기록 › 설정에서 다시 볼 수 있다.", "dim")


func _end(skipped: bool) -> void:
	running = false
	_wait = {}
	set_process(false)
	dialog.hide_box()
	highlight.clear()
	rain.set_rain(false)
	rain.show_stone(false)
	_restore_speed()
	Game.paused = false
	Q.vcall("set_time_override", [-1.0])
	screens_on = []
	build_only = []
	if ui != null:
		ui.nav.set_enabled(null)
	_i = _steps.size()
	_save(true)
	finished.emit(skipped)


# ------------------------------------------------------------------ 단계
func _next() -> void:
	if not running:
		return
	_wait = {}
	set_process(false)
	_restore_speed()
	_i += 1
	if _i >= _steps.size():
		_end(false)
		return
	_save(false)
	var s := UI.to_dict(_steps[_i])
	match str(s.get("type", "")):
		"say", "highlight":
			_say(s)
		"wait_cmd", "wait_event", "wait_screen":
			_begin_wait(s)
		"camera":
			_camera(s)
			_next()
		"set":
			_apply_set(s)
			_next()
		_:
			_next()     # 모르는 단계는 넘긴다(데이터가 앞서가도 죽지 않게)


func _say(s: Dictionary) -> void:
	var sp := UI.to_dict(_speakers.get(str(s.get("speaker", "")), {}))
	var text := str(s.get("text", ""))
	if s.get("text_by") is Dictionary:
		var tb: Dictionary = s["text_by"]
		var key := str(_last_args.get(str(tb.get("key", "")), ""))
		text = str(UI.to_dict(tb.get("map", {})).get(key, tb.get("default", text)))
	rain.show_stone(bool(s.get("stone", false)))
	var target := str(s.get("target", s.get("highlight", "")))
	if target != "" and ui != null:
		highlight.point_at(ui.target_rect.bind(target), str(s.get("type", "")) == "highlight")
	else:
		highlight.clear()
	dialog.at_top = ui != null and str(ui.screen) != ""
	dialog.say(str(sp.get("name", "")), _fill(text), str(sp.get("role", "")))


func _begin_wait(s: Dictionary) -> void:
	rain.show_stone(false)
	# 이미 해 둔 일이면(다시 불러온 도시, 순서를 앞질러 한 플레이어) 기다리지 않는다
	if str(s.get("type", "")) == "wait_cmd" and _already_done(s):
		_wait = s
		_complete_wait_at.call_deferred(_i)
		return
	_wait = s
	_wait_t = 0.0
	var target := str(s.get("highlight", ""))
	if target != "" and ui != null:
		highlight.point_at(ui.target_rect.bind(target), false)
	else:
		highlight.clear()
	dialog.hint(_fill(str(s.get("hint", ""))))
	if s.has("speed"):
		_saved_speed = Game.speed
		Game.speed = maxf(Game.speed, float(s["speed"]))
	set_process(true)
	# 이미 일어난 일이면(앞 대사를 읽는 사이) 바로 통과
	if str(s.get("type", "")) == "wait_event" and _event_seen(s):
		_complete_wait()


## wait_cmd 의 일이 이미 이뤄졌나(읽기만 한다 — 도시에 그 건물이 있나, 탐험대가 나가 있나).
func _already_done(s: Dictionary) -> bool:
	var st: Variant = Game.state
	if st == null:
		return false
	var want := str(s.get("cmd", ""))
	var m := UI.to_dict(s.get("match", {}))
	match want:
		"zone":
			for b: Variant in st.buildings.values():
				if b is Dictionary and str(b.get("kind", "")) == "house":
					return true
		"build":
			var t := str(m.get("type", ""))
			var need := maxi(1, int(m.get("min", 1)))   # "min": n — 그 시설이 n개 있어야 해 둔 것
			var have := 0
			for b2: Variant in st.buildings.values():
				if b2 is Dictionary and (t == "" or str(b2.get("type", "")) == t):
					if str(b2.get("kind", "")) != "house":
						have += 1
			# 공사 중(site)도 buildings 안에 type 을 달고 있다 → 위에서 함께 센다
			if have >= need:
				return true
		"expedition_send":
			for tm: Variant in st.teams:
				if tm is Dictionary and str(tm.get("state", "")) != "idle":
					return true
	return false


func _event_names(s: Dictionary) -> Array:
	var e: Variant = s.get("event", "")
	return e if e is Array else [str(e)]


func _event_seen(s: Dictionary) -> bool:
	for n in _event_names(s):
		if int(_counts.get(n, 0)) > int(_mark.get(n, 0)):
			return true
	return false


## 미뤄 부른 완료는 그 단계가 아직 지금 단계일 때만(같은 프레임에 이벤트가 여러 번 와도 한 단계만 넘어가게 —
## 통합: building_changed 가 한 프레임에 여러 번 와서 대사 두 개와 살피기 단계를 통째로 건너뛰던 것).
func _complete_wait_at(step: int) -> void:
	if step == _i and not _wait.is_empty():
		_complete_wait()


func _complete_wait(timed_out: bool = false) -> void:
	var s := _wait
	_wait = {}
	_mark = _counts.duplicate()
	if timed_out:
		_i += int(s.get("timeout_skip", 0))
	_next()


func _process(delta: float) -> void:
	if _wait.is_empty():
		return
	_wait_t += delta
	if str(_wait.get("type", "")) == "wait_screen" and ui != null and str(ui.screen) == str(_wait.get("screen", "")):
		_complete_wait()
		return
	if _wait_t >= float(_wait.get("timeout", 30.0 if str(_wait.get("type", "")) != "wait_cmd" else 120.0)):
		_complete_wait(true)


func _on_event(n: String, _payload: Dictionary) -> void:
	if not running:
		return
	_counts[n] = int(_counts.get(n, 0)) + 1
	if not _wait.is_empty() and str(_wait.get("type", "")) == "wait_event" and n in _event_names(_wait):
		_complete_wait_at.call_deferred(_i)


## UIRoot.cmd 가 성공한 명령마다 부른다.
func on_cmd(cmd_name: String, args: Dictionary, result: Dictionary) -> void:
	if not running or _wait.is_empty() or str(_wait.get("type", "")) != "wait_cmd":
		return
	if cmd_name != str(_wait.get("cmd", "")) or not bool(result.get("ok", false)):
		return
	var m := UI.to_dict(_wait.get("match", {}))
	for k: String in m:
		if k == "min":   # 개수 조건(_already_done 용) — 인자가 아니다
			continue
		if str(args.get(k, "")) != str(m[k]):
			return
	_last_args = args.duplicate()
	_complete_wait_at.call_deferred(_i)


func _camera(s: Dictionary) -> void:
	if s.has("zoom"):
		Q.vcall("set_zoom", [float(s["zoom"])])
	if s.has("floor_cut"):
		Q.vcall("set_floor_cut", [int(s["floor_cut"])])
		if ui != null:
			ui.rail.set_cut(int(s["floor_cut"]))
	if s.has("rotate"):
		Q.vcall("rotate_view", [int(s["rotate"])])
	if s.has("time"):
		Q.vcall("set_time_override", [float(s["time"])])
	var f: Variant = s.get("focus")
	if f is Array and f.size() >= 3:
		Q.vcall("focus_on", [Vector3i(int(f[0]), int(f[1]), int(f[2]))])     # 계약 밖: 있으면 쓴다


func _apply_set(s: Dictionary) -> void:
	if s.has("paused"):
		Game.paused = bool(s["paused"])
	if s.has("rain"):
		rain.set_rain(bool(s["rain"]))
	if s.has("screens"):
		screens_on = UI.to_array(s["screens"])
		if ui != null:
			ui.nav.set_enabled(null if screens_on.is_empty() else screens_on)
	if s.has("build_only"):
		build_only = UI.to_array(s["build_only"])
		if ui != null and str(ui.screen) == "build":
			ui.build.on_filter_changed()
	if s.has("open") and ui != null:
		ui.jump(UI.to_dict(s["open"]))
	if s.has("close") and ui != null:
		ui.close_screen()


func _restore_speed() -> void:
	if _saved_speed > 0.0:
		Game.speed = _saved_speed
		_saved_speed = -1.0


func _fill(text: String) -> String:
	var hud: Variant = Game.query("hud")
	var title := str(hud.get("title", "대장")) if hud is Dictionary else "대장"
	return text.replace("{title}", title)


## 화면 잠금(튜토리얼이 아직 안 가르친 화면).
func screen_allowed(id: String) -> bool:
	return screens_on.is_empty() or id in screens_on


func build_allowed(id: String) -> bool:
	return build_only.is_empty() or id in build_only


func build_allowed_cat(items: Array) -> bool:
	if build_only.is_empty():
		return true
	for it: Variant in items:
		if it is Dictionary and str(it.get("id", "")) in build_only:
			return true
	return false


## (테스트·스크린샷용) 지금 단계 번호.
func step_index() -> int:
	return _i
