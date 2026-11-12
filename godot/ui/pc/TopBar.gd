class_name TopBar
extends PanelContainer
## 위 띠(1080p에서 높이 52). 왼쪽부터: 돈·순수입 | 계층 다섯 칩 | 행복 | 신호등 일곱 | (빈칸) | 날짜·시각 | 배속 | 창 버튼.
## 읽는 것: hud(0.25초) — money, net_per_day, pop{t1..}, labor[{tier,name}](계층 이름), happiness, signals[], day, hour, speed, paused.
## 모든 칸은 올리면 설명, 누르면 그 자리(jump)로 간다.

signal jump(target: Variant)
signal speed_pressed(speed: float, paused: bool)
signal window_pressed(id: String)

const WINDOWS := [
	["metrics", "현황판", "metrics", "Tab"], ["economy", "경제", "economy", "F2"], ["trade", "교역", "trade", "F3"],
	["expedition", "탐험", "expedition", "F4"], ["keep", "성채", "keep", "F6"], ["help", "도움말", "help", "F1"],
]

var _money: Label
var _net: Label
var _money_btn: Button
var _tier_box: HBoxContainer
var _tiers: Dictionary = {}       # tier -> {btn, lab}
var _happy_pic: Picto
var _happy: Label
var _sig_box: HBoxContainer
var _sigs: Dictionary = {}        # id -> {btn, pic, bar}
var _date: Label
var _clock: Label
var _tod: Picto
var _speed_btns: Dictionary = {}  # key -> PcButton
var win_btns: Dictionary = {}
var compact: int = 0          # 0 = 다 보임, 1 = 계층 이름 빼기, 2 = 순수입·날짜도 줄이기
var _hud: Dictionary = {}


func _init() -> void:
	theme_type_variation = "PanelBar"
	mouse_filter = Control.MOUSE_FILTER_STOP


var _row: HBoxContainer


func _ready() -> void:
	var row := UI.hbox(10)
	_row = row
	add_child(row)
	# ── 돈 ──
	_money_btn = _flat_btn()
	var mb := UI.hbox(6)
	_money_btn.add_child(mb)
	mb.add_child(Picto.make("coin", UI.col("gold")))
	_money = UI.label("₩0", "LabelGold")
	mb.add_child(_money)
	_net = UI.label("", "LabelSmall")
	mb.add_child(_net)
	_money_btn.pressed.connect(func() -> void: jump.emit({"screen": "economy", "arg": "finance"}))
	TipLayer.set_tip(_money_btn, func() -> String: return "금고\n지금 %s. 하루 순수입 %s(최근 며칠 평균).\n누르면 경제 › 장부." % [UI.won(_hud.get("money", 0)), UI.won_signed(_hud.get("net_per_day", 0))])
	row.add_child(_money_btn)
	row.add_child(VSeparator.new())
	# ── 계층 ──
	_tier_box = UI.hbox(4)
	row.add_child(_tier_box)
	for t in range(1, 6):
		var b := _flat_btn()
		var hb := UI.hbox(4)
		b.add_child(hb)
		var dot := Picto.make("pop", UI.tier_col(t))
		hb.add_child(dot)
		var lab := UI.label("", "LabelSmall")
		hb.add_child(lab)
		b.pressed.connect(func() -> void: jump.emit({"screen": "metrics", "arg": "tiers"}))
		var tt := t
		TipLayer.set_tip(b, func() -> String: return _tier_tip(tt))
		_tier_box.add_child(b)
		_tiers[t] = {"btn": b, "lab": lab}
	# ── 행복 ──
	var hbtn := _flat_btn()
	var hh := UI.hbox(4)
	hbtn.add_child(hh)
	_happy_pic = Picto.make("smile", UI.col("jade_hi"))
	hh.add_child(_happy_pic)
	_happy = UI.label("", "LabelBold")
	hh.add_child(_happy)
	hbtn.pressed.connect(func() -> void: jump.emit({"screen": "lens", "arg": "happiness"}))
	TipLayer.set_tip(hbtn, func() -> String: return "행복도 %d\n도시 평균. 높을수록 주민이 빨리 들어오고 오래 산다.\n누르면 행복 렌즈(집마다 색)." % int(float(_hud.get("happiness", 0))))
	row.add_child(hbtn)
	row.add_child(VSeparator.new())
	# ── 신호등 ──
	_sig_box = UI.hbox(2)
	row.add_child(_sig_box)
	for id: String in ["water", "power", "food", "fun", "fire", "disease", "labor"]:
		_add_signal(id)
	row.add_child(UI.spacer(true))
	# ── 날짜·시각 ──
	var dbtn := _flat_btn()
	var dh := UI.hbox(6)
	dbtn.add_child(dh)
	_tod = Picto.make("clock", UI.col("paper2"))
	dh.add_child(_tod)
	_date = UI.label("", "LabelSmall")
	dh.add_child(_date)
	_clock = UI.label("", "LabelBold")
	dh.add_child(_clock)
	TipLayer.set_tip(dbtn, func() -> String: return "%d일째 %s\n하루는 ×1에서 10분. 멈춘 채로도 짓고 볼 수 있다." % [int(_hud.get("day", 1)), UI.clock(float(_hud.get("hour", 0.0)))])
	row.add_child(dbtn)
	# ── 배속 ──
	var sp := UI.hbox(2)
	row.add_child(sp)
	for s: Array in [["pause", "", "Space", -1.0], ["x1", "×1", "1", 1.0], ["x2", "×2", "2", 2.0], ["x4", "×4", "3", 4.0]]:
		var b2 := PcButton.make(s[1], "pause" if s[0] == "pause" else ("play" if s[0] == "x1" else "ff"), "", "ButtonToggle")
		b2.toggle_mode = true
		b2.min_h = 36
		b2.min_w = 44
		var spd: float = s[3]
		b2.pressed.connect(func() -> void:
			if spd < 0.0:
				speed_pressed.emit(Game.speed, not Game.paused)
			else:
				speed_pressed.emit(spd, false))
		var tipk: String = s[2]
		TipLayer.set_tip(b2, ("멈춤 [Space]\n멈춘 채로도 짓고, 창을 보고, 승급할 수 있다." if spd < 0.0 else "배속 %s [%s]\n하루가 %s분." % [s[1], tipk, UI.dec(10.0 / spd)]))
		sp.add_child(b2)
		_speed_btns[s[0]] = b2


