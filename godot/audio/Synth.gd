extends RefCounted
## Synth — 코드로 소리를 만드는 작은 공구함. 음원 파일 없음, 내려받기 없음.
## 모든 것은 PackedFloat32Array(모노, -1..1, SR Hz) 위에서 돈다. 잡음은 씨앗(seed)으로 정해져 늘 같은 소리가 나온다.
## - 소리 조각: partial(사인 + 지수 감쇠) · modal(여러 부분음 = 나무·쇠·깡통) · tone(파형 + 음높이 미끄럼) · fm(종)
##   · noise(잡음 + 상태변수 필터, 고정/훑기) · thud(음높이가 떨어지는 쿵) · tick(아주 짧은 딸깍)
## - 버퍼 효과: lp1 · hp1 · svf · echo · room(작은 슈뢰더 잔향) · softclip · fades · trim
## - 크기: peak · rms · short_rms(가장 시끄러운 50 ms) · normalize
## - 내보내기: to_wav(16비트, 모노/의사 스테레오, 루프) · loop_xfade(끝→처음 이음매 없애기)
## 규칙: 게임 상태를 읽지 않는다. 스레드 없음(웹).

const SR := 22050
const INV_SR := 1.0 / 22050.0
## 지금 만드는 표본율(기본 22050). 먼 배경 소리는 11025 로 만들어 반값에 짓는다(set_rate).
static var R_: float = 22050.0
static var INV_R: float = 1.0 / 22050.0


static func set_rate(r: float) -> void:
	R_ = r
	INV_R = 1.0 / r

const LCG_M := 2147483647
const LCG_A := 48271
const INV_M2 := 2.0 / 2147483647.0

enum { SINE, TRI, SQUARE, SAW }


## 정해진 난수(MINSTD). 같은 씨앗 → 같은 수열.
class Rng:
	var s: int = 1

	func _init(seed_value: int = 1) -> void:
		s = absi(seed_value * 7919 + 104729) % 2147483647
		if s == 0:
			s = 1

	func f() -> float:
		s = (s * 48271) % 2147483647
		return float(s) / 2147483647.0

	## -1..1
	func n() -> float:
		s = (s * 48271) % 2147483647
		return float(s) * (2.0 / 2147483647.0) - 1.0

	func r(a: float, b: float) -> float:
		return a + (b - a) * f()

	func i(a: int, b: int) -> int:  # a..b 포함
		return a + int(f() * float(b - a + 1)) % (b - a + 1)

	func pick(arr: Array) -> Variant:
		return arr[int(f() * arr.size()) % arr.size()]


static func buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(1, int(sec * R_)))
	return b


static func secs(b: PackedFloat32Array) -> float:
	return float(b.size()) * INV_R


# ------------------------------------------------------------------ 소리 조각

## 사인 부분음: t0초에 시작, attack 초 동안 선형으로 올라 t60 초에 -60 dB 로 지수 감쇠.
## f_end > 0 이면 감쇠 동안 지수적으로 음높이가 미끄러진다(glide 초 동안).
static func partial(out: PackedFloat32Array, t0: float, f: float, amp: float, t60: float,
		attack: float = 0.002, f_end: float = -1.0, glide: float = 0.0, phase: float = 0.0) -> void:
	var i0 := int(t0 * R_)
	var n := mini(int((t60 + attack) * R_), out.size() - i0)
	if n <= 0 or f <= 0.0 or f >= R_ * 0.48 or f_end >= R_ * 0.48:   # 나이퀴스트 넘는 부분음은 버린다(접힘 방지)
		return
	var na := mini(n, maxi(1, int(attack * R_)))
	var dec := pow(0.001, 1.0 / maxf(1.0, t60 * R_))   # 표본당 감쇠
	var ph := phase
	var w := TAU * f * INV_R
	if f_end <= 0.0:
		# 고정 음높이: 회전 페이저(곱셈 넷)로 sin 호출 없이. 감쇠도 페이저 크기에 곱한다.
		var c := cos(ph) * amp
		var sn := sin(ph) * amp
		var cr := cos(w)
		var sr_ := sin(w)
		var inv_na := 1.0 / float(na)
		for k in na:
			out[i0 + k] += sn * float(k) * inv_na
			var nc := (c * cr - sn * sr_) * dec
			sn = (c * sr_ + sn * cr) * dec
			c = nc
		var cd := cr * dec
		var sd := sr_ * dec
		for k in range(na, n):
			out[i0 + k] += sn
			var nc2 := c * cd - sn * sd
			sn = c * sd + sn * cd
			c = nc2
		return
	var gl_n := maxi(1, int((glide if glide > 0.0 else t60) * R_))
	var wk := pow(f_end / f, 1.0 / float(gl_n))
	var e := amp
	for k in n:
		var a := e if k >= na else e * float(k) / float(na)
		out[i0 + k] += a * sin(ph)
		ph += w
		if k < gl_n:
			w *= wk
		e *= dec


