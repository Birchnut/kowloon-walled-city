extends Node2D
## 직접 줍기 화면(저해상도 SubViewport 안). RunWorld를 읽어 그리고, events로 손맛(흔들림·먼지·글자)을 낸다.
## 색의 약속: 빨강 = 곧 맞는 자리(예고), 노랑 = 지금 칠 수 있는 곳·주울 것, 초록 = 출구.

const RunCfg = preload("res://expedition/RunCfg.gd")
const RunArt = preload("res://expedition/RunArt.gd")
const DungeonGen = preload("res://expedition/DungeonGen.gd")
const Actor = preload("res://expedition/RunActor.gd")

const RED := Color(1.0, 0.22, 0.2)
const YEL := Color(1.0, 0.82, 0.25)
const GRN := Color(0.4, 1.0, 0.5)
const CHUNK := 32

var world: RefCounted = null
var map_layer: Node2D
var ents: Node2D
var air: Node2D
var cam: Camera2D
var font: Font
var cam_pos := Vector2.ZERO
var shake := 0.0
var shake_rng := RandomNumberGenerator.new()
var parts: Array = []        # {p, v, life, max, col, size, g, z, vz}
var texts: Array = []        # {p, text, col, life, big}
var rings: Array = []        # {p, r, life}
var t := 0.0
var sfx: Node = null         # RunSfx (없어도 된다)
var hud: Node = null         # 방 이름·배너를 넘긴다
var view_size := Vector2(480, 270)
var aim_world := Vector2.ZERO
var fog := true


func _ready() -> void:
	font = load("res://assets/fonts/Galmuri9.ttf")
	map_layer = Node2D.new()
	add_child(map_layer)
	ents = Node2D.new()
	add_child(ents)
	ents.draw.connect(_draw_ents)
	air = Node2D.new()
	add_child(air)
	air.draw.connect(_draw_air)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	shake_rng.seed = 5


func bind(w: RefCounted) -> void:
	world = w
	for c in map_layer.get_children():
		c.queue_free()
	parts.clear()
	texts.clear()
	rings.clear()
	var W: int = world.w
	var H: int = world.h
	for cy in int(ceil(H / float(CHUNK))):
		for cx in int(ceil(W / float(CHUNK))):
			var img := RunArt.map_chunk(world.tiles, W, H, cx, cy, CHUNK)
			if img == null:
				continue
			var s := Sprite2D.new()
			s.texture = ImageTexture.create_from_image(img)
			s.centered = false
			s.position = Vector2(cx * CHUNK * 16, cy * CHUNK * 16)
			map_layer.add_child(s)
	cam_pos = world.player.pos
	cam.position = cam_pos


func world_from_screen(screen_p: Vector2, screen_size: Vector2, scale_i: int) -> Vector2:
	return cam.position + cam.offset + (screen_p - screen_size / 2.0) / float(scale_i)


func tick(dt: float) -> void:
	t += dt
	if world == null:
		return
	_consume_events()
	var p: Actor = world.player
	var look: Vector2 = (aim_world - p.pos)
	look = look.limit_length(140.0) * 0.22
	var target: Vector2 = p.pos + look + Vector2(0, -6)
	cam_pos = cam_pos.lerp(target, 1.0 - exp(-dt * 9.0))
	shake = maxf(0.0, shake - dt * 18.0)
	var so := Vector2.ZERO
	if shake > 0.05:
		so = Vector2(shake_rng.randf_range(-1, 1), shake_rng.randf_range(-1, 1)) * shake
	cam.position = cam_pos.round()
	cam.offset = so.round()
	for k in range(parts.size() - 1, -1, -1):
		var q: Dictionary = parts[k]
		q["life"] -= dt
		if q["life"] <= 0:
			parts.remove_at(k)
			continue
		q["p"] += q["v"] * dt
		q["v"] *= exp(-dt * q.get("drag", 4.0))
		if q.has("vz"):
			q["vz"] -= 300.0 * dt
			q["z"] = maxf(0.0, q["z"] + q["vz"] * dt)
	for k in range(texts.size() - 1, -1, -1):
		texts[k]["life"] -= dt
		texts[k]["p"] += Vector2(0, -14 * dt)
		if texts[k]["life"] <= 0:
			texts.remove_at(k)
	for k in range(rings.size() - 1, -1, -1):
		rings[k]["life"] -= dt
		if rings[k]["life"] <= 0:
			rings.remove_at(k)
	ents.queue_redraw()
	air.queue_redraw()


