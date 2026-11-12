shader_type spatial;
render_mode unshaded, cull_disabled;
// 김·연기·향·불꽃·물방울·비둘기·먼지 — 전부 셰이더가 시간으로 움직인다(CPU 0).
// INSTANCE_CUSTOM = (씨앗, 종류, 시작 시각, 크기 배율). 디더로 사라진다(반투명 블렌드 없음 → 픽셀이 또렷).
// 종류: 0 김 1 연기 2 향 3 불꽃 4 물방울 5 비둘기 6 먼지(일회성) 7 반딧불(네온 주변 입자)

uniform sampler3D lightgrid : filter_linear, repeat_disable;
uniform vec3 lg_origin = vec3(-2.0, 0.0, -2.0);
uniform vec3 lg_inv_size = vec3(0.0625, 0.1, 0.0625);
uniform float ppu = 11.3137;
uniform float zoom = 1.0;
uniform float time_s = 0.0;
uniform float night = 0.0;
uniform float work = 1.0;          // 일하는 시간(불꽃)
uniform vec3 amb = vec3(1.0);
uniform vec3 smoke_col = vec3(0.42, 0.4, 0.5);
uniform float neon_gain = 1.2;
uniform float cut_y = 1000.0;

varying float kind;
varying float life;      // 0..1
varying float seed;
varying vec2 size_px;
varying vec3 glow;
varying vec2 luv;

float h1(float x) { return fract(sin(x * 12.9898) * 43758.5453); }

float bayer4(ivec2 p) {
	int x = p.x & 3;
	int y = p.y & 3;
	int v = 0;
	if (y == 0) { v = (x == 0) ? 0 : (x == 1) ? 8 : (x == 2) ? 2 : 10; }
	else if (y == 1) { v = (x == 0) ? 12 : (x == 1) ? 4 : (x == 2) ? 14 : 6; }
	else if (y == 2) { v = (x == 0) ? 3 : (x == 1) ? 11 : (x == 2) ? 1 : 9; }
	else { v = (x == 0) ? 15 : (x == 1) ? 7 : (x == 2) ? 13 : 5; }
	return (float(v) + 0.5) / 16.0;
}

