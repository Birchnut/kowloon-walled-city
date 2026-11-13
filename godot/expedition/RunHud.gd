extends Control
## 직접 줍기 HUD(원래 해상도로 또렷하게): 하트, 소란 게이지, 손에 든 것, 배낭 띠, 지도, 도시 소식, 안내, 배너.

const RunCfg = preload("res://expedition/RunCfg.gd")
const RunArt = preload("res://expedition/RunArt.gd")
const Actor = preload("res://expedition/RunActor.gd")

var world: RefCounted = null
var font: Font
var font_b: Font
var s: int = 3               # HUD 배율(1080p=3, 720p=2)
var t := 0.0
var banner := ""
var banner_t := 0.0
var room_title := ""
var room_t := 0.0
var hurt_t := 0.0
var ticker_lines: Array = []
var ticker_t := 0.0
var muted := false
var slot_rects: Array = []
var noise_shown := 0.0
var boss_flash := 0.0
var nameplate_t := 0.0


func _ready() -> void:
	font = load("res://assets/fonts/Galmuri11.ttf")
	font_b = load("res://assets/fonts/Galmuri11-Bold.ttf")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func bind(w: RefCounted) -> void:
	world = w
	banner = ""
	room_title = ""
	noise_shown = 0.0


func fs(k: float = 1.0) -> int:
	return int(round(8 * s * k))


func flash_hurt() -> void:
	hurt_t = 0.35


func on_event(e: Dictionary) -> void:
	match str(e["t"]):
		"banner":
			banner = e["text"]
			banner_t = 2.2
		"boss_intro":
			nameplate_t = 2.4
			banner_t = 0.0
		"room":
			room_title = "깊이 %d · %s" % [e["depth"], e["name"]]
			room_t = 2.5


func tick(dt: float) -> void:
	t += dt
	banner_t = maxf(0.0, banner_t - dt)
	room_t = maxf(0.0, room_t - dt)
	hurt_t = maxf(0.0, hurt_t - dt)
	boss_flash = maxf(0.0, boss_flash - dt)
	nameplate_t = maxf(0.0, nameplate_t - dt)
	if world != null:
		noise_shown = lerpf(noise_shown, world.noise, 1.0 - exp(-dt * 10.0))
	queue_redraw()


func slot_at(p: Vector2) -> int:
	for k in slot_rects.size():
		if (slot_rects[k] as Rect2).has_point(p):
			return k
	return -1


