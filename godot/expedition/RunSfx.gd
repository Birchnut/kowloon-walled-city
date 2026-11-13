extends Node
## 코드로 합성한 효과음(음원 파일 없음). 처음 한 번 만들어 두고 재생기 여러 개로 돌려 쓴다.
## M 키로 끄고 켠다(RunSandbox). 헤드리스에서는 만들지 않는다.

const RATE := 22050
const S = preload("res://audio/Synth.gd")
const SHEET_R := [1.0, 1.47, 2.09, 2.56, 3.18, 3.9, 4.7, 5.6]
const SHEET_A := [1.0, 0.8, 0.7, 0.55, 0.45, 0.35, 0.28, 0.2]
const TIN_R := [1.0, 1.59, 2.14, 2.65, 3.5]
const TIN_A := [1.0, 0.6, 0.45, 0.3, 0.2]
const WOOD_R := [1.0, 2.57, 4.1]
const WOOD_A := [1.0, 0.45, 0.18]

var streams: Dictionary = {}        # id -> AudioStreamWAV 또는 [변형들]
var players: Array = []
var search_player: AudioStreamPlayer
var ambient: AudioStreamPlayer
var muted: bool = false
var _rr := 0
var _last: Dictionary = {}
var rng := RandomNumberGenerator.new()

const VOL := {
	"swing": -8.0, "hit": -4.0, "clang": -4.0, "pickup": -9.0, "pop": -10.0, "roll": -11.0, "hurt": -3.0,
	"alarm": -9.0, "stomp": -2.0, "tick": -14.0, "squeak": -15.0, "bark": -9.0, "growl": -8.0,
	"whistle": -10.0, "throw": -12.0, "clank": -8.0, "crash": -5.0, "creak": -10.0, "crackle": -14.0,
	"zap": -8.0, "hydraulic": -9.0, "spit": -9.0, "thud": -7.0, "grunt": -10.0, "down": -5.0, "drop": -11.0,
	"yelp": -8.0, "bonk": -7.0, "puff": -9.0, "roar": -3.0, "siren": -9.0, "flood": -8.0, "wood": -7.0,
}


func _ready() -> void:
	rng.seed = 11
	for k in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	var gen := {
		"swing": _swing(), "hit": _hit(), "clang": _clang(), "pickup": _pickup(), "pop": _pop(), "roll": _roll(),
		"hurt": _hurt(), "alarm": _alarm(), "stomp": _stomp(), "tick": _tick(), "squeak": _squeak(),
		"bark": _bark(), "growl": _growl(), "whistle": _whistle(), "throw": _throw_s(), "clank": _clank(),
		"crash": _crash(), "creak": _creak(), "crackle": _crackle(), "zap": _zap(), "hydraulic": _hydraulic(),
		"spit": _spit(), "thud": _thud(), "grunt": _grunt(), "down": _down(), "drop": _drop(),
	}
	for k in gen:
		streams[k] = _wav(gen[k])
	# Synth.gd 로 다시 만든 것들(재질 소리, 변형 여러 개 — 같은 소리가 연달아 똑같이 나지 않게)
	S.set_rate(float(RATE))
	streams["hit"] = [_s_clonk(330.0, 1), _s_clonk(370.0, 2), _s_clonk(300.0, 3), _s_clonk(410.0, 4)]
	streams["clang"] = [_s_clonk(180.0, 5, 1.6), _s_clonk(200.0, 6, 1.6)]
	streams["clank"] = [_s_tin(7), _s_tin(8), _s_tin(9)]
	streams["wood"] = [_s_wood(10), _s_wood(11)]
	streams["thud"] = [_s_wood(12)]
	streams["yelp"] = [_s_yelp(1.0), _s_yelp(1.12)]
	streams["squeak"] = [_s_squeak(1.0), _s_squeak(1.2)]
	streams["bonk"] = [_s_bonk()]
	streams["puff"] = [_s_puff()]
	streams["hydraulic"] = [_s_hydraulic()]
	streams["stomp"] = [_s_stomp()]
	streams["roar"] = [_s_roar()]
	streams["siren"] = [_s_siren()]
	streams["flood"] = [_s_flood()]
	streams["swing"] = [_s_whoosh(1), _s_whoosh(2)]
	search_player = AudioStreamPlayer.new()
	var ss := _wav(_rustle())
	ss.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ss.loop_end = int(RATE * 0.6)
	search_player.stream = ss
	search_player.volume_db = -14.0
	add_child(search_player)
	ambient = AudioStreamPlayer.new()
	# 6초 + 0.5초를 만들어 끝 0.5초를 처음에 겹쳐 이음매 없이(예전엔 6초마다 딸깍)
	var raw := _drone(6.5)
	var looped := S.loop_xfade(raw, int(RATE * 6.0), int(RATE * 0.5))
	var amb := S.to_wav(looped, true)
	ambient.stream = amb
	ambient.volume_db = -20.0
	add_child(ambient)
	ambient.play()


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)