void vertex() {
	seed = INSTANCE_CUSTOM.x;
	kind = INSTANCE_CUSTOM.y;
	float t0 = INSTANCE_CUSTOM.z;
	float sc = max(INSTANCE_CUSTOM.w, 0.2);
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 p = base;
	float sz = 2.0;
	life = 0.0;
	if (kind < 0.5) {            // 김
		float dur = 3.2 + seed * 1.5;
		life = fract(time_s / dur + seed * 7.0);
		p.y += life * 1.2 * sc;
		p.x += sin(life * 5.0 + seed * 20.0) * 0.12 * life;
		p.z += cos(life * 4.0 + seed * 11.0) * 0.12 * life;
		sz = floor(1.5 + life * 3.0 * sc) * zoom;
	} else if (kind < 1.5) {     // 연기
		float dur = 5.0 + seed * 2.0;
		life = fract(time_s / dur + seed * 7.0);
		p.y += life * 2.4 * sc;
		p.x += life * life * 1.1 + sin(life * 6.0 + seed * 20.0) * 0.1;
		p.z += life * life * 0.4;
		sz = floor(2.0 + life * 4.0 * sc) * zoom;
	} else if (kind < 2.5) {     // 향
		float dur = 4.0 + seed;
		life = fract(time_s / dur + seed * 7.0);
		p.y += life * 0.9;
		p.x += sin(life * 9.0 + seed * 20.0) * 0.06;
		sz = zoom;
	} else if (kind < 3.5) {     // 불꽃
		float dur = 0.5 + seed * 0.3;
		float cyc = floor(time_s / dur + seed * 7.0);
		life = fract(time_s / dur + seed * 7.0);
		float a = h1(cyc + seed * 31.0) * 6.283;
		float sp = 0.3 + 0.5 * h1(cyc * 1.7 + seed * 3.0);
		p.x += cos(a) * sp * life;
		p.z += sin(a) * sp * life;
		p.y += (0.6 * life - 1.4 * life * life) * 0.8 + 0.1;
		sz = zoom;
		if (h1(floor(time_s * 0.7) + seed * 5.0) > 0.45 * work) { life = 2.0; }
	} else if (kind < 4.5) {     // 물방울
		float dur = 1.4 + seed * 1.5;
		life = fract(time_s / dur + seed * 7.0);
		p.y += (1.0 - life * life) * 0.5 * sc;
		sz = zoom;
		if (life > 0.9) { sz = 2.0 * zoom; }
	} else if (kind < 5.5) {     // 비둘기 떼
		float a = time_s * (0.5 + seed * 0.3) + seed * 40.0;
		float r = 1.1 + 0.9 * h1(seed * 13.0) + 0.3 * sin(time_s * 0.4 + seed * 9.0);
		p.x += cos(a) * r;
		p.z += sin(a) * r * 0.8;
		p.y += 1.0 + 0.5 * sin(a * 0.5 + seed * 5.0) + seed;
		sz = 3.0 * zoom;
		life = fract(time_s * 3.0 + seed * 3.0);
		if (night > 0.6) { life = 2.0; }
	} else if (kind < 6.5) {     // 먼지(일회성, t0에서 시작)
		life = (time_s - t0) / 1.3;
		float a = seed * 6.283;
		p.x += cos(a) * 0.7 * life;
		p.z += sin(a) * 0.7 * life;
		p.y += 0.2 + 0.5 * life * h1(seed * 3.0);
		sz = floor(2.0 + life * 3.0) * zoom;
		if (life < 0.0 || life > 1.0) { life = 2.0; }
	} else if (kind > 7.5 && kind < 8.5) {   // 불길: 짧게 솟는 혀
		float dur = 0.55 + seed * 0.35;
		life = fract(time_s / dur + seed * 7.0);
		p.x += (h1(seed * 17.0) - 0.5) * 0.7 + sin(time_s * 9.0 + seed * 30.0) * 0.04;
		p.z += (h1(seed * 29.0) - 0.5) * 0.7;
		p.y += life * (0.7 + 0.45 * h1(seed * 3.0));
		sz = floor(5.0 - life * 3.5 + 0.5) * zoom;
	} else if (kind > 8.5 && kind < 9.5) {   // 검은 연기(불)
		float dur = 3.0 + seed * 1.5;
		life = fract(time_s / dur + seed * 7.0);
		p.y += 0.4 + life * 2.6;
		p.x += life * life * 0.9 + sin(life * 5.0 + seed * 20.0) * 0.15;
		p.z += (h1(seed * 9.0) - 0.5) * 0.5 + life * 0.3;
		sz = floor(3.0 + life * 6.0) * zoom;
	} else if (kind > 9.5 && kind < 10.5) {  // 파리: 쓰레기 위를 맴돈다
		float a = time_s * (3.0 + seed * 2.0) + seed * 40.0;
		float r = 0.12 + 0.12 * h1(seed * 13.0);
		p.x += cos(a) * r + sin(a * 2.7) * 0.04;
		p.z += sin(a * 1.3) * r;
		p.y += 0.25 + 0.12 * sin(a * 1.9 + seed * 5.0);
		sz = max(1.0, floor(zoom * 0.5 + 0.5));
		life = 0.5;
	} else if (kind > 10.5 && kind < 11.5) { // 거품: 통 위로 톡톡
		float dur = 0.9 + seed * 0.8;
		life = fract(time_s / dur + seed * 7.0);
		p.x += (h1(seed * 5.0) - 0.5) * 0.18;
		p.z += (h1(seed * 7.0) - 0.5) * 0.18;
		p.y += life * 0.12;
		sz = max(1.0, floor(zoom * 0.6));
	} else if (kind > 11.5 && kind < 12.5) { // 공사 먼지(간간이)
		float dur = 2.2 + seed;
		life = fract(time_s / dur + seed * 7.0);
		p.x += (h1(seed * 5.0 + floor(time_s / dur)) - 0.5) * 0.8;
		p.z += (h1(seed * 7.0 + floor(time_s / dur)) - 0.5) * 0.8;
		p.y += life * 0.5;
		sz = floor(1.0 + life * 3.0) * zoom;
	} else {                     // 네온 주변 떠다니는 빛 알갱이
		float dur = 6.0 + seed * 3.0;
		life = fract(time_s / dur + seed * 7.0);
		p.y += life * 0.8;
		p.x += sin(life * 6.0 + seed * 30.0) * 0.3;
		p.z += cos(life * 5.0 + seed * 17.0) * 0.3;
		sz = zoom;
		if (night < 0.4) { life = 2.0; }
	}
	if (p.y > cut_y) { life = 2.0; }
	size_px = vec2(sz, (kind > 4.5 && kind < 5.5) ? 2.0 * zoom : sz);
	vec4 vc = VIEW_MATRIX * vec4(p, 1.0);
	vec2 px = floor(vc.xy * ppu + 0.5);
	vec2 off = VERTEX.xy * size_px + mod(size_px, 2.0) * 0.5;
	POSITION = PROJECTION_MATRIX * vec4((px + off) / ppu, vc.z + 0.3, 1.0);
	luv = UV;
	vec3 gp = (p - lg_origin) * lg_inv_size;
	vec4 lg = textureLod(lightgrid, gp, 0.0);
	glow = lg.rgb * neon_gain * night + vec3(1.0, 0.77, 0.42) * lg.a * 0.6 * night;
}

