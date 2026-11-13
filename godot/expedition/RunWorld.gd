extends RefCounted
## 직접 줍기 한 판의 규칙(시뮬레이션). 그림·소리 없이도 돈다 — 자동 플레이어 배치가 이걸 그대로 돌린다.
## step(dt)마다 input(RunInput)을 읽는다. 화면 쪽은 events 목록(소리·흔들림·글자)을 읽고 비운다.

const RunCfg = preload("res://expedition/RunCfg.gd")
const DungeonGen = preload("res://expedition/DungeonGen.gd")
const Actor = preload("res://expedition/RunActor.gd")
const RunInput = preload("res://expedition/RunInput.gd")

const TS := 16.0
const PACK_SLOTS := 6

var dest: String = "scrap_yard"
var seed_value: int = 1
var danger: int = 2
var stock: Dictionary = {}
var dun: Dictionary = {}
var w: int = 0
var h: int = 0
var tiles: PackedByteArray
var solid: PackedByteArray
var rooms: Array = []
var astar: AStarGrid2D
var rng := RandomNumberGenerator.new()

var input: RunInput = RunInput.new()
var player: Actor
var enemies: Array = []
var boss: Actor = null
var piles: Array = []
var items: Array = []
var throws: Array = []
var junks: Array = []
var wires: Array = []
var exits: Array = []
var cubes: Array = []          # 압축 큐브(잠깐 단단한 장애물) {pos, t}
var marks: Array = []          # 바닥 경고 표시(두목 침 뱉기) {pos, r, t, dur}
var next_id: int = 1

var time: float = 0.0
var hitstop: float = 0.0
var noise: float = 0.0
var noise_level: int = 0
var pack: Array = []
var big: Dictionary = {}       # 큰 짐 {goods:{}, finds:[]}
var held: Array = []           # 손에 든 던질 것 ["can","brick"]
var pack_open: bool = false
var cur_room: int = 0
var visited: Dictionary = {}
var found: Dictionary = {}
var lost: Dictionary = {}
var kills: Dictionary = {}
var finished: bool = false
var outcome: String = ""
var result: Dictionary = {}
var boss_dead: bool = false
var reached_boss: bool = false
var max_depth_seen: int = 0
var prompt: String = ""
var search_target: Dictionary = {}
var exit_progress: float = 0.0
var exit_target: Dictionary = {}
var events: Array = []
var fx: bool = true            # false면 events를 쌓지 않는다(배치 속도)
var attack_buffer: float = 0.0
var swing_cd: float = 0.0
var roll_cd: float = 0.0
var down_t: float = 0.0
var item_under: Dictionary = {}
var last_hurt_by: String = ""
var dodges: int = 0
var hits_taken: int = 0
var hurt_log: Dictionary = {}
var hp_at_boss: int = -1
var floodlights: bool = false
var still_t: float = 0.0
var hushing: bool = false
var events_seen: Array = []
var last_event_t: float = -99.0
var wanted: Array = []        # 지금 도시에 모자란 것(CityLink.wanted)
var time_at_boss: float = -1.0


# ------------------------------------------------------------------ 시작
func setup(p_dest: String, begin: Dictionary) -> void:
	dest = p_dest
	stock = (begin.get("stock", {}) as Dictionary).duplicate()
	danger = int(begin.get("danger", 2))
	seed_value = int(begin.get("seed", 1))
	rng.seed = seed_value * 7919 + 13
	RunCfg.skin_id = RunCfg.skin_for(dest)
	var gen := DungeonGen.new()
	dun = gen.generate(seed_value, stock.duplicate(), danger)
	w = dun["w"]
	h = dun["h"]
	tiles = (dun["tiles"] as PackedByteArray).duplicate()
	rooms = dun["rooms"]
	solid.resize(w * h)
	for k in w * h:
		solid[k] = 1 if DungeonGen.is_solid_code(tiles[k]) else 0
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(TS, TS)
	astar.offset = Vector2(TS / 2, TS / 2)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in h:
		for x in w:
			if solid[y * w + x] == 1:
				astar.set_point_solid(Vector2i(x, y), true)
	pack.resize(PACK_SLOTS)
	pack.fill(null)
	player = _new_actor("player", Vector2.ZERO)
	player.hp = RunCfg.i("player_hp", 6)
	player.max_hp = player.hp
	player.radius = RunCfg.f("player_radius", 5)
	for o in dun["objects"]:
		var c: Vector2i = o["cell"]
		var p := cell_center(c)
		match str(o["type"]):
			"start":
				player.pos = p
				player.room = o["room"]
			"pile":
				piles.append({"pos": p, "cell": c, "room": o["room"], "bundles": o.get("bundles", []), "heal": o.get("heal", false), "progress": 0.0, "popped": 0, "rummaged": false, "locker": o.get("locker", false)})
			"throwable":
				items.append(_mk_item("throw", p, {"tk": o.get("kind", "can")}))
			"rat":
				var n := rng.randi_range(RunCfg.i("rat_swarm_min", 3), RunCfg.i("rat_swarm_max", 5))
				for k in n:
					_spawn_enemy("rat", p + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)), o["room"])
			"dog":
				_spawn_enemy("dog", p, o["room"])
			"guard":
				var g := _spawn_enemy("guard", p, o["room"])
				var pts: Array = []
				for pc in o.get("patrol", []):
					pts.append(cell_center(pc))
				if pts.is_empty():
					pts = [p + Vector2(-48, 0), p + Vector2(48, 0)]
				g.data["patrol"] = pts
				g.data["wp"] = 0
			"rival":
				_spawn_enemy("rival", p, o["room"])
			"junk":
				junks.append({"cell": c, "pos": p, "state": "idle", "t": 0.0, "target": p, "room": o["room"]})
			"wire":
				var cells: Array = o["cells"]
				var box := Rect2(cell_center(cells[0]), Vector2.ZERO)
				for wc in cells:
					box = box.expand(cell_center(wc))
				wires.append({"cells": cells, "phase": float(o["phase"]), "state": "idle", "box": box.grow(8), "room": o["room"], "hit": {}})
			"exit":
				exits.append({"pos": p, "kind": o.get("exit", "mid"), "room": o["room"], "active": true})
			"boss":
				boss = _new_actor("boss", p)
				boss.room = o["room"]
				boss.hp = RunCfg.i("boss_hp", 12)
				boss.max_hp = boss.hp
				boss.radius = 14
				boss.home = p
				boss.set_state("dormant")
				boss.data["phase"] = 1
	visited[player.room] = true
	cur_room = player.room
	player.face = Vector2.RIGHT
	input.aim = player.pos + Vector2(40, 0)


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * TS + TS / 2, c.y * TS + TS / 2)


func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TS)), int(floor(p.y / TS)))


func _new_actor(kind: String, p: Vector2) -> Actor:
	var a := Actor.new()
	a.id = next_id
	next_id += 1
	a.kind = kind
	a.pos = p
	a.home = p
	return a


func _spawn_enemy(kind: String, p: Vector2, room: int) -> Actor:
	var a := _new_actor(kind, p)
	a.room = room
	match kind:
		"rat":
			a.hp = RunCfg.i("rat_hp", 1); a.radius = 3.5
			a.timer = rng.randf_range(0.5, 2.0)
		"dog":
			a.hp = RunCfg.i("dog_hp", 3); a.radius = 6
			a.data["dir"] = 1.0 if rng.randf() < 0.5 else -1.0
		"guard":
			a.hp = RunCfg.i("guard_hp", 5); a.radius = 6
			a.set_state("patrol")
		"rival":
			a.hp = RunCfg.i("rival_hp", 3); a.radius = 5.5
			a.set_state("loot")
			a.data["bag"] = []
	a.max_hp = a.hp
	a.face = Vector2.DOWN.rotated(rng.randf() * TAU)
	enemies.append(a)
	return a


func _mk_item(kind: String, p: Vector2, extra: Dictionary = {}) -> Dictionary:
	var it := {"kind": kind, "pos": p, "vel": Vector2.ZERO, "z": 0.0, "vz": 0.0, "delay": 0.0, "t": 0.0}
	it.merge(extra)
	return it


func _ev(type: String, data: Dictionary = {}) -> void:
	if not fx:
		return
	data["t"] = type
	events.append(data)


# ------------------------------------------------------------------ 한 걸음
func step(dt: float) -> void:
	if finished:
		return
	if hitstop > 0.0:
		hitstop -= dt
		input.clear_edges()
		return
	if input.pack_toggle:
		pack_open = not pack_open
		_ev("sfx", {"id": "tick"})
	if input.slot_action >= 0:
		slot_action(input.slot_action)
	if input.slot_one >= 0:
		slot_drop_one(input.slot_one)
	var sdt := dt * (0.3 if pack_open else 1.0)
	time += sdt
	_player_step(sdt)
	for e: Actor in enemies:
		if not e.dead:
			_enemy_step(e, sdt)
	if boss != null and not boss.dead:
		_boss_step(sdt)
	_separate()
	_throws_step(sdt)
	_items_step(sdt)
	_hazards_step(sdt)
	_noise_step(sdt)
	_room_step()
	_prompt_step()
	for k in range(enemies.size() - 1, -1, -1):
		if enemies[k].dead and enemies[k].st > 1.5:
			enemies.remove_at(k)
	input.clear_edges()


