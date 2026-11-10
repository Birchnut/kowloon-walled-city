shader_type spatial;
render_mode unshaded, cull_back;
// 구룡성채 도시 셰이더 — 조명을 직접 계산한다(3단 톤 + 높이맵 그림자 + 복셀 빛번짐).
// 모든 색 연산은 sRGB(보이는 그대로) 공간에서 하고 마지막에만 선형으로 바꾼다 → 팔레트가 정확히 나온다.
// 정점 규약은 MeshBuf.gd, 알파 규약은 PixelAtlas.gd.

uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform sampler2D heightmap : filter_nearest, repeat_disable;   // R = 높이(1/16층 단위)
uniform sampler3D lightgrid : filter_linear, repeat_disable;    // RGB = 네온, A = 창 불빛
uniform vec2 hm_origin = vec2(-10.0, -10.0);
uniform float hm_size = 32.0;
uniform float hm_clamp = 99.0;       // 층 컷: 이 층 위는 그림자를 안 던짐
uniform float floor_h = 0.8165;
uniform vec3 lg_origin = vec3(-2.0, 0.0, -2.0);
uniform vec3 lg_inv_size = vec3(0.0625, 0.1, 0.0625);

uniform vec3 sun_dir = vec3(-0.4, 0.7, 0.6);
uniform vec3 lit_top = vec3(1.0, 0.98, 0.9);
uniform vec3 lit_side = vec3(0.95, 0.9, 0.8);
uniform vec3 shade = vec3(0.68, 0.68, 0.85);
uniform vec3 haze_col = vec3(0.9, 0.86, 0.78);
uniform vec3 sky_col = vec3(0.6, 0.75, 0.86);
uniform float depth_haze = 0.03;
uniform vec3 view_fwd = vec3(-0.7, 0.0, -0.7);
uniform vec3 view_center = vec3(6.0, 0.0, 6.0);
uniform vec3 lot_center = vec3(6.0, 0.0, 6.0);
uniform float lot_half = 6.0;

uniform float night = 0.0;
uniform float win_level = 0.0;
uniform float biz_day = 1.0;         // 낮 영업 가게 불
uniform float power = 0.0;
uniform vec3 wave_center = vec3(6.0, 0.0, 6.0);
uniform float wave_radius = 1000.0;
uniform vec3 warm_col = vec3(1.0, 0.77, 0.42);
uniform vec3 tv_col = vec3(0.56, 0.82, 1.0);
uniform vec3 candle_col = vec3(1.0, 0.6, 0.29);
uniform float neon_gain = 1.2;
uniform float window_spill = 0.5;
uniform float bands = 3.0;
uniform float light_dither = 0.0;     // 0 = 딱 끊기는 빛 고리(광원에 붙는다), 1 = 디더로 번짐
uniform float ao_strength = 0.2;
uniform float floor_grime = 0.1;
uniform float time_s = 0.0;
uniform vec4 plane = vec4(0.0, 0.0, 0.0, 0.0);   // xz = 그림자 중심(지면), z = 진행 각, w = 세기
uniform float ground_fade = 1.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 info;

void vertex() {
	vec3 p = VERTEX;
	float kind = UV2.y;
	if (kind > 2.5 && kind < 3.5) {
		float ph = UV2.x * 6.283 + (p.x + p.z) * 0.9;
		float s = sin(time_s * 1.7 + ph) + 0.5 * sin(time_s * 2.9 + ph * 1.7);
		p += NORMAL * (floor(s * 1.2 + 0.5) / 16.0) * COLOR.a;
	} else if (kind > 7.5 && kind < 8.5) {
		p.y += (floor(fract(time_s * 9.0) * 2.0) / 32.0) * power * 0.0 + step(0.5, fract(time_s * 11.0)) / 40.0;
	}
	VERTEX = p;
	wpos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	info = UV2;
}

float hm(ivec2 c) {
	int s = int(hm_size) - 1;
	c = clamp(c, ivec2(0), ivec2(s));
	return min(texelFetch(heightmap, c, 0).r * 255.0 / 16.0, hm_clamp);
}

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

float hash11(float x) {
	return fract(sin(x * 12.9898) * 43758.5453);
}

