extends RefCounted
## 자동 플레이어 — 사람과 같은 RunInput(이동·조준·클릭·Space·E·Tab·칸)만 채운다. 규칙을 몰래 바꾸지 않는다.
## 성격 3가지(data/run/run_bots.json): careless(덜렁이) / average(보통) / careful(꼼꼼 욕심).
## 반응 지연(react) 뒤에 예고를 "보고", dodge 확률로 피할지 정한다. 피하기는 구르기(무적) 또는 걸어서 비키기.

const RunCfg = preload("res://expedition/RunCfg.gd")
const RunWorld = preload("res://expedition/RunWorld.gd")
const RunInput = preload("res://expedition/RunInput.gd")
const Actor = preload("res://expedition/RunActor.gd")

var profile_id := "average"
var P: Dictionary = {}
var rng := RandomNumberGenerator.new()
var seen: Dictionary = {}        # 위협 키 -> {t0, dodge:bool}
var path := PackedVector2Array()
var path_i := 0
var path_t := 0.0
var path_goal := Vector2.INF
var atk_cd := 0.0
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var jiggle_t := 0.0
var jiggle := Vector2.ZERO
var explore_rooms: Dictionary = {}
var wait_t := 0.0
var throw_cd := 0.0
var goal_desc := ""
var pack_op := -1
var t := 0.0
var leaving := false
var leave_reason := ""
var wd_pos := Vector2.ZERO
var wd_t := 0.0
var ignore: Dictionary = {}


func setup(profile: String, seed_value: int) -> void:
	profile_id = profile
	P = RunCfg.bot(profile)
	rng.seed = seed_value * 31 + 7


func fill(inp: RunInput, w: RunWorld, dt: float) -> void:
	t += dt
	atk_cd -= dt
	throw_cd -= dt
	var p: Actor = w.player
	inp.move = Vector2.ZERO
	inp.interact = false
	if w.finished or p.state == "down":
		return
	# 배낭 정리 중(Tab 열고 칸 누르고 닫기)
	if pack_op >= 0:
		if not w.pack_open:
			inp.pack_toggle = true
		else:
			inp.slot_action = pack_op
			pack_op = -2
		return
	if pack_op == -2:
		if w.pack_open:
			inp.pack_toggle = true
		pack_op = -1
		return
	if w.pack_open:
		inp.pack_toggle = true
		return
	# 끼임 감지
	if p.pos.distance_to(last_pos) < 0.4 and not w.search_target.is_empty() == false and inp.move.length() == 0.0:
		pass
	var moved := p.pos.distance_to(last_pos)
	last_pos = p.pos
	# 지켜보기: 8초 동안 제자리면(뒤지는 중 제외) 지금 노리던 더미를 포기한다
	if p.pos.distance_to(wd_pos) > 10.0 or not w.search_target.is_empty():
		wd_pos = p.pos
		wd_t = 0.0
	else:
		wd_t += dt
		if wd_t > 8.0:
			var bp := _best_pile(w)
			if not bp.is_empty():
				ignore[bp["pos"]] = true
			path = PackedVector2Array()
			wd_t = 0.0
	# 1) 위협 피하기
	var dodge := _threat(w, dt)
	if dodge != Vector2.INF:
		inp.move = dodge.normalized() if dodge.length() > 0.01 else Vector2.ZERO
		inp.aim = p.pos + (inp.move if inp.move != Vector2.ZERO else p.face) * 30
		return
	# 2) 싸움
	if _fight(inp, w):
		return
	# 3) 할 일
	var goal := _goal(inp, w)
	if goal == Vector2.INF:
		return
	_walk(inp, w, goal, dt, moved)