static func win_tip(id: String, key: String) -> String:
	match id:
		"metrics":
			return "현황판 [%s]\n모든 수급을 한 표로: 물·전기·먹을 것·물건·서비스·불과 병. 무엇이 모자라고 무엇을 하면 되는지." % key
		"economy":
			return "경제 [%s]\n상품 재고와 흐름, 일손, 장부." % key
		"trade":
			return "교역 [%s]\n거래처와 계약. 정해진 시각마다 사고판다." % key
		"expedition":
			return "탐험 [%s]\n자재를 구하러 사람을 보낸다. 직접 줍기(준비 중)." % key
		"keep":
			return "성채 [%s]\n목표·정책·연구·기록·설정." % key
		"help":
			return "조작 도움말 [%s]\n마우스·키보드 조작 전부." % key
	return ""


func _flat_btn() -> Button:
	var b := Button.new()
	b.theme_type_variation = "ButtonFlat"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 40)
	# 자식 상자 크기에 맞춘다
	b.child_entered_tree.connect(func(c: Node) -> void:
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			(c as Control).resized.connect(func() -> void: _fit_flat(b))
			_fit_flat.call_deferred(b))
	return b


func _fit_flat(b: Button) -> void:
	if b.get_child_count() == 0:
		return
	var c: Control = b.get_child(0)
	var m := c.get_combined_minimum_size()
	b.custom_minimum_size = Vector2(m.x + 12, maxf(40, m.y + 4))
	c.position = Vector2(6, (b.size.y - m.y) * 0.5).floor()
	c.size = m


