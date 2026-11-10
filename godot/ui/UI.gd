class_name UI
extends RefCounted
## UI — 컴포넌트 공용 도우미(정적). 색·폰트는 전부 테마("Kowloon" 타입)에서 읽는다.
## 규칙 없음: 여기에는 게임 규칙·수치가 하나도 없다.

const UNIT := 2            # 디자인 1px = 논리 2px
const TOUCH := 56          # 최소 터치 크기(논리 px)
const ICON_TEX := "res://assets/ui/icons.png"
const MISC := "res://assets/ui/misc/%s.png"
const FALLBACK_THEME := "res://assets/themes/main_theme.tres"
const WJ := "\u2060"

static var _theme: Theme = null
static var _atlas: Texture2D = null
static var _icons: Dictionary = {}
static var _misc: Dictionary = {}


static func theme() -> Theme:
	if _theme == null:
		_theme = ThemeDB.get_project_theme()
		if _theme == null and ResourceLoader.exists(FALLBACK_THEME):
			_theme = load(FALLBACK_THEME)
		if _theme == null:
			_theme = Theme.new()
	return _theme


static func col(n: String) -> Color:
	var t := theme()
	if t.has_color(n, "Kowloon"):
		return t.get_color(n, "Kowloon")
	return Color(1, 0, 1)


static func font(n: String = "body") -> Font:
	var t := theme()
	if t.has_font(n, "Kowloon"):
		return t.get_font(n, "Kowloon")
	return ThemeDB.fallback_font


static func font_size(n: String = "body") -> int:
	var t := theme()
	if t.has_font_size(n, "Kowloon"):
		return t.get_font_size(n, "Kowloon")
	return 24


## 색조(tone) 이름 → 색. 로그·토스트·칩이 같이 쓴다. 모르는 tone은 종이색.
static func tone_col(tone: String) -> Color:
	match tone:
		"good", "gain", "jade", "ok":
			return col("jade_hi")
		"bad", "loss", "danger", "red", "alert":
			return col("red_hi")
		"warn", "gold", "money", "vice", "unlock":
			return col("gold")
		"debug", "dim", "system":
			return col("dim")
	return col("paper")


static func icon(n: String) -> Texture2D:
	if _icons.has(n):
		return _icons[n]
	if _atlas == null and ResourceLoader.exists(ICON_TEX):
		_atlas = load(ICON_TEX)
	var tex: Texture2D = null
	if _atlas != null and IconIndex.ICONS.has(n):
		var a := AtlasTexture.new()
		a.atlas = _atlas
		a.region = IconIndex.ICONS[n]
		tex = a
	_icons[n] = tex
	return tex


static func has_icon(n: String) -> bool:
	return IconIndex.ICONS.has(n)


static func misc(n: String) -> Texture2D:
	if not _misc.has(n):
		var p := MISC % n
		_misc[n] = load(p) if ResourceLoader.exists(p) else null
	return _misc[n]


# ------------------------------------------------------------------ 만들기
## 한국어 줄바꿈을 띄어쓰기에서만 하게 한다(CSS keep-all).
## 글자 사이에 U+2060(WORD JOINER, 폭 0)을 끼워 낱말 중간에서 줄이 갈리지 않게 한다.
## 줄바꿈 되는 라벨에 글을 넣을 때는 항상 이걸 거친다: label.text = UI.keep(s)
static func keep(text: String) -> String:
	if text.length() < 2:
		return text
	var out := PackedStringArray()
	var n := text.length()
	for i in n:
		var ch := text[i]
		out.append(ch)
		if i < n - 1 and ch != " " and ch != "\n" and ch != WJ:
			var nx := text[i + 1]
			if nx != " " and nx != "\n" and nx != WJ:
				out.append(WJ)
	return "".join(out)


static func label(text: String = "", variation: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = keep(text) if wrap else text
	if variation != "":
		l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func icon_rect(n: String, tint: Color = Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(n)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate = tint
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


static func hbox(sep: int = 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func vbox(sep: int = 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func spacer(expand: bool = true, min_size: Vector2 = Vector2.ZERO) -> Control:
	var s := Control.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.custom_minimum_size = min_size
	if expand:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


static func panel(variation: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	return p


static func margin(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


## 작은 글자 딱지(역할·태그). tone: "" / gold / red / jade / paper
static func tag(text: String, tone: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	var lab := "LabelSmall"
	match tone:
		"gold":
			p.theme_type_variation = "PanelTagGold"
			lab = "LabelGoldSmall"
		"red":
			p.theme_type_variation = "PanelTagRed"
		"jade":
			p.theme_type_variation = "PanelTagJade"
		"paper":
			p.theme_type_variation = "PanelTagPaper"
			lab = "LabelInkSmall"
		_:
			p.theme_type_variation = "PanelTag"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(text, lab))
	return p


# ------------------------------------------------------------------ 표시
## 1234.5 → "1,234". 음수는 "−".
static func num(v: Variant) -> String:
	var n := int(floor(float(v) + 0.0001)) if (v is float or v is int) else 0
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return ("-" + out) if neg else out


static func clock(hour: float) -> String:
	var h := int(floor(fposmod(hour, 24.0)))
	var m := int(floor(fposmod(hour, 1.0) * 60.0))
	return "%02d:%02d" % [h, m]


## 화면 안전 영역(노치) 여백을 논리 px로. [top, bottom]
static func safe_insets(node: Node) -> Vector2:
	if not node.is_inside_tree():
		return Vector2.ZERO
	var win := node.get_window()
	if win == null:
		return Vector2.ZERO
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.y <= 0 or safe.size.y <= 0 or OS.has_feature("pc"):
		return Vector2.ZERO
	var scale_y := float(win.size.y) / maxf(1.0, node.get_viewport().get_visible_rect().size.y)
	var top := clampf(float(safe.position.y) / maxf(scale_y, 0.01), 0.0, 80.0)
	var bottom := clampf(float(screen.y - safe.end.y) / maxf(scale_y, 0.01), 0.0, 60.0)
	return Vector2(top, bottom)


## 2px 격자에 맞춘다(픽셀이 반 칸 어긋나지 않게).
static func snap(v: Vector2) -> Vector2:
	return Vector2(round(v.x / UNIT) * UNIT, round(v.y / UNIT) * UNIT)


static func to_dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func to_array(v: Variant) -> Array:
	return v if v is Array else []


## 한국어 조사 고르기: UI.josa("따거", "라", "이라") → "따거라"
static func josa(word: String, no_batchim: String, with_batchim: String) -> String:
	if word.is_empty():
		return word + no_batchim
	var code := word.unicode_at(word.length() - 1)
	if code >= 0xAC00 and code <= 0xD7A3:
		return word + (no_batchim if (code - 0xAC00) % 28 == 0 else with_batchim)
	if code >= 0x30 and code <= 0x39:
		# 숫자: 영·일·삼·육·칠·팔 은 받침 있음
		return word + (with_batchim if (code - 0x30) in [0, 1, 3, 6, 7, 8] else no_batchim)
	return word + no_batchim