// 높이맵을 격자 DDA로 따라가며 해가 가려지는지 본다(정확한 칸 경계 → 또렷한 그림자).
bool shadowed(vec3 p, vec3 d) {
	vec2 pos = p.xz - hm_origin;
	ivec2 cell = ivec2(floor(pos));
	vec2 dir = d.xz;
	vec2 ad = max(abs(dir), vec2(1e-4));
	vec2 inv = 1.0 / ad;
	ivec2 stp = ivec2(dir.x >= 0.0 ? 1 : -1, dir.y >= 0.0 ? 1 : -1);
	vec2 nxt = vec2(cell) + vec2(dir.x >= 0.0 ? 1.0 : 0.0, dir.y >= 0.0 ? 1.0 : 0.0);
	vec2 tmax = abs(nxt - pos) * inv;
	float top = hm_clamp < 90.0 ? hm_clamp : 16.0;
	for (int i = 0; i < 28; i++) {
		float t;
		if (tmax.x < tmax.y) { t = tmax.x; tmax.x += inv.x; cell.x += stp.x; }
		else { t = tmax.y; tmax.y += inv.y; cell.y += stp.y; }
		float ry = p.y + d.y * t;
		if (ry > top * floor_h) { return false; }
		if (hm(cell) * floor_h > ry + 0.004) { return true; }
	}
	return false;
}

vec3 to_linear(vec3 c) {
	// 호환(GLES3) 렌더러는 unshaded 출력을 그대로 내보낸다 → sRGB 값을 그대로 쓴다.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
#endif
}

