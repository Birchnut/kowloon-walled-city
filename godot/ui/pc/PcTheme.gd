class_name PcTheme
extends RefCounted
## PC판(v0.5) 테마 — 시안 '다: 먹띠와 장부'. 코드로 만든다(StyleBoxFlat). 텍스처 없음.
##
## 두 벌이다.
##   get_theme()    = 먹빛 판용(기본, UIRoot 에 걸린다). 늘 켜져 있는 계기: 위 띠·목표·층·렌즈·짓기 띠·창 단추.
##                    바탕 rgba(20,17,13,.86), 글자 #F2EAD8, 가는 테두리.
##   paper_theme()  = 종이용. 읽을 것: 장부·돈·회상회 같은 창, 알림 쪽지, 안내 카드, 툴팁, 확인창.
##                    바탕 #F3EDDF, 글자 #201C16, 줄 #D6CCB6, 강조 #A3301E, 좋음 #2E6A4C, 주의 #85570A.
## 두 벌은 같은 변형 이름(LabelSmall, PanelBar, Button …)을 쓴다. 노드에 `PcTheme.paper(node)` 를 하면
## 그 아래 전부가 종이 색이 된다(PcWindow·Toasts·Dialog·TipLayer 는 이미 한다). 컴포넌트는 변형 이름만 알면 된다.
## 종이 안에서 색을 코드로 직접 읽어야 하면 UI.pcol / pstate / ptone / ptier (종이용 색) 를 쓴다.
##
## 글꼴(둘 다 OFL, assets/fonts/CREDITS.md): 제목·숫자 Hahmlet, 본문 Noto Sans KR. 픽셀 글꼴은 UI 에서 쓰지 않는다.
##   small = 본문 18px · body = 20px · head = 창 제목 34px · num = 숫자 22px

# 먹빛 판(기본). 이름은 옛 팔레트 그대로 두고 값만 시안 색으로 바꿨다 — 그래서 UI.col("gold") 같은 호출은 그대로 읽힌다.
const PAL := {
	"out": "0b0906", "ink0": "14110d", "ink1": "14110d", "ink2": "f0e8d614", "ink3": "f0e8d62a",
	"line": "f0e8d62a", "paper": "f2ead8", "paper_hi": "fffaf0", "paper2": "c9bfa9", "paper3": "978e7b",
	"dim": "c9bfa9", "mute": "978e7b",
	"red": "b9442f", "red_hi": "f2907d", "red_d": "8a2f21", "red_dd": "4a1f19",
	"gold": "ebc06a", "gold_hi": "f4d58f", "gold_d": "f0e8d65c", "gold_dd": "f0e8d61f",
	"jade": "8fcda6", "jade_hi": "8fcda6", "jade_d": "2e6a4c", "jade_dd": "1d3f2e",
	"ink_text": "17140f", "ink_text_dim": "585044",
	"blue": "8fbbe0", "blue_d": "2a5a8a",
	"tag": "e9a08e", "act_bg": "f2ead8", "act_fg": "17140f", "track": "f0e8d624",
}

# 종이. 같은 이름의 뜻만 종이 위로 옮겼다(paper = 종이 위 글자색이라 어둡다).
const PAL_PAPER := {
	"out": "d6ccb6", "ink0": "ebe3d0", "ink1": "f3eddf", "ink2": "ece4d2", "ink3": "e0d6c0",
	"line": "d6ccb6", "paper": "201c16", "paper_hi": "0d0b08", "paper2": "585044", "paper3": "6e6657",
	"dim": "585044", "mute": "6e6657",
	"red": "a3301e", "red_hi": "a3301e", "red_d": "8a2818", "red_dd": "f6e2da",
	"gold": "85570a", "gold_hi": "85570a", "gold_d": "c9a45e", "gold_dd": "f4e8c8",
	"jade": "2e6a4c", "jade_hi": "2e6a4c", "jade_d": "2e6a4c", "jade_dd": "dcebdf",
	"ink_text": "201c16", "ink_text_dim": "585044",
	"blue": "2a5a8a", "blue_d": "2a5a8a",
	"tag": "a3301e", "act_bg": "201c16", "act_fg": "f3eddf", "track": "ddd3be",
}

