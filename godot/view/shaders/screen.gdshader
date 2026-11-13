shader_type canvas_item;
// 저해상도 뷰포트를 정수배로 확대해 화면에 붙인다. (선택) 색 단계 양자화.
uniform bool quantize = false;
uniform float levels = 24.0;
uniform float dim = 0.0;   // 고요시간: 화면이 살짝 어두워진다(0..1)

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (quantize) {
		c.rgb = floor(c.rgb * levels + 0.5) / levels;
	}
	c.rgb *= vec3(1.0 - dim, 1.0 - dim * 0.9, 1.0 - dim * 0.7);
	COLOR = vec4(c.rgb, 1.0);
}
