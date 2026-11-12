class_name MenuGrid
extends PanelContainer
## 오른쪽 아래 창 버튼 3×2: 현황판 Tab · 경제 F2 · 교역 F3 / 탐험 F4 · 성채 F6 · 도움말 F1.
## 배지: 탐험 = 돌아온 팀 수(초록), 교역 = 실패한 계약 수(빨강).

signal window_pressed(id: String)

var btns: Dictionary = {}


func _init() -> void:
	theme_type_variation = "PanelBar"
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	add_child(g)
	for w: Array in TopBar.WINDOWS:
		var b := PcButton.make(w[1], w[2], w[3], "ButtonGold" if w[0] == "metrics" else "Button")
		b.min_h = 38
		b.min_w = 128
		b.center = false
		var wid: String = w[0]
		b.pressed.connect(func() -> void: window_pressed.emit(wid))
		TipLayer.set_tip(b, TopBar.win_tip(wid, w[3]))
		g.add_child(b)
		btns[wid] = b
