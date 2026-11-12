extends RefCounted
## 화면 확인용 입력 대본(script=이름). 장면을 차려 놓고(적 배치·순간 이동) 정해진 입력을 넣는다.
## 사람이 하는 것과 같은 RunInput만 쓴다. 차림은 확인용이라 규칙 밖의 일(순간 이동)을 한다.
## 이름: rat dog guard slap throw search pack noise junk wire boss bosswin exit down

const RunWorld = preload("res://expedition/RunWorld.gd")
const RunInput = preload("res://expedition/RunInput.gd")
const Actor = preload("res://expedition/RunActor.gd")

var name := ""
var t := 0.0
var w: RunWorld
var mem: Dictionary = {}


func setup(n: String, world: RunWorld) -> void:
	name = n
	w = world
	var p: Actor = w.player
	match name:
		"rat":
			_teleport_room_center(1)
			for k in 4:
				var r := w._spawn_enemy("rat", p.pos + Vector2(50 + k * 6, -10 + k * 7), w.cur_room)
				r.aware = true
				r.set_state("chase")
		"dog":
			_teleport_room_center(1)
			var d := w._spawn_enemy("dog", p.pos + Vector2(60, 0), w.cur_room)
			d.aware = true
			d.set_state("circle", 0.6)
		"guard":
			_teleport_room_center(1)
			var g := w._spawn_enemy("guard", p.pos + Vector2(90, 0), w.cur_room)
			g.face = Vector2.LEFT
			g.data["patrol"] = [p.pos + Vector2(90, 0), p.pos + Vector2(90, 40)]
			g.set_state("look", 99.0)
			g.data["look_base"] = PI
		"slap":
			_teleport_room_center(1)
			# 오른쪽 벽 쪽으로 몰아 둔다
			var rr: Rect2 = w._room_rect(w.cur_room)
			p.pos = Vector2(rr.end.x - 60, rr.get_center().y)
			p.pos = w.cell_center(w._free_cell_near(w.to_cell(p.pos)))
			var d3 := w._spawn_enemy("dog", p.pos + Vector2(20, 0), w.cur_room)
			d3.aware = true
			d3.set_state("recover", 2.0)
			var g3 := w._spawn_enemy("guard", p.pos + Vector2(0, 26), w.cur_room)
			g3.aware = true
			g3.set_state("recover", 2.0)
			for k in 3:
				var r3 := w._spawn_enemy("rat", p.pos + Vector2(-20 - k * 6, -14 + k * 8), w.cur_room)
				r3.aware = true
				r3.set_state("recover", 3.0)
		"throw":
			_teleport_room_center(1)
			var g2 := w._spawn_enemy("guard", p.pos + Vector2(80, 0), w.cur_room)
			g2.face = Vector2.LEFT
			g2.data["patrol"] = [p.pos + Vector2(80, 0)]
			g2.set_state("look", 99.0)
			g2.data["look_base"] = PI
			w.held = ["can", "can"]
			p.pos += Vector2(-40, 0)
		"search", "noise":
			var pl := _nearest_pile_with_loot()
			p.pos = (pl["pos"] as Vector2) + Vector2(-14, 2)
			w._room_step()
			if name == "noise":
				w.noise = 88.0
		"pack":
			var goods := ["scrap", "wood", "concrete", "scrap", "metal", "canned"]
			for k in 6:
				w.pack[k] = {"good": goods[k], "bundles": 3 if goods[k] != "metal" else 2, "units": 9 if goods[k] != "metal" else 4}
			var it := w._mk_item("good", p.pos + Vector2(4, 3), {"good": "elec", "units": 2, "bundles": 1})
			w.items.append(it)
		"junk":
			for j in w.junks:
				p.pos = (j["pos"] as Vector2) + Vector2(-46, 10)
				w._room_step()
				break
		"wire":
			for wv in w.wires:
				p.pos = (wv["box"] as Rect2).get_center() + Vector2(0, 0)
				p.pos = w.cell_center(wv["cells"][0])
				w._room_step()
				break
		"boss", "bosswin":
			var b: Actor = w.boss
			var rr: Rect2 = w._room_rect(b.room)
			p.pos = Vector2(rr.get_center().x, rr.end.y - 40)
			w.visited[b.room] = true
			w._room_step()
			if name == "bosswin":
				b.hp = 1
				p.hp = p.max_hp
				w.pack[0] = {"good": "metal", "bundles": 2, "units": 4}
				w.pack[1] = {"good": "elec", "bundles": 2, "units": 4}
		"exit":
			w.pack[0] = {"good": "metal", "bundles": 3, "units": 6}
			w.pack[1] = {"good": "scrap", "bundles": 2, "units": 6}
			w.pack[2] = {"good": "elec", "bundles": 1, "units": 2}
			w.found = {"metal": 6, "scrap": 6, "elec": 2}
			var ex0: Dictionary = w.exits[0]
			p.pos = w.cell_center(w._free_cell_near(w.to_cell((ex0["pos"] as Vector2) + Vector2(24, 0))))
		"down":
			_teleport_room_center(1)
			p.hp = 1
			w.pack[0] = {"good": "metal", "bundles": 3, "units": 6}
			w.pack[1] = {"good": "scrap", "bundles": 3, "units": 9}
			w.pack[2] = {"good": "elec", "bundles": 2, "units": 4}
			w.found = {"metal": 6, "scrap": 9, "elec": 4}
			var d2 := w._spawn_enemy("dog", p.pos + Vector2(50, 0), w.cur_room)
			d2.aware = true
			d2.set_state("tele", 0.6)
			d2.lock_dir = Vector2.LEFT
	w.input.aim = p.pos + Vector2(40, 0)


