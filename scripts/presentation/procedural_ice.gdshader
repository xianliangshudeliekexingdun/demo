shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
varying vec4 ice_data;

float ice_hash(vec2 p) {
	return fract(sin(dot(p, vec2(93.17, 147.29))) * 38193.713);
}
void vertex() {
	ice_data = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float mode = floor(ice_data.x * 10.0 + 0.5);
	float phase = ice_data.y;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float t = reduced_motion ? 0.0 : core_time;
	float a = 0.0;
	float bright = 0.0;
	vec3 deep = vec3(0.16, 0.40, 0.58);
	vec3 pale = vec3(0.77, 0.94, 1.0);
	if (mode < 0.5) {
		float rim = 1.0 - smoothstep(0.017, 0.048, abs(r - 0.88));
		float ticks = pow(abs(cos(angle * 6.0)), 24.0) * smoothstep(0.68, 0.77, r) * (1.0 - smoothstep(0.92, 1.0, r));
		a = rim * 0.7 + ticks * 0.8;
		bright = rim * 0.75 + ticks * 0.3;
	} else if (mode < 1.5) {
		float border = 1.0 - smoothstep(0.016, 0.036, abs(r - 0.9));
		float rays = pow(abs(cos(angle * 6.0 + sin(r * 12.0) * 0.12)), 34.0);
		float cracks = rays * smoothstep(0.17, 0.32, r) * (1.0 - smoothstep(0.81, 0.91, r));
		float grain = ice_hash(floor(p * 23.0));
		a = (border * 0.44 + cracks * 0.31 + step(0.985, grain) * 0.13) * (1.0 - smoothstep(0.94, 1.0, r));
		bright = cracks + border * 0.6;
	} else if (mode < 2.5) {
		float edge = 1.0 - smoothstep(0.72, 1.0, abs(p.y));
		float spine = 1.0 - smoothstep(0.055, 0.22, abs(p.y));
		float teeth = pow(abs(cos(UV.x * 36.0)), 10.0) * (1.0 - smoothstep(0.12, 0.85, abs(p.y)));
		a = edge * 0.23 + spine * 0.58 + teeth * 0.27;
		a *= smoothstep(0.0, 0.035, UV.x) * (1.0 - smoothstep(0.965, 1.0, UV.x));
		bright = spine + teeth * 0.7;
	} else if (mode < 3.5) {
		float d = abs(p.x) + abs(p.y);
		a = 1.0 - smoothstep(0.82, 0.95, d);
		float outline = smoothstep(0.56, 0.73, d);
		deep = vec3(0.025, 0.075, 0.15);
		pale = vec3(0.88, 0.98, 1.0);
		bright = mix(0.98, 0.0, outline);
	} else if (mode < 4.5) {
		float hex = max(abs(p.x) * 0.92 + abs(p.y) * 0.22, abs(p.y) * 0.9);
		float rim = 1.0 - smoothstep(0.024, 0.067, abs(hex - 0.78));
		float facets = (1.0 - smoothstep(0.012, 0.026, abs(p.x))) * smoothstep(0.28, 0.72, abs(p.y));
		a = rim * 0.8 + facets * 0.22;
		bright = rim * 0.8 + facets;
	} else if (mode < 5.5) {
		float branch = pow(abs(cos(angle * 3.0)), 32.0) * smoothstep(0.2, 0.29, r);
		float broken = step(0.25, fract(r * 4.4 + phase));
		float edge = 1.0 - smoothstep(0.018, 0.045, abs(r - 0.75));
		a = (branch * broken * 0.85 + edge * 0.35) * (1.0 - smoothstep(0.81, 0.95, r));
		bright = branch + edge * 0.6;
	} else if (mode < 6.5) {
		float left = (1.0 - smoothstep(0.07, 0.14, abs(p.x + 0.52))) * (1.0 - smoothstep(0.36, 0.59, abs(p.y)));
		float right = (1.0 - smoothstep(0.07, 0.14, abs(p.x - 0.52))) * (1.0 - smoothstep(0.36, 0.59, abs(p.y)));
		float slash = (1.0 - smoothstep(0.07, 0.15, abs(p.x + p.y))) * (1.0 - smoothstep(0.45, 0.74, r));
		a = (left + right + slash) * 0.9;
		pale = vec3(0.86, 0.95, 1.0);
		bright = 0.9;
	} else if (mode < 7.5) {
		float side = 1.0 - smoothstep(0.02, 0.07, abs(abs(p.y) - 0.89));
		float ends = 1.0 - smoothstep(0.02, 0.07, abs(abs(p.x) - 0.93));
		float chevron = pow(1.0 - abs(sin(UV.x * 22.0 - abs(p.y) * 2.1)), 28.0);
		a = side * 0.48 + ends * 0.4 + chevron * 0.15;
		a *= 1.0 - smoothstep(0.95, 1.0, max(abs(p.x), abs(p.y)));
		bright = side + ends * 0.7;
	} else if (mode < 8.5) {
		float side = phase < 0.5 ? -1.0 : 1.0;
		float x = p.x * side;
		float bow = 0.22 + 0.46 * (1.0 - p.y * p.y);
		float border = 1.0 - smoothstep(0.025, 0.08, abs(x - bow));
		float inner = 1.0 - smoothstep(0.02, 0.05, abs(x - (bow - 0.52)));
		float cap = 1.0 - smoothstep(0.83, 0.98, abs(p.y));
		a = (border * 0.8 + inner * 0.5) * cap;
		bright = border + inner * 0.7;
	} else {
		float rays = pow(abs(cos(angle * 5.0 + ice_data.w * 4.0)), 19.0);
		float fracture = (1.0 - smoothstep(0.035, 0.08, abs(p.x + p.y * 0.37)));
		a = (rays * 0.6 + fracture * 0.4) * (1.0 - smoothstep(0.3, 0.95, r));
		bright = rays + fracture;
	}
	vec3 color = mix(deep, pale, clamp(bright, 0.0, 1.0)) * COLOR.rgb;
	ALBEDO = color;
	EMISSION = color * 0.18;
	float alpha_limit = mode > 2.5 && mode < 3.5 ? 0.9 : 0.72;
	ALPHA = clamp(a * ice_data.z * COLOR.a, 0.0, alpha_limit);
}