# ------------------------------------------------------------------ 위협
## 피할 방향을 돌려준다(INF = 위협 없음). 구르기는 inp에 직접 넣지 못하므로 world.input에 넣는다.
func _threat(w: RunWorld, dt: float) -> Vector2:
	var p: Actor = w.player
	var best := Vector2.INF
	var best_rem := 99.0
	var roll := false
	var cands: Array = []   # [key, remaining, away_dir, roll_ok]
	for e: Actor in w.enemies:
		if e.dead or e.state != "tele":
			continue
		var rem := e.timer - e.st
		var d := p.pos.distance_to(e.pos)
		var tk := "%d_%d" % [e.id, int((w.time - e.st) * 20.0)]
		match e.kind:
			"dog":
				var L := RunCfg.f("dog_lunge_speed", 255) * RunCfg.f("dog_lunge_time", 0.3)
				var seg_d := _seg_dist(p.pos, e.pos, e.pos + e.lock_dir * (L + 6))
				if seg_d < 12:
					var side := Vector2(-e.lock_dir.y, e.lock_dir.x)
					if side.dot(p.pos - e.pos) < 0:
						side = -side
					cands.append(["d" + tk, rem, side, true])
			"rat":
				if d < 36:
					cands.append(["r" + tk, rem, (p.pos - e.pos).normalized(), true])
			"guard":
				if d < RunCfg.f("guard_reach", 26) + 14:
					cands.append(["g" + tk, rem, (p.pos - e.pos).normalized(), true])
			"rival":
				if d < 34:
					cands.append(["v" + tk, rem, (p.pos - e.pos).normalized(), true])
	for j in w.junks:
		if j["state"] == "warn":
			var tp: Vector2 = j["target"]
			if p.pos.distance_to(tp) < RunCfg.f("junk_radius", 19) + 8:
				cands.append(["j%s" % str(j["cell"]), RunCfg.f("junk_tele", 0.95) - j["t"], (p.pos - tp).normalized() if p.pos.distance_to(tp) > 1 else Vector2.RIGHT, false])
	for wv in w.wires:
		if wv["state"] in ["warn", "active"] and (wv["box"] as Rect2).grow(10).has_point(p.pos):
			var on := false
			for c in wv["cells"]:
				if Rect2(Vector2(c) * 16.0 - Vector2(6, 6), Vector2(28, 28)).has_point(p.pos):
					on = true
					break
			if on:
				var cen := (wv["box"] as Rect2).get_center()
				cands.append(["w%s_%d" % [str(wv["cells"][0]), int((w.time + float(wv["phase"])) / RunCfg.f("wire_period", 3.4))], 0.5, (p.pos - cen).normalized(), false])
	var b: Actor = w.boss
	if b != null and not b.dead:
		if b.state == "stomp_tele":
			var area := Rect2(b.pos - Vector2(RunCfg.f("boss_stomp_w", 38), RunCfg.f("boss_stomp_h", 30)) / 2, Vector2(RunCfg.f("boss_stomp_w", 38), RunCfg.f("boss_stomp_h", 30))).grow(10)
			if area.has_point(p.pos):
				cands.append(["bs%d" % int((w.time - b.st) * 20.0), b.timer - b.st, (p.pos - b.pos).normalized() if p.pos.distance_to(b.pos) > 1 else Vector2.DOWN, true])
		for m in w.marks:
			if p.pos.distance_to(m["pos"]) < m["r"] + 10:
				cands.append(["m%s" % str(m["pos"]), m["dur"] - m["t"], (p.pos - m["pos"]).normalized() if p.pos.distance_to(m["pos"]) > 1 else Vector2.LEFT, true])
		if b.state in ["howl_tele", "howl"]:
			var R := RunCfg.f("boss_howl_r", 92)
			var dd := p.pos.distance_to(b.pos)
			if dd < R + 8:
				var speed_r := R / RunCfg.f("boss_howl_time", 0.55)
				var r_now: float = float(b.data.get("howl_r", 0.0)) if b.state == "howl" else 0.0
				var rem3 := (dd - r_now) / speed_r + ((b.timer - b.st) if b.state == "howl_tele" else 0.0)
				if dd > r_now:
					cands.append(["hw%d" % int((w.time - b.st) * 20.0), rem3, (p.pos - b.pos).normalized(), true])
		if b.state in ["sweep_tele", "sweep"]:
			var sx: float = b.data["sweep_x"]
			var dir: float = b.data["sweep_dir"]
			var gap: Vector2 = b.data["gap"]
			var ahead := (p.pos.x - sx) * dir
			if ahead > -4 and ahead < 120:
				var in_gap := p.pos.y > gap.x + 4 and p.pos.y < gap.y - 4
				if not in_gap:
					var to_gap := Vector2(0, signf((gap.x + gap.y) / 2 - p.pos.y))
					var rem2 := (ahead - 8) / RunCfg.f("boss_sweep_speed", 150) + (b.timer - b.st if b.state == "sweep_tele" else 0.0)
					cands.append(["sw%d_%d" % [int(gap.x), int(w.time - b.st)], rem2, to_gap, true])
	if cands.is_empty():
		return Vector2.INF
	var act := Vector2.INF
	for c in cands:
		var key: String = c[0]
		if not seen.has(key):
			seen[key] = {"t0": t, "dodge": rng.randf() < float(P.get("dodge", 0.6)), "rolled": false}
		var info: Dictionary = seen[key]
		if t - float(info["t0"]) < float(P.get("react", 0.25)):
			continue
		if not info["dodge"]:
			continue
		var rem: float = c[1]
		if rem < best_rem:
			best_rem = rem
			act = c[2]
			roll = c[3] and rem < 0.24 and not info["rolled"]
			if roll:
				info["rolled"] = true
	if act == Vector2.INF:
		return Vector2.INF
	if roll and w.roll_cd <= 0.0:
		w.input.roll = true
	return act


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var u := clampf((p - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
	return p.distance_to(a + ab * u)


# ------------------------------------------------------------------ 싸움
func _fight(inp: RunInput, w: RunWorld) -> bool:
	var p: Actor = w.player
	var punish: bool = P.get("punish", true)
	var target: Actor = null
	var bd := 9999.0
	for e: Actor in w.enemies:
		if e.dead or e.state == "gone":
			continue
		if e.kind == "rival" and not e.data.get("hostile", false):
			continue
		var d := p.pos.distance_to(e.pos)
		var relevant := e.aware or d < 34
		if e.kind == "guard" and not e.aware:
			relevant = d < 34 and not bool(P.get("sneak", false))
		if not relevant or d > 90:
			continue
		if not w._los(p.pos, e.pos):
			continue
		if d < bd:
			bd = d
			target = e
	# 두목: 끼였을 때만 친다
	var b: Actor = w.boss
	var low: bool = p.hp <= int(P.get("leave_hp", 2))
	if b != null and not b.dead and b.state not in ["dormant"] and w.cur_room == b.room and not low:
		if b.state == "stuck" and (target == null or bd > 26):
			_approach_attack(inp, w, b.pos, 20.0, 18.0)
			return true
		if target == null:
			# 거리 두고 맴돌기(머리에서 50~70)
			var away := p.pos - b.pos
			var d2 := away.length()
			var rr: Rect2 = w._room_rect(b.room).grow(-20)
			var mv := Vector2.ZERO
			if d2 < 52:
				mv = away.normalized()
			elif d2 > 80:
				mv = -away.normalized() * 0.6
			else:
				mv = Vector2(-away.y, away.x).normalized() * 0.5
			if not rr.has_point(p.pos + mv * 20):
				mv = (rr.get_center() - p.pos).normalized()
			inp.move = mv
			inp.aim = b.pos
			return true
	if target == null:
		return false
	var d := bd
	var reach := RunCfg.f("swing_range", 27) + target.radius - 3
	# 던져서 기절(들개·경비원)
	if not w.held.is_empty() and throw_cd <= 0.0 and target.kind in ["dog", "guard"] and d > 34 and d < 120 and target.state not in ["stun"] and rng.randf() < float(P.get("throw", 0.3)) * 0.05:
		inp.aim = target.pos
		inp.throw = true
		throw_cd = 1.5
		return true
	var vulnerable := target.state in ["recover", "stun", "idle", "patrol", "look", "circle", "chase", "investigate", "search", "loot", "flee", "turn", "strike"]
	if target.kind == "dog" and punish and target.state == "circle" and d > reach + 4:
		# 맴도는 개는 거리만 유지하며 기다린다(덮침 뒤 헥헥거릴 때 친다)
		inp.aim = target.pos
		inp.move = Vector2.ZERO if d > 40 else (p.pos - target.pos).normalized() * 0.5
		return true
	if target.state == "tele" and punish:
		inp.aim = target.pos
		return true   # 예고 중엔 위협 쪽 로직에 맡기고 대기
	if vulnerable or not punish:
		_approach_attack(inp, w, target.pos, reach, 0.0)
		return true
	inp.aim = target.pos
	return true


func _approach_attack(inp: RunInput, w: RunWorld, tp: Vector2, reach: float, extra: float) -> void:
	var p: Actor = w.player
	var d := p.pos.distance_to(tp)
	var err := float(P.get("aim_err", 0.2))
	inp.aim = p.pos + (tp - p.pos).rotated(rng.randf_range(-err, err))
	if d > reach + extra * 0.0:
		var dir := (tp - p.pos).normalized()
		if w._los(p.pos, tp):
			inp.move = dir
		else:
			_walk(inp, w, tp, 0.016, 1.0)
	if d <= reach + 2 and atk_cd <= 0.0:
		inp.attack = true
		atk_cd = 0.28 + rng.randf() * 0.1


# ------------------------------------------------------------------ 목표
func _goal(inp: RunInput, w: RunWorld) -> Vector2:
	var p: Actor = w.player
	var full_leave := int(P.get("full_leave", 6))
	var should_leave := false
	goal_desc = ""
	if p.hp <= int(P.get("leave_hp", 2)) and not (w.boss_dead and w.big.is_empty()):
		should_leave = true
		leave_reason = "hp"
	elif w.noise_level >= int(P.get("noise_leave", 99)) and w.pack_bundles() > 0:
		should_leave = true
		leave_reason = "noise"
	elif w.time > 540.0:
		should_leave = true
		leave_reason = "time"
	elif w.boss_dead and not w.big.is_empty():
		should_leave = true
		leave_reason = "boss"
	var full := w.pack_slots_used() >= full_leave and _pack_all_capped(w)
	if full and not should_leave:
		# 배낭이 찼다: 두목에 덤빌 체력이면 두목 방으로 곧장, 아니면 나간다
		var b0: Actor = w.boss
		if b0 == null or b0.dead or p.hp < int(P.get("full_boss_hp", P.get("boss_hp", 3))):
			should_leave = true
			leave_reason = "full"
	leaving = should_leave
	# 발밑의 더 좋은 물건과 바꿔 담기(꼼꼼 욕심만 신경 쓴다, 보통도 가끔)
	if not w.item_under.is_empty() and P.get("explore", 0.5) > 0.4:
		var lo := _lowest_slot(w)
		if lo >= 0 and float(RunCfg.good(w.item_under["good"]).get("value", 1)) > float(RunCfg.good(w.pack[lo]["good"]).get("value", 1)) * 1.4:
			pack_op = lo
			return Vector2.INF
	# 큰 짐 줍기
	if w.boss_dead and w.big.is_empty():
		for it in w.items:
			if it["kind"] == "big":
				goal_desc = "큰 짐"
				return it["pos"]
	# 가까운 떨어진 물건(들어갈 때)
	var near_item := Vector2.INF
	var nd := 140.0
	for it in w.items:
		if it["delay"] > 0.0:
			continue
		var ok := false
		match str(it["kind"]):
			"good": ok = w._pack_fit(it["good"], it["bundles"]) >= 0
			"throw": ok = w.held.size() < RunCfg.i("throw_carry_max", 3)
			"heal": ok = p.hp < p.max_hp
		if not ok:
			continue
		var d: float = p.pos.distance_to(it["pos"])
		if d < nd and w.to_cell(it["pos"]) != Vector2i(-1, -1):
			nd = d
			near_item = it["pos"]
	if should_leave:
		if near_item != Vector2.INF and nd < 40:
			return near_item
		return _nearest_exit(inp, w)
	if near_item != Vector2.INF:
		goal_desc = "물건"
		return near_item
	# 지금 방의 더미(배낭이 찼으면 건너뛴다)
	var pile := _best_pile(w) if not full else {}
	if not pile.is_empty():
		var pp: Vector2 = pile["pos"]
		if p.pos.distance_to(pp) < 17.0:
			# 주변이 조용하면 뒤진다
			var calm := true
			for e: Actor in w.enemies:
				if not e.dead and e.aware and e.pos.distance_to(p.pos) < (60 if profile_id != "careless" else 20) and (e.kind != "rival" or e.data.get("hostile", false)) and w._los(p.pos, e.pos):
					calm = false
			if calm or profile_id == "careless" or wd_t > 3.0:
				inp.interact = true
				inp.aim = pp
				goal_desc = "뒤지기"
				return Vector2.INF
		goal_desc = "더미"
		return pp
	# 다음 방
	var nxt := _next_room(w, full)
	if nxt < 0:
		leave_reason = "done"
		return _nearest_exit(inp, w)
	var r: Dictionary = w.rooms[nxt]
	goal_desc = "방 %d" % nxt
	return w.cell_center(r["origin"] + Vector2i(13, 8))


func _pack_all_capped(w: RunWorld) -> bool:
	# 칸이 다 찼고, 같은 물건을 더 겹칠 자리도 거의 없으면 true
	var room := 0
	for s in w.pack:
		if s == null:
			return false
		room += int(RunCfg.good(s["good"]).get("cap", 3)) - int(s["bundles"])
	return room <= 2


func _lowest_slot(w: RunWorld) -> int:
	var lo := -1
	var lv := 99999.0
	for k in w.pack.size():
		var s: Variant = w.pack[k]
		if s == null:
			return -1
		var v := float(RunCfg.good(s["good"]).get("value", 1)) * int(s["units"])
		if v < lv:
			lv = v
			lo = k
	return lo


func _best_pile(w: RunWorld) -> Dictionary:
	var p: Actor = w.player
	var best: Dictionary = {}
	var bd := 99999.0
	var rect: Rect2i = w.rooms[w.cur_room]["rect"]
	for pl in w.piles:
		if pl["bundles"].is_empty() and pl["rummaged"]:
			continue
		if ignore.has(pl["pos"]):
			continue
		if pl["room"] != w.cur_room and not rect.has_point(w.to_cell(pl["pos"])):
			continue
		# 경비원 시야 안의 더미는 꼼꼼이만 피한다
		if P.get("sneak", false) and _in_guard_cone(w, pl["pos"]):
			continue
		var d: float = p.pos.distance_to(pl["pos"])
		if d < bd:
			bd = d
			best = pl
	return best


func _in_guard_cone(w: RunWorld, pos: Vector2) -> bool:
	for e: Actor in w.enemies:
		if e.dead or e.kind != "guard" or e.aware:
			continue
		var to := pos - e.pos
		if to.length() < RunCfg.f("guard_cone_range", 104) + 10 and absf(angle_difference(e.face.angle(), to.angle())) < deg_to_rad(RunCfg.f("guard_cone_deg", 60)) / 2.0 + 0.2:
			return true
	return false


func _next_room(w: RunWorld, boss_only: bool = false) -> int:
	var p: Actor = w.player
	var cands: Array = []
	for rid in w.visited:
		for l in w.rooms[rid]["links"]:
			if w.visited.has(l):
				continue
			var r: Dictionary = w.rooms[l]
			if r["kind"] == "boss":
				if p.hp < int(P.get("boss_hp", 3)):
					continue
			elif boss_only and not r["main"]:
				continue
			elif not r["main"]:
				if not explore_rooms.has(l):
					explore_rooms[l] = rng.randf() < float(P.get("explore", 0.5))
				if not explore_rooms[l]:
					continue
			cands.append(l)
	if cands.is_empty():
		# 두목 방에 이미 갔고 두목이 살아 있으면, 체력이 되면 다시 싸우러
		if w.boss != null and not w.boss.dead and w.visited.has(w.boss.room) and p.hp >= int(P.get("boss_hp", 3)):
			return w.boss.room
		return -1
	# 곁방 먼저(가까운 순), 그다음 두목
	cands.sort_custom(func(a: int, b: int) -> bool:
		var ka: int = 1 if w.rooms[a]["kind"] == "boss" else 0
		var kb: int = 1 if w.rooms[b]["kind"] == "boss" else 0
		if ka != kb:
			return ka < kb
		return int(w.rooms[a]["depth"]) < int(w.rooms[b]["depth"]))
	return cands[0]


func _nearest_exit(_inp: RunInput, w: RunWorld) -> Vector2:
	var p: Actor = w.player
	var best := Vector2.INF
	var bd := 1e9
	for ex in w.exits:
		if not ex["active"]:
			continue
		var d := float(w.find_path(p.pos, ex["pos"]).size())
		if d < bd:
			bd = d
			best = ex["pos"]
	goal_desc = "출구"
	if best != Vector2.INF and p.pos.distance_to(best) < 10.0:
		_inp.interact = true
		return Vector2.INF
	return best


func _walk(inp: RunInput, w: RunWorld, goal: Vector2, dt: float, moved: float) -> void:
	var p: Actor = w.player
	path_t -= dt
	if path.is_empty() or path_t <= 0.0 or goal.distance_to(path_goal) > 12.0:
		path = w.find_path(p.pos, goal)
		path_i = 1 if path.size() > 1 else 0
		path_t = 0.5
		path_goal = goal
	var wp := goal
	if not path.is_empty():
		while path_i < path.size() - 1 and p.pos.distance_to(path[path_i]) < 6.0:
			path_i += 1
		wp = path[mini(path_i, path.size() - 1)]
		if path_i >= path.size() - 1:
			wp = goal
	var dir := wp - p.pos
	if dir.length() < 1.5:
		inp.move = Vector2.ZERO
	else:
		inp.move = dir.normalized()
	# 꼼꼼이: 경비원 시야로 들어가려 하면 깡통을 반대편에 던지거나 잠시 기다린다
	if P.get("sneak", false) and _in_guard_cone(w, p.pos + inp.move * 28.0) and not _in_guard_cone(w, p.pos):
		var g := _nearest_guard(w)
		if g != null and not w.held.is_empty() and throw_cd <= 0.0 and rng.randf() < float(P.get("throw", 0.5)):
			var away := g.pos + (g.pos - p.pos).normalized() * 50.0
			inp.aim = away
			inp.throw = true
			throw_cd = 2.5
			inp.move = Vector2.ZERO
			return
		wait_t += dt
		if wait_t < 2.5:
			inp.move = Vector2.ZERO
			return
	else:
		wait_t = maxf(0.0, wait_t - dt)
	# 꼼꼼이: 등 돌린 경비원 뒤로 다가가 기습
	if inp.move != Vector2.ZERO:
		inp.aim = p.pos + inp.move * 30.0
	if moved < 0.15 and inp.move != Vector2.ZERO:
		stuck_t += dt
	else:
		stuck_t = maxf(0.0, stuck_t - dt)
	if stuck_t > 0.6:
		jiggle = Vector2.from_angle(rng.randf() * TAU)
		jiggle_t = 0.3
		stuck_t = 0.0
		path = PackedVector2Array()
	if jiggle_t > 0.0:
		jiggle_t -= dt
		inp.move = jiggle


func _nearest_guard(w: RunWorld) -> Actor:
	var best: Actor = null
	var bd := 1e9
	for e: Actor in w.enemies:
		if e.dead or e.kind != "guard":
			continue
		var d := e.pos.distance_to(w.player.pos)
		if d < bd:
			bd = d
			best = e
	return best
