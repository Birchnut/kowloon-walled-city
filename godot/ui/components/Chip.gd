class_name Chip
extends PixelButton
## Chip — 켜고 끄는 칩. 켜지면 상아 마작패. 여러 개 중 하나만 고르려면 Segmented 를 쓴다.


static func chip(text: String, icon_id: String = "", on: bool = false, red: bool = false) -> Chip:
	var c := Chip.new()
	c.label_text = text
	c.icon_name = icon_id
	c.theme_type_variation = "ButtonChipRed" if red else "ButtonChip"
	c.toggle_mode = true
	c.button_pressed = on
	return c
