extends RefCounted
## SfxBank — 효과음 조리법. 이름마다 변주 몇 개를 Synth 조각으로 짓는다.
## 재질: 대나무 딱(나무 부분음), 함석 쿵(빽빽한 쇠 부분음 + 잡음), 깡통(짧은 쇠), 동전 찰랑(높은 짧은 쇠),
## 마작패(사기 딸깍), 오르골 쇠살(tine), 종(FM). 날카로운 소리는 피한다(위쪽 저역 통과, 높은 음은 작게).
## 만든 뒤 finalize: 직류 빼기 → 꼬리 자르기 → 짧은 RMS 를 TARGET_DB 로 맞춤(봉우리 -1 dB 눌러 막음).
## 들리는 크기 차이는 GAIN_DB(재생할 때 volume_db)로만 준다.

const S := preload("res://audio/Synth.gd")

const TARGET_DB := -20.0

## 이름 → [변주 수, 재생 이득 dB, 재생할 때 음높이 흔들기(±비율), 같은 소리 다시 울리지 않는 간격 s]
const SPEC := {
	"click": [3, -9.0, 0.03, 0.06],
	"hover": [3, -19.0, 0.04, 0.07],
	"tab": [2, -9.0, 0.02, 0.06],
	"window_open": [1, -9.0, 0.02, 0.08],
	"window_close": [1, -10.0, 0.02, 0.08],
	"zone": [3, -5.0, 0.03, 0.06],
	"build": [3, -4.0, 0.02, 0.08],
	"place_fail": [2, -7.0, 0.0, 0.15],
	"rotate": [2, -9.0, 0.03, 0.06],
	"demolish": [2, -3.0, 0.03, 0.10],
	"upgrade": [1, -4.0, 0.0, 0.15],
	"money": [2, -4.0, 0.02, 0.12],
	"unlock": [1, -4.0, 0.0, 0.2],
	"goal": [1, -3.0, 0.0, 0.3],
	"floor": [1, -3.0, 0.0, 0.3],
	"tier_up": [1, -2.0, 0.0, 0.5],
	"alert": [1, -8.0, 0.0, 0.4],
	"hazard_on": [1, -4.0, 0.0, 0.5],
	"fire": [1, -4.0, 0.0, 0.4],
	"fire_out": [1, -7.0, 0.03, 0.3],
	"disease": [1, -5.0, 0.0, 0.4],
	"speed": [3, -10.0, 0.02, 0.06],
	"expedition": [1, -6.0, 0.0, 0.3],
	"construction_done": [2, -9.0, 0.03, 0.25],
	"repair_done": [1, -8.0, 0.03, 0.25],
	"contract_done": [1, -6.0, 0.0, 0.3],
	"research_done": [1, -5.0, 0.0, 0.3],
}

# 재질(부분음 비율, 세기, 감쇠 t60 s)
const WOOD_R := [1.0, 2.57, 4.1]
const WOOD_A := [1.0, 0.45, 0.18]
const SHEET_R := [1.0, 1.47, 2.09, 2.56, 3.18, 3.9, 4.7, 5.6]
const SHEET_A := [1.0, 0.8, 0.7, 0.55, 0.45, 0.35, 0.28, 0.2]
const SHEET_T := [0.6, 0.5, 0.45, 0.38, 0.3, 0.25, 0.2, 0.15]
const TIN_R := [1.0, 1.59, 2.14, 2.65, 3.5]
const TIN_A := [1.0, 0.6, 0.45, 0.3, 0.2]
const COIN_R := [1.0, 2.76, 5.4]
const COIN_A := [1.0, 0.45, 0.2]
const TINE_R := [1.0, 2.0, 5.4, 8.9]
const TINE_A := [1.0, 0.12, 0.22, 0.06]


static func names() -> Array:
	return SPEC.keys()


static func variants(sfx_name: String) -> int:
	return int(SPEC.get(sfx_name, [1])[0])


static func gain_db(sfx_name: String) -> float:
	return float(SPEC.get(sfx_name, [1, -8.0])[1])


static func pitch_jitter(sfx_name: String) -> float:
	return float(SPEC.get(sfx_name, [1, 0.0, 0.0])[2])


static func min_gap(sfx_name: String) -> float:
	return float(SPEC.get(sfx_name, [1, 0.0, 0.0, 0.06])[3])


## 다 만든 표본(정규화까지). 모르는 이름이면 빈 배열.
static func build(sfx_name: String, v: int) -> PackedFloat32Array:
	if not has_method_static(sfx_name):
		return PackedFloat32Array()
	var b: PackedFloat32Array = render(sfx_name, v)
	return finalize(b)


