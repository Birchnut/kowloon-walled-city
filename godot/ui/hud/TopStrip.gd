class_name TopStrip
extends PanelContainer
## TopStrip — 상단 띠(화면 높이 13% 이하). 데이터는 query("hud") 하나.
##  1줄: 시계 원판 · 등급·호칭 / 날짜·시각 ……… 돈(+일 수지) · 총인구 · 행복 얼굴
##  2줄: 계층 칩(있는 계층만, 인원) ……… 물·전기 눈금(공급 vs 수요, 모자라면 빨강)
##  3줄: 알림 한 줄(hud.alerts 를 돌려 가며, 없으면 다음 목표). 누르면 그 알림의 jump 로.
## 누르는 곳: 돈 → 경제/장부, 계층 칩 → 경제/노동력, 물·전기 → 경제/물·전기, 알림 → jump.

signal jump(target: Dictionary)

const ALERT_SEC := 4.0

var dial: TimeDial
var money: IconLabel
var _net: Label
var _grade: Label
var _day: Label
var _pop: Label
var _face: HappyFace
var _tiers: HBoxContainer
var _water: UtilPip
var _power: UtilPip
var _alert_row: Control
var _alert_bar: ColorRect
var _alert: Label
var _safe: Control
var _alerts: Array = []
var _goal: Dictionary = {}
var _alert_i: int = 0
var _alert_t: float = 0.0
var _last_day: int = -1
var _tier_sig: String = ""


func _init() -> void:
	theme_type_variation = "PanelStrip"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(0)
	add_child(v)
	_safe = UI.spacer(false, Vector2(0, 0))
	v.add_child(_safe)

	# ── 1줄 ──
	var a := UI.margin(6, 2, 8, 0)
	v.add_child(a)
	var row := UI.hbox(8)
	a.add_child(row)
	dial = TimeDial.new()
	row.add_child(dial)
	var dc := UI.vbox(-4)
	dc.alignment = BoxContainer.ALIGNMENT_CENTER
	dc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dc)
	_grade = UI.label("공터 · 대장", "LabelGoldSmall")
	_grade.clip_text = true
	_grade.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dc.add_child(_grade)
	_day = UI.label("1일 06:00", "LabelDim")
	dc.add_child(_day)
	var mc := UI.vbox(-4)
	mc.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(mc)
	money = IconLabel.make("coin", "LabelGold")
	mc.add_child(money)
	_net = UI.label("+0/일", "LabelSmall")
	_net.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mc.add_child(_net)
	_tap(mc, func() -> void: jump.emit({"screen": "economy", "arg": "finance"}))
	var pc := UI.hbox(2)
	row.add_child(pc)
	pc.add_child(UI.icon_rect("pop"))
	_pop = UI.label("0", "LabelBold")
	pc.add_child(_pop)
	_tap(pc, func() -> void: jump.emit({"screen": "economy", "arg": "labor"}))
	_face = HappyFace.new()
	row.add_child(_face)
	_tap(_face, func() -> void: jump.emit({"screen": "keep", "arg": "goals"}))

	# ── 2줄 ──
	var b := UI.margin(8, 2, 8, 0)
	v.add_child(b)
	var r2 := UI.hbox(6)
	b.add_child(r2)
	# 계층 칩은 폭이 모자라면 잘린다(띠 전체 폭을 밀어내지 않게 최소 폭 0인 그릇에 담는다)
	var holder := Control.new()
	holder.clip_contents = true
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(0, 30)
	r2.add_child(holder)
	_tiers = UI.hbox(4)
	holder.add_child(_tiers)
	holder.resized.connect(func() -> void: _tiers.size = Vector2(maxf(_tiers.get_combined_minimum_size().x, holder.size.x), holder.size.y))
	_tiers.minimum_size_changed.connect(func() -> void: _tiers.size = Vector2(maxf(_tiers.get_combined_minimum_size().x, holder.size.x), holder.size.y))
	_tap(holder, func() -> void: jump.emit({"screen": "economy", "arg": "labor"}))
	_water = UtilPip.make("水")
	_power = UtilPip.make("電")
	r2.add_child(_water)
	r2.add_child(_power)
	_tap(_water, func() -> void: jump.emit({"screen": "economy", "arg": "utilities"}))
	_tap(_power, func() -> void: jump.emit({"screen": "economy", "arg": "utilities"}))

	# ── 3줄: 알림 ──
	var c := UI.margin(8, 2, 8, 4)
	v.add_child(c)
	var r3 := UI.hbox(6)
	c.add_child(r3)
	_alert_row = r3
	_alert_bar = ColorRect.new()
	_alert_bar.custom_minimum_size = Vector2(4, 20)
	_alert_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r3.add_child(_alert_bar)
	_alert = UI.label("", "LabelSmall")
	_alert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alert.clip_text = true
	_alert.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	r3.add_child(_alert)
	r3.add_child(UI.icon_rect("chev_r", UI.col("mute")))
	_tap(r3, _on_alert_tap)


