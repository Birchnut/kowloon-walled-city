extends SceneTree
## 테마 생성기 — res://assets/themes/main_theme.tres 를 통째로 다시 만든다.
##
##   godot --headless --path godot -s res://ui/dev/build_theme.gd
##
## 스타일을 바꾸는 길은 둘:
##  (a) 에디터에서 main_theme.tres 를 직접 고친다(색은 "Kowloon" 타입의 color, 판은 각 타입의 stylebox).
##  (b) 아래 팔레트/치수를 고치고 이 스크립트를 다시 돌린다(텍스처까지 바꾸려면 gen_ui_assets.py 먼저).
## 컴포넌트는 색·폰트를 전부 테마에서 읽는다(UI.col / UI.font) → 코드 수정 없이 재스킨.

const OUT_PATH := "res://assets/themes/main_theme.tres"
const NINE := "res://assets/ui/nine/%s.png"

const PAL := {
	"out": "05070d", "ink0": "0b0f1a", "ink1": "121829", "ink2": "1b2338", "ink3": "27314d",
	"line": "3a4670", "paper": "efe6d0", "paper_hi": "fffaf0", "paper2": "cfc3a4", "paper3": "a89a78",
	"dim": "8d97ad", "mute": "5b6682",
	"red": "c9362e", "red_hi": "e2574a", "red_d": "9a2422", "red_dd": "561519",
	"gold": "e8b54a", "gold_hi": "ffe08a", "gold_d": "9c742c", "gold_dd": "5c4318",
	"jade": "3fb090", "jade_hi": "7fe0bf", "jade_d": "1f6e5a", "jade_dd": "123f36",
	"ink_text": "1a1f2e", "ink_text_dim": "5a5648",
}

var t: Theme


func c(n: String) -> Color:
	return Color(PAL[n])


