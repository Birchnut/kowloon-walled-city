shader_type spatial;
render_mode unshaded, cull_disabled;
// 사람 빌보드(v4): 스프라이트 텍셀 = 부위 번호(PeopleSprites). 인스턴스마다 피부·머리·옷·바지·소품 색을 입힌다.
// 발 위치를 픽셀 격자에 맞추고 텍셀 = 화면 픽셀 1:1.
// INSTANCE_CUSTOM = (열, 행, 깃발: 1 뒤집기 + 2 숨김 + 4 실내, 팔레트: 피부 + 머리×8 + 바지×64 + 소품×512)
// COLOR.rgb = 웃옷, COLOR.a = 앞치마·모자 색 번호/8

uniform sampler2D tex : filter_nearest, repeat_disable;
uniform sampler3D lightgrid : filter_linear, repeat_disable;
uniform vec3 lg_origin = vec3(-2.0, 0.0, -2.0);
uniform vec3 lg_inv_size = vec3(0.0625, 0.1, 0.0625);
uniform float ppu = 22.6;
uniform vec2 frame_px = vec2(16.0, 32.0);
uniform vec2 sheet_px = vec2(576.0, 96.0);
uniform float depth_bias = 0.1;
uniform vec3 amb = vec3(0.9, 0.9, 0.9);
uniform float night = 0.0;
uniform float neon_gain = 1.2;
uniform vec3 warm = vec3(1.0, 0.82, 0.6);

const vec3 SKIN[6] = vec3[](vec3(0.98, 0.80, 0.66), vec3(0.93, 0.72, 0.56), vec3(0.80, 0.58, 0.42), vec3(0.64, 0.45, 0.32), vec3(0.99, 0.86, 0.74), vec3(0.86, 0.66, 0.50));
const vec3 HAIR[8] = vec3[](vec3(0.16, 0.13, 0.20), vec3(0.24, 0.18, 0.16), vec3(0.42, 0.28, 0.20), vec3(0.62, 0.60, 0.64), vec3(0.88, 0.86, 0.84), vec3(0.20, 0.16, 0.26), vec3(0.55, 0.20, 0.22), vec3(0.30, 0.26, 0.40));
const vec3 PANTS[8] = vec3[](vec3(0.29, 0.35, 0.54), vec3(0.24, 0.22, 0.30), vec3(0.45, 0.40, 0.34), vec3(0.55, 0.50, 0.42), vec3(0.20, 0.20, 0.24), vec3(0.36, 0.44, 0.36), vec3(0.62, 0.36, 0.32), vec3(0.80, 0.78, 0.72));
const vec3 ACC[8] = vec3[](vec3(0.96, 0.94, 0.90), vec3(0.85, 0.37, 0.37), vec3(0.37, 0.53, 0.77), vec3(0.88, 0.64, 0.24), vec3(0.37, 0.68, 0.48), vec3(0.24, 0.22, 0.30), vec3(0.70, 0.55, 0.78), vec3(0.76, 0.27, 0.24));
const vec3 PROP[4] = vec3[](vec3(0.54, 0.59, 0.67), vec3(0.79, 0.77, 0.71), vec3(0.79, 0.71, 0.54), vec3(0.85, 0.30, 0.25));

varying vec3 shirt;
varying float accf;
varying float flags;
varying float pal;
varying vec3 glow;

void vertex() {
	vec4 vc = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec2 px = floor(vc.xy * ppu + 0.5);
	vec2 off = vec2(VERTEX.x * frame_px.x + mod(frame_px.x, 2.0) * 0.5, (VERTEX.y + 0.5) * frame_px.y);
	POSITION = PROJECTION_MATRIX * vec4((px + off) / ppu, vc.z + depth_bias, 1.0);
	flags = INSTANCE_CUSTOM.z;
	float flip = mod(flags, 2.0);
	float u = flip > 0.5 ? (1.0 - UV.x) : UV.x;
	UV = vec2((INSTANCE_CUSTOM.x + u) * frame_px.x, (INSTANCE_CUSTOM.y + UV.y) * frame_px.y) / sheet_px;
	shirt = COLOR.rgb;
	accf = COLOR.a;
	pal = INSTANCE_CUSTOM.w;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.2, 0.0, 1.0)).xyz;
	vec4 lg = textureLod(lightgrid, (wp - lg_origin) * lg_inv_size, 0.0);
	glow = lg.rgb * neon_gain * night + vec3(1.0, 0.77, 0.42) * lg.a * 0.5 * night;
}

void fragment() {
	if (mod(floor(flags / 2.0), 2.0) > 0.5) { discard; }
	vec4 t = texture(tex, UV);
	if (t.a < 0.5) { discard; }
	int part = int(t.r * 16.0);
	int p = int(pal + 0.5);
	int si = p % 8;
	int hi = (p / 8) % 8;
	int pi = (p / 64) % 8;
	int ri = (p / 512) % 4;
	vec3 c = vec3(1.0, 0.0, 1.0);
	if (part == 1) { c = vec3(0.16, 0.13, 0.21); }
	else if (part == 2) { c = SKIN[min(si, 5)]; }
	else if (part == 3) { c = HAIR[hi]; }
	else if (part == 4) { c = shirt; }
	else if (part == 5) { c = PANTS[pi]; }
	else if (part == 6) { c = vec3(0.23, 0.19, 0.28); }
	else if (part == 7) { c = vec3(0.12, 0.10, 0.16); }
	else if (part == 8) { c = ACC[int(accf * 8.0 + 0.5) % 8]; }
	else if (part == 9) { c = PROP[ri]; }
	else if (part == 10) { c = vec3(0.96, 0.94, 0.90); }
	else if (part == 11) { c = vec3(0.69, 0.50, 0.31); }
	else if (part == 12) { c = shirt * 0.78; }
	else if (part == 13) { c = SKIN[min(si, 5)] * 0.84; }
	bool inside = mod(floor(flags / 4.0), 2.0) > 0.5;
	vec3 light = amb;
	if (inside) {
		light = mix(max(amb, vec3(0.55)), warm, night * 0.85);
	}
	c = c * light + (c * 0.6 + 0.15) * glow;
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
}
