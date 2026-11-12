class_name CityMarkers
extends Node3D
## 건물 표시(뷰 전용, v4 9×9): 수요 부족 "!" · 승급 가능 "▲" · 멈춘 시설 "z" · 불 · 병 · 탄 집(수리 망치). 건물마다 하나, 발자국 가운데 위.
## buildings[bid]만 읽는다. building_changed마다 refresh() — 메시는 다시 짓지 않는다.
## 깊이 검사 없이 맨 위에 그리되, 완전히 파묻힌 칸(드러난 면이 없는 칸)은 건너뛴다.

const MAX_INST := 256
const ICON := 9          # 아이콘 칸 크기(텍셀)
const KINDS := {"bad": 0, "up": 1, "off": 2, "warn": 3, "fire": 4, "sick": 5, "repair": 6, "burnt": 7}
const ART := {
	"bad": ["...###...", "..#####..", ".###r###.", "###rrr###", "###rrr###", ".###r###.", "..##r##..", "...###...", "........."],
	"warn": ["...###...", "..#####..", ".###k###.", "###kkk###", "###kkk###", ".###k###.", "..##k##..", "...###...", "........."],
	"up": ["....g....", "...ggg...", "..ggggg..", ".ggggggg.", "ggggggggg", "...ggg...", "...ggg...", "...ggg...", "........."],
	"off": ["..#####..", ".#######.", "##zzzzz##", "####zz###", "###zz####", "##zzzzz##", ".#######.", "..#####..", "........."],
	"fire": ["....o....", "...oo..o.", "..ooo.oo.", ".ooyoooo.", ".oyyyoo..", "ooyyyyoo.", "oyyyyyyo.", ".oyyyyo..", "..oooo..."],
	"sick": ["..#####..", ".##ggg##.", "##ggggg##", "#gg#g#gg#", "#ggggggg#", "##g###g##", ".#ggggg#.", "..#####..", "........."],
	"repair": ["......bb.", ".....b..b", "......bb.", ".....b...", "....b....", "...b.....", "ww.......", "www......", ".w......."],
	"burnt": ["..#####..", ".#######.", "##kkkkk##", "##k###k##", "##k###k##", "##kkkkk##", ".#######.", "..#####..", "........."],
}
const PRIO := {0: 5, 1: 2, 2: 3, 3: 1, 4: 9, 5: 4, 6: 6, 7: 6}
const PAL := {"#": "#2a2238", "r": "#ffffff", "k": "#2a2238", "g": "#5dff9a", "z": "#ffffff", "o": "#ff6a2a", "y": "#ffe27a", "b": "#d8d2c4", "w": "#a8704e"}
const FILL := {"bad": "#ff4a4a", "warn": "#ffc43c", "off": "#8a84a6", "sick": "#b8e05a", "burnt": "#6a6070"}

var cfg: ViewCfg
var view: Control
var mesher: CityMesher
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _items: Array = []   # [{pos: Vector3, kind: int, seed: float}]
var show_warn := false   # needs 렌즈가 켜지면 주의(노랑)와 승급 가능(▲)도 보인다


func setup(c: ViewCfg, v: Control, m: CityMesher) -> void:
	cfg = c
	view = v
	mesher = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = MAX_INST
	mm.visible_instance_count = 0
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://view/shaders/marker.gdshader")
	var tex := _make_icons()
	_mat.set_shader_parameter("tex", tex)
	_mat.set_shader_parameter("frame_px", Vector2(ICON, ICON))
	_mat.set_shader_parameter("sheet_px", Vector2(tex.get_width(), tex.get_height()))
	_mat.render_priority = 20
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = _mat
	_mmi.custom_aabb = AABB(Vector3(-30, -5, -30), Vector3(80, 40, 80))
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


