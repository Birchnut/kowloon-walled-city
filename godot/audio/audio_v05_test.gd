extends SceneTree
## v0.5 소리 검사(헤드리스): godot --headless --path godot -s res://audio/audio_v05_test.gd [-- out=/어디/폴더]
## - audio_map.json 에 적힌 파일이 전부 읽히는지, 길이, WAV 는 봉우리·RMS(ogg 는 ffmpeg 로 잰 값을 docs 에)
## - 확대 단계 0..4 → 음악 dB·생활 소리 배율·웅성/장터 층 목표가 가까울수록 커지는지
## - 재생 상태: 곡이 시작되는지, 분위기(밤→낮)에 따라 재생 목록이 바뀌는지
## - 고요시간: quiet_start → 1초 안에 음악·생활 소리 사라지고 배관 층·물방울·발소리만, quiet_end → 2초 안에 돌아옴
## 결과: 콘솔 표 + out 폴더에 report_v05.md. 실패가 있으면 종료 코드 1.

const Director := preload("res://audio/AudioDirector.gd")

var fails: Array = []
var md: Array = []
var out_dir := "user://audio_dump"


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		print("FAIL ", msg)


func _wav_levels(s: AudioStreamWAV) -> Array:
	# 16비트 모노/스테레오 PCM → [봉우리 dBFS, RMS dBFS]
	var d := s.data
	var n := d.size() / 2
	var pk := 0.0
	var ss := 0.0
	for i in n:
		var v := float(d.decode_s16(i * 2)) / 32768.0
		pk = maxf(pk, absf(v))
		ss += v * v
	return [linear_to_db(maxf(pk, 1e-9)), linear_to_db(maxf(sqrt(ss / maxf(1.0, float(n))), 1e-9))]


