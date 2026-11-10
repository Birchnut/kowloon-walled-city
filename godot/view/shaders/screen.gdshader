shader_type canvas_item;
// 저해상도 뷰포트를 정수배로 확대해 화면에 붙인다. (선택) 색 단계 양자화.
uniform bool quantize = false;
uniform float levels = 24.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (quantize) {
		c.rgb = floor(c.rgb * levels + 0.5) / levels;
	}
	COLOR = vec4(c.rgb, 1.0);
}
