extends RefCounted
## AmbienceBank — 성채의 배경 소리. 루프 층(이음매 없음)과 가끔 울리는 한 번짜리 소리.
## 루프 두 갈래:
##   잡음 바닥(웅웅·바람·웅성·불·비): 길이 L + X 를 그린 뒤 꼬리 X 를 머리에 교차(Synth.loop_xfade).
##     느린 흔들림(LFO)은 모두 L 안에 정수 번 돌아서 교차 구간에서도 모양이 맞는다. 주기음(50 Hz 전기 웅웅)은 교차 뒤에 더한다.
##   사건 모음(장터 달그락·귀뚜라미·빗방울): 사건을 L 안에 흩고 넘친 꼬리를 앞으로 접는다(Synth.fold) — 그 자체로 이음매 없음.
## 긴 루프는 코루틴: 4096 표본마다 bud.over() 를 보고 넘치면 다음 프레임으로 넘긴다(웹에서 끊김 방지).

const S := preload("res://audio/Synth.gd")
const SR := 22050
const LOOP_TARGET_DB := -22.0


## 프레임 예산. tree 가 없으면(헤드리스 검사) 쉬지 않고 한 번에 만든다.
class Budget:
	var deadline: int = 0
	var ms: float = 4.0
	var tree: SceneTree = null
	var frames: int = 0
	var busy_us: int = 0      # 실제로 일한 시간(기다린 프레임 제외)
	var seg: int = 0
	var max_seg_us: int = 0   # 한 프레임에 가장 오래 붙잡은 시간(끊김 크기)
	var max_seg_at: String = ""
	var label: String = ""    # 지금 만드는 것(끊김 범인 찾기용)
	var cpu_probe: bool = false   # 리눅스에서 프레임마다 메인 스레드 CPU 도 잰다(검사용, KOWLOON_AUDIO_PROBE=1)
	var cpu_seg: float = 0.0
	var max_cpu_ms: float = 0.0
	var max_cpu_at: String = ""

	func start() -> void:
		seg = Time.get_ticks_usec()
		deadline = seg + int(ms * 1000.0)
		if cpu_probe:
			cpu_seg = _cpu()

	static func _cpu() -> float:
		var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
		if f == null:
			return 0.0
		var l := f.get_line()
		f.close()
		return float(l.split(" ")[0]) / 1.0e6

	func end_seg() -> void:
		var d := Time.get_ticks_usec() - seg
		busy_us += d
		if d > max_seg_us:
			max_seg_us = d
			max_seg_at = label
		if cpu_probe:
			var c := _cpu() - cpu_seg
			if c > max_cpu_ms:
				max_cpu_ms = c
				max_cpu_at = label

	func busy_now() -> int:
		return busy_us + Time.get_ticks_usec() - seg

	func over() -> bool:
		return tree != null and Time.get_ticks_usec() > deadline

	func wait() -> void:
		frames += 1
		end_seg()
		await tree.process_frame
		start()


## 루프 이름 → [만드는 함수, 표본율, 스테레오 지연(표본)]
const LOOPS := {
	"hum": ["_hum", 11025, 130],
	"wind": ["_wind", 11025, 165],
	"murmur": ["_murmur", 11025, 140],
	"market": ["_market", 11025, 120],
	"crickets": ["_crickets", 11025, 198],
	"fire": ["_firebed", 11025, 90],
	"rain": ["_rain", 11025, 143],
}

## 한 번짜리 이름 → 변주 수, 기본 이득 dB
const SHOTS := {
	"bird": [3, -14.0],
	"pigeon": [2, -12.0],
	"dog": [2, -13.0],
	"bell": [2, -15.0],
	"kettle": [1, -20.0],
	"mahjong": [2, -14.0],
	"radio": [2, -17.0],
	"hammer": [2, -13.0],
	"horn": [1, -14.0],
	"drip": [3, -16.0],
	"wok": [2, -15.0],
	"shutter": [1, -14.0],
}


static func build_loop(loop_name: String, bud: Budget) -> PackedFloat32Array:
	var b: PackedFloat32Array
	match loop_name:
		"hum":
			b = await _hum(bud)
		"wind":
			b = await _wind(bud)
		"murmur":
			b = await _murmur(bud)
		"market":
			b = await _market(bud)
		"crickets":
			b = await _crickets(bud)
		"fire":
			b = await _firebed(bud)
		"rain":
			b = await _rain(bud)
	if bud.over():
		await bud.wait()
	_norm_rms(b, LOOP_TARGET_DB)
	return b


