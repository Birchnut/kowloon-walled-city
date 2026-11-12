extends Node
## AudioDirector — Sfx 오토로드가 자식으로 만드는 소리 담당 노드.
## - 버스: Master → SFX · Ambience(+ AmbL · AmbR 좌우) · Music. 없으면 실행 중에 만든다(project.godot 를 건드리지 않는다).
## - 만들기: 효과음 → 배경 루프 → 배경 한 번짜리 → 악기 → 바탕 화음 순서로, 프레임마다 BUDGET_MS 만큼만(웹 끊김 방지).
##   아직 안 만든 효과음을 부르면 그 자리에서 만든다(한 번, 수 ms).
## - 효과음: 목소리 SFX_VOICES 개, 같은 이름은 SPEC 간격 안에 다시 안 울림, 이름당 동시 3개, 변주 돌려 쓰기 + 음높이 살짝 흔들기.
## - 배경: 게임 상태(시각·인구·공사장·불·확대·배속·멈춤)를 0.5초마다 읽어 층별 목표 크기를 정하고 천천히 따라간다.
## - 음악: 분위기(낮·저녁·밤·불)에 맞춰 씨앗 구절을 띄엄띄엄. 실제 시간 기준(배속과 무관).
## - 설정: user://audio.cfg (nosave 실행이면 메모리만).
## 규칙: 게임 상태는 읽기만 한다(Game.state, Game.view 를 덕 타이핑으로). 명령은 보내지 않는다.

const S := preload("res://audio/Synth.gd")
const SB := preload("res://audio/SfxBank.gd")
const AB := preload("res://audio/AmbienceBank.gd")
const MB := preload("res://audio/MusicBank.gd")

const CFG_PATH := "user://audio.cfg"
const BUS_NAMES := {"master": "Master", "sfx": "SFX", "ambience": "Ambience", "music": "Music"}
const DEFAULT_VOL := {"master": 0.9, "sfx": 0.85, "ambience": 0.7, "music": 0.4}
const SFX_VOICES := 12
const AMB_VOICES := 3
const MUS_VOICES := 8
const BUDGET_MS := 4.0
const FREQUENT := ["click", "hover", "window_open", "window_close", "tab", "zone", "build", "place_fail", "rotate", "speed"]

## 배경 층 → 기본 dB(재생 크기), 따라가는 시간(초)
const LAYERS := {
	"hum": [-7.0, 2.5], "wind": [-11.0, 2.5], "murmur": [-8.0, 2.5], "market": [-11.0, 2.5],
	"crickets": [-16.0, 3.0], "fire": [-7.0, 1.0], "rain": [-9.0, 2.0],
}
const PAUSE_DUCK_DB := -9.0
const MUSIC_PAUSE_DUCK_DB := -5.0

## 사건 → 효과음(UI 가 부르지 않는 것만). UI 가 나중에 직접 부르게 되면 auto_event_sfx = false.
const EVENT_SFX := {
	"construction_done": "construction_done", "research_done": "research_done", "milestone": "tier_up",
	"fire_out": "fire_out", "repair_done": "repair_done", "repaired": "repair_done", "house_repaired": "repair_done",
}

var auto_event_sfx := true
var vol: Dictionary = DEFAULT_VOL.duplicate()
var master_muted := false
var sfx_muted := false
var music_on := true
var ambience_on := true
var rain := 0.0
var mem_only := false

# 만든 것
var sfx: Dictionary = {}      # 이름 → Array[AudioStreamWAV]
var shots: Dictionary = {}    # 배경 한 번짜리 이름 → Array[AudioStreamWAV]
var loops: Dictionary = {}    # 층 이름 → AudioStreamWAV
var insts: Dictionary = {}    # 악기 → AudioStreamWAV
var pads: Dictionary = {}     # 바탕 화음 → AudioStreamWAV
var build_us: Dictionary = {} # 작업 이름 → 걸린 µs
var build_total_us := 0
var build_frames := 0
var build_done := false