## 여러 부분음 묶음(나무·쇠·깡통). ratios·amps·t60s 는 같은 길이.
static func modal(out: PackedFloat32Array, t0: float, f: float, amp: float, ratios: Array, amps: Array, t60s: Array, attack: float = 0.001) -> void:
	for j in ratios.size():
		partial(out, t0, f * float(ratios[j]), amp * float(amps[j]), float(t60s[j]), attack, -1.0, 0.0, float(j) * 1.3)


## 파형 + 음높이 미끄럼(지수) + 사다리꼴 외피(attack, hold, release). 단순 파형은 띠가 제한되지 않으니 높은 음에는 lp 를 따로 건다.
static func tone(out: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float, shape: int, amp: float,
		attack: float = 0.005, release: float = 0.05, vib_hz: float = 0.0, vib_depth: float = 0.0) -> void:
	var i0 := int(t0 * R_)
	var n := mini(int(dur * R_), out.size() - i0)
	if n <= 0:
		return
	var na := maxi(1, int(attack * R_))
	var nr := maxi(1, int(release * R_))
	var ph := 0.0
	var fk := pow(f1 / f0, 1.0 / float(n))
	var inc := f0 * INV_R
	var vw := TAU * vib_hz * INV_R
	var vib := vib_hz > 0.0 and vib_depth > 0.0
	for k in n:
		var a := amp
		if k < na:
			a *= float(k) / float(na)
		elif k > n - nr:
			a *= float(n - k) / float(nr)
		ph += inc * (1.0 + vib_depth * sin(vw * float(k))) if vib else inc
		inc *= fk
		if ph >= 1.0:
			ph -= 1.0
		var v: float
		if shape == SINE:
			v = sin(TAU * ph)
		elif shape == TRI:
			v = 4.0 * absf(ph - 0.5) - 1.0
		elif shape == SQUARE:
			v = 1.0 if ph < 0.5 else -1.0
		else:
			v = 2.0 * ph - 1.0
		out[i0 + k] += a * v


## FM 종: 운반파 fc, 변조파 fc*ratio, 변조 깊이 index0 → index1 로 줄어듦, t60 감쇠.
static func fm(out: PackedFloat32Array, t0: float, fc: float, ratio: float, index0: float, index1: float, amp: float, t60: float, attack: float = 0.002) -> void:
	var i0 := int(t0 * R_)
	var n := mini(int((t60 + attack) * R_), out.size() - i0)
	if n <= 0:
		return
	var na := maxi(1, int(attack * R_))
	var dec := pow(0.001, 1.0 / maxf(1.0, t60 * R_))
	var dec_i := pow(maxf(index1, 0.0001) / maxf(index0, 0.0001), 1.0 / float(n))
	var e := 1.0
	var idx := index0
	var wc := TAU * fc * INV_R
	var wm := wc * ratio
	for k in n:
		var a := e if k >= na else e * float(k) / float(na)
		out[i0 + k] += amp * a * sin(wc * float(k) + idx * sin(wm * float(k)))
		e *= dec
		idx *= dec_i