## 쉼표: 예산을 넘었으면 다음 프레임으로. 돌아오면 Synth 표본율을 다시 맞춘다(그사이 다른 곳이 바꿨을 수 있다).
static func _wait(bud: Budget, r: float) -> void:
	if bud.over():
		await bud.wait()
	S.set_rate(r)


static func loop_rate(loop_name: String) -> int:
	return int(LOOPS[loop_name][1])


static func loop_stereo(loop_name: String) -> int:
	return int(LOOPS[loop_name][2])


static func _norm_rms(b: PackedFloat32Array, db: float) -> void:
	var r := S.rms(b)
	if r > 1e-7:
		S.gain(b, db_to_linear(db) / r)
	var p := S.peak(b)
	if p > 0.89:
		S.gain(b, 0.89 / p)


# ------------------------------------------------------------------ 잡음 바닥 루프

## 멀리서 오는 도시 웅웅: 갈색 잡음(낮게) + 가운데 띠 차 소리 부풀기 + 50 Hz 변압기 웅.
static func _hum(bud: Budget) -> PackedFloat32Array:
	var R := 11025.0
	var L := int(8.0 * R)
	var X := int(R)
	var n := L + X
	var b := PackedFloat32Array()
	b.resize(n)
	var s := 4242
	var br := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var y3 := 0.0
	var a1 := 1.0 - exp(-TAU * 110.0 / R)
	var a2 := 1.0 - exp(-TAU * 420.0 / R)
	var w1 := TAU / 8.0
	for i in n:
		if (i & 4095) == 0 and bud.over():
			await bud.wait()
		s = (s * 48271) % 2147483647
		var w := float(s) * S.INV_M2 - 1.0
		br = br * 0.997 + w * 0.06
		y1 += a1 * (br - y1)
		y2 += a2 * (w - y2)
		y3 += a2 * (y2 - y3)
		var t := float(i) / R
		var swell := 0.55 + 0.3 * sin(w1 * 2.0 * t + 1.0) + 0.15 * sin(w1 * 3.0 * t + 2.3)
		b[i] = y1 * 2.2 + y3 * 1.6 * swell
	await _wait(bud, 22050.0)
	S.hp1(b, 25.0, R)
	await _wait(bud, 22050.0)
	S.dc_block(b)
	await _wait(bud, 22050.0)
	b = S.loop_xfade(b, L, X)
	await _wait(bud, 22050.0)
	for i in L:
		var t := float(i) / R
		b[i] += (0.004 * sin(TAU * 50.0 * t) + 0.0025 * sin(TAU * 100.0 * t + 0.5) + 0.0012 * sin(TAU * 150.0 * t + 1.7)) * (0.8 + 0.2 * sin(w1 * t))
	return b


## 옥상 바람: 띠 통과 잡음, 가운데 주파수·세기가 느리게 흔들린다(L 안에 1·3·5 번), 셀 때 가는 휘파람.
static func _wind(bud: Budget) -> PackedFloat32Array:
	var Ls := 10.0
	var R := 11025.0
	var L := int(Ls * R)
	var X := int(2.0 * R)
	var n := L + X
	var b := PackedFloat32Array()
	b.resize(n)
	var s := 777
	var ic1 := 0.0
	var ic2 := 0.0
	var jc1 := 0.0
	var jc2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	var k1 := 1.0
	var c1 := 0.0
	var c2 := 0.0
	var c3 := 0.0
	var m := 0.5
	var w0 := TAU / Ls
	for i in n:
		if (i & 4095) == 0 and bud.over():
			await bud.wait()
		var t := float(i) / R
		if (i & 15) == 0:
			m = clampf(0.5 + 0.25 * sin(w0 * t + 0.3) + 0.15 * sin(w0 * 3.0 * t + 1.1) + 0.1 * sin(w0 * 5.0 * t + 2.0), 0.0, 1.0)
			var fc := 220.0 + 650.0 * m * m
			var g := tan(PI * fc / R)
			k1 = 1.0 / (1.2 + 2.0 * m)
			a1 = 1.0 / (1.0 + g * (g + k1))
			a2 = g * a1
			a3 = g * a2
			var g2 := tan(PI * fc * 2.1 / R)
			var k2 := 1.0 / 9.0
			c1 = 1.0 / (1.0 + g2 * (g2 + k2))
			c2 = g2 * c1
			c3 = g2 * c2
		s = (s * 48271) % 2147483647
		var x := float(s) * S.INV_M2 - 1.0
		var v3 := x - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		var u3 := x - jc2
		var u1 := c1 * jc1 + c2 * u3
		var u2 := jc2 + c2 * jc1 + c3 * u3
		jc1 = 2.0 * u1 - jc1
		jc2 = 2.0 * u2 - jc2
		var gust := 0.3 + 0.7 * pow(m, 1.5)
		b[i] = v1 * gust + u1 * 0.12 * maxf(0.0, m - 0.6) * 2.5
	return S.loop_xfade(b, L, X)