var _rng := RandomNumberGenerator.new()
var _sfx_pool: Array = []
var _amb_pool: Array = []
var _mus_pool: Array = []
var _pad_players: Array = []
var _pad_cur := ""
var _pad_slot := 0
var _pad_tw: Array = []
var _bus_last: Dictionary = {}
var _last_play: Dictionary = {}
var _var_idx: Dictionary = {}
var _layer_p: Dictionary = {}     # 층 → AudioStreamPlayer
var _layer_g: Dictionary = {}     # 층 → 지금 크기(0..1)
var _layer_tgt: Dictionary = {}   # 층 → 목표 크기
var _layer_quiet: Dictionary = {} # 층 → 조용히 지난 초
var _started := false             # 배경·음악 시작(웹은 첫 입력 뒤)
var _amb_fade := 0.0
var _duck_db := 0.0
var _mduck_db := 0.0
var _state_t := 0.0
var _shot_t := 0.0
var _last_shot_ms := -100000
var st: Dictionary = {"tod": 0.4, "pop": 0, "sites": 0, "fires": 0, "zoom_out": 0.5, "speed": 1.0, "paused": false}
var w: Dictionary = {}            # 시간대 가중치(디버그·샌드박스에 보임)
var _fires_ev := 0
var _tod_override := -1.0
var _mood := "day"
var _notes: Array = []            # [시각 ms, 악기, 반음, 세기, 분위기]
var _next_phrase_ms := 0
var _phrase_n := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20261113
	mem_only = "nosave" in OS.get_cmdline_user_args() or OS.get_environment("KOWLOON_NOSAVE") == "1"
	_load_cfg()
	_ensure_buses()
	_apply_volumes()
	for i in SFX_VOICES:
		_sfx_pool.append(_player("SFX"))
	for i in AMB_VOICES:
		_amb_pool.append(_player("Ambience"))
	for i in MUS_VOICES:
		_mus_pool.append(_player("Music"))
	for i in 2:
		_pad_players.append(_player("Music"))
	for l: String in LAYERS:
		_layer_g[l] = 0.0
		_layer_tgt[l] = 0.0
		_layer_quiet[l] = 0.0
	var g := get_node_or_null("/root/Game")
	if g != null:
		if g.has_signal("event"):
			g.event.connect(_on_game_event)
		if g.has_signal("state_replaced"):
			g.state_replaced.connect(func() -> void: _fires_ev = 0)
	# 웹: 브라우저는 첫 입력 뒤에야 소리를 낸다 → 배경·음악은 첫 입력에 시작. 데스크톱은 바로.
	if not OS.has_feature("web"):
		_started = true
	_next_phrase_ms = Time.get_ticks_msec() + 5000
	_build_all.call_deferred()


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


func _input(ev: InputEvent) -> void:
	if _started:
		return
	if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventKey and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
		_started = true
		_next_phrase_ms = Time.get_ticks_msec() + 4000


# ------------------------------------------------------------------ 버스 · 설정

func _ensure_buses() -> void:
	for b: String in ["SFX", "Ambience", "Music"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	for side: Array in [["AmbL", -0.55], ["AmbR", 0.55]]:
		if AudioServer.get_bus_index(side[0]) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, side[0])
			AudioServer.set_bus_send(i, "Ambience")
			var pan := AudioEffectPanner.new()
			pan.pan = float(side[1])
			AudioServer.add_bus_effect(i, pan)
	# 마지막 안전망: 주 버스 봉우리 제한(웹 '표본 재생'에서는 효과가 빠지니 각 소리 크기를 낮게 잡아 둔다)
	var mi := AudioServer.get_bus_index("Master")
	var has_lim := false
	for k in AudioServer.get_bus_effect_count(mi):
		if AudioServer.get_bus_effect(mi, k) is AudioEffectHardLimiter:
			has_lim = true
	if not has_lim:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(mi, lim)


func _bus_key(bus: String) -> String:
	var k := bus.to_lower()
	if k == "amb" or k == "ambient":
		k = "ambience"
	return k if BUS_NAMES.has(k) else ""


func set_volume(bus: String, v: float) -> void:
	var k := _bus_key(bus)
	if k == "":
		push_warning("Sfx.set_volume: 모르는 버스 %s" % bus)
		return
	vol[k] = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_cfg()