const FS_SMALL := 18
const FS_BODY := 20
const FS_HEAD := 34
const FS_NUM := 22

static var _t: Theme = null
static var _p: Theme = null


## 먹빛 판용 색(옛 이름 그대로).
static func c(n: String) -> Color:
	return Color(PAL.get(n, "ff00ff"))


## 종이용 색.
static func cp(n: String) -> Color:
	return Color(PAL_PAPER.get(n, "ff00ff"))


static func get_theme() -> Theme:
	if _t == null:
		_t = _build(false)
	return _t


static func paper_theme() -> Theme:
	if _p == null:
		_p = _build(true)
	return _p


## 이 노드 아래 전부를 종이 색으로. 돌려주는 값은 노드(체이닝용).
static func paper(n: Control) -> Control:
	n.theme = paper_theme()
	return n


# ------------------------------------------------------------------ 공용 조각(새 창·새 판을 쉽게)
## 먹빛 판(늘 켜져 있는 계기). parent 에 붙이고 돌려준다. 안은 UI.vbox/hbox 로 채운다.
static func ink_panel(parent: Node = null, variation: String = "PanelBar") -> PanelContainer:
	var p := UI.panel(variation)
	if parent != null:
		parent.add_child(p)
	return p


## 종이 판(읽을 것을 담는 상자). 안쪽 글자·단추가 전부 종이 색이 된다.
static func paper_panel(parent: Node = null, variation: String = "PanelBar") -> PanelContainer:
	var p := UI.panel(variation)
	paper(p)
	if parent != null:
		parent.add_child(p)
	return p


## 살짝 기운 종이 쪽지(알림·한 줄 소식). 안은 호출한 쪽이 채운다.
static func paper_note(tilt_deg: float = 0.0) -> PanelContainer:
	var p := UI.panel("PanelToast")
	paper(p)
	p.rotation_degrees = tilt_deg
	return p


## 창 제목 아래 가는 줄 + 작은 라벨 머리글(종이 창 안 단락). PcWindow.section 과 같은 모양.
static func rule(parent: Control) -> HSeparator:
	var s := HSeparator.new()
	parent.add_child(s)
	return s


static func _col(h: String, a: float = 1.0) -> Color:
	var k := Color(h)
	return Color(k.r, k.g, k.b, k.a * a)


static func _flat(pal: Dictionary, bg: String, border: String = "", bw: int = 1, pad: Vector4 = Vector4(10, 8, 10, 8), bg_a: float = 1.0, radius: int = 4, shadow: int = 0, bg_override: Variant = null) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg_override if bg_override is Color else _col(pal.get(bg, "ff00ff"), bg_a)
	if border != "":
		s.border_color = _col(pal.get(border, "ff00ff"))
		s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_color = Color(0.03, 0.02, 0.01, 0.38)
		s.shadow_offset = Vector2(0, shadow * 0.4)
	return s