# ------------------------------------------------------------------ 줍는 이
func _player_step(dt: float) -> void:
	var p := player
	p.st += dt
	p.squash = maxf(0.0, p.squash - dt)
	p.spin += p.spin_v * dt
	p.spin_v = move_toward(p.spin_v, 0.0, 40.0 * dt)
	if absf(p.spin_v) < 0.5:
		p.spin = lerp_angle(p.spin, 0.0, minf(1.0, dt * 12.0))
	p.inv = maxf(0.0, p.inv - dt)
	p.flash = maxf(0.0, p.flash - dt)
	roll_cd = maxf(0.0, roll_cd - dt)
	swing_cd = maxf(0.0, swing_cd - dt)
	attack_buffer = maxf(0.0, attack_buffer - dt)
	if p.state == "down":
		down_t += dt
		p.vel = p.vel.move_toward(Vector2.ZERO, 400 * dt)
		_move(p, p.vel * dt)
		if down_t > 1.4:
			_finish("down")
		return
	var aim_v := input.aim - p.pos
	if aim_v.length() > 2.0:
		p.face = aim_v.normalized()
	var mv := input.move.limit_length(1.0)
	if input.attack:
		attack_buffer = 0.15
	var speed := RunCfg.f("player_speed", 92) * soft_mult(p.pos)
	# 구르기
	if input.roll and roll_cd <= 0.0 and p.state != "roll":
		var d := mv.normalized() if mv.length() > 0.1 else p.face
		p.set_state("roll", RunCfg.f("roll_time", 0.3))
		p.lock_dir = d
		search_target = {}
		_ev("sfx", {"id": "roll"})
		_ev("dust", {"pos": p.pos, "n": 6, "dir": -d})
	if p.state == "roll":
		var u := p.st / p.timer
		p.vel = p.lock_dir * RunCfg.f("roll_speed", 205) * (1.0 - 0.55 * u * u)
		_move(p, (p.vel + p.knock) * dt)
		p.knock = p.knock.move_toward(Vector2.ZERO, 900 * dt)
		if p.st >= p.timer:
			p.set_state("idle")
			roll_cd = RunCfg.f("roll_cooldown", 0.42)
		return
	# 휘두르기
	var sw_total := RunCfg.f("swing_windup") + RunCfg.f("swing_active") + RunCfg.f("swing_recover")
	if p.state == "swing":
		if not p.hit_done and p.st >= RunCfg.f("swing_windup"):
			p.hit_done = true
			_swing_hit()
		if p.st >= sw_total:
			p.set_state("idle")
	if attack_buffer > 0.0 and p.state != "swing" and swing_cd <= 0.0:
		attack_buffer = 0.0
		p.set_state("swing")
		p.lock_dir = p.face
		swing_cd = sw_total * 0.9
		search_target = {}
		p.squash = 0.18
		_ev("sfx", {"id": "swing"})
		p.knock += p.face * 40.0
		_hear(p.pos, 50.0)
	# 던지기
	if input.throw and p.state != "swing":
		_throw()
	var target := mv * speed
	if p.state == "swing":
		target *= RunCfg.f("swing_move_mult", 0.45)
	var acc := RunCfg.f("player_accel", 1100) if mv.length() > 0.05 else RunCfg.f("player_friction", 1400)
	p.vel = p.vel.move_toward(target, acc * dt)
	_move(p, (p.vel + p.knock) * dt)
	p.knock = p.knock.move_toward(Vector2.ZERO, 700 * dt)
	if p.vel.length() > 20:
		p.anim += dt * p.vel.length() / 14.0
		if fx and int(p.anim * 2.0) != int((p.anim - dt * p.vel.length() / 14.0) * 2.0):
			_ev("step", {"pos": p.pos + Vector2(0, 4)})
	else:
		p.anim = 0.0
	_interact(dt, mv)


func _interact(dt: float, mv: Vector2) -> void:
	var p := player
	var still := mv.length() < 0.3 and p.state != "swing"
	# 출구
	exit_target = {}
	var near_pile := 99.0
	for pl in piles:
		if not (pl["bundles"].is_empty() and pl["rummaged"]):
			near_pile = minf(near_pile, p.pos.distance_to(pl["pos"]))
	for ex in exits:
		var de: float = p.pos.distance_to(ex["pos"])
		# 출구는 더 가까이 서야 하고, 더미가 더 가까우면 더미가 먼저다(뒤지다 실수로 나가지 않게)
		if ex["active"] and de < 13.0 and de < near_pile:
			exit_target = ex
	if not exit_target.is_empty() and input.interact and still:
		exit_progress += dt
		if exit_progress >= RunCfg.f("exit_hold", 0.9):
			_finish("boss" if boss_dead else "exit")
		return
	exit_progress = 0.0
	# 더미
	var best: Dictionary = {}
	var bd := 24.0
	for pl in piles:
		if pl["bundles"].is_empty() and pl["rummaged"]:
			continue
		var d := p.pos.distance_to(pl["pos"])
		if d < bd:
			bd = d
			best = pl
	if best.is_empty() or not input.interact or not still:
		if not search_target.is_empty():
			_ev("search_stop", {})
		search_target = {}
		return
	if not is_same(search_target, best):
		search_target = best
		_ev("search_start", {"pos": best["pos"]})
	var need := search_need(best)
	best["progress"] += dt
	_add_noise(RunCfg.f("noise_search", 6.0) * dt * (RunCfg.f("locker_noise_mult", 1.6) if best.get("locker", false) and best["popped"] == 0 else 1.0))
	if best.get("locker", false) and best["popped"] == 0 and fmod(best["progress"], 0.35) < dt:
		_ev("sfx", {"id": "clank"})
		_ev("dust", {"pos": best["pos"], "n": 2, "dir": Vector2.UP})
	_hear(p.pos, 46.0, dt)
	if best["progress"] >= need:
		best["progress"] = 0.0
		best["popped"] += 1
		if best["bundles"].is_empty():
			best["rummaged"] = true
			if best["heal"]:
				best["heal"] = false
				_pop_item(_mk_item("heal", best["pos"]))
				_ev("text", {"pos": best["pos"], "text": "반창고", "col": "pink"})
			else:
				_ev("text", {"pos": best["pos"], "text": "허탕", "col": "grey"})
				_ev("sfx", {"id": "tick"})
			search_target = {}
			return
		var b: Dictionary = best["bundles"].pop_front()
		found[b["good"]] = int(found.get(b["good"], 0)) + int(b["units"])
		_pop_item(_mk_item("good", best["pos"], {"good": b["good"], "units": b["units"], "bundles": 1}))
		_add_noise(RunCfg.f("noise_pop", 2.0))
		_ev("sfx", {"id": "pop"})
		if best["bundles"].is_empty():
			if best["heal"]:
				best["heal"] = false
				_pop_item(_mk_item("heal", best["pos"]))
			best["rummaged"] = true
			search_target = {}
			_ev("search_stop", {})


## 이 더미에서 다음 묶음이 나오기까지 E를 누르고 있어야 하는 초.
func search_need(pl: Dictionary) -> float:
	var depth: int = rooms[pl["room"]]["depth"]
	var per := RunCfg.f("search_per_bundle", 0.5) + depth * RunCfg.f("search_depth_extra", 0.04)
	if pl["popped"] == 0:
		per += RunCfg.f("search_first_extra", 0.15)
		if pl.get("locker", false):
			per += RunCfg.f("locker_open", 1.8)
	return per


func _pop_item(it: Dictionary) -> void:
	var a := rng.randf() * TAU
	it["vel"] = Vector2.from_angle(a) * rng.randf_range(30, 55)
	it["vz"] = 90.0
	it["z"] = 1.0
	it["delay"] = 0.35
	items.append(it)


func _swing_hit() -> void:
	var p := player
	var rng_px := RunCfg.f("swing_range", 27)
	var half := deg_to_rad(RunCfg.f("swing_arc_deg", 120)) / 2.0
	var origin := p.pos
	var any := false
	for e: Actor in enemies:
		if e.dead:
			continue
		var d: Vector2 = e.pos - origin
		if d.length() - e.radius > rng_px:
			continue
		if d.length() > 4 and absf(angle_difference(p.lock_dir.angle(), d.angle())) > half:
			continue
		if not _los(origin, e.pos):
			continue
		_hurt_enemy(e, RunCfg.i("swing_damage", 1), d.normalized(), "swing")
		any = true
	if boss != null and not boss.dead and boss.state == "stuck":
		var d2 := boss.pos - origin
		if d2.length() - 16.0 <= rng_px and absf(angle_difference(p.lock_dir.angle(), d2.angle())) <= half:
			_hurt_boss(1)
			any = true
	if any:
		_add_noise(RunCfg.f("noise_hit", 2.5))
	else:
		_ev("swish", {"pos": origin + p.lock_dir * 18})


func _throw() -> void:
	var p := player
	if held.is_empty():
		_ev("text", {"pos": p.pos + Vector2(0, -20), "text": "던질 게 없다", "col": "grey"})
		return
	var kind: String = held.pop_back()
	var to: Vector2 = plan_throw(input.aim)["to"]
	var dur := maxf(0.25, p.pos.distance_to(to) / RunCfg.f("throw_speed", 190) + 0.12)
	throws.append({"kind": kind, "from": p.pos, "to": to, "pos": p.pos, "t": 0.0, "dur": dur, "z": 0.0, "bounce": 0, "spin": 0.0})
	_ev("sfx", {"id": "throw"})


## 던지면 어디에 떨어지는가(미리 보기와 실제가 같은 계산): 사거리 안에서 벽에 막히면 그 앞.
func plan_throw(aim: Vector2) -> Dictionary:
	var from := player.pos
	var to := aim
	var dv := to - from
	if dv.length() > RunCfg.f("throw_max", 150):
		to = from + dv.normalized() * RunCfg.f("throw_max", 150)
	var n := int(from.distance_to(to) / 4.0) + 1
	var land := to
	var blocked := false
	for k in range(1, n + 1):
		var q := from.lerp(to, float(k) / n)
		if _solid_at(q):
			land = from.lerp(to, float(k - 1) / n)
			blocked = true
			break
	var dir := (to - from).normalized() if from.distance_to(to) > 1 else Vector2.RIGHT
	var bounce := land + dir * 14.0
	if _solid_at(bounce):
		bounce = land
	return {"from": from, "to": land, "bounce": bounce, "blocked": blocked}