func _draw() -> void:
	var vs := get_viewport_rect().size
	s = maxi(1, int(round(vs.y / 360.0)))
	if world == null:
		return
	var p: Actor = world.player
	var pad := 6 * s
	for k in 6:
		var bw0 := (6 - k) * 14.0 * s
		var a0 := 0.025
		draw_rect(Rect2(0, 0, vs.x, bw0), Color(0, 0, 0, a0))
		draw_rect(Rect2(0, vs.y - bw0, vs.x, bw0), Color(0, 0, 0, a0))
		draw_rect(Rect2(0, 0, bw0, vs.y), Color(0, 0, 0, a0))
		draw_rect(Rect2(vs.x - bw0, 0, bw0, vs.y), Color(0, 0, 0, a0))
	# 맞았을 때 붉은 테두리 / 체력이 낮으면 맥박
	var edge := hurt_t / 0.35 * 0.55
	if p.hp <= 3 and p.state != "down":
		edge = maxf(edge, 0.18 + 0.12 * sin(t * 6.0))
	if edge > 0.01:
		var bw := 18.0 * s
		var c := Color(0.8, 0.05, 0.05, edge)
		draw_rect(Rect2(0, 0, vs.x, bw), c)
		draw_rect(Rect2(0, vs.y - bw, vs.x, bw), c)
		draw_rect(Rect2(0, 0, bw, vs.y), c)
		draw_rect(Rect2(vs.x - bw, 0, bw, vs.y), c)
	# ---- 왼쪽 위: 하트·소란·손
	var hs := (s + 1) * 7
	for k in int(ceil(p.max_hp / 2.0)):
		var key := "heart_empty"
		if p.hp >= k * 2 + 2:
			key = "heart"
		elif p.hp == k * 2 + 1:
			key = "heart_half"
		var hp_bob := 0.0
		if p.hp <= 3 and key != "heart_empty":
			hp_bob = -absf(sin(t * 6.0)) * s
		draw_texture_rect(RunArt.tex(key), Rect2(pad + k * (hs + s * 2), pad + hp_bob, hs, hs), false)
	var ny := pad + hs + 4 * s
	var nw := 100 * s
	var nmax := RunCfg.f("noise_max", 100)
	var u := clampf(noise_shown / nmax, 0.0, 1.0)
	_text(Vector2(pad, ny + fs()), "소란", Color(0.85, 0.82, 0.78), fs())
	var bx := pad + 28 * s
	draw_rect(Rect2(bx - s, ny + s, nw + 2 * s, 7 * s), Color(0.08, 0.06, 0.08))
	var ncol := Color(0.95, 0.75, 0.25).lerp(Color(1.0, 0.25, 0.2), u)
	if u > 0.85:
		ncol = ncol.lerp(Color.WHITE, 0.3 + 0.3 * sin(t * 18.0))
	draw_rect(Rect2(bx, ny + 2 * s, nw * u, 5 * s), ncol)
	for k in range(1, 4):
		draw_rect(Rect2(bx + nw * k / 4.0, ny + 2 * s, s, 5 * s), Color(0, 0, 0, 0.4))
	if world.noise_level >= world.events_total():
		_text(Vector2(bx + nw + 5 * s, ny + fs()), "더 갈 데 없음", Color(1, 0.45, 0.35), fs())
	elif world.noise_level > 0:
		_text(Vector2(bx + nw + 5 * s, ny + fs()), "%d단계" % world.noise_level, Color(1, 0.45, 0.35), fs())
	if world.hushing:
		_text(Vector2(bx + nw * 0.35, ny - 2 * s), "숨죽임…", Color(0.7, 0.85, 1.0), fs(0.8))
	var hy := ny + 12 * s
	_text(Vector2(pad, hy + fs()), "손", Color(0.85, 0.82, 0.78), fs())
	for k in RunCfg.i("throw_carry_max", 3):
		var r := Rect2(bx + k * 12 * s, hy + s, 10 * s, 9 * s)
		draw_rect(r, Color(0.08, 0.06, 0.08, 0.7))
		if k < world.held.size():
			var tex := RunArt.tex(str(world.held[k]))
			var ts := tex.get_size() * s
			draw_texture_rect(tex, Rect2(r.get_center() - ts / 2, ts), false)
	var mm := int(world.time) / 60
	var ss := int(world.time) % 60
	_text(Vector2(pad, hy + 14 * s + fs()), "%d:%02d" % [mm, ss], Color(0.65, 0.62, 0.6), fs())
	# ---- 오른쪽 위: 도시 소식 + 지도
	var tw := 150 * s
	var tx := vs.x - tw - pad
	draw_rect(Rect2(tx, pad, tw, 30 * s), Color(0.06, 0.05, 0.07, 0.78))
	draw_rect(Rect2(tx, pad, tw, 30 * s), Color(0.5, 0.45, 0.4, 0.5), false, 1.0)
	_text(Vector2(tx + 4 * s, pad + fs()), "성채 소식", Color(0.95, 0.8, 0.45), fs(0.8))
	for k in mini(2, ticker_lines.size()):
		var line: String = ticker_lines[k]
		_text(Vector2(tx + 4 * s, pad + fs() + (k + 1) * 10 * s), line, Color(0.85, 0.85, 0.82, 1.0 if k == 0 else 0.7), fs(0.8), tw - 8 * s)
	_minimap(Rect2(tx, pad + 33 * s, tw, 70 * s))
	# ---- 위 가운데: 두목 체력, 배너, 방 이름
	var b: Actor = world.boss
	if b != null and not b.dead and b.state != "dormant":
		var bw2 := 160 * s
		var bxx := vs.x / 2 - bw2 / 2
		_text_c(Vector2(vs.x / 2, pad + fs()), str(RunCfg.skin().get("boss", {}).get("name", "두목")), Color(1, 0.85, 0.5), fs())
		draw_rect(Rect2(bxx - s, pad + 11 * s, bw2 + 2 * s, 6 * s), Color(0.08, 0.06, 0.08))
		draw_rect(Rect2(bxx, pad + 12 * s, bw2 * float(b.hp) / b.max_hp, 4 * s), Color(0.9, 0.3, 0.2).lerp(Color.WHITE, boss_flash * 3.0))
		if int(b.data.get("phase", 1)) == 2:
			draw_rect(Rect2(bxx + bw2 / 2.0 - s, pad + 10 * s, 2 * s, 8 * s), Color(1, 0.85, 0.4))
	if nameplate_t > 0.0:
		# 두목 이름판: 위아래 띠 + 큰 이름 + 한 줄
		var na := minf(1.0, nameplate_t * 2.0) * minf(1.0, (2.4 - nameplate_t) * 4.0)
		var ny0 := vs.y * 0.62
		draw_rect(Rect2(0, ny0 - fs(3.2), vs.x, fs(4.6)), Color(0.05, 0.03, 0.04, 0.75 * na))
		draw_rect(Rect2(0, ny0 - fs(3.2), vs.x, 2 * s), Color(0.95, 0.75, 0.2, na))
		draw_rect(Rect2(0, ny0 + fs(1.4) - 2 * s, vs.x, 2 * s), Color(0.95, 0.75, 0.2, na))
		var bsk: Dictionary = RunCfg.skin().get("boss", {})
		_text_c(Vector2(vs.x / 2, ny0 - fs(0.6)), str(bsk.get("name", "두목")), Color(1, 0.9, 0.6, na), fs(3.0), true)
		_text_c(Vector2(vs.x / 2, ny0 + fs(0.9)), str(bsk.get("sub", "")), Color(0.85, 0.8, 0.75, na), fs(1.0))
	if banner_t > 0.0:
		var a := minf(1.0, banner_t * 2.0)
		var by := vs.y * 0.24
		var w := font_b.get_string_size(banner, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(2.0)).x
		draw_rect(Rect2(vs.x / 2 - w / 2 - 12 * s, by - fs(2.0) - 2 * s, w + 24 * s, fs(2.0) + 10 * s), Color(0.05, 0.04, 0.06, 0.7 * a))
		_text_c(Vector2(vs.x / 2, by), banner, Color(1, 0.92, 0.75, a), fs(2.0), true)
	if room_t > 0.0 and banner_t <= 0.0:
		var a2 := minf(1.0, room_t * 2.0)
		_text_c(Vector2(vs.x / 2, vs.y * 0.2), room_title, Color(0.9, 0.88, 0.8, a2), fs(1.3))
	# ---- 아래: 배낭 띠 + 안내
	_pack_strip(vs)
	if world.prompt != "":
		_text_c(Vector2(vs.x / 2, vs.y - 44 * s), world.prompt, Color(1, 0.95, 0.8), fs(1.1))
	if muted:
		_text(Vector2(pad, vs.y - pad), "소리 꺼짐 (M)", Color(0.7, 0.7, 0.7), fs(0.8))


