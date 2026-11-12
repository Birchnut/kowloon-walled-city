extends RefCounted
## AudioAnalyze — 귀 대신 숫자. 봉우리·RMS·짧은 RMS·길이·스펙트럼 무게중심·올라가는/줄어드는 시간·루프 이음매.
## 검사(audio_test.gd)와 샌드박스가 쓴다. 게임에서는 쓰지 않는다.

const S := preload("res://audio/Synth.gd")


static func _fft(re: PackedFloat64Array, im: PackedFloat64Array) -> void:
	var n := re.size()
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j ^= bit
		if i < j:
			var t := re[i]
			re[i] = re[j]
			re[j] = t
			t = im[i]
			im[i] = im[j]
			im[j] = t
	var size := 2
	while size <= n:
		var ang := -TAU / float(size)
		var wr := cos(ang)
		var wi := sin(ang)
		var half := size >> 1
		var st := 0
		while st < n:
			var cr := 1.0
			var ci := 0.0
			for k in half:
				var a := st + k
				var b := a + half
				var tr := re[b] * cr - im[b] * ci
				var ti := re[b] * ci + im[b] * cr
				re[b] = re[a] - tr
				im[b] = im[a] - ti
				re[a] += tr
				im[a] += ti
				var ncr := cr * wr - ci * wi
				ci = cr * wi + ci * wr
				cr = ncr
			st += size
		size <<= 1


## 에너지로 무게를 준 평균 스펙트럼 무게중심(Hz)과 85% 굴림점(Hz).
static func spectrum(b: PackedFloat32Array, sr: float) -> Dictionary:
	var N := 1024
	var hop := 512
	var num := 0.0
	var den := 0.0
	var acc := PackedFloat64Array()
	acc.resize(N / 2)
	var frames := 0
	var i0 := 0
	var maxframes := 200
	var step := maxi(hop, (b.size() - N) / maxframes)
	while i0 + N <= b.size() or (i0 == 0 and b.size() > 0):
		var re := PackedFloat64Array()
		re.resize(N)
		var im := PackedFloat64Array()
		im.resize(N)
		for k in N:
			var x := b[i0 + k] if i0 + k < b.size() else 0.0
			re[k] = x * (0.5 - 0.5 * cos(TAU * float(k) / float(N)))
		_fft(re, im)
		for k in N / 2:
			var m := re[k] * re[k] + im[k] * im[k]
			acc[k] += m
			num += m * float(k) * sr / float(N)
			den += m
		frames += 1
		i0 += step
		if i0 + N > b.size():
			break
	var tot := 0.0
	for k in N / 2:
		tot += acc[k]
	var run := 0.0
	var roll := 0.0
	for k in N / 2:
		run += acc[k]
		if run >= 0.85 * tot:
			roll = float(k) * sr / float(N)
			break
	return {"centroid": num / maxf(den, 1e-12), "rolloff85": roll}


## 5 ms 창 RMS 외피에서: 봉우리까지 시간(ms), 봉우리에서 -20 dB 까지(ms).
static func envelope(b: PackedFloat32Array, sr: float) -> Dictionary:
	var w := maxi(1, int(0.005 * sr))
	var env := PackedFloat32Array()
	var i := 0
	while i < b.size():
		var s := 0.0
		var n := mini(w, b.size() - i)
		for k in n:
			s += b[i + k] * b[i + k]
		env.append(sqrt(s / float(n)))
		i += w
	var pk := 0
	for k in env.size():
		if env[k] > env[pk]:
			pk = k
	var th := env[pk] * 0.1
	var dk := env.size() - 1
	for k in range(pk, env.size()):
		if env[k] < th:
			dk = k
			break
	return {"attack_ms": pk * 5.0, "decay20_ms": (dk - pk) * 5.0}


static func has_nan(b: PackedFloat32Array) -> bool:
	for x in b:
		if is_nan(x) or is_inf(x):
			return true
	return false


static func dc(b: PackedFloat32Array) -> float:
	var s := 0.0
	for x in b:
		s += x
	return s / maxf(1.0, float(b.size()))


## 루프 이음매: 끝→처음 한 걸음의 크기를 보통 한 걸음(|차이| 99번째 백분위)과 비교.
## 또 끝 50 ms 와 처음 50 ms 의 RMS 차(dB)로 외피가 맞는지 본다.
static func loop_seam(b: PackedFloat32Array, sr: float) -> Dictionary:
	var n := b.size()
	var d := PackedFloat32Array()
	d.resize(n - 1)
	for i in n - 1:
		d[i] = absf(b[i + 1] - b[i])
	var sorted := d.duplicate()
	sorted.sort()
	var p99 := sorted[int(0.99 * float(sorted.size() - 1))]
	var jump := absf(b[0] - b[n - 1])
	var w := int(0.05 * sr)
	var head := b.slice(0, w)
	var tail := b.slice(n - w, n)
	var rh := S.rms(head)
	var rt := S.rms(tail)
	return {"jump": jump, "p99": p99, "ratio": jump / maxf(p99, 1e-9),
		"edge_db": absf(linear_to_db(maxf(rh, 1e-9)) - linear_to_db(maxf(rt, 1e-9)))}


static func row(b: PackedFloat32Array, sr: float) -> Dictionary:
	var sp := spectrum(b, sr)
	var en := envelope(b, sr)
	return {"len_s": float(b.size()) / sr, "peak_db": linear_to_db(maxf(S.peak(b), 1e-9)), "rms_db": linear_to_db(maxf(S.rms(b), 1e-9)),
		"srms_db": linear_to_db(maxf(S.short_rms(b, 0.05 * sr / S.R_), 1e-9)), "k_db": _k_db(b, sr), "centroid": sp["centroid"], "rolloff": sp["rolloff85"],
		"attack_ms": en["attack_ms"], "decay20_ms": en["decay20_ms"], "nan": has_nan(b), "dc": dc(b)}


## 이 스레드(메인)가 쓴 CPU 시간(ms). 리눅스만(/proc/thread-self/schedstat, ns 단위), 아니면 -1.
## 다른 프로그램과 CPU 를 나눠 써도(빼앗긴 시간은 빠진다) 흔들리지 않는다.
static func cpu_ms() -> float:
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f == null:
		return -1.0
	var line := f.get_line()   # /proc 파일은 크기가 0 이라 get_as_text 가 비어 온다
	f.close()
	var parts := line.split(" ")
	if parts.is_empty():
		return -1.0
	return float(parts[0]) / 1.0e6


static func _k_db(b: PackedFloat32Array, sr: float) -> float:
	var old := S.R_
	S.set_rate(sr)
	var r := S.k_short_rms(b)
	S.set_rate(old)
	return linear_to_db(maxf(r, 1e-9))