static func has_method_static(sfx_name: String) -> bool:
	return SPEC.has(sfx_name)


static func finalize(b: PackedFloat32Array) -> PackedFloat32Array:
	S.dc_block(b)
	var o := S.trim(b)
	S.normalize(o, TARGET_DB, -1.0)
	return o


# ------------------------------------------------------------------ 재질 조각

static func wood(out: PackedFloat32Array, t0: float, f: float, amp: float, len_s: float = 0.06, seed_value: int = 1) -> void:
	S.modal(out, t0, f, amp, WOOD_R, WOOD_A, [len_s, len_s * 0.55, len_s * 0.3], 0.0008)
	S.noise(out, t0, 0.02, amp * 0.35, 1, f * 2.2, f * 2.0, 2.5, seed_value, 0.0005, 0.008)


static func sheet(out: PackedFloat32Array, t0: float, f: float, amp: float, len_k: float = 1.0) -> void:
	var t := []
	for x: float in SHEET_T:
		t.append(x * len_k)
	S.modal(out, t0, f, amp, SHEET_R, SHEET_A, t, 0.002)


static func tin(out: PackedFloat32Array, t0: float, f: float, amp: float, len_s: float = 0.2) -> void:
	S.modal(out, t0, f, amp, TIN_R, TIN_A, [len_s, len_s * 0.6, len_s * 0.45, len_s * 0.3, len_s * 0.2], 0.001)


static func coin(out: PackedFloat32Array, t0: float, f: float, amp: float, len_s: float = 0.14) -> void:
	S.modal(out, t0, f, amp, COIN_R, COIN_A, [len_s, len_s * 0.5, len_s * 0.25], 0.0005)


## 오르골 쇠살: 맑은 바탕음 + 약한 비화성 배음, 길게 남는다.
static func tine(out: PackedFloat32Array, t0: float, f: float, amp: float, len_s: float = 1.2) -> void:
	S.modal(out, t0, f, amp, TINE_R, TINE_A, [len_s, len_s * 0.3, len_s * 0.12, len_s * 0.06], 0.0015)


## 마작패 둘이 부딪는 딸깍(사기).
static func tile(out: PackedFloat32Array, t0: float, amp: float, rng: S.Rng) -> void:
	var f := rng.r(2400.0, 3600.0)
	S.modal(out, t0, f, amp, [1.0, 2.31], [1.0, 0.4], [0.025, 0.012], 0.0003)
	S.noise(out, t0, 0.015, amp * 0.5, 1, f * 1.3, f * 1.2, 2.0, rng.i(1, 99999), 0.0003, 0.006)


# ------------------------------------------------------------------ 조리법

