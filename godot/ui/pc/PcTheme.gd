class_name PcTheme
extends RefCounted
## PC판(v0.4) 테마 — 코드로 만든다(StyleBoxFlat, 둥근 모서리 없음 = 픽셀 결). 텍스처 없음.
## 색은 v0.3 팔레트 그대로("Kowloon" 타입). 글꼴은 정수배만 쓴다(픽셀 글꼴이 번지지 않게):
##   small  = Galmuri9 ×2 = 20px   (표·설명 — 1080p에서 기본 글자)
##   body   = Galmuri11 ×2 = 24px  (값·버튼)
##   head   = NeoDunggeunmo ×2 = 32px (창 제목)
## 재스킨: PAL과 아래 치수만 고치면 된다. 컴포넌트는 UI.col()/변형 이름으로만 읽는다.

const PAL := {
	"out": "05070d", "ink0": "0b0f1a", "ink1": "121829", "ink2": "1b2338", "ink3": "27314d",
	"line": "3a4670", "paper": "efe6d0", "paper_hi": "fffaf0", "paper2": "cfc3a4", "paper3": "a89a78",
	"dim": "8d97ad", "mute": "5b6682",
	"red": "c9362e", "red_hi": "e2574a", "red_d": "9a2422", "red_dd": "561519",
	"gold": "e8b54a", "gold_hi": "ffe08a", "gold_d": "9c742c", "gold_dd": "5c4318",
	"jade": "3fb090", "jade_hi": "7fe0bf", "jade_d": "1f6e5a", "jade_dd": "123f36",
	"ink_text": "1a1f2e", "ink_text_dim": "5a5648",
	"blue": "5aa0e0", "blue_d": "2a5a8a",
}

const FS_SMALL := 20
const FS_BODY := 24
const FS_HEAD := 32

static var _t: Theme = null


static func c(n: String) -> Color:
	return Color(PAL.get(n, "ff00ff"))


static func get_theme() -> Theme:
	if _t == null:
		_t = _build()
	return _t