## 쿵: 음높이가 f0 → f1 로 빨리 떨어지는 사인(북·널빤지·발구름).
static func thud(out: PackedFloat32Array, t0: float, f0: float, f1: float, amp: float, t60: float) -> void:
	partial(out, t0, f0, amp, t60, 0.001, f1, minf(0.06, t60 * 0.5))


## 잡음 + 상태변수 필터. mode 0=LP 1=BP 2=HP. f0→f1 훑기(지수). 외피: attack 선형, 그다음 t60 지수 감쇠,
## hold 초 동안은 감쇠 없이 유지. dur = 전체 길이 상한.
static func noise(out: PackedFloat32Array, t0: float, dur: float, amp: float, mode: int, f0: float, f1: float, q: float,
		seed_value: int, attack: float = 0.001, t60: float = 1.0, hold: float = 0.0) -> void:
	var i0 := int(t0 * R_)
	var n := mini(int(dur * R_), out.size() - i0)
	if n <= 0:
		return
	var s := absi(seed_value * 7919 + 104729) % LCG_M
	if s == 0:
		s = 1
	var na := maxi(1, int(attack * R_))
	var nh := int(hold * R_)
	var dec := pow(0.001, 1.0 / maxf(1.0, t60 * R_))
	var e := 1.0
	var ic1 := 0.0
	var ic2 := 0.0
	var k_ := 1.0 / maxf(0.3, q)
	var lf := log(f1 / f0) / float(n)
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	for k in n:
		if (k & 15) == 0:
			var fc := minf(f0 * exp(lf * float(k)), R_ * 0.45)
			var g := tan(PI * fc * INV_R)
			a1 = 1.0 / (1.0 + g * (g + k_))
			a2 = g * a1
			a3 = g * a2
		s = (s * LCG_A) % LCG_M
		var x := float(s) * INV_M2 - 1.0
		var v3 := x - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		var y := v2
		if mode == 1:
			y = v1 * k_ * 1.4
		elif mode == 2:
			y = x - k_ * v1 - v2
		var a := e
		if k < na:
			a = float(k) / float(na)
		elif k >= na + nh:
			e *= dec
		out[i0 + k] += amp * a * y


## 아주 짧은 딸깍(나무·플라스틱·사기). bright: 띠 가운데 Hz.
static func tick(out: PackedFloat32Array, t0: float, amp: float, bright: float, seed_value: int, len_s: float = 0.012) -> void:
	noise(out, t0, len_s * 2.0, amp, 1, bright, bright * 0.8, 3.0, seed_value, 0.0005, len_s)
	partial(out, t0, bright * 0.5, amp * 0.5, len_s * 1.5, 0.0005)


# ------------------------------------------------------------------ 버퍼 효과

static func lp1(b: PackedFloat32Array, hz: float, sr: float = -1.0) -> void:
	if sr <= 0.0:
		sr = R_
	var a := 1.0 - exp(-TAU * hz / sr)
	var y := 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = y


## 루프용 낮은 통과: 한 바퀴 미리 돌려 끝 상태로 시작한다 → 끝→처음 이음매가 그대로 이어진다.
static func lp1_loop(b: PackedFloat32Array, hz: float, sr: float = -1.0) -> void:
	if sr <= 0.0:
		sr = R_
	var a := 1.0 - exp(-TAU * hz / sr)
	var y := 0.0
	for x in b:
		y += a * (x - y)
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = y


static func hp1(b: PackedFloat32Array, hz: float, sr: float = -1.0) -> void:
	if sr <= 0.0:
		sr = R_
	var a := 1.0 - exp(-TAU * hz / sr)
	var y := 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = b[i] - y