func get_volume(bus: String) -> float:
	var k := _bus_key(bus)
	return float(vol.get(k, 0.0))


func mute(on: bool) -> void:
	master_muted = on
	_apply_volumes()
	_save_cfg()


func set_sfx_muted(on: bool) -> void:
	sfx_muted = on
	_apply_volumes()
	_save_cfg()


func set_music_enabled(on: bool) -> void:
	music_on = on
	if not on:
		for p: AudioStreamPlayer in _mus_pool + _pad_players:
			p.stop()
		_pad_cur = ""
		_notes.clear()
	_apply_volumes()
	_save_cfg()


func set_ambience_enabled(on: bool) -> void:
	ambience_on = on
	_apply_volumes()
	_save_cfg()


func _apply_volumes() -> void:
	for k: String in BUS_NAMES:
		var i := AudioServer.get_bus_index(BUS_NAMES[k])
		if i < 0:
			continue
		var v := float(vol.get(k, 1.0))
		var off := v <= 0.001
		if k == "master":
			off = off or master_muted
		elif k == "sfx":
			off = off or sfx_muted
		elif k == "music":
			off = off or not music_on
		elif k == "ambience":
			off = off or not ambience_on
		var extra := 0.0
		if k == "ambience":
			extra = _duck_db
		elif k == "music":
			extra = _mduck_db
		var db := linear_to_db(maxf(v, 0.001)) + extra
		# 바뀐 때만 건드린다(웹 '표본 재생'에서는 버스 값이 바뀔 때마다 브라우저 쪽으로 넘어간다)
		var last: Array = _bus_last.get(k, [null, 999.0])
		if last[0] != off:
			AudioServer.set_bus_mute(i, off)
			last[0] = off
		if absf(float(last[1]) - db) > 0.05:
			AudioServer.set_bus_volume_db(i, db)
			last[1] = db
		_bus_last[k] = last


func _load_cfg() -> void:
	if mem_only:
		return
	var c := ConfigFile.new()
	if c.load(CFG_PATH) != OK:
		return
	for k: String in DEFAULT_VOL:
		vol[k] = clampf(float(c.get_value("audio", k, DEFAULT_VOL[k])), 0.0, 1.0)
	master_muted = bool(c.get_value("audio", "muted", false))
	sfx_muted = bool(c.get_value("audio", "sfx_muted", false))
	music_on = bool(c.get_value("audio", "music_on", true))
	ambience_on = bool(c.get_value("audio", "ambience_on", true))


func _save_cfg() -> void:
	if mem_only:
		return
	var c := ConfigFile.new()
	for k: String in vol:
		c.set_value("audio", k, vol[k])
	c.set_value("audio", "muted", master_muted)
	c.set_value("audio", "sfx_muted", sfx_muted)
	c.set_value("audio", "music_on", music_on)
	c.set_value("audio", "ambience_on", ambience_on)
	c.save(CFG_PATH)


# ------------------------------------------------------------------ 만들기

func _build_all() -> void:
	var bud := AB.Budget.new()
	bud.ms = BUDGET_MS
	bud.tree = get_tree()
	bud.start()
	await build_everything(bud)
	build_frames = bud.frames
	build_done = true


## 모든 소리를 만든다. bud.tree 가 없으면 쉬지 않고 한 번에(헤드리스 검사).
func build_everything(bud: AB.Budget) -> void:
	# 자주 쓰는 효과음 → 배경 바닥 루프(배경이 빨리 시작하게) → 나머지 효과음 → …
	for n: String in FREQUENT:
		if not sfx.has(n):
			await _build_sfx(n, bud)
	for l: String in ["hum", "wind", "murmur", "crickets", "market"]:
		await _build_loop(l, bud)
	for n: String in SB.names():
		if not sfx.has(n):
			await _build_sfx(n, bud)
	for n: String in AB.SHOTS:
		var b0 := bud.busy_now()
		var arr: Array = []
		for v in int(AB.SHOTS[n][0]):
			arr.append(S.to_wav(AB.build_shot(n, v), false, 0, AB.SHOT_RATE))
			if bud.over():
				await bud.wait()
		shots[n] = arr
		_note("shot:" + n, bud.busy_now() - b0)
	for i: String in MB.INSTS:
		var b0 := bud.busy_now()
		insts[i] = S.to_wav(MB.build_inst(i))
		_note("inst:" + i, bud.busy_now() - b0)
		if bud.over():
			await bud.wait()
	for l: String in ["fire", "rain"]:
		await _build_loop(l, bud)
	for p: String in MB.PADS:
		var b0 := bud.busy_now()
		var b: PackedFloat32Array = await MB.build_pad(p, bud)
		pads[p] = S.to_wav(b, true, 0, 11025)
		_note("pad:" + p, bud.busy_now() - b0)
		if bud.over():
			await bud.wait()