func play(id: String) -> void:
	if muted or not streams.has(id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, 0)) < 45:
		return
	_last[id] = now
	var p: AudioStreamPlayer = players[_rr % players.size()]
	_rr += 1
	var st: Variant = streams[id]
	if st is Array:
		st = (st as Array)[rng.randi_range(0, (st as Array).size() - 1)]
	p.stream = st
	p.volume_db = VOL.get(id, -8.0)
	var spread := 0.14 if id in ["hit", "clank", "clang", "bonk", "wood"] else 0.07
	p.pitch_scale = rng.randf_range(1.0 - spread, 1.0 + spread)
	p.play()


func loop_search(on: bool) -> void:
	if on and not search_player.playing and not muted:
		search_player.play()
	elif not on and search_player.playing:
		search_player.stop()


# ------------------------------------------------------------------ 합성
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for k in samples.size():
		var v := int(clampf(samples[k], -1.0, 1.0) * 32000.0)
		b.encode_s16(k * 2, v)
	w.data = b
	return w


func _buf(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	return a


func _env(k: int, n: int, att: float = 0.01, curve: float = 2.0) -> float:
	var t := float(k) / n
	var a := minf(1.0, t / maxf(att, 0.0001))
	return a * pow(1.0 - t, curve)


## 잡음 + 한 극 저역 통과(차단 주파수가 시간에 따라 변함)
func _noise_sweep(sec: float, f0: float, f1: float, curve: float = 2.0, att: float = 0.01) -> PackedFloat32Array:
	var a := _buf(sec)
	var n := a.size()
	var y := 0.0
	for k in n:
		var f := lerpf(f0, f1, float(k) / n)
		var alpha := clampf(TAU * f / RATE, 0.0, 1.0)
		y += alpha * (rng.randf_range(-1, 1) - y)
		a[k] = y * _env(k, n, att, curve) * 1.6
	return a


func _tone(sec: float, f0: float, f1: float, shape: String = "sine", curve: float = 2.0, att: float = 0.005) -> PackedFloat32Array:
	var a := _buf(sec)
	var n := a.size()
	var ph := 0.0
	for k in n:
		var f := lerpf(f0, f1, float(k) / n)
		ph += f / RATE
		var s := 0.0
		match shape:
			"sine": s = sin(ph * TAU)
			"square": s = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			"saw": s = fmod(ph, 1.0) * 2.0 - 1.0
			"tri": s = 1.0 - 4.0 * absf(fmod(ph, 1.0) - 0.5)
		a[k] = s * _env(k, n, att, curve)
	return a


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gb: float = 1.0, offset: int = 0) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size() + offset)
	var o := PackedFloat32Array()
	o.resize(n)
	for k in n:
		var v := 0.0
		if k < a.size():
			v += a[k]
		if k - offset >= 0 and k - offset < b.size():
			v += b[k - offset] * gb
		o[k] = v
	return o