func _ready() -> void:
	set_process(true)


## 탭(눌렀다 거의 안 움직이고 뗌) → cb. 끌기와 구분한다.
func _tap(ctrl: Control, cb: Callable) -> void:
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := {"p": Vector2.ZERO, "down": false}
	ctrl.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				st["down"] = true
				st["p"] = ev.global_position
			elif st["down"]:
				st["down"] = false
				if ev.global_position.distance_to(st["p"]) < 14.0:
					cb.call()
			ctrl.accept_event())


func set_safe_top(px: float) -> void:
	_safe.custom_minimum_size.y = px


func set_time(tod: float) -> void:
	dial.tod = tod


## hud = query("hud") 결과(빈 Dictionary 여도 된다).
func refresh(hud: Dictionary) -> void:
	var day := int(hud.get("day", 1))
	if _last_day >= 0 and day != _last_day:
		_pulse(_day)
	_last_day = day
	_day.text = "%d일 · %s" % [day, UI.clock(float(hud.get("hour", 0.0)))]
	var gn := str(hud.get("grade_name", ""))
	var title := str(hud.get("title", "대장"))
	_grade.text = ("%s · %s" % [gn, title]) if gn != "" else title
	money.set_value(float(hud.get("money", 0.0)))
	var net := float(hud.get("net_per_day", 0.0))
	_net.text = "%s%s/일" % ["+" if net >= 0.0 else "-", UI.num(absf(net))]
	_net.add_theme_color_override("font_color", UI.col("jade_hi") if net >= 0.0 else UI.col("red_hi"))
	_pop.text = UI.num(float(hud.get("pop_total", 0)))
	_face.set_value(float(hud.get("happiness", 50.0)))
	for l: Variant in UI.to_array(hud.get("labor", [])):
		if l is Dictionary and str(l.get("name", "")) != "":
			_names_cache[int(l.get("tier", 0))] = str(l["name"])
	_refresh_tiers(UI.to_dict(hud.get("pop", {})))
	var w := UI.to_dict(hud.get("water", {}))
	var p := UI.to_dict(hud.get("power", {}))
	_water.set_values(float(w.get("supply", 0.0)), float(w.get("demand", 0.0)))
	_power.set_values(float(p.get("supply", 0.0)), float(p.get("demand", 0.0)))
	_alerts = UI.to_array(hud.get("alerts", []))
	_goal = UI.to_dict(hud.get("next_goal", {}))
	if _alert_i >= _alerts.size():
		_alert_i = 0
	_show_alert()


func _refresh_tiers(pop: Dictionary) -> void:
	var names := _tier_names()
	var rows: Array = []
	for t: int in range(1, 6):
		var n := int(pop.get("t%d" % t, 0))
		if n > 0:
			rows.append([t, n])
	var short := rows.size() > 3
	var sig := str(rows) + str(short)
	if sig == _tier_sig:
		return
	_tier_sig = sig
	for ch in _tiers.get_children():
		_tiers.remove_child(ch)
		ch.queue_free()
	if rows.is_empty():
		_tiers.add_child(UI.label("아직 아무도 안 산다", "LabelMute"))
		return
	for r: Array in rows:
		var nm: String = names.get(r[0], "t%d" % r[0])
		_tiers.add_child(TierChip.make(int(r[0]), nm.substr(0, 1) if short else nm, int(r[1])))


## 계층 이름표(경제 질의의 tiers 에서 한 번 읽어 둔다).
static var _names_cache: Dictionary = {}
static func _tier_names() -> Dictionary:
	if _names_cache.is_empty():
		for row: Variant in UI.to_array(Q.dict("economy").get("tiers", [])):
			if row is Dictionary:
				_names_cache[int(row.get("tier", 0))] = str(row.get("name", ""))
	if _names_cache.is_empty():
		return {1: "떠돌이", 2: "세입자", 3: "토박이", 4: "유지", 5: "거물"}
	return _names_cache


func _process(delta: float) -> void:
	_alert_t += delta
	if _alert_t >= ALERT_SEC and _alerts.size() > 1:
		_alert_t = 0.0
		_alert_i = (_alert_i + 1) % _alerts.size()
		_show_alert()


func _show_alert() -> void:
	var text := ""
	var tone := ""
	if not _alerts.is_empty():
		var a := UI.to_dict(_alerts[_alert_i])
		text = str(a.get("text", ""))
		tone = str(a.get("tone", ""))
		if _alerts.size() > 1:
			text = "%s  (%d/%d)" % [text, _alert_i + 1, _alerts.size()]
	elif str(_goal.get("text", "")) != "":
		text = "다음: %s · %d%%" % [str(_goal["text"]), int(float(_goal.get("progress", 0.0)) * 100.0)]
		tone = "dim"
	else:
		text = "별일 없다."
		tone = "dim"
	if _alert.text != text:
		_alert.text = text
	var c := UI.tone_col(tone) if tone != "" else UI.col("paper")
	_alert.add_theme_color_override("font_color", c)
	_alert_bar.color = c