func _pack_strip(vs: Vector2) -> void:
	slot_rects.clear()
	var open: bool = world.pack_open
	var cs := (20 if not open else 30) * s
	var gap := 2 * s
	var n: int = world.pack.size()
	var total := n * cs + (n - 1) * gap + cs + 6 * s
	var x0 := vs.x / 2 - total / 2.0
	var y0 := vs.y - cs - 6 * s if not open else vs.y / 2 - cs / 2.0
	if open:
		draw_rect(Rect2(0, 0, vs.x, vs.y), Color(0, 0, 0, 0.45))
		_text_c(Vector2(vs.x / 2, y0 - 26 * s), "배낭", Color(1, 0.9, 0.7), fs(1.6), true)
		var msg := "왼쪽 클릭·1~6 칸째 내려놓기  ·  오른쪽 클릭·Shift+숫자 한 묶음만  ·  Tab 닫기"
		if not world.item_under.is_empty():
			var ug: String = world.item_under["good"]
			var us: int = world.bundle_stars(ug)
			msg = "발밑: %s (가치 %s) — 바꿀 칸을 누르세요" % [RunCfg.good_name(ug), "●".repeat(us) + "○".repeat(5 - us)]
		_text_c(Vector2(vs.x / 2, y0 - 12 * s), msg, Color(0.9, 0.88, 0.82), fs())
	for k in n:
		var r := Rect2(x0 + k * (cs + gap), y0, cs, cs)
		slot_rects.append(r)
		var sl: Variant = world.pack[k]
		var hover := open and r.has_point(get_local_mouse_position())
		draw_rect(r, Color(0.07, 0.06, 0.08, 0.85))
		draw_rect(r, Color(1, 0.85, 0.4) if hover else Color(0.45, 0.4, 0.36), false, float(s))
		_text(r.position + Vector2(2 * s, fs(0.8)), str(k + 1), Color(0.6, 0.58, 0.55), fs(0.8))
		if sl != null:
			var tex := RunArt.tex("good_" + str(sl["good"]))
			var is_ := tex.get_size() * (s * (2 if not open else 3) * 0.6)
			draw_texture_rect(tex, Rect2(r.get_center() - is_ / 2 - Vector2(0, 2 * s), is_), false)
			var cap := int(RunCfg.good(sl["good"]).get("cap", 3))
			for bb in cap:
				draw_rect(Rect2(r.position.x + 3 * s + bb * 4 * s, r.end.y - 4 * s, 3 * s, 2 * s), RunCfg.good_color(sl["good"]) if bb < int(sl["bundles"]) else Color(0.25, 0.22, 0.22))
			if (world.wanted as Array).has(sl["good"]):
				_text(r.position + Vector2(r.size.x - 8 * s, fs(0.8)), "★", Color(1, 0.85, 0.3), fs(0.8))
			if open:
				_text_c(Vector2(r.get_center().x, r.end.y + 9 * s), "%s %d" % [RunCfg.good(sl["good"]).get("short", ""), sl["units"]], Color(0.9, 0.88, 0.82), fs())
				var stars: int = world.bundle_stars(sl["good"])
				_text_c(Vector2(r.get_center().x, r.end.y + 19 * s), "가치 " + "●".repeat(stars) + "○".repeat(5 - stars), Color(1, 0.85, 0.4), fs(0.8))
	# 도시에 모자란 것
	if not (world.wanted as Array).is_empty():
		var names: Array = []
		for g in world.wanted:
			names.append(RunCfg.good_name(g))
		var wy := y0 - 4 * s if not open else y0 + cs + 30 * s
		_text_c(Vector2(vs.x / 2, wy), "★ 지금 도시에 모자란 것: " + " · ".join(PackedStringArray(names)), Color(1, 0.85, 0.4, 0.9), fs(0.9))
	# 큰 짐 칸
	var br := Rect2(x0 + n * (cs + gap) + 6 * s, y0, cs, cs)
	draw_rect(br, Color(0.12, 0.1, 0.05, 0.85))
	draw_rect(br, Color(0.95, 0.75, 0.25, 0.8 if not world.big.is_empty() else 0.3), false, float(s))
	if not world.big.is_empty():
		var tex2 := RunArt.tex("big")
		var is2 := tex2.get_size() * s * (1.2 if not open else 1.8)
		draw_texture_rect(tex2, Rect2(br.get_center() - is2 / 2, is2), false)
	else:
		_text_c(br.get_center() + Vector2(0, fs(0.4)), "큰 짐", Color(0.6, 0.5, 0.3, 0.6), fs(0.8))