static func _flat(bg: String, border: String = "", bw: int = 2, pad: Vector4 = Vector4(10, 8, 10, 8), bg_a: float = 1.0, lip: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(c(bg), bg_a)
	if border != "":
		s.border_color = c(border)
		s.set_border_width_all(bw)
		if lip > 0:
			s.border_width_bottom = bw + lip
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = false
	return s


static func _build() -> Theme:
	var t := Theme.new()
	var f_body: Font = load("res://assets/fonts/Galmuri11.ttf")
	var f_bold: Font = load("res://assets/fonts/Galmuri11-Bold.ttf")
	var f_small: Font = load("res://assets/fonts/Galmuri9.ttf")
	var f_head0: Font = load("res://assets/ui/fonts/NeoDunggeunmo.ttf")
	var head := FontVariation.new()
	head.base_font = f_head0
	head.fallbacks = [f_bold]
	t.default_font = f_small
	t.default_font_size = FS_SMALL

	for k: String in PAL:
		t.set_color(k, "Kowloon", c(k))
	t.set_font("body", "Kowloon", f_body)
	t.set_font("bold", "Kowloon", f_bold)
	t.set_font("small", "Kowloon", f_small)
	t.set_font("head", "Kowloon", head)
	t.set_font_size("body", "Kowloon", FS_BODY)
	t.set_font_size("small", "Kowloon", FS_SMALL)
	t.set_font_size("head", "Kowloon", FS_HEAD)
	t.set_font_size("big", "Kowloon", 48)

	# ── Label ──
	t.set_color("font_color", "Label", c("paper"))
	t.set_constant("line_spacing", "Label", 3)
	var lab := func(n: String, f: Font, fs: int, col: String, shadow: String = "") -> void:
		t.set_type_variation(n, "Label")
		t.set_font("font", n, f)
		t.set_font_size("font_size", n, fs)
		t.set_color("font_color", n, c(col))
		if shadow != "":
			t.set_color("font_shadow_color", n, c(shadow))
			t.set_constant("shadow_offset_x", n, 2)
			t.set_constant("shadow_offset_y", n, 2)
	lab.call("LabelSmall", f_small, FS_SMALL, "paper")
	lab.call("LabelDim", f_small, FS_SMALL, "dim")
	lab.call("LabelMute", f_small, FS_SMALL, "mute")
	lab.call("LabelBody", f_body, FS_BODY, "paper")
	lab.call("LabelBold", f_bold, FS_BODY, "paper")
	lab.call("LabelGold", f_bold, FS_BODY, "gold")
	lab.call("LabelGoldSmall", f_small, FS_SMALL, "gold")
	lab.call("LabelJade", f_bold, FS_BODY, "jade_hi")
	lab.call("LabelJadeSmall", f_small, FS_SMALL, "jade_hi")
	lab.call("LabelRed", f_bold, FS_BODY, "red_hi")
	lab.call("LabelRedSmall", f_small, FS_SMALL, "red_hi")
	lab.call("LabelHead", head, FS_HEAD, "gold_hi", "red_dd")
	lab.call("LabelHeadPaper", head, FS_HEAD, "paper", "out")
	lab.call("LabelKey", f_small, FS_SMALL, "gold")
	lab.call("LabelInk", f_body, FS_BODY, "ink_text")
	lab.call("LabelInkSmall", f_small, FS_SMALL, "ink_text_dim")

	# ── Panel ──
	t.set_stylebox("panel", "PanelContainer", _flat("ink1", "line", 2, Vector4(12, 10, 12, 10), 0.96))
	var pv := func(n: String, sb: StyleBox) -> void:
		t.set_type_variation(n, "PanelContainer")
		t.set_stylebox("panel", n, sb)
	pv.call("PanelBar", _flat("ink1", "line", 2, Vector4(10, 6, 10, 6), 0.94))
	pv.call("PanelDeep", _flat("ink0", "ink3", 2, Vector4(10, 8, 10, 8), 0.96))
	pv.call("PanelInset", _flat("ink0", "", 0, Vector4(8, 6, 8, 6), 0.8))
	pv.call("PanelRow", _flat("ink2", "", 0, Vector4(8, 4, 8, 4), 0.7))
	pv.call("PanelRowHi", _flat("ink3", "gold_d", 2, Vector4(8, 4, 8, 4), 0.9))
	pv.call("PanelGold", _flat("ink1", "gold_d", 2, Vector4(14, 12, 14, 12), 0.98))
	pv.call("PanelWindow", _flat("ink1", "gold_d", 2, Vector4(0, 0, 0, 0), 0.98))
	pv.call("PanelTitle", _flat("ink2", "", 0, Vector4(14, 6, 8, 6), 1.0))
	pv.call("PanelTip", _flat("ink0", "gold_d", 2, Vector4(12, 10, 12, 10), 0.97))
	pv.call("PanelToast", _flat("ink0", "line", 2, Vector4(12, 8, 12, 8), 0.94))
	pv.call("PanelRed", _flat("red_dd", "red", 2, Vector4(10, 6, 10, 6), 0.95))
	pv.call("PanelJade", _flat("jade_dd", "jade", 2, Vector4(10, 6, 10, 6), 0.95))
	pv.call("PanelGoldFill", _flat("gold_dd", "gold", 2, Vector4(10, 6, 10, 6), 0.95))
	pv.call("PanelTag", _flat("ink3", "", 0, Vector4(6, 1, 6, 1), 1.0))
	pv.call("PanelTagGold", _flat("gold_dd", "", 0, Vector4(6, 1, 6, 1), 1.0))
	pv.call("PanelTagRed", _flat("red_dd", "", 0, Vector4(6, 1, 6, 1), 1.0))
	pv.call("PanelTagJade", _flat("jade_dd", "", 0, Vector4(6, 1, 6, 1), 1.0))
	pv.call("PanelTagPaper", _flat("paper2", "", 0, Vector4(6, 1, 6, 1), 1.0))
	pv.call("PanelNone", StyleBoxEmpty.new())

	# ── Button ── (아래 턱 2px, 마우스를 올리면 금테, 누르면 1px 내려감 = 턱이 없어짐)
	var btn := func(n: String, bg: String, bd: String, hov_bg: String, hov_bd: String, pr_bg: String, pr_bd: String, fc: String, fc_on: String, f: Font, fs: int) -> void:
		if n != "Button":
			t.set_type_variation(n, "Button")
		t.set_stylebox("normal", n, _flat(bg, bd, 2, Vector4(10, 4, 10, 6), 1.0, 2))
		t.set_stylebox("hover", n, _flat(hov_bg, hov_bd, 2, Vector4(10, 4, 10, 6), 1.0, 2))
		t.set_stylebox("pressed", n, _flat(pr_bg, pr_bd, 2, Vector4(10, 6, 10, 4), 1.0, 0))
		t.set_stylebox("hover_pressed", n, _flat(pr_bg, pr_bd, 2, Vector4(10, 6, 10, 4), 1.0, 0))
		t.set_stylebox("disabled", n, _flat("ink1", "ink3", 2, Vector4(10, 4, 10, 6), 1.0, 2))
		t.set_stylebox("focus", n, StyleBoxEmpty.new())
		t.set_color("font_color", n, c(fc))
		t.set_color("font_hover_color", n, c(fc))
		t.set_color("font_focus_color", n, c(fc))
		t.set_color("font_pressed_color", n, c(fc_on))
		t.set_color("font_hover_pressed_color", n, c(fc_on))
		t.set_color("font_disabled_color", n, c("mute"))
		t.set_color("icon_normal_color", n, c(fc))
		t.set_color("icon_hover_color", n, c(fc))
		t.set_color("icon_pressed_color", n, c(fc_on))
		t.set_color("icon_hover_pressed_color", n, c(fc_on))
		t.set_color("icon_disabled_color", n, c("mute"))
		t.set_font("font", n, f)
		t.set_font_size("font_size", n, fs)
		t.set_constant("h_separation", n, 6)
	btn.call("Button", "ink2", "line", "ink3", "gold_d", "ink0", "gold", "paper", "gold_hi", f_small, FS_SMALL)
	# 켜고 끄는 칩(탭·배속·층·렌즈): 켜짐 = 금빛 판
	btn.call("ButtonToggle", "ink2", "line", "ink3", "gold_d", "gold_dd", "gold", "paper", "gold_hi", f_small, FS_SMALL)
	btn.call("ButtonGold", "gold_d", "gold", "gold", "gold_hi", "gold_dd", "gold", "ink_text", "gold_hi", f_bold, FS_SMALL)
	btn.call("ButtonJade", "jade_d", "jade", "jade", "jade_hi", "jade_dd", "jade", "paper_hi", "paper_hi", f_bold, FS_SMALL)
	btn.call("ButtonRed", "red_d", "red", "red", "red_hi", "red_dd", "red", "gold_hi", "gold_hi", f_bold, FS_SMALL)
	btn.call("ButtonFlat", "ink1", "", "ink3", "", "ink0", "", "paper", "gold_hi", f_small, FS_SMALL)
	for s: String in ["normal", "disabled"]:
		t.set_stylebox(s, "ButtonFlat", _flat("ink1", "", 0, Vector4(6, 2, 6, 2), 0.0))
	t.set_stylebox("hover", "ButtonFlat", _flat("ink3", "", 0, Vector4(6, 2, 6, 2), 0.9))
	t.set_stylebox("pressed", "ButtonFlat", _flat("ink0", "", 0, Vector4(6, 2, 6, 2), 0.9))
	t.set_stylebox("hover_pressed", "ButtonFlat", _flat("ink0", "", 0, Vector4(6, 2, 6, 2), 0.9))
	# 짓기 카드: 넓은 판
	btn.call("ButtonCard", "ink2", "ink3", "ink3", "gold_d", "gold_dd", "gold", "paper", "gold_hi", f_small, FS_SMALL)

	# ── 스크롤 ──
	var grab := _flat("line", "", 0, Vector4(3, 3, 3, 3))
	var grab_h := _flat("gold_d", "", 0, Vector4(3, 3, 3, 3))
	for sbt: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbt, _flat("ink0", "", 0, Vector4(3, 3, 3, 3), 0.5))
		t.set_stylebox("scroll_focus", sbt, _flat("ink0", "", 0, Vector4(3, 3, 3, 3), 0.5))
		t.set_stylebox("grabber", sbt, grab)
		t.set_stylebox("grabber_highlight", sbt, grab_h)
		t.set_stylebox("grabber_pressed", sbt, grab_h)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())

	# ── 구분선 ──
	var sep := StyleBoxLine.new()
	sep.color = c("ink3")
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 6)
	var vsep := StyleBoxLine.new()
	vsep.color = c("ink3")
	vsep.thickness = 2
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_constant("separation", "VSeparator", 6)

	# ── 진행 막대 ──
	t.set_stylebox("background", "ProgressBar", _flat("ink0", "ink3", 2, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", _flat("jade", "", 0, Vector4(0, 0, 0, 0)))
	t.set_font_size("font_size", "ProgressBar", FS_SMALL)

	# ── 슬라이더·체크 ──
	t.set_stylebox("slider", "HSlider", _flat("ink0", "line", 2, Vector4(0, 4, 0, 4)))

	# ── 툴팁(기본 툴팁은 쓰지 않지만 혹시를 대비) ──
	t.set_stylebox("panel", "TooltipPanel", _flat("ink0", "gold_d", 2, Vector4(10, 8, 10, 8), 0.97))
	t.set_color("font_color", "TooltipLabel", c("paper"))
	t.set_font("font", "TooltipLabel", f_small)
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)

	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)
	t.set_constant("h_separation", "GridContainer", 10)
	t.set_constant("v_separation", "GridContainer", 4)
	return t
