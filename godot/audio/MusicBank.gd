extends RefCounted
## MusicBank — 아주 작은 생성 음악. 깡통 오르골·나무 건반·튕긴 줄 세 악기와 느린 바탕 화음 넷.
## 선율은 소리음계(5음) + 씨앗 패턴으로만 짓는다(남의 선율 없음). 분위기: 낮 · 저녁 · 밤 · 불(경보 물들임).
## 음 하나 = 악기 표본 하나를 pitch_scale 로 옮겨 재생(오르골은 원래 그렇게 들린다).

const S := preload("res://audio/Synth.gd")
const AB := preload("res://audio/AmbienceBank.gd")
const SR := 22050

## 악기 → 바탕 Hz(표본의 실제 음높이)
static var base_hz: Dictionary = {"box": 523.25, "wood": 261.63, "pluck": 261.63}

const MOODS := {
	"day": {"root": 523.25, "scale": [0, 2, 4, 7, 9], "inst": ["box", "box", "wood"], "bpm": 84.0, "rest": [6.0, 14.0], "len": [4, 7], "pad": "", "lo": -5, "hi": 12, "vel": 0.9},
	"evening": {"root": 440.0, "scale": [0, 3, 5, 7, 10], "inst": ["pluck", "box", "pluck"], "bpm": 72.0, "rest": [8.0, 16.0], "len": [4, 6], "pad": "pad_warm", "lo": -7, "hi": 10, "vel": 0.85},
	"night": {"root": 349.23, "scale": [0, 2, 4, 7, 9], "inst": ["box", "wood"], "bpm": 58.0, "rest": [12.0, 24.0], "len": [3, 5], "pad": "pad_night", "lo": -5, "hi": 9, "vel": 0.7},
	"alarm": {"root": 293.66, "scale": [0, 1, 5, 7, 8], "inst": ["wood", "pluck"], "bpm": 100.0, "rest": [3.0, 7.0], "len": [5, 8], "pad": "pad_tense", "lo": -5, "hi": 12, "vel": 0.8},
}

const PADS := ["pad_warm", "pad_night", "pad_tense"]
const INSTS := ["box", "wood", "pluck"]


static func build_inst(inst: String) -> PackedFloat32Array:
	var o: PackedFloat32Array
	match inst:
		"box":
			o = S.buf(2.6)
			S.modal(o, 0.0, 523.25, 0.5, [1.0, 2.0, 5.4, 8.9], [1.0, 0.1, 0.18, 0.05], [2.2, 0.6, 0.25, 0.1], 0.0015)
			S.tick(o, 0.0, 0.05, 4000.0, 11, 0.004)
			S.lp1(o, 7500.0)
		"wood":
			o = S.buf(1.2)
			S.modal(o, 0.0, 261.63, 0.6, [1.0, 3.93, 9.0], [1.0, 0.22, 0.05], [0.9, 0.25, 0.07], 0.002)
			S.noise(o, 0.0, 0.03, 0.08, 1, 900.0, 800.0, 1.5, 12, 0.001, 0.015)
		"pluck":
			o = _ks(261.63, 2.4)
	S.dc_block(o)
	o = S.trim(o)
	S.normalize(o, -20.0, -1.0)
	return o


## 튕긴 줄(카플러스-스트롱). 실제 음높이를 base_hz 에 적는다.
static func _ks(f: float, sec: float) -> PackedFloat32Array:
	var N := maxi(2, int(round(SR / f - 0.5)))
	base_hz["pluck"] = float(SR) / (float(N) + 0.5)
	var line := PackedFloat32Array()
	line.resize(N)
	var rng := S.Rng.new(271)
	var y := 0.0
	for i in N:
		y += 0.5 * (rng.n() - y)   # 무른 손톱(높은 잡음 덜)
		line[i] = y
	var o := S.buf(sec)
	var p := 0
	for i in o.size():
		var a := line[p]
		var q := (p + 1) % N
		line[p] = (a + line[q]) * 0.5 * 0.9965
		o[i] = a
		p = q
	S.fade_in(o, 0.002)
	S.lp1(o, 3500.0)
	return o