## 웅성거림(11025 Hz): 목소리 5개 — 성대(톱니) + 숨(잡음)을 두 포먼트 띠로 거른 음절이 구절·쉼으로 이어진다.
## 낱말은 없다(알아들을 수 없는 거리). 멀리 있는 소리라 2 kHz 위는 깎는다.
static func _murmur(bud: Budget) -> PackedFloat32Array:
	var R := 11025.0
	var Ls := 9.0
	var L := int(Ls * R)
	var X := int(1.5 * R)
	var n := L + X
	var b := PackedFloat32Array()
	b.resize(n)
	var rng := S.Rng.new(9090)
	var F1 := [300.0, 400.0, 550.0, 650.0, 750.0]
	var F2 := [900.0, 1100.0, 1300.0, 1700.0, 2000.0]
	for vi in 5:
		var f0 := rng.r(105.0, 140.0) if vi % 2 == 0 else rng.r(185.0, 240.0)
		var vg := rng.r(0.5, 1.0)
		var s := 1000 + vi * 37
		var ph := rng.f()
		# 음절 일정
		var sched: Array = []
		var t := rng.r(0.0, 1.5)
		var total := float(n) / R
		while t < total:
			var pend := t + rng.r(0.8, 3.0)
			while t < pend and t < total:
				var d := rng.r(0.09, 0.22)
				sched.append([int(t * R), int(d * R), rng.pick(F1), rng.pick(F2), rng.r(0.6, 1.0)])
				t += d + rng.r(0.01, 0.06)
			t += rng.r(0.4, 2.5)
		var ic1 := 0.0
		var ic2 := 0.0
		var jc1 := 0.0
		var jc2 := 0.0
		var cnt := 0
		for syl: Array in sched:
			var i0: int = syl[0]
			var dn: int = syl[1]
			var g1 := tan(PI * float(syl[2]) / R)
			var g2 := tan(PI * float(syl[3]) / R)
			var kq := 1.0 / 5.0
			var a1 := 1.0 / (1.0 + g1 * (g1 + kq))
			var a2 := g1 * a1
			var a3 := g1 * a2
			var c1 := 1.0 / (1.0 + g2 * (g2 + kq))
			var c2 := g2 * c1
			var c3 := g2 * c2
			var amp: float = float(syl[4]) * vg
			var fstep := f0 * (1.0 + rng.r(-0.08, 0.08)) / R
			for k in dn:
				var i := i0 + k
				if i >= n:
					break
				cnt += 1
				if (cnt & 4095) == 0 and bud.over():
					await bud.wait()
				var e := sin(PI * float(k) / float(dn))
				ph += fstep
				ph -= floorf(ph)
				s = (s * 48271) % 2147483647
				var src := (2.0 * ph - 1.0) * 0.6 + (float(s) * S.INV_M2 - 1.0) * 0.4
				var v3 := src - ic2
				var v1 := a1 * ic1 + a2 * v3
				var v2 := ic2 + a2 * ic1 + a3 * v3
				ic1 = 2.0 * v1 - ic1
				ic2 = 2.0 * v2 - ic2
				var u3 := src - jc2
				var u1 := c1 * jc1 + c2 * u3
				var u2 := jc2 + c2 * jc1 + c3 * u3
				jc1 = 2.0 * u1 - jc1
				jc2 = 2.0 * u2 - jc2
				b[i] += (v1 + 0.6 * u1) * e * amp
	await _wait(bud, 22050.0)
	S.lp1(b, 1800.0, R)
	await _wait(bud, 22050.0)
	S.lp1(b, 2600.0, R)
	await _wait(bud, 22050.0)
	S.echo(b, 0.083, 0.25, 0.3, R)
	await _wait(bud, 22050.0)
	if bud.over():
		await bud.wait()
	return S.loop_xfade(b, L, X)