func _swing() -> PackedFloat32Array: return _noise_sweep(0.16, 800, 4000, 1.5, 0.3)
func _hit() -> PackedFloat32Array: return _mix(_tone(0.12, 160, 60, "sine", 3.0), _noise_sweep(0.06, 5000, 1500, 2.0), 0.7)
func _clang() -> PackedFloat32Array: return _mix(_mix(_tone(0.35, 620, 600, "tri", 3.0), _tone(0.35, 931, 925, "sine", 4.0), 0.5), _noise_sweep(0.05, 6000, 2000), 0.6)
func _pickup() -> PackedFloat32Array: return _mix(_tone(0.07, 660, 660, "square", 1.0), _tone(0.1, 990, 990, "square", 1.5), 1.0, int(RATE * 0.06))
func _pop() -> PackedFloat32Array: return _tone(0.08, 300, 700, "sine", 2.0)
func _roll() -> PackedFloat32Array: return _noise_sweep(0.25, 300, 1200, 1.2, 0.2)
func _hurt() -> PackedFloat32Array: return _mix(_tone(0.25, 420, 140, "square", 1.5), _noise_sweep(0.1, 3000, 800), 0.5)
func _tick() -> PackedFloat32Array: return _tone(0.03, 1400, 1400, "square", 2.0)
func _squeak() -> PackedFloat32Array: return _tone(0.09, 2200, 3000, "tri", 1.0)
func _whistle() -> PackedFloat32Array: return _mix(_tone(0.12, 1800, 2100, "sine", 0.5), _tone(0.2, 2100, 1700, "sine", 1.5), 1.0, int(RATE * 0.13))
func _throw_s() -> PackedFloat32Array: return _noise_sweep(0.12, 1500, 500, 1.0, 0.4)
func _clank() -> PackedFloat32Array: return _mix(_tone(0.18, 1200, 1150, "tri", 4.0), _noise_sweep(0.04, 6000, 3000), 0.8)
func _creak() -> PackedFloat32Array: return _tone(0.5, 110, 80, "saw", 0.8, 0.2)
func _thud() -> PackedFloat32Array: return _mix(_tone(0.2, 90, 40, "sine", 2.0), _noise_sweep(0.15, 600, 200), 0.6)
func _drop() -> PackedFloat32Array: return _tone(0.08, 400, 200, "tri", 2.0)
func _grunt() -> PackedFloat32Array: return _tone(0.15, 140, 110, "saw", 1.5, 0.03)
func _spit() -> PackedFloat32Array: return _mix(_noise_sweep(0.3, 400, 2000, 1.0, 0.3), _tone(0.3, 70, 50, "square", 2.0), 0.3)


func _bark() -> PackedFloat32Array:
	var a := _mix(_tone(0.12, 520, 300, "saw", 1.5, 0.01), _noise_sweep(0.12, 2000, 800, 2.0), 0.5)
	return a


func _growl() -> PackedFloat32Array:
	var a := _buf(0.6)
	var n := a.size()
	var ph := 0.0
	for k in n:
		var t := float(k) / RATE
		ph += (85.0 + sin(t * 40.0) * 15.0) / RATE
		var s := (fmod(ph, 1.0) * 2.0 - 1.0) * (0.6 + 0.4 * sin(t * 70.0))
		a[k] = s * _env(k, n, 0.15, 0.8) * 0.8
	return a


func _alarm() -> PackedFloat32Array:
	var a := _buf(0.9)
	var n := a.size()
	var ph := 0.0
	for k in n:
		var t := float(k) / RATE
		var f := 700.0 if fmod(t, 0.3) < 0.15 else 520.0
		ph += f / RATE
		a[k] = (1.0 if fmod(ph, 1.0) < 0.5 else -1.0) * 0.5 * _env(k, n, 0.02, 0.6)
	return a


func _stomp() -> PackedFloat32Array:
	return _mix(_mix(_tone(0.6, 70, 30, "sine", 2.0), _noise_sweep(0.4, 1500, 150, 2.0)), _tone(0.3, 140, 60, "square", 3.0), 0.3)


func _crash() -> PackedFloat32Array:
	var a := _noise_sweep(0.6, 3000, 300, 1.5)
	for k in 5:
		a = _mix(a, _tone(0.12, 800 + k * 230, 700 + k * 200, "tri", 3.0), 0.4, int(RATE * (0.03 + k * 0.07)))
	return a


func _crackle() -> PackedFloat32Array:
	var a := _buf(0.5)
	for k in a.size():
		a[k] = (rng.randf_range(-1, 1) if rng.randf() < 0.04 else 0.0) * 0.8
	return a


func _zap() -> PackedFloat32Array:
	var a := _buf(0.4)
	var n := a.size()
	var ph := 0.0
	for k in n:
		ph += (120.0 + rng.randf() * 40.0) / RATE
		a[k] = ((1.0 if fmod(ph, 1.0) < 0.5 else -1.0) * 0.4 + rng.randf_range(-0.5, 0.5)) * _env(k, n, 0.01, 1.0)
	return a


func _hydraulic() -> PackedFloat32Array:
	return _mix(_noise_sweep(0.5, 2500, 1800, 0.7, 0.1), _tone(0.5, 60, 90, "saw", 1.0, 0.1), 0.25)