func _note(n: String, us: int) -> void:
	build_us[n] = us
	build_total_us += us


func _build_loop(l: String, bud: AB.Budget) -> void:
	var b0 := bud.busy_now()
	var b: PackedFloat32Array = await AB.build_loop(l, bud)
	loops[l] = S.to_wav(b, true, AB.loop_stereo(l), AB.loop_rate(l))
	_note("loop:" + l, bud.busy_now() - b0)
	if bud.over():
		await bud.wait()


## bud 가 있으면 무거운 조리법 중간에 프레임을 넘긴다. 없으면(play 에서 아직 안 만든 이름) 그 자리에서 한 번에.
func _build_sfx(n: String, bud: AB.Budget = null) -> void:
	var t0 := Time.get_ticks_usec()
	var b0 := bud.busy_now() if bud != null else 0
	var arr: Array = []
	for v in SB.variants(n):
		var b: PackedFloat32Array = await SB.build(n, v, bud)
		arr.append(S.to_wav(b, false, 0, SB.rate(n)))
		if bud != null and bud.over():
			await bud.wait()
	sfx[n] = arr
	_note("sfx:" + n, (bud.busy_now() - b0) if bud != null else Time.get_ticks_usec() - t0)


# ------------------------------------------------------------------ 효과음

func play(n: String, volume: float = 1.0) -> void:
	if sfx_muted or master_muted or not SB.SPEC.has(n):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(n, -100000)) < int(SB.min_gap(n) * 1000.0):
		return
	var same := 0
	for p: AudioStreamPlayer in _sfx_pool:
		if p.playing and p.get_meta("sfx", "") == n:
			same += 1
	if same >= 3:
		return
	if not sfx.has(n):
		_build_sfx(n)
	var arr: Array = sfx[n]
	if arr.is_empty():
		return
	_last_play[n] = now
	var vi := 0
	if arr.size() > 1:
		vi = (int(_var_idx.get(n, 0)) + 1 + _rng.randi() % (arr.size() - 1)) % arr.size()
	_var_idx[n] = vi
	var pl := _free_player(_sfx_pool)
	pl.stream = arr[vi]
	pl.set_meta("sfx", n)
	pl.volume_db = SB.gain_db(n) + linear_to_db(maxf(volume, 0.001))
	var j := SB.pitch_jitter(n)
	pl.pitch_scale = 1.0 + (_rng.randf_range(-j, j) if j > 0.0 else 0.0)
	pl.play()


func _free_player(pool: Array) -> AudioStreamPlayer:
	var oldest: AudioStreamPlayer = pool[0]
	var oldest_t := 1 << 62
	for p: AudioStreamPlayer in pool:
		if not p.playing:
			p.set_meta("t", Time.get_ticks_msec())
			return p
		var t := int(p.get_meta("t", 0))
		if t < oldest_t:
			oldest_t = t
			oldest = p
	oldest.stop()
	oldest.set_meta("t", Time.get_ticks_msec())
	return oldest


func _on_game_event(n: String, p: Dictionary) -> void:
	match n:
		"fire_started":
			_fires_ev += 1
		"fire_out":
			_fires_ev = maxi(0, _fires_ev - 1)
		"contract_done":
			if auto_event_sfx and bool(p.get("ok", true)):
				play("contract_done")
			return
	if auto_event_sfx and EVENT_SFX.has(n):
		play(EVENT_SFX[n])


