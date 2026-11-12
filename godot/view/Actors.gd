class_name CityActors
extends Node3D
## 시설 안 사람들(v4) — FacilityBuilder가 남긴 자리(slots)에 일손·손님을 앉히고 움직인다. 규칙 없음, 상태를 읽기만 한다.
## 보이는 조건: 트인 시설(장터·노점·텃밭)은 확대 1단부터, 닫힌 시설은 가장 가까운 두 단계(인형의 집) 또는 그 층을 잘라 볼 때.
## 일손 자리는 buildings[bid].staff 비율만큼, 손님 자리는 영업 시간표(looks.json busy)와 시각만큼. 꺼진·탄 시설은 비고 어둡다.

const ActorShader := preload("res://view/shaders/actor.gdshader")
const MAX_INST := 900
const LOD_SIZE := [Vector2(6, 12), Vector2(10, 20), Vector2(20, 40), Vector2(26, 52)]
const LOD_NAME := ["S", "M", "X", "XX"]
const ANIM_HZ := {"shuffle": 5.0, "sew": 9.0, "write": 2.5, "phone": 1.6, "stamp": 3.5, "drill": 8.0, "cut": 4.0, "solder": 6.0, "hammer": 3.0, "dice": 4.0, "roll": 3.0, "stir": 1.5, "pour": 1.2}
const POSE_HZ := {"work": 4.0, "swork": 3.0, "cheer": 2.4, "sing": 1.8, "bow": 0.6, "bathe": 0.8, "sit_eat": 1.6, "taichi": 0.35, "squat": 1.2, "pass": 2.0, "walk": 4.0, "hammer": 1.6, "cook": 2.2, "carry": 3.5, "bucket": 3.5, "can": 4.0, "sack": 3.5}
const COOKS := ["noodle_stall", "burger", "sushi", "food_cans", "teahouse", "brewery", "noodle_mill", "candle", "soap"]
const MOVERS := ["carry", "walk", "can", "bucket", "sack"]
## 일손 옷(분류·외형별 제복) — 없으면 계층 팔레트
const UNIFORM := {"noodle_stall": "#f4f0e6", "burger": "#d85f5f", "sushi": "#f4f0e6", "dentist": "#eef4f6", "clinic": "#eef4f6", "pharmacy": "#eef4f6",
	"fire_bucket": "#c2463c", "fire_station": "#c2463c", "trash_guild": "#7a9a5c", "power_plant": "#5f86c4", "power_waste": "#5f86c4", "assembly": "#5f86c4",
	"callcenter": "#f4f0e6", "casino": "#2e2a3a", "landmark_hall": "#3e4a7a", "salon": "#e8a0b8", "karaoke": "#9b3a6e", "suit": "#2e2a3a"}

var cfg: ViewCfg
var view: Control
var slots: Array = []
var extra: Array = []            # 뷰가 만든 임시 사람(양동이 줄 등): 같은 모양 + "t0"
var _mmi: Array = []
var _mats: Array = []
var _vis: Array = []             # 보이는 자리 [{s, phase, ...}]
var _tick := 0.0
var _dirty := true
var _cut := -1
var _zoom_i := 1
var _inner := false
var _hour := 12.0
var _t := 0.0
var occupants: Dictionary = {}   # bid -> [{tier, shirt, pal, until, hs, look}] 걸어 들어온 손님
var _leavers: Array = []
var _guest_rank: Dictionary = {}


## 걸어온 주민이 시설에 들어와 손님 자리에 앉는다(dur초). 자리가 차 있으면 그냥 들어가 사라진 것으로.
func occupy(bid: int, who: Dictionary, dur: float) -> void:
	if not occupants.has(bid):
		occupants[bid] = []
	var w2 := who.duplicate()
	w2["until"] = _t + dur
	w2["bid"] = bid
	(occupants[bid] as Array).append(w2)
	_dirty = true


## 자리에서 일어난 손님들(주민 쪽이 문에서 다시 걷게 한다).
func pop_leavers() -> Array:
	var out := _leavers
	_leavers = []
	return out