func _consume_events() -> void:
	var evs: Array = world.events
	for e in evs:
		match str(e["t"]):
			"sfx":
				if sfx != null:
					sfx.play(e["id"])
			"shake":
				shake = maxf(shake, float(e["a"]))
			"dust":
				var col := Color("8a7860") if e.get("col", "") != "brick" else Color("a0503a")
				for k in int(e["n"]):
					var d: Vector2 = e["dir"]
					var v := (d * 40.0 + Vector2.from_angle(randf() * TAU) * randf_range(10, 40))
					parts.append({"p": e["pos"] + Vector2(randf_range(-3, 3), randf_range(-2, 2)), "v": v, "life": randf_range(0.25, 0.5), "max": 0.5, "col": col, "size": 2.0 if randf() < 0.5 else 1.0})
			"step":
				if randf() < 0.7:
					parts.append({"p": e["pos"] + Vector2(randf_range(-2, 2), 0), "v": Vector2(randf_range(-8, 8), -6), "life": 0.3, "max": 0.3, "col": Color(0.55, 0.47, 0.38, 0.8), "size": 1.0})
			"hit":
				var dir: Vector2 = e["dir"]
				for k in 7:
					parts.append({"p": e["pos"], "v": (dir.rotated(randf_range(-0.9, 0.9)) * randf_range(60, 140)), "life": randf_range(0.12, 0.25), "max": 0.25, "col": Color(1, 0.95, 0.7), "size": 1.0, "drag": 9.0})
				parts.append({"p": e["pos"], "v": Vector2.ZERO, "life": 0.08, "max": 0.08, "col": Color.WHITE, "size": 9.0, "star": true})
			"kill":
				for k in 10:
					parts.append({"p": e["pos"], "v": Vector2.from_angle(randf() * TAU) * randf_range(30, 90), "life": randf_range(0.3, 0.6), "max": 0.6, "col": Color("8a7860"), "size": 2.0})
				texts.append({"p": e["pos"] + Vector2(0, -12), "text": _kill_word(e["kind"]), "col": Color.WHITE, "life": 0.9})
			"swish":
				pass
			"hurt":
				for k in 6:
					parts.append({"p": e["pos"], "v": Vector2.from_angle(randf() * TAU) * randf_range(40, 80), "life": 0.3, "max": 0.3, "col": Color(1, 0.3, 0.3), "size": 1.0})
				if hud != null:
					hud.flash_hurt()
			"pickup":
				texts.append({"p": e["pos"] + Vector2(0, -18), "text": e["text"], "col": Color.from_string(str(e["col"]), Color.WHITE), "life": 0.9})
				for k in 5:
					parts.append({"p": e["pos"] + Vector2(0, -6), "v": Vector2.from_angle(-PI / 2 + randf_range(-1, 1)) * randf_range(30, 60), "life": 0.3, "max": 0.3, "col": YEL, "size": 1.0})
			"text":
				var cs := {"red": RED, "yellow": YEL, "grey": Color(0.75, 0.75, 0.75), "white": Color.WHITE, "pink": Color("ff9ab0")}
				texts.append({"p": e["pos"], "text": e["text"], "col": cs.get(e.get("col", "white"), Color.WHITE), "life": 1.0 if not e.get("big", false) else 0.8, "big": e.get("big", false)})
			"ring":
				rings.append({"p": e["pos"], "r": e["r"], "life": 0.6})
			"crash":
				for k in 16:
					parts.append({"p": e["pos"] + Vector2(randf_range(-10, 10), 0), "v": Vector2.from_angle(randf() * TAU) * randf_range(20, 80), "life": randf_range(0.3, 0.7), "max": 0.7, "col": [Color("7a4a34"), Color("5f6a74"), Color("8a7a52")][k % 3], "size": 2.0, "z": 10.0, "vz": randf_range(30, 90)})
			"stomp":
				for k in 18:
					parts.append({"p": e["pos"] + Vector2(randf_range(-18, 18), randf_range(-12, 12)), "v": Vector2.from_angle(randf() * TAU) * randf_range(40, 110), "life": randf_range(0.3, 0.6), "max": 0.6, "col": Color("8a7860"), "size": 2.0})
			"wave":
				rings.append({"p": e["pos"], "r": 60.0, "life": 0.8, "col": RED})
			"room", "banner", "boss_intro", "boss_dead", "finished":
				if hud != null:
					hud.on_event(e)
				if e["t"] == "boss_dead":
					for k in 40:
						parts.append({"p": e["pos"], "v": Vector2.from_angle(randf() * TAU) * randf_range(40, 160), "life": randf_range(0.4, 1.0), "max": 1.0, "col": [YEL, Color("5e6873"), Color("ff6030")][k % 3], "size": 2.0})
			"search_start":
				if sfx != null:
					sfx.loop_search(true)
			"search_stop":
				if sfx != null:
					sfx.loop_search(false)
	evs.clear()
	if sfx != null and world.search_target.is_empty():
		sfx.loop_search(false)


func _kill_word(kind: String) -> String:
	return {"rat": "찍", "dog": "깨갱", "guard": "기절", "rival": "꽥"}.get(kind, "퍽")