static func _fv(path: String, wght: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(path)
	f.variation_opentype = {"wght": wght}
	return f


static func _build(is_paper: bool) -> Theme:
	var pal: Dictionary = PAL_PAPER if is_paper else PAL
	var col := func(n: String) -> Color: return Color(pal.get(n, "ff00ff"))
	var t := Theme.new()
	var hah := "res://assets/fonts/Hahmlet-VF.ttf"
	var noto := "res://assets/fonts/NotoSansKR-VF.ttf"
	var f_small: Font = _fv(noto, 400)
	var f_body: Font = _fv(noto, 400)
	var f_med: Font = _fv(noto, 500)
	var f_bold: Font = _fv(hah, 600)       # 강한 글자·숫자
	var f_head: Font = _fv(hah, 700)       # 창 제목
	t.default_font = f_small
	t.default_font_size = FS_SMALL

	for k: String in pal:
		t.set_color(k, "Kowloon", Color(pal[k]))
	t.set_font("body", "Kowloon", f_body)
	t.set_font("bold", "Kowloon", f_bold)
	t.set_font("small", "Kowloon", f_small)
	t.set_font("head", "Kowloon", f_head)
	t.set_font_size("body", "Kowloon", FS_BODY)
	t.set_font_size("small", "Kowloon", FS_SMALL)
	t.set_font_size("head", "Kowloon", FS_HEAD)
	t.set_font_size("big", "Kowloon", 48)

	# ── Label ──
	t.set_color("font_color", "Label", col.call("paper"))
	t.set_constant("line_spacing", "Label", 2)
	var lab := func(n: String, f: Font, fs: int, cn: String) -> void:
		t.set_type_variation(n, "Label")
		t.set_font("font", n, f)
		t.set_font_size("font_size", n, fs)
		t.set_color("font_color", n, col.call(cn))
	lab.call("LabelSmall", f_small, FS_SMALL, "paper")
	lab.call("LabelDim", f_small, FS_SMALL, "dim")
	lab.call("LabelMute", f_small, FS_SMALL, "mute")
	lab.call("LabelBody", f_body, FS_BODY, "paper")
	lab.call("LabelBold", f_bold, FS_BODY, "paper")
	lab.call("LabelNum", f_bold, FS_NUM, "paper")
	lab.call("LabelGold", f_bold, FS_BODY, "gold" if not is_paper else "red")   # 종이 위의 머리글·강조는 붉은 먹
	lab.call("LabelGoldSmall", f_med, FS_SMALL, "gold" if not is_paper else "red")   # 머리글: 종이 위에서는 붉은 강조
	lab.call("LabelJade", f_bold, FS_BODY, "jade_hi")
	lab.call("LabelJadeSmall", f_small, FS_SMALL, "jade_hi")
	lab.call("LabelRed", f_bold, FS_BODY, "red_hi")
	lab.call("LabelRedSmall", f_small, FS_SMALL, "red_hi")
	lab.call("LabelHead", f_head, FS_HEAD, "paper")
	lab.call("LabelHeadPaper", f_head, FS_HEAD, "paper")
	lab.call("LabelKey", f_small, FS_SMALL - 2, "mute")
	lab.call("LabelInk", f_body, FS_BODY, "ink_text")
	lab.call("LabelInkSmall", f_small, FS_SMALL, "ink_text_dim")

	# ── Panel ── (먹빛 판 = 반투명 + 1px 가는 선 + 그림자 / 종이 = 불투명 + 1px 종이 선)
	var A := 1.0 if is_paper else 0.86
	var R := 3 if is_paper else 4
	var SH := 0
	t.set_stylebox("panel", "PanelContainer", _flat(pal, "ink1", "line", 1, Vector4(14, 12, 14, 12), A, R, 6))
	var pv := func(n: String, sb: StyleBox) -> void:
		t.set_type_variation(n, "PanelContainer")
		t.set_stylebox("panel", n, sb)
	pv.call("PanelBar", _flat(pal, "ink1", "line", 1, Vector4(12, 8, 12, 8), A, R, 6))
	pv.call("PanelDeep", _flat(pal, "ink0", "line", 1, Vector4(12, 10, 12, 10), 0.9 if is_paper else 0.6, R, SH))
	pv.call("PanelInset", _flat(pal, "ink0", "", 0, Vector4(8, 6, 8, 6), 1.0 if is_paper else 0.5, R, SH))
	pv.call("PanelRow", _row_box(pal, is_paper, false))
	pv.call("PanelRowHi", _row_box(pal, is_paper, true))
	pv.call("PanelNote", _row_box(pal, is_paper, false, true))
	pv.call("PanelNoteHi", _row_box(pal, is_paper, true, true))
	pv.call("PanelGold", _flat(pal, "ink1", "line", 1, Vector4(16, 14, 16, 14), A, R, 6))
	pv.call("PanelWindow", _flat(pal, "ink1", "gold_d" if is_paper else "line", 1, Vector4(0, 0, 0, 0), 1.0 if is_paper else 0.94, R, 28 if is_paper else 12))
	pv.call("PanelTitle", _flat(pal, "ink1", "", 0, Vector4(26, 20, 20, 12), 0.0, 0, 0))
	pv.call("PanelTip", _flat(pal, "ink1", "gold_d" if is_paper else "line", 1, Vector4(14, 10, 14, 10), 1.0, R, 12))
	pv.call("PanelToast", _flat(pal, "ink1", "gold_d" if is_paper else "line", 1, Vector4(14, 9, 14, 9), 1.0, 2, 8))
	# 상태 카드: 종이 = 옅은 색조 + 색 선, 먹빛 = 어두운 색조
	pv.call("PanelRed", _flat(pal, "red_dd", "red", 1, Vector4(14, 10, 14, 10), 1.0 if is_paper else 0.92, R, 6))
	pv.call("PanelJade", _flat(pal, "jade_dd", "jade", 1, Vector4(14, 10, 14, 10), 1.0 if is_paper else 0.92, R, 6))
	pv.call("PanelGoldFill", _flat(pal, "gold_dd", "gold_d", 1, Vector4(14, 10, 14, 10), 1.0 if is_paper else 0.92, R, 6))
	pv.call("PanelTag", _flat(pal, "ink3", "", 0, Vector4(7, 1, 7, 1), 1.0, 2, 0))
	pv.call("PanelTagGold", _flat(pal, "gold_dd", "", 0, Vector4(7, 1, 7, 1), 1.0, 2, 0))
	pv.call("PanelTagRed", _flat(pal, "red_dd", "", 0, Vector4(7, 1, 7, 1), 1.0, 2, 0))
	pv.call("PanelTagJade", _flat(pal, "jade_dd", "", 0, Vector4(7, 1, 7, 1), 1.0, 2, 0))
	pv.call("PanelTagPaper", _flat(pal, "ink3", "", 0, Vector4(7, 1, 7, 1), 1.0, 2, 0))
	pv.call("PanelNone", StyleBoxEmpty.new())

	# ── Button ──
	var btn_bg: Color
	var btn_hov: Color
	var btn_bd: Color
	var btn_fg: Color
	var act_bg: Color = col.call("act_bg")
	var act_fg: Color = col.call("act_fg")
	if is_paper:
		btn_bg = Color("e6ddc9")
		btn_hov = Color("d9cfb8")
		btn_bd = Color("c2b79e")
		btn_fg = Color("201c16")
	else:
		btn_bg = Color("f0e8d614")
		btn_hov = Color("f0e8d62a")
		btn_bd = Color("f0e8d638")
		btn_fg = Color("f2ead8")
	var dis_fg: Color = col.call("mute")
	var mk := func(bg: Color, bd: Color, pad: Vector4 = Vector4(12, 5, 12, 5)) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_border_width_all(1)
		s.border_color = bd
		s.set_corner_radius_all(3)
		s.content_margin_left = pad.x
		s.content_margin_top = pad.y
		s.content_margin_right = pad.z
		s.content_margin_bottom = pad.w
		s.anti_aliasing = true
		return s
	var btn := func(n: String, bg: Color, bd: Color, hov: Color, hov_bd: Color, on_bg: Color, on_bd: Color, fc: Color, fc_on: Color, f: Font) -> void:
		if n != "Button":
			t.set_type_variation(n, "Button")
		t.set_stylebox("normal", n, mk.call(bg, bd))
		t.set_stylebox("hover", n, mk.call(hov, hov_bd))
		t.set_stylebox("pressed", n, mk.call(on_bg, on_bd))
		t.set_stylebox("hover_pressed", n, mk.call(on_bg, on_bd))
		var dis: StyleBoxFlat = mk.call(Color(bg.r, bg.g, bg.b, bg.a * 0.5), Color(bd.r, bd.g, bd.b, bd.a * 0.5))
		t.set_stylebox("disabled", n, dis)
		t.set_stylebox("focus", n, StyleBoxEmpty.new())
		for cn: String in ["font_color", "font_hover_color", "font_focus_color", "icon_normal_color", "icon_hover_color"]:
			t.set_color(cn, n, fc)
		for cn2: String in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]:
			t.set_color(cn2, n, fc_on)
		t.set_color("font_disabled_color", n, dis_fg)
		t.set_color("icon_disabled_color", n, dis_fg)
		t.set_font("font", n, f)
		t.set_font_size("font_size", n, FS_SMALL)
		t.set_constant("h_separation", n, 6)
	btn.call("Button", btn_bg, btn_bd, btn_hov, btn_bd, act_bg, act_bg, btn_fg, act_fg, f_med)
	# 켜고 끄는 칩(탭·배속·층·렌즈): 켜짐 = 밝은 판(종이에서는 먹빛 판)
	btn.call("ButtonToggle", btn_bg, btn_bd, btn_hov, btn_bd, act_bg, act_bg, btn_fg, act_fg, f_med)
	# 주 단추: 처음부터 켜진 모양
	btn.call("ButtonGold", act_bg, act_bg, act_bg.lightened(0.12) if not is_paper else Color("3a342a"), act_bg, act_bg.darkened(0.1), act_bg, act_fg, act_fg, f_med)
	btn.call("ButtonJade", Color("2e6a4c"), Color("2e6a4c"), Color("38805c"), Color("38805c"), Color("245840"), Color("245840"), Color("f3eddf"), Color("f3eddf"), f_med)
	btn.call("ButtonRed", Color("a3301e") if is_paper else Color("8a2f21"), Color("a3301e") if is_paper else Color("f2907d"), Color("b93c28") if is_paper else Color("a03828"), Color("b93c28") if is_paper else Color("f2907d"), Color("8a2818"), Color("8a2818"), Color("f3eddf"), Color("f3eddf"), f_med)
	btn.call("ButtonFlat", Color(0, 0, 0, 0), Color(0, 0, 0, 0), btn_hov, Color(0, 0, 0, 0), btn_hov, Color(0, 0, 0, 0), btn_fg, btn_fg, f_small)
	for s: String in ["normal", "disabled"]:
		t.set_stylebox(s, "ButtonFlat", mk.call(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Vector4(6, 2, 6, 2)))
	for s2: String in ["hover", "pressed", "hover_pressed"]:
		t.set_stylebox(s2, "ButtonFlat", mk.call(btn_hov, Color(0, 0, 0, 0), Vector4(6, 2, 6, 2)))
	# 색 단추가 꺼졌을 때: 색을 빼고 흐린 종이 + 읽을 수 있는 글자(대비 4.5 이상)
	var dis_bg := Color("e2dac6") if is_paper else Color("f0e8d60a")
	var dis_bd := Color("c9bea6") if is_paper else Color("f0e8d61f")
	var dis_fc := Color("5f584b") if is_paper else Color("978e7b")
	for n2: String in ["ButtonGold", "ButtonJade", "ButtonRed"]:
		t.set_stylebox("disabled", n2, mk.call(dis_bg, dis_bd))
		t.set_color("font_disabled_color", n2, dis_fc)
		t.set_color("icon_disabled_color", n2, dis_fc)
	# 짓기 카드: 넓은 판
	btn.call("ButtonCard", btn_bg, btn_bd, btn_hov, btn_bd, Color("f0e8d62e") if not is_paper else Color("d9cfb8"), btn_fg, btn_fg, btn_fg, f_small)

	# ── 스크롤 ──
	var grab_c: Color = Color("c2b79e") if is_paper else Color("f0e8d63a")
	var grab := _flat(pal, "ink3", "", 0, Vector4(3, 3, 3, 3), 1.0, 3, 0, grab_c)
	var grab_h := _flat(pal, "ink3", "", 0, Vector4(3, 3, 3, 3), 1.0, 3, 0, grab_c.darkened(0.2) if is_paper else Color("f0e8d65c"))
	for sbt: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbt, _flat(pal, "ink0", "", 0, Vector4(3, 3, 3, 3), 0.0 if not is_paper else 0.6, 3, 0))
		t.set_stylebox("scroll_focus", sbt, _flat(pal, "ink0", "", 0, Vector4(3, 3, 3, 3), 0.0 if not is_paper else 0.6, 3, 0))
		t.set_stylebox("grabber", sbt, grab)
		t.set_stylebox("grabber_highlight", sbt, grab_h)
		t.set_stylebox("grabber_pressed", sbt, grab_h)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())

	# ── 구분선 ──(1px 가는 줄)
	var sep := StyleBoxLine.new()
	sep.color = col.call("line")
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 8)
	var vsep := StyleBoxLine.new()
	vsep.color = col.call("line")
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_constant("separation", "VSeparator", 10)

	# ── 진행 막대 ──
	t.set_stylebox("background", "ProgressBar", _flat(pal, "ink0", "", 0, Vector4(0, 0, 0, 0), 1.0, 2, 0, Color(pal["track"])))
	t.set_stylebox("fill", "ProgressBar", _flat(pal, "jade", "", 0, Vector4(0, 0, 0, 0), 1.0, 2))
	t.set_font_size("font_size", "ProgressBar", FS_SMALL)

	# ── 슬라이더·체크 ──
	t.set_stylebox("slider", "HSlider", _flat(pal, "ink0", "line", 1, Vector4(0, 4, 0, 4), 1.0, 2, 0, Color(pal["track"])))

	# ── 툴팁(기본 툴팁은 쓰지 않지만 혹시를 대비) ──
	t.set_stylebox("panel", "TooltipPanel", _flat(pal, "ink1", "gold_d", 1, Vector4(12, 8, 12, 8), 1.0, R, 8))
	t.set_color("font_color", "TooltipLabel", col.call("paper"))
	t.set_font("font", "TooltipLabel", f_small)
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)

	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)
	t.set_constant("h_separation", "GridContainer", 10)
	t.set_constant("v_separation", "GridContainer", 4)
	return t