func _on_alert_tap() -> void:
	if not _alerts.is_empty():
		var a := UI.to_dict(_alerts[_alert_i])
		jump.emit(Q.norm_jump(a.get("jump", {})))
	else:
		jump.emit({"screen": "keep", "arg": "goals"})


## 알림 줄의 화면 영역(튜토리얼 강조용).
func alert_rect() -> Rect2:
	return _alert_row.get_global_rect()


func money_rect() -> Rect2:
	return money.get_global_rect()


func _pulse(n: Control) -> void:
	var tw := n.create_tween()
	tw.tween_property(n, "modulate", Color(2, 2, 2), 0.1)
	tw.tween_property(n, "modulate", Color.WHITE, 0.6)


# ------------------------------------------------------------------ 작은 부품
## 계층 칩: 계층색 점 + 이름 + 인원.
class TierChip extends PanelContainer:
	static func make(t: int, nm: String, n: int) -> TierChip:
		var c := TierChip.new()
		c.theme_type_variation = "PanelTag"
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UI.hbox(4)
		c.add_child(h)
		var dot := ColorRect.new()
		dot.color = TierChip.tier_col(t)
		dot.custom_minimum_size = Vector2(6, 6)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(dot)
		h.add_child(UI.label(nm, "LabelSmall"))
		h.add_child(UI.label(UI.num(n), "LabelGoldSmall"))
		return c

	static func tier_col(t: int) -> Color:
		match t:
			1: return UI.col("paper3")
			2: return UI.col("jade")
			3: return UI.col("gold")
			4: return UI.col("red_hi")
			5: return UI.col("paper_hi")
		return UI.col("dim")


## 물·전기 눈금: 간판 글자 + 공급/수요 막대. 모자라면 빨강·깜빡.
class UtilPip extends HBoxContainer:
	var glyph: Label
	var bar: RatioBar
	var _short := false
	var _t := 0.0

	static func make(g: String) -> UtilPip:
		var u := UtilPip.new()
		u.add_theme_constant_override("separation", 2)
		u.glyph = UI.label(g, "LabelSmall")
		u.add_child(u.glyph)
		u.bar = RatioBar.make(0.0, "off", 12)
		u.bar.custom_minimum_size = Vector2(40, 16)
		u.bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		u.add_child(u.bar)
		return u

	func set_values(supply: float, demand: float) -> void:
		_short = demand > supply + 0.01
		if demand <= 0.0 and supply <= 0.0:
			bar.set_ratio(0.0, "off")
		elif _short:
			bar.set_ratio(supply / maxf(demand, 0.01), "bad")
		else:
			bar.set_ratio(1.0 if demand <= 0.0 else clampf(demand / maxf(supply, 0.01), 0.15, 1.0), "ok")
		glyph.add_theme_color_override("font_color", UI.col("red_hi") if _short else UI.col("paper"))
		set_process(_short)
		if not _short:
			glyph.modulate = Color.WHITE

	func _process(d: float) -> void:
		_t += d
		glyph.modulate = Color.WHITE if fmod(_t, 0.8) < 0.5 else Color(1, 1, 1, 0.35)


## 행복 얼굴(픽셀): 값에 따라 입 모양·색.
class HappyFace extends Control:
	var value := 50.0

	func _init() -> void:
		custom_minimum_size = Vector2(28, 28)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_value(v: float) -> void:
		if absf(v - value) > 0.4:
			value = v
			queue_redraw()

	func _draw() -> void:
		var c := UI.col("jade") if value >= 65.0 else (UI.col("gold") if value >= 40.0 else UI.col("red_hi"))
		var o := Vector2(2, 2)
		var px := 2.0
		# 12×12 원(2px 도트)
		var rows := ["....####....", "..########..", ".##########.", ".##########.", "############", "############",
			"############", "############", ".##########.", ".##########.", "..########..", "....####...."]
		for y in rows.size():
			for x in 12:
				if rows[y][x] == "#":
					draw_rect(Rect2(o + Vector2(x, y) * px, Vector2(px, px)), c)
		var ink := UI.col("ink0")
		draw_rect(Rect2(o + Vector2(3, 4) * px, Vector2(px, px * 2)), ink)
		draw_rect(Rect2(o + Vector2(8, 4) * px, Vector2(px, px * 2)), ink)
		if value >= 65.0:
			for p in [Vector2(3, 8), Vector2(4, 9), Vector2(5, 9), Vector2(6, 9), Vector2(7, 9), Vector2(8, 8)]:
				draw_rect(Rect2(o + p * px, Vector2(px, px)), ink)
		elif value >= 40.0:
			draw_rect(Rect2(o + Vector2(4, 9) * px, Vector2(px * 4, px)), ink)
		else:
			for p in [Vector2(3, 10), Vector2(4, 9), Vector2(5, 9), Vector2(6, 9), Vector2(7, 9), Vector2(8, 10)]:
				draw_rect(Rect2(o + p * px, Vector2(px, px)), ink)