## 상태변수 필터(고정). mode 0=LP 1=BP 2=HP.
static func svf(b: PackedFloat32Array, hz: float, q: float, mode: int) -> void:
	var g := tan(PI * minf(hz, R_ * 0.45) * INV_R)
	var k_ := 1.0 / maxf(0.3, q)
	var a1 := 1.0 / (1.0 + g * (g + k_))
	var a2 := g * a1
	var a3 := g * a2
	var ic1 := 0.0
	var ic2 := 0.0
	for i in b.size():
		var x := b[i]
		var v3 := x - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		b[i] = v2 if mode == 0 else (v1 * k_ if mode == 1 else x - k_ * v1 - v2)


## 메아리(골목 벽에 한 번 두 번 튕김).
static func echo(b: PackedFloat32Array, time: float, fb: float, mix: float, sr: float = -1.0) -> void:
	if sr <= 0.0:
		sr = R_
	var d := maxi(1, int(time * sr))
	var line := PackedFloat32Array()
	line.resize(d)
	var p := 0
	var y := 0.0
	for i in b.size():
		var dl := line[p]
		y += 0.45 * (dl - y)   # 되돌아오는 소리는 무디게
		line[p] = b[i] + y * fb
		b[i] += y * mix
		p = (p + 1) % d


## 작은 방 잔향(슈뢰더: 빗살 4 + 올패스 2). size 0..1, damp 0..1.
static func room(b: PackedFloat32Array, size: float, mix: float, damp: float = 0.4) -> void:
	# 잔향 꼬리는 높은 소리가 필요 없다 → 반 표본율로 줄여(짝 평균) 빗살 넷 + 올패스 하나를 한 번 훑고, 선형으로 늘려 더한다.
	var n := b.size()
	var hn := n / 2 + 1
	var h := PackedFloat32Array()
	h.resize(hn + 1)
	for i in n / 2:
		h[i] = 0.5 * (b[2 * i] + b[2 * i + 1])
	var hr := R_ * 0.5
	var sc := (0.35 + 0.6 * size) * hr / 44100.0   # 원 수치는 44.1 kHz 기준
	var fb := 0.70 + 0.25 * size
	var d0 := maxi(4, int(1116.0 * sc))
	var d1 := maxi(4, int(1188.0 * sc))
	var d2 := maxi(4, int(1277.0 * sc))
	var d3 := maxi(4, int(1356.0 * sc))
	var l0 := PackedFloat32Array()
	l0.resize(d0)
	var l1 := PackedFloat32Array()
	l1.resize(d1)
	var l2 := PackedFloat32Array()
	l2.resize(d2)
	var l3 := PackedFloat32Array()
	l3.resize(d3)
	var da := maxi(4, int(70.0 * hr / 11025.0))
	var la := PackedFloat32Array()
	la.resize(da)
	var p0 := 0
	var p1 := 0
	var p2 := 0
	var p3 := 0
	var pa := 0
	var z0 := 0.0
	var z1 := 0.0
	var z2 := 0.0
	var z3 := 0.0
	var dm := 1.0 - damp
	for i in hn:
		var x := h[i]
		var o0 := l0[p0]
		var o1 := l1[p1]
		var o2 := l2[p2]
		var o3 := l3[p3]
		z0 = o0 * dm + z0 * damp
		z1 = o1 * dm + z1 * damp
		z2 = o2 * dm + z2 * damp
		z3 = o3 * dm + z3 * damp
		l0[p0] = x + z0 * fb
		l1[p1] = x + z1 * fb
		l2[p2] = x + z2 * fb
		l3[p3] = x + z3 * fb
		p0 += 1
		if p0 >= d0:
			p0 = 0
		p1 += 1
		if p1 >= d1:
			p1 = 0
		p2 += 1
		if p2 >= d2:
			p2 = 0
		p3 += 1
		if p3 >= d3:
			p3 = 0
		var wv := (o0 + o1 + o2 + o3) * 0.25
		var bo := la[pa]
		la[pa] = wv + bo * 0.5
		pa += 1
		if pa >= da:
			pa = 0
		h[i] = (bo - wv) * mix
	for i in n:
		var j := i >> 1
		b[i] += h[j] if (i & 1) == 0 else 0.5 * (h[j] + h[j + 1])