void fragment() {
	if (life > 1.0) { discard; }
	float dth = bayer4(ivec2(FRAGCOORD.xy));
	vec2 q = floor(luv * size_px);
	vec2 c = (q + 0.5) - size_px * 0.5;
	vec3 col = vec3(1.0);
	if (kind < 1.5) {
		float r = size_px.x * 0.5;
		if (dot(c, c) > r * r + 0.3) { discard; }
		float fade = (kind < 0.5) ? (1.0 - life) * 0.85 : (1.0 - life * life) * 0.9;
		fade *= smoothstep(0.0, 0.08, life);
		fade *= mix(1.0, 0.5, night);       // 밤엔 옅게: 덩어리를 가리는 안개가 되지 않게
		if (fade < dth) { discard; }
		col = (kind < 0.5) ? vec3(0.96, 0.96, 1.0) * mix(amb, vec3(1.0), 0.5 * (1.0 - night)) : smoke_col * amb;
		if (c.y < 0.0 && kind < 0.5) { col *= 0.93; }
		col += glow * 0.35;
	} else if (kind < 2.5) {
		if ((1.0 - life) * 0.7 < dth) { discard; }
		col = vec3(0.86, 0.84, 0.92) * mix(amb, vec3(1.0), 0.4) + glow * 0.6;
	} else if (kind < 3.5) {
		col = mix(vec3(1.0, 0.95, 0.6), vec3(1.0, 0.5, 0.2), life);
	} else if (kind < 4.5) {
		col = vec3(0.6, 0.8, 1.0) * mix(amb, vec3(1.0), 0.5);
	} else if (kind < 5.5) {
		// 3×2: 날개 올림(v) / 내림(-)
		float up = step(0.5, life);
		float on = 0.0;
		if (up > 0.5) { on = (q.y < 0.5 * zoom * 2.0 / 2.0) ? step(abs(c.x), size_px.x * 0.17) : 1.0 - step(abs(c.x), size_px.x * 0.17); }
		else { on = (q.y >= size_px.y * 0.5) ? 1.0 : 0.0; }
		if (on < 0.5) { discard; }
		col = vec3(0.93, 0.92, 0.97) * mix(amb, vec3(1.0), 0.3);
	} else if (kind < 6.5) {
		float r = size_px.x * 0.5;
		if (dot(c, c) > r * r + 0.3) { discard; }
		if ((1.0 - life) * 0.8 < dth) { discard; }
		col = vec3(0.86, 0.8, 0.72) * amb;
	} else if (kind > 7.5 && kind < 8.5) {
		float r = size_px.x * 0.5;
		if (dot(c, c) > r * r + 0.3) { discard; }
		if ((1.0 - life) * 1.1 < dth * 0.8) { discard; }
		col = mix(vec3(1.0, 0.92, 0.45), vec3(1.0, 0.36, 0.12), life);
		if (dot(c, c) < r * r * 0.25) { col = mix(col, vec3(1.0, 1.0, 0.8), 0.6 * (1.0 - life)); }
	} else if (kind > 8.5 && kind < 9.5) {
		float r = size_px.x * 0.5;
		if (dot(c, c) > r * r + 0.3) { discard; }
		float fade = (1.0 - life) * 0.95 * smoothstep(0.0, 0.1, life);
		if (fade < dth) { discard; }
		col = mix(vec3(0.18, 0.15, 0.18), vec3(0.42, 0.38, 0.42), life) * mix(amb, vec3(1.0), 0.3);
	} else if (kind > 9.5 && kind < 10.5) {
		col = vec3(0.1, 0.1, 0.12);
	} else if (kind > 10.5 && kind < 11.5) {
		if (life > 0.85) { discard; }
		col = vec3(0.95, 0.95, 0.88) * mix(amb, vec3(1.0), 0.5);
	} else if (kind > 11.5 && kind < 12.5) {
		float r = size_px.x * 0.5;
		if (dot(c, c) > r * r + 0.3) { discard; }
		if ((1.0 - life) * 0.6 < dth) { discard; }
		col = vec3(0.86, 0.8, 0.72) * amb;
	} else {
		if (sin(life * 3.14159) * 0.8 < dth) { discard; }
		col = clamp(glow * 2.2, vec3(0.0), vec3(1.0));
		if (max(col.r, max(col.g, col.b)) < 0.35) { discard; }
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
}
