shader_type spatial;
render_mode unshaded, cull_disabled;
// 배경: 디더 그라디언트 하늘 + 해/달 + 별 + 구름 + 사자산 능선과 "합법 도시" 스카이라인 2겹(패럴랙스) + 지면 연무.

uniform vec2 res = vec2(272.0, 482.0);
uniform vec3 sky_top = vec3(0.5, 0.7, 0.85);
uniform vec3 sky_mid = vec3(0.75, 0.87, 0.88);
uniform vec3 sky_low = vec3(0.95, 0.92, 0.82);
uniform vec3 haze = vec3(0.9, 0.86, 0.78);
uniform vec3 sil_far = vec3(0.8, 0.85, 0.87);
uniform vec3 sil_near = vec3(0.66, 0.74, 0.81);
uniform vec3 win_col = vec3(1.0, 0.8, 0.45);
uniform float horizon = 150.0;
uniform vec2 pan_px = vec2(0.0);
uniform float yaw_px = 0.0;
uniform float night = 0.0;
uniform float stars = 0.0;
uniform float time_s = 0.0;
uniform float zoom = 1.0;
uniform vec3 sun = vec3(0.0, 0.0, 0.0);      // xy = px, z = 반지름(0이면 없음)
uniform vec3 sun_col = vec3(1.0, 0.95, 0.8);
uniform vec3 moon = vec3(0.0, 0.0, 0.0);
uniform sampler2D skyline : filter_nearest, repeat_enable;

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

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec2 p = floor(SCREEN_UV * res);
	ivec2 ip = ivec2(p);
	float dth = bayer4(ip);
	float hy = floor(horizon - pan_px.y * 0.18);
	// 하늘 그라디언트(띠 + 디더)
	float t = clamp(p.y / max(hy, 1.0), 0.0, 1.0);
	float tq = clamp(floor(t * 11.0 + dth) / 11.0, 0.0, 1.0);
	vec3 c = tq < 0.55 ? mix(sky_top, sky_mid, tq / 0.55) : mix(sky_mid, sky_low, (tq - 0.55) / 0.45);
	// 별
	if (stars > 0.01 && p.y < hy) {
		vec2 sp = p + vec2(floor(yaw_px * 0.3), 0.0);
		float h = hash21(sp);
		if (h > 0.9965) {
			float tw = 0.6 + 0.4 * step(0.5, hash21(sp + floor(time_s * 1.5)));
			c = mix(c, vec3(0.95, 0.95, 1.0), stars * tw * (1.0 - t * 0.8));
		}
	}
	// 해 / 달
	if (sun.z > 0.5) {
		float d = distance(p, floor(sun.xy));
		if (d < sun.z) { c = sun_col; }
		else if (d < sun.z * 2.6) {
			float g = 1.0 - (d - sun.z) / (sun.z * 1.6);
			if (g * 0.8 > dth) { c = mix(c, sun_col, 0.45); }
		}
	}
	if (moon.z > 0.5) {
		float d2 = distance(p, floor(moon.xy));
		if (d2 < moon.z) {
			c = vec3(0.93, 0.93, 0.84);
			if (distance(p, floor(moon.xy) + vec2(2.0, -1.0)) < moon.z * 0.35) { c = vec3(0.8, 0.8, 0.78); }
		}
	}
	// 구름(느리게 흐르는 픽셀 덩어리)
	if (p.y < hy - 6.0) {
		vec2 cp = vec2(p.x + yaw_px * 0.5 + time_s * 1.2, p.y * 2.6);
		float nz = vnoise(cp / 46.0) * 0.6 + vnoise(cp / 17.0) * 0.4;
		float band = smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.62, 0.95, t));
		float cl = nz * band;
		vec3 cc = mix(sky_low, vec3(1.0), 0.35 * (1.0 - night));
		if (cl > 0.5) { c = mix(c, cc, 0.75 - 0.3 * night); }
		else if (cl > 0.44) { c = mix(c, cc, 0.4 - 0.2 * night); }
	}
	// 스카이라인 3겹: 0 능선, 1 먼 도시, 2 가까운 도시
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float par = 0.05 + 0.06 * fi;
		float base_y = hy + 4.0 + fi * 9.0;
		float sx = p.x + yaw_px * (0.55 + 0.2 * fi) - pan_px.x * par;
		float sy = p.y - (base_y - 64.0);
		vec3 lc = (i == 0) ? mix(sil_far, sky_low, 0.5) : ((i == 1) ? sil_far : sil_near);
		if (sy >= 64.0) {
			c = lc;
		} else if (sy >= 0.0) {
			vec4 s = texture(skyline, vec2((sx + 0.5) / 512.0, (fi * 64.0 + sy + 0.5) / 192.0));
			if (s.r > 0.5) {
				c = lc;
				if (s.b > 0.5) { c = mix(lc, sky_low, 0.22); }
				if (s.g > 0.5 && night > 0.35) {
					float h2 = hash21(floor(vec2(sx, sy)) + fi * 17.0);
					if (h2 < 0.2 + 0.5 * night) { c = mix(lc, win_col, (i == 1) ? 0.55 : 0.85); }
				}
			}
		}
	}
	// 지평선 아래: 연무 낀 땅
	float gy = hy + 4.0 + 18.0;
	if (p.y >= gy) {
		float g = clamp((p.y - gy) / 26.0, 0.0, 1.0);
		float gq = clamp(floor(g * 5.0 + dth) / 5.0, 0.0, 1.0);
		c = mix(sil_near, haze, gq);
		float g2 = clamp((p.y - gy - 26.0) / max(res.y - gy - 26.0, 1.0), 0.0, 1.0);
		float g2q = floor(g2 * 6.0 + dth) / 6.0;
		c = mix(c, mix(haze, sil_near, 0.35), g2q * 0.6);
	}
	ALBEDO = to_linear(clamp(c, vec3(0.0), vec3(1.0)));
}
