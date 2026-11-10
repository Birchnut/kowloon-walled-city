class_name CityPeople
extends Node3D
## 사람들 — 뷰 전용 연출(규칙 없음). 가구 수와 시간대에 맞춰 옥상·골목·다리·대문 앞·(층 컷이면) 방 안을 걷는다.
## LOD 3단: 줌 ×1 = 3×5px 점사람, ×2 = 5×10px, ×4 = CC0 16×32 스프라이트(4방향, 카메라 각에 맞춰 선택).

const PeopleShader := preload("res://view/shaders/people.gdshader")
const MAX_INST := 220

var cfg: ViewCfg
var view: Control
var mesher: CityMesher
var agents: Array = []
var nodes: Dictionary = {}          # Vector3i(x,y,level) -> {pos, kind}
var by_kind: Dictionary = {}        # kind -> Array[Vector3i]
var _mmi: Array = []                # [tiny, small, near] MultiMeshInstance3D
var _mats: Array = []
var _cut := -1
var _tick := 0.0
var _rs := 12345
var _bridges: Array = []
var _nightlife := false
var _waiting_n := 0
var _gate := Vector3.ZERO


func setup(c: ViewCfg, v: Control, m: CityMesher, lg: Texture3D) -> void:
	cfg = c
	view = v
	mesher = m
	var texs := [_make_tiny(), _make_small(), _make_near()]
	var frames := [Vector2(4, 6), Vector2(6, 11), Vector2(16, 32)]
	for i in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mm.mesh = q
		mm.instance_count = MAX_INST
		mm.visible_instance_count = 0
		var mat := ShaderMaterial.new()
		mat.shader = PeopleShader
		mat.set_shader_parameter("tex", texs[i])
		mat.set_shader_parameter("lightgrid", lg)
		mat.set_shader_parameter("frame_px", frames[i])
		mat.set_shader_parameter("sheet_px", Vector2((texs[i] as Texture2D).get_width(), (texs[i] as Texture2D).get_height()))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.custom_aabb = AABB(Vector3(-30, -5, -30), Vector3(80, 40, 80))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mmi.append(mi)
		_mats.append(mat)


func _rnd() -> float:
	_rs = (_rs * 1103515245 + 12345) & 0x7fffffff
	return float((_rs >> 8) % 100000) / 100000.0


func _ri(n: int) -> int:
	return int(_rnd() * n) % maxi(n, 1)


