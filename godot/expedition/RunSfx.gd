extends Node
## 코드로 합성한 효과음(음원 파일 없음). 처음 한 번 만들어 두고 재생기 여러 개로 돌려 쓴다.
## M 키로 끄고 켠다(RunSandbox). 헤드리스에서는 만들지 않는다.

const RATE := 22050

var streams: Dictionary = {}
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
	search_player = AudioStreamPlayer.new()
	var ss := _wav(_rustle())
	ss.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ss.loop_end = int(RATE * 0.6)
	search_player.stream = ss
	search_player.volume_db = -14.0
	add_child(search_player)
	ambient = AudioStreamPlayer.new()
	var amb := _wav(_drone())
	amb.loop_mode = AudioStreamWAV.LOOP_FORWARD
	amb.loop_end = int(RATE * 6.0)
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
	p.stream = streams[id]
	p.volume_db = VOL.get(id, -8.0)
	p.pitch_scale = rng.randf_range(0.93, 1.07)
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


func _drone() -> PackedFloat32Array:
	# 낮은 웅웅거림 + 바람(6초, 끊김 없이 돌게 주파수를 6초에 맞춘다)
	var a := _buf(6.0)
	var n := a.size()
	var y := 0.0
	for k in n:
		var t := float(k) / RATE
		var s := sin(t * TAU * 55.0) * 0.35 + sin(t * TAU * 55.5) * 0.3 + sin(t * TAU * 82.5) * 0.12
		y += 0.02 * (rng.randf_range(-1, 1) - y)
		var wind := y * (0.6 + 0.4 * sin(t * TAU / 6.0)) * 3.0
		a[k] = (s * 0.5 + wind) * 0.6
	return a