## 불 바닥: 낮은 불길 웅(깜박이는 세기) + 탁탁 튀는 소리(접어서 이음매 없음).
static func _firebed(bud: Budget) -> PackedFloat32Array:
	var R := 11025.0
	S.set_rate(R)
	var Ls := 5.0
	var L := int(Ls * R)
	var X := int(0.8 * R)
	var n := L + X
	var b := PackedFloat32Array()
	b.resize(n)
	var s := 3131
	var br := 0.0
	var y := 0.0
	var a := 1.0 - exp(-TAU * 380.0 / R)
	var w0 := TAU / Ls
	for i in n:
		if (i & 4095) == 0 and bud.over():
			await _wait(bud, R)
		s = (s * 48271) % 2147483647
		var w := float(s) * S.INV_M2 - 1.0
		br = br * 0.99 + w * 0.1
		y += a * (br - y)
		var t := float(i) / R
		var fl := 0.6 + 0.2 * sin(w0 * 3.0 * t) + 0.12 * sin(w0 * 7.0 * t + 1.0) + 0.08 * sin(w0 * 11.0 * t + 2.0)
		b[i] = y * fl
	S.hp1(b, 70.0)
	S.dc_block(b)
	b = S.loop_xfade(b, L, X)
	await _wait(bud, R)
	S.gain(b, 0.1)
	var e := S.buf(Ls + 0.3)
	var rng := S.Rng.new(5151)
	for j in 70:
		var amp := 0.25 * pow(rng.f(), 2.5)
		S.tick(e, rng.r(0.0, Ls), amp + 0.02, rng.r(1500.0, 4200.0), rng.i(1, 99999), rng.r(0.003, 0.01))
	for j in 6:
		S.thud(e, rng.r(0.0, Ls), 320.0, 140.0, 0.12, 0.05)
	S.lp1(e, 5500.0)
	await _wait(bud, R)
	e = S.fold(e, L)
	for i in L:
		b[i] += e[i] * 1.2
	S.set_rate(22050.0)
	return b


## 비: 넓은 띠 잡음 바닥 + 작은 물방울 + 함석지붕 톡.
static func _rain(bud: Budget) -> PackedFloat32Array:
	var R := 11025.0
	S.set_rate(R)
	var Ls := 8.0
	var L := int(Ls * R)
	var X := int(R)
	var n := L + X
	var b := PackedFloat32Array()
	b.resize(n)
	var s := 8080
	var y1 := 0.0
	var y2 := 0.0
	var ah := 1.0 - exp(-TAU * 500.0 / R)
	var al := 1.0 - exp(-TAU * 4500.0 / R)
	var w0 := TAU / Ls
	for i in n:
		if (i & 4095) == 0 and bud.over():
			await _wait(bud, R)
		s = (s * 48271) % 2147483647
		var w := float(s) * S.INV_M2 - 1.0
		y1 += ah * (w - y1)
		var hp := w - y1
		y2 += al * (hp - y2)
		var t := float(i) / R
		b[i] = y2 * (0.85 + 0.15 * sin(w0 * 2.0 * t))
	b = S.loop_xfade(b, L, X)
	await _wait(bud, R)
	var e := S.buf(Ls + 0.3)
	var rng := S.Rng.new(6262)
	for j in 160:
		S.partial(e, rng.r(0.0, Ls), rng.r(1500.0, 3500.0), rng.r(0.02, 0.08), 0.02, 0.001, -1.0)
	for j in 14:
		S.modal(e, rng.r(0.0, Ls), rng.r(900.0, 1400.0), rng.r(0.05, 0.12), [1.0, 1.59, 2.14], [1.0, 0.5, 0.3], [0.08, 0.05, 0.03])
	if bud.over():
		await _wait(bud, R)
	e = S.fold(e, L)
	await _wait(bud, R)
	for i in L:
		b[i] += e[i] * 0.6
	await _wait(bud, R)
	S.lp1_loop(b, 4800.0)
	S.set_rate(22050.0)
	return b