# ------------------------------------------------------------------ 피해
func _hurt_enemy(e: Actor, dmg: int, dir: Vector2, src: String) -> void:
	if e.dead:
		return
	var sneak := e.kind == "guard" and not e.aware and src == "swing"
	if sneak:
		dmg *= 2
		_ev("text", {"pos": e.pos + Vector2(0, -22), "text": "기습", "col": "yellow"})
	e.hp -= dmg
	e.flash = 0.12
	var mass := {"rat": 0.6, "dog": 1.0, "guard": 2.2, "rival": 1.4}.get(e.kind, 1.0) as float
	e.knock += dir * RunCfg.f("swing_knockback", 170) / mass
	if e.kind == "rival":
		e.data["hostile"] = true
	e.spin_v = (12.0 if rng.randf() < 0.5 else -12.0) * (1.4 if e.kind == "rat" else 1.0) / mass
	e.squash = 0.16
	if e.kind == "dog":
		_ev("sfx", {"id": "yelp"})
	if e.kind == "guard":
		e.data["light_off"] = RunCfg.f("guard_light_drop", 1.0)
		_ev("drop_light", {"pos": e.pos, "dir": dir})
	if e.kind in ["rat", "dog", "rival"]:
		e.set_state("stun", 0.32)
	elif e.kind == "guard":
		if not e.aware:
			_alert_guard(e)
		if e.state != "tele":
			e.set_state("stun", 0.18)
	_ev("hit", {"pos": e.pos, "dir": dir})
	_ev("sfx", {"id": "hit"})
	_ev("shake", {"a": 2.5})
	hitstop = maxf(hitstop, RunCfg.f("hitstop_hit", 0.05))
	if e.hp <= 0:
		e.dead = true
		e.st = 0.0
		e.state = "dead"
		kills[e.kind] = int(kills.get(e.kind, 0)) + 1
		hitstop = maxf(hitstop, RunCfg.f("hitstop_kill", 0.09))
		_ev("kill", {"pos": e.pos, "kind": e.kind})
		if e.kind == "rat":
			_ev("sfx", {"id": "puff"})
		_ev("shake", {"a": 4.0})
		if e.kind == "rival":
			for b in e.data.get("bag", []):
				found[b["good"]] = int(found.get(b["good"], 0)) + int(b["units"])
				_pop_item(_mk_item("good", e.pos, {"good": b["good"], "units": b["units"], "bundles": 1}))
			e.data["bag"] = []
			_ev("text", {"pos": e.pos + Vector2(0, -20), "text": "보따리를 떨궜다", "col": "yellow"})


func _hurt_player(dmg: int, from: Vector2, by: String) -> bool:
	var p := player
	if p.state == "down" or finished:
		return false
	if p.state == "roll" and p.st < RunCfg.f("roll_iframes", 0.26):
		if not p.data.get("dodged", false):
			dodges += 1
			_ev("text", {"pos": p.pos + Vector2(0, -22), "text": "휙", "col": "white"})
		p.data["dodged"] = true
		return false
	if p.inv > 0.0:
		return false
	p.hp -= dmg
	hits_taken += 1
	hurt_log[by] = int(hurt_log.get(by, 0)) + 1
	last_hurt_by = by
	p.inv = RunCfg.f("hurt_iframes", 0.9)
	p.flash = 0.15
	p.squash = 0.2
	p.spin_v = 6.0 if rng.randf() < 0.5 else -6.0
	var dir := (p.pos - from).normalized() if p.pos.distance_to(from) > 0.5 else Vector2.DOWN
	p.knock = dir * 180.0
	if p.state == "swing":
		p.set_state("idle")
	search_target = {}
	hitstop = maxf(hitstop, RunCfg.f("hitstop_hurt", 0.08))
	_ev("hurt", {"pos": p.pos, "dmg": dmg})
	_ev("sfx", {"id": "hurt"})
	_ev("shake", {"a": 5.0})
	if p.hp <= 0:
		p.hp = 0
		p.set_state("down")
		down_t = 0.0
		_ev("sfx", {"id": "down"})
		_ev("banner", {"text": "털썩."})
	return true


func _hurt_boss(dmg: int) -> void:
	boss.hp -= dmg
	boss.flash = 0.12
	_ev("weak_hit", {"pos": boss.pos})
	hitstop = maxf(hitstop, RunCfg.f("hitstop_hit", 0.05))
	_ev("hit", {"pos": boss.pos, "dir": (boss.pos - player.pos).normalized()})
	_ev("sfx", {"id": "clang"})
	_ev("shake", {"a": 3.0})
	if boss.hp <= boss.max_hp / 2 and int(boss.data["phase"]) == 1:
		boss.data["phase"] = 2
		_ev("banner", {"text": str(RunCfg.skin().get("lines", {}).get("phase2", "두목이 달아올랐다"))})
		_ev("sfx", {"id": "alarm"})
		for k in 3:
			var r := _spawn_enemy("rat", boss.home + Vector2(rng.randf_range(-60, 60), -20), boss.room)
			r.aware = true
			r.set_state("chase")
	if boss.hp <= 0:
		boss.dead = true
		boss_dead = true
		boss.set_state("dead")
		kills["boss"] = 1
		hitstop = 0.25
		_ev("boss_dead", {"pos": boss.pos})
		_ev("banner", {"text": str(RunCfg.skin().get("lines", {}).get("dead", "두목이 쓰러졌다."))})
		_ev("shake", {"a": 9.0})
		_ev("sfx", {"id": "stomp"})
		var bigd: Dictionary = dun.get("big", {})
		if not bigd.is_empty():
			for g in bigd:
				found[g] = int(found.get(g, 0)) + int(bigd[g])
			var it := _mk_item("big", boss.pos, {"goods": bigd.duplicate()})
			_pop_item(it)
		var r: Dictionary = rooms[boss.room]
		var ex_cell := _free_cell_near(r["origin"] + Vector2i(13, 12))
		exits.append({"pos": cell_center(ex_cell), "kind": "boss", "room": boss.room, "active": true})
		_ev("text", {"pos": cell_center(ex_cell) + Vector2(0, -14), "text": "뒷문이 열렸다", "col": "yellow"})
		for e: Actor in enemies:
			if e.room == boss.room and not e.dead and e.kind == "rat":
				e.set_state("flee", 3.0)
				e.target = boss.pos


func _free_cell_near(c: Vector2i) -> Vector2i:
	for rad in 6:
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var n := c + Vector2i(dx, dy)
				if not _solid_cell(n):
					return n
	return c


# ------------------------------------------------------------------ 적
func _enemy_step(e: Actor, dt: float) -> void:
	e.st += dt
	e.flash = maxf(0.0, e.flash - dt)
	e.knock = e.knock.move_toward(Vector2.ZERO, 650 * dt)
	e.squash = maxf(0.0, e.squash - dt)
	e.bonk_cd = maxf(0.0, e.bonk_cd - dt)
	e.spin += e.spin_v * dt
	e.spin_v = move_toward(e.spin_v, 0.0, 30.0 * dt)
	if absf(e.spin_v) < 0.5:
		e.spin = lerp_angle(e.spin, 0.0, minf(1.0, dt * 10.0))
	if e.data.has("light_off"):
		e.data["light_off"] = float(e.data["light_off"]) - dt
		if float(e.data["light_off"]) <= 0.0:
			e.data.erase("light_off")
	var rm: Dictionary = rooms[e.room] if e.room >= 0 else {}
	# 방이 다르고 멀면 쉬게 한다(쫓던 중이 아니면) — 같은 방이거나 깨어 있는 놈만 생각한다
	var near := e.pos.distance_squared_to(player.pos) < 300.0 * 300.0
	if not near and not e.aware and e.state != "loot" and e.kind != "rival":
		return
	match e.kind:
		"rat": _ai_rat(e, dt)
		"dog": _ai_dog(e, dt)
		"guard": _ai_guard(e, dt)
		"rival": _ai_rival(e, dt)
	_move(e, (e.vel + e.knock) * dt)
	if e.vel.length() > 5:
		e.anim += dt * e.vel.length() / 12.0
		if e.state != "tele":
			e.face = e.face.slerp(e.vel.normalized(), minf(1.0, dt * 10.0)) if e.kind != "guard" or e.state != "chase" else e.face
	if rm.is_empty():
		pass


func _can_see_player(e: Actor, max_d: float) -> bool:
	if player.state == "down":
		return false
	var d := e.pos.distance_to(player.pos)
	return d <= max_d and _los(e.pos, player.pos)


func _ai_rat(e: Actor, dt: float) -> void:
	var to_p := player.pos - e.pos
	var d := to_p.length()
	match e.state:
		"idle":
			e.timer -= dt
			if e.timer <= 0:
				e.timer = rng.randf_range(0.6, 1.8)
				e.target = e.home + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
			_steer(e, e.target, 30.0, dt, false)
			if _can_see_player(e, RunCfg.f("rat_aggro", 95)):
				e.aware = true
				e.set_state("chase")
				_ev("sfx", {"id": "squeak"})
		"chase":
			_steer(e, player.pos + e.data.get("off", Vector2.ZERO), RunCfg.f("rat_speed", 100), dt, true)
			if e.st > 0.5 and not e.data.has("off"):
				e.data["off"] = Vector2.from_angle(rng.randf() * TAU) * 10.0
			if d < 30.0 and e.st > 0.25 and _los(e.pos, player.pos):
				e.set_state("tele", RunCfg.f("rat_tele", 0.38) * rng.randf_range(0.9, 1.2))
				e.target = player.pos
				_ev("tele", {"pos": e.pos, "kind": "rat"})
			if d > 260 and e.st > 3.0:
				e.aware = false
				e.set_state("idle")
		"tele":
			e.vel = e.vel.move_toward(Vector2.ZERO, 900 * dt)
			if e.st < e.timer * RunCfg.f("tele_track", 0.5):
				e.target = player.pos
			e.lock_dir = (e.target - e.pos).normalized()
			e.face = e.lock_dir
			if e.st >= e.timer:
				e.set_state("dash", RunCfg.f("rat_dash_time", 0.18))
				_ev("sfx", {"id": "squeak"})
		"dash":
			e.vel = e.lock_dir * RunCfg.f("rat_dash_speed", 210)
			if not e.hit_done and d < e.radius + player.radius + 3:
				e.hit_done = true
				_hurt_player(RunCfg.i("rat_damage", 1), e.pos, "rat")
			if e.st >= e.timer:
				e.set_state("recover", RunCfg.f("rat_recover", 0.55))
		"recover", "stun":
			e.vel = e.vel.move_toward(Vector2.ZERO, 500 * dt)
			if e.st >= e.timer:
				e.set_state("chase")
		"flee":
			var away := (e.pos - e.target).normalized()
			e.vel = e.vel.move_toward(away * RunCfg.f("rat_speed", 100) * 1.1, 800 * dt)
			if e.st >= e.timer:
				e.set_state("chase" if e.aware else "idle")


