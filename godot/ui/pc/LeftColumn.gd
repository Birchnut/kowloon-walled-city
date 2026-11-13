class_name LeftColumn
extends VBoxContainer
## 왼쪽 기둥: 위 = 다음 목표(할 일·진행·방법 한 줄·가는 버튼), 가운데 = 알림 목록(누르면 그 자리로), 아래 = 층·렌즈(FloorPanel).
## 읽는 것: hud.next_goal{id,text,progress,rewards}, hud.alerts[{id,text,tone,jump}], hud.alerts_total, data/ui/goal_tips.json.

signal jump(target: Variant)

const W := 340.0

var goal_box: PanelContainer
var _goal_text: Label
var _goal_bar: RatioBarPc
var _goal_pct: Label
var _goal_tip: Label
var _goal_reward: Label
var _goal_btns: HFlowContainer
var _goal_id: String = "?"
var alert_box: PanelContainer
var _alerts: VBoxContainer
var _alert_head: Label
var _alert_sig: String = ""
var floors: FloorPanel
var collapsed_goal: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(W, 0)


func _ready() -> void:
	# ── 다음 목표 ──
	goal_box = UI.panel("PanelGold")
	goal_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(goal_box)
	var gv := UI.vbox(6)
	goal_box.add_child(gv)
	var gh := UI.hbox(6)
	gv.add_child(gh)
	gh.add_child(Picto.make("goal", UI.col("gold")))
	var gt := UI.label("다음 목표", "LabelGoldSmall")
	gt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gh.add_child(gt)
	var all := PcButton.make("목표 전부", "", "", "ButtonFlat")
	all.min_h = 28
	all.pressed.connect(func() -> void: jump.emit({"screen": "keep", "arg": "goals"}))
	TipLayer.set_tip(all, "네모청 › 목표\n앞으로의 목표와 끝낸 목표.")
	gh.add_child(all)
	_goal_text = UI.label("", "LabelBold", true)
	_goal_text.custom_minimum_size.x = W - 30
	gv.add_child(_goal_text)
	var pr := UI.hbox(8)
	gv.add_child(pr)
	_goal_bar = RatioBarPc.new()
	_goal_bar.col = UI.col("jade")
	_goal_bar.custom_minimum_size = Vector2(220, 12)
	_goal_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(_goal_bar)
	_goal_pct = UI.label("", "LabelSmall")
	pr.add_child(_goal_pct)
	_goal_tip = UI.label("", "LabelDim", true)
	_goal_tip.custom_minimum_size.x = W - 30
	gv.add_child(_goal_tip)
	_goal_reward = UI.label("", "LabelGoldSmall", true)
	_goal_reward.custom_minimum_size.x = W - 30
	_goal_reward.max_lines_visible = 2          # 열리는 시설 목록이 길면 두 줄까지(전부는 마우스를 올려서)
	_goal_reward.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_goal_reward.mouse_filter = Control.MOUSE_FILTER_STOP
	gv.add_child(_goal_reward)
	# 가는 버튼은 넷까지, 넘치면 다음 줄로(1층 필수 셋은 시장·먹을 것·물·놀 것 넷)
	_goal_btns = HFlowContainer.new()
	_goal_btns.add_theme_constant_override("h_separation", 4)
	_goal_btns.add_theme_constant_override("v_separation", 4)
	_goal_btns.custom_minimum_size.x = W - 30
	gv.add_child(_goal_btns)

	# ── 알림 ──
	alert_box = UI.panel("PanelNone")          # 알림은 상자 없이 종이 쪽지만 쌓는다
	PcTheme.paper(alert_box)
	alert_box.mouse_filter = Control.MOUSE_FILTER_STOP
	alert_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(alert_box)
	var av := UI.vbox(6)
	alert_box.add_child(av)
	var ah := UI.hbox(6)
	av.add_child(ah)
	ah.add_child(Picto.make("alert", UI.col("paper2")))
	_alert_head = UI.label("알림", "LabelGoldSmall")
	ah.add_child(_alert_head)
	ah.visible = false                        # 시안: 머리글 없이 쪽지만(개수는 "알림 N" 대신 쪽지 수로 보인다)
	_alerts = UI.vbox(2)
	av.add_child(_alerts)

	add_child(UI.spacer(true))
	floors = FloorPanel.new()
	add_child(floors)


