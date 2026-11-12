extends SceneTree
## 소리 검사(헤드리스): godot --headless --path godot -s res://audio/audio_test.gd [-- out=/어디/폴더]
## - 효과음·배경 한 번짜리·루프·악기·바탕 화음을 모두 만들고: 조용함/클리핑/NaN/직류 검사, 봉우리·RMS·길이·무게중심 표
## - 루프 이음매(끝→처음 한 걸음 / 보통 걸음, 끝·처음 50 ms RMS 차)
## - 만드는 시간(효과음 합, 전체 합)
## - 구절 생성기가 결정적인지, 음역 안인지
## - 감독(AudioDirector)의 상태 → 층 목표·한 번짜리 빈도가 말이 되는지(밤 귀뚜라미 > 낮, 저녁 웅성 > 새벽, 멀리 보면 바람 ↑, 불 → 불 층)
## - 같은 효과음 연타 막기
## 결과: 콘솔 표 + out 폴더에 WAV 와 report.md. 실패가 있으면 종료 코드 1.

const S := preload("res://audio/Synth.gd")
const SB := preload("res://audio/SfxBank.gd")
const AB := preload("res://audio/AmbienceBank.gd")
const MB := preload("res://audio/MusicBank.gd")
const AN := preload("res://audio/AudioAnalyze.gd")
const Director := preload("res://audio/AudioDirector.gd")
const SfxScript := preload("res://ui/Sfx.gd")

var fails: Array = []
var md: Array = []
var out_dir := "user://audio_dump"
var cpu_acc := 0.0   # 만들기만 잰 CPU ms(분석·파일 쓰기 제외)


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


func _fmt(x: float, d: int = 1) -> String:
	return String.num(x, d)


func _one_shot_rows(title: String, names: Array, nvar: Callable, maker: Callable, gains: Callable, rate_of: Callable) -> int:
	md.append("\n### %s\n" % title)
	md.append("| 이름 | 변주 | Hz | 길이 s | 봉우리 dBFS | 짧은RMS dBFS | 귀가중 짧은RMS | 재생 이득 dB | 들리는 크기 dB | 무게중심 Hz | 85% Hz | 올라감 ms | -20dB까지 ms | 만들기 ms |")
	md.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	var total := 0
	# 먼저 모두 만들고(CPU 를 한 번에 잰다), 그다음 분석
	var built := {}
	var times := {}
	var c0 := AN.cpu_ms()
	for n: String in names:
		var nv: int = nvar.call(n)
		var t0 := Time.get_ticks_usec()
		var bufs: Array = []
		for v in nv:
			bufs.append(await maker.call(n, v))
		times[n] = Time.get_ticks_usec() - t0
		built[n] = bufs
	cpu_acc += AN.cpu_ms() - c0
	for n: String in names:
		var nv: int = nvar.call(n)
		var rate: int = rate_of.call(n)
		var bufs: Array = built[n]
		var us: int = times[n]
		total += us
		var r0: Dictionary = {}
		for v in nv:
			var b: PackedFloat32Array = bufs[v]
			var r := AN.row(b, float(rate))
			if v == 0:
				r0 = r
			_check(b.size() > 100, "%s#%d 비었다" % [n, v])
			_check(not bool(r["nan"]), "%s#%d NaN" % [n, v])
			_check(float(r["peak_db"]) > -30.0, "%s#%d 너무 조용 %.1f dB" % [n, v, r["peak_db"]])
			_check(float(r["peak_db"]) <= -0.9, "%s#%d 봉우리 %.2f dBFS(클리핑 위험)" % [n, v, r["peak_db"]])
			_check(absf(float(r["dc"])) < 0.01, "%s#%d 직류 %.4f" % [n, v, r["dc"]])
			_check(float(r["len_s"]) < 4.0, "%s#%d 너무 길다 %.2f s" % [n, v, r["len_s"]])
			S.save_wav(b, "%s/%s_%d.wav" % [out_dir, n, v], rate)
		var g: float = gains.call(n)
		md.append("| %s | %d | %d | %s | %s | %s | %s | %s | %s |" % [n, nv, rate, _fmt(r0["len_s"], 2), _fmt(r0["peak_db"]), _fmt(r0["srms_db"]), _fmt(r0["k_db"]),
			_fmt(g), _fmt(float(r0["k_db"]) + g)] + " %s | %s | %s | %s | %s |" % [ _fmt(r0["centroid"], 0), _fmt(r0["rolloff"], 0), _fmt(r0["attack_ms"], 0), _fmt(r0["decay20_ms"], 0), _fmt(us / 1000.0, 1)])
		print("%-18s v%d len %.2fs peak %6.1f srms %6.1f k %6.1f play %6.1f  cent %5.0f  att %3.0fms dec %4.0fms  %5.1fms" % [n, nv, r0["len_s"], r0["peak_db"], r0["srms_db"], r0["k_db"], float(r0["k_db"]) + g, r0["centroid"], r0["attack_ms"], r0["decay20_ms"], us / 1000.0])
	return total


