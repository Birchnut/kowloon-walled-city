shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
// 건물 표시 빌보드: 픽셀 격자에 맞추고 아이콘 텍셀 = 화면 픽셀 정수배. INSTANCE_CUSTOM = (아이콘, 통통 튐, 위상, -).

uniform sampler2D tex : filter_nearest, repeat_disable;
uniform float ppu = 11.3137;
uniform vec2 frame_px = vec2(7.0, 7.0);
uniform vec2 sheet_px = vec2(36.0, 9.0);
uniform float px_scale = 1.0;
uniform float time_s = 0.0;

void vertex() {
	vec4 vc = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec2 px = floor(vc.xy * ppu + 0.5);
	float bob = INSTANCE_CUSTOM.y > 0.5 ? floor(abs(sin(time_s * 3.2 + INSTANCE_CUSTOM.z * 6.283)) * 2.5) : 0.0;
	vec2 sz = frame_px * px_scale;
	vec2 off = vec2(VERTEX.x * sz.x + 0.5 * px_scale, (VERTEX.y + 0.5) * sz.y + bob * px_scale);
	POSITION = PROJECTION_MATRIX * vec4((px + off) / ppu, vc.z + 2.0, 1.0);
	UV = vec2((INSTANCE_CUSTOM.x + UV.x) * frame_px.x, UV.y * frame_px.y) / sheet_px;
}

void fragment() {
	vec4 t = texture(tex, UV);
	if (t.a < 0.5) { discard; }
	ALBEDO = t.rgb;
}