## 창이 낮으면(1280×720 등) 방법 줄을 접어 층·렌즈가 잘리지 않게 한다 — 방법은 목표 카드에 마우스를 올리면 나온다.
func _fit() -> void:
	var tight := get_viewport_rect().size.y < 1000.0
	_goal_tip.visible = _goal_tip.text != "" and not tight
	TipLayer.set_tip(_goal_text, ("이렇게 한다\n" + _goal_tip.text) if tight and _goal_tip.text != "" else "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _goal_tip != null:
		_fit()


func refresh(h: Dictionary) -> void:
	_refresh_goal(UI.to_dict(h.get("next_goal", {})))
	_refresh_alerts(UI.to_array(h.get("alerts", [])), int(h.get("alerts_total", 0)))
	floors.refresh(h)


func _refresh_goal(g: Dictionary) -> void:
	var text := str(g.get("text", ""))
	goal_box.visible = text != ""
	if text == "":
		return
	var p := clampf(float(g.get("progress", 0.0)), 0.0, 1.0)
	_goal_bar.ratio = p
	# 목표 판정은 시뮬이 2경제시간마다 한다 — 100%가 된 뒤 카드가 뜨기까지의 공백을 "곧 달성"으로 메운다(통합 때 고침)
	var id := str(g.get("id", ""))
	_goal_pct.text = "곧 달성" if p >= 0.999 and id != "" else UI.pct(p)
	if id == _goal_id and _goal_text.text != "":
		return
	_goal_id = id
	_goal_text.text = UI.keep(UI.no_hanja(text))
	var rw: Array = []
	for r: Variant in UI.to_array(g.get("rewards", [])):
		rw.append(str(r))
	_goal_reward.text = UI.keep("보상 " + " · ".join(rw)) if not rw.is_empty() else ""
	_goal_reward.visible = not rw.is_empty()
	TipLayer.set_tip(_goal_reward, "보상\n" + " · ".join(rw))
	var tip := goal_tip(id, text)
	_goal_tip.text = UI.keep(UI.no_hanja(str(tip.get("tip", ""))))
	_fit()
	PcWindow.clear(_goal_btns)
	for b: Variant in UI.to_array(tip.get("go", [])).slice(0, 4):
		var bd := UI.to_dict(b)
		var btn := PcButton.make(str(bd.get("label", "")), "right", "", "Button")
		btn.min_h = 32
		var j: Variant = bd.get("jump", {})
		btn.pressed.connect(func() -> void: jump.emit(j))
		_goal_btns.add_child(btn)
	_goal_btns.visible = _goal_btns.get_child_count() > 0


## 목표 id → {tip, go}. 1) goal_tips.items[id] 2) goal_tips.patterns(목표 문장에 든 낱말) 3) 빈 것(목표 문장만).
## SIM 이 목표를 고쳐 써도 패턴이 맞으면 방법 줄이 남는다.
static func goal_tip(id: String, text: String) -> Dictionary:
	var root := UI.to_dict(Data.file("goal_tips"))
	var by_id := UI.to_dict(UI.to_dict(root.get("items", {})).get(id, {}))
	if not by_id.is_empty():
		return by_id
	for pat: Variant in UI.to_array(root.get("patterns", [])):
		var pd := UI.to_dict(pat)
		for w: Variant in UI.to_array(pd.get("words", [])):
			if text.contains(str(w)):
				return pd
	return {}


func _refresh_alerts(list: Array, total: int) -> void:
	var sig := JSON.stringify(list)
	if sig == _alert_sig:
		return
	_alert_sig = sig
	PcWindow.clear(_alerts)
	alert_box.visible = not list.is_empty()
	_alert_head.text = "알림 %d" % maxi(total, list.size())
	for a: Variant in list.slice(0, 6):
		var ad := UI.to_dict(a)
		var tone := str(ad.get("tone", ""))
		var b := ClickRow.new()
		b.base = "PanelNote"
		var hb := UI.hbox(6)
		b.add_child(hb)
		var pic := "warn" if tone in ["bad", "danger", "red", "alert"] else ("check" if tone in ["good", "ok", "jade"] else "alert")
		var t := str(ad.get("text", ""))
		if t.contains("불") and tone in ["bad", "danger", "red"]:
			pic = "fire"
		hb.add_child(Picto.make(pic, UI.ptone(tone)))
		var l := UI.label(t, "LabelSmall", true)
		l.custom_minimum_size.x = W - 90
		hb.add_child(l)
		# 살짝 기운 쪽지: 줄마다 -0.7° ~ +0.7°
		var tilt: float = [-0.8, 0.6, -0.4, 0.9, -0.7, 0.45][_alerts.get_child_count() % 6]
		b.rotation_degrees = tilt
		b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
		var j: Variant = ad.get("jump", {})
		b.pressed.connect(func() -> void: jump.emit(j))
		var jj := Q.norm_jump(j)
		TipLayer.set_tip(b, "%s\n누르면: %s" % [t, _jump_word(jj)])
		_alerts.add_child(b)


static func _jump_word(j: Dictionary) -> String:
	match str(j.get("screen", "")):
		"focus":
			return "그 자리로 카메라를 옮긴다"
		"build":
			return "짓기 — 그 시설"
		"metrics":
			return "장부"
		"lens":
			return "범위 렌즈"
		"economy":
			return "돈 창"
		"trade":
			return "회상회 창"
		"expedition":
			return "회색 띠 창"
		"keep":
			return "네모청 창"
		"upgrade":
			return "일괄 승급"
		"inspect":
			return "그 건물 살피기"
	return "—"


func goal_rect() -> Rect2:
	return goal_box.get_global_rect() if goal_box.visible else Rect2()