func setup(c: ViewCfg, v: Control, lg: Texture3D) -> void:
	cfg = c
	view = v
	for i in 4:
		var sz: String = LOD_NAME[i]
		var tex := PeopleSprites.build(sz)
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
		mat.shader = ActorShader
		mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("lightgrid", lg)
		mat.set_shader_parameter("frame_px", LOD_SIZE[i])
		mat.set_shader_parameter("sheet_px", Vector2(tex.get_width(), tex.get_height()))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.custom_aabb = AABB(Vector3(-40, -5, -40), Vector3(120, 60, 120))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mmi.append(mi)
		_mats.append(mat)


func set_lightgrid(lg: Texture3D) -> void:
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("lightgrid", lg)


func set_slots(list: Array) -> void:
	slots = list
	_dirty = true


func set_extra(list: Array) -> void:
	extra = list
	_dirty = true


func set_view_state(cut: int, zoom_i: int, inner: bool) -> void:
	if cut != _cut or zoom_i != _zoom_i or inner != _inner:
		_cut = cut
		_zoom_i = zoom_i
		_inner = inner
		_dirty = true


func set_light(amb: Vector3, night: float, neon_gain: float, lg_origin: Vector3, lg_inv: Vector3, warm: Vector3) -> void:
	for m in _mats:
		var mat: ShaderMaterial = m
		mat.set_shader_parameter("amb", amb)
		mat.set_shader_parameter("night", night)
		mat.set_shader_parameter("neon_gain", neon_gain)
		mat.set_shader_parameter("lg_origin", lg_origin)
		mat.set_shader_parameter("lg_inv_size", lg_inv)
		mat.set_shader_parameter("warm", warm)


## 영업 시간표: 이 시각에 손님이 차는 비율
static func busy_frac(busy: String, hr: float) -> float:
	match busy:
		"evening":
			if hr >= 17.0 or hr < 1.0:
				return 1.0
			if hr >= 10.0:
				return 0.45
			if hr < 2.5:
				return 0.4
			return 0.04
		"night":
			if hr >= 19.0 or hr < 4.0:
				return 1.0
			if hr >= 13.0:
				return 0.3
			return 0.04
		"always":
			return 0.85 if (hr >= 7.0 and hr < 22.0) else 0.5
	if hr >= 17.0 and hr < 19.0:
		return 1.0      # 저녁 장보기 붐빔
	if hr >= 8.0 and hr < 18.5:
		return 0.85
	if hr >= 18.5 and hr < 21.0:
		return 0.35
	if hr >= 6.5 and hr < 8.0:
		return 0.3
	return 0.03


func _visible_slot(s: Dictionary, bs: Dictionary, staff_rank: Dictionary, staff_n: Dictionary) -> bool:
	var z: int = int(s.get("z", 0))
	if _cut >= 0 and z > _cut:
		return false
	var out: bool = bool(s.get("out", false))
	var house := str(s.get("role", "")) == "resident"
	if out:
		if _zoom_i < 1:
			return false
	else:
		var cut_here := _cut >= 0 and z == _cut and _zoom_i >= int(cfg.r("interior.cut_actor_zoom", 2))
		if not (cut_here or (_inner and not house)):
			return false
	var bid := int(s.get("bid", -1))
	var b: Dictionary = bs.get(bid, {})
	if str(b.get("burn", "")) != "":
		return false
	if house:
		var night := _hour >= 22.5 or _hour < 6.5
		return (str(s.get("when", "day")) == "night") == night
	var role := str(s.get("role", "staff"))
	if role == "idle":
		return true
	if not bool(b.get("active", true)):
		return false
	var rec := cfg.look_recipe(str(s.get("look", "")))
	var bf := busy_frac(str(rec.get("busy", "day")), _hour)
	if role == "staff":
		if bf < 0.2 and str(rec.get("busy", "day")) != "always":
			return false
		var ratio := clampf(float(b.get("staff", 1.0)), 0.0, 1.0)
		var n: int = int(staff_n.get(bid, 1))
		var rank: int = int(staff_rank.get(int(s.get("i", 0)), 0))
		return (float(rank) + 0.5) / float(maxi(n, 1)) <= ratio + 0.001
	var rank: int = int(_guest_rank.get(int(s.get("i", 0)), 0))
	var occ: Array = occupants.get(bid, [])
	if rank < occ.size():
		return true   # 걸어 들어온 주민이 앉은 자리
	var h := ViewCfg.h2(int(s.get("i", 0)) * 13 + bid, 77) % 100
	return float(h) < bf * 100.0 * float(cfg.r("interior.ambient_guests", 0.55))


