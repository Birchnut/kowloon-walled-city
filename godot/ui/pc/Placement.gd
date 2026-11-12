class_name Placement
extends Node
## Placement — 도시 위에서 짓고 허무는 손(마우스·키보드). 그림은 뷰가, 판정은 시뮬(can)이 한다.
##  mode "zone"     : 주거 칠하기. 누르고 끌면 네모(Shift = 지나간 칸만). 바닥 하이라이트만(view.set_zone_preview). 떼면 zone.
##  mode "build"    : 시설. 마우스를 따라 발자국 전체(2개 층이면 두 층) 고스트 + 생길 골조 + 층마다 사각 범위 + 닿는 집 수 + 거절 이유.
##                    R = 돌리기(1×2). 왼쪽 클릭 = 짓기(배치 모드에 남는다). 오른쪽 클릭·Esc = 그만.
##  mode "demolish" : 누르면 demolish_preview 확인 창 → demolish.
##  mode "pick"     : 시설을 누르면 그 시설로 build.
## 작업 층: 층 고르기에서 고른 층. '전체'를 보고 있었으면 가장 위의 열린 층으로 바꿔 보여 주고, 끝나면 '전체'로 돌린다.

signal mode_changed(mode: String)

var ui: Node = null
var mode: String = ""
var item: Dictionary = {}           # build 중인 시설(build_menu 항목)
var rot: int = 0
var z: int = 0
var _restore_cut: int = -2
var _hover_cell: Variant = null     # Vector3i (작업 층 평면 위)
var _can: Dictionary = {}
var _range: Dictionary = {}
# 칠하기
var _painting := false
var _p0: Vector3i
var _stroke: Array = []
var _zone_cells: Array = []
var _zone_can: Dictionary = {}


func active() -> bool:
	return mode != ""


func start_zone() -> void:
	_enter("zone")
	item = ui.build.find("house")
	ui.toast("주거 칠하기 — 끌어서 네모로 칠한다. Shift는 지나간 칸만. 오른쪽 클릭 = 그만", "dim", "house")


func start_build(it: Dictionary) -> void:
	if it.is_empty():
		return
	if bool(it.get("locked", false)):
		ui.toast("아직 지을 수 없다 — %s" % str(it.get("lock_hint", "")), "warn", "lock")
		Sfx.play("place_fail")
		return
	if str(it.get("id", "")) == "house":
		start_zone()
		return
	var keep_rot := mode == "build" and str(item.get("id", "")) == str(it.get("id", ""))
	_enter("build")
	item = it
	if not keep_rot:
		rot = 0
	_update_hover()


func start_demolish() -> void:
	_enter("demolish")


func start_pick() -> void:
	_enter("pick")


func _enter(m: String) -> void:
	var was := mode
	if was != "" and was != m:
		_clear_preview()
	mode = m
	_painting = false
	if m in ["zone", "build"]:
		if _restore_cut == -2:
			var cur := _view_cut()
			_restore_cut = cur
			var top := int(ui.hud.get("floors_unlocked", 1)) - 1
			z = cur if cur >= 0 else maxi(top, 0)
		Q.vcall("show_floor_grid", [z, true])
		Q.vcall("set_drag_paint", [true])
	else:
		_leave_floor()
		Q.vcall("set_drag_paint", [m in ["demolish", "pick"]])
	ui.build.set_active({"zone": "house", "demolish": "demolish", "pick": "pick"}.get(m, str(item.get("id", "")) if m == "build" else ""))
	ui.inspector.deselect()
	mode_changed.emit(mode)


func cancel() -> void:
	if mode == "":
		return
	_clear_preview()
	_leave_floor()
	Q.vcall("set_drag_paint", [false])
	mode = ""
	item = {}
	_painting = false
	ui.build.set_active("")
	ui.tips.cursor_text = ""
	mode_changed.emit(mode)


func _leave_floor() -> void:
	if _restore_cut != -2:
		Q.vcall("show_floor_grid", [z, false])
		Q.vcall("set_floor_cut", [_restore_cut])
		_restore_cut = -2


