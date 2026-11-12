extends Control
## 시작 화면 · 멈춤 · 결과 화면. 버튼은 직접 그린다(픽셀 글꼴, 마우스·키 둘 다).

const RunCfg = preload("res://expedition/RunCfg.gd")
const RunArt = preload("res://expedition/RunArt.gd")

signal action(id: String)

var mode := ""               # "" start pause result
var data: Dictionary = {}
var font: Font
var font_b: Font
var s := 3
var t := 0.0
var buttons: Array = []      # {rect, label, id}
var line := ""

const LINES := {
	"exit": [
		"살아서 나왔다. 그게 이 동네의 수익률이다.",
		"배낭은 무겁고 발걸음은 가볍다. 반대가 아니라 다행이다.",
		"아무도 쫓아오지 않았다. 아마도.",
	],
	"boss": [
		"큰형은 오늘부로 정년퇴직했다. 퇴직금은 우리가 챙겼다.",
		"압축기를 압축했다. 관리사무소에 보고할 생각은 없다.",
		"두목 방까지 갔다 온 사람은 말이 짧아진다. 할 말이 없어서다.",
	],
	"down": [
		"눈을 떠 보니 리어카 위였다. 누가 끌었는지는 묻지 않기로 했다.",
		"절반은 잃었다. 나머지 절반은 운이다.",
		"고물 야적장 1, 우리 0. 재경기는 내일.",
	],
}


func _ready() -> void:
	font = load("res://assets/fonts/Galmuri11.ttf")
	font_b = load("res://assets/fonts/Galmuri11-Bold.ttf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_mode(m: String, d: Dictionary = {}) -> void:
	mode = m
	data = d
	visible = m != ""
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	if m == "result":
		var arr: Array = LINES.get(str(d.get("outcome", "exit")), LINES["exit"])
		line = arr[int(d.get("seed", 0)) % arr.size()]
	queue_redraw()


func _process(dt: float) -> void:
	t += dt
	if visible:
		queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for b in buttons:
			if (b["rect"] as Rect2).has_point(ev.position):
				action.emit(b["id"])
				accept_event()
				return


func fs(k: float = 1.0) -> int:
	return int(round(8 * s * k))


func _draw() -> void:
	buttons.clear()
	var vs := get_viewport_rect().size
	s = maxi(1, int(round(vs.y / 360.0)))
	match mode:
		"start": _draw_start(vs)
		"pause": _draw_pause(vs)
		"result": _draw_result(vs)


func _panel(r: Rect2) -> void:
	draw_rect(r, Color(0.07, 0.06, 0.08, 0.94))
	draw_rect(r, Color(0.55, 0.45, 0.35), false, float(s))
	draw_rect(r.grow(-3 * s), Color(0.3, 0.25, 0.2), false, 1.0)


func _button(c: Vector2, label: String, id: String, w: float = 0.0) -> void:
	var tw := font_b.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(1.2)).x
	var bw := maxf(w, tw + 20 * s)
	var r := Rect2(c - Vector2(bw / 2, 9 * s), Vector2(bw, 18 * s))
	var hover := r.has_point(get_local_mouse_position())
	draw_rect(r, Color(0.35, 0.22, 0.15) if hover else Color(0.2, 0.15, 0.12))
	draw_rect(r, Color(1, 0.8, 0.45) if hover else Color(0.65, 0.5, 0.35), false, float(s))
	_tc(Vector2(c.x, c.y + fs(0.45)), label, Color(1, 0.93, 0.8), fs(1.2), true)
	buttons.append({"rect": r, "id": id})


func _tc(p: Vector2, s_: String, col: Color, size_: int, bold: bool = false) -> void:
	var f := font_b if bold else font
	var w := f.get_string_size(s_, HORIZONTAL_ALIGNMENT_LEFT, -1, size_).x
	var o := (p - Vector2(w / 2.0, 0)).round()
	draw_string(f, o + Vector2(0, s), s_, HORIZONTAL_ALIGNMENT_LEFT, -1, size_, Color(0, 0, 0, col.a * 0.8))
	draw_string(f, o, s_, HORIZONTAL_ALIGNMENT_LEFT, -1, size_, col)


func _tl(p: Vector2, s_: String, col: Color, size_: int, bold: bool = false) -> void:
	var f := font_b if bold else font
	draw_string(f, p.round() + Vector2(0, s), s_, HORIZONTAL_ALIGNMENT_LEFT, -1, size_, Color(0, 0, 0, col.a * 0.8))
	draw_string(f, p.round(), s_, HORIZONTAL_ALIGNMENT_LEFT, -1, size_, col)