# ------------------------------------------------------------------ 배경: 상태 읽기

func set_tod_override(t: float) -> void:
	_tod_override = t


func set_state_override(d: Dictionary) -> void:
	set_meta("st_override", d)


func _read_state() -> void:
	var g := get_node_or_null("/root/Game")
	var ov: Dictionary = get_meta("st_override", {})
	if g != null:
		st["speed"] = float(g.get("speed")) if g.get("speed") != null else 1.0
		st["paused"] = bool(g.get("paused")) if g.get("paused") != null else false
		var v: Variant = g.get("view")
		var tod := -1.0
		if v is Object and is_instance_valid(v):
			if v.has_method("tod"):
				tod = float(v.tod())
			var zi: Variant = v.get("zoom_i")
			var zl: Variant = v.get("_zoom_levels")
			if zi != null and zl is Array and (zl as Array).size() > 1:
				st["zoom_out"] = 1.0 - float(zi) / float((zl as Array).size() - 1)
		var s: Variant = g.get("state")
		if tod < 0.0 and s != null and g.has_method("time_of_day"):
			tod = float(g.time_of_day())
		if tod >= 0.0:
			st["tod"] = tod
		if s is Object and s.get("buildings") is Dictionary:
			var pop := 0
			var sites := 0
			var burning := 0
			for b: Variant in (s.get("buildings") as Dictionary).values():
				if not (b is Dictionary):
					continue
				var kind := str(b.get("kind", ""))
				if kind == "house":
					pop += int(b.get("residents", 0))
				elif kind == "site":
					sites += 1
				if bool(b.get("burning", false)) or float(b.get("fire", 0.0)) > 0.0:
					burning += 1
			st["pop"] = pop
			st["sites"] = sites
			st["fires"] = maxi(burning, _fires_ev)
	if _tod_override >= 0.0:
		st["tod"] = _tod_override
	for k: String in ov:
		st[k] = ov[k]
	_weights()


static func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


func _weights() -> void:
	var h := fposmod(float(st["tod"]), 1.0) * 24.0
	var day := _ss(5.5, 7.5, h) * (1.0 - _ss(17.5, 19.5, h))
	var night := maxf(1.0 - _ss(4.5, 6.5, h), _ss(19.0, 21.0, h))
	var evening := _ss(15.5, 17.0, h) * (1.0 - _ss(19.0, 20.5, h))
	var morning := _ss(6.0, 7.5, h) * (1.0 - _ss(8.5, 10.0, h))
	var deep := _ss(0.5, 1.5, h) * (1.0 - _ss(4.0, 5.5, h))   # 새벽 1~5시
	var pop := float(st["pop"])
	var cs := pop / (pop + 250.0)
	w = {"h": h, "day": day, "night": night, "evening": evening, "morning": morning, "deep": deep, "cs": cs,
		"awake": 1.0 - 0.8 * deep, "zoom_out": float(st["zoom_out"])}


func _layer_targets() -> void:
	var cs: float = w["cs"]
	var zo: float = w["zoom_out"]
	var t := {}
	t["hum"] = (0.45 + 0.55 * cs) * (1.0 - 0.25 * float(w["deep"]))
	t["wind"] = clampf(0.3 + 0.6 * zo + 0.15 * float(w["night"]), 0.0, 1.0)
	t["murmur"] = clampf(cs * float(w["awake"]) * (0.65 + 0.5 * float(w["evening"]) + 0.15 * float(w["morning"])) * (0.8 + 0.35 * (1.0 - zo)), 0.0, 1.0)
	t["market"] = clampf(cs * (float(w["evening"]) + 0.35 * float(w["morning"])) * (0.75 + 0.35 * (1.0 - zo)), 0.0, 1.0)
	t["crickets"] = float(w["night"]) * (1.0 - 0.45 * cs)
	var f := int(st["fires"])
	t["fire"] = 0.0 if f <= 0 else minf(1.0, 0.6 + 0.2 * float(f))
	t["rain"] = rain
	_layer_tgt = t


# ------------------------------------------------------------------ 배경: 매 프레임