# ------------------------------------------------------------------ 그리기: 바닥 + 몸
func _draw_ents() -> void:
	if world == null:
		return
	var ci := ents
	var p: Actor = world.player
	var vis := Rect2(cam.position - view_size / 2 - Vector2(64, 64), view_size + Vector2(128, 128))
	# 누전 웅덩이
	for wv in world.wires:
		if not (wv["box"] as Rect2).intersects(vis):
			continue
		var stt: String = wv["state"]
		for c in wv["cells"]:
			var cp := Vector2(c) * 16.0
			if stt == "warn":
				if fmod(t * 14.0 + c.x * 0.7 + c.y * 1.3, 2.0) < 1.0:
					ci.draw_rect(Rect2(cp, Vector2(16, 16)), Color(0.4, 0.75, 1.0, 0.22))
				if randf() < 0.08:
					ci.draw_rect(Rect2(cp + Vector2(randi() % 14, randi() % 14), Vector2(2, 2)), Color(0.8, 0.95, 1))
			elif stt == "active":
				ci.draw_rect(Rect2(cp, Vector2(16, 16)), Color(0.55, 0.85, 1.0, 0.45))
				var a := cp + Vector2(randf() * 16, randf() * 16)
				var pts := PackedVector2Array([a])
				for k in 4:
					a += Vector2(randf_range(-6, 6), randf_range(-6, 6))
					pts.append(a)
				ci.draw_polyline(pts, Color(0.9, 0.97, 1.0), 1.0)
	# 소리 고리(던진 깡통)
	for r in rings:
		var u: float = 1.0 - r["life"] / 0.6
		ci.draw_arc(r["p"], float(r["r"]) * (0.25 + 0.75 * u), 0, TAU, 40, Color(r.get("col", Color(1, 1, 1)), 0.5 * (1.0 - u)), 1.0)
	# 출구
	for ex in world.exits:
		if not ex["active"]:
			continue
		var tex := RunArt.tex("exit_" + str(ex["kind"]))
		ci.draw_texture(tex, (ex["pos"] as Vector2) - tex.get_size() / 2)
		var bob := sin(t * 4.0) * 2.0
		_arrow_down(ci, (ex["pos"] as Vector2) + Vector2(0, -16 + bob), GRN)
		_label(ci, (ex["pos"] as Vector2) + Vector2(0, -24 + bob), "출구", GRN)
		if is_same(world.exit_target, ex) and world.exit_progress > 0.0:
			_progress_ring(ci, ex["pos"], 11.0, world.exit_progress / RunCfg.f("exit_hold", 0.9), GRN)
	# 더미
	var near_pile: Dictionary = {}
	var nd := 24.0
	for pl in world.piles:
		if not vis.has_point(pl["pos"]):
			continue
		var empty: bool = pl["bundles"].is_empty() and pl["rummaged"]
		var tex := RunArt.tex("pile_empty" if empty else "pile")
		ci.draw_texture(tex, (pl["pos"] as Vector2) - Vector2(tex.get_width() / 2.0, tex.get_height() - 5))
		if not empty:
			var ph: float = fmod(t * 0.8 + pl["pos"].x * 0.013, 1.6)
			if ph < 0.25:
				var gp: Vector2 = pl["pos"] + Vector2(-4 + int(pl["pos"].y) % 9, -9)
				var s := 2.0 * (1.0 - absf(ph - 0.125) / 0.125)
				ci.draw_line(gp - Vector2(s, 0), gp + Vector2(s, 0), YEL, 1.0)
				ci.draw_line(gp - Vector2(0, s), gp + Vector2(0, s), YEL, 1.0)
			var d: float = p.pos.distance_to(pl["pos"])
			if d < nd:
				nd = d
				near_pile = pl
	if not near_pile.is_empty() and p.state != "down":
		if is_same(world.search_target, near_pile):
			var depth: int = world.rooms[near_pile["room"]]["depth"]
			var per := RunCfg.f("search_per_bundle", 0.5) + depth * RunCfg.f("search_depth_extra", 0.04) + (RunCfg.f("search_first_extra", 0.15) if near_pile["popped"] == 0 else 0.0)
			_progress_ring(ci, (near_pile["pos"] as Vector2) + Vector2(0, -14), 6.0, near_pile["progress"] / per, YEL)
			for k in 2:
				parts.append({"p": (near_pile["pos"] as Vector2) + Vector2(randf_range(-8, 8), -4), "v": Vector2(randf_range(-30, 30), randf_range(-50, -20)), "life": 0.25, "max": 0.25, "col": Color("8a7860"), "size": 1.0})
		else:
			_key_hint(ci, (near_pile["pos"] as Vector2) + Vector2(0, -18), "E")
	# 경비원 손전등(벽에 잘린 원뿔)
	for e: Actor in world.enemies:
		if e.dead or e.kind != "guard" or not vis.has_point(e.pos):
			continue
		_cone(ci, e)
	# 바닥 예고
	for e: Actor in world.enemies:
		if e.dead or not vis.has_point(e.pos):
			continue
		if e.state == "tele":
			var u := clampf(e.st / maxf(0.01, e.timer), 0.0, 1.0)
			match e.kind:
				"dog":
					var L := RunCfg.f("dog_lunge_speed", 255) * RunCfg.f("dog_lunge_time", 0.3)
					_lane(ci, e.pos, e.lock_dir, L, 9.0, u)
				"rat":
					_lane(ci, e.pos, e.lock_dir, RunCfg.f("rat_dash_speed", 210) * RunCfg.f("rat_dash_time", 0.18), 5.0, u)
				"guard":
					_sector(ci, e.pos, e.lock_dir, RunCfg.f("guard_reach", 26) + 6, deg_to_rad(60), u)
				"rival":
					_sector(ci, e.pos, e.lock_dir, 28.0, 1.0, u)
	for j in world.junks:
		if j["state"] == "warn":
			var u: float = clampf(j["t"] / RunCfg.f("junk_tele", 0.95), 0.0, 1.0)
			var rr := RunCfg.f("junk_radius", 19)
			ci.draw_circle(j["target"], rr * (0.4 + 0.6 * u), Color(0, 0, 0, 0.25 + 0.35 * u))
			ci.draw_arc(j["target"], rr, 0, TAU, 28, Color(RED, 0.5 + 0.5 * sin(t * 30.0)), 1.0)
	_draw_boss_ground(ci)
	# 떨어진 물건
	for it in world.items:
		var ip: Vector2 = it["pos"]
		if not vis.has_point(ip):
			continue
		var tex: Texture2D
		match str(it["kind"]):
			"good": tex = RunArt.tex("good_" + str(it["good"]))
			"throw": tex = RunArt.tex(str(it["tk"]))
			"heal": tex = RunArt.tex("heal")
			"big": tex = RunArt.tex("big")
		var bob := 0.0 if it["z"] > 0 else (sin(t * 5.0 + ip.x) * 1.0 if it["kind"] != "throw" else 0.0)
		ci.draw_texture(RunArt.tex("shadow"), ip - Vector2(6, 2), Color(1, 1, 1, 0.6))
		ci.draw_texture(tex, (ip - tex.get_size() / 2 + Vector2(0, -3 - it["z"] + bob)).round())
		if it["kind"] == "good" and is_same(world.item_under, it):
			ci.draw_rect(Rect2(ip - Vector2(7, 10), Vector2(14, 14)), Color(YEL, 0.6 + 0.4 * sin(t * 8)), false, 1.0)
		if it["kind"] == "big":
			ci.draw_arc(ip + Vector2(0, -3), 11 + sin(t * 4) * 1.5, 0, TAU, 24, Color(YEL, 0.7), 1.0)
	# 몸통들(위아래 순서)
	var bodies: Array = []
	for e: Actor in world.enemies:
		if vis.has_point(e.pos) and not (e.dead and e.st > 0.6):
			bodies.append(e)
	bodies.append(p)
	for j in world.junks:
		if j["state"] != "fallen" and vis.has_point(j["pos"]):
			bodies.append(j)
	for cb in world.cubes:
		bodies.append(cb)
	bodies.sort_custom(func(a: Variant, b: Variant) -> bool: return _ypos(a) < _ypos(b))
	for b in bodies:
		if b is Dictionary:
			if b.has("cell"):
				_draw_junk(ci, b)
			else:
				var tex := RunArt.tex("cube")
				var life: float = b["life"] - b["t"]
				if life > 0.8 or fmod(t * 10.0, 1.0) < 0.6:
					ci.draw_texture(tex, (b["pos"] as Vector2) - Vector2(8, 10))
		elif b == p:
			_draw_player(ci)
		else:
			_draw_enemy(ci, b)
	# 방 안개(아직 안 가 본 방)
	if fog:
		for r in world.rooms:
			if world.visited.has(r["id"]):
				continue
			var rc: Rect2i = r["rect"]
			ci.draw_rect(Rect2(Vector2(rc.position) * 16.0, Vector2(rc.size) * 16.0), Color(0.04, 0.03, 0.05, 0.72))