func _tr(p: Vector2, s_: String, col: Color, size_: int) -> void:
	var w := font.get_string_size(s_, HORIZONTAL_ALIGNMENT_LEFT, -1, size_).x
	_tl(p - Vector2(w, 0), s_, col, size_)


func _draw_start(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.04, 0.06))
	# 바닥에 깔린 고철 무늬
	for k in 60:
		var x := RunArt.hash01(k, 1, 90) * vs.x
		var y := vs.y * 0.62 + RunArt.hash01(k, 2, 91) * vs.y * 0.38
		draw_rect(Rect2(x, y, (4 + RunArt.hash01(k, 3, 92) * 18) * s, (2 + RunArt.hash01(k, 4, 93) * 5) * s), Color(0.18 + RunArt.hash01(k, 5) * 0.1, 0.13, 0.11, 0.8))
	var cx := vs.x / 2
	_tc(Vector2(cx, vs.y * 0.13), "직접 줍기", Color(0.95, 0.75, 0.45), fs(1.4))
	_tc(Vector2(cx, vs.y * 0.13 + fs(3.2)), "고물 야적장", Color(1, 0.95, 0.85), fs(3.0), true)
	_tc(Vector2(cx, vs.y * 0.13 + fs(4.8)), "쌓인 차체, 녹슨 담, 그리고 압축기 \"큰형\". 주로 나오는 것: 철제 · 고물 · 전자 폐품", Color(0.8, 0.78, 0.72), fs())
	var r := Rect2(cx - 200 * s, vs.y * 0.33, 400 * s, 118 * s)
	_panel(r)
	var stock: Dictionary = data.get("stock", {})
	var x0 := r.position.x + 12 * s
	var y := r.position.y + 16 * s
	_tl(Vector2(x0, y), "남은 재고", Color(0.95, 0.8, 0.5), fs(1.1), true)
	_tl(Vector2(x0 + 200 * s, y), "위험도", Color(0.95, 0.8, 0.5), fs(1.1), true)
	var dg := int(data.get("danger", 2))
	for k in 5:
		var star := "■" if k < dg else "□"
		_tl(Vector2(x0 + 245 * s + k * 10 * s, y), star, Color(1, 0.35, 0.3) if k < dg else Color(0.4, 0.35, 0.35), fs(1.1))
	_tl(Vector2(x0 + 200 * s, y + 14 * s), "지도 번호 %d" % int(data.get("seed", 0)), Color(0.7, 0.68, 0.62), fs())
	_tl(Vector2(x0 + 200 * s, y + 26 * s), "방 6~8개 · 출구 2곳 · 맨 안쪽에 두목", Color(0.7, 0.68, 0.62), fs())
	var ids: Array = RunCfg.goods().keys()
	var maxv := 1
	for g in stock:
		maxv = maxi(maxv, int(stock[g]))
	var k2 := 0
	for g in ids:
		if not stock.has(g):
			continue
		var yy := y + 10 * s + k2 * 12 * s
		draw_texture_rect(RunArt.tex("good_" + g), Rect2(x0, yy, 10 * s, 10 * s), false)
		_tl(Vector2(x0 + 14 * s, yy + fs()), RunCfg.good_name(g), Color(0.9, 0.88, 0.82), fs())
		draw_rect(Rect2(x0 + 68 * s, yy + 3 * s, 90 * s, 5 * s), Color(0.15, 0.12, 0.12))
		draw_rect(Rect2(x0 + 68 * s, yy + 3 * s, 90 * s * int(stock[g]) / maxv, 5 * s), RunCfg.good_color(g))
		_tl(Vector2(x0 + 162 * s, yy + fs()), str(int(stock[g])), Color(0.8, 0.78, 0.72), fs())
		k2 += 1
	_tl(Vector2(x0 + 200 * s, y + 46 * s), "조작", Color(0.95, 0.8, 0.5), fs(1.1), true)
	var ctl := ["WASD 이동 · 마우스 조준", "왼쪽 클릭 쇠파이프 · 오른쪽 클릭 던지기", "Space 구르기(무적) · E 꾹 뒤지기/나가기", "Tab 배낭 · Esc 멈춤 · M 소리 · F2 자동"]
	for k in ctl.size():
		_tl(Vector2(x0 + 200 * s, y + 58 * s + k * 11 * s), ctl[k], Color(0.8, 0.78, 0.72), fs(0.9))
	_button(Vector2(cx - 70 * s, r.end.y + 26 * s), "들어가기 (Enter)", "enter", 120 * s)
	_button(Vector2(cx + 70 * s, r.end.y + 26 * s), "다른 지도 (R)", "reroll", 120 * s)
	if str(data.get("source", "")) == "sample":
		_tc(Vector2(cx, vs.y - 10 * s), "도시와 아직 연결 안 됨 — 견본 재고로 연습 중", Color(0.5, 0.48, 0.45), fs(0.8))


