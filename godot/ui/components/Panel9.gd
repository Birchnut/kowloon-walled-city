class_name Panel9
extends PanelContainer
## Panel9 — 9-슬라이스 판. variant 로 테마의 판 종류를 고른다.
##   ""(먹판) / Gold / Deep / Inset / Plaque / PlaqueGold / PlaqueJade / PlaqueInk / Paper / Sheet / Strip / Bar / Sign …
## (= theme_type_variation "Panel<variant>". 새 판은 테마에 타입만 추가하면 된다.)

@export var variant: String = "":
	set(v):
		variant = v
		theme_type_variation = ("Panel" + v) if v != "" else ""


static func make(p_variant: String = "", blocks_touch: bool = true) -> Panel9:
	var p := Panel9.new()
	p.variant = p_variant
	p.mouse_filter = Control.MOUSE_FILTER_STOP if blocks_touch else Control.MOUSE_FILTER_IGNORE
	return p