func _ypos(b: Variant) -> float:
	if b is Dictionary:
		return (b["pos"] as Vector2).y + (4.0 if b.has("cell") else 0.0)
	return (b as Actor).pos.y


func _draw_player(ci: CanvasItem) -> void:
	var p: Actor = world.player
	var tex := RunArt.tex("char_player")
	ci.draw_texture(RunArt.tex("shadow"), p.pos - Vector2(6, 2))
	var blink := p.inv > 0.0 and fmod(t * 16.0, 1.0) < 0.4
	var col := Color(1, 1, 1, 0.45 if blink else 1.0)
	if p.flash > 0.0:
		col = Color(4, 0.6, 0.6, 1)
	var dir := p.face
	var colx := 1
	var flip := false
	if absf(dir.x) > absf(dir.y) * 0.9:
		colx = 0
		flip = dir.x > 0
	elif dir.y < 0:
		colx = 2
	var row := 0
	if p.vel.length() > 20 and p.state != "roll":
		row = [1, 0, 2, 0][int(p.anim * 2.0) % 4]
	var bob := 0.0
	if p.state == "down":
		ci.draw_set_transform(p.pos + Vector2(0, -4), PI / 2 * minf(1.0, world.down_t * 4.0), Vector2.ONE)
		ci.draw_texture_rect_region(tex, Rect2(-8, -16, 16, 32), Rect2(colx * 16, 0, 16, 32), Color(0.8, 0.8, 0.8))
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	if p.state == "roll":
		var u := p.st / maxf(0.01, p.timer)
		var ang := u * TAU * signf(p.lock_dir.x if absf(p.lock_dir.x) > 0.1 else 1.0)
		ci.draw_set_transform(p.pos + Vector2(0, -8), ang, Vector2(1, 0.8))
		ci.draw_texture_rect_region(tex, Rect2(-8, -12, 16, 24), Rect2(colx * 16, 8, 16, 24), col)
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	# 쇠파이프(몸 뒤로 갈 때 먼저 그린다)
	var behind := dir.y < -0.3
	if behind:
		_draw_pipe(ci, p)
	ci.draw_set_transform(p.pos + Vector2(0, -12 + bob), 0, Vector2(-1 if flip else 1, 1))
	ci.draw_texture_rect_region(tex, Rect2(-8, -18, 16, 32), Rect2(colx * 16, row * 32, 16, 32), col)
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if not behind:
		_draw_pipe(ci, p)
	# 손에 든 던질 것 개수
	if not world.held.is_empty():
		for k in world.held.size():
			ci.draw_rect(Rect2(p.pos + Vector2(-5 + k * 4, 6), Vector2(3, 2)), Color(0.85, 0.85, 0.88))