# ------------------------------------------------------------------ 스프라이트
func _make_tiny() -> ImageTexture:
	# 3×5 점사람 2프레임(칸 4×6). 알파 0.5 = 옷(가구 유형 색으로 물든다)
	var img := Image.create(8, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hair := Color("#3a3048")
	var skin := Color("#f2c9a2")
	var shirt := Color(1, 1, 1, 0.5)
	var pants := Color("#4a5a8a")
	for f in 2:
		var ox := f * 4
		img.set_pixel(ox + 1, 1, hair)
		img.set_pixel(ox + 1, 2, skin)
		for x in 3:
			img.set_pixel(ox + x, 3, shirt)
		img.set_pixel(ox + 1, 4, shirt)
		if f == 0:
			img.set_pixel(ox + 0, 5, pants)
			img.set_pixel(ox + 2, 5, pants)
			img.set_pixel(ox + 0, 4, shirt)
			img.set_pixel(ox + 2, 4, shirt)
		else:
			img.set_pixel(ox + 1, 5, pants)
	return ImageTexture.create_from_image(img)


func _make_small() -> ImageTexture:
	# 5×10 2프레임(칸 6×11)
	var img := Image.create(12, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hair := Color("#3a3048")
	var skin := Color("#f2c9a2")
	var skin2 := Color("#dba886")
	var shirt := Color(1, 1, 1, 0.5)
	var shirt2 := Color(0.82, 0.82, 0.88, 0.5)
	var pants := Color("#4a5a8a")
	var shoe := Color("#3a3048")
	for f in 2:
		var ox := f * 6
		for x in [1, 2, 3]:
			img.set_pixel(ox + x, 1, hair)
			img.set_pixel(ox + x, 2, skin)
			img.set_pixel(ox + x, 3, skin)
		img.set_pixel(ox + 1, 2, hair)
		img.set_pixel(ox + 3, 3, skin2)
		for y in [4, 5, 6]:
			for x in 5:
				img.set_pixel(ox + x, y, shirt if x < 4 else shirt2)
		img.set_pixel(ox + 0, 6, skin)
		img.set_pixel(ox + 4, 6, skin2)
		for x in [1, 2, 3]:
			img.set_pixel(ox + x, 7, pants)
			img.set_pixel(ox + x, 8, pants)
		if f == 0:
			img.set_pixel(ox + 1, 9, pants)
			img.set_pixel(ox + 3, 9, pants)
			img.set_pixel(ox + 0, 10, shoe)
			img.set_pixel(ox + 1, 10, shoe)
			img.set_pixel(ox + 3, 10, shoe)
			img.set_pixel(ox + 4, 10, shoe)
			img.set_pixel(ox + 2, 8, Color(0, 0, 0, 0))
		else:
			img.set_pixel(ox + 2, 9, pants)
			img.set_pixel(ox + 2, 10, shoe)
			img.set_pixel(ox + 3, 10, shoe)
	return ImageTexture.create_from_image(img)


func _make_near() -> ImageTexture:
	# CC0 캐릭터 16장(각 64×96 = 4방향 × 3프레임, 프레임 16×32)을 4×4로 묶는다
	var img := Image.create(256, 384, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 16:
		var path := "res://assets/view/people/char_%02d.png" % (i + 1)
		if not ResourceLoader.exists(path):
			continue
		var t: Variant = load(path)
		if t is Texture2D:
			var src: Image = (t as Texture2D).get_image()
			if src == null:
				continue
			if src.is_compressed():
				src.decompress()
			src.convert(Image.FORMAT_RGBA8)
			img.blit_rect(src, Rect2i(0, 0, 64, 96), Vector2i((i % 4) * 64, (i / 4) * 96))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ 걸을 수 있는 곳
func rebuild(st: CityState) -> void:
	nodes.clear()
	by_kind = {"ground": [], "roof": [], "street": [], "inside": []}
	var gw := cfg.grid.x
	var gh := cfg.grid.y
	var fh := cfg.floor_h
	_nightlife = false
	for b in st.businesses.values():
		var g: String = str(b.get("group", ""))
		if g == "fun" or g == "vice":
			_nightlife = true
			break
	for x in gw:
		for y in gh:
			var h := 0
			while mesher.solid.has(Vector3i(x, y, h)):
				h += 1
			var top := Vector3i(x, y, h)
			var kind := ""
			if not st.cells.has(top):
				kind = "ground" if h == 0 else "roof"
			else:
				var c: Dictionary = st.cells[top]
				var form: String = str(cfg.recipe(str(c.get("kind", "")), str(c.get("type", ""))).get("form", "box"))
				if form == "open" and str(c.get("kind", "")) != "site":
					kind = "ground" if h == 0 else "roof"
			if kind != "":
				nodes[top] = {"pos": Vector3(x + 0.5, h * fh, y + 0.5), "kind": kind}
				by_kind[kind].append(top)
	# 담장 밖 보도(행인)
	for x in range(-2, gw + 2):
		for yy in [gh + 1, -2]:
			var k := Vector3i(x, yy, 0)
			nodes[k] = {"pos": Vector3(x + 0.5, 0, yy + 0.5), "kind": "street"}
			by_kind["street"].append(k)
	for y in range(-1, gh + 1):
		for xx in [gw + 1, -2]:
			var k2 := Vector3i(xx, y, 0)
			nodes[k2] = {"pos": Vector3(xx + 0.5, 0, y + 0.5), "kind": "street"}
			by_kind["street"].append(k2)
	if _cut >= 0:
		for p in mesher.solid:
			if p.z == _cut:
				var kk := Vector3i(p.x, p.y, 1000 + p.z)
				nodes[kk] = {"pos": Vector3(p.x + 0.5, p.z * fh, p.y + 0.5), "kind": "inside", "cell": p}
				by_kind["inside"].append(kk)
	_gate = Vector3(gw * 0.5, 0, gh + 1.3)
	_waiting_n = 0
	for h2 in st.households.values():
		if h2.get("home", null) == null:
			_waiting_n += mini(int(h2.get("size", 1)), 3)
	_waiting_n = mini(_waiting_n, 20)
	# 사라진 자리의 사람은 없앤다
	var keep: Array = []
	for a in agents:
		if a["kind"] == "gate" or a["kind"] == "bridge" or nodes.has(a["node"]):
			keep.append(a)
	agents = keep


func set_bridges(list: Array) -> void:
	_bridges = list
	var keep: Array = []
	for a in agents:
		if a["kind"] != "bridge":
			keep.append(a)
	agents = keep


func set_cut(n: int) -> void:
	if n == _cut:
		return
	_cut = n
	var keep: Array = []
	for a in agents:
		if a["kind"] != "inside":
			keep.append(a)
	agents = keep
	if Game.state != null:
		rebuild(Game.state)


# ------------------------------------------------------------------ 목표 인원
func _targets(t: float) -> Dictionary:
	var st: CityState = Game.state
	var pop := float(st.population())
	var cap := float(cfg.r("people.max", 140))
	var base := clampf(pop * 0.11, 3.0, cap)
	var hr := t * 24.0
	var ag := 0.05
	var ar := 0.02
	if hr >= 5.5 and hr < 7.5:
		ag = 0.5
		ar = 0.35
	elif hr >= 7.5 and hr < 17.0:
		ag = 1.0
		ar = 0.45
	elif hr >= 17.0 and hr < 20.0:
		ag = 0.9
		ar = 1.0
	elif hr >= 20.0 and hr < 23.5:
		ag = 0.85 if _nightlife else 0.3
		ar = 0.35
	elif hr >= 23.5 or hr < 2.0:
		ag = 0.5 if _nightlife else 0.08
		ar = 0.1
	var out := {
		"ground": int(minf(base * 0.45 * ag, float(by_kind["ground"].size()) * 0.9)),
		"roof": int(minf(base * 0.5 * ar, float(by_kind["roof"].size()) * 0.5)),
		"street": int(clampf(base * 0.12 * ag, 0.0, 10.0)),
		"inside": int(minf(float(by_kind["inside"].size()) * 0.75 * maxf(ag, 0.35), 70.0)),
		"gate": _waiting_n,
		"bridge": int(float(_bridges.size()) * 0.6 * ag)
	}
	return out


func _color_for(st: CityState) -> Array:
	var ids: Array = st.households.keys()
	if ids.is_empty():
		return [cfg.household_color(""), _ri(16)]
	var h: Dictionary = st.households[ids[_ri(ids.size())]]
	var type: String = str(h.get("type", ""))
	return [cfg.household_color(type), (type.hash() + _ri(3)) % 16]


func _spawn(kind: String, st: CityState) -> void:
	var cc := _color_for(st)
	var a := {"kind": kind, "color": cc[0], "char": cc[1], "wait": _rnd() * 2.0, "speed": 0.45 + 0.35 * _rnd(), "walking": false, "dir": Vector3(1, 0, 0), "phase": _rnd()}
	if kind == "gate":
		a["node"] = Vector3i(0, 0, -1)
		a["pos"] = _gate + Vector3((_rnd() - 0.5) * 2.6, 0, _rnd() * 1.1)
		a["home"] = a["pos"]
	elif kind == "bridge":
		if _bridges.is_empty():
			return
		var b: Dictionary = _bridges[_ri(_bridges.size())]
		a["node"] = Vector3i(0, 0, -2)
		a["a"] = b["a"]
		a["b"] = b["b"]
		a["pos"] = (b["a"] as Vector3).lerp(b["b"], _rnd())
	else:
		var list: Array = by_kind.get(kind, [])
		if list.is_empty():
			return
		var k: Vector3i = list[_ri(list.size())]
		a["node"] = k
		a["pos"] = (nodes[k]["pos"] as Vector3) + Vector3((_rnd() - 0.5) * 0.5, 0, (_rnd() - 0.5) * 0.5)
	a["from"] = a["pos"]
	a["to"] = a["pos"]
	agents.append(a)


func _pick_next(a: Dictionary) -> void:
	var kind: String = a["kind"]
	if kind == "gate":
		var home: Vector3 = a["home"]
		a["to"] = home + Vector3((_rnd() - 0.5) * 0.4, 0, (_rnd() - 0.5) * 0.4)
		return
	if kind == "bridge":
		a["to"] = a["b"] if (a["pos"] as Vector3).distance_to(a["a"]) < 0.3 else a["a"]
		return
	var k: Vector3i = a["node"]
	var here: Dictionary = nodes.get(k, {})
	if here.is_empty():
		return
	# 같은 자리 안에서 어슬렁 / 옆 칸으로
	if _rnd() < (0.6 if kind == "inside" else 0.25):
		a["to"] = (here["pos"] as Vector3) + Vector3((_rnd() - 0.5) * 0.55, 0, (_rnd() - 0.5) * 0.55)
		return
	var opts: Array = []
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
		var nk: Vector3i = k + d
		if nodes.has(nk) and nodes[nk]["kind"] == kind:
			if kind == "inside":
				# 문이 있을 법한 곳만: 같은 가구/가게거나 절반 확률
				var ca: Dictionary = Game.state.cells.get(here.get("cell", Vector3i.ZERO), {})
				var cb: Dictionary = Game.state.cells.get(nodes[nk].get("cell", Vector3i.ZERO), {})
				if not mesher._same_unit(ca, cb) and _rnd() < 0.8:
					continue
			opts.append(nk)
		elif kind == "roof":
			# 한 층 차이는 가끔 오르내린다(사다리)
			for dz in [1, -1]:
				var nk2: Vector3i = nk + Vector3i(0, 0, dz)
				if nodes.has(nk2) and nodes[nk2]["kind"] == "roof" and _rnd() < 0.25:
					opts.append(nk2)
	if opts.is_empty():
		a["to"] = (here["pos"] as Vector3) + Vector3((_rnd() - 0.5) * 0.5, 0, (_rnd() - 0.5) * 0.5)
		return
	var nx: Vector3i = opts[_ri(opts.size())]
	a["node"] = nx
	a["to"] = (nodes[nx]["pos"] as Vector3) + Vector3((_rnd() - 0.5) * 0.5, 0, (_rnd() - 0.5) * 0.5)


func step(delta: float, t: float) -> void:
	var st: CityState = Game.state
	if st == null:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.12
		var want := _targets(t)
		var have := {}
		for a in agents:
			have[a["kind"]] = int(have.get(a["kind"], 0)) + 1
		for kind in want:
			var n: int = int(have.get(kind, 0))
			if n < int(want[kind]) and agents.size() < MAX_INST:
				for i in mini(int(want[kind]) - n, 6):
					_spawn(kind, st)
			elif n > int(want[kind]):
				for i in agents.size():
					if agents[i]["kind"] == kind and not agents[i]["walking"]:
						agents.remove_at(i)
						break
	for a in agents:
		if a["walking"]:
			var to: Vector3 = a["to"]
			var pos: Vector3 = a["pos"]
			var d := to - pos
			var dist := d.length()
			var stepd: float = float(a["speed"]) * delta
			if dist <= stepd:
				a["pos"] = to
				a["walking"] = false
				a["wait"] = _rnd() * (4.0 if a["kind"] != "street" and a["kind"] != "bridge" else 0.5) + (1.5 if a["kind"] == "gate" else 0.0)
			else:
				a["pos"] = pos + d / dist * stepd
				a["dir"] = d / dist
		else:
			a["wait"] = float(a["wait"]) - delta
			if float(a["wait"]) <= 0.0:
				_pick_next(a)
				a["walking"] = (a["to"] as Vector3).distance_to(a["pos"]) > 0.02
	_render()


func _render() -> void:
	var zf: int = int(view._zoom_levels[view.zoom_i])
	var lod := 0 if zf <= 1 else (1 if zf <= 2 else 2)
	for i in 3:
		(_mmi[i] as MultiMeshInstance3D).visible = i == lod
	var mm: MultiMesh = (_mmi[lod] as MultiMeshInstance3D).multimesh
	var mat: ShaderMaterial = _mats[lod]
	mat.set_shader_parameter("ppu", view.ppu())
	mat.set_shader_parameter("px_scale", 1.0)
	var basis: Basis = view._cam.global_transform.basis
	var fh := cfg.floor_h
	var n := mini(agents.size(), MAX_INST)
	var tt: float = view._t
	var cut_y := 1000.0 if _cut < 0 else float(_cut) * fh + 0.05
	for i in n:
		var a: Dictionary = agents[i]
		var pos: Vector3 = a["pos"]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(i, a["color"])
		var dir: Vector3 = a["dir"]
		var sx := dir.dot(basis.x)
		var sy := dir.dot(basis.y)
		var walking: bool = a["walking"]
		var fr := int(tt * 5.0 + float(a["phase"]) * 7.0) % 2
		var hide := 1.0 if pos.y > cut_y else 0.0
		if lod < 2:
			mm.set_instance_custom_data(i, Color(float(fr) if walking else 0.0, 0.0, 1.0 if sx < 0.0 else 0.0, hide))
		else:
			var colx := 1
			if sx >= 0.0 and sy < 0.0:
				colx = 3
			elif sx < 0.0 and sy >= 0.0:
				colx = 0
			elif sx >= 0.0 and sy >= 0.0:
				colx = 2
			var ch: int = int(a["char"]) % 16
			var row := (1 + fr) if walking else 0
			mm.set_instance_custom_data(i, Color(float((ch % 4) * 4 + colx), float((ch / 4) * 3 + row), 0.0, hide))
	mm.visible_instance_count = n


func set_light(amb: Vector3, night: float, neon_gain: float, lg_origin: Vector3, lg_inv: Vector3) -> void:
	for m in _mats:
		var mat: ShaderMaterial = m
		mat.set_shader_parameter("amb", amb)
		mat.set_shader_parameter("night", night)
		mat.set_shader_parameter("neon_gain", neon_gain)
		mat.set_shader_parameter("lg_origin", lg_origin)
		mat.set_shader_parameter("lg_inv_size", lg_inv)