void fragment() {
	vec4 t = texture(atlas, UV);
	if (t.a < 0.25) { discard; }
	int kind = int(info.y + 0.5);
	float rnd = info.x;
	bool is_glass = t.a < 0.625;
	bool is_emit = (!is_glass) && t.a < 0.875;
	vec3 base = t.rgb * COLOR.rgb;
	vec3 n = wnrm;
	float dth = bayer4(ivec2(FRAGCOORD.xy));

	// 지면: 부지에서 멀어지면 디더로 사라진다
	if (kind == 4) {
		vec2 dd = abs(wpos.xz - lot_center.xz) - vec2(lot_half);
		float dist = max(max(dd.x, dd.y), 0.0) + 0.35 * min(max(dd.x, 0.0), max(dd.y, 0.0));
		float f = clamp((dist - 2.6 * ground_fade) / (4.5 * ground_fade), 0.0, 1.0);
		if (f > dth) { discard; }
		base = mix(base, haze_col / max(lit_top, vec3(0.05)), clamp(f * 0.8, 0.0, 0.7));
	}

	// ── 해/달 3단 톤 ──
	vec3 light;
	float ndl = dot(n, sun_dir);
	bool sh = true;
	if (kind == 5) {
		sh = false;
	} else if (ndl > 0.16) {
		sh = shadowed(wpos + n * 0.03, sun_dir);
	}
	if (!sh) {
		light = (n.y > 0.5) ? lit_top : ((ndl > 0.42) ? lit_side : mix(lit_side, shade, 0.45));
	} else {
		light = shade;
		if (n.y > 0.5) { light *= 1.10; }
		else if (n.y < -0.5) { light *= 0.82; }
		else if (abs(n.z) > 0.5) { light *= 0.93; }
	}

	// ── 맞닿는 곳 어둡게 / 지붕 가장자리 밝게 ──
	vec2 hp = wpos.xz - hm_origin;
	float ao = 0.0;
	float rim = 0.0;
	if (kind != 5) {
		if (n.y > 0.5) {
			ivec2 c = ivec2(floor(hp));
			vec2 f = fract(hp);
			float myh = wpos.y / floor_h;
			float e = 0.126;
			float hl = hm(c + ivec2(-1, 0)); float hr = hm(c + ivec2(1, 0));
			float hu = hm(c + ivec2(0, -1)); float hd = hm(c + ivec2(0, 1));
			if (f.x < e) { if (hl > myh + 0.3) ao = 1.0; else if (hl < myh - 0.3) rim = 1.0; }
			if (f.x > 1.0 - e) { if (hr > myh + 0.3) ao = 1.0; else if (hr < myh - 0.3) rim = 1.0; }
			if (f.y < e) { if (hu > myh + 0.3) ao = 1.0; else if (hu < myh - 0.3) rim = 1.0; }
			if (f.y > 1.0 - e) { if (hd > myh + 0.3) ao = 1.0; else if (hd < myh - 0.3) rim = 1.0; }
		} else if (abs(n.y) < 0.5) {
			vec2 q = hp + n.xz * 0.06;
			float hfront = hm(ivec2(floor(q))) * floor_h;
			float d = wpos.y - hfront;
			if (d > -0.01 && d < floor_h * 0.19) { ao = 1.0; }
		}
	}
	light *= 1.0 - ao * ao_strength;
	light *= 1.0 + rim * 0.07 * (1.0 - night * 0.5);

	// 아래층일수록 때가 낀다(층 단위 계단)
	float fl = clamp(floor(wpos.y / floor_h + 0.02), 0.0, 3.0);
	if (kind != 4 && kind != 5) {
		light *= 1.0 - floor_grime * (1.0 - fl / 3.0);
	}

	vec3 col = base * light;

	// 비행기 그림자
	if (plane.w > 0.01) {
		vec2 g = wpos.xz - sun_dir.xz / max(sun_dir.y, 0.2) * wpos.y * 0.35;
		vec2 r = g - plane.xy;
		float ca = cos(plane.z); float sa = sin(plane.z);
		vec2 l = vec2(r.x * ca + r.y * sa, -r.x * sa + r.y * ca);
		float body = step(abs(l.y), 0.42) * step(abs(l.x), 3.4);
		float wing = step(abs(l.x + 0.2 - abs(l.y) * 0.35), 0.75 - abs(l.y) * 0.1) * step(abs(l.y), 3.3);
		float tail = step(abs(l.x + 3.0), 0.4) * step(abs(l.y), 1.2);
		if (body + wing + tail > 0.5) { col *= mix(vec3(1.0), vec3(0.66, 0.66, 0.8), plane.w); }
	}

	// 깊이 연무: 뒤쪽 탑이 살짝 뿌옇게 → 덩어리가 분리돼 보인다
	float depth = dot(wpos - view_center, view_fwd);
	float hz = clamp(depth * depth_haze, 0.0, 0.32);
	hz = floor(hz * 24.0 + dth) / 24.0;
	col = mix(col, haze_col, hz * (kind == 4 ? 0.5 : 1.0));

	float powered = step(distance(wpos, wave_center), wave_radius) * step(0.5, power);

	// ── 복셀 빛번짐(네온·창) ──
	vec3 gp = (wpos + n * 0.3 - lg_origin) * lg_inv_size;
	vec4 lg = texture(lightgrid, gp);
	vec3 add = lg.rgb * neon_gain * night * powered + warm_col * lg.a * window_spill * min(win_level * 1.6, 1.0) * max(night, 0.0) * (0.25 + 0.75 * powered);
	float inten = max(add.r, max(add.g, add.b));
	if (inten > 0.02) {
		float q = floor(min(inten, 1.0) * bands + mix(0.35, dth, light_dither)) / bands;
		add *= q / inten;
		float boost = (kind == 4 && is_glass) ? 1.8 : 1.0;
		col += (base * 0.7 + 0.22) * add * boost;
	}

	// ── 유리 ──
	if (is_glass) {
		if (kind == 1 || kind == 7) {
			float on = 0.0;
			vec3 lc = warm_col;
			float pick = fract(rnd * 7.31);
			if (powered > 0.5) {
				float lvl = (kind == 7) ? max(win_level * 1.3, biz_day * 0.0) : win_level;
				on = step(rnd, lvl);
				if (kind == 7) { on = step(fract(rnd * 3.3), min(lvl * 1.5, 1.0)); }
				if (pick > 0.84) {
					lc = tv_col * (0.72 + 0.28 * step(0.5, hash11(floor(time_s * 5.0) + rnd * 91.0)));
				} else if (pick > 0.62) {
					lc = vec3(0.86, 1.0, 0.84);
				} else if (pick > 0.34) {
					lc = warm_col;
				} else {
					lc = warm_col * vec3(1.0, 0.84, 0.66);
				}
			} else {
				on = step(rnd, win_level * 0.2);
				lc = candle_col * (0.5 + 0.14 * step(0.5, hash11(floor(time_s * 7.0) + rnd * 37.0)));
			}
			if (on > 0.5) {
				col = lc * (0.86 + 0.5 * (t.b - 0.55));
			} else {
				col *= mix(vec3(1.0), vec3(0.7, 0.78, 1.0), night);
			}
		} else if (kind == 4) {
			col = mix(col, sky_col, 0.45) + add * 0.4;
		} else if (kind == 5) {
			col = base * light;
		} else {
			col *= mix(vec3(1.0), vec3(0.7, 0.78, 1.0), night);
		}
	}
	if (is_emit) {
		col = base * (0.9 + 0.1 * step(0.3, hash11(floor(time_s * 6.0) + rnd * 13.0)));
	}
	if (kind == 2) {
		float lit = powered * step(0.3, night);
		float fk = 1.0;
		if (fract(rnd * 3.71) > 0.82) {
			fk = step(0.25, hash11(floor(time_s * 9.0) + rnd * 57.0));
		}
		vec3 painted = base * light * 0.92;
		vec3 neon = COLOR.rgb * 1.08 + vec3(0.12);
		col = mix(painted, neon, lit * (0.25 + 0.75 * fk));
	}
	if (kind == 5) {
		// 층 컷 실내: 밤엔 방 불빛이 바닥을 덥힌다
		float rl = lg.a * powered;
		col = mix(col, col * 0.5 + base * warm_col * 0.75, clamp(night * step(0.05, rl + 1.0), 0.0, 1.0) * 0.0);
	}

	ALBEDO = to_linear(clamp(col, vec3(0.0), vec3(1.0)));
}