func _draw_pipe(ci: CanvasItem, p: Actor) -> void:
	var base := p.pos + Vector2(0, -8)
	var aim_a := p.face.angle()
	var wind := RunCfg.f("swing_windup", 0.06)
	var act := RunCfg.f("swing_active", 0.08)
	var a := aim_a + 1.1
	var len := 12.0
	if p.state == "swing":
		var half := deg_to_rad(RunCfg.f("swing_arc_deg", 120)) / 2.0
		var la := p.lock_dir.angle()
		if p.st < wind:
			a = la - half - 0.3
		elif p.st < wind + act:
			var u := (p.st - wind) / act
			a = la - half + 2.0 * half * u
			# 휘두른 자국
			var pts := PackedVector2Array()
			for k in 9:
				var aa := la - half + 2.0 * half * (float(k) / 8.0) * u
				pts.append(base + Vector2.from_angle(aa) * (RunCfg.f("swing_range", 27) - 2))
			ci.draw_polyline(pts, Color(1, 1, 1, 0.9), 3.0)
		else:
			a = la + half
			var fade := 1.0 - (p.st - wind - act) / RunCfg.f("swing_recover", 0.17)
			if fade > 0:
				var pts2 := PackedVector2Array()
				for k in 9:
					pts2.append(base + Vector2.from_angle(la - half + 2.0 * half * float(k) / 8.0) * (RunCfg.f("swing_range", 27) - 2))
				ci.draw_polyline(pts2, Color(1, 1, 1, 0.5 * fade), 2.0)
		len = 16.0
	var tip := base + Vector2.from_angle(a) * len
	ci.draw_line(base + Vector2.from_angle(a) * 3, tip, OUT_COL, 3.0)
	ci.draw_line(base + Vector2.from_angle(a) * 3, tip, Color("9aa2aa"), 1.0)

const OUT_COL := Color("1a1418")


func _draw_enemy(ci: CanvasItem, e: Actor) -> void:
	var shake_o := Vector2.ZERO
	if e.state == "tele":
		shake_o = Vector2(sin(t * 70.0), 0) * 1.0
	var col := Color.WHITE
	if e.flash > 0:
		col = Color(5, 5, 5, 1)
	elif e.state == "tele":
		col = Color(1.0, 0.65, 0.65)
	elif e.state == "stun":
		col = Color(0.8, 0.8, 1.0)
	if e.dead:
		col = Color(1, 1, 1, maxf(0.0, 1.0 - e.st / 0.6))
	var flip := e.face.x < 0
	var pos := e.pos + shake_o
	match e.kind:
		"rat":
			ci.draw_texture(RunArt.tex("shadow"), pos - Vector2(5, 2), Color(1, 1, 1, 0.5))
			var tex := RunArt.tex("rat%d" % (int(e.anim * 3.0) % 2))
			ci.draw_set_transform(pos + Vector2(0, -3), 0 if not e.dead else PI, Vector2(-1 if flip else 1, 1))
			ci.draw_texture(tex, Vector2(-7, -5), col)
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"dog":
			ci.draw_texture(RunArt.tex("shadow"), pos - Vector2(8, 2), Color(1, 1, 1, 0.6))
			var key := "dog%d" % (int(e.anim * 2.0) % 2)
			if e.state == "tele":
				key = "dog_tele"
			elif e.state == "lunge":
				key = "dog_lunge"
			var tex := RunArt.tex(key)
			ci.draw_set_transform(pos + Vector2(0, -5), 0 if not e.dead else PI, Vector2(-1 if flip else 1, 1))
			ci.draw_texture(tex, Vector2(-11, -8), col)
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			if e.state == "recover":
				_label(ci, pos + Vector2(0, -16), "헥헥", Color(0.8, 0.8, 0.8))
		"guard", "rival":
			ci.draw_texture(RunArt.tex("shadow"), pos - Vector2(6, 2))
			var tex := RunArt.tex("char_guard" if e.kind == "guard" else "char_rival")
			var colx := 1
			var fl := false
			if absf(e.face.x) > absf(e.face.y) * 0.9:
				colx = 0
				fl = e.face.x > 0
			elif e.face.y < 0:
				colx = 2
			var row: int = [1, 0, 2, 0][int(e.anim * 2.0) % 4] if e.vel.length() > 8 else 0
			if e.dead:
				ci.draw_set_transform(pos + Vector2(0, -4), PI / 2, Vector2.ONE)
				ci.draw_texture_rect_region(tex, Rect2(-8, -16, 16, 32), Rect2(colx * 16, 0, 16, 32), col)
				ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			else:
				ci.draw_set_transform(pos + Vector2(0, -12), 0, Vector2(-1 if fl else 1, 1))
				ci.draw_texture_rect_region(tex, Rect2(-8, -18, 16, 32), Rect2(colx * 16, row * 32, 16, 32), col)
				ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				# 곤봉 / 보따리
				if e.kind == "guard":
					var ba := e.face.angle() + (-2.2 if e.state == "tele" else (1.2 if e.state == "strike" else 0.9))
					var b0 := pos + Vector2(0, -9)
					ci.draw_line(b0, b0 + Vector2.from_angle(ba) * 11, OUT_COL, 3.0)
					ci.draw_line(b0, b0 + Vector2.from_angle(ba) * 11, Color("2a2a30"), 1.0)
				else:
					var n: int = e.data.get("bag", []).size()
					if n > 0:
						ci.draw_circle(pos + Vector2(5, -10), 3 + n * 0.6, Color("8a7650"))
					if e.state == "search":
						_label(ci, pos + Vector2(0, -26), "뒤적" + ".".repeat(int(t * 3) % 4), Color(0.8, 0.8, 0.8))
	# 예고 표시: 빨간 느낌표
	if e.state == "tele" and not e.dead:
		_bang(ci, pos + Vector2(0, -24 if e.kind in ["guard", "rival"] else -14), RED)
	# 경비원 의심 게이지
	if e.kind == "guard" and not e.aware and e.alert > 0.05 and not e.dead:
		var gp := pos + Vector2(0, -28)
		ci.draw_rect(Rect2(gp - Vector2(5, 1), Vector2(10, 3)), Color(0, 0, 0, 0.7))
		ci.draw_rect(Rect2(gp - Vector2(5, 1), Vector2(10 * minf(1.0, e.alert), 3)), YEL)
		_label(ci, gp + Vector2(0, -6), "?", YEL)
	# 체력(맞은 적만)
	if e.hp < e.max_hp and e.max_hp > 1 and not e.dead:
		var hp_p := pos + Vector2(-6, 4)
		for k in e.max_hp:
			ci.draw_rect(Rect2(hp_p + Vector2(k * 3, 0), Vector2(2, 2)), RED if k < e.hp else Color(0.2, 0.2, 0.2))