func _down() -> PackedFloat32Array:
	return _mix(_tone(0.6, 300, 80, "square", 1.2), _thud(), 1.0, int(RATE * 0.3))


func _rustle() -> PackedFloat32Array:
	var a := _buf(0.6)
	var n := a.size()
	var y := 0.0
	for k in n:
		var amp := 0.5 + 0.5 * sin(float(k) / RATE * TAU * 9.0)
		y += 0.25 * (rng.randf_range(-1, 1) - y)
		a[k] = y * amp * (1.0 if rng.randf() > 0.002 else 3.0)
	return a


func _drone(sec: float = 6.0) -> PackedFloat32Array:
	# 낮은 웅웅거림 + 바람(6초 주기에 맞춘 주파수, 이음매는 loop_xfade 가 지운다)
	var a := _buf(sec)
	var n := a.size()
	var y := 0.0
	for k in n:
		var t := float(k) / RATE
		var s := sin(t * TAU * 55.0) * 0.35 + sin(t * TAU * 55.5) * 0.3 + sin(t * TAU * 82.5) * 0.12
		y += 0.02 * (rng.randf_range(-1, 1) - y)
		var wind := y * (0.6 + 0.4 * sin(t * TAU / 6.0)) * 3.0
		a[k] = (s * 0.5 + wind) * 0.6
	return a


# ------------------------------------------------------------------ Synth.gd 조리법
func _fin(b: PackedFloat32Array, db: float = -16.0) -> AudioStreamWAV:
	S.dc_block(b)
	var o := S.trim(b)
	S.normalize(o, db, -1.0, true)
	return S.to_wav(o)


## 쇠파이프가 고철에 맞는 "콩": 판금 부분음 + 낮은 쿵 + 짧은 잡음 타격.
func _s_clonk(f: float, sd: int, len_k: float = 1.0) -> AudioStreamWAV:
	var b := S.buf(0.6 * len_k)
	var t := []
	for x in [0.35, 0.3, 0.26, 0.22, 0.18, 0.14, 0.11, 0.09]:
		t.append(x * len_k)
	S.modal(b, 0.0, f, 0.6, SHEET_R, SHEET_A, t, 0.001)
	S.thud(b, 0.0, 160.0, 60.0, 0.7, 0.12)
	S.noise(b, 0.0, 0.03, 0.5, 1, 3500.0, 1800.0, 1.5, sd, 0.0005, 0.02)
	S.room(b, 0.25, 0.12)
	return _fin(b, -14.0)


## 깡통이 굴러떨어지는 달그락(작은 타격 서너 번).
func _s_tin(sd: int) -> AudioStreamWAV:
	var b := S.buf(0.5)
	var r := S.Rng.new(sd)
	var tt := 0.0
	for k in 4:
		S.modal(b, tt, r.r(700.0, 950.0), 0.5 / (k + 1), TIN_R, TIN_A, [0.09, 0.06, 0.05, 0.04, 0.03], 0.0008)
		tt += r.r(0.05, 0.11) * (1.0 + k * 0.3)
	return _fin(b, -17.0)


func _s_wood(sd: int) -> AudioStreamWAV:
	var b := S.buf(0.3)
	S.modal(b, 0.0, 180.0 + sd * 7.0, 0.7, WOOD_R, WOOD_A, [0.12, 0.07, 0.04], 0.0008)
	S.thud(b, 0.0, 120.0, 50.0, 0.6, 0.1)
	S.noise(b, 0.0, 0.025, 0.3, 1, 1200.0, 900.0, 2.0, sd, 0.0005, 0.01)
	return _fin(b, -15.0)


## 들개 깨갱: 높게 올랐다 떨어지는 콧소리(떨림 포함) 두 번.
func _s_yelp(k: float) -> AudioStreamWAV:
	var b := S.buf(0.45)
	S.tone(b, 0.0, 0.16, 1250.0 * k, 820.0 * k, S.SAW, 0.4, 0.004, 0.05, 28.0, 0.04)
	S.tone(b, 0.2, 0.18, 1100.0 * k, 650.0 * k, S.SAW, 0.3, 0.004, 0.08, 24.0, 0.05)
	S.svf(b, 2200.0, 1.2, 1)
	return _fin(b, -17.0)