func _recompute() -> void:
	_dirty = false
	var bs: Dictionary = Game.state.buildings if Game.state != null else {}
	var staff_n: Dictionary = {}
	var staff_rank: Dictionary = {}
	var guest_n: Dictionary = {}
	_guest_rank = {}
	for s in slots:
		var bid := int(s.get("bid", -1))
		if str(s.get("role", "")) == "staff":
			staff_rank[int(s.get("i", 0))] = int(staff_n.get(bid, 0))
			staff_n[bid] = int(staff_n.get(bid, 0)) + 1
		elif str(s.get("role", "")) == "guest":
			_guest_rank[int(s.get("i", 0))] = int(guest_n.get(bid, 0))
			guest_n[bid] = int(guest_n.get(bid, 0)) + 1
	# 자리 시간이 끝난 손님은 일어난다(넘치는 손님도 — 자리 수만큼만 앉는다)
	for bid in occupants.keys():
		var keep_o: Array = []
		for o in occupants[bid]:
			if float(o["until"]) <= _t or keep_o.size() >= int(guest_n.get(bid, 0)):
				_leavers.append(o)
			else:
				keep_o.append(o)
		if keep_o.is_empty():
			occupants.erase(bid)
		else:
			occupants[bid] = keep_o
	var keep: Dictionary = {}
	for v in _vis:
		keep[v["key"]] = v
	_vis = []
	for s in slots + extra:
		if _vis.size() >= MAX_INST:
			break
		var is_extra: bool = s.has("t0")
		if not is_extra and not _visible_slot(s, bs, staff_rank, staff_n):
			continue
		if is_extra and _zoom_i < 1:
			continue
		var key: String = "%d:%d:%s" % [int(s.get("bid", -1)), int(s.get("i", 0)), str(s.get("pose", ""))]
		var oc: Dictionary = {}
		if str(s.get("role", "")) == "guest":
			var occl: Array = occupants.get(int(s.get("bid", -1)), [])
			var rk: int = int(_guest_rank.get(int(s.get("i", 0)), 99))
			if rk < occl.size():
				oc = occl[rk]
				key += ":o%d" % int(oc.get("hs", 0))
		if keep.has(key):
			_vis.append(keep[key])
			continue
		var hs := ViewCfg.h2(int(s.get("bid", 0)) * 31 + int(s.get("i", 0)), 5)
		var look := str(s.get("look", ""))
		var shirt := Color("#c9c2b4")
		var role := str(s.get("role", ""))
		if role == "staff" and UNIFORM.has(look):
			shirt = Color(UNIFORM[look])
		elif s.has("tier"):
			shirt = cfg.tier_color(int(s["tier"]), hs % 5)
		else:
			shirt = cfg.tier_color(1 + hs % 5, hs / 7 % 5)
		var prop := 0
		match str(s.get("prop", s.get("pose", ""))):
			"can":
				prop = 1
			"sack":
				prop = 2
			"stir":
				prop = 3
		var pal := (hs % 6) + ((hs / 6) % 8) * 8 + ((hs / 48) % 8) * 64 + prop * 512
		if not oc.is_empty():
			shirt = oc["shirt"]
			pal = int(oc["pal"]) + prop * 512
		_vis.append({"key": key, "hs": hs, "s": s, "shirt": shirt, "pal": pal, "phase": float(hs % 1000) / 1000.0, "acc": float((hs / 300) % 8) / 8.0})