func _draw_junk(ci: CanvasItem, j: Dictionary) -> void:
	var tex := RunArt.tex("junk")
	var p: Vector2 = j["pos"]
	var rot := 0.0
	if j["state"] == "warn":
		var u: float = j["t"] / RunCfg.f("junk_tele", 0.95)
		rot = sin(t * 40.0) * 0.06 * (1.0 + u * 2.0)
		if randf() < 0.3:
			parts.append({"p": p + Vector2(randf_range(-6, 6), -20), "v": Vector2(randf_range(-10, 10), 30), "life": 0.3, "max": 0.3, "col": Color("7a6a50"), "size": 1.0})
		_bang(ci, p + Vector2(0, -32), RED)
	ci.draw_set_transform(p + Vector2(0, 6), rot, Vector2.ONE)
	ci.draw_texture(tex, Vector2(-tex.get_width() / 2.0, -tex.get_height()))
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_boss_ground(ci: CanvasItem) -> void:
	var b: Actor = world.boss
	if b == null:
		return
	var rr: Rect2 = world._room_rect(b.room)
	# 레일(위·아래 벽을 따라)
	ci.draw_rect(Rect2(rr.position.x, rr.position.y + 34, rr.size.x, 2), Color("3a3430"))
	ci.draw_rect(Rect2(rr.position.x, rr.end.y - 4, rr.size.x, 2), Color("3a3430"))
	if b.dead:
		return
	# 침 뱉기 표시
	for m in world.marks:
		var u: float = clampf(m["t"] / m["dur"], 0.0, 1.0)
		ci.draw_circle(m["pos"], m["r"], Color(RED, 0.15 + 0.25 * u))
		ci.draw_arc(m["pos"], m["r"] * (1.6 - 0.6 * u), 0, TAU, 24, RED, 1.0)
		ci.draw_arc(m["pos"], m["r"], 0, TAU, 24, Color(RED, 0.8), 1.0)
	if b.state == "stomp_tele":
		var u := clampf(b.st / b.timer, 0.0, 1.0)
		var sw := RunCfg.f("boss_stomp_w", 38)
		var sh := RunCfg.f("boss_stomp_h", 30)
		var r := Rect2(b.pos - Vector2(sw, sh) / 2, Vector2(sw, sh))
		ci.draw_rect(r, Color(RED, 0.18 + 0.3 * u))
		ci.draw_rect(r.grow(8.0 * (1.0 - u)), RED, false, 1.0)
	elif b.state in ["sweep_tele", "sweep"]:
		var sx: float = b.data["sweep_x"]
		var gap: Vector2 = b.data["gap"]
		var hw := RunCfg.f("boss_sweep_w", 12) / 2.0
		var col := Color(RED, 0.25 + (0.25 * sin(t * 20.0) if b.state == "sweep_tele" else 0.2))
		ci.draw_rect(Rect2(sx - hw, rr.position.y + 36, hw * 2, gap.x - rr.position.y - 36), col)
		ci.draw_rect(Rect2(sx - hw, gap.y, hw * 2, rr.end.y - gap.y), col)
		ci.draw_rect(Rect2(sx - hw - 2, gap.x, hw * 2 + 4, gap.y - gap.x), Color(GRN, 0.35), false, 1.0)
		if b.state == "sweep_tele":
			var dir: float = b.data["sweep_dir"]
			for k in 3:
				var ax := sx + dir * (12 + k * 10 + fmod(t * 30.0, 10.0))
				_chevron(ci, Vector2(ax, rr.get_center().y), dir, RED)
			# 진행 방향 전체에 옅은 띠
			var from := sx
			var to := rr.end.x if dir > 0 else rr.position.x
			ci.draw_rect(Rect2(minf(from, to), rr.position.y + 36, absf(to - from), 2), Color(RED, 0.4))
		else:
			ci.draw_rect(Rect2(sx - 3, rr.position.y + 34, 6, rr.size.y - 36), Color("2a2a30"))
			for y in range(int(rr.position.y + 36), int(rr.end.y), 8):
				if y > gap.x - 4 and y < gap.y:
					continue
				ci.draw_rect(Rect2(sx - 4, y, 8, 4), YEL if (y / 8) % 2 == 0 else Color("1c1a1a"))
	# 그림자(머리 아래)
	if b.state != "dormant":
		var lift := _boss_lift(b)
		var sc := 1.0 - lift / 60.0
		ci.draw_texture_rect(RunArt.tex("shadow_big"), Rect2(b.pos - Vector2(20, 7) * sc, Vector2(40, 14) * sc), false, Color(1, 1, 1, 0.9))


