shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform float flow_speed;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec4 ember_color : source_color;
varying vec4 vortex_data;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() { vortex_data = INSTANCE_CUSTOM; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x + 0.000001);
	float age = clamp(vortex_data.g, 0.0, 1.0);
	float phase = vortex_data.r * 6.283185;
	int mode = int(floor(vortex_data.b * 8.0 + 0.5));
	float t = reduced_motion ? 0.0 : core_time * flow_speed;
	float edge = 1.0 - smoothstep(0.94, 1.0, r);
	float fade = pow(1.0 - age, 1.3);
	float n = noise(p * 6.0 + vec2(phase, -t * 0.8));
	float alpha = 0.0;
	float light = 0.0;
	vec3 color = shell_color.rgb;
	if (mode == 0 || mode == 1) {
		// Active shape remains the full actual radius through travel and hold.
		float spin = mode == 1 ? t * 0.62 : t;
		float spiral = angle * 3.0 - log(max(r, 0.06)) * 5.2 - spin * 1.7 + phase;
		float arms = pow(1.0 - abs(sin(spiral * 0.5)), 6.0);
		float strands = arms * smoothstep(0.07, 0.22, r) * (1.0 - smoothstep(0.77, 0.98, r));
		float core = exp(-dot(p, p) * 23.0);
		float heat = smoothstep(0.23, 0.76, n) * (1.0 - smoothstep(0.4, 1.0, r));
		float rim = exp(-pow((r - 0.92) * 42.0, 2.0)) * (0.25 + 0.75 * pow(max(sin(angle * 9.0 + phase), 0.0), 3.0));
		alpha = strands * (0.20 + n * 0.20) + heat * 0.09 + core * 0.26 + rim * 0.10;
		light = strands * 0.02 + core * 0.05;
		color = mix(edge_color.rgb, shell_color.rgb, clamp(0.55 + strands * 0.30 + heat * 0.12, 0.0, 1.0));
		color = mix(color, energy_color.rgb, strands * 0.55 + core * 0.38);
		color = mix(color, core_color.rgb, core * 0.25);
		if (mode == 1) { alpha *= 0.86; light *= 0.80; }
	} else if (mode == 2 || mode == 6) {
		vec2 q = p / vec2(0.35 + n * 0.16, 0.67);
		float flame = exp(-dot(q, q) * 1.8) * smoothstep(0.15, 0.72, n);
		float flash = exp(-dot(p, p) * 13.0) * (1.0 - smoothstep(0.0, 0.30, age));
		alpha = (flame * 0.66 + flash * 0.76) * fade;
		light = flash * 0.13 * fade;
		color = mix(shell_color.rgb, core_color.rgb, flash * 0.65);
		if (mode == 6) { alpha *= 0.65; light *= 0.60; }
	} else if (mode == 3) {
		float marks = pow(max(sin(angle * 5.0 + phase), 0.0), 9.0);
		alpha = exp(-pow((r - 0.64 - n * 0.06) * 23.0, 2.0)) * marks * 0.62;
		light = alpha * 0.015;
		color = mix(edge_color.rgb, ember_color.rgb, 0.62);
	} else if (mode == 5) {
		float core = exp(-dot(p, p) * mix(3.5, 14.0, age));
		float curl = pow(max(sin(angle * 3.0 + r * 9.0 - t + phase), 0.0), 5.0) * (1.0 - r);
		alpha = (core * 0.36 + curl * 0.30) * (0.18 + age * 0.82);
		light = core * age * 0.07;
		color = mix(shell_color.rgb, energy_color.rgb, core * age);
	} else {
		// Expired/cooling shapes have no full-radius boundary or explosion ring.
		float core = exp(-dot(p, p) * (9.0 + age * 12.0));
		alpha = mode == 4 ? core * 0.34 * fade : 0.0;
		for (int i = 0; i < 6; i++) {
			float a = float(i) * 2.39996 + phase - age * 1.7;
			vec2 at = vec2(cos(a), sin(a)) * (0.16 + age * 0.35);
			at.y -= age * 0.13;
			vec2 q = (p - at) / vec2(0.035, 0.025);
			alpha += exp(-dot(q, q)) * fade * (reduced_motion ? 0.45 : 0.72);
		}
		light = alpha * 0.035;
		color = mix(ember_color.rgb, edge_color.rgb, age);
	}
	float strength = vortex_data.a * edge;
	alpha = clamp(alpha, 0.0, 0.93) * strength;
	COLOR = vec4(color * alpha + energy_color.rgb * light * strength, alpha);
}