## 바탕 화음(11025 Hz, 8초, 모든 주파수가 1/8 Hz 의 정수배 → 이음매 없음).
static func build_pad(pad: String, bud: AB.Budget) -> PackedFloat32Array:
	var R := 11025.0
	var Ls := 8.0
	var notes: Array
	match pad:
		"pad_warm":
			notes = [110.0, 164.875, 261.625]
		"pad_night":
			notes = [87.25, 130.875, 220.0]
		_:
			notes = [73.375, 146.875, 155.5]
	var L := int(Ls * R)
	var o := PackedFloat32Array()
	o.resize(L)
	var rng := S.Rng.new(hash(pad))
	var amw := TAU / Ls
	var blk := 64
	for j in notes.size():
		var f: float = notes[j]
		for h in 2:
			var fh := f * float(h + 1) + (0.125 if h == 1 else 0.0)   # 2배음을 살짝 어긋내 맥놀이
			var w := TAU * fh / R
			var cr := cos(w)
			var sr_ := sin(w)
			var c := 1.0
			var sn := 0.0
			var amp := (0.5 if h == 0 else 0.18) / float(notes.size())
			var amk := float(rng.i(1, 3))
			var amp0 := rng.r(0.0, TAU)
			var g := amp
			for i in L:
				if (i % blk) == 0:
					g = amp * (0.7 + 0.3 * sin(amw * amk * float(i) / R + amp0))
					if (i & 8191) == 0 and bud.over():
						await bud.wait()
				o[i] += sn * g
				var nc := c * cr - sn * sr_
				sn = c * sr_ + sn * cr
				c = nc
	AB._norm_rms(o, -24.0)
	return o


## 한 구절: [[초, 악기, 반음, 세기], …]. 씨앗이 같으면 같은 구절.
static func phrase(mood: String, seed_value: int) -> Array:
	var m: Dictionary = MOODS.get(mood, MOODS["day"])
	var rng := S.Rng.new(seed_value)
	var scale: Array = m["scale"]
	var beat := 60.0 / float(m["bpm"]) * 0.5   # 8분음표
	var cells := [[1, 1, 2], [2, 1, 1], [1, 1, 1, 1], [3, 1], [2, 2], [1, 3], [4]]
	var nlen := rng.i(int(m["len"][0]), int(m["len"][1]))
	var out: Array = []
	var deg := rng.i(0, scale.size() - 1)
	var octv := 0
	var t := 0.0
	var inst: String = rng.pick(m["inst"])
	var lo: int = m["lo"]
	var hi: int = m["hi"]
	var cell: Array = rng.pick(cells)
	var ci := 0
	for k in nlen:
		var semis: int = int(scale[deg]) + 12 * octv
		semis = clampi(semis, lo, hi)
		var vel: float = float(m["vel"]) * rng.r(0.6, 1.0) * (0.7 if k == nlen - 1 else 1.0)
		out.append([t, inst, semis, vel])
		# 가끔 아래 5도·옥타브 겹음(오르골 두 손가락)
		if rng.f() < 0.15 and semis - 12 >= lo:
			out.append([t, inst, semis - 12, vel * 0.5])
		t += beat * float(cell[ci])
		ci += 1
		if ci >= cell.size():
			cell = rng.pick(cells)
			ci = 0
		var step: int = rng.pick([-2, -1, -1, 1, 1, 1, 2, 0])
		deg += step
		if deg >= scale.size():
			deg -= scale.size()
			octv += 1
		elif deg < 0:
			deg += scale.size()
			octv -= 1
		if 12 * octv + int(scale[deg]) > hi:
			octv -= 1
		elif 12 * octv + int(scale[deg]) < lo:
			octv += 1
	return out


static func pitch_for(mood: String, inst: String, semis: int) -> float:
	var m: Dictionary = MOODS.get(mood, MOODS["day"])
	var ps := float(m["root"]) * pow(2.0, float(semis) / 12.0) / float(base_hz.get(inst, 523.25))
	# 악기 표본에서 너무 멀면 옥타브를 옮긴다(나무 건반은 낮게, 오르골은 높게 남는다)
	while ps > 2.2:
		ps *= 0.5
	while ps < 0.45:
		ps *= 2.0
	return ps