static func softclip(b: PackedFloat32Array, drive: float = 1.0) -> void:
	var inv := 1.0 / tanh(drive)
	for i in b.size():
		b[i] = tanh(b[i] * drive) * inv


static func gain(b: PackedFloat32Array, g: float) -> void:
	for i in b.size():
		b[i] *= g


static func fade_in(b: PackedFloat32Array, sec: float) -> void:
	var n := mini(b.size(), int(sec * R_))
	for i in n:
		b[i] *= float(i) / float(n)


static func fade_out(b: PackedFloat32Array, sec: float) -> void:
	var n := mini(b.size(), int(sec * R_))
	var s0 := b.size() - n
	for i in n:
		b[s0 + i] *= float(n - i) / float(n)


## 끝의 조용한 꼬리를 자르고(-66 dB 아래) 마지막 10 ms 를 줄여 끝낸다.
static func trim(b: PackedFloat32Array, floor_db: float = -66.0) -> PackedFloat32Array:
	var th := db_to_linear(floor_db) * maxf(peak(b), 1e-6)
	var last := b.size() - 1
	while last > 0 and absf(b[last]) < th:
		last -= 1
	var n := mini(b.size(), last + int(0.01 * R_) + 1)
	var o := b.slice(0, n)
	fade_out(o, 0.01)
	return o


## 직류 성분 빼기(잡음 쿵이 가끔 한쪽으로 치우친다).
static func dc_block(b: PackedFloat32Array) -> void:
	var x1 := 0.0
	var y1 := 0.0
	for i in b.size():
		var x := b[i]
		var y := x - x1 + 0.995 * y1
		x1 = x
		y1 = y
		b[i] = y


static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, t0: float, g: float = 1.0) -> void:
	var i0 := int(t0 * R_)
	var n := mini(src.size(), dst.size() - i0)
	for i in n:
		dst[i0 + i] += src[i] * g


## 반 표본율로 만든 src 를 dst 에 두 배로 늘려(선형) 더한다. 낮은 소리를 반값에 만들 때.
static func mix_up2(dst: PackedFloat32Array, src: PackedFloat32Array, g: float = 1.0) -> void:
	var n := mini(dst.size(), src.size() * 2 - 1)
	for i in n:
		var j := i >> 1
		dst[i] += g * (src[j] if (i & 1) == 0 else 0.5 * (src[j] + src[j + 1]))


# ------------------------------------------------------------------ 크기

static func peak(b: PackedFloat32Array) -> float:
	var m := 0.0
	for x in b:
		m = maxf(m, absf(x))
	return m


## 루프 꼬리 접기: 길이 L + tail 버퍼에서 tail 을 처음으로 더한다(사건형 루프는 이것만으로 이음매가 없다).
static func fold(b: PackedFloat32Array, length: int) -> PackedFloat32Array:
	for i in range(length, b.size()):
		b[i % length] += b[i]
	return b.slice(0, length)


static func rms(b: PackedFloat32Array) -> float:
	if b.is_empty():
		return 0.0
	var s := 0.0
	for x in b:
		s += x * x
	return sqrt(s / float(b.size()))


## 가장 시끄러운 50 ms 창의 RMS(짧은 소리의 '들리는 크기' 대용).
static func short_rms(b: PackedFloat32Array, win_s: float = 0.05) -> float:
	var w := maxi(1, mini(b.size(), int(win_s * R_)))
	var s := 0.0
	for i in w:
		s += b[i] * b[i]
	var best := s
	for i in range(w, b.size()):
		s += b[i] * b[i] - b[i - w] * b[i - w]
		best = maxf(best, s)
	return sqrt(maxf(best, 0.0) / float(w))