func _make_icons() -> ImageTexture:
	var names: Array = KINDS.keys()
	var img := Image.create(ICON * names.size(), ICON, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for nm in names:
		var ox: int = int(KINDS[nm]) * ICON
		var art: Array = ART[nm]
		for y in ICON:
			var row: String = art[y]
			for x in ICON:
				var ch := row[x]
				if ch == ".":
					continue
				var c := Color(PAL.get(ch, "#ffffff"))
				if ch == "#" and FILL.has(nm):
					# 테두리 안쪽(이웃이 모두 칠해진 칸)은 바탕색
					var inner := x > 0 and y > 0 and x < ICON - 1 and y < ICON - 1 and row[x - 1] != "." and row[x + 1] != "." and str(art[y - 1])[x] != "." and str(art[y + 1])[x] != "."
					if inner:
						c = Color(FILL[nm])
				img.set_pixel(ox + x, y, c)
		if nm == "up":
			for y in ICON:
				for x in ICON:
					if str(art[y])[x] == "." and ((x > 0 and str(art[y])[x - 1] == "g") or (x < ICON - 1 and str(art[y])[x + 1] == "g") or (y < ICON - 1 and str(art[y + 1])[x] == "g")):
						img.set_pixel(ox + x, y, Color("#1e4a2e"))
	return ImageTexture.create_from_image(img)


## 상태에서 표시 목록을 다시 만든다(가볍다: 건물 수만큼).
func refresh(st: CityState) -> void:
	_items.clear()
	if st == null:
		return
	var bs: Variant = st.get("buildings")
	if not (bs is Dictionary):
		_push()
		return
	var cut: int = int(view.floor_cut)
	var fh := cfg.floor_h
	for bid in bs:
		var b: Variant = bs[bid]
		if not (b is Dictionary):
			continue
		var kind := -1
		var bk: String = str(b.get("kind", ""))
		var burn: String = str(b.get("burn", ""))
		var zi: int = int(view.zoom_i)
		if burn == "burning":
			kind = KINDS["fire"]
		elif burn == "burnt":
			kind = KINDS["repair"] if b.get("repair", null) is Dictionary else KINDS["burnt"]
		elif bool(b.get("sick", false)) and (zi >= 2 or show_warn or ViewCfg.h2(int(bid), 3) % 4 == 0):
			kind = KINDS["sick"]   # 멀리선 병든 집 넷 중 하나만(구역이 보이면 충분), 가까이선 전부
		elif bk == "house":
			var ns: String = str(b.get("need_state", "ok"))
			if ns == "bad":
				kind = KINDS["bad"]
			elif bool(b.get("upgradable", false)) and (show_warn or zi >= 2):
				kind = KINDS["up"]      # 승급 가능 ▲: 가까이(2단 이상)나 수요 렌즈에서만 — 멀리선 도시를 덮는다
			elif ns == "warn" and show_warn:
				kind = KINDS["warn"]
		elif bk == "facility":
			if not bool(b.get("active", true)) and zi >= 1:
				kind = KINDS["off"]
		if kind < 0:
			continue
		var pos: Variant = b.get("pos", null)
		if not (pos is Vector3i):
			continue
		var p: Vector3i = pos
		if cut >= 0 and p.z > cut:
			continue
		var size := int(b.get("size", 1))
		var bw := int(b.get("w", size))
		var bh := int(b.get("h", size))
		var bd := int(b.get("d", 1))
		if bw * bh <= 1 and bd <= 1 and not _exposed(p, cut) and kind != KINDS["fire"]:
			continue
		var c := Vector3(p.x + 0.5 * float(bw), (p.z + bd) * fh + 0.05, p.y + 0.5 * float(bh))
		if cut >= 0 and p.z == cut:
			c.y = p.z * fh + 0.45
		_items.append({"pos": c, "kind": kind, "seed": float(int(bid) % 17) / 17.0, "col": Vector2i(p.x, p.y), "z": p.z})
	# 기둥마다 하나만(가장 급한 것, 같으면 가장 높은 것) — 탑에 표시가 줄줄이 달리지 않게
	var best: Dictionary = {}
	for it in _items:
		var k: Vector2i = it["col"]
		var cur: Variant = best.get(k, null)
		if cur == null or PRIO[it["kind"]] > PRIO[cur["kind"]] or (PRIO[it["kind"]] == PRIO[cur["kind"]] and int(it["z"]) > int(cur["z"])):
			best[k] = it
	_items = best.values()
	if _items.size() > MAX_INST:
		_items.resize(MAX_INST)
	_push()


func _exposed(p: Vector3i, cut: int) -> bool:
	if cut >= 0 and p.z == cut:
		return true
	if not mesher.solid.has(p + Vector3i(0, 0, 1)):
		return true
	for d in CityMesher.DIR:
		if not mesher.solid.has(p + d):
			return true
	return false


func _push() -> void:
	var mm := _mmi.multimesh
	var n := mini(_items.size(), MAX_INST)
	for i in n:
		var it: Dictionary = _items[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, it["pos"]))
		var bob := 1.0 if (it["kind"] == KINDS["up"] or it["kind"] == KINDS["fire"]) else 0.0
		mm.set_instance_custom_data(i, Color(float(it["kind"]), bob, float(it["seed"]), 0.0))
	mm.visible_instance_count = n


func set_frame(ppu: float, px_scale: float, t: float) -> void:
	_mat.set_shader_parameter("ppu", ppu)
	_mat.set_shader_parameter("px_scale", px_scale)
	_mat.set_shader_parameter("time_s", t)


func count() -> int:
	return _items.size()