func _view_cut() -> int:
	var v := Q.view()
	return int(v.get("floor_cut")) if v != null and v.get("floor_cut") != null else -1


func _clear_preview() -> void:
	Q.vcall("show_ghost", [[], true, [], 1])
	Q.vcall("set_zone_preview", [[], []])
	Q.vcall("show_cells", [[], "range"])
	Q.vcall("show_cells", [[], "warn"])
	Q.vcall("show_cells", [[], "valid"])
	ui.tips.cursor_text = ""


func rotate() -> void:
	if mode == "build" and bool(item.get("rotatable", false)):
		rot = 1 - rot
		Sfx.play("rotate")
		_update_hover()


## 층 고르기·PgUp/PgDn 으로 보는 층이 바뀌면 작업 층도 따라간다.
func _process(_d: float) -> void:
	if mode in ["zone", "build"]:
		var cut := _view_cut()
		if cut >= 0 and cut != z:
			z = cut
			Q.vcall("show_floor_grid", [z, true])
			_update_hover()


# ------------------------------------------------------------------ 마우스
var _mouse: Vector2 = Vector2.ZERO


func on_mouse_move(screen: Vector2) -> void:
	_mouse = screen
	match mode:
		"zone", "build":
			var r: Dictionary = UI.to_dict(Q.vcall("pick_floor", [screen, z], {}))
			var c: Variant = r.get("pos") if bool(r.get("ok", r.get("in_grid", false))) else null
			if c != _hover_cell:
				_hover_cell = c
				if mode == "zone" and _painting and c is Vector3i:
					_extend_paint(c)
				_update_hover()
		"demolish", "pick":
			var h: Dictionary = UI.to_dict(Q.vcall("hover", [screen], {}))
			var c2: Variant = h.get("pos") if bool(h.get("hit", false)) else null
			if c2 != _hover_cell:
				_hover_cell = c2
				_update_hover()


func _origin() -> Variant:
	if not (_hover_cell is Vector3i):
		return null
	var fp := _fp()
	var c: Vector3i = _hover_cell
	return Vector3i(c.x - (fp.x - 1) / 2, c.y - (fp.y - 1) / 2, z)


func _fp() -> Vector2i:
	var f := UI.to_array(item.get("footprint", [1, 1]))
	var w := int(f[0]) if f.size() > 0 else 1
	var h := int(f[1]) if f.size() > 1 else 1
	return Vector2i(h, w) if rot == 1 else Vector2i(w, h)


func _update_hover() -> void:
	match mode:
		"build":
			_preview_build()
		"zone":
			if not _painting:
				var cells: Array = [_hover_cell] if _hover_cell is Vector3i else []
				if cells.is_empty():
					Q.vcall("set_zone_preview", [[], []])
					ui.tips.cursor_text = ""
					return
				var cz := Q.can_full("zone", {"cells": cells})
				Q.vcall("set_zone_preview", [cells, [bool(cz.get("ok", false))]])
				_set_cursor("판잣집 %s · 눌러 끌어 칠한다" % UI.won(UI.to_dict(cz.get("cost", {})).get("money", UI.to_dict(item.get("cost", {})).get("money", 0))) if bool(cz.get("ok", false)) else str(cz.get("reason", "")), "" if bool(cz.get("ok", false)) else "bad")
		"demolish", "pick":
			if _hover_cell is Vector3i:
				var inf := Q.dict("info", {"pos": _hover_cell})
				var fp: Array = UI.to_array(inf.get("footprint", []))
				if fp.is_empty():
					fp = [_hover_cell]
				Q.vcall("show_cells", [fp, "warn" if mode == "demolish" else "select"])
				if mode == "demolish":
					_set_cursor("%s — 눌러 철거" % str(inf.get("title", "")), "warn")
				else:
					var ok := str(inf.get("kind", "")) == "facility"
					_set_cursor(("%s — 눌러 같은 것 짓기" % str(inf.get("title", ""))) if ok else "시설을 고른다", "" if ok else "dim")
			else:
				Q.vcall("show_cells", [[], "warn" if mode == "demolish" else "select"])
				ui.tips.cursor_text = ""