func _stream_len(s: AudioStream) -> float:
	return s.get_length()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	var d: Node = Director.new()
	d.set("mem_only", true)
	root.add_child(d)
	await process_frame
	var map: Dictionary = d.get("map")
	_check(not map.is_empty(), "audio_map.json 을 못 읽었다")

	# 1) 파일
	md.append("# v0.5 소리 검사 (audio_v05_test.gd)\n")
	md.append("## 파일 읽기\n")
	md.append("| 갈래 | 이름 | 파일 수 | 길이 s(합) | 봉우리 dBFS(WAV) | RMS dBFS(WAV) |")
	md.append("|---|---|---|---|---|---|")
	var n_files := 0
	for kind: String in ["sfx_files", "shot_files"]:
		var sect: Dictionary = map.get(kind, {})
		for n: String in sect:
			if n.begins_with("_"):
				continue
			var paths: Array = sect[n].get("files", [])
			var tot := 0.0
			var pk := -200.0
			var rm := -200.0
			for pth: Variant in paths:
				n_files += 1
				_check(ResourceLoader.exists(str(pth)), "없는 파일 %s" % pth)
				var s: Variant = load(str(pth))
				_check(s is AudioStream, "못 읽는 파일 %s" % pth)
				if s is AudioStream:
					var L := _stream_len(s)
					tot += L
					_check(L > 0.005 and L < 20.0, "길이가 이상하다 %s %.3f" % [pth, L])
					if s is AudioStreamWAV:
						var lv := _wav_levels(s)
						pk = maxf(pk, lv[0])
						rm = maxf(rm, lv[1])
						_check(float(lv[0]) > -30.0, "너무 조용하다 %s 봉우리 %.1f" % [pth, lv[0]])
						_check(float(lv[0]) < 0.5, "클리핑 %s 봉우리 %.1f" % [pth, lv[0]])
			md.append("| %s | %s | %d | %.2f | %s | %s |" % [kind, n, paths.size(), tot, "%.1f" % pk if pk > -199.0 else "(ogg)", "%.1f" % rm if rm > -199.0 else "(ogg)"])
	for n: String in (map.get("loop_files", {}) as Dictionary):
		if n.begins_with("_"):
			continue
		var pth := str(map["loop_files"][n]["file"])
		var s: Variant = load(pth)
		_check(s is AudioStream, "못 읽는 루프 파일 %s" % pth)
		if s is AudioStream:
			n_files += 1
			md.append("| loop_files | %s | 1 | %.2f | (ogg) | (ogg) |" % [n, _stream_len(s)])
	var rec: Node = d.get("rec")
	var mus: Dictionary = (map.get("music", {}) as Dictionary).get("tracks", {})
	md.append("\n## 곡\n")
	md.append("| 곡 | 길이 s |")
	md.append("|---|---|")
	for id: String in mus:
		var s: Variant = load(str(mus[id]))
		_check(s is AudioStream, "못 읽는 곡 %s" % mus[id])
		if s is AudioStream:
			n_files += 1
			var L := _stream_len(s)
			_check(L > 60.0, "곡이 너무 짧다 %s" % id)
			md.append("| %s | %.1f |" % [id, L])
	_check(rec.get("active") == true, "받은 곡이 활성화되지 않았다")
	_check(int((rec.get("tracks") as Dictionary).size()) == mus.size(), "곡 수가 다르다")
	print("파일 %d 개 읽음" % n_files)

	# 2) 확대 단계
	md.append("\n## 확대 단계 (zoom_i 0 = 멀리 … 4 = 가까이)\n")
	md.append("| zoom_i | zoom_out | 음악 +dB | 생활 배율 | 웅성 목표 | 장터 목표 | 마작 분당 | 웍 분당 |")
	md.append("|---|---|---|---|---|---|---|---|")
	var murm: Array = []
	var mkt: Array = []
	var mus_db: Array = []
	var mj: Array = []
	for zi in 5:
		var zo := 1.0 - float(zi) / 4.0
		d.call("set_state_override", {"tod": 18.0 / 24.0, "pop": 600, "sites": 0, "fires": 0, "zoom_out": zo, "zoom_i": zi, "speed": 1.0, "paused": false})
		d.call("_read_state")
		d.call("_layer_targets")
		var tg: Dictionary = d.get("_layer_tgt")
		var r: Dictionary = d.call("shot_rates")
		var mdb: float = d.call("music_zoom_db", zo)
		var lm: float = d.call("life_mult", zo)
		murm.append(float(tg["murmur"]))
		mkt.append(float(tg["market"]))
		mus_db.append(mdb)
		mj.append(float(r["mahjong"]))
		md.append("| %d | %.2f | %.1f | %.2f | %.2f | %.2f | %.2f | %.2f |" % [zi, zo, mdb, lm, tg["murmur"], tg["market"], r["mahjong"], r["wok"]])
	for i in 4:
		_check(float(mus_db[i + 1]) < float(mus_db[i]), "확대할수록 음악이 작아져야 한다 (%d→%d)" % [i, i + 1])
		_check(float(murm[i + 1]) > float(murm[i]), "확대할수록 웅성이 커져야 한다 (%d→%d)" % [i, i + 1])
		_check(float(mkt[i + 1]) > float(mkt[i]), "확대할수록 장터가 커져야 한다 (%d→%d)" % [i, i + 1])
		_check(float(mj[i + 1]) > float(mj[i]), "확대할수록 마작패가 잦아져야 한다 (%d→%d)" % [i, i + 1])

	# 3) 재생: 곡 시작·분위기
	d.set("_started", true)
	d.set_meta("st_override", {})
	d.call("set_tod_override", 22.0 / 24.0)
	d.call("set_state_override", {"pop": 600, "sites": 0, "fires": 0, "zoom_out": 1.0, "zoom_i": 0, "speed": 1.0, "paused": false})
	var t0 := Time.get_ticks_msec()
	while not d.get("build_done") and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	_check(d.get("build_done") == true, "소리 만들기가 30 초 안에 안 끝났다")
	await _wait(4.5)
	var ds1: Dictionary = d.call("debug_state")
	var now1: String = ds1["rec"]["now"]
	var night_list: Array = (map["music"]["lists"] as Dictionary)["night"]
	md.append("\n## 재생 상태\n")
	md.append("- 밤 22시, 시작 4.5 s 뒤: 분위기 %s, 곡 `%s`, 남은 %.1f s, 음악 확대 dB %.1f" % [ds1["mood"], now1, ds1["rec"]["remaining"], ds1["music_zoom_db"]])
	_check(now1 != "" and night_list.has(now1), "밤인데 밤 목록의 곡이 안 나온다: '%s'" % now1)
	var mi := AudioServer.get_bus_index("Music")
	_check(AudioServer.get_bus_volume_db(mi) > -25.0, "멀리 볼 때 음악 버스가 너무 작다 %.1f" % AudioServer.get_bus_volume_db(mi))
	var bus_far := AudioServer.get_bus_volume_db(mi)
	# 확대 → 음악 버스 내려감
	d.call("set_state_override", {"pop": 600, "sites": 0, "fires": 0, "zoom_out": 0.0, "zoom_i": 4, "speed": 1.0, "paused": false})
	await _wait(2.5)
	var bus_near := AudioServer.get_bus_volume_db(mi)
	md.append("- 음악 버스(dB): 멀리 %.1f → 가까이 %.1f" % [bus_far, bus_near])
	_check(bus_near < bus_far - 10.0, "확대해도 음악 버스가 충분히 안 내려갔다 (%.1f → %.1f)" % [bus_far, bus_near])
	d.call("set_state_override", {"pop": 600, "sites": 0, "fires": 0, "zoom_out": 1.0, "zoom_i": 0, "speed": 1.0, "paused": false})
	# 분위기 → 낮: 밤 곡이 낮 목록에 없으면 갈아탄다(6 s)
	d.call("set_tod_override", 13.0 / 24.0)
	var day_list: Array = (map["music"]["lists"] as Dictionary)["day"]
	var switched := false
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 14000:
		await _wait(0.5)
		var rs: Dictionary = d.call("debug_state")["rec"]
		if day_list.has(rs["now"]) and maxf(float(rs["vols"][0]), float(rs["vols"][1])) > 0.99:
			switched = true
			break
	var ds2: Dictionary = d.call("debug_state")
	md.append("- 낮 13시로 바꾼 뒤: 분위기 %s, 곡 `%s`, 갈아탄 시간 %.1f s" % [ds2["mood"], ds2["rec"]["now"], (Time.get_ticks_msec() - t1) / 1000.0])
	_check(switched, "낮이 됐는데 낮 목록 곡으로 안 바뀌었다: %s" % str(ds2["rec"]))

	# 4) 고요시간
	md.append("\n## 고요시간 (실제 시간)\n")
	md.append("| 시각 | q | 음악 버스 dB | 웅웅 층 dB | 배관 층 dB | 배관 재생 | 고요 소리 재생 수 |")
	md.append("|---|---|---|---|---|---|---|")
	d.call("set_tod_override", 13.0 / 24.0)
	await _wait(3.0)   # 생활 소리가 올라올 시간
	var lp: Dictionary = d.get("_layer_p")
	var qp: Array = d.get("_q_pool")
	var rows := func(label: String) -> Dictionary:
		var hum_db := (lp["hum"] as AudioStreamPlayer).volume_db if lp.has("hum") else -99.0
		var pipe_p: AudioStreamPlayer = lp.get("pipe")
		var pipe_db := pipe_p.volume_db if pipe_p != null else -99.0
		var pipe_pl := pipe_p != null and pipe_p.playing
		var nq := 0
		for p: AudioStreamPlayer in qp:
			if p.playing:
				nq += 1
		var r := {"q": float(d.get("_q")), "mus": AudioServer.get_bus_volume_db(mi), "hum": hum_db, "pipe": pipe_db, "pipe_pl": pipe_pl, "nq": nq}
		md.append("| %s | %.2f | %.1f | %.1f | %.1f | %s | %d |" % [label, r["q"], r["mus"], r["hum"], r["pipe"], str(pipe_pl), nq])
		return r
	var before: Dictionary = rows.call("고요 전")
	d.call("quiet_start")
	await _wait(1.25)
	var at1: Dictionary = rows.call("start+1.25s")
	_check(float(at1["q"]) > 0.99, "고요시간이 1 초 안에 완전히 안 됐다 q=%.2f" % at1["q"])
	_check(float(at1["mus"]) < float(before["mus"]) - 50.0, "고요 1 초 뒤 음악이 안 사라졌다 (%.1f → %.1f)" % [before["mus"], at1["mus"]])
	_check(float(at1["hum"]) < -60.0, "고요 1 초 뒤 생활 소리(웅웅)가 안 사라졌다 %.1f" % at1["hum"])
	_check(bool(at1["pipe_pl"]) and float(at1["pipe"]) > -40.0, "배관 떨림이 안 들린다 (재생 %s, %.1f dB)" % [str(at1["pipe_pl"]), at1["pipe"]])
	var seen_q := 0
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 12000 and seen_q < 2:
		await _wait(0.25)
		var any_q := 0
		for p: AudioStreamPlayer in qp:
			if p.playing:
				any_q += 1
		seen_q = maxi(seen_q, any_q)
	md.append("- 고요 12 초 안에 동시에 들린 고요 소리(물방울·발소리·균열) 최대 %d 개" % seen_q)
	_check(seen_q >= 1, "고요시간에 물방울·발소리·균열이 하나도 안 났다")
	d.call("quiet_end")
	await _wait(2.3)
	var after: Dictionary = rows.call("end+2.3s")
	_check(float(after["q"]) < 0.01, "quiet_end 2 초 뒤에도 고요가 남았다 q=%.2f" % after["q"])
	_check(float(after["mus"]) > float(before["mus"]) - 3.0, "quiet_end 뒤 음악이 안 돌아왔다 (%.1f → %.1f)" % [before["mus"], after["mus"]])
	_check(float(after["hum"]) > -40.0, "quiet_end 뒤 웅웅이 안 돌아왔다 %.1f" % after["hum"])
	# 사건 이름으로도
	d.call("_on_game_event", "quiet_start", {})
	_check(d.get("quiet_on") == true, "사건 quiet_start 가 안 먹었다")
	d.call("_on_game_event", "quiet_end", {})
	_check(d.get("quiet_on") == false, "사건 quiet_end 가 안 먹었다")
	# 끝 사건을 놓쳐도 max_s 에 풀린다
	d.call("quiet_start")
	d.set("_quiet_t", 1000.0)
	await process_frame
	await process_frame
	_check(d.get("quiet_on") == false, "max_s 안전장치가 안 풀었다")

	# 5) UI 효과음: 파일로 소리 난다 + 연타 막기
	d.call("set_sfx_muted", false)
	d.call("play", "click")
	var heard := false
	for p: AudioStreamPlayer in d.get("_sfx_pool"):
		if p.playing and p.get_meta("sfx", "") == "click":
			heard = true
			_check(p.stream is AudioStreamWAV and "kenney" in str(p.stream.resource_path), "click 이 Kenney 파일이 아니다: %s" % p.stream.resource_path)
	_check(heard, "click 이 안 울렸다")
	md.append("\n## UI 효과음\n- Kenney 파일로 대체된 이름 %d 개: %s" % [(d.get("file_sfx") as Dictionary).size(), ", ".join((d.get("file_sfx") as Dictionary).keys())])
	md.append("- 합성 그대로 남은 이름: %s" % ", ".join(_synth_left(d)))

	md.append("\n검사 결과: %s" % ("통과" if fails.is_empty() else "실패 %d — %s" % [fails.size(), "; ".join(fails)]))
	var f := FileAccess.open(out_dir + "/report_v05.md", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(md) + "\n")
		f.close()
	print("보고서: %s/report_v05.md" % ProjectSettings.globalize_path(out_dir))
	print("AUDIO V05 TEST: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)


func _synth_left(d: Node) -> Array:
	var SBc: GDScript = load("res://audio/SfxBank.gd")
	var left: Array = []
	for n: String in SBc.names():
		if not (d.get("file_sfx") as Dictionary).has(n):
			left.append(n)
	return left