func _ai_dog(e: Actor, dt: float) -> void:
	var to_p := player.pos - e.pos
	var d := to_p.length()
	match e.state:
		"idle":
			e.vel = e.vel.move_toward(Vector2.ZERO, 300 * dt)
			if _can_see_player(e, RunCfg.f("dog_aggro", 130)):
				e.aware = true
				e.set_state("circle", rng.randf_range(RunCfg.f("dog_circle_min"), RunCfg.f("dog_circle_max")) * 0.6)
				_ev("text", {"pos": e.pos + Vector2(0, -18), "text": "멍", "col": "white"})
				_ev("sfx", {"id": "bark"})
		"investigate":
			_steer(e, e.target, RunCfg.f("dog_speed", 92) * 0.8, dt, false)
			if _can_see_player(e, RunCfg.f("dog_aggro", 130)):
				e.aware = true
				e.set_state("circle", 1.0)
			elif e.pos.distance_to(e.target) < 12 or e.st > 4.0:
				e.home = e.pos
				e.set_state("idle")
		"circle":
			var want := RunCfg.f("dog_circle_r", 56)
			var radial := to_p.normalized()
			var tang := Vector2(-radial.y, radial.x) * float(e.data.get("dir", 1.0))
			var push := clampf((d - want) / 30.0, -1.0, 1.0)
			var desired := (tang + radial * push * 1.3).normalized() * RunCfg.f("dog_speed", 92)
			if not _los(e.pos, player.pos):
				_steer(e, player.pos, RunCfg.f("dog_speed", 92), dt, true)
			else:
				e.vel = e.vel.move_toward(desired, 500 * dt)
			e.face = radial
			if e.stuck_t > 0.4:
				e.data["dir"] = -float(e.data.get("dir", 1.0))
				e.stuck_t = 0.0
			if e.st >= e.timer and d < want + 40 and _los(e.pos, player.pos):
				e.set_state("tele", RunCfg.f("dog_tele", 0.6))
				_ev("sfx", {"id": "growl"})
				_ev("tele", {"pos": e.pos, "kind": "dog"})
			if d > 300:
				e.aware = false
				e.home = e.pos
				e.set_state("idle")
		"tele":
			e.vel = e.vel.move_toward(Vector2.ZERO, 700 * dt)
			if e.st < e.timer * RunCfg.f("tele_track", 0.5):
				e.lock_dir = to_p.normalized()
			e.face = e.lock_dir
			if e.st >= e.timer:
				e.set_state("lunge", RunCfg.f("dog_lunge_time", 0.3))
				_ev("sfx", {"id": "bark"})
		"lunge":
			e.vel = e.lock_dir * RunCfg.f("dog_lunge_speed", 255)
			if not e.hit_done and d < e.radius + player.radius + 4:
				e.hit_done = true
				_hurt_player(RunCfg.i("dog_damage", 1), e.pos, "dog")
			if e.st >= e.timer:
				e.set_state("recover", RunCfg.f("dog_recover", 0.75))
		"recover", "stun":
			e.vel = e.vel.move_toward(Vector2.ZERO, 500 * dt)
			if e.st >= e.timer:
				e.data["dir"] = 1.0 if rng.randf() < 0.5 else -1.0
				e.set_state("circle", rng.randf_range(RunCfg.f("dog_circle_min", 1.3), RunCfg.f("dog_circle_max", 2.4)))


func _alert_guard(e: Actor) -> void:
	if not e.aware:
		_ev("text", {"pos": e.pos + Vector2(0, -26), "text": "!", "col": "red", "big": true})
		_ev("sfx", {"id": "whistle"})
		_add_noise(RunCfg.f("noise_alert", 10.0))
	e.aware = true
	e.alert = 1.0
	e.last_seen = player.pos
	e.seen_t = 0.0
	e.set_state("chase")


func _guard_sees(e: Actor) -> bool:
	if player.state == "down":
		return false
	if e.data.has("light_off"):
		return e.pos.distance_to(player.pos) < 14.0
	var to_p := player.pos - e.pos
	var d := to_p.length()
	if d > cone_range():
		return d < 14.0
	if absf(angle_difference(e.face.angle(), to_p.angle())) > deg_to_rad(cone_deg()) / 2.0:
		return d < 14.0
	return _los(e.pos, player.pos)


## 물렁한 땅(매립지) 위면 느려진다. 들개는 익숙해서 안 느려진다.
func soft_mult(pos: Vector2) -> float:
	var c := to_cell(pos)
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return 1.0
	if tiles[c.y * w + c.x] == DungeonGen.SOFT:
		return float(RunCfg.skin().get("soft", {}).get("speed", 0.7))
	return 1.0


func cone_range() -> float:
	return RunCfg.f("guard_cone_range", 104) * (RunCfg.f("flood_range_mult", 1.4) if floodlights else 1.0)


func cone_deg() -> float:
	return RunCfg.f("guard_cone_deg", 60) * (RunCfg.f("flood_angle_mult", 1.3) if floodlights else 1.0)


func _ai_guard(e: Actor, dt: float) -> void:
	var to_p := player.pos - e.pos
	var d := to_p.length()
	var sees := _guard_sees(e)
	if not e.aware and e.state in ["patrol", "look", "investigate", "turn"]:
		if sees:
			var rate := 1.0 / RunCfg.f("guard_spot_time", 0.45) * (2.0 if d < 45 else 1.0)
			e.alert += rate * dt
			if e.alert >= 1.0:
				_alert_guard(e)
				return
		else:
			e.alert = maxf(0.0, e.alert - 0.6 * dt)
	match e.state:
		"patrol":
			var pts: Array = e.data.get("patrol", [])
			if pts.is_empty():
				e.vel = Vector2.ZERO
				return
			var wp: Vector2 = pts[int(e.data.get("wp", 0)) % pts.size()]
			_steer(e, wp, RunCfg.f("guard_patrol_speed", 36), dt, false)
			if e.vel.length() > 3:
				e.face = e.face.slerp(e.vel.normalized(), minf(1.0, dt * 4.0))
			if e.pos.distance_to(wp) < 8:
				e.data["wp"] = int(e.data.get("wp", 0)) + 1
				e.set_state("look", 1.4)
				e.data["look_base"] = e.face.angle()
		"look":
			e.vel = e.vel.move_toward(Vector2.ZERO, 300 * dt)
			var base: float = e.data.get("look_base", 0.0)
			e.face = Vector2.from_angle(base + sin(e.st * 2.6) * 0.9)
			if e.st >= e.timer:
				e.set_state("patrol")
		"turn":
			e.vel = e.vel.move_toward(Vector2.ZERO, 300 * dt)
			e.face = e.face.slerp((e.target - e.pos).normalized(), minf(1.0, dt * 6.0))
			if e.st > 1.2:
				e.set_state("look", 1.2)
				e.data["look_base"] = e.face.angle()
		"investigate":
			_steer(e, e.target, RunCfg.f("guard_chase_speed", 76) * 0.6, dt, false)
			if e.vel.length() > 3:
				e.face = e.face.slerp(e.vel.normalized(), minf(1.0, dt * 5.0))
			if e.pos.distance_to(e.target) < 12 or e.st > 5.0:
				e.set_state("look", 2.6)
				e.data["look_base"] = e.face.angle()
		"chase":
			if sees or (d < 120 and _los(e.pos, player.pos)):
				e.last_seen = player.pos
				e.seen_t = 0.0
			else:
				e.seen_t += dt
			var goal := e.last_seen
			_steer(e, goal, RunCfg.f("guard_chase_speed", 76), dt, true)
			e.face = e.face.slerp((goal - e.pos).normalized(), minf(1.0, dt * 8.0)) if e.pos.distance_to(goal) > 2 else e.face
			if d <= RunCfg.f("guard_reach", 26) + 2 and e.seen_t < 0.2:
				e.set_state("tele", RunCfg.f("guard_tele", 0.55))
				e.lock_dir = to_p.normalized()
				_ev("sfx", {"id": "grunt"})
				_ev("tele", {"pos": e.pos, "kind": "guard"})
			elif e.seen_t > RunCfg.f("guard_lose_time", 3.5):
				e.aware = false
				e.alert = 0.4
				e.set_state("look", 2.0)
				e.data["look_base"] = e.face.angle()
				_ev("text", {"pos": e.pos + Vector2(0, -24), "text": "?", "col": "white", "big": true})
		"tele":
			e.vel = e.vel.move_toward(Vector2.ZERO, 600 * dt)
			if e.st < e.timer * RunCfg.f("tele_track", 0.5):
				e.lock_dir = e.lock_dir.slerp(to_p.normalized(), minf(1.0, dt * 8.0))
			e.face = e.lock_dir
			if e.st >= e.timer:
				e.set_state("strike", 0.12)
				_ev("sfx", {"id": "swing"})
				var reach := RunCfg.f("guard_reach", 26) + 6
				if d - player.radius <= reach and absf(angle_difference(e.lock_dir.angle(), to_p.angle())) < deg_to_rad(60):
					_hurt_player(RunCfg.i("guard_damage", 2), e.pos, "guard")
				e.knock += e.lock_dir * 60
		"strike":
			if e.st >= e.timer:
				e.set_state("recover", RunCfg.f("guard_recover", 0.6))
		"recover", "stun":
			e.vel = e.vel.move_toward(Vector2.ZERO, 500 * dt)
			if e.st >= e.timer:
				e.set_state("chase")
				e.aware = true