func _draw_pause(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var r := Rect2(vs.x / 2 - 90 * s, vs.y / 2 - 70 * s, 180 * s, 140 * s)
	_panel(r)
	_tc(Vector2(vs.x / 2, r.position.y + 22 * s), "멈춤", Color(1, 0.9, 0.7), fs(1.8), true)
	_tc(Vector2(vs.x / 2, r.position.y + 36 * s), "도시는 계속 돈다. 아마도.", Color(0.7, 0.68, 0.62), fs(0.9))
	_button(Vector2(vs.x / 2, r.position.y + 56 * s), "계속 (Esc)", "resume", 140 * s)
	_button(Vector2(vs.x / 2, r.position.y + 78 * s), "처음부터 (R)", "restart", 140 * s)
	_button(Vector2(vs.x / 2, r.position.y + 100 * s), "소리 끄기/켜기 (M)", "mute", 140 * s)
	_button(Vector2(vs.x / 2, r.position.y + 122 * s), "포기하고 나가기 (Q)", "giveup", 140 * s)


func _draw_result(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.035, 0.05, 0.92))
	var oc := str(data.get("outcome", "exit"))
	var title: String = {"exit": "무사히 빠져나왔다", "boss": "큰형을 눕히고 나왔다", "down": "실려 나왔다"}.get(oc, oc)
	var tcol: Color = {"exit": Color(0.6, 1, 0.65), "boss": Color(1, 0.85, 0.35), "down": Color(1, 0.45, 0.4)}.get(oc, Color.WHITE)
	_tc(Vector2(vs.x / 2, vs.y * 0.12), title, tcol, fs(2.6), true)
	_tc(Vector2(vs.x / 2, vs.y * 0.12 + fs(2.2)), line, Color(0.85, 0.82, 0.75), fs(1.1))
	var r := Rect2(vs.x / 2 - 210 * s, vs.y * 0.27, 420 * s, 150 * s)
	_panel(r)
	var cols := [["들고 나온 것", "carried", Color(0.6, 1, 0.65)], ["두고 온 것", "left", Color(0.85, 0.8, 0.7)], ["잃은 것", "lost", Color(1, 0.5, 0.45)]]
	for c in cols.size():
		var x0 := r.position.x + 12 * s + c * 136 * s
		var y0 := r.position.y + 16 * s
		_tl(Vector2(x0, y0), cols[c][0], cols[c][2], fs(1.1), true)
		var dd: Dictionary = data.get(cols[c][1], {})
		var k := 0
		var total := 0
		for g in RunCfg.goods().keys():
			var n := int(dd.get(g, 0))
			if n <= 0:
				continue
			total += n
			var yy := y0 + 8 * s + k * 12 * s
			draw_texture_rect(RunArt.tex("good_" + g), Rect2(x0, yy, 10 * s, 10 * s), false)
			_tl(Vector2(x0 + 14 * s, yy + fs()), "%s %d" % [RunCfg.good_name(g), n], Color(0.9, 0.88, 0.82), fs())
			k += 1
		if k == 0:
			_tl(Vector2(x0, y0 + 8 * s + fs()), "없음", Color(0.5, 0.48, 0.45), fs())
	var finds: Array = data.get("finds", [])
	var fy := r.end.y - 26 * s
	if not finds.is_empty():
		_tl(Vector2(r.position.x + 12 * s, fy), "발견: " + ", ".join(PackedStringArray(finds)), Color(1, 0.85, 0.4), fs())
	var kills: Dictionary = data.get("kills", {})
	var kn := 0
	for kk in kills:
		kn += int(kills[kk])
	var tt := float(data.get("time", 0.0))
	_tl(Vector2(r.position.x + 12 * s, r.end.y - 12 * s), "걸린 시간 %d:%02d · 가 본 방 %d/%d · 눕힌 것 %d · 소란 %d단계" % [int(tt) / 60, int(tt) % 60, int(data.get("rooms_visited", 0)), int(data.get("rooms_total", 0)), kn, int(data.get("noise_level", 0))], Color(0.7, 0.68, 0.62), fs())
	_button(Vector2(vs.x / 2 - 70 * s, r.end.y + 24 * s), "도시로 (Enter)", "city", 120 * s)
	_button(Vector2(vs.x / 2 + 70 * s, r.end.y + 24 * s), "한 판 더 (R)", "again", 120 * s)
