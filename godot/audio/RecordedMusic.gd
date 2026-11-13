extends Node
## RecordedMusic — 받아 둔 곡(CC0 음원, godot/audio/music/)을 분위기별 재생 목록으로 번갈아 튼다.
## - 곡 사이는 crossfade_s 동안 겹쳐 부드럽게. 분위기가 바뀌어 지금 곡이 새 목록에 없으면 mood_switch_fade_s 에 걸쳐 바꾼다.
## - 곡이 하나도 안 읽히면 active == false (AudioDirector 가 합성 음악을 쓴다).
## - 시간은 tick(dt) 에 들어오는 실제 시간 기준(배속과 무관).
## - 목록·파일 이름은 godot/data/audio/audio_map.json 의 "music". 음량 덕(확대·고요시간·멈춤)은 AudioDirector 가 Music 버스로 건다.

var active := false
var mood := "day"
var tracks: Dictionary = {}      # 곡 이름 → AudioStream
var lists: Dictionary = {}       # 분위기 → Array[곡 이름]
var crossfade_s := 5.0
var switch_fade_s := 6.0
var start_delay_s := 3.0
var alarm_duck_db := -8.0
var bus_name := "Music"

var _p: Array = []               # AudioStreamPlayer 둘
var _vol: Array = [0.0, 0.0]     # 선형 0..1
var _tgt: Array = [0.0, 0.0]
var _fade_s: Array = [5.0, 5.0]
var _cur := -1                   # 지금 곡이 있는 플레이어(-1 = 없음)
var _cur_id := ""
var _history: Array = []
var _t_since_start := 0.0
var _rng := RandomNumberGenerator.new()
var _alarm_db := 0.0
var _switching := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7311972
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus_name
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.volume_db = -80.0
		add_child(p)
		_p.append(p)


## 설정을 읽고 곡을 불러온다. 불러온 곡 수를 돌려준다.
func setup(cfg: Dictionary) -> int:
	crossfade_s = float(cfg.get("crossfade_s", 5.0))
	switch_fade_s = float(cfg.get("mood_switch_fade_s", 6.0))
	start_delay_s = float(cfg.get("start_delay_s", 3.0))
	alarm_duck_db = float(cfg.get("alarm_duck_db", -8.0))
	tracks.clear()
	var tr: Dictionary = cfg.get("tracks", {})
	for id: String in tr:
		var path := str(tr[id])
		if not ResourceLoader.exists(path):
			push_warning("RecordedMusic: 곡 파일이 없다 %s" % path)
			continue
		var s: Variant = load(path)
		if s is AudioStream:
			tracks[id] = s
		else:
			push_warning("RecordedMusic: 읽을 수 없는 곡 %s" % path)
	lists.clear()
	var ls: Dictionary = cfg.get("lists", {})
	for m: String in ls:
		var arr: Array = []
		for id: Variant in ls[m]:
			if tracks.has(str(id)):
				arr.append(str(id))
		lists[m] = arr
	active = tracks.size() > 0
	return tracks.size()


func has_list(m: String) -> bool:
	return not (lists.get(m, []) as Array).is_empty()


## 지금 분위기의 재생 목록(alarm 은 목록이 없으면 마지막 일반 분위기 것을 이어 쓴다).
func _list_for(m: String) -> Array:
	var l: Array = lists.get(m, [])
	if l.is_empty():
		l = lists.get("night" if m == "alarm" else "day", [])
	return l


func _pick(m: String) -> String:
	var l := _list_for(m)
	if l.is_empty():
		return ""
	var cands: Array = []
	for id: Variant in l:
		if not _history.has(id) or l.size() == 1:
			cands.append(id)
	if cands.is_empty():
		_history.clear()
		cands = l.duplicate()
	if cands.size() > 1 and cands.has(_cur_id):
		cands.erase(_cur_id)
	return str(cands[_rng.randi() % cands.size()])


func _start_track(id: String, fade_s: float) -> void:
	if id == "" or not tracks.has(id):
		return
	var slot := 0 if _cur != 0 else 1
	var p: AudioStreamPlayer = _p[slot]
	p.stream = tracks[id]
	_vol[slot] = 0.0
	_tgt[slot] = 1.0
	_fade_s[slot] = maxf(0.05, fade_s)
	p.volume_db = -80.0
	p.play()
	if _cur >= 0:
		_tgt[_cur] = 0.0
		_fade_s[_cur] = maxf(0.05, fade_s)
	_cur = slot
	_cur_id = id
	_history.append(id)
	if _history.size() > 3:
		_history.pop_front()
	_switching = false


## 지금 곡 이름("" = 없음), 남은 초.
func now_playing() -> String:
	if _cur >= 0 and (_p[_cur] as AudioStreamPlayer).playing:
		return _cur_id
	return ""


func remaining_s() -> float:
	if _cur < 0:
		return 0.0
	var p: AudioStreamPlayer = _p[_cur]
	if p.stream == null or not p.playing:
		return 0.0
	return maxf(0.0, p.stream.get_length() - p.get_playback_position())


func stop_all() -> void:
	for i in _p.size():
		(_p[i] as AudioStreamPlayer).stop()
		_vol[i] = 0.0
		_tgt[i] = 0.0
	_cur = -1
	_cur_id = ""
	_t_since_start = 0.0


## 곧바로 다음 곡으로(시험·샌드박스용).
func skip() -> void:
	_start_track(_pick(mood), crossfade_s)


func tick(dt: float) -> void:
	if not active or _p.size() < 2:
		return
	_t_since_start += dt
	var cur_alive := _cur >= 0 and (_p[_cur] as AudioStreamPlayer).playing
	if not cur_alive:
		_cur = -1
		_cur_id = ""
		if _t_since_start >= start_delay_s:
			_start_track(_pick(mood), 2.0)
	else:
		var l := _list_for(mood)
		var rem := remaining_s()
		if rem <= crossfade_s + 0.2:
			_start_track(_pick(mood), crossfade_s)
		elif not _switching and not l.has(_cur_id) and not l.is_empty():
			# 분위기가 바뀌어 지금 곡이 어울리지 않는다 → 부드럽게 갈아탄다
			_switching = true
			_start_track(_pick(mood), switch_fade_s)
	var want_alarm := alarm_duck_db if mood == "alarm" else 0.0
	_alarm_db += (want_alarm - _alarm_db) * minf(1.0, dt / 1.5)
	for i in 2:
		var p: AudioStreamPlayer = _p[i]
		if not p.playing:
			continue
		var step := dt / float(_fade_s[i])
		if _vol[i] < _tgt[i]:
			_vol[i] = minf(_tgt[i], _vol[i] + step)
		elif _vol[i] > _tgt[i]:
			_vol[i] = maxf(_tgt[i], _vol[i] - step)
		if _tgt[i] <= 0.0 and _vol[i] <= 0.001 and i != _cur:
			p.stop()
			continue
		# 선형 크로스페이드를 제곱 곡선(동력 맞춤에 가까운)으로
		var g: float = pow(float(_vol[i]), 1.5)
		p.volume_db = linear_to_db(maxf(g, 0.0001)) + _alarm_db


func debug_state() -> Dictionary:
	return {"active": active, "tracks": tracks.size(), "mood": mood, "now": now_playing(), "remaining": snappedf(remaining_s(), 0.1),
		"vols": [snappedf(float(_vol[0]), 0.01), snappedf(float(_vol[1]), 0.01)], "history": _history.duplicate()}