func _ai_rival(e: Actor, dt: float) -> void:
	var to_p := player.pos - e.pos
	var d := to_p.length()
	var spd := RunCfg.f("rival_speed", 58)
	if e.data.get("hostile", false) and e.state in ["loot", "search", "leave"]:
		e.set_state("chase")
		_ev("text", {"pos": e.pos + Vector2(0, -24), "text": "뭐냐", "col": "red"})
	match e.state:
		"loot":
			var bag: Array = e.data["bag"]
			if bag.size() >= RunCfg.i("rival_bag", 4):
				e.set_state("leave")
				return
			var tgt: Dictionary = e.data.get("pile", {})
			if tgt.is_empty() or tgt["bundles"].is_empty():
				tgt = {}
				var bd := 99999.0
				for pl in piles:
					if pl["bundles"].is_empty() or is_same(pl, search_target):
						continue
					var dd: float = e.pos.distance_to(pl["pos"])
					if dd < bd and dd < 700:
						bd = dd
						tgt = pl
				e.data["pile"] = tgt
				if tgt.is_empty():
					e.set_state("leave")
					return
			_steer(e, tgt["pos"], spd, dt, false)
			if e.pos.distance_to(tgt["pos"]) < 16:
				e.set_state("search", RunCfg.f("rival_search", 1.6))
		"search":
			e.vel = e.vel.move_toward(Vector2.ZERO, 400 * dt)
			var tgt: Dictionary = e.data.get("pile", {})
			if tgt.is_empty() or tgt["bundles"].is_empty():
				e.set_state("loot")
				return
			if e.st >= e.timer:
				var b: Dictionary = tgt["bundles"].pop_front()
				e.data["bag"].append(b)
				if tgt["bundles"].is_empty():
					tgt["rummaged"] = true
				_ev("text", {"pos": e.pos + Vector2(0, -20), "text": "+%s" % RunCfg.good(b["good"]).get("short", ""), "col": "grey"})
				e.set_state("loot")
		"leave":
			var rm: Dictionary = rooms[e.room]
			var doors: Array = rm.get("doors", [])
			if doors.is_empty():
				e.dead = true
				return
			var dc: Vector2 = cell_center(doors[0]["cell"])
			_steer(e, dc, spd, dt, false)
			if e.pos.distance_to(dc) < 10:
				e.dead = true
				e.state = "gone"
		"chase":
			_steer(e, player.pos, spd * 1.25, dt, true)
			if d < 24:
				e.set_state("tele", RunCfg.f("rival_tele", 0.5))
				e.lock_dir = to_p.normalized()
				_ev("tele", {"pos": e.pos, "kind": "rival"})
		"tele":
			e.vel = e.vel.move_toward(Vector2.ZERO, 600 * dt)
			e.face = e.lock_dir
			if e.st >= e.timer:
				e.set_state("recover", 0.7)
				e.knock += e.lock_dir * 120
				if d < 30 and absf(angle_difference(e.lock_dir.angle(), to_p.angle())) < 1.0:
					_hurt_player(RunCfg.i("rival_damage", 1), e.pos, "rival")
		"recover", "stun":
			e.vel = e.vel.move_toward(Vector2.ZERO, 500 * dt)
			if e.st >= e.timer:
				e.set_state("chase" if e.data.get("hostile", false) else "loot")


# ------------------------------------------------------------------ 두목 "큰형"
func _boss_step(dt: float) -> void:
	var b := boss
	b.st += dt
	b.flash = maxf(0.0, b.flash - dt)
	var ph: int = b.data["phase"]
	var to_p := player.pos - b.pos
	var rrect: Rect2 = _room_rect(b.room)
	match b.state:
		"dormant":
			if cur_room == b.room and rrect.grow(-12).has_point(player.pos):
				b.set_state("intro", RunCfg.f("boss_intro", 2.2))
				reached_boss = true
				hp_at_boss = player.hp
				time_at_boss = time
				_ev("sfx", {"id": "alarm"})
				_ev("boss_intro", {})
		"intro":
			if b.st >= b.timer:
				b.set_state("track", 1.0)
		"track":
			var spd := RunCfg.f("boss_speed2" if ph == 2 else "boss_speed", 52)
			b.vel = b.vel.move_toward(to_p.normalized() * spd if to_p.length() > 4 else Vector2.ZERO, 200 * dt)
			b.pos += b.vel * dt
			b.pos = b.pos.clamp(rrect.position + Vector2(24, 48), rrect.end - Vector2(24, 24))
			if player.state == "down":
				return
			if b.st >= b.timer:
				_boss_pick(ph, to_p.length())
		"stomp_tele":
			# 예고 앞쪽 35% 동안은 머리가 줍는 이 쪽으로 조금 더 따라온다(그다음엔 고정)
			if b.st < b.timer * 0.35:
				b.pos += (player.pos - b.pos).limit_length(RunCfg.f("boss_speed2" if ph == 2 else "boss_speed", 52) * 1.2 * dt)
			if b.st >= b.timer:
				var area := Rect2(b.pos - Vector2(RunCfg.f("boss_stomp_w", 38), RunCfg.f("boss_stomp_h", 30)) / 2, Vector2(RunCfg.f("boss_stomp_w", 38), RunCfg.f("boss_stomp_h", 30)))
				if area.grow(player.radius).has_point(player.pos):
					_hurt_player(RunCfg.i("boss_stomp_damage", 2), b.pos, "boss")
				for e: Actor in enemies:
					if not e.dead and area.has_point(e.pos):
						_hurt_enemy(e, 3, (e.pos - b.pos).normalized(), "boss")
				_ev("stomp", {"pos": b.pos})
				_ev("sfx", {"id": "stomp"})
				_ev("shake", {"a": 7.0})
				_add_noise(3.0)
				if rng.randf() < 0.45:
					var it := _mk_item("throw", b.pos + Vector2(0, 18), {"tk": "can"})
					_pop_item(it)
				var chain: int = int(b.data.get("chain", 0))
				if chain > 0:
					# 연속 찍기: 끼지 않고 바로 다음 찍기(마지막에 오래 낀다)
					b.data["chain"] = chain - 1
					b.set_state("stomp_tele", RunCfg.f("boss_chain_tele", 0.5))
					_ev("sfx", {"id": "hydraulic"})
				else:
					b.set_state("stuck", RunCfg.f("boss_stuck", 1.7) * (RunCfg.f("boss_chain_stuck_mult", 1.6) if b.data.get("chained", false) else 1.0))
					b.data["chained"] = false
		"stuck":
			if b.st >= b.timer:
				b.set_state("rise", 0.45)
				_ev("sfx", {"id": "hydraulic"})
		"rise":
			if b.st >= b.timer:
				b.set_state("track", rng.randf_range(0.9, 1.6) * (0.75 if ph == 2 else 1.0))
		"spit":
			var done := true
			for m in marks:
				if m["t"] < m["dur"]:
					done = false
			if done and b.st > 0.3:
				b.set_state("track", rng.randf_range(0.8, 1.3))
		"howl_tele":
			if b.st >= b.timer:
				b.set_state("howl", RunCfg.f("boss_howl_time", 0.55))
				b.data["howl_hit"] = false
				_ev("sfx", {"id": "roar"})
				_ev("shake", {"a": 4.0})
				var alive := 0
				for e: Actor in enemies:
					if not e.dead and e.kind == "dog":
						alive += 1
				for k in mini(2, 4 - alive):
					var dg := _spawn_enemy("dog", b.home + Vector2(rng.randf_range(-80, 80), 10), b.room)
					dg.aware = true
					dg.set_state("circle", 1.2)
		"howl":
			# 울부짖음 고리: 0 → 최대 반지름으로 퍼진다. 고리가 지나는 순간 그 자리에 있으면 맞는다(굴러 넘기 가능)
			var rad := RunCfg.f("boss_howl_r", 92) * clampf(b.st / b.timer, 0.0, 1.0)
			b.data["howl_r"] = rad
			if not b.data.get("howl_hit", false) and absf(player.pos.distance_to(b.pos) - rad) < 7.0:
				if _hurt_player(RunCfg.i("boss_howl_damage", 2), b.pos, "boss"):
					b.data["howl_hit"] = true
			if b.st >= b.timer:
				b.set_state("stuck", RunCfg.f("boss_stuck", 1.2) * 0.8)
		"sweep_tele":
			if b.st >= b.timer:
				b.set_state("sweep")
				_ev("sfx", {"id": "hydraulic"})
		"sweep":
			var sx: float = b.data["sweep_x"]
			var dir: float = b.data["sweep_dir"]
			sx += dir * RunCfg.f("boss_sweep_speed", 150) * dt
			b.data["sweep_x"] = sx
			var half := RunCfg.f("boss_sweep_w", 12) / 2.0
			var gap: Vector2 = b.data["gap"]
			if absf(player.pos.x - sx) < half + player.radius and not (player.pos.y > gap.x and player.pos.y < gap.y):
				_hurt_player(RunCfg.i("boss_sweep_damage", 1), Vector2(sx - dir * 10, player.pos.y), "boss")
			if (dir > 0 and sx > rrect.end.x - 16) or (dir < 0 and sx < rrect.position.x + 16):
				b.set_state("track", 1.0)
	# 바닥 표시(침) 진행
	for m in marks:
		if m["t"] >= m["dur"]:
			continue
		m["t"] += dt
		if m["t"] >= m["dur"]:
			if player.pos.distance_to(m["pos"]) < m["r"] + player.radius:
				_hurt_player(RunCfg.i("boss_spit_damage", 1), m["pos"], "boss")
			cubes.append({"pos": m["pos"], "t": 0.0, "life": 4.0})
			_ev("sfx", {"id": "thud"})
			_ev("dust", {"pos": m["pos"], "n": 8, "dir": Vector2.ZERO})
			_ev("shake", {"a": 2.0})
	for k in range(marks.size() - 1, -1, -1):
		if marks[k]["t"] >= marks[k]["dur"]:
			marks.remove_at(k)
	for k in range(cubes.size() - 1, -1, -1):
		cubes[k]["t"] += dt
		if cubes[k]["t"] > cubes[k]["life"]:
			_ev("dust", {"pos": cubes[k]["pos"], "n": 5, "dir": Vector2.ZERO})
			cubes.remove_at(k)


## 다음 공격을 고른다. 1페이즈: 내려찍기·침. 2페이즈: 내려찍기·침·쓸기·연속 찍기 중 무작위(같은 것 두 번 연속 금지 — 순서를 외울 수 없게).
func _boss_pick(ph: int, dist: float) -> void:
	var b := boss
	var opts := {"stomp": 3.0, "spit": 2.0}
	var special := str(RunCfg.skin().get("boss", {}).get("special", "chain"))
	if ph == 2:
		opts = {"stomp": 2.0, "spit": 1.5, "sweep": 1.3, "chain": 1.6}
		if special == "howl":
			opts = {"stomp": 2.0, "spit": 1.5, "howl": 1.8}
	elif special == "howl":
		opts["howl"] = 1.0
	var last: String = b.data.get("last", "")
	if opts.has(last) and last != "stomp":
		opts.erase(last)
	if dist < 28:
		opts["stomp"] = float(opts.get("stomp", 1.0)) + 3.0
	var keys: Array = opts.keys()
	var ws: Array = []
	for k in keys:
		ws.append(opts[k])
	var pick: String = keys[_pick_w(ws)]
	b.data["last"] = pick
	match pick:
		"stomp", "chain":
			if pick == "chain":
				b.data["chain"] = RunCfg.i("boss_chain_n", 3) - 1
				b.data["chained"] = true
				_ev("banner", {"text": "고철 압축기: 쾅쾅쾅"})
			b.set_state("stomp_tele", RunCfg.f("boss_stomp_tele2" if ph == 2 else "boss_stomp_tele", 0.8))
			b.vel = Vector2.ZERO
			_ev("sfx", {"id": "hydraulic"})
			_ev("tele", {"pos": b.pos, "kind": "stomp"})
		"spit":
			_boss_spit_start(ph)
		"sweep":
			_boss_sweep_start()
		"howl":
			b.set_state("howl_tele", RunCfg.f("boss_howl_tele", 0.9))
			b.vel = Vector2.ZERO
			_ev("sfx", {"id": "growl"})
			_ev("tele", {"pos": b.pos, "kind": "howl"})