func _set_cursor(t: String, tone: String) -> void:
	ui.tips.cursor_tone = tone
	ui.tips.cursor_text = t


func _preview_build() -> void:
	var o: Variant = _origin()
	if not (o is Vector3i):
		Q.vcall("show_ghost", [[], true, [], 1])
		Q.vcall("show_cells", [[], "range"])
		ui.tips.cursor_text = ""
		return
	var id := str(item.get("id", ""))
	_can = Q.can_full("build", {"type": id, "pos": o, "rot": rot})
	var cells: Array = UI.to_array(_can.get("cells", []))
	if cells.is_empty():
		cells = [o]
	var sup: Array = UI.to_array(_can.get("supports", _can.get("support_cells", [])))
	if not (sup.is_empty() or sup[0] is Vector3i):
		sup = UI.to_array(_can.get("support_cells", []))
	var ok := bool(_can.get("ok", false))
	var code := str(_can.get("code", ""))
	# 돈·물건이 모자라도 자리는 맞다 → 고스트는 초록 테두리, 막대에 이유
	var place_ok := ok or code in ["money", "goods"]
	Q.vcall("show_ghost", [cells, place_ok, sup, maxi(1, int(item.get("floors", 1)))])
	_range = {}
	if item.get("range") is Dictionary:
		_range = Q.dict("range_preview", {"type": id, "pos": o, "rot": rot})
		Q.vcall("show_cells", [UI.to_array(_range.get("cells", [])), "range"])
	else:
		Q.vcall("show_cells", [[], "range"])
	var line := "%s · %s" % [str(item.get("name", "")), ui.build.cost_text(item)]
	if not _range.is_empty():
		line += " · " + str(_range.get("text", "범위 안 주거 %d채" % int(_range.get("houses", 0))))
	if sup.size() > 0:
		line += " · 골조 %d" % sup.size()
	if bool(item.get("rotatable", false)):
		line += " · R 돌리기"
	if not ok:
		line = str(_can.get("reason", "놓을 수 없다")) + ("\n" + line if code in ["money", "goods"] else "")
	_set_cursor(line, "" if ok else ("warn" if place_ok else "bad"))


## 뷰의 cell_dragged: 칠하기·배치 모드에서 왼쪽 누름(first)과 끌기.
func on_cell_dragged(info: Dictionary) -> void:
	var first := bool(info.get("first", false))
	match mode:
		"zone":
			var c: Variant = info.get("pos")
			if not (c is Vector3i) or not bool(info.get("ok", info.get("in_grid", true))):
				if first:
					Sfx.play("place_fail")
				return
			if first:
				_painting = true
				_p0 = c
				_stroke = [c]
				_hover_cell = c
				_extend_paint(c)
			elif _painting:
				_hover_cell = c
				_extend_paint(c)
		"build":
			if first:
				commit_build()
		"demolish":
			if first:
				var h: Dictionary = UI.to_dict(Q.vcall("hover", [_mouse], {}))
				if bool(h.get("hit", false)):
					confirm_demolish(h.get("pos"))
		"pick":
			if first:
				var h2: Dictionary = UI.to_dict(Q.vcall("hover", [_mouse], {}))
				if bool(h2.get("hit", false)):
					pick_at(h2.get("pos"))


