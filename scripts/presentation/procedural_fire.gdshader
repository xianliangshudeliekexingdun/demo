shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform sampler2D flame_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_flame_texture = false;
uniform vec4 flame_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
varying vec4 effect_data;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x), mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}
float wisps(vec2 p) {
	return noise(p) * 0.66 + noise(p * 2.13 + vec2(2.8, 0.5)) * 0.34;
}
void vertex() {
	effect_data = INSTANCE_CUSTOM;
}
void fragment() {
	float mode = floor(effect_data.x * 10.0 + 0.5);
	float phase = effect_data.y;
	float opacity = effect_data.z;
	float seed = effect_data.w * 37.0;
	float t = (reduced_motion ? 0.0 : core_time) + seed;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float alpha = 0.0;
	vec3 outer = vec3(0.96, 0.29, 0.055) * COLOR.rgb;
	vec3 hot = vec3(1.0, 0.88, 0.51) * COLOR.rgb;
	vec3 color = outer;
	if (mode < 0.5) {
		// Preserve the painted, branching silhouette. UV motion is deliberately
		// tiny: no cone/triangle procedural mask may replace the actual artwork.
		vec2 fire_uv = UV;
		float edge_weight = sin(UV.y * 3.14159265);
		if (!reduced_motion) {
			fire_uv.x += (noise(vec2(UV.y * 3.4, t * 0.7)) - 0.5) * 0.018 * edge_weight;
			fire_uv.y += sin(UV.x * 8.0 + t * 1.7) * 0.006 * edge_weight;
		}
		vec4 painted = texture(flame_texture, flame_uv_rect.xy + fire_uv * flame_uv_rect.zw);
		alpha = has_flame_texture ? painted.a : 0.0;
		color = painted.rgb * COLOR.rgb;
	} else if (mode < 1.5) {
		float n = wisps(p * 4.1 + vec2(t * 0.16, -t * 0.10));
		float fractures = pow(1.0 - abs(sin(n * 15.0 + angle * 2.0)), 12.0);
		float pockets = smoothstep(0.42, 0.77, n);
		alpha = (pockets * 0.18 + fractures * 0.20) * (1.0 - smoothstep(0.80, 1.0, r));
		color = mix(vec3(0.27, 0.13, 0.09), outer, pockets * 0.9 + fractures * 0.1);
	} else if (mode < 2.5) {
		float ripple = sin(UV.x * 42.0 - t * 16.0) * 0.06 + wisps(vec2(UV.x * 18.0 - t * 4.0, UV.y * 3.0)) * 0.1;
		float side = abs(p.y) + ripple;
		float body = 1.0 - smoothstep(0.48, 1.0, side);
		float core = 1.0 - smoothstep(0.08, 0.30, abs(p.y));
		alpha = body * smoothstep(0.0, 0.018, UV.x) * (1.0 - smoothstep(0.982, 1.0, UV.x));
		color = mix(outer, hot, core * 0.82 + sin(UV.x * 28.0 - t * 9.0) * 0.08);
	} else if (mode < 3.5) {
		float tongues = sin(angle * 15.0 + t * 3.0) * 0.035 + noise(p * 8.0) * 0.045;
		float outer_edge = 1.0 - smoothstep(0.91 + tongues, 1.0, r);
		float inner_edge = smoothstep(0.69, 0.84, r);
		alpha = inner_edge * outer_edge * 0.62;
		color = mix(outer, hot, smoothstep(0.80, 0.89, r));
	} else if (mode < 4.5) {
		float circle = (1.0 - smoothstep(0.012, 0.026, abs(r - 0.88))) + (1.0 - smoothstep(0.008, 0.016, abs(r - 0.71))) * 0.55;
		float facets = abs(p.x) + abs(p.y);
		float diamond = 1.0 - smoothstep(0.012, 0.025, abs(facets - 0.78));
		float runes = pow(abs(sin(angle * 8.0)), 28.0) * smoothstep(0.74, 0.79, r) * (1.0 - smoothstep(0.86, 0.90, r));
		float cracks = pow(1.0 - abs(sin(wisps(p * 5.0) * 18.0)), 14.0) * 0.12;
		alpha = (circle * 0.35 + diamond * 0.28 + runes * 0.45 + cracks) * (1.0 - smoothstep(0.96, 1.0, r));
		color = hot;
	} else if (mode < 5.5) {
		float side = phase < 0.5 ? -1.0 : 1.0;
		float x = p.x * side;
		float y = p.y;
		float bow = 0.24 + 0.47 * (1.0 - y * y);
		float inner = bow - 0.58;
		float outer_border = 1.0 - smoothstep(0.035, 0.095, abs(x - bow));
		float inner_border = 1.0 - smoothstep(0.025, 0.065, abs(x - inner));
		float end_cap = (1.0 - smoothstep(0.035, 0.085, abs(abs(y) - 0.88))) * smoothstep(inner - 0.04, inner, x) * (1.0 - smoothstep(bow, bow + 0.04, x));
		float pane = smoothstep(inner - 0.02, inner + 0.03, x) * (1.0 - smoothstep(bow - 0.03, bow + 0.02, x));
		float cap = 1.0 - smoothstep(0.89, 0.97, abs(y));
		alpha = (outer_border * 0.96 + inner_border * 0.46 + end_cap * 0.75 + pane * 0.18) * cap;
		color = mix(vec3(1.0, 0.72, 0.30), hot, outer_border * 0.8);
	} else if (mode < 6.5) {
		float diamond = abs(p.x) * 0.85 + abs(p.y) * 0.55;
		alpha = (1.0 - smoothstep(0.30, 0.8, diamond)) * (1.0 - smoothstep(0.72, 1.0, r));
		color = hot;
	} else {
		float ray = pow(abs(sin(angle * 4.0 + phase)), 26.0);
		float ring = (1.0 - smoothstep(0.018, 0.035, abs(r - 0.62)));
		alpha = (ray * 0.45 * smoothstep(0.25, 0.40, r) + ring * 0.35) * (1.0 - smoothstep(0.80, 1.0, r));
		color = mix(hot, vec3(0.82, 0.67, 0.99), phase);
	}
	ALBEDO = color;
	EMISSION = color * 0.22;
	ALPHA = clamp(alpha * opacity * COLOR.a, 0.0, 0.9);
}