func _boss_lift(b: Actor) -> float:
	match b.state:
		"stomp_tele": return 24.0 + sin(t * 50.0) * 1.0
		"stuck": return 0.0
		"rise": return 20.0 * clampf(b.st / maxf(0.01, b.timer), 0.0, 1.0)
		"dead": return 0.0
	return 20.0


func _draw_air() -> void:
	if world == null:
		return
	var ci := air
	# 두목 머리(공중)
	var b: Actor = world.boss
	if b != null and b.state != "dormant":
		var rr: Rect2 = world._room_rect(b.room)
		# 문형 기중기 들보
		if not b.dead:
			ci.draw_rect(Rect2(b.pos.x - 5, rr.position.y + 30, 10, rr.size.y - 30), Color(0.25, 0.27, 0.3, 0.55))
			ci.draw_rect(Rect2(b.pos.x - 5, rr.position.y + 30, 2, rr.size.y - 30), Color(0.4, 0.42, 0.45, 0.55))
		var lift := _boss_lift(b)
		var tex := RunArt.tex("boss_head_stuck" if b.state in ["stuck", "dead"] else "boss_head")
		var col := Color.WHITE if b.flash <= 0 else Color(4, 4, 4)
		if b.dead:
			col = Color(0.5, 0.5, 0.5)
		ci.draw_texture(tex, (b.pos - Vector2(tex.get_width() / 2.0, tex.get_height() - 4 + lift)).round(), col)
		if b.state == "stuck":
			_label(ci, b.pos + Vector2(0, -40), "약점!", YEL)
			_arrow_down(ci, b.pos + Vector2(0, -32 + sin(t * 10) * 2), YEL)
		if b.state == "stomp_tele":
			_bang(ci, b.pos + Vector2(0, -44 - lift * 0.3), RED)
		# 침: 날아가는 큐브
		for m in world.marks:
			var u: float = clampf(m["t"] / m["dur"], 0.0, 1.0)
			if u > 0.35:
				var v := (u - 0.35) / 0.65
				var from: Vector2 = m["from"]
				var cp: Vector2 = from.lerp(m["pos"], v) + Vector2(0, -60.0 * 4 * v * (1 - v))
				ci.draw_texture(RunArt.tex("cube"), cp - Vector2(8, 10))
	# 던진 것
	for th in world.throws:
		var tp: Vector2 = th["pos"]
		ci.draw_texture(RunArt.tex("shadow"), tp - Vector2(6, 2), Color(1, 1, 1, 0.4))
		var tex2 := RunArt.tex(str(th["kind"]))
		ci.draw_set_transform(tp + Vector2(0, -th["z"] - 3), th["spin"], Vector2.ONE)
		ci.draw_texture(tex2, -tex2.get_size() / 2)
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# 조준 표시(던질 것이 있을 때만 착지점)
	var p: Actor = world.player
	if not world.held.is_empty() and p.state != "down":
		var to := aim_world
		var dv := to - p.pos
		if dv.length() > RunCfg.f("throw_max", 150):
			to = p.pos + dv.normalized() * RunCfg.f("throw_max", 150)
		ci.draw_arc(to, 4, 0, TAU, 12, Color(1, 1, 1, 0.35), 1.0)
	# 조각
	for q in parts:
		var a: float = clampf(q["life"] / q["max"], 0.0, 1.0)
		var c: Color = q["col"]
		if q.get("star", false):
			ci.draw_circle(q["p"], q["size"] * (0.5 + a), Color(1, 1, 1, a))
			continue
		var s: float = q["size"]
		ci.draw_rect(Rect2((q["p"] as Vector2) + Vector2(0, -q.get("z", 0.0)), Vector2(s, s)), Color(c, c.a * a))
	# 글자
	for tx in texts:
		var a2: float = clampf(tx["life"] * 2.0, 0.0, 1.0)
		if tx.get("big", false):
			_label(ci, tx["p"], tx["text"], Color(tx["col"], a2), 18)
		else:
			_label(ci, tx["p"], tx["text"], Color(tx["col"], a2))