func _pick_w(ws: Array) -> int:
	var tot := 0.0
	for x in ws:
		tot += float(x)
	var r := rng.randf() * tot
	for k in ws.size():
		r -= float(ws[k])
		if r <= 0.0:
			return k
	return ws.size() - 1


func _boss_spit_start(ph: int) -> void:
	var b := boss
	var n := RunCfg.i("boss_spit_n2" if ph == 2 else "boss_spit_n", 3)
	var rrect := _room_rect(b.room).grow(-24)
	for k in n:
		var p := player.pos + player.vel * 0.3 if k == 0 else player.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(26, 70)
		p = p.clamp(rrect.position + Vector2(0, 40), rrect.end)
		marks.append({"pos": p, "r": RunCfg.f("boss_spit_r", 14), "t": 0.0, "dur": RunCfg.f("boss_spit_tele", 0.95) + k * 0.12, "from": rooms[b.room]["origin"] * TS + Vector2(13 * TS, 2 * TS)})
	b.set_state("spit")
	_ev("sfx", {"id": "spit"})
	_ev("tele", {"pos": b.pos, "kind": "spit"})


func _boss_sweep_start() -> void:
	var b := boss
	var rr := _room_rect(b.room)
	var from_left := player.pos.x > rr.get_center().x
	b.data["sweep_dir"] = 1.0 if from_left else -1.0
	b.data["sweep_x"] = rr.position.x + 20 if from_left else rr.end.x - 20
	var gy := rng.randf_range(rr.position.y + 60, rr.end.y - 40)
	b.data["gap"] = Vector2(gy - 16, gy + 16)
	b.set_state("sweep_tele", RunCfg.f("boss_sweep_tele", 1.0))
	_ev("sfx", {"id": "alarm"})
	_ev("tele", {"pos": b.pos, "kind": "sweep"})


func _room_rect(rid: int) -> Rect2:
	var r: Rect2i = rooms[rid]["rect"]
	return Rect2(Vector2(r.position) * TS + Vector2(TS, TS), Vector2(r.size - Vector2i(2, 2)) * TS)


# ------------------------------------------------------------------ 던진 것·떨어진 것
func _throws_step(dt: float) -> void:
	for k in range(throws.size() - 1, -1, -1):
		var t: Dictionary = throws[k]
		t["t"] += dt
		t["spin"] += dt * 14.0
		var u := clampf(t["t"] / t["dur"], 0.0, 1.0)
		var peak := RunCfg.f("throw_peak", 20) * (0.35 if t["bounce"] > 0 else 1.0)
		var np: Vector2 = (t["from"] as Vector2).lerp(t["to"], u)
		# 벽에 맞으면 거기서 떨어진다
		if _solid_at(np):
			t["to"] = t["pos"]
			u = 1.0
			np = t["pos"]
		t["pos"] = np
		t["z"] = 4.0 * peak * u * (1.0 - u)
		if t["bounce"] == 0 and t["z"] < 14.0 and u > 0.15:
			for e: Actor in enemies:
				if not e.dead and e.pos.distance_to(np) < e.radius + 4:
					_hurt_enemy(e, 1, (t["to"] - t["from"]).normalized(), "throw")
					e.set_state("stun", RunCfg.f("throw_stun", 1.2))
					_ev("text", {"pos": e.pos + Vector2(0, -20), "text": "깡", "col": "yellow"})
					t["to"] = np
					u = 1.0
					break
			if boss != null and not boss.dead and boss.state == "stuck" and boss.pos.distance_to(np) < 18:
				_hurt_boss(1)
				t["to"] = np
				u = 1.0
		if u >= 1.0:
			if t["bounce"] == 0:
				_noise_at(t["to"], RunCfg.f("throw_noise_radius", 130), "throw")
				_add_noise(RunCfg.f("noise_throw", 3.0))
				_ev("sfx", {"id": "clank"})
				_ev("dust", {"pos": t["to"], "n": 4, "dir": Vector2.ZERO})
				_ev("ring", {"pos": t["to"], "r": RunCfg.f("throw_noise_radius", 130)})
				var dir: Vector2 = (t["to"] - t["from"]).normalized()
				t["bounce"] = 1
				t["from"] = t["to"]
				var nt: Vector2 = t["to"] + dir * 14.0
				t["to"] = nt if not _solid_at(nt) else t["from"]
				t["t"] = 0.0
				t["dur"] = 0.18
			else:
				throws.remove_at(k)
				if t["kind"] == "can":
					var it := _mk_item("throw", t["pos"], {"tk": "can"})
					it["delay"] = 0.6
					items.append(it)
				else:
					_ev("dust", {"pos": t["pos"], "n": 6, "dir": Vector2.ZERO, "col": "brick"})


func _items_step(dt: float) -> void:
	var p := player
	item_under = {}
	for k in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[k]
		it["t"] += dt
		if it["z"] > 0.0 or it["vz"] > 0.0:
			it["vz"] -= 400.0 * dt
			it["z"] = maxf(0.0, it["z"] + it["vz"] * dt)
			if it["z"] <= 0.0:
				it["vz"] = 0.0
		var np: Vector2 = it["pos"] + it["vel"] * dt
		if not _solid_at(np):
			it["pos"] = np
		else:
			it["vel"] = -it["vel"] * 0.3
		it["vel"] = (it["vel"] as Vector2).move_toward(Vector2.ZERO, 120 * dt)
		it["delay"] = maxf(0.0, it["delay"] - dt)
		if p.state == "down" or it["delay"] > 0.0:
			continue
		var d: float = p.pos.distance_to(it["pos"])
		if d > 34.0:
			continue
		var can := false
		match str(it["kind"]):
			"good": can = _pack_fit(it["good"], it["bundles"]) >= 0
			"throw": can = held.size() < RunCfg.i("throw_carry_max", 3)
			"heal": can = p.hp < p.max_hp
			"big": can = big.is_empty()
		if not can:
			if d < 14.0 and it["kind"] == "good":
				item_under = it
			continue
		if d > 6.0:
			it["pos"] = (it["pos"] as Vector2).move_toward(p.pos, (60.0 + (34.0 - d) * 8.0) * dt)
			continue
		items.remove_at(k)
		match str(it["kind"]):
			"good":
				_pack_add(it)
				_ev("pickup", {"pos": p.pos, "text": "+%s" % RunCfg.good_name(it["good"]), "col": RunCfg.good(it["good"]).get("color", "#ffffff")})
			"throw":
				held.append(it["tk"])
				_ev("pickup", {"pos": p.pos, "text": "+%s" % ("깡통" if it["tk"] == "can" else "벽돌"), "col": "#c8c8c8"})
			"heal":
				p.hp = mini(p.max_hp, p.hp + RunCfg.i("heal_amount", 2))
				_ev("pickup", {"pos": p.pos, "text": "+♥", "col": "#ff8098"})
			"big":
				big = {"goods": it["goods"], "finds": RunCfg.file("run_goods").get("big", {}).get("finds", [])}
				_ev("pickup", {"pos": p.pos, "text": "큰 짐을 멨다", "col": "#f0c040"})
				_ev("banner", {"text": "큰 짐을 멨다. 이제 나가기만 하면 된다"})
		_ev("sfx", {"id": "pickup"})


func _pack_fit(good: String, bundles: int) -> int:
	var cap := int(RunCfg.good(good).get("cap", 3))
	for k in PACK_SLOTS:
		var s: Variant = pack[k]
		if s != null and s["good"] == good and int(s["bundles"]) + bundles <= cap:
			return k
	for k in PACK_SLOTS:
		if pack[k] == null:
			return k
	return -1


func _pack_add(it: Dictionary, slot: int = -1) -> void:
	var k := slot if slot >= 0 else _pack_fit(it["good"], it["bundles"])
	if k < 0:
		return
	if pack[k] == null:
		pack[k] = {"good": it["good"], "bundles": int(it["bundles"]), "units": int(it["units"])}
	else:
		pack[k]["bundles"] += int(it["bundles"])
		pack[k]["units"] += int(it["units"])


## 배낭 칸 비우기(바닥에 내려놓는다). 발밑에 못 담은 물건이 있고 배낭이 열려 있으면 그것과 바꾼다.
func slot_action(k: int) -> void:
	if k < 0 or k >= PACK_SLOTS or pack[k] == null or player.state == "down":
		return
	var s: Dictionary = pack[k]
	pack[k] = null
	var it := _mk_item("good", player.pos + Vector2(rng.randf_range(-6, 6), 8), {"good": s["good"], "units": s["units"], "bundles": s["bundles"]})
	it["delay"] = 1.2
	if not item_under.is_empty() and items.has(item_under):
		var u := item_under
		items.erase(u)
		_pack_add(u, k)
		_ev("pickup", {"pos": player.pos, "text": "바꿔 담음: %s" % RunCfg.good_name(u["good"]), "col": "#ffffff"})
		item_under = {}
	else:
		_ev("text", {"pos": player.pos + Vector2(0, -20), "text": "내려놓음: %s" % RunCfg.good_name(s["good"]), "col": "grey"})
	items.append(it)
	_ev("sfx", {"id": "drop"})


## 한 묶음만 덜어 발밑에 내려놓는다(칸에 하나뿐이면 칸째).
func slot_drop_one(k: int) -> void:
	if k < 0 or k >= PACK_SLOTS or pack[k] == null or player.state == "down":
		return
	var s: Dictionary = pack[k]
	if int(s["bundles"]) <= 1:
		slot_action(k)
		return
	var per := int(s["units"]) / int(s["bundles"])
	s["bundles"] = int(s["bundles"]) - 1
	s["units"] = int(s["units"]) - per
	var it := _mk_item("good", player.pos + Vector2(rng.randf_range(-6, 6), 8), {"good": s["good"], "units": per, "bundles": 1})
	it["delay"] = 1.2
	items.append(it)
	_ev("text", {"pos": player.pos + Vector2(0, -20), "text": "한 묶음 덜어냄: %s" % RunCfg.good_name(s["good"]), "col": "grey"})
	_ev("sfx", {"id": "drop"})


