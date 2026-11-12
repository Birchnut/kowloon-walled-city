class_name V4Shim
extends RefCounted
## V4Shim — 개발용 다리(통합 때 지운다). 이 클론에는 아직 v3 시뮬·옛 뷰뿐이라, UI가 쓰는 v4 계약
## (docs/ARCHITECTURE.md "v4 (PC판) 계약 변경")의 빈 곳을 있는 것으로 채운다.
##
## 규칙: **모든 채움은 여기 한 곳에서만.** UI 코드는 Q.dict/Q.list/Q.can_full/Q.vcall 만 부르고, Q 가 여기를 거친다.
## 이미 v4 모양으로 온 값(키가 있으면)은 건드리지 않는다 → 진짜 v4 시뮬·뷰가 오면 저절로 꺼진다.
## 통합: ENABLED = false 로 두고 확인한 뒤 이 파일과 Q.gd 의 "V4Shim" 두 줄을 지운다(목록: docs/UI_NOTES.md v4 §심 목록).
##
## 여기 든 계산(사각 범위·덮임·신호등 판정)은 **임시 흉내**다. 규칙의 원본은 SIM 이다.

const ENABLED := true

## DevHarness hz=1: 불·병 견본(불난 집 1, 탄 집 1, 아픈 집 2)을 보여 준다(화면 확인용).
static var sample_hazards := false


# ================================================================== 질의
static func query(n: String, args: Dictionary, v: Variant) -> Variant:
	if not ENABLED:
		return v
	match n:
		"hud":
			return _hud(v)
		"build_menu":
			return _build_menu(v)
		"metrics":
			return v if (v is Dictionary and (v as Dictionary).has("rows")) else _metrics()
		"hazards":
			return v if (v is Dictionary and (v as Dictionary).has("fire")) else _hazards()
		"coverage":
			return v if (v is Dictionary and (v as Dictionary).has("covered")) else _coverage(str(args.get("kind", "market")))
		"range_preview":
			return _range_preview(args, v)
		"info":
			return _info(v)
		"expeditions":
			return _expeditions(v)
	return v


static func can(n: String, args: Dictionary, v: Dictionary) -> Dictionary:
	if not ENABLED or n != "build" or v.has("cells"):
		return v
	var it := menu_item(str(args.get("type", "")))
	var pos: Variant = args.get("pos")
	if not (pos is Vector3i) or it.is_empty():
		return v
	var cells := footprint_cells(it, pos, int(args.get("rot", 0)))
	var out := v.duplicate()
	out["cells"] = cells
	out["supports"] = v.get("support_cells", [])
	if not bool(v.get("ok", false)):
		return out
	var st: Variant = Game.state
	if st == null:
		return out
	var gw := int(Data.cfg("grid.width", 12))
	var gh := int(Data.cfg("grid.height", 12))
	for c: Vector3i in cells:
		if c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh:
			out["ok"] = false
			out["code"] = "shape"
			out["reason"] = "부지 밖으로 나간다 — 모양이 다 들어갈 자리가 필요하다."
			return out
		if c.z >= int(st.floors_unlocked):
			out["ok"] = false
			out["code"] = "floor"
			out["reason"] = "%d층이 아직 안 열렸다 — 두 개 층짜리는 두 층 모두 자리가 있어야 한다." % (c.z + 1)
			return out
		if st.cells.has(c):
			out["ok"] = false
			out["code"] = "shape"
			out["reason"] = "자리가 모자란다 — %d×%d 모양이 다 빈칸이어야 한다." % [_fp(it, int(args.get("rot", 0))).x, _fp(it, int(args.get("rot", 0))).y]
			return out
	return out


