shader_type spatial;
render_mode unshaded, cull_disabled;
// 사람 빌보드: 발 위치를 픽셀 격자에 맞추고 스프라이트 텍셀 = 화면 픽셀 정수배로 그린다.
// INSTANCE_CUSTOM = (프레임 x, 프레임 y, 좌우 뒤집기, 숨김). COLOR = 옷 색(알파 0.5 텍셀에만).

uniform sampler2D tex : filter_nearest, repeat_disable;
uniform sampler3D lightgrid : filter_linear, repeat_disable;
uniform vec3 lg_origin = vec3(-2.0, 0.0, -2.0);
uniform vec3 lg_inv_size = vec3(0.0625, 0.1, 0.0625);
uniform float ppu = 11.3137;
uniform vec2 frame_px = vec2(4.0, 6.0);     // 한 프레임 크기(텍셀)
uniform vec2 sheet_px = vec2(32.0, 16.0);   // 시트 크기(텍셀)
uniform vec2 origin_px = vec2(0.0, 0.0);    // 시트 안에서 이 LOD의 시작점
uniform float px_scale = 1.0;               // 텍셀 1개 = 화면 픽셀 몇 개
uniform vec3 amb = vec3(0.9, 0.9, 0.9);
uniform float night = 0.0;
uniform float neon_gain = 1.2;

varying vec3 tint;
varying vec3 glow;
varying float hide;

void vertex() {
	vec4 vc = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec2 px = floor(vc.xy * ppu + 0.5);
	vec2 sz = frame_px * px_scale;
	vec2 off = vec2(VERTEX.x * sz.x + mod(frame_px.x, 2.0) * 0.5 * px_scale, (VERTEX.y + 0.5) * sz.y);
	POSITION = PROJECTION_MATRIX * vec4((px + off) / ppu, vc.z + 0.22, 1.0);
	float fx = INSTANCE_CUSTOM.x;
	float fy = INSTANCE_CUSTOM.y;
	float u = (INSTANCE_CUSTOM.z > 0.5) ? (1.0 - UV.x) : UV.x;
	UV = (origin_px + vec2((fx + u) * frame_px.x, (fy + UV.y) * frame_px.y)) / sheet_px;
	tint = COLOR.rgb;
	hide = INSTANCE_CUSTOM.w;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.2, 0.0, 1.0)).xyz;
	vec3 gp = (wp - lg_origin) * lg_inv_size;
	vec4 lg = textureLod(lightgrid, gp, 0.0);
	glow = lg.rgb * neon_gain * night + vec3(1.0, 0.77, 0.42) * lg.a * 0.5 * night;
}

void fragment() {
	if (hide > 0.5) { discard; }
	vec4 t = texture(tex, UV);
	if (t.a < 0.25) { discard; }
	vec3 c = t.rgb;
	if (t.a < 0.75) { c *= tint; }
	c = c * amb + (c * 0.6 + 0.15) * glow;
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
}