func _process(dt: float) -> void:
	_state_t -= dt
	if _state_t <= 0.0:
		_state_t = 0.5
		_read_state()
		_layer_targets()
	var paused: bool = st["paused"]
	var want_duck := PAUSE_DUCK_DB if paused else 0.0
	var want_mduck := MUSIC_PAUSE_DUCK_DB if paused else 0.0
	var k := minf(1.0, dt / 0.6)
	_duck_db += (want_duck - _duck_db) * k
	_mduck_db += (want_mduck - _mduck_db) * k
	_apply_volumes()
	if not _started:
		return
	_amb_fade = minf(1.0, _amb_fade + dt / 4.0)
	_mix_layers(dt)
	_shot_t -= dt
	if _shot_t <= 0.0:
		_shot_t = 0.25
		_schedule_shots(0.25)
	_music_tick()


func _mix_layers(dt: float) -> void:
	for l: String in LAYERS:
		if not loops.has(l):
			continue
		var tgt: float = float(_layer_tgt.get(l, 0.0)) * _amb_fade
		var g: float = _layer_g[l]
		g += (tgt - g) * minf(1.0, dt / float(LAYERS[l][1]))
		_layer_g[l] = g
		var p: AudioStreamPlayer = _layer_p.get(l)
		if p == null:
			p = _player("Ambience")
			p.stream = loops[l]
			_layer_p[l] = p
		if g < 0.003:
			_layer_quiet[l] = float(_layer_quiet[l]) + dt
			if p.playing and float(_layer_quiet[l]) > 2.0:
				p.stop()
			p.volume_db = -80.0
			continue
		_layer_quiet[l] = 0.0
		var db := float(LAYERS[l][0]) + linear_to_db(g)
		if absf(p.volume_db - db) > 0.05:
			p.volume_db = db
		if not p.playing:
			var ln: float = p.stream.get_length()
			p.play(_rng.randf_range(0.0, ln * 0.95))


## 한 번짜리 사건들의 분당 빈도(× 배속 기운, 멈춤이면 거의 없음).
func shot_rates() -> Dictionary:
	if w.is_empty():
		return {}
	var cs: float = w["cs"]
	var day: float = w["day"]
	var night: float = w["night"]
	var eve: float = w["evening"]
	var mor: float = w["morning"]
	var deep: float = w["deep"]
	var sites := float(mini(int(st["sites"]), 3)) / 3.0
	var r := {
		"bird": 5.0 * day * (1.0 - 0.4 * cs),
		"pigeon": 1.5 * (0.8 * day + 0.2 * eve),
		"dog": 0.7 * (0.3 + 0.7 * cs) * (0.5 + 0.5 * night),
		"bell": 1.0 * cs * minf(1.0, day + eve) * 0.9,
		"kettle": 0.35 * cs * (mor + eve),
		"mahjong": 1.2 * cs * (0.6 * eve + 0.8 * night) * (1.0 - 0.6 * deep),
		"radio": 0.5 * cs * (eve + 0.6 * night) * (1.0 - 0.7 * deep),
		"hammer": 3.0 * sites * (0.4 + 0.6 * day),
		"horn": 0.25 * (0.4 + 0.6 * night),
		"drip": 2.0 * night * (0.3 + 0.7 * cs),
		"wok": 1.5 * cs * (eve + 0.5 * mor + 0.3 * day),
		"shutter": 0.4 * cs * (mor + _ss(20.5, 21.5, float(w["h"])) * (1.0 - _ss(23.0, 23.9, float(w["h"])))),
	}
	var spd: float = maxf(1.0, float(st["speed"]))
	var mult := clampf(1.0 + 0.25 * log(spd) / log(2.0), 1.0, 1.6)
	if bool(st["paused"]):
		mult = 0.15
	for n: String in r:
		r[n] = float(r[n]) * mult
	return r


func _schedule_shots(dt: float) -> void:
	if not ambience_on or master_muted:
		return
	var now := Time.get_ticks_msec()
	if now - _last_shot_ms < 1200:
		return
	var r := shot_rates()
	for n: String in r:
		if not shots.has(n):
			continue
		var p := float(r[n]) / 60.0 * dt
		if _rng.randf() < p:
			play_shot(n)
			return