# ================================================================== 뷰
## 뷰에 그 메서드가 없을 때 Q.vcall 이 부른다. 옛 뷰(v3)의 비슷한 것으로 흉내.
static func view_call(v: Node, method: String, a: Array, fallback: Variant) -> Variant:
	if not ENABLED or v == null:
		return fallback
	match method:
		"set_insets":
			if v.has_method("set_bottom_inset") and a.size() >= 4:
				v.call("set_bottom_inset", float(a[3]))
			return null
		"hover":
			return v.call("pick", a[0]) if v.has_method("pick") else {}
		"set_zone_preview":
			var cells: Array = a[0] if a.size() > 0 and a[0] is Array else []
			var oks: Array = a[1] if a.size() > 1 and a[1] is Array else []
			var good: Array = []
			var bad: Array = []
			for i in cells.size():
				if i < oks.size() and not bool(oks[i]):
					bad.append(cells[i])
				else:
					good.append(cells[i])
			if v.has_method("show_cells"):
				v.call("show_cells", good, "valid")
				v.call("show_cells", bad, "warn")
			return null
		"set_coverage":
			if v.has_method("show_cells"):
				v.call("show_cells", a[0] if a.size() > 0 else [], "range")
				v.call("show_cells", a[1] if a.size() > 1 else [], "warn")
			return null
		"focus":
			var p: Variant = a[0] if a.size() > 0 else null
			if p is Vector3i and v.get("target") != null:
				var fh := 1.0
				var cfg: Variant = v.get("cfg")
				if cfg != null and cfg.get("floor_h") != null:
					fh = float(cfg.get("floor_h"))
				v.set("target", Vector3(p.x + 0.5, (p.z + 0.5) * fh, p.y + 0.5))
				if a.size() > 1 and int(a[1]) >= 0 and v.has_method("set_zoom"):
					v.call("set_zoom", int(a[1]))
				if v.has_method("_clamp_target"):
					v.call("_clamp_target")
				if v.has_method("_apply_camera"):
					v.call("_apply_camera")
			return null
		"set_input_enabled":
			if v is Control:
				(v as Control).mouse_filter = Control.MOUSE_FILTER_STOP if bool(a[0]) else Control.MOUSE_FILTER_IGNORE
			return null
		"who":
			return {"ok": false, "text": ""}
	return fallback


## 옛 뷰는 카메라 키·오른쪽 끌기를 모른다(v4 에서는 뷰가 가진다). v4 뷰(hover 가 있음)면 아무것도 안 한다.
static func is_v4_view(v: Node) -> bool:
	return v != null and v.has_method("hover") and v.has_method("set_zone_preview")