## 귀에 가까운 크기(대충 K 가중): 100 Hz 아래 깎기(2단) + 1.7 kHz 위 +4 dB 선반 → 가장 시끄러운 50 ms RMS.
## 낮은 쿵과 높은 딸깍을 같은 '들리는 크기'로 맞추려고 쓴다.
static func k_short_rms(b: PackedFloat32Array) -> float:
	var c := b.duplicate()
	hp1(c, 100.0)
	hp1(c, 100.0)
	var a := 1.0 - exp(-TAU * 1700.0 * INV_R)
	var y := 0.0
	for i in c.size():
		y += a * (c[i] - y)
		c[i] += 0.58 * (c[i] - y)
	return short_rms(c)


## 짧은 RMS 를 target_db 에 맞추고, 봉우리가 peak_db 를 넘으면 부드럽게 눌러 맞춘다.
static func normalize(b: PackedFloat32Array, target_db: float, peak_db: float = -1.0, k_weighted: bool = false) -> void:
	var r := k_short_rms(b) if k_weighted else short_rms(b)
	if r < 1e-7:
		return
	var g := db_to_linear(target_db) / r
	var p := 0.0
	for i in b.size():
		var x := b[i] * g
		b[i] = x
		p = maxf(p, absf(x))
	var lim := db_to_linear(peak_db)
	if p > lim:
		# 봉우리만 둥글게: tanh 무릎. 무릎 아래는 거의 그대로.
		var knee := lim * 0.7
		for i in b.size():
			var x := b[i]
			var ax := absf(x)
			if ax > knee:
				var over := (ax - knee) / (lim - knee)
				b[i] = signf(x) * (knee + (lim - knee) * tanh(over))


# ------------------------------------------------------------------ 루프 · 내보내기

## buf 길이가 L + X 일 때: 꼬리 X 표본을 처음 X 표본 위로 교차해 L 길이 이음매 없는 루프를 만든다.
## 결과[L-1] 다음에 결과[0] 이 오면 원래 buf[L-1] → buf[L] 과 같은 흐름이다.
static func loop_xfade(b: PackedFloat32Array, length: int, x: int) -> PackedFloat32Array:
	var o := b.slice(0, length)
	var xx := mini(x, b.size() - length)
	for i in xx:
		var t := float(i) / float(xx)
		var gi := sin(t * PI * 0.5)       # 같은 힘 교차(잡음끼리는 상관이 없으니 등전력)
		var go := cos(t * PI * 0.5)
		o[i] = b[i] * gi + b[length + i] * go
	return o


## 16비트 WAV. stereo_delay > 0 이면 오른쪽을 그만큼(표본) 늦춘 의사 스테레오(루프면 감아 돈다).
static func to_wav(b: PackedFloat32Array, loop: bool = false, stereo_delay: int = 0, rate: int = -1) -> AudioStreamWAV:
	if rate <= 0:
		rate = int(R_)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	var n := b.size()
	var bytes := PackedByteArray()
	if stereo_delay > 0:
		w.stereo = true
		bytes.resize(n * 4)
		for i in n:
			var j := i - stereo_delay
			if j < 0:
				j = (j + n) if loop else -1
			var r := b[j] if j >= 0 else 0.0
			bytes.encode_s16(i * 4, int(clampf(b[i], -1.0, 1.0) * 32767.0))
			bytes.encode_s16(i * 4 + 2, int(clampf(r, -1.0, 1.0) * 32767.0))
	else:
		bytes.resize(n * 2)
		for i in n:
			bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


## 분석·검사용 WAV 파일 쓰기(모노 16비트).
static func save_wav(b: PackedFloat32Array, path: String, rate: int = -1) -> void:
	if rate <= 0:
		rate = int(R_)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var n := b.size()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(rate)
	f.store_32(rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 2)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	f.store_buffer(bytes)
	f.close()