func _extend_paint(c: Vector3i) -> void:
	if not (c in _stroke):
		_stroke.append(c)
	var cells: Array = []
	if Input.is_key_pressed(KEY_SHIFT):
		cells = _stroke.duplicate()
	else:
		for x in range(mini(_p0.x, c.x), maxi(_p0.x, c.x) + 1):
			for y in range(mini(_p0.y, c.y), maxi(_p0.y, c.y) + 1):
				cells.append(Vector3i(x, y, z))
	_zone_cells = cells
	_zone_can = Q.can_full("zone", {"cells": cells})
	var bad := {}
	for s: Variant in UI.to_array(_zone_can.get("skipped", [])):
		var p: Variant = UI.to_dict(s).get("pos")
		if p is Vector3i:
			bad[p] = str(UI.to_dict(s).get("reason", ""))
	var oks: Array = []
	for cc: Vector3i in cells:
		oks.append(not bad.has(cc))
	Q.vcall("set_zone_preview", [cells, oks])
	var n := int(_zone_can.get("built", cells.size() - bad.size()))
	var line := "판잣집 %d채 · %s" % [n, UI.won(UI.to_dict(_zone_can.get("cost", {})).get("money", 0))]
	if not bad.is_empty():
		line += " · 못 짓는 칸 %d(%s)" % [bad.size(), str(bad.values()[0])]
	_set_cursor(line, "" if n > 0 else "bad")


## 왼쪽 버튼을 뗐다(UIRoot._input 이 알려 준다).
func on_left_release() -> void:
	if mode != "zone" or not _painting:
		return
	_painting = false
	var cells := _zone_cells.duplicate()
	_zone_cells = []
	_stroke = []
	Q.vcall("set_zone_preview", [[], []])
	if cells.is_empty():
		return
	var r: Dictionary = ui.cmd("zone", {"cells": cells})
	if bool(r.get("ok", false)):
		Sfx.play("zone")
		var sk := UI.to_array(r.get("skipped", []))
		ui.toast("판잣집 %d채%s" % [int(r.get("built", cells.size())), (" — %d칸은 못 지었다" % sk.size()) if not sk.is_empty() else ""], "good", "house")
	else:
		Sfx.play("place_fail")
		ui.toast(str(r.get("reason", "칠할 수 없다.")), "bad")
	_update_hover()


func commit_build() -> void:
	var o: Variant = _origin()
	if not (o is Vector3i):
		return
	var id := str(item.get("id", ""))
	var r: Dictionary = ui.cmd("build", {"type": id, "pos": o, "rot": rot})
	if bool(r.get("ok", false)):
		Sfx.play("build")
		var bd := float(item.get("build_days", 0.0))
		ui.toast("%s 공사 시작%s" % [str(item.get("name", "")), (" — %s" % UI.days(bd)) if bd > 0.0 else ""], "good", UI.cat_picto(ui.build.cat_of(id)))
		item = ui.build.find(id)     # 비용·잠김이 바뀌었을 수 있다
	else:
		Sfx.play("place_fail")
		ui.toast(str(r.get("reason", "놓을 수 없다.")), "bad")
	_update_hover()


func confirm_demolish(pos: Variant) -> void:
	if not (pos is Vector3i):
		return
	var pv := Q.dict("demolish_preview", {"pos": pos})
	var inf := Q.dict("info", {"pos": pos})
	var title := str(pv.get("title", inf.get("title", "")))
	if title == "":
		return
	var lines := UI.to_array(pv.get("lines", []))
	if lines.is_empty():
		lines = ["되돌릴 수 없다."]
	ui.confirm({"kicker": "철거", "title": "%s 허문다" % UI.josa(title, "를", "을"), "lines": lines, "ok_text": "허문다", "danger": true}, func() -> void:
		var r: Dictionary = ui.cmd("demolish", {"pos": pos})
		if bool(r.get("ok", false)):
			Sfx.play("demolish")
			ui.inspector.deselect()
		else:
			ui.toast(str(r.get("reason", "")), "bad")
		_update_hover())


func pick_at(pos: Variant) -> void:
	if not (pos is Vector3i):
		return
	var inf := Q.dict("info", {"pos": pos})
	var t := str(inf.get("type", ""))
	if str(inf.get("kind", "")) == "house":
		start_zone()
		return
	if t == "" or str(inf.get("kind", "")) not in ["facility", "site"]:
		ui.toast("따라 지을 시설이 아니다.", "dim")
		return
	var it: Dictionary = ui.build.find(t)
	if not it.is_empty():
		ui.build.select_cat(ui.build.cat_of(t))
		start_build(it)
		rot = int(inf.get("rot", 0))