func _minimap(area: Rect2) -> void:
	draw_rect(area, Color(0.06, 0.05, 0.07, 0.45))
	var rooms: Array = world.rooms
	var maxg := Vector2i.ZERO
	for r in rooms:
		maxg = Vector2i(maxi(maxg.x, r["g"].x), maxi(maxg.y, r["g"].y))
	var cell := minf((area.size.x - 8 * s) / (maxg.x + 1), (area.size.y - 8 * s) / (maxg.y + 1))
	var rw := cell * 0.72
	var rh := rw * 0.62
	var o := area.position + Vector2(4 * s, 4 * s) + Vector2((area.size.x - 8 * s - cell * (maxg.x + 1)) / 2, (area.size.y - 8 * s - cell * (maxg.y + 1)) / 2)
	var known := {}
	for r in rooms:
		if world.visited.has(r["id"]):
			known[r["id"]] = true
			for l in r["links"]:
				known[l] = true
	for r in rooms:
		if not known.has(r["id"]):
			continue
		var c: Vector2 = o + Vector2(r["g"]) * cell + Vector2(cell / 2, cell / 2)
		for l in r["links"]:
			if l > r["id"] and known.has(l):
				var c2: Vector2 = o + Vector2(rooms[l]["g"]) * cell + Vector2(cell / 2, cell / 2)
				draw_line(c, c2, Color(0.5, 0.45, 0.4), float(s))
	for r in rooms:
		if not known.has(r["id"]):
			continue
		var c: Vector2 = o + Vector2(r["g"]) * cell + Vector2(cell / 2, cell / 2)
		var rr := Rect2(c - Vector2(rw, rh) / 2, Vector2(rw, rh))
		var vis: bool = world.visited.has(r["id"])
		var col := Color(0.32, 0.28, 0.25) if vis else Color(0.15, 0.13, 0.13)
		if r["kind"] == "boss" and vis:
			col = Color(0.45, 0.18, 0.15)
		draw_rect(rr, col)
		draw_rect(rr, Color(1, 0.85, 0.4) if r["id"] == world.cur_room else Color(0.5, 0.45, 0.4), false, float(s) if r["id"] == world.cur_room else 1.0)
		if not vis:
			_text_c(c + Vector2(0, fs(0.35)), "?", Color(0.6, 0.55, 0.5), fs(0.8))
		elif r.get("has_exit", false):
			draw_circle(c + Vector2(rw / 2 - 3 * s, -rh / 2 + 3 * s), 2.0 * s, Color(0.4, 1.0, 0.5))
		if r["kind"] == "boss" and vis:
			_text_c(c + Vector2(0, fs(0.35)), "두목", Color(1, 0.6, 0.5), fs(0.7))
		if r["id"] == world.cur_room:
			var pr: Rect2i = r["rect"]
			var rel: Vector2 = (world.player.pos / 16.0 - Vector2(pr.position)) / Vector2(pr.size)
			draw_circle(rr.position + rel * rr.size, 1.5 * s, Color.WHITE)


func _text(p: Vector2, s_: String, col: Color, size_: int, max_w: float = -1) -> void:
	var o := p.round()
	draw_string(font, o + Vector2(0, s), s_, HORIZONTAL_ALIGNMENT_LEFT, max_w, size_, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, o, s_, HORIZONTAL_ALIGNMENT_LEFT, max_w, size_, col)


func _text_c(p: Vector2, s_: String, col: Color, size_: int, bold: bool = false) -> void:
	var f := font_b if bold else font
	var w := f.get_string_size(s_, HORIZONTAL_ALIGNMENT_LEFT, -1, size_).x
	var o := (p - Vector2(w / 2.0, 0)).round()
	draw_string(f, o + Vector2(0, s), s_, HORIZONTAL_ALIGNMENT_LEFT, -1, size_, Color(0, 0, 0, col.a * 0.8))
	draw_string(f, o, s_, HORIZONTAL_ALIGNMENT_LEFT, -1, size_, col)