## 누를 수 있는 줄 바탕. 먹빛 = 연한 크림, 종이 = 밑줄만 있는 줄. note = 종이 쪽지(알림).
static func _row_box(pal: Dictionary, is_paper: bool, hi: bool, note: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.anti_aliasing = true
	if is_paper and note:
		s.bg_color = Color("faf6ea") if hi else Color("f3eddf")
		s.border_color = Color("a3301e") if hi else Color("c9bea6")
		s.set_border_width_all(1)
		s.set_corner_radius_all(2)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 7
		s.content_margin_bottom = 7
		s.shadow_size = 5
		s.shadow_color = Color(0.03, 0.02, 0.01, 0.34)
		s.shadow_offset = Vector2(0, 2)
	elif is_paper:
		s.bg_color = Color("e6ddc9") if hi else Color(0, 0, 0, 0)
		s.border_color = Color("d6ccb6")
		s.border_width_bottom = 1
		s.set_corner_radius_all(0)
		s.content_margin_left = 6
		s.content_margin_right = 6
		s.content_margin_top = 5
		s.content_margin_bottom = 5
	else:
		s.bg_color = Color("f0e8d61f") if hi else Color("f0e8d60d")
		s.set_corner_radius_all(3)
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		if note:
			s.border_color = Color("f0e8d62a")
			s.set_border_width_all(1)
	return s