func _run() -> void:
	var t_all := Time.get_ticks_usec()
	var cpu0 := AN.cpu_ms()
	md.append("# 소리 분석표 (audio_test.gd 가 만든 것)\n")
	md.append("'귀가중 짧은RMS' = 100 Hz 아래 깎고 1.7 kHz 위 +4 dB 한 뒤 가장 시끄러운 50 ms RMS(효과음은 이 값을 -20 dBFS 로 맞춰 만든다). '들리는 크기' = 귀가중 + 재생 이득. 버스 크기는 빼고 본 값(기본: 주 0.9 = -0.9 dB, SFX 0.85 = -1.4 dB, 배경 0.7 = -3.1 dB, 음악 0.4 = -8 dB).")
	# 1) 효과음
	cpu_acc = 0.0
	var sfx_us: int = await _one_shot_rows("효과음 (SFX 버스)", SB.names(), func(n: String) -> int: return SB.variants(n),
		func(n: String, v: int) -> PackedFloat32Array: return await SB.build(n, v), func(n: String) -> float: return SB.gain_db(n), func(n: String) -> int: return SB.rate(n))
	var c_sfx := cpu_acc
	print("효과음 만들기 합: 벽시계 %.1f ms, CPU %.0f ms" % [sfx_us / 1000.0, c_sfx])
	for n: String in SfxScript.NAMES:
		_check(SB.SPEC.has(n), "NAMES 의 %s 에 조리법이 없다" % n)
	# 2) 배경 한 번짜리
	cpu_acc = 0.0
	var shot_us: int = await _one_shot_rows("배경 한 번짜리 (Ambience 버스, 무작위 -4..0 dB 더)", AB.SHOTS.keys(), func(n: String) -> int: return int(AB.SHOTS[n][0]),
		func(n: String, v: int) -> PackedFloat32Array: return await AB.build_shot(n, v), func(n: String) -> float: return float(AB.SHOTS[n][1]), func(_n: String) -> int: return AB.SHOT_RATE)
	var c_shot := cpu_acc
	# 3) 악기
	cpu_acc = 0.0
	var inst_us := 0
	md.append("\n### 음악 악기\n")
	md.append("| 악기 | 바탕 Hz | 길이 s | 봉우리 dBFS | 무게중심 Hz | -20dB까지 ms |")
	md.append("|---|---|---|---|---|---|")
	for i: String in MB.INSTS:
		var t0 := Time.get_ticks_usec()
		var c0 := AN.cpu_ms()
		var b: PackedFloat32Array = await MB.build_inst(i)
		cpu_acc += AN.cpu_ms() - c0
		inst_us += Time.get_ticks_usec() - t0
		var r := AN.row(b, 22050.0)
		_check(not bool(r["nan"]) and float(r["peak_db"]) > -30.0 and float(r["peak_db"]) <= -0.9, "악기 %s 크기 이상 %.1f" % [i, r["peak_db"]])
		S.save_wav(b, "%s/inst_%s.wav" % [out_dir, i])
		md.append("| %s | %s | %s | %s | %s | %s |" % [i, _fmt(MB.base_hz[i], 2), _fmt(r["len_s"], 2), _fmt(r["peak_db"]), _fmt(r["centroid"], 0), _fmt(r["decay20_ms"], 0)])
	# 4) 루프
	md.append("\n### 루프 (이음매: 끝→처음 한 걸음 ÷ 보통 걸음 99백분위, 끝·처음 50 ms RMS 차)\n")
	md.append("| 루프 | Hz | 길이 s | RMS dBFS | 봉우리 dBFS | 무게중심 Hz | 이음매 비 | 가장자리 dB | 만들기 ms |")
	md.append("|---|---|---|---|---|---|---|---|---|")
	var c_inst := cpu_acc
	cpu_acc = 0.0
	var bud := AB.Budget.new()   # tree 없음 = 쉬지 않음
	var loop_us := 0
	var all_loops: Array = []
	for l: String in AB.LOOPS:
		all_loops.append([l, "amb"])
	for p: String in MB.PADS:
		all_loops.append([p, "pad"])
	for e: Array in all_loops:
		var l: String = e[0]
		var t0 := Time.get_ticks_usec()
		var c0 := AN.cpu_ms()
		var b: PackedFloat32Array
		var sr := 22050.0
		if e[1] == "amb":
			b = await AB.build_loop(l, bud)
			sr = float(AB.loop_rate(l))
		else:
			b = await MB.build_pad(l, bud)
			sr = 11025.0
		var us := Time.get_ticks_usec() - t0
		cpu_acc += AN.cpu_ms() - c0
		loop_us += us
		var r := AN.row(b, sr)
		var seam := AN.loop_seam(b, sr)
		_check(not bool(r["nan"]), "루프 %s NaN" % l)
		_check(float(r["peak_db"]) <= -0.9 and float(r["rms_db"]) > -40.0, "루프 %s 크기 이상 rms %.1f peak %.1f" % [l, r["rms_db"], r["peak_db"]])
		_check(float(seam["ratio"]) <= 2.0, "루프 %s 이음매 튐 %.2f×" % [l, seam["ratio"]])
		_check(float(seam["edge_db"]) <= 4.0 or l in ["murmur", "market", "crickets", "fire", "rain"], "루프 %s 끝·처음 크기 차 %.1f dB" % [l, seam["edge_db"]])
		# 이음매 듣기용: 루프를 두 번 이어 쓴다
		var twice := b.duplicate()
		twice.append_array(b)
		S.save_wav(twice, "%s/loop_%s_x2.wav" % [out_dir, l], int(sr))
		md.append("| %s | %d | %s | %s | %s | %s | %s | %s | %s |" % [l, int(sr), _fmt(r["len_s"], 1), _fmt(r["rms_db"]), _fmt(r["peak_db"]), _fmt(r["centroid"], 0), _fmt(seam["ratio"], 2), _fmt(seam["edge_db"]), _fmt(us / 1000.0, 0)])
		print("loop %-10s %5d Hz %.1fs rms %6.1f peak %6.1f cent %5.0f seam %.2fx edge %.1fdB  %.0fms" % [l, int(sr), r["len_s"], r["rms_db"], r["peak_db"], r["centroid"], seam["ratio"], seam["edge_db"], us / 1000.0])
	var c_loop := cpu_acc
	var total_ms := (sfx_us + shot_us + inst_us + loop_us) / 1000.0
	var total_cpu := c_sfx + c_shot + c_inst + c_loop
	md.append("\n만들기 시간(데스크톱 빌드, 이 상자 2코어를 다른 작업과 나눠 씀). 벽시계: 효과음 %.0f · 배경 한 번짜리 %.0f · 악기 %.0f · 루프+바탕화음 %.0f · 합 %.0f ms. **CPU 시간(/proc, 10 ms 단위): 효과음 %.0f · 한 번짜리 %.0f · 악기 %.0f · 루프 %.0f · 합 %.0f ms.** 게임에서는 프레임마다 4 ms 씩 나눠 만든다." % [sfx_us / 1000.0, shot_us / 1000.0, inst_us / 1000.0, loop_us / 1000.0, total_ms, c_sfx, c_shot, c_inst, c_loop, total_cpu])
	print("만들기 합: 벽시계 %.0f ms (효과음 %.0f, 한 번짜리 %.0f, 악기 %.0f, 루프 %.0f) / CPU %.0f ms (효과음 %.0f, 한 번짜리 %.0f, 악기 %.0f, 루프 %.0f)" % [total_ms, sfx_us / 1000.0, shot_us / 1000.0, inst_us / 1000.0, loop_us / 1000.0, total_cpu, c_sfx, c_shot, c_inst, c_loop])
	# CPU 시간을 못 읽는 곳(리눅스 밖)에서는 벽시계로 본다
	var judge := total_cpu if cpu0 >= 0.0 else total_ms
	_check(judge < 1500.0, "전체 만들기가 1.5 s 를 넘었다: %.0f ms" % judge)
	_check((c_sfx if cpu0 >= 0.0 else sfx_us / 1000.0) < 600.0, "효과음 만들기가 0.6 s 를 넘었다")
	# 5) 구절 생성기
	for mood: String in MB.MOODS:
		var a := MB.phrase(mood, 12345)
		var b := MB.phrase(mood, 12345)
		_check(str(a) == str(b), "구절 %s 이 결정적이지 않다" % mood)
		_check(a.size() >= 3, "구절 %s 이 너무 짧다" % mood)
		var m: Dictionary = MB.MOODS[mood]
		for nt: Array in a:
			_check(int(nt[2]) >= int(m["lo"]) and int(nt[2]) <= int(m["hi"]), "구절 %s 음역 밖 %d" % [mood, nt[2]])
			var ps := MB.pitch_for(mood, nt[1], int(nt[2]))
			_check(ps > 0.35 and ps < 3.0, "구절 %s pitch_scale %.2f" % [mood, ps])
	# 6) 감독 논리
	await _director_checks()
	md.append("\n검사 결과: %s" % ("통과" if fails.is_empty() else "실패 %d — %s" % [fails.size(), "; ".join(fails)]))
	var f := FileAccess.open(out_dir + "/report.md", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(md) + "\n")
		f.close()
	print("보고서: %s/report.md  (%.1f s)" % [ProjectSettings.globalize_path(out_dir), (Time.get_ticks_usec() - t_all) / 1e6])
	print("AUDIO TEST: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)


func _director_checks() -> void:
	var d: Node = Director.new()
	d.set("mem_only", true)
	root.add_child(d)
	await process_frame
	d.set("_started", true)
	var cases := [
		["새벽 3시, 인구 600", {"tod": 3.0 / 24.0, "pop": 600, "sites": 0, "fires": 0, "zoom_out": 0.5, "speed": 1.0, "paused": false}],
		["아침 8시, 인구 600", {"tod": 8.0 / 24.0, "pop": 600, "sites": 1, "fires": 0, "zoom_out": 0.5, "speed": 1.0, "paused": false}],
		["낮 13시, 인구 40", {"tod": 13.0 / 24.0, "pop": 40, "sites": 2, "fires": 0, "zoom_out": 0.5, "speed": 1.0, "paused": false}],
		["낮 13시, 인구 600, 멀리", {"tod": 13.0 / 24.0, "pop": 600, "sites": 2, "fires": 0, "zoom_out": 1.0, "speed": 1.0, "paused": false}],
		["낮 13시, 인구 600, 가까이", {"tod": 13.0 / 24.0, "pop": 600, "sites": 2, "fires": 0, "zoom_out": 0.0, "speed": 1.0, "paused": false}],
		["저녁 18시, 인구 600", {"tod": 18.0 / 24.0, "pop": 600, "sites": 0, "fires": 0, "zoom_out": 0.5, "speed": 1.0, "paused": false}],
		["저녁 18시, 인구 600, ×4", {"tod": 18.0 / 24.0, "pop": 600, "sites": 0, "fires": 0, "zoom_out": 0.5, "speed": 4.0, "paused": false}],
		["밤 22시, 인구 600, 불 2", {"tod": 22.0 / 24.0, "pop": 600, "sites": 0, "fires": 2, "zoom_out": 0.5, "speed": 1.0, "paused": false}],
		["밤 22시, 인구 600, 멈춤", {"tod": 22.0 / 24.0, "pop": 600, "sites": 0, "fires": 0, "zoom_out": 0.5, "speed": 1.0, "paused": true}],
	]
	md.append("\n### 배경이 상태를 따라가는 모양 (층 목표 0..1, 한 번짜리 = 분당 합)\n")
	md.append("| 상황 | 웅웅 | 바람 | 웅성 | 장터 | 귀뚜라미 | 불 | 한 번짜리/분 | 많은 것 | 음악 |")
	md.append("|---|---|---|---|---|---|---|---|---|---|")
	var res := {}
	for c: Array in cases:
		d.call("set_state_override", c[1])
		d.call("_read_state")
		d.call("_layer_targets")
		var t: Dictionary = d.get("_layer_tgt")
		var r: Dictionary = d.call("shot_rates")
		var tot := 0.0
		var top: Array = []
		for k: String in r:
			tot += float(r[k])
			top.append([float(r[k]), k])
		top.sort()
		top.reverse()
		var tops := ", ".join(top.slice(0, 3).map(func(x: Array) -> String: return "%s %.1f" % [x[1], x[0]]))
		res[c[0]] = {"t": t, "tot": tot}
		md.append("| %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.1f | %s | %s |" % [c[0], t["hum"], t["wind"], t["murmur"], t["market"], t["crickets"], t["fire"], tot, tops, d.call("mood_now")])
	_check(float(res["새벽 3시, 인구 600"]["t"]["crickets"]) > float(res["낮 13시, 인구 600, 멀리"]["t"]["crickets"]) + 0.3, "밤 귀뚜라미가 낮보다 크지 않다")
	_check(float(res["저녁 18시, 인구 600"]["t"]["murmur"]) > float(res["새벽 3시, 인구 600"]["t"]["murmur"]) * 2.0, "저녁 웅성이 새벽보다 충분히 크지 않다")
	_check(float(res["저녁 18시, 인구 600"]["t"]["market"]) > 0.4, "저녁 장터가 약하다")
	_check(float(res["낮 13시, 인구 600, 멀리"]["t"]["wind"]) > float(res["낮 13시, 인구 600, 가까이"]["t"]["wind"]) + 0.3, "멀리 볼 때 바람이 세지지 않는다")
	_check(float(res["낮 13시, 인구 600, 가까이"]["t"]["murmur"]) > float(res["낮 13시, 인구 40"]["t"]["murmur"]) * 3.0, "인구가 늘어도 웅성이 크지 않다")
	_check(float(res["밤 22시, 인구 600, 불 2"]["t"]["fire"]) > 0.5, "불이 나도 불 층이 없다")
	_check(float(res["저녁 18시, 인구 600, ×4"]["tot"]) > float(res["저녁 18시, 인구 600"]["tot"]) * 1.3, "×4 에서 한 번짜리가 늘지 않는다")
	_check(float(res["저녁 18시, 인구 600, ×4"]["tot"]) < float(res["저녁 18시, 인구 600"]["tot"]) * 1.7, "×4 에서 한 번짜리가 너무 늘었다")
	_check(float(res["밤 22시, 인구 600, 멈춤"]["tot"]) < 1.0, "멈춤인데 한 번짜리가 많다")
	for c: Array in cases:
		_check(float(res[c[0]]["tot"]) < 20.0, "%s: 한 번짜리가 분당 20 을 넘는다" % c[0])
	# 연타 막기: 같은 이름 두 번 → 한 번만 소리
	var playing_before := 0
	d.call("play", "click")
	d.call("play", "click")
	d.call("play", "click")
	for p: AudioStreamPlayer in d.get("_sfx_pool"):
		if p.playing and p.get_meta("sfx", "") == "click":
			playing_before += 1
	_check(playing_before == 1, "click 연타가 막히지 않았다(%d)" % playing_before)
	# 볼륨 API
	d.call("set_volume", "music", 0.25)
	_check(absf(float(d.call("get_volume", "Music")) - 0.25) < 1e-6, "get_volume(music)")
	var mi := AudioServer.get_bus_index("Music")
	_check(mi >= 0 and absf(AudioServer.get_bus_volume_db(mi) - linear_to_db(0.25)) < 0.5, "Music 버스 크기가 반영되지 않았다")
	_check(AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Ambience") >= 0, "버스가 없다")
	d.call("mute", true)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "mute(true) 가 주 버스를 끄지 않았다")
	d.call("mute", false)
	d.queue_free()
