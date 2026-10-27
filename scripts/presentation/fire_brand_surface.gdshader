shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform float flow_speed;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
varying vec4 brand_data;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 v = b - a;
	return length(p - a - v * clamp(dot(p - a, v) / dot(v, v), 0.0, 1.0));
}
void vertex() { brand_data = INSTANCE_CUSTOM; }
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	int mode = int(floor(brand_data.b * 8.0 + 0.5));
	float progress = clamp(brand_data.g, 0.0, 1.0);
	float t = reduced_motion ? 0.0 : core_time * flow_speed;
	float phase = brand_data.r * 6.283185;
	float n = noise(p * 5.0 + vec2(phase, -t));
	float alpha = 0.0;
	float heat = 0.0;
	vec3 color = shell_color.rgb;
	if (mode == 0) {
		float ring = exp(-pow((r - 0.70) / 0.045, 2.0)) * smoothstep(-0.2, 0.4, sin(a * 3.0 + phase));
		alpha = ring * (0.36 + progress * 0.35) + exp(-r * r * 15.0) * progress * 0.35;
		heat = 0.45;
	} else if (mode == 1) {
		// A short target-local flame seal; no lingering debuff or ground area.
		vec2 q = vec2(p.x, -p.y) * 0.25;
		float d = segment(q, vec2(0.01, 0.20), vec2(-0.05, 0.07));
		d = min(d, segment(q, vec2(-0.05, 0.07), vec2(-0.15, -0.03)));
		d = min(d, segment(q, vec2(-0.15, -0.03), vec2(-0.08, -0.18)));
		d = min(d, segment(q, vec2(-0.08, -0.18), vec2(0.08, -0.18)));
		d = min(d, segment(q, vec2(0.08, -0.18), vec2(0.15, -0.03)));
		d = min(d, segment(q, vec2(0.15, -0.03), vec2(0.05, 0.04)));
		d = min(d, segment(q, vec2(0.05, 0.04), vec2(0.03, -0.04)));
		d = min(d, segment(q, vec2(0.03, -0.04), vec2(0.01, 0.20)));
		float line = exp(-pow(d / max(fwidth(d), 0.013), 2.0));
		float halo = exp(-pow(d / 0.040, 2.0));
		float core = exp(-dot(p, p) * 13.0) * pow(1.0 - progress, 2.0);
		alpha = (line * 0.85 + halo * 0.24 + core * 0.85) * pow(1.0 - progress, 0.85);
		heat = clamp(line * 0.50 + core, 0.0, 1.0);
	} else if (mode == 2) {
		float rays = pow(max(0.0, cos(a * 5.0 + phase)), 6.0) * exp(-r * 3.0);
		alpha = (exp(-r * r * 13.0) + rays * 0.5) * pow(1.0 - progress, 1.3);
		heat = 0.95;
	} else if (mode == 3) {
		float thread = exp(-pow(p.y / (0.24 + n * 0.08), 2.0));
		float core = exp(-pow(p.y / 0.080, 2.0));
		float flow = 0.55 + 0.45 * sin((brand_data.r + p.x / 24.0) * 18.0 - t * 1.7);
		alpha = thread * 0.65 + core * (0.30 + flow * 0.18);
		heat = clamp(core * 0.72 + flow * 0.14, 0.0, 1.0);
	} else {
		alpha = smoothstep(0.70, 0.94, n) * (1.0 - smoothstep(0.30, 0.90, r)) * pow(1.0 - progress, 1.5) * 0.48;
		color = edge_color.rgb;
		heat = 0.22;
	}
	color = mix(color, energy_color.rgb, heat * 0.80);
	color = mix(color, core_color.rgb, heat * heat * (mode == 1 || mode == 2 ? 0.70 : 0.38));
	float edge = mode == 3 ? 1.0 - smoothstep(0.94, 1.0, abs(p.x)) : 1.0 - smoothstep(0.93, 1.0, r);
	alpha = clamp(alpha * brand_data.a * edge, 0.0, 0.95);
	COLOR = vec4(color * alpha + energy_color.rgb * heat * alpha * 0.10, alpha);
}