static func camera_input(v: Node, ev: InputEvent) -> bool:
	if not ENABLED or v == null or is_v4_view(v):
		return false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match (ev as InputEventKey).keycode:
			KEY_Q:
				v.call("rotate_view", -1)
				return true
			KEY_E:
				v.call("rotate_view", 1)
				return true
			KEY_PAGEUP, KEY_BRACKETRIGHT:
				_cut_step(v, 1)
				return true
			KEY_PAGEDOWN, KEY_BRACKETLEFT:
				_cut_step(v, -1)
				return true
	if ev is InputEventMouseMotion and ((ev as InputEventMouseMotion).button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0:
		if v.has_method("pan_by"):
			v.call("pan_by", (ev as InputEventMouseMotion).relative)
		return false
	return false


static func _cut_step(v: Node, d: int) -> void:
	var st: Variant = Game.state
	var top := int(st.floors_unlocked) if st != null else 1
	var cur := int(v.get("floor_cut")) if v.get("floor_cut") != null else -1
	var n := cur
	if d > 0:
		n = -1 if cur < 0 or cur + 1 >= top else cur + 1
	else:
		n = top - 1 if cur < 0 else maxi(cur - 1, 0)
	v.call("set_floor_cut", n)


static func camera_process(v: Node, delta: float) -> void:
	if not ENABLED or v == null or is_v4_view(v) or not v.has_method("pan_by"):
		return
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		d.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		d.y -= 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		d.x += 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		d.x -= 1
	if d != Vector2.ZERO:
		v.call("pan_by", d * 600.0 * delta)


# ================================================================== 채움
static func menu_item(id: String) -> Dictionary:
	for cat: Variant in UI.to_array(query("build_menu", {}, Game.query("build_menu", {}))):
		for it: Variant in UI.to_array(UI.to_dict(cat).get("items", [])):
			if it is Dictionary and str(it.get("id", "")) == id:
				return it
	return {}


static func _fp(it: Dictionary, rot: int) -> Vector2i:
	var fp: Array = UI.to_array(it.get("footprint", [1, 1]))
	var w := int(fp[0]) if fp.size() > 0 else 1
	var h := int(fp[1]) if fp.size() > 1 else 1
	return Vector2i(h, w) if rot % 2 == 1 else Vector2i(w, h)


static func footprint_cells(it: Dictionary, pos: Vector3i, rot: int) -> Array:
	var f := _fp(it, rot)
	var out: Array = []
	for dz in maxi(1, int(it.get("floors", 1))):
		for x in f.x:
			for y in f.y:
				out.append(Vector3i(pos.x + x, pos.y + y, pos.z + dz))
	return out


static var _menu_cache: Array = []
static var _menu_frame: int = -1


static func _build_menu(v: Variant) -> Variant:
	if not (v is Array):
		return v
	var f := Engine.get_process_frames()
	if f == _menu_frame and not _menu_cache.is_empty():
		return _menu_cache
	var out: Array = (v as Array).duplicate(true)
	var small_rot := ["market", "service", "food", "goods", "electronics", "vice"]
	for cat: Variant in out:
		var cid := str(UI.to_dict(cat).get("cat", ""))
		for it: Variant in UI.to_array(UI.to_dict(cat).get("items", [])):
			var d: Dictionary = it
			d["sign"] = UI.no_hanja(str(d.get("sign", "")))
			if d.has("footprint"):
				continue
			var size := int(d.get("size", 1))
			var id := str(d.get("id", ""))
			var fp := [size, size]
			if size == 1 and cid in small_rot and id not in ["garden", "roof_garden"]:
				fp = [1, 2]
			d["footprint"] = fp
			d["floors"] = 2 if cid == "landmark" else 1
			d["rotatable"] = int(fp[0]) != int(fp[1])
			d["build_days"] = 0.0 if id == "house" else (2.0 if cid == "landmark" else 0.1 * float(int(fp[0]) * int(fp[1])))
			var r: Variant = d.get("range", 0)
			if (r is int or r is float) and float(r) > 0.0:
				d["range"] = {"r": int(r), "up": 1, "down": 1}
			else:
				d["range"] = null
			d["needs_sky"] = id in ["garden", "roof_garden"]
			d["min_floor"] = 0
	_menu_cache = out
	_menu_frame = f
	return out


static func _hud(v: Variant) -> Variant:
	if not (v is Dictionary):
		return v
	var d: Dictionary = (v as Dictionary).duplicate()
	if not d.has("grid"):
		d["grid"] = {"w": int(Data.cfg("grid.width", 12)), "h": int(Data.cfg("grid.height", 12)), "floors": int(Data.cfg("grid.max_floors", 10))}
	if not d.has("speed"):
		d["speed"] = Game.speed
	if not d.has("paused"):
		d["paused"] = Game.paused
	if not d.has("hazards"):
		var hz := _hazards()
		var fire: Dictionary = hz["fire"]
		var dis: Dictionary = hz["disease"]
		d["hazards"] = {"fire": {"on": fire["on"], "burning": (fire["burning"] as Array).size(), "burnt": (fire["burnt"] as Array).size(), "covered_pct": fire["covered_pct"]},
			"disease": {"on": dis["on"], "sick_houses": (dis["sick"] as Array).size(), "covered_pct": dis["covered_pct"]}}
	if not d.has("signals"):
		d["signals"] = _signals(d)
	return d


static func _ratio_state(r: float, need: bool) -> String:
	if not need:
		return "ok"
	if r >= 0.999:
		return "ok"
	if r >= 0.8:
		return "warn"
	return "bad"


static func _signals(h: Dictionary) -> Array:
	var out: Array = []
	for u: String in ["water", "power"]:
		var x := UI.to_dict(h.get(u, {}))
		var sup := float(x.get("supply", 0.0))
		var dem := float(x.get("demand", 0.0))
		var nm := "물" if u == "water" else "전기"
		var st := _ratio_state(sup / maxf(dem, 0.001), dem > 0.0)
		if u == "power" and dem <= 0.0:
			st = "off"
		out.append({"id": u, "name": nm, "state": st,
			"text": ("%s %s / %s — 넉넉하다" if st == "ok" else "%s %s / %s — 모자란다. 더 지어야 한다") % [nm, UI.dec(sup), UI.dec(dem)] if st != "off" else "전기는 아직 쓰는 곳이 없다",
			"jump": {"screen": "build", "arg": u}})
	var eco := UI.to_dict(Game.query("economy", {}))
	var worst := "ok"
	var worst_name := ""
	for g: Variant in UI.to_array(eco.get("goods", [])):
		var gd := UI.to_dict(g)
		if str(gd.get("id", "")) in ["veg", "noodles", "fishball"] and float(gd.get("cons", 0.0)) > 0.0:
			var s := str(gd.get("state", "ok"))
			if s == "bad" or (s == "warn" and worst == "ok"):
				worst = s
				worst_name = str(gd.get("name", ""))
	out.append({"id": "food", "name": "먹을 것", "state": worst,
		"text": "먹을 것이 넉넉하다" if worst == "ok" else "%s 모자람 — 현황판에서 확인" % worst_name, "jump": {"screen": "metrics", "arg": "food"}})
	var fun := _coverage("fun")
	var fs := "ok" if float(fun["pct"]) >= 0.9 or int(fun["total"]) == 0 else ("warn" if float(fun["pct"]) >= 0.6 else "bad")
	out.append({"id": "fun", "name": "놀 것", "state": fs, "text": "놀 곳 범위 안의 집 %s" % fun["text"], "jump": {"screen": "lens", "arg": "fun"}})
	var hz := UI.to_dict(h.get("hazards", {}))
	var fire := UI.to_dict(hz.get("fire", {}))
	var fst := "off"
	if bool(fire.get("on", false)):
		fst = "bad" if int(fire.get("burning", 0)) > 0 else ("warn" if float(fire.get("covered_pct", 0.0)) < 0.9 else "ok")
	out.append({"id": "fire", "name": "불", "state": fst,
		"text": "아직 불 걱정은 없다(2층이 열리면 켜진다)" if fst == "off" else ("불이 났다 — %d곳" % int(fire.get("burning", 0)) if fst == "bad" else "소방 범위 %s" % UI.pct(fire.get("covered_pct", 0.0))),
		"jump": {"screen": "lens", "arg": "fire"} if fst != "bad" else {"screen": "focus", "arg": _first_pos(_hazards()["fire"]["burning"])}})
	var dis := UI.to_dict(hz.get("disease", {}))
	var dst := "off"
	if bool(dis.get("on", false)):
		dst = "bad" if int(dis.get("sick_houses", 0)) > 0 else ("warn" if float(dis.get("covered_pct", 0.0)) < 0.9 else "ok")
	out.append({"id": "disease", "name": "병", "state": dst,
		"text": "아직 병 걱정은 없다(3층이 열리면 켜진다)" if dst == "off" else ("아픈 집 %d채" % int(dis.get("sick_houses", 0)) if dst == "bad" else "쓰레기 수거 범위 %s" % UI.pct(dis.get("covered_pct", 0.0))),
		"jump": {"screen": "lens", "arg": "trash"}})
	var lst := "ok"
	var ltxt := "일손이 맞다"
	for l: Variant in UI.to_array(h.get("labor", [])):
		var ld := UI.to_dict(l)
		if int(ld.get("need", 0)) > int(ld.get("have", 0)):
			lst = "bad" if float(ld.get("have", 0)) < float(ld.get("need", 0)) * 0.8 else "warn"
			ltxt = "%s 일손 %d / %d" % [ld.get("name", ""), int(ld.get("have", 0)), int(ld.get("need", 0))]
			break
	out.append({"id": "labor", "name": "일손", "state": lst, "text": ltxt, "jump": {"screen": "metrics", "arg": "labor"}})
	return out


static func _first_pos(arr: Variant) -> String:
	for x: Variant in UI.to_array(arr):
		var p: Variant = UI.to_dict(x).get("pos")
		if p is Vector3i:
			return "%d,%d,%d" % [p.x, p.y, p.z]
	return ""


static func _houses() -> Array:
	var out: Array = []
	var st: Variant = Game.state
	if st == null:
		return out
	var keys: Array = st.buildings.keys()
	keys.sort()
	for k: Variant in keys:
		var b: Dictionary = st.buildings[k]
		if str(b.get("kind", "")) == "house":
			out.append(b)
	return out


static func _hazards() -> Dictionary:
	var st: Variant = Game.state
	var fl := int(st.floors_unlocked) if st != null else 1
	var fire_on := fl >= 2 or sample_hazards
	var dis_on := fl >= 3 or sample_hazards
	var burning: Array = []
	var burnt: Array = []
	var sick: Array = []
	if sample_hazards:
		var hs := _houses()
		if hs.size() > 0:
			burning.append({"bid": int(hs[0]["id"]), "pos": hs[0]["pos"]})
		if hs.size() > 1:
			burnt.append({"bid": int(hs[1]["id"]), "pos": hs[1]["pos"], "repair_text": "수리 ₩120 · 고물 10 · 반나절"})
		for i in range(2, mini(4, hs.size())):
			sick.append({"bid": int(hs[i]["id"]), "pos": hs[i]["pos"], "days_left": 1.5})
	var fc := _coverage("fire")
	var tc := _coverage("trash")
	return {
		"fire": {"on": fire_on, "since_day": 1, "grace_left": 0.0, "covered_pct": fc["pct"], "burning": burning, "burnt": burnt,
			"text": "소방대 범위 밖의 칸은 불이 날 수 있다. 범위 안이면 금방 꺼진다." if fire_on else "2층이 열리면 불 걱정이 시작된다."},
		"disease": {"on": dis_on, "covered_pct": tc["pct"], "sick": sick, "trash_pct": 1.0 - float(tc["pct"]),
			"text": "쓰레기 수거 범위 밖에 쓰레기가 쌓이면 병이 돈다. 의원 범위 안이면 빨리 낫는다." if dis_on else "3층이 열리면 병 걱정이 시작된다."},
	}


static func _cov_types(kind: String) -> Array:
	var out: Array = []
	if kind.begins_with("service:"):
		return [kind.substr(8)]
	for cat: Variant in UI.to_array(_build_menu(Game.query("build_menu", {}))):
		var cid := str(UI.to_dict(cat).get("cat", ""))
		for it: Variant in UI.to_array(UI.to_dict(cat).get("items", [])):
			var id := str(UI.to_dict(it).get("id", ""))
			var look := str(UI.to_dict(it).get("look", ""))
			match kind:
				"market":
					if cid == "market":
						out.append(id)
				"fun":
					if id in ["mahjong", "teahouse", "karaoke", "gambling_den", "shrine"] or look in ["mahjong", "teahouse", "karaoke"]:
						out.append(id)
				"fire":
					if id.contains("fire") or look.begins_with("fire_"):
						out.append(id)
				"trash":
					if id.contains("trash") or look == "trash_guild":
						out.append(id)
				"clinic":
					if id.contains("clinic") or id == "dentist" or look == "clinic":
						out.append(id)
	return out


static func _coverage(kind: String) -> Dictionary:
	var st: Variant = Game.state
	var types := _cov_types(kind)
	var covered: Array = []
	var uncovered: Array = []
	if st == null:
		return {"covered": covered, "uncovered": uncovered, "pct": 0.0, "text": "", "total": 0}
	var srcs: Array = []
	for b: Variant in st.buildings.values():
		var bd: Dictionary = b
		if str(bd.get("kind", "")) == "facility" and str(bd.get("type", "")) in types:
			var it := menu_item(str(bd.get("type", "")))
			var rg := UI.to_dict(it.get("range", {}))
			if not rg.is_empty():
				var f := _fp(it, int(bd.get("rot", 0)))
				srcs.append({"pos": bd.get("pos"), "w": f.x, "h": f.y, "r": int(rg.get("r", 0)), "up": int(rg.get("up", 1)), "down": int(rg.get("down", 1))})
	for h: Dictionary in _houses():
		var p: Vector3i = h["pos"]
		var ok := false
		for s: Dictionary in srcs:
			var o: Vector3i = s["pos"]
			var dx := maxi(maxi(o.x - p.x, p.x - (o.x + int(s["w"]) - 1)), 0)
			var dy := maxi(maxi(o.y - p.y, p.y - (o.y + int(s["h"]) - 1)), 0)
			var dz := p.z - o.z
			if maxi(dx, dy) <= int(s["r"]) and dz <= int(s["up"]) and dz >= -int(s["down"]):
				ok = true
				break
		(covered if ok else uncovered).append(p)
	var tot := covered.size() + uncovered.size()
	var pctv := float(covered.size()) / float(tot) if tot > 0 else 0.0
	return {"covered": covered, "uncovered": uncovered, "pct": pctv, "text": "%d / %d채" % [covered.size(), tot], "total": tot}


static func _range_preview(args: Dictionary, v: Variant) -> Variant:
	var d: Dictionary = UI.to_dict(v).duplicate()
	if d.has("by_floor"):
		return d
	var it := menu_item(str(args.get("type", "")))
	var pos: Variant = args.get("pos")
	var rg := UI.to_dict(it.get("range", {}))
	if it.is_empty() or not (pos is Vector3i) or rg.is_empty():
		return {"cells": [], "by_floor": {}, "houses": 0, "text": ""}
	var f := _fp(it, int(args.get("rot", 0)))
	var r := int(rg.get("r", 0))
	var gw := int(Data.cfg("grid.width", 12))
	var gh := int(Data.cfg("grid.height", 12))
	var st: Variant = Game.state
	var top := int(st.floors_unlocked) if st != null else 1
	var by: Dictionary = {}
	var cells: Array = []
	var houses := 0
	for dz in range(-int(rg.get("down", 1)), int(rg.get("up", 1)) + maxi(1, int(it.get("floors", 1)))):
		var z: int = pos.z + dz
		if z < 0 or z >= top:
			continue
		var fl: Array = []
		for x in range(pos.x - r, pos.x + f.x + r):
			for y in range(pos.y - r, pos.y + f.y + r):
				if x < 0 or y < 0 or x >= gw or y >= gh:
					continue
				var c := Vector3i(x, y, z)
				fl.append(c)
				cells.append(c)
				if st != null and st.cells.has(c) and str(UI.to_dict(st.cells[c]).get("kind", "")) == "house":
					houses += 1
		by[z] = fl
	return {"cells": cells, "by_floor": by, "houses": houses, "text": "범위 안 주거 %d채" % houses}


static func _info(v: Variant) -> Variant:
	if not (v is Dictionary):
		return v
	var d: Dictionary = (v as Dictionary).duplicate()
	var kind := str(d.get("kind", ""))
	if kind == "facility" and not d.has("w"):
		var it := menu_item(str(d.get("type", "")))
		var f := _fp(it, 0)
		d["w"] = f.x
		d["h"] = f.y
		d["d"] = int(it.get("floors", 1))
		d["rot"] = 0
		if not d.has("range") or not (d["range"] is Dictionary):
			d["range"] = it.get("range")
		d["build_left_text"] = ""
		d["interior"] = {"staff_ratio": UI.to_dict(d.get("staff", {})).get("ratio", 1.0), "active": d.get("active", true)}
	elif kind == "house" and not d.has("burn"):
		d["arriving_text"] = ""
		d["burn"] = ""
		d["sick"] = false
		d["repair"] = null
		if sample_hazards:
			var hz := _hazards()
			for b: Variant in hz["fire"]["burning"]:
				if int(UI.to_dict(b).get("bid", -1)) == int(d.get("bid", -2)):
					d["burn"] = "burning"
			for b2: Variant in hz["fire"]["burnt"]:
				if int(UI.to_dict(b2).get("bid", -1)) == int(d.get("bid", -2)):
					d["burn"] = "burnt"
					d["repair"] = {"ok": true, "cost_text": "₩120 · 고물 10", "days": 0.5}
			for s: Variant in hz["disease"]["sick"]:
				if int(UI.to_dict(s).get("bid", -1)) == int(d.get("bid", -2)):
					d["sick"] = true
	return d


static func _expeditions(v: Variant) -> Variant:
	if not (v is Dictionary):
		return v
	var d: Dictionary = (v as Dictionary).duplicate(true)
	var spd := float(Data.cfg("time.seconds_per_day", 600.0))
	for t: Variant in UI.to_array(d.get("teams", [])):
		var td: Dictionary = t
		if not td.has("days_left"):
			td["days_left"] = float(td.get("seconds_left", 0.0)) / spd
			td["total_days"] = float(td.get("total_seconds", 0.0)) / spd
	var i := 0
	for x: Variant in UI.to_array(d.get("dests", [])):
		var xd: Dictionary = x
		i += 1
		if not xd.has("stock_pct"):
			xd["stock_pct"] = 0.35 + 0.13 * float((i * 37) % 6)
		if not xd.has("days"):
			xd["days"] = float(xd.get("seconds", 0.0)) / spd
		if not xd.has("run"):
			var band := str(xd.get("band", "near"))
			xd["run"] = {"available": false, "danger": {"near": 1, "mid": 2, "far": 3}.get(band, 1), "text": "직접 줍기 — 아직 준비 중(시제품 단계)"}
	return d


static func _metrics() -> Dictionary:
	var eco := UI.to_dict(Game.query("economy", {}))
	var hud := UI.to_dict(_hud(Game.query("hud", {})))
	var rows: Array = []
	var hints := {"water": "빗물받이·급수탑을 더 짓는다", "power": "발전기를 짓거나 외부 전력을 끈다"}
	for u: Variant in UI.to_array(eco.get("utilities", [])):
		var ud := UI.to_dict(u)
		var sup := float(ud.get("supply", 0.0))
		var dem := float(ud.get("demand", 0.0))
		var st := _ratio_state(sup / maxf(dem, 0.001), dem > 0.0)
		rows.append({"id": str(ud.get("id", "")), "group": "utility", "name": str(ud.get("name", "")), "supply": sup, "demand": dem, "unit": "",
			"ratio": sup / maxf(dem, 0.001) if dem > 0.0 else 1.0, "state": st, "days_left": null,
			"hint": "넉넉하다" if st == "ok" else str(hints.get(str(ud.get("id", "")), "더 짓는다")),
			"jump": {"screen": "build", "arg": str(ud.get("id", ""))}})
	var food_ids := ["veg", "noodles", "fishball", "moonshine"]
	for g: Variant in UI.to_array(eco.get("goods", [])):
		var gd := UI.to_dict(g)
		if str(gd.get("cat", "")) != "consumer":
			continue
		var sup2 := float(gd.get("prod", 0.0)) + float(gd.get("imp", 0.0))
		var dem2 := float(gd.get("cons", 0.0)) + float(gd.get("exp", 0.0))
		var st2 := str(gd.get("state", "ok"))
		var dl: Variant = gd.get("days_left", -1.0)
		var hint := "넉넉하다"
		if st2 != "ok":
			hint = "만드는 곳을 늘리거나 교역으로 들인다"
		elif dem2 <= 0.0 and float(gd.get("stock", 0.0)) <= 0.0:
			hint = "아직 찾는 집이 없다"
		rows.append({"id": str(gd.get("id", "")), "group": "food" if str(gd.get("id", "")) in food_ids else "goods", "name": str(gd.get("name", "")),
			"supply": sup2, "demand": dem2, "unit": "/일", "ratio": sup2 / maxf(dem2, 0.001) if dem2 > 0.0 else 1.0, "state": st2,
			"days_left": dl if (dl is float or dl is int) and float(dl) >= 0.0 else null, "stock": float(gd.get("stock", 0.0)),
			"hint": hint, "jump": {"screen": "economy", "arg": str(gd.get("id", ""))}})
	for k: Array in [["market", "시장 범위"], ["fun", "놀 곳 범위"]]:
		var cv := _coverage(k[0])
		var tot := int(cv["total"])
		var stc := "ok" if float(cv["pct"]) >= 0.95 or tot == 0 else ("warn" if float(cv["pct"]) >= 0.7 else "bad")
		rows.append({"id": k[0], "group": "service", "name": k[1], "supply": float((cv["covered"] as Array).size()), "demand": float(tot), "unit": "채",
			"ratio": float(cv["pct"]) if tot > 0 else 1.0, "state": stc, "days_left": null,
			"hint": "범위 밖의 집 %d채 — 렌즈로 본다" % (cv["uncovered"] as Array).size() if stc != "ok" else "다 닿는다",
			"jump": {"screen": "lens", "arg": k[0]}})
	var hz := _hazards()
	var hazards: Array = []
	for hk: Array in [["fire", "불", "소방 범위"], ["disease", "병", "쓰레기 수거 범위"]]:
		var x: Dictionary = hz[hk[0]]
		var on := bool(x["on"])
		var active := (x["burning"] as Array).size() + (x["burnt"] as Array).size() if hk[0] == "fire" else (x["sick"] as Array).size()
		var stz := "off" if not on else ("bad" if active > 0 else ("warn" if float(x["covered_pct"]) < 0.9 else "ok"))
		hazards.append({"id": hk[0], "name": hk[1], "on": on, "covered_pct": x["covered_pct"], "active": active, "text": str(x["text"]),
			"jump": {"screen": "lens", "arg": "fire" if hk[0] == "fire" else "trash"}})
		rows.append({"id": hk[0], "group": "hazard", "name": hk[2], "supply": float(x["covered_pct"]) * 100.0, "demand": 100.0, "unit": "%",
			"ratio": float(x["covered_pct"]), "state": stz, "days_left": null,
			"hint": "아직 꺼져 있다" if not on else ("불난 곳 %d · 탄 집 %d" % [(x["burning"] as Array).size(), (x["burnt"] as Array).size()] if hk[0] == "fire" else "아픈 집 %d채" % active),
			"jump": {"screen": "lens", "arg": "fire" if hk[0] == "fire" else "trash"}})
	var tiers: Array = []
	for t: Variant in UI.to_array(eco.get("tiers", [])):
		var td := UI.to_dict(t).duplicate()
		td["full"] = td.get("full_houses", 0)
		td["arriving"] = 0
		tiers.append(td)
	var fin := UI.to_dict(eco.get("finance", {}))
	var avg := UI.to_dict(fin.get("avg", {}))
	var inc := 0.0
	var cost := 0.0
	var lines: Array = []
	for l: Variant in UI.to_array(fin.get("lines", [])):
		var ld := UI.to_dict(l)
		var a := float(avg.get(str(ld.get("id", "")), ld.get("amount", 0.0)))
		if a > 0.0:
			inc += a
		else:
			cost += a
		lines.append({"name": str(ld.get("name", "")), "amount": a})
	return {"rows": rows, "labor": eco.get("labor", hud.get("labor", [])), "tiers": tiers,
		"finance": {"income": inc, "cost": cost, "net": float(avg.get("net", fin.get("net", 0.0))), "lines": lines}, "hazards": hazards}