func _init() -> void:
	t = Theme.new()
	var f_body: Font = load("res://assets/fonts/Galmuri11.ttf")
	var f_bold: Font = load("res://assets/fonts/Galmuri11-Bold.ttf")
	var f_small: Font = load("res://assets/fonts/Galmuri9.ttf")
	var f_head: Font = load("res://assets/ui/fonts/NeoDunggeunmo.ttf")
	# 간판 서체에 한자가 없으니 Galmuri를 대체 글꼴로 건다.
	var head := FontVariation.new()
	head.base_font = f_head
	head.fallbacks = [f_bold]

	t.default_font = f_body
	t.default_font_size = 24

	# ── 팔레트·공용 폰트: "Kowloon" 타입 ──
	for k in PAL:
		t.set_color(k, "Kowloon", c(k))
	t.set_font("body", "Kowloon", f_body)
	t.set_font("bold", "Kowloon", f_bold)
	t.set_font("small", "Kowloon", f_small)
	t.set_font("head", "Kowloon", head)
	t.set_font_size("body", "Kowloon", 24)     # Galmuri11 ×2
	t.set_font_size("small", "Kowloon", 20)    # Galmuri9 ×2
	t.set_font_size("head", "Kowloon", 32)     # NeoDunggeunmo ×2
	t.set_font_size("big", "Kowloon", 48)      # Galmuri11 ×4 (간판 큰 글자)
	t.set_constant("unit", "Kowloon", 2)
	t.set_constant("touch", "Kowloon", 56)

	# ── Label ──
	t.set_color("font_color", "Label", c("paper"))
	t.set_constant("line_spacing", "Label", 4)
	_label("LabelSmall", f_small, 20, "paper")
	_label("LabelDim", f_small, 20, "dim")
	_label("LabelMute", f_small, 20, "mute")
	_label("LabelBold", f_bold, 24, "paper")
	_label("LabelGold", f_bold, 24, "gold")
	_label("LabelGoldSmall", f_small, 20, "gold")
	_label("LabelJade", f_bold, 24, "jade_hi")
	_label("LabelRed", f_bold, 24, "red_hi")
	_label("LabelInk", f_body, 24, "ink_text")
	_label("LabelInkBold", f_bold, 24, "ink_text")
	_label("LabelInkSmall", f_small, 20, "ink_text_dim")
	_label("LabelInkRed", f_bold, 24, "red_d")
	_label("LabelHead", head, 32, "gold_hi", "red_dd")
	_label("LabelHeadPaper", head, 32, "paper", "out")
	_label("LabelHeadInk", head, 32, "ink_text")
	_label("LabelSign", f_bold, 24, "gold_hi", "red_dd")
	_label("LabelSignBig", f_bold, 48, "gold_hi", "red_dd")
	_label("LabelStone", f_bold, 72, "paper2", "out")

	# ── Panel ──
	_panel("PanelContainer", "panel", 8, 12, 10)
	_panel_var("PanelGold", "panel_gold", 8, 14, 12)
	_panel_var("PanelDeep", "panel_deep", 8, 10, 8)
	_panel_var("PanelInset", "inset", 8, 10, 8)
	_panel_var("PanelPlaque", "plaque", 8, 14, 6)
	_panel_var("PanelPlaqueGold", "plaque_gold", 8, 14, 6)
	_panel_var("PanelPlaqueJade", "plaque_jade", 8, 14, 6)
	_panel_var("PanelPlaqueInk", "plaque_ink", 8, 14, 6)
	_panel_var("PanelTag", "tag", 6, 8, 2)
	_panel_var("PanelTagGold", "tag_gold", 6, 8, 2)
	_panel_var("PanelTagRed", "tag_red", 6, 8, 2)
	_panel_var("PanelTagJade", "tag_jade", 6, 8, 2)
	_panel_var("PanelTagPaper", "tag_paper", 6, 8, 2)
	_panel_var("PanelSign", "sign", 8, 8, 8)
	_panel_var("PanelSignOff", "sign_off", 8, 8, 8)
	_panel_var("PanelSignGold", "sign_gold", 8, 8, 8)
	_panel_var("PanelBadge", "badge", 8, 6, 0)
	_panel_var("PanelBracket", "bracket", 14, 0, 0)
	_panel_var("PanelBracketRed", "bracket_red", 14, 0, 0)
	_panel_var("PanelBracketJade", "bracket_jade", 14, 0, 0)
	_panel_var("PanelSeal", "seal", 8, 10, 8)
	# 종이(결재 서류): 아래 턱 2
	var paper := _tex("paper", 8, 8, 8, 12)
	_margins(paper, 18, 16, 18, 20)
	t.set_type_variation("PanelPaper", "PanelContainer")
	t.set_stylebox("panel", "PanelPaper", paper)
	# 시트 / 상단 띠 / 하단 바
	var sheet := _tex("sheet", 2, 8, 2, 2)
	_margins(sheet, 0, 8, 0, 0)
	t.set_type_variation("PanelSheet", "PanelContainer")
	t.set_stylebox("panel", "PanelSheet", sheet)
	var strip := _tex("strip", 2, 2, 2, 8)
	_margins(strip, 0, 0, 0, 6)
	t.set_type_variation("PanelStrip", "PanelContainer")
	t.set_stylebox("panel", "PanelStrip", strip)
	var bar := _tex("bar", 2, 8, 2, 2)
	_margins(bar, 0, 6, 0, 0)
	t.set_type_variation("PanelBar", "PanelContainer")
	t.set_stylebox("panel", "PanelBar", bar)
	var empty := StyleBoxEmpty.new()
	t.set_type_variation("PanelNone", "PanelContainer")
	t.set_stylebox("panel", "PanelNone", empty)

	# ── Button ──
	_button("Button", "btn", "btn_down", "paper", "paper", f_body)
	_button_var("ButtonRed", "btn_red", "btn_red_down", "gold_hi", "gold_hi", f_bold)
	_button_var("ButtonJade", "btn_jade", "btn_jade_down", "paper_hi", "paper_hi", f_bold)
	_button_var("ButtonGold", "btn_gold", "btn_gold_down", "ink_text", "ink_text", f_bold)
	# 칩: 꺼짐 = 먹색 버튼, 켜짐 = 상아 마작패(비취 등)
	_button_var("ButtonChip", "btn", "tile", "paper", "ink_text", f_body, true)
	_button_var("ButtonChipRed", "btn", "tile_red", "paper", "red_d", f_body, true)
	# 동사 버튼: 꺼짐 = 먹판, 켜짐 = 옻칠 간판
	_button_var("ButtonVerb", "btn", "btn_red", "paper", "gold_hi", f_small, true)
	# 레일(우측) 버튼
	_button_var("ButtonRail", "btn", "btn_gold", "paper", "ink_text", f_small, true)
	# 테두리만
	var ghost := _tex("btn_ghost", 8, 8, 8, 8)
	_margins(ghost, 14, 8, 14, 8)
	t.set_type_variation("ButtonGhost", "Button")
	for s in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(s, "ButtonGhost", ghost)
	t.set_stylebox("focus", "ButtonGhost", empty)
	t.set_color("font_color", "ButtonGhost", c("dim"))
	t.set_color("font_hover_color", "ButtonGhost", c("dim"))
	t.set_color("font_pressed_color", "ButtonGhost", c("paper"))
	t.set_color("font_focus_color", "ButtonGhost", c("dim"))
	t.set_font("font", "ButtonGhost", f_small)
	t.set_font_size("font_size", "ButtonGhost", 20)
	# 완전 투명(넓은 탭 영역)
	t.set_type_variation("ButtonFlat", "Button")
	for s in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(s, "ButtonFlat", empty)

	# ── 스크롤바: 얇은 선 하나 ──
	var sb_bg := StyleBoxEmpty.new()
	var sb_grab := StyleBoxFlat.new()
	sb_grab.bg_color = c("line")
	sb_grab.content_margin_left = 2
	sb_grab.content_margin_right = 2
	sb_grab.content_margin_top = 2
	sb_grab.content_margin_bottom = 2
	for sbt in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbt, sb_bg)
		t.set_stylebox("scroll_focus", sbt, sb_bg)
		t.set_stylebox("grabber", sbt, sb_grab)
		t.set_stylebox("grabber_highlight", sbt, sb_grab)
		t.set_stylebox("grabber_pressed", sbt, sb_grab)
	t.set_stylebox("panel", "ScrollContainer", empty)
	t.set_stylebox("focus", "ScrollContainer", empty)

	# ── 슬라이더 ──
	var track := _tex("meter_bg", 4, 4, 4, 4)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var area := StyleBoxFlat.new()
	area.bg_color = c("gold_d")
	area.content_margin_top = 3
	area.content_margin_bottom = 3
	area.expand_margin_left = -2
	area.border_width_top = 2
	area.border_width_bottom = 2
	area.border_color = Color(0, 0, 0, 0)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	var grab: Texture2D = load("res://assets/ui/misc/grabber.png")
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	t.set_icon("grabber_disabled", "HSlider", grab)

	# ── 구분선 ──
	var sep := StyleBoxLine.new()
	sep.color = c("ink3")
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)
	var sep_p := StyleBoxLine.new()
	sep_p.color = c("paper2")
	sep_p.thickness = 2
	t.set_type_variation("SepPaper", "HSeparator")
	t.set_stylebox("separator", "SepPaper", sep_p)

	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)

	var err := ResourceSaver.save(t, OUT_PATH)
	print("theme saved: ", OUT_PATH, " err=", err)
	quit()