func play_shot(n: String, gain_db: float = 0.0) -> void:
	if not shots.has(n):
		return
	var arr: Array = shots[n]
	_last_shot_ms = Time.get_ticks_msec()
	var pl := _free_player(_amb_pool)
	pl.stream = arr[_rng.randi() % arr.size()]
	pl.bus = ["Ambience", "AmbL", "AmbR"][_rng.randi() % 3]
	pl.volume_db = float(AB.SHOTS[n][1]) + _rng.randf_range(-4.0, 0.0) + gain_db + linear_to_db(maxf(_amb_fade, 0.01))
	pl.pitch_scale = _rng.randf_range(0.9, 1.1) if n == "bird" else _rng.randf_range(0.96, 1.04)
	pl.play()


# ------------------------------------------------------------------ 음악

func mood_now() -> String:
	if int(st["fires"]) > 0:
		return "alarm"
	var h := fposmod(float(st["tod"]), 1.0) * 24.0
	if h >= 6.0 and h < 17.0:
		return "day"
	if h >= 17.0 and h < 21.0:
		return "evening"
	return "night"


func _music_tick() -> void:
	if not music_on or master_muted or insts.size() < MB.INSTS.size():
		return
	var m := mood_now()
	if m != _mood:
		_mood = m
		if m == "alarm":   # 불이 나면 다음 구절을 곧바로
			_notes.clear()
			_next_phrase_ms = mini(_next_phrase_ms, Time.get_ticks_msec() + 1500)
	_pad_tick()
	var now := Time.get_ticks_msec()
	if _notes.is_empty() and now >= _next_phrase_ms:
		_phrase_n += 1
		var ph := MB.phrase(_mood, _phrase_n * 7919 + hash(_mood))
		var end_ms := now
		for nt: Array in ph:
			var at := now + int(float(nt[0]) * 1000.0)
			_notes.append([at, nt[1], nt[2], nt[3], _mood])
			end_ms = maxi(end_ms, at)
		var md: Dictionary = MB.MOODS[_mood]
		_next_phrase_ms = end_ms + int(_rng.randf_range(float(md["rest"][0]), float(md["rest"][1])) * 1000.0)
	while not _notes.is_empty() and int(_notes[0][0]) <= now:
		var nt: Array = _notes.pop_front()
		var pl := _free_player(_mus_pool)
		pl.stream = insts[nt[1]]
		pl.pitch_scale = MB.pitch_for(nt[4], nt[1], int(nt[2]))
		pl.volume_db = linear_to_db(maxf(float(nt[3]), 0.01)) - 6.0
		pl.play()


func _pad_tick() -> void:
	var want: String = MB.MOODS[_mood]["pad"]
	if want != "" and not pads.has(want):
		return
	if want != _pad_cur:
		_pad_cur = want
		for t: Tween in _pad_tw:
			if t.is_valid():
				t.kill()
		_pad_tw.clear()
		var old: AudioStreamPlayer = _pad_players[_pad_slot]
		_pad_slot = 1 - _pad_slot
		var nw: AudioStreamPlayer = _pad_players[_pad_slot]
		if old.playing:
			var tw := create_tween()
			tw.tween_property(old, "volume_db", -60.0, 4.0)
			tw.tween_callback(old.stop)
			_pad_tw.append(tw)
		if want != "":
			nw.stream = pads[want]
			nw.volume_db = -60.0
			nw.play(_rng.randf_range(0.0, 7.0))
			var tw2 := create_tween()
			tw2.tween_property(nw, "volume_db", -12.0, 5.0)
			_pad_tw.append(tw2)


# ------------------------------------------------------------------ 보기(샌드박스·검사)

func debug_state() -> Dictionary:
	var lg := {}
	for l: String in _layer_g:
		lg[l] = snappedf(float(_layer_g[l]), 0.01)
	return {"started": _started, "built": build_done, "build_ms": build_total_us / 1000.0, "state": st.duplicate(),
		"weights": w.duplicate(), "layers": lg, "targets": _layer_tgt.duplicate(), "mood": _mood, "duck_db": _duck_db}