# ------------------------------------------------------------------ 사건 모음 루프

## 장터: 그릇 부딪는 소리, 칼질 묶음, 웍 지글, 주판알. 웅성거림 위에 얹힌다.
static func _market(bud: Budget) -> PackedFloat32Array:
	var R := 11025.0
	S.set_rate(R)
	var Ls := 9.0
	var L := int(Ls * R)
	var e := S.buf(Ls + 1.0)
	var rng := S.Rng.new(7373)
	for j in 14:
		S.modal(e, rng.r(0.0, Ls), rng.r(1700.0, 2600.0), rng.r(0.08, 0.18), [1.0, 2.76, 5.4], [1.0, 0.4, 0.15], [0.14, 0.07, 0.03])
	for j in 3:
		var t0 := rng.r(0.0, Ls)
		for k in rng.i(3, 6):
			var t := t0 + 0.17 * k + rng.r(-0.01, 0.01)
			S.thud(e, t, 190.0, 120.0, 0.22, 0.05)
			S.tick(e, t, 0.15, 1400.0, rng.i(1, 9999))
	if bud.over():
		await _wait(bud, R)
	for j in 2:
		S.noise(e, rng.r(0.0, Ls), 1.4, 0.05, 2, 2600.0, 3200.0, 0.7, rng.i(1, 9999), 0.12, 0.6, 0.5)
	for j in 2:
		var t0 := rng.r(0.0, Ls)
		for k in 5:
			S.tick(e, t0 + 0.05 * k + rng.r(0.0, 0.02), 0.12, 2600.0, rng.i(1, 9999), 0.006)
	if bud.over():
		await _wait(bud, R)
	S.lp1(e, 5000.0)
	await _wait(bud, R)
	S.echo(e, 0.061, 0.3, 0.3)
	await _wait(bud, R)
	var out := S.fold(e, L)
	S.set_rate(22050.0)
	return out


## 귀뚜라미 셋: 주기가 L/k 라 루프 이음매에서도 박자가 맞다. 낮게, 6 kHz 위는 깎는다.
static func _crickets(bud: Budget) -> PackedFloat32Array:
	var R := 11025.0
	S.set_rate(R)
	var Ls := 6.0
	var L := int(Ls * R)
	var e := S.buf(Ls + 0.4)
	var rng := S.Rng.new(4545)
	var cr := [[3950.0, 8, 3, 0.22], [4350.0, 10, 2, 0.15], [4700.0, 7, 4, 0.1]]
	for c: Array in cr:
		var per := Ls / float(c[1])
		var off := rng.r(0.0, per)
		for k in int(c[1]):
			var t := off + per * k
			var amp: float = float(c[3]) * rng.r(0.7, 1.0)
			for p in int(c[2]):
				S.partial(e, t + 0.03 * p, float(c[0]) * rng.r(0.995, 1.005), amp, 0.022, 0.004)
		if bud.over():
			await _wait(bud, R)
	S.lp1(e, 6000.0)
	await _wait(bud, R)
	S.echo(e, 0.11, 0.2, 0.25)
	await _wait(bud, R)
	var out := S.fold(e, L)
	S.set_rate(22050.0)
	return out


# ------------------------------------------------------------------ 한 번짜리

## 먼 소리라 11025 Hz 로 만든다(반값). 재생할 때 to_wav(..., SHOT_RATE).
const SHOT_RATE := 11025


static func build_shot(shot_name: String, v: int, bud: Budget = null) -> PackedFloat32Array:
	S.set_rate(SHOT_RATE)
	var o: PackedFloat32Array = await _shot(shot_name, v, bud)
	await _wait_opt(bud, SHOT_RATE)
	S.dc_block(o)
	o = S.trim(o)
	S.normalize(o, -20.0, -1.0, true)
	S.set_rate(22050.0)
	return o


## 거리감: 높은 소리 깎고 골목 메아리.
static func _far(o: PackedFloat32Array, lp: float = 3000.0, echo_t: float = 0.09) -> void:
	S.lp1(o, lp)
	S.echo(o, echo_t, 0.3, 0.35)


static func _wait_opt(bud: Budget, r: float) -> void:
	if bud != null and bud.over():
		await bud.wait()
	S.set_rate(r)