## 묶음 하나의 가치(별 1~5): 값 × 묶음 크기, 도시에 모자란 물건이면 1.5배.
func bundle_stars(good: String) -> int:
	var gd := RunCfg.good(good)
	var v := float(gd.get("value", 1)) * float(gd.get("bundle", 1))
	if good in wanted:
		v *= 1.5
	if v <= 3.0:
		return 1
	if v <= 4.5:
		return 2
	if v <= 6.5:
		return 3
	if v <= 9.0:
		return 4
	return 5


func pack_bundles() -> int:
	var n := 0
	for s in pack:
		if s != null:
			n += int(s["bundles"])
	return n


func pack_slots_used() -> int:
	var n := 0
	for s in pack:
		if s != null:
			n += 1
	return n


# ------------------------------------------------------------------ 위험물
func _hazards_step(dt: float) -> void:
	for j in junks:
		match str(j["state"]):
			"idle":
				if player.pos.distance_to(j["pos"]) < RunCfg.f("junk_trigger", 30) and player.state != "down":
					_junk_trigger(j, player.pos)
			"warn":
				j["t"] += dt
				if j["t"] >= RunCfg.f("junk_tele", 0.95):
					j["state"] = "fallen"
					var tp: Vector2 = j["target"]
					var rr := RunCfg.f("junk_radius", 19)
					if player.pos.distance_to(tp) < rr + player.radius:
						_hurt_player(RunCfg.i("junk_damage", 1), tp, "junk")
					for e: Actor in enemies:
						if not e.dead and e.pos.distance_to(tp) < rr + e.radius:
							_hurt_enemy(e, 2, (e.pos - tp).normalized(), "junk")
					_ev("crash", {"pos": tp})
					_ev("sfx", {"id": "crash"})
					_ev("shake", {"a": 5.0})
					_add_noise(RunCfg.f("noise_crash", 6.0))
					# 무너진 더미 자리 = 작은 더미(고물 한 묶음이 남아 있으면)
					var c: Vector2i = j["cell"]
					tiles[c.y * w + c.x] = DungeonGen.RUBBLE
					solid[c.y * w + c.x] = 0
					astar.set_point_solid(c, false)
					var sl: Dictionary = dun["stock_left"]
					var bundles: Array = []
					if int(sl.get("scrap", 0)) > 0:
						var u := mini(3, int(sl["scrap"]))
						sl["scrap"] = int(sl["scrap"]) - u
						bundles.append({"good": "scrap", "units": u})
					piles.append({"pos": tp, "cell": to_cell(tp), "room": j["room"], "bundles": bundles, "heal": false, "progress": 0.0, "popped": 0, "rummaged": false, "rubble": true})
	for wv in wires:
		var period := RunCfg.f("wire_period", 3.4)
		var ph := fmod(time + float(wv["phase"]), period)
		var warn_at := period - RunCfg.f("wire_active", 0.45) - RunCfg.f("wire_warn", 0.75)
		var act_at := period - RunCfg.f("wire_active", 0.45)
		var prev: String = wv["state"]
		wv["state"] = "active" if ph >= act_at else ("warn" if ph >= warn_at else "idle")
		if wv["state"] == "warn" and prev == "idle":
			if (wv["box"] as Rect2).grow(80).has_point(player.pos):
				_ev("sfx", {"id": "crackle"})
		if wv["state"] == "active":
			if prev != "active":
				wv["hit"] = {}
				if (wv["box"] as Rect2).grow(80).has_point(player.pos):
					_ev("sfx", {"id": "zap"})
			if (wv["box"] as Rect2).has_point(player.pos) and _on_wire(wv, player.pos) and not wv["hit"].has(0):
				if _hurt_player(RunCfg.i("wire_damage", 1), player.pos + Vector2(0, -4), "wire"):
					wv["hit"][0] = true
			for e: Actor in enemies:
				if not e.dead and not wv["hit"].has(e.id) and (wv["box"] as Rect2).has_point(e.pos) and _on_wire(wv, e.pos):
					wv["hit"][e.id] = true
					_hurt_enemy(e, 1, Vector2.UP, "wire")
					e.set_state("stun", 0.8)


func _on_wire(wv: Dictionary, p: Vector2) -> bool:
	var c := to_cell(p)
	return c in wv["cells"]


func _junk_trigger(j: Dictionary, at: Vector2) -> void:
	if j["state"] != "idle":
		return
	j["state"] = "warn"
	j["t"] = 0.0
	var dir := (at - j["pos"]) as Vector2
	j["target"] = j["pos"] + dir.limit_length(20.0) if dir.length() > 1 else j["pos"] + Vector2(0, 16)
	_ev("sfx", {"id": "creak"})
	_ev("tele", {"pos": j["pos"], "kind": "junk"})


# ------------------------------------------------------------------ 소란
func _add_noise(n: float) -> void:
	if finished:
		return
	if noise_level >= events_total():
		return   # 사건을 다 겪었으면 더 오르지 않는다(늦은 판이 끝없는 파도가 되지 않게)
	noise += n * (1.0 + RunCfg.f("noise_level_mult", 0.25) * mini(noise_level, RunCfg.i("noise_level_cap", 3)))


func events_total() -> int:
	return (RunCfg.v("noise_events", []) as Array).size()


func _noise_step(dt: float) -> void:
	# 가만히 숨죽이고 있으면(움직임·뒤지기·휘두르기 없음) 소란이 가라앉는다
	var p := player
	var busy := input.move.length() > 0.1 or not search_target.is_empty() or p.state in ["swing", "roll"] or not throws.is_empty()
	still_t = 0.0 if busy else still_t + dt
	hushing = still_t > RunCfg.f("noise_still_delay", 1.0) and noise > 0.0
	if hushing:
		noise = maxf(0.0, noise - RunCfg.f("noise_decay_still", 3.0) * dt)
	else:
		_add_noise(RunCfg.f("noise_passive", 0.3) * dt)
	if noise >= RunCfg.f("noise_max", 100) and noise_level < events_total():
		noise = 0.0
		noise_level += 1
		_noise_event(noise_level - 1)


## 소란이 찰 때마다 정해진 사건 하나(run_tuning.json noise_events 순서): 들개 떼 → 경비 순찰 → 투광등 → 쥐 떼.
func _noise_event(k: int) -> void:
	var evs: Array = RunCfg.v("noise_events", [])
	if k < 0 or k >= evs.size():
		return
	var ev: Dictionary = evs[k]
	var rm: Dictionary = rooms[cur_room]
	var doors: Array = rm.get("doors", [])
	var center := cell_center(rm["origin"] + Vector2i(13, 8))
	var at := center
	var far := -1.0
	for dd in doors:
		var dp := cell_center(dd["cell"])
		var dist := dp.distance_to(player.pos)
		if dist > far:
			far = dist
			at = dp
	at = at.move_toward(center, 20.0)
	var spawn: Dictionary = ev.get("spawn", {})
	for kind in spawn:
		for n in int(spawn[kind]):
			var e := _spawn_enemy(kind, at + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)), cur_room)
			e.aware = true
			match kind:
				"rat": e.set_state("chase")
				"dog": e.set_state("circle", 1.5)
				"guard":
					e.set_state("chase")
					e.last_seen = player.pos
					e.data["patrol"] = [at, center]
	if ev.get("flood", false):
		floodlights = true
	events_seen.append(str(ev.get("id", "")))
	last_event_t = time
	_ev("wave", {"pos": at, "level": noise_level, "id": ev.get("id", "")})
	_ev("banner", {"text": str(ev.get("banner", "소란"))})
	_ev("sfx", {"id": str(ev.get("sfx", "alarm"))})


## 소리가 난 곳: 쥐는 흩어지고, 들개·경비원은 보러 온다. 무너지는 더미도 흔들린다.
func _noise_at(p: Vector2, radius: float, _src: String) -> void:
	for e: Actor in enemies:
		if e.dead:
			continue
		var d := e.pos.distance_to(p)
		if d > radius:
			continue
		match e.kind:
			"rat":
				if e.state != "dash":
					e.set_state("flee", 1.6)
					e.target = p
			"dog":
				if e.state in ["idle", "investigate"]:
					e.set_state("investigate")
					e.target = p
			"guard":
				if e.state in ["patrol", "look", "investigate", "turn"]:
					e.set_state("investigate")
					e.target = p
					_ev("text", {"pos": e.pos + Vector2(0, -24), "text": "?", "col": "white", "big": true})
	for j in junks:
		if j["state"] == "idle" and (j["pos"] as Vector2).distance_to(p) < 36:
			_junk_trigger(j, p)


## 줍는 이가 내는 작은 소리(휘두르기·뒤지기) — 가까운 경비원이 돌아본다.
func _hear(p: Vector2, radius: float, dt: float = 1.0) -> void:
	for e: Actor in enemies:
		if e.dead or e.kind != "guard" or e.aware:
			continue
		if e.pos.distance_to(p) < minf(radius, RunCfg.f("guard_hear", 70)):
			if e.state in ["patrol", "look"]:
				e.set_state("turn")
				e.target = p
				e.alert = maxf(e.alert, 0.3)
	if dt >= 1.0:
		for e: Actor in enemies:
			if not e.dead and e.kind == "rat" and e.pos.distance_to(p) < 40 and e.state in ["chase", "idle"] and rng.randf() < 0.5:
				e.set_state("flee", 0.8)
				e.target = p


# ------------------------------------------------------------------ 방
func _room_step() -> void:
	var c := to_cell(player.pos)
	for r in rooms:
		var rc: Rect2i = r["rect"]
		if rc.grow(-1).has_point(c):
			if cur_room != r["id"]:
				cur_room = r["id"]
				if not visited.has(cur_room):
					visited[cur_room] = true
					_ev("room", {"name": r["name"], "depth": r["depth"]})
				max_depth_seen = maxi(max_depth_seen, int(r["depth"]))
			break


func _prompt_step() -> void:
	prompt = ""
	if player.state == "down":
		return
	if not exit_target.is_empty():
		prompt = "E 꾹: 빠져나가기" + (" (두목 잡음)" if boss_dead else "")
		return
	if not search_target.is_empty():
		prompt = "뒤지는 중…"
		return
	if not item_under.is_empty():
		prompt = "배낭이 찼다 — Tab 열고 칸을 눌러 바꿔 담기" if not pack_open else "바꿀 칸을 누른다(1~6)"
		return
	for pl in piles:
		if not (pl["bundles"].is_empty() and pl["rummaged"]) and player.pos.distance_to(pl["pos"]) < 24:
			prompt = "E 꾹: 따기(시끄럽다)" if pl.get("locker", false) and pl["popped"] == 0 else "E 꾹: 뒤지기"
			return


