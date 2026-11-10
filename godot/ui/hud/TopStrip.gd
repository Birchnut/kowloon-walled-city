class_name TopStrip
extends PanelContainer
## TopStrip — 상단 띠. 날짜·시계, 돈/식량/자재/인구(변화량 번쩍), 위신·악명·민심, 별명 한 줄.
## 띠 어디를 눌러도 pressed 가 나간다(→ 기록). 데이터는 query("hud") 하나.

signal pressed

var dial: TimeDial
var money: IconLabel
var food: IconLabel
var mat: IconLabel
var pop: IconLabel
var _day: Label
var _clock: Label
var _m_prestige: Meter
var _m_notoriety: Meter
var _m_morale: Meter
var _epithet: Label
var _hit: Button
var _last_day: int = -1
var _safe: Control


func _init() -> void:
	theme_type_variation = "PanelStrip"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(2)
	add_child(v)
	_safe = UI.spacer(false, Vector2(0, 0))
	v.add_child(_safe)

	# ── 1줄: 시계 + 재고 ──
	var a := UI.margin(8, 4, 8, 0)
	v.add_child(a)
	var row := UI.hbox(10)
	a.add_child(row)
	dial = TimeDial.new()
	row.add_child(dial)
	var dc := UI.vbox(-2)
	dc.alignment = BoxContainer.ALIGNMENT_CENTER
	dc.custom_minimum_size = Vector2(66, 0)
	row.add_child(dc)
	_day = UI.label("1일차", "LabelGoldSmall")
	dc.add_child(_day)
	_clock = UI.label("06:00", "LabelDim")
	dc.add_child(_clock)
	row.add_child(UI.spacer(true))
	money = IconLabel.make("coin", "LabelGold")
	food = IconLabel.make("food", "LabelBold")
	mat = IconLabel.make("mat", "LabelBold")
	pop = IconLabel.make("pop", "LabelBold")
	pop.show_delta = false
	for il in [money, food, mat, pop]:
		row.add_child(il)

	# ── 2줄: 지표 ──
	var b := UI.margin(10, 0, 10, 0)
	v.add_child(b)
	var meters := UI.hbox(14)
	b.add_child(meters)
	_m_prestige = _meter("위신", "gold")
	_m_notoriety = _meter("악명", "red")
	_m_morale = _meter("민심", "jade")
	for m in [_m_prestige, _m_notoriety, _m_morale]:
		meters.add_child(m)

	# ── 3줄: 별명 ──
	var c := UI.margin(10, 0, 8, 2)
	v.add_child(c)
	var er := UI.hbox(6)
	c.add_child(er)
	er.add_child(UI.icon_rect("diamond", UI.col("red")))
	_epithet = UI.label("", "LabelSmall")
	_epithet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_epithet.clip_text = true
	_epithet.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	er.add_child(_epithet)
	er.add_child(UI.label("기록", "LabelMute"))
	er.add_child(UI.icon_rect("chev_r", UI.col("mute")))

	_hit = Button.new()
	_hit.theme_type_variation = "ButtonFlat"
	_hit.focus_mode = Control.FOCUS_NONE
	_hit.pressed.connect(func() -> void: pressed.emit())
	add_child(_hit)


func _meter(cap: String, tone: String) -> Meter:
	var m := Meter.new()
	m.caption = cap
	m.tone = tone
	return m


func set_safe_top(px: float) -> void:
	_safe.custom_minimum_size.y = px


## hud = query("hud") 결과(빈 Dictionary 여도 된다).
func refresh(hud: Dictionary) -> void:
	var day := int(hud.get("day", 1))
	_day.text = "%d일차" % day
	if _last_day >= 0 and day != _last_day:
		_pulse_day()
	_last_day = day
	_clock.text = UI.clock(float(hud.get("hour", 0.0)))
	money.set_value(float(hud.get("money", 0.0)))
	food.set_value(float(hud.get("food", 0.0)))
	mat.set_value(float(hud.get("materials", 0.0)))
	pop.set_value(float(hud.get("population", 0)))
	_m_prestige.set_value(float(hud.get("prestige", 0.0)))
	_m_notoriety.set_value(float(hud.get("notoriety", 0.0)))
	_m_morale.set_value(float(hud.get("morale", 0.0)))
	var title := str(hud.get("title", "대장"))
	var ep := str(hud.get("epithet", ""))
	var line := ("%s · %s" % [ep, title]) if ep != "" else ("아직 이름 없는 땅 · %s" % title)
	if _epithet.text != line:
		_epithet.text = line


func set_time(tod: float) -> void:
	dial.tod = tod


func _pulse_day() -> void:
	_day.pivot_offset = _day.size * 0.5
	var tw := _day.create_tween()
	tw.tween_property(_day, "modulate", Color(2, 2, 2), 0.1)
	tw.tween_property(_day, "modulate", Color.WHITE, 0.6)
