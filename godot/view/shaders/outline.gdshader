shader_type spatial;
render_mode unshaded, blend_mul, depth_test_disabled, depth_draw_never, cull_disabled;
// 깊이 불연속에 1px 어두운 외곽선(가까운 쪽 픽셀을 어둡게). 곱하기 블렌드라 화면 텍스처가 필요 없다.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec2 res = vec2(272.0, 482.0);
uniform float strength = 0.35;
uniform float threshold = 0.3;
uniform vec3 tint = vec3(0.55, 0.5, 0.75);

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 px = 1.0 / res;
	vec2 uv = SCREEN_UV;
	float d0 = lin_depth(uv, INV_PROJECTION_MATRIX);
	float dl = lin_depth(uv + vec2(-px.x, 0.0), INV_PROJECTION_MATRIX);
	float dr = lin_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float du = lin_depth(uv + vec2(0.0, -px.y), INV_PROJECTION_MATRIX);
	float dd = lin_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	// 이웃이 훨씬 멀면(내가 가리는 쪽) 가장자리
	float e = max(max(dl - d0, dr - d0), max(du - d0, dd - d0));
	// 같은 면의 기울기는 빼 준다(2차 미분)
	float sx = abs(dl + dr - 2.0 * d0);
	float sy = abs(du + dd - 2.0 * d0);
	float edge = step(threshold, e) * step(threshold * 0.6, max(sx, sy));
	if (d0 > 190.0) { edge = 0.0; }
	vec3 m = mix(vec3(1.0), mix(vec3(1.0), tint, strength * 2.0), edge);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = clamp(m, vec3(0.0), vec3(1.0));
#else
	ALBEDO = pow(clamp(m, vec3(0.0), vec3(1.0)), vec3(2.2));
#endif
}