func step(delta: float, hour: float) -> void:
	_t += delta
	if absf(hour - _hour) > 0.25:
		_hour = hour
		_dirty = true
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_dirty = true
	if _dirty:
		_recompute()
	_render()


func _render() -> void:
	var lod := lod_for(_zoom_i)
	for i in 4:
		(_mmi[i] as MultiMeshInstance3D).visible = i == lod
	var mm: MultiMesh = (_mmi[lod] as MultiMeshInstance3D).multimesh
	var mat: ShaderMaterial = _mats[lod]
	mat.set_shader_parameter("ppu", view.ppu())
	var basis: Basis = view._cam.global_transform.basis
	var n := mini(_vis.size(), MAX_INST)
	for i in n:
		var v: Dictionary = _vis[i]
		var s: Dictionary = v["s"]
		var pose := str(s.get("pose", "stand"))
		var pos: Vector3 = s["pos"]
		var dir: Vector3 = s.get("dir", Vector3(0, 0, 1))
		var ph: float = v["phase"]
		var anim := str(s.get("anim", ""))
		if anim == "hammer":
			pose = "hammer"
		elif pose == "swork" and str(s.get("role", "")) == "staff" and str(s.get("look", "")) in COOKS:
			pose = "cook"
		var hz: float = float(ANIM_HZ.get(anim, POSE_HZ.get(pose, 0.0)))
		var fr := 0
		# 쉬는 사람의 다양성: 서 있는 자리는 가끔 두리번·머리 긁기, 일손은 가끔 문밖에서 담배 한 대
		var idle_k := fposmod(_t / 40.0 + ph * 3.7, 1.0)
		if pose == "stand" and not s.has("t0"):
			if idle_k < 0.18:
				pose = "look"
			elif idle_k > 0.9:
				pose = "scratch"
		if str(s.get("role", "")) == "staff" and s.has("door") and idle_k > 0.86 and int(v.get("hs", 0)) % 3 == 0:
			pose = "smoke"
			pos = s["door"]
			dir = -dir
			hz = 0.45
		if hz > 0.0:
			fr = int(floor(_t * hz * 2.0 + ph * 7.0)) % 4
		elif pose in ["stand", "sit", "look"]:
			fr = 3 if fposmod(_t * 0.33 + ph * 5.0, 1.0) < 0.06 else 0
			if pose == "look":
				fr = int(floor(_t * 0.8 + ph * 5.0)) % 4
		if pose in MOVERS and not s.has("t0"):
			# 제자리에서 앞뒤로 오간다(나르기·심부름)
			var k := fposmod(_t * 0.18 + ph, 1.0)
			var tri := absf(k * 2.0 - 1.0) * 2.0 - 1.0
			pos = pos + dir * (tri * 0.22)
			if k < 0.5:
				dir = -dir
		if s.has("t0"):
			# 양동이 줄: 들고 건넨다(좌우를 번갈아 본다)
			if pose == "pass" and int(floor(_t * 1.6 + ph * 3.0)) % 2 == 1:
				dir = -dir
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(i, Color(v["shirt"].r, v["shirt"].g, v["shirt"].b, v["acc"]))
		var sx := dir.dot(basis.x)
		var sy := dir.dot(basis.y)
		var row := 0
		var flip := 0.0
		if absf(sx) > absf(sy) * 1.15:
			row = 1
			flip = 1.0 if sx < 0.0 else 0.0
		elif sy > 0.0:
			row = 2
		if pose == "lie" or pose == "bathe":
			row = 0
			flip = 1.0 if sx < 0.0 else 0.0
		var col := PeopleSprites.pose_index(pose) * PeopleSprites.FRAMES + fr
		var inside := 0.0 if bool(s.get("out", false)) else 4.0
		mm.set_instance_custom_data(i, Color(float(col), float(row), flip + inside, float(v["pal"])))
	mm.visible_instance_count = n


static func lod_for(zi: int) -> int:
	return 0 if zi <= 1 else (1 if zi == 2 else (2 if zi == 3 else 3))


func count() -> int:
	return _vis.size()