func _s_squeak(k: float) -> AudioStreamWAV:
	var b := S.buf(0.14)
	S.tone(b, 0.0, 0.11, 2600.0 * k, 3500.0 * k, S.TRI, 0.5, 0.003, 0.03, 40.0, 0.06)
	return _fin(b, -21.0)


## 만화 같은 "뽀잉" 쿵: 아래로 미끄러지는 사인 + 딸깍.
func _s_bonk() -> AudioStreamWAV:
	var b := S.buf(0.45)
	S.partial(b, 0.0, 900.0, 0.6, 0.35, 0.002, 280.0, 0.25)
	S.thud(b, 0.0, 200.0, 70.0, 0.6, 0.1)
	S.tick(b, 0.0, 0.5, 3000.0, 3)
	return _fin(b, -15.0)


func _s_puff() -> AudioStreamWAV:
	var b := S.buf(0.3)
	S.noise(b, 0.0, 0.28, 0.6, 1, 1800.0, 500.0, 0.9, 21, 0.004, 0.18)
	S.partial(b, 0.0, 520.0, 0.3, 0.06, 0.001, 900.0, 0.05)
	return _fin(b, -18.0)


## 압축기 유압: 쉬익 하는 띠 잡음 훑기 + 낮은 펌프 웅.
func _s_hydraulic() -> AudioStreamWAV:
	var b := S.buf(0.9)
	S.noise(b, 0.0, 0.8, 0.5, 1, 1800.0, 3200.0, 2.5, 31, 0.08, 1.2, 0.3)
	S.tone(b, 0.0, 0.8, 55.0, 75.0, S.SAW, 0.35, 0.1, 0.2)
	S.lp1(b, 4000.0)
	return _fin(b, -18.0)


func _s_stomp() -> AudioStreamWAV:
	var b := S.buf(1.0)
	S.thud(b, 0.0, 110.0, 32.0, 1.0, 0.5)
	S.noise(b, 0.0, 0.5, 0.7, 0, 1600.0, 200.0, 0.7, 41, 0.001, 0.35)
	S.modal(b, 0.01, 120.0, 0.4, SHEET_R, SHEET_A, [0.6, 0.5, 0.4, 0.35, 0.3, 0.25, 0.2, 0.15], 0.002)
	S.room(b, 0.6, 0.25)
	return _fin(b, -12.0)


## 큰형 등장 포효: 쇠 긁히는 톱니파 두 겹이 내려가며 떨림 + 유압.
func _s_roar() -> AudioStreamWAV:
	var b := S.buf(1.6)
	S.tone(b, 0.0, 1.3, 140.0, 70.0, S.SAW, 0.5, 0.1, 0.4, 9.0, 0.06)
	S.tone(b, 0.0, 1.3, 211.0, 97.0, S.SQUARE, 0.25, 0.1, 0.4, 7.0, 0.05)
	S.noise(b, 0.0, 1.4, 0.4, 1, 700.0, 300.0, 1.2, 51, 0.15, 1.6, 0.5)
	S.lp1(b, 2500.0)
	S.room(b, 0.7, 0.3)
	S.softclip(b, 1.5)
	return _fin(b, -12.0)


func _s_siren() -> AudioStreamWAV:
	var b := S.buf(1.6)
	for k in 2:
		S.tone(b, k * 0.8, 0.4, 650.0, 950.0, S.TRI, 0.4, 0.02, 0.02)
		S.tone(b, k * 0.8 + 0.4, 0.4, 950.0, 650.0, S.TRI, 0.4, 0.02, 0.05)
	S.echo(b, 0.18, 0.3, 0.3)
	return _fin(b, -17.0)


## 투광등 켜짐: 큰 스위치 탁 + 웅 올라오는 소리.
func _s_flood() -> AudioStreamWAV:
	var b := S.buf(1.0)
	S.tick(b, 0.0, 0.8, 1500.0, 61, 0.02)
	S.thud(b, 0.0, 180.0, 60.0, 0.5, 0.08)
	S.tone(b, 0.05, 0.9, 60.0, 120.0, S.SAW, 0.25, 0.3, 0.3)
	S.lp1(b, 1800.0)
	return _fin(b, -18.0)


func _s_whoosh(sd: int) -> AudioStreamWAV:
	var b := S.buf(0.2)
	S.noise(b, 0.0, 0.18, 0.6, 1, 700.0, 3200.0, 1.6, sd, 0.05, 0.25, 0.04)
	return _fin(b, -20.0)