func _teleport_room_center(depth: int) -> void:
	for r in w.rooms:
		if int(r["depth"]) == depth and r["kind"] == "normal":
			var c: Vector2i = r["origin"] + Vector2i(13, 8)
			w.player.pos = w.cell_center(w._free_cell_near(c))
			w.visited[r["id"]] = true
			w._room_step()
			# 그 방의 원래 적은 치운다(대본 장면만 보이게)
			for e in w.enemies:
				if e.room == r["id"]:
					e.dead = true
					e.state = "gone"
					e.st = 9.0
			return


func _nearest_pile_with_loot() -> Dictionary:
	var best: Dictionary = {}
	var bd := 1e9
	for pl in w.piles:
		if pl["bundles"].size() >= 2:
			var d: float = w.player.pos.distance_to(pl["pos"])
			if d < bd:
				bd = d
				best = pl
	return best


func fill(inp: RunInput, world: RunWorld, dt: float) -> void:
	t += dt
	var p: Actor = world.player
	if name in ["boss", "bosswin"]:
		return
	inp.move = Vector2.ZERO
	inp.interact = false
	match name:
		"rat", "dog":
			var tgt: Actor = null
			for e: Actor in world.enemies:
				if not e.dead and e.state != "gone":
					tgt = e
					break
			if tgt != null:
				inp.aim = tgt.pos
				if tgt.state == "tele" and tgt.st > tgt.timer * 0.75 and not mem.has("rolled%d" % tgt.id):
					mem["rolled%d" % tgt.id] = true
					inp.move = Vector2(0, 1)
					inp.roll = true
				elif tgt.state in ["recover", "stun"] and p.pos.distance_to(tgt.pos) < 40:
					inp.move = (tgt.pos - p.pos).normalized()
					if p.pos.distance_to(tgt.pos) < 26:
						inp.attack = true
		"guard":
			if t < 1.2:
				inp.move = Vector2(0.6, 0)
			else:
				for e: Actor in world.enemies:
					if e.kind == "guard" and not e.dead:
						inp.aim = e.pos
						if e.state == "tele" and e.st > e.timer * 0.7 and not mem.has("r"):
							mem["r"] = true
							inp.move = Vector2(-1, 0.3)
							inp.roll = true
						elif e.state == "recover":
							inp.move = (e.pos - p.pos).normalized()
							inp.attack = p.pos.distance_to(e.pos) < 28
		"slap":
			var tgt2: Actor = null
			var bd2 := 999.0
			for e: Actor in world.enemies:
				if not e.dead and e.state != "gone" and e.pos.distance_to(p.pos) < bd2:
					bd2 = e.pos.distance_to(p.pos)
					tgt2 = e
			if tgt2 != null:
				inp.aim = tgt2.pos
				if bd2 > 22:
					inp.move = (tgt2.pos - p.pos).normalized()
				inp.attack = bd2 < 30
		"throw":
			var g: Actor = null
			for e: Actor in world.enemies:
				if e.kind == "guard" and not e.dead:
					g = e
			if g == null:
				return
			if t < 0.6:
				inp.throw_hold = t > 0.1
			if t > 0.6 and not mem.has("thrown"):
				mem["thrown"] = true
				inp.throw_hold = false
				inp.aim = g.pos + Vector2(40, -60)
				inp.throw = true
			elif mem.has("thrown") and t > 2.0:
				# 등 뒤로 돌아 들어가 기습
				var behind := g.pos - g.face * 16.0
				inp.aim = g.pos
				if p.pos.distance_to(behind) > 8 and p.pos.distance_to(g.pos) > 22:
					inp.move = (behind - p.pos).normalized()
				else:
					inp.attack = true
			else:
				inp.aim = g.pos + Vector2(40, -60)
		"search", "noise":
			inp.interact = true
			inp.aim = p.pos + Vector2(20, 0)
		"pack":
			if t > 1.0 and not mem.has("tab"):
				mem["tab"] = true
				inp.pack_toggle = true
			elif t > 2.6 and not mem.has("swap"):
				mem["swap"] = true
				inp.slot_action = 1
			elif t > 3.6 and not mem.has("close"):
				mem["close"] = true
				inp.pack_toggle = true
		"junk":
			if t < 0.6:
				inp.move = Vector2(1, 0)
			elif t > 1.0 and t < 1.4:
				inp.move = Vector2(-1, 0)
		"wire":
			inp.aim = p.pos + Vector2(30, 0)
		"exit":
			var ex: Dictionary = world.exits[0]
			if p.pos.distance_to(ex["pos"]) > 6 and t < 3.0:
				inp.move = ((ex["pos"] as Vector2) - p.pos).normalized()
			else:
				inp.interact = true
		"down":
			inp.aim = p.pos + Vector2(40, 0)