func _label(type: String, font: Font, size: int, col: String, shadow: String = "") -> void:
	t.set_type_variation(type, "Label")
	t.set_font("font", type, font)
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, c(col))
	if shadow != "":
		t.set_color("font_shadow_color", type, c(shadow))
		t.set_constant("shadow_offset_x", type, 2)
		t.set_constant("shadow_offset_y", type, 2)
		t.set_constant("shadow_outline_size", type, 0)


func _tex(n: String, l: int, tp: int, r: int, b: int) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load(NINE % n)
	s.texture_margin_left = l
	s.texture_margin_top = tp
	s.texture_margin_right = r
	s.texture_margin_bottom = b
	return s


func _margins(s: StyleBox, l: float, tp: float, r: float, b: float) -> void:
	s.content_margin_left = l
	s.content_margin_top = tp
	s.content_margin_right = r
	s.content_margin_bottom = b


func _panel(type: String, tex: String, m: int, pad_x: int, pad_y: int) -> void:
	var s := _tex(tex, m, m, m, m)
	_margins(s, pad_x, pad_y, pad_x, pad_y)
	t.set_stylebox("panel", type, s)


func _panel_var(type: String, tex: String, m: int, pad_x: int, pad_y: int) -> void:
	t.set_type_variation(type, "PanelContainer")
	_panel(type, tex, m, pad_x, pad_y)


## 버튼: normal 은 아래 턱 4(논리 px), pressed 는 2px 내려가고 턱 2.
## toggle=true 면 pressed 스타일이 "켜짐"의 모습(=따로 그린 판)이다.
func _button(type: String, up: String, down: String, col: String, col_on: String, font: Font, toggle: bool = false) -> void:
	var n := _tex(up, 8, 8, 8, 12)
	_margins(n, 14, 8, 14, 12)
	var p := _tex(down, 8, 10 if not toggle else 8, 8, 10 if not toggle else 12)
	if toggle:
		_margins(p, 14, 8, 14, 12)
	else:
		_margins(p, 14, 10, 14, 10)
	var d := _tex("btn_off", 8, 10, 8, 10)
	_margins(d, 14, 10, 14, 10)
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, n)
	t.set_stylebox("pressed", type, p)
	t.set_stylebox("hover_pressed", type, p)
	t.set_stylebox("disabled", type, d)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, c(col))
	t.set_color("font_hover_color", type, c(col))
	t.set_color("font_focus_color", type, c(col))
	t.set_color("font_pressed_color", type, c(col_on))
	t.set_color("font_hover_pressed_color", type, c(col_on))
	t.set_color("font_disabled_color", type, c("mute"))
	t.set_color("icon_normal_color", type, c(col))
	t.set_color("icon_hover_color", type, c(col))
	t.set_color("icon_focus_color", type, c(col))
	t.set_color("icon_pressed_color", type, c(col_on))
	t.set_color("icon_hover_pressed_color", type, c(col_on))
	t.set_color("icon_disabled_color", type, c("mute"))
	t.set_font("font", type, font)
	t.set_font_size("font_size", type, 24 if font.resource_path.find("Galmuri9") < 0 else 20)
	t.set_constant("h_separation", type, 6)


func _button_var(type: String, up: String, down: String, col: String, col_on: String, font: Font, toggle: bool = false) -> void:
	t.set_type_variation(type, "Button")
	_button(type, up, down, col, col_on, font, toggle)