static func render(n: String, v: int) -> PackedFloat32Array:
	var rng := S.Rng.new(hash(n) + v * 101)
	var o: PackedFloat32Array
	match n:
		"click":
			o = S.buf(0.12)
			var f: float = [1250.0, 1130.0, 1370.0][v % 3]
			wood(o, 0.0, f, 0.6, 0.05, 11 + v)
			S.partial(o, 0.0, 240.0, 0.25, 0.04)
			S.lp1(o, 7000.0)
		"hover":
			o = S.buf(0.05)
			S.tick(o, 0.0, 0.3, 2900.0 + 250.0 * v, 21 + v, 0.006)
			S.partial(o, 0.0, 1700.0 + 120.0 * v, 0.18, 0.02)
			S.lp1(o, 6000.0)
		"tab":
			o = S.buf(0.16)
			wood(o, 0.0, 880.0 + 60.0 * v, 0.5, 0.05, 31 + v)
			wood(o, 0.045, 1040.0 + 60.0 * v, 0.32, 0.05, 32 + v)
			S.noise(o, 0.0, 0.04, 0.12, 2, 3000.0, 3000.0, 0.7, 33 + v, 0.002, 0.03)
			S.lp1(o, 7000.0)
		"window_open":
			o = S.buf(0.45)
			S.noise(o, 0.0, 0.2, 0.45, 1, 450.0, 1600.0, 1.6, 41, 0.07, 0.2)
			wood(o, 0.16, 980.0, 0.5, 0.06, 42)
			S.thud(o, 0.16, 210.0, 150.0, 0.25, 0.08)
			S.room(o, 0.25, 0.25)
		"window_close":
			o = S.buf(0.4)
			S.noise(o, 0.0, 0.16, 0.4, 1, 1400.0, 450.0, 1.6, 51, 0.02, 0.18)
			S.thud(o, 0.12, 170.0, 90.0, 0.55, 0.12)
			wood(o, 0.125, 720.0, 0.35, 0.05, 52)
			S.room(o, 0.25, 0.22)
		"zone":
			o = S.buf(0.35)
			var k := 1.0 + 0.06 * float(v)
			S.thud(o, 0.0, 150.0 * k, 95.0 * k, 0.7, 0.12)
			S.modal(o, 0.0, 420.0 * k, 0.45, WOOD_R, WOOD_A, [0.12, 0.06, 0.03])
			S.noise(o, 0.0, 0.06, 0.25, 0, 900.0, 700.0, 0.7, 61 + v, 0.001, 0.04)
			S.tick(o, 0.07, 0.18, 2500.0, 62 + v)
			S.room(o, 0.2, 0.2)
			S.lp1(o, 6000.0)
		"build":
			o = S.buf(0.9)
			var f := 195.0 + 22.0 * float(v)
			S.thud(o, 0.0, 115.0, 60.0, 0.7, 0.2)
			sheet(o, 0.0, f, 0.28, 1.0)
			S.noise(o, 0.0, 0.3, 0.28, 1, 1800.0, 1300.0, 0.9, 71 + v, 0.001, 0.22)
			for t: float in [0.3, 0.44]:
				S.modal(o, t, 880.0 + 40.0 * v, 0.25, TIN_R, TIN_A, [0.08, 0.05, 0.04, 0.03, 0.02])
				S.tick(o, t, 0.2, 1800.0, 72 + v)
			S.room(o, 0.35, 0.25)
			S.lp1(o, 6500.0)
		"place_fail":
			o = S.buf(0.4)
			var f := 230.0 - 15.0 * v
			for j in 2:
				var t := 0.11 * j
				S.modal(o, t, f * (1.0 if j == 0 else 0.82), 0.6, [1.0, 1.59, 2.14], [1.0, 0.5, 0.3], [0.18, 0.1, 0.06])
				S.thud(o, t, 160.0, 110.0, 0.3, 0.06)
			S.lp1(o, 1500.0)
		"rotate":
			o = S.buf(0.16)
			for j in 3:
				S.tick(o, 0.035 * j, [0.5, 0.4, 0.45][j], 2200.0 + 200.0 * v + 120.0 * j, 81 + j + 5 * v)
				S.modal(o, 0.035 * j, 800.0 + 50.0 * v, 0.2, WOOD_R, WOOD_A, [0.03, 0.02, 0.01])
			S.lp1(o, 6500.0)
		"demolish":
			o = S.buf(1.0)
			S.thud(o, 0.0, 120.0, 45.0, 0.9, 0.35)
			S.noise(o, 0.0, 0.7, 0.45, 0, 1200.0, 260.0, 0.8, 91 + v, 0.005, 0.5, 0.1)
			sheet(o, 0.08, 165.0 + 15.0 * v, 0.14, 0.6)
			for j in 11:
				var t := rng.r(0.05, 0.65) * (0.5 + 0.5 * float(j) / 11.0)
				S.tick(o, t, rng.r(0.08, 0.3) * (1.0 - 0.5 * float(j) / 11.0), rng.r(1200.0, 3400.0), rng.i(1, 9999))
			S.room(o, 0.4, 0.3)
			S.lp1(o, 5500.0)
		"upgrade":
			o = S.buf(1.4)
			wood(o, 0.0, 600.0, 0.4, 0.06, 101)
			S.thud(o, 0.0, 160.0, 100.0, 0.35, 0.08)
			var notes := [659.3, 784.0, 880.0, 1046.5]
			for j in notes.size():
				tine(o, 0.08 + 0.085 * j, notes[j], 0.32 - 0.03 * j, 0.9)
			S.noise(o, 0.3, 0.6, 0.04, 2, 5000.0, 5000.0, 0.7, 102, 0.1, 0.5)
			S.room(o, 0.4, 0.25)
			S.lp1(o, 7000.0)
		"money":
			o = S.buf(0.75)
			# 깡통 몸통(통 울림) + 동전이 안에서 몇 번 찰랑
			S.noise(o, 0.0, 0.35, 0.22, 1, 850.0 + 60.0 * v, 800.0, 4.0, 111 + v, 0.01, 0.25)
			tin(o, 0.0, 620.0 + 40.0 * v, 0.22, 0.18)
			var t := 0.0
			for j in 9:
				t += rng.r(0.012, 0.045)
				coin(o, t, rng.r(2300.0, 3300.0), rng.r(0.12, 0.26), 0.1)
			coin(o, t + 0.06, 2650.0 + 100.0 * v, 0.3, 0.32)
			S.room(o, 0.2, 0.15)
			S.lp1(o, 6500.0)
		"unlock":
			o = S.buf(1.5)
			S.tick(o, 0.0, 0.45, 2000.0, 121)
			S.thud(o, 0.0, 320.0, 210.0, 0.35, 0.05)
			S.tick(o, 0.045, 0.35, 1600.0, 122)
			tine(o, 0.14, 784.0, 0.35, 1.0)
			tine(o, 0.32, 1174.7, 0.3, 1.1)
			S.room(o, 0.4, 0.25)
			S.lp1(o, 7000.0)
		"goal":
			o = S.buf(2.2)
			# 마작패 섞기: 처음엔 빽빽, 점점 성기게 + 탁자 웅웅
			S.noise(o, 0.0, 0.6, 0.12, 0, 380.0, 300.0, 0.7, 131, 0.05, 0.4, 0.4)
			var t := 0.0
			while t < 0.52:
				tile(o, t, rng.r(0.12, 0.3), rng)
				t += rng.r(0.008, 0.03) * (1.0 + 2.0 * t)
			# 탁! (패 엎기) + 오르골 화음
			tile(o, 0.6, 0.5, rng)
			tile(o, 0.612, 0.4, rng)
			S.thud(o, 0.6, 220.0, 140.0, 0.4, 0.06)
			for j in 3:
				tine(o, 0.66 + 0.025 * j, [523.3, 659.3, 784.0][j], 0.28, 1.3)
			S.partial(o, 0.66, 261.6, 0.18, 1.0)
			S.room(o, 0.45, 0.28)
			S.lp1(o, 7000.0)
		"floor":
			o = S.buf(2.0)
			var notes := [523.3, 587.3, 659.3, 784.0]
			for j in notes.size():
				wood(o, 0.08 * j, notes[j], 0.42, 0.12, 141 + j)
			sheet(o, 0.33, 330.0, 0.12, 1.4)
			tine(o, 0.33, 1046.5, 0.3, 1.3)
			tine(o, 0.33, 523.3, 0.2, 1.3)
			S.room(o, 0.5, 0.3)
			S.lp1(o, 7000.0)
		"tier_up":
			o = S.buf(3.2)
			S.fm(o, 0.0, 98.0, 1.41, 5.0, 0.5, 0.45, 3.0)
			S.modal(o, 0.0, 98.0, 0.25, [1.0, 1.52, 2.0, 2.68], [1.0, 0.6, 0.4, 0.25], [3.0, 2.2, 1.6, 1.0])
			S.noise(o, 0.0, 1.6, 0.06, 2, 4500.0, 4500.0, 0.7, 151, 0.02, 1.2)
			var run := [523.3, 587.3, 659.3, 784.0, 880.0, 1046.5]
			for j in run.size():
				tine(o, 0.18 + 0.09 * j, run[j], 0.22, 0.8)
			for j in 4:
				tine(o, 0.8 + 0.02 * j, [523.3, 659.3, 784.0, 1046.5][j], 0.2, 1.8)
			S.room(o, 0.6, 0.35)
			S.lp1(o, 7000.0)
		"alert":
			o = S.buf(1.4)
			S.fm(o, 0.0, 659.3, 2.0, 1.4, 0.2, 0.45, 0.9)
			S.fm(o, 0.22, 493.9, 2.0, 1.4, 0.2, 0.45, 1.0)
			S.lp1(o, 3000.0)
			S.room(o, 0.35, 0.2)
		"hazard_on":
			o = S.buf(3.2)
			S.tick(o, 0.0, 0.3, 1500.0, 161)
			S.fm(o, 0.0, 146.8, 1.41, 4.0, 0.3, 0.55, 3.0)
			S.modal(o, 0.0, 146.8, 0.3, [1.0, 2.0, 2.76, 3.52], [1.0, 0.45, 0.3, 0.15], [3.0, 1.8, 1.0, 0.6])
			S.room(o, 0.6, 0.3)
			S.lp1(o, 4000.0)
		"fire":
			o = S.buf(1.5)
			S.noise(o, 0.0, 0.7, 0.45, 1, 300.0, 1800.0, 1.2, 171, 0.25, 0.4)
			for j in 14:
				S.tick(o, rng.r(0.1, 0.95), rng.r(0.08, 0.3), rng.r(1500.0, 3800.0), rng.i(1, 9999), 0.006)
			for t: float in [0.05, 0.3]:
				S.modal(o, t, 620.0, 0.28, [1.0, 2.76, 4.1], [1.0, 0.35, 0.15], [0.5, 0.25, 0.12])
			S.room(o, 0.35, 0.2)
			S.lp1(o, 5500.0)
		"fire_out":
			o = S.buf(1.0)
			S.noise(o, 0.0, 0.5, 0.45, 1, 1800.0, 600.0, 0.7, 181, 0.008, 0.35)
			S.noise(o, 0.05, 0.9, 0.08, 1, 2600.0, 2200.0, 0.8, 182, 0.06, 0.5, 0.25)
			S.thud(o, 0.0, 180.0, 90.0, 0.2, 0.08)
			S.lp1(o, 3500.0)
		"disease":
			o = S.buf(1.3)
			S.tone(o, 0.0, 1.0, 220.0, 165.0, S.TRI, 0.3, 0.08, 0.3, 5.0, 0.02)
			S.tone(o, 0.0, 1.0, 223.0, 163.0, S.TRI, 0.3, 0.08, 0.3, 4.3, 0.02)
			for j in 5:
				S.partial(o, rng.r(0.1, 0.8), rng.r(280.0, 360.0), 0.15, 0.06, 0.003, rng.r(450.0, 560.0), 0.04)
			S.lp1(o, 1500.0)
			S.room(o, 0.3, 0.2)
		"speed":
			o = S.buf(0.1)
			for j in 2:
				S.modal(o, 0.028 * j, 1500.0 + 150.0 * v + 200.0 * j, 0.45, WOOD_R, WOOD_A, [0.03, 0.02, 0.01])
				S.tick(o, 0.028 * j, 0.25, 3000.0, 191 + v + j)
			S.lp1(o, 6500.0)
		"expedition":
			o = S.buf(1.3)
			for t: float in [0.0, 0.16]:
				S.modal(o, t, 1400.0, 0.28, [1.0, 1.48, 2.2], [1.0, 0.5, 0.25], [0.55, 0.35, 0.2])
			for j in 6:
				wood(o, 0.35 + 0.07 * j + rng.r(-0.01, 0.01), 480.0 + rng.r(-30.0, 30.0), 0.18, 0.04, 201 + j)
			S.lp1(o, 4500.0)
			S.room(o, 0.35, 0.2)
		"construction_done":
			o = S.buf(0.8)
			for t: float in [0.0, 0.12]:
				S.modal(o, t, 900.0 + 40.0 * v, 0.3, TIN_R, TIN_A, [0.08, 0.05, 0.04, 0.03, 0.02])
				S.tick(o, t, 0.25, 1800.0, 211 + v)
			wood(o, 0.3, 587.3 * (1.0 + 0.05 * v), 0.4, 0.1, 213)
			wood(o, 0.38, 784.0 * (1.0 + 0.05 * v), 0.45, 0.14, 214)
			S.room(o, 0.3, 0.2)
			S.lp1(o, 6500.0)
		"repair_done":
			o = S.buf(0.7)
			for j in 5:
				S.tick(o, 0.025 * j, 0.25, 2800.0 - 80.0 * j, 221 + j, 0.005)
			tin(o, 0.18, 1200.0, 0.35, 0.25)
			S.lp1(o, 6000.0)
		"contract_done":
			o = S.buf(1.4)
			S.thud(o, 0.0, 140.0, 70.0, 0.8, 0.12)
			S.noise(o, 0.0, 0.06, 0.35, 0, 1500.0, 1200.0, 0.7, 231, 0.001, 0.05)
			S.modal(o, 0.22, 990.0, 0.3, [1.0, 2.37, 3.9], [1.0, 0.4, 0.2], [1.0, 0.4, 0.2])
			S.lp1(o, 5000.0)
			S.room(o, 0.35, 0.2)
		"research_done":
			o = S.buf(1.6)
			for j in 8:
				var f := 3000.0 - 150.0 * j
				S.tick(o, 0.03 * j, 0.25, f, 241 + j, 0.006)
				S.modal(o, 0.03 * j, 1400.0 - 40.0 * j, 0.15, WOOD_R, WOOD_A, [0.03, 0.02, 0.01])
			tine(o, 0.3, 659.3, 0.3, 1.1)
			tine(o, 0.3, 987.8, 0.22, 1.1)
			S.room(o, 0.4, 0.25)
			S.lp1(o, 7000.0)
		_:
			o = PackedFloat32Array()
	return o