# ------------------------------------------------------------------ 작은 도구
func _label(ci: CanvasItem, p: Vector2, s: String, col: Color, size: int = 10) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var o := (p - Vector2(w / 2.0, 0)).round()
	for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		ci.draw_string(font, o + d, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.08, 0.06, 0.08, col.a))
	ci.draw_string(font, o, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _bang(ci: CanvasItem, p: Vector2, col: Color) -> void:
	var s := 1.0 + 0.25 * sin(t * 30.0)
	ci.draw_rect(Rect2(p + Vector2(-2, -7) * s, Vector2(4, 10) * s), OUT_COL)
	ci.draw_rect(Rect2(p + Vector2(-1, -6) * s, Vector2(2, 6) * s), col)
	ci.draw_rect(Rect2(p + Vector2(-1, 1) * s, Vector2(2, 2) * s), col)


func _arrow_down(ci: CanvasItem, p: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -3), p + Vector2(4, -3), p + Vector2(0, 2)]), col)


func _chevron(ci: CanvasItem, p: Vector2, dir: float, col: Color) -> void:
	ci.draw_polyline(PackedVector2Array([p + Vector2(-3 * dir, -5), p + Vector2(2 * dir, 0), p + Vector2(-3 * dir, 5)]), col, 2.0)


func _key_hint(ci: CanvasItem, p: Vector2, k: String) -> void:
	var bob := sin(t * 6.0)
	var r := Rect2(p + Vector2(-5, -6 + bob), Vector2(10, 10))
	ci.draw_rect(r.grow(1), OUT_COL)
	ci.draw_rect(r, Color(0.92, 0.9, 0.85))
	ci.draw_string(font, r.position + Vector2(2, 9), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, OUT_COL)


func _progress_ring(ci: CanvasItem, p: Vector2, r: float, u: float, col: Color) -> void:
	ci.draw_arc(p, r, 0, TAU, 24, Color(0, 0, 0, 0.6), 3.0)
	ci.draw_arc(p, r, -PI / 2, -PI / 2 + TAU * clampf(u, 0.0, 1.0), 24, col, 2.0)


func _lane(ci: CanvasItem, from: Vector2, dir: Vector2, length: float, width: float, u: float) -> void:
	var n := Vector2(-dir.y, dir.x) * width / 2.0
	var end := from + dir * length
	var poly := PackedVector2Array([from + n, end + n, end - n, from - n])
	ci.draw_colored_polygon(poly, Color(RED, 0.12 + 0.18 * u))
	var fill_end := from + dir * length * u
	ci.draw_colored_polygon(PackedVector2Array([from + n, fill_end + n, fill_end - n, from - n]), Color(RED, 0.3))
	ci.draw_polyline(PackedVector2Array([from + n, end + n, end - n, from - n, from + n]), Color(RED, 0.7), 1.0)


func _sector(ci: CanvasItem, from: Vector2, dir: Vector2, r: float, half: float, u: float) -> void:
	var pts := PackedVector2Array([from])
	var a0 := dir.angle()
	for k in 11:
		pts.append(from + Vector2.from_angle(a0 - half + 2.0 * half * k / 10.0) * r)
	ci.draw_colored_polygon(pts, Color(RED, 0.15 + 0.2 * u))
	var pts2 := PackedVector2Array([from])
	for k in 11:
		pts2.append(from + Vector2.from_angle(a0 - half + 2.0 * half * k / 10.0) * r * u)
	ci.draw_colored_polygon(pts2, Color(RED, 0.3))
	pts.append(from)
	ci.draw_polyline(pts, Color(RED, 0.8), 1.0)


func _cone(ci: CanvasItem, e: Actor) -> void:
	var rng := RunCfg.f("guard_cone_range", 104)
	var half := deg_to_rad(RunCfg.f("guard_cone_deg", 60)) / 2.0
	var a0 := e.face.angle()
	var pts := PackedVector2Array([e.pos])
	for k in 15:
		var a := a0 - half + 2.0 * half * k / 14.0
		var d := Vector2.from_angle(a)
		var L := rng
		var s := 8.0
		while s < rng:
			if world._solid_at(e.pos + d * s):
				L = s
				break
			s += 6.0
		pts.append(e.pos + d * L)
	var col := Color(1.0, 0.95, 0.55, 0.16)
	if e.aware:
		col = Color(1.0, 0.35, 0.3, 0.2)
	elif e.alert > 0.05:
		col = Color(1.0, 0.8, 0.3, 0.22 + 0.1 * e.alert)
	if e.state in ["stun"]:
		col.a *= 0.4
	ci.draw_colored_polygon(pts, col)
	pts.append(e.pos)
	ci.draw_polyline(pts, Color(col, 0.35), 1.0)