# ------------------------------------------------------------------ 끝
func _finish(oc: String) -> void:
	if finished:
		return
	finished = true
	outcome = oc
	var carried := {}
	var lost_l := {}
	var bundles_list: Array = []   # [slot, good, units]
	for k in PACK_SLOTS:
		var s: Variant = pack[k]
		if s == null:
			continue
		var per := int(s["units"]) / int(s["bundles"])
		var extra := int(s["units"]) - per * int(s["bundles"])
		for b in int(s["bundles"]):
			bundles_list.append({"good": s["good"], "units": per + (extra if b == 0 else 0)})
	if oc == "down":
		# 묶음의 절반(내림)을 무작위로 잃는다. 큰 짐은 떨군다.
		for k in range(bundles_list.size() - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var tmp: Variant = bundles_list[k]
			bundles_list[k] = bundles_list[j]
			bundles_list[j] = tmp
		var n_lose := bundles_list.size() / 2
		for k in n_lose:
			var b: Dictionary = bundles_list[k]
			lost_l[b["good"]] = int(lost_l.get(b["good"], 0)) + int(b["units"])
		bundles_list = bundles_list.slice(n_lose)
		if not big.is_empty():
			for g in big["goods"]:
				lost_l[g] = int(lost_l.get(g, 0)) + int(big["goods"][g])
	for b in bundles_list:
		carried[b["good"]] = int(carried.get(b["good"], 0)) + int(b["units"])
	var finds: Array = []
	if not big.is_empty() and oc != "down":
		for g in big["goods"]:
			carried[g] = int(carried.get(g, 0)) + int(big["goods"][g])
		finds.append_array(big["finds"])
	if oc == "boss" and big.is_empty():
		pass
	var left := {}
	for it in items:
		if it["kind"] == "good":
			left[it["good"]] = int(left.get(it["good"], 0)) + int(it["units"])
		elif it["kind"] == "big":
			for g in it["goods"]:
				left[g] = int(left.get(g, 0)) + int(it["goods"][g])
	lost = lost_l
	result = {
		"dest": dest, "loot": carried, "outcome": oc, "finds": finds,
		"carried": carried, "left": left, "lost": lost_l, "found": found.duplicate(),
		"time": time, "kills": kills.duplicate(), "rooms_visited": visited.size(), "rooms_total": rooms.size(),
		"reached_boss": reached_boss, "boss_killed": boss_dead, "max_depth": max_depth_seen,
		"noise_level": noise_level, "events": events_seen.duplicate(), "hp": player.hp, "seed": seed_value, "big": not big.is_empty() and oc != "down",
		"last_hurt_by": last_hurt_by, "hurt_log": hurt_log.duplicate(), "hp_at_boss": hp_at_boss, "time_at_boss": time_at_boss, "dodges": dodges, "hits_taken": hits_taken,
	}
	_ev("finished", {"outcome": oc})


## 포기(멈춤 메뉴): 들어온 구멍까지 걸어 나간 셈 치지 않는다 — 쓰러진 것과 같다.
func give_up() -> void:
	if not finished:
		player.hp = 0
		_finish("down")


# ------------------------------------------------------------------ 충돌·길찾기
func _solid_cell(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return true
	return solid[c.y * w + c.x] == 1


func _solid_at(p: Vector2) -> bool:
	return _solid_cell(Vector2i(int(floor(p.x / TS)), int(floor(p.y / TS))))


func _box_hits(cx: float, cy: float, r: float) -> bool:
	var x0 := int(floor((cx - r) / TS))
	var x1 := int(floor((cx + r) / TS))
	var y0 := int(floor((cy - r) / TS))
	var y1 := int(floor((cy + r) / TS))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _solid_cell(Vector2i(x, y)):
				return true
	return false


func _move(a: Actor, d: Vector2) -> void:
	var before := a.pos
	var n := int(ceil(d.length() / 5.0))
	if n < 1:
		n = 1
	var sd := d / n
	var r := a.radius
	for k in n:
		if sd.x != 0.0:
			var nx := a.pos.x + sd.x
			if not _box_hits(nx, a.pos.y, r):
				a.pos.x = nx
			else:
				# 모서리 보정: 위아래로 4px 안에 빈 길이 있으면 그쪽으로 미끄러진다
				var slid := false
				for off in [1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0, 5.0, -5.0]:
					if not _box_hits(nx, a.pos.y + off, r) and not _box_hits(a.pos.x, a.pos.y + signf(off), r):
						a.pos.y += signf(off) * minf(absf(sd.x), 1.5)
						slid = true
						break
				if not slid:
					_bonk(a, absf(a.knock.x))
					a.vel.x = 0.0
					a.knock.x = 0.0
		if sd.y != 0.0:
			var ny := a.pos.y + sd.y
			if not _box_hits(a.pos.x, ny, r):
				a.pos.y = ny
			else:
				var slid2 := false
				for off in [1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0, 5.0, -5.0]:
					if not _box_hits(a.pos.x + off, ny, r) and not _box_hits(a.pos.x + signf(off), a.pos.y, r):
						a.pos.x += signf(off) * minf(absf(sd.y), 1.5)
						slid2 = true
						break
				if not slid2:
					_bonk(a, absf(a.knock.y))
					a.vel.y = 0.0
					a.knock.y = 0.0
	# 더미·큐브는 둥근 장애물로 밀어낸다
	for pl in piles:
		var dv: Vector2 = a.pos - pl["pos"]
		var minr := r + 6.0
		if dv.length_squared() < minr * minr and dv.length_squared() > 0.001:
			var np: Vector2 = pl["pos"] + dv.normalized() * minr
			if not _box_hits(np.x, np.y, r):
				a.pos = np
	for cb in cubes:
		var dv: Vector2 = a.pos - cb["pos"]
		var minr := r + 8.0
		if dv.length_squared() < minr * minr and dv.length_squared() > 0.001:
			var np: Vector2 = cb["pos"] + dv.normalized() * minr
			if not _box_hits(np.x, np.y, r):
				a.pos = np
	var moved := a.pos.distance_to(before)
	if d.length() > 0.3 and moved < d.length() * 0.3:
		a.stuck_t += maxf(0.016, d.length() / maxf(1.0, a.vel.length()))
	else:
		a.stuck_t = maxf(0.0, a.stuck_t - 0.05)


## 밀려 날아가다 벽에 쾅: 별이 돌고 잠깐 더 어지럽다.
func _bonk(a: Actor, speed: float) -> void:
	if a == player or speed < RunCfg.f("bonk_speed", 70.0) or a.bonk_cd > 0.0 or a.dead:
		return
	a.bonk_cd = 0.5
	_ev("bonk", {"pos": a.pos})
	_ev("sfx", {"id": "bonk"})
	if a.kind in ["rat", "dog", "rival"]:
		a.set_state("stun", RunCfg.f("bonk_stun", 0.6))
	elif a.kind == "guard" and a.state != "tele":
		a.set_state("stun", RunCfg.f("bonk_stun", 0.6) * 0.6)


func _separate() -> void:
	var all: Array = enemies
	for i in all.size():
		var a: Actor = all[i]
		if a.dead:
			continue
		for j in range(i + 1, all.size()):
			var b: Actor = all[j]
			if b.dead:
				continue
			var dv := b.pos - a.pos
			var minr := a.radius + b.radius
			var dl := dv.length_squared()
			if dl < minr * minr and dl > 0.0001:
				var dl2 := sqrt(dl)
				var push := dv / dl2 * (minr - dl2) * 0.5
				if not _box_hits(a.pos.x - push.x, a.pos.y - push.y, a.radius):
					a.pos -= push
				if not _box_hits(b.pos.x + push.x, b.pos.y + push.y, b.radius):
					b.pos += push
		# 줍는 이와 겹치지 않게(줍는 이는 안 밀린다)
		var dp := a.pos - player.pos
		var mr := a.radius + player.radius - 1.0
		if dp.length_squared() < mr * mr and dp.length_squared() > 0.0001 and a.state not in ["dash", "lunge"]:
			var np := player.pos + dp.normalized() * mr
			if not _box_hits(np.x, np.y, a.radius):
				a.pos = np


func _los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := int(d.length() / 6.0) + 1
	for k in range(1, n):
		if _solid_at(a + d * (float(k) / n)):
			return false
	return true


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var fc := to_cell(from)
	var tc := to_cell(to)
	if _solid_cell(tc):
		tc = _free_cell_near(tc)
	if _solid_cell(fc):
		fc = _free_cell_near(fc)
	if not astar.region.has_point(fc) or not astar.region.has_point(tc):
		return PackedVector2Array()
	return astar.get_point_path(fc, tc)


func _steer(a: Actor, goal: Vector2, speed: float, dt: float, aggressive: bool) -> void:
	var dir := Vector2.ZERO
	var dist := a.pos.distance_to(goal)
	if dist < 3.0:
		a.vel = a.vel.move_toward(Vector2.ZERO, 600 * dt)
		return
	var direct := a.stuck_t < 0.3 and _los(a.pos, goal) and _los(a.pos + Vector2(a.radius, a.radius), goal) and _los(a.pos - Vector2(a.radius, a.radius), goal)
	if direct:
		dir = (goal - a.pos).normalized()
		a.path = PackedVector2Array()
	else:
		a.path_t -= dt
		if a.path.is_empty() or a.path_t <= 0.0 or a.path_i >= a.path.size():
			a.path = find_path(a.pos, goal)
			a.path_i = 1 if a.path.size() > 1 else 0
			a.path_t = 0.6 if aggressive else 1.2
			a.stuck_t = 0.0
		if a.path.is_empty():
			dir = (goal - a.pos).normalized()
		else:
			var wp: Vector2 = a.path[mini(a.path_i, a.path.size() - 1)]
			if a.pos.distance_to(wp) < 5.0 and a.path_i < a.path.size() - 1:
				a.path_i += 1
				wp = a.path[a.path_i]
			dir = (wp - a.pos).normalized()
	a.vel = a.vel.move_toward(dir * speed, 700 * dt)