static func _shot(n: String, v: int, bud: Budget = null) -> PackedFloat32Array:
	var rng := S.Rng.new(hash(n) * 3 + v * 977)
	var o: PackedFloat32Array
	match n:
		"bird":   # 참새 몇 번 짹
			o = S.buf(1.2)
			var t := 0.0
			for j in rng.i(2, 5):
				var f := rng.r(2500.0, 3300.0) * (1.0 + 0.04 * v)
				S.partial(o, t, f, rng.r(0.2, 0.35), 0.07, 0.004, f * rng.r(1.1, 1.25), 0.04)
				S.partial(o, t, f * 0.5, 0.05, 0.05, 0.004)
				t += rng.r(0.08, 0.2)
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 5500.0, 0.07)
		"pigeon":   # 구-구루-구
			o = S.buf(1.8)
			var f0 := 380.0 + 30.0 * v
			var t := 0.0
			for j in 3:
				var d: float = [0.28, 0.42, 0.35][j]
				S.tone(o, t, d, f0 * [1.0, 1.15, 0.95][j], f0 * [1.2, 1.05, 0.85][j], S.SINE, 0.3, 0.06, 0.1, 22.0, 0.03)
				S.tone(o, t, d, f0 * 2.0 * [1.0, 1.15, 0.95][j], f0 * 2.0 * [1.2, 1.05, 0.85][j], S.SINE, 0.06, 0.06, 0.1, 22.0, 0.03)
				t += d + 0.06
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 1400.0, 0.08)
		"dog":   # 멀리 개 두어 번
			o = S.buf(1.4)
			var t := 0.0
			for j in 1 + v + rng.i(0, 1):
				var f0 := rng.r(330.0, 420.0)
				var tmp := S.buf(0.25)
				S.tone(tmp, 0.0, 0.16, f0, f0 * 0.75, S.SAW, 0.5, 0.008, 0.08)
				S.noise(tmp, 0.0, 0.14, 0.25, 0, 2000.0, 1200.0, 0.7, rng.i(1, 9999), 0.004, 0.12)
				var f1 := tmp.duplicate()
				S.svf(tmp, 750.0, 3.0, 1)
				S.svf(f1, 1500.0, 3.0, 1)
				S.mix_into(o, tmp, t, 1.0)
				S.mix_into(o, f1, t, 0.6)
				t += rng.r(0.22, 0.32)
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 2200.0, 0.11)
		"bell":   # 자전거 따르릉
			o = S.buf(1.4)
			var f := 1350.0 + 120.0 * v
			for k in 2 + v:
				S.modal(o, 0.11 * k, f, 0.3, [1.0, 1.48, 2.2], [1.0, 0.5, 0.25], [0.5, 0.35, 0.2])
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 3200.0, 0.07)
		"kettle":   # 주전자 — 낮게, 먼 데서
			o = S.buf(3.0)
			S.tone(o, 0.0, 2.6, 1450.0, 1750.0, S.SINE, 0.25, 0.9, 0.5, 6.0, 0.006)
			await _wait_opt(bud, SHOT_RATE)
			S.noise(o, 0.0, 2.6, 0.12, 1, 1500.0, 1700.0, 2.0, 313, 0.8, 4.0, 1.2)
			await _wait_opt(bud, SHOT_RATE)
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 2500.0, 0.09)
		"mahjong":   # 이웃집 마작판 패 섞기
			o = S.buf(2.2)
			var t := 0.0
			var end := rng.r(1.0, 1.7)
			while t < end:
				var f := rng.r(2300.0, 3500.0)
				S.modal(o, t, f, rng.r(0.08, 0.25), [1.0, 2.31], [1.0, 0.4], [0.025, 0.012], 0.0003)
				t += rng.r(0.01, 0.05) * (1.0 + t)
			S.noise(o, 0.0, end, 0.04, 0, 380.0, 300.0, 0.7, 321 + v, 0.1, 2.0, end - 0.3)
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 4000.0, 0.06)
		"radio":   # 먼 라디오 한 소절(소리음계에서 씨앗으로 지은 선율)
			o = S.buf(3.2)
			var scale := [0, 2, 4, 7, 9, 12, 14]
			var root: float = [392.0, 349.2, 440.0][v % 3]
			var t := 0.1
			var deg := rng.i(0, 4)
			for j in rng.i(6, 9):
				var d: float = rng.pick([0.2, 0.2, 0.4, 0.3, 0.6])
				var f: float = root * pow(2.0, float(scale[deg]) / 12.0)
				S.tone(o, t, d * 0.95, f, f, S.TRI, 0.2, 0.02, 0.06, 5.5, 0.008)
				S.tone(o, t, d * 0.95, f * 0.5, f * 0.5, S.TRI, 0.12, 0.02, 0.06)
				t += d
				deg = clampi(deg + rng.pick([-2, -1, -1, 1, 1, 2]), 0, scale.size() - 1)
				await _wait_opt(bud, SHOT_RATE)
			S.svf(o, 1300.0, 0.9, 1)
			S.noise(o, 0.0, t + 0.2, 0.025, 1, 2000.0, 2000.0, 0.6, 331 + v, 0.05, 9.0, t)
			for j in 8:
				S.tick(o, rng.r(0.0, t), 0.05, 2500.0, rng.i(1, 9999), 0.004)
			S.fade_in(o, 0.25)
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 2800.0, 0.1)
		"hammer":   # 공사장 망치
			o = S.buf(2.2)
			var cnt := 3 + v + rng.i(0, 1)
			for k in cnt:
				var t := 0.38 * k + rng.r(-0.03, 0.03)
				S.modal(o, t, rng.r(760.0, 880.0), 0.35, [1.0, 1.59, 2.14, 2.65], [1.0, 0.6, 0.4, 0.25], [0.12, 0.08, 0.05, 0.04])
				S.thud(o, t, 200.0, 120.0, 0.3, 0.05)
				S.tick(o, t, 0.2, 1900.0, rng.i(1, 9999))
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 3500.0, 0.1)
		"horn":   # 항구 쪽 뱃고동
			o = S.buf(3.4)
			S.tone(o, 0.0, 2.4, 110.0, 108.0, S.SAW, 0.3, 0.35, 0.8)
			await _wait_opt(bud, SHOT_RATE)
			S.tone(o, 0.0, 2.4, 110.7, 108.5, S.SAW, 0.3, 0.35, 0.8)
			await _wait_opt(bud, SHOT_RATE)
			S.tone(o, 0.0, 2.4, 165.0, 162.0, S.SAW, 0.12, 0.35, 0.8)
			await _wait_opt(bud, SHOT_RATE)
			S.lp1(o, 500.0)
			await _wait_opt(bud, SHOT_RATE)
			S.lp1(o, 700.0)
			await _wait_opt(bud, SHOT_RATE)
			S.echo(o, 0.23, 0.35, 0.45)
		"drip":   # 실외기 물방울
			o = S.buf(0.4)
			var f: float = [1150.0, 1350.0, 980.0][v % 3]
			S.partial(o, 0.0, f, 0.4, 0.06, 0.001, f * 1.6, 0.03)
			S.tick(o, 0.0, 0.08, 2500.0, 341 + v, 0.004)
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 4500.0, 0.05)
		"wok":   # 웍 탕 + 국자 긁기
			o = S.buf(1.2)
			S.modal(o, 0.0, 420.0 + 40.0 * v, 0.35, [1.0, 1.59, 2.14, 2.65, 3.5], [1.0, 0.6, 0.45, 0.3, 0.2], [0.35, 0.22, 0.15, 0.1, 0.07])
			S.noise(o, 0.12, 0.35, 0.12, 1, 1800.0, 2400.0, 1.5, 351 + v, 0.03, 0.3)
			S.noise(o, 0.0, 1.0, 0.04, 2, 3000.0, 3000.0, 0.7, 352 + v, 0.15, 0.8, 0.3)
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 3500.0, 0.06)
		"shutter":   # 철문 셔터 드르륵
			o = S.buf(1.6)
			var t := 0.0
			while t < 1.0:
				S.modal(o, t, rng.r(240.0, 300.0), 0.12, [1.0, 1.47, 2.09, 2.56], [1.0, 0.7, 0.5, 0.3], [0.08, 0.06, 0.05, 0.04])
				t += rng.r(0.025, 0.04)
			S.noise(o, 0.0, 1.0, 0.1, 1, 900.0, 700.0, 1.0, 361, 0.05, 3.0, 0.8)
			S.thud(o, 1.0, 140.0, 80.0, 0.4, 0.12)
			await _wait_opt(bud, SHOT_RATE)
			_far(o, 2500.0, 0.1)
		_:
			o = PackedFloat32Array()
	return o