func _add_signal(id: String) -> void:
	var b := _flat_btn()
	b.custom_minimum_size = Vector2(40, 40)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	b.add_child(v)
	var pic := Picto.make(UI.signal_picto(id), UI.col("mute"))
	v.add_child(pic)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(24, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(bar)
	var sid := id
	b.pressed.connect(func() -> void:
		var s := _signal(sid)
		if not s.is_empty():
			jump.emit(s.get("jump", {})))
	TipLayer.set_tip(b, func() -> String:
		var s := _signal(sid)
		var st := str(s.get("state", "off"))
		var word: String = {"ok": "좋음", "warn": "주의", "bad": "위험", "off": "꺼짐"}.get(st, st)
		return "%s — %s\n%s\n누르면 그 자리로." % [str(s.get("name", sid)), word, str(s.get("text", ""))])
	_sig_box.add_child(b)
	_sigs[id] = {"btn": b, "pic": pic, "bar": bar}


func _signal(id: String) -> Dictionary:
	for s: Variant in UI.to_array(_hud.get("signals", [])):
		if str(UI.to_dict(s).get("id", "")) == id:
			return s
	return {}


func _tier_tip(t: int) -> String:
	var nm := tier_name(t)
	var pop := int(UI.to_dict(_hud.get("pop", {})).get("t%d" % t, 0))
	var lab := {}
	for l: Variant in UI.to_array(_hud.get("labor", [])):
		if int(UI.to_dict(l).get("tier", 0)) == t:
			lab = l
	var s := "%s — %s명\n" % [nm, UI.num(pop)]
	if not lab.is_empty():
		s += "일손 %s / 필요 %s" % [UI.num(lab.get("have", 0)), UI.num(lab.get("need", 0))]
		if int(lab.get("need", 0)) > int(lab.get("have", 0)):
			s += " — 모자란다"
	s += "\n누르면 현황판 › 계층."
	return s


func tier_name(t: int) -> String:
	for l: Variant in UI.to_array(_hud.get("labor", [])):
		if int(UI.to_dict(l).get("tier", 0)) == t:
			return str(UI.to_dict(l).get("name", "%d계층" % t))
	return "%d계층" % t


func refresh(h: Dictionary) -> void:
	_hud = h
	_money.text = UI.won(h.get("money", 0))
	var net := float(h.get("net_per_day", 0.0))
	_net.text = "%s/일" % UI.won_signed(net)
	_net.add_theme_color_override("font_color", UI.col("jade_hi") if net >= 0.0 else UI.col("red_hi"))
	var pop := UI.to_dict(h.get("pop", {}))
	for t in range(1, 6):
		var n := int(pop.get("t%d" % t, 0))
		var e: Dictionary = _tiers[t]
		(e["lab"] as Label).text = UI.big(n) if compact > 0 else "%s %s" % [tier_name(t), UI.big(n)]
		(e["btn"] as Control).modulate.a = 1.0 if n > 0 else 0.45
	var hp := float(h.get("happiness", 0.0))
	_happy.text = str(int(hp))
	_happy_pic.shape = "smile" if hp >= 50.0 else "frown"
	_happy_pic.color = UI.col("jade_hi") if hp >= 65.0 else (UI.col("gold") if hp >= 40.0 else UI.col("red_hi"))
	for id: String in _sigs:
		var s := _signal(id)
		var st := str(s.get("state", "off"))
		var e2: Dictionary = _sigs[id]
		var c := UI.state_col(st)
		(e2["pic"] as Picto).color = c if st != "off" else UI.col("mute")
		(e2["bar"] as ColorRect).color = c if st != "off" else Color(0, 0, 0, 0)
		(e2["btn"] as Control).visible = not s.is_empty() or id in ["water", "food", "fun"]
	_date.text = "%d일째" % int(h.get("day", 1))
	_date.visible = compact < 2
	_net.visible = compact < 2
	if _row != null:
		_row.add_theme_constant_override("separation", 10 if compact < 2 else 4)
	_clock.text = UI.clock(float(h.get("hour", 0.0)))
	var hr := float(h.get("hour", 12.0))
	_tod.shape = "clock"
	_tod.color = UI.col("gold_hi") if hr >= 6.0 and hr < 19.0 else Color("5aa0e0")
	var paused := bool(h.get("paused", Game.paused))
	var spd := float(h.get("speed", Game.speed))
	(_speed_btns["pause"] as Button).set_pressed_no_signal(paused)
	(_speed_btns["x1"] as Button).set_pressed_no_signal(not paused and spd < 1.5)
	(_speed_btns["x2"] as Button).set_pressed_no_signal(not paused and spd >= 1.5 and spd < 3.0)
	(_speed_btns["x4"] as Button).set_pressed_no_signal(not paused and spd >= 3.0)


## 좁은 화면: 1 = 계층 칩에서 이름을 빼고 숫자만(이름은 툴팁), 2 = 순수입도 툴팁으로.
func set_compact(level: int) -> void:
	if compact == level:
		return
	compact = level
	refresh(_hud)


func signal_rect(id: String) -> Rect2:
	if _sigs.has(id):
		return (_sigs[id]["btn"] as Control).get_global_rect()
	return Rect2()
