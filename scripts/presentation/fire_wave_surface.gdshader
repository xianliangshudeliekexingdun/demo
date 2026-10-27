shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec4 ember_color : source_color;
varying vec4 wave_data;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() { wave_data = INSTANCE_CUSTOM; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float age = clamp(wave_data.g, 0.0, 1.0);
	float phase = wave_data.r * 6.283185;
	int mode = int(floor(wave_data.b * 8.0 + 0.5));
	float t = reduced_motion ? 0.0 : core_time;
	float edge = 1.0 - smoothstep(0.94, 1.0, r);
	float fade = pow(1.0 - age, 1.25);
	float n = noise(p * 7.0 + vec2(phase, -t * 2.4));
	float alpha = 0.0;
	float light = 0.0;
	vec3 color = shell_color.rgb;
	if (mode == 0) {
		// Instant whole-area release; outward movement is decorative only.
		float front = 0.10 + pow(age, 0.55) * 0.85;
		float roll = noise(vec2(angle * 5.0 + phase, r * 9.0 - t * 5.0));
		float rim = exp(-pow((r - front - (roll - 0.5) * 0.075) * 25.0, 2.0));
		float tongues = pow(max(sin(angle * 11.0 + phase + roll * 4.0 - t * 2.0), 0.0), 4.0);
		float whole = (0.10 + n * 0.12) * (1.0 - smoothstep(0.0, 0.15, age));
		float fringe = exp(-pow((r - front + 0.055) * 16.0, 2.0)) * smoothstep(0.22, 0.78, roll);
		alpha = (rim * (0.40 + tongues * 0.40) + fringe * 0.32 + whole) * fade;
		light = (rim * 0.08 + whole * 0.10) * fade;
		color = mix(shell_color.rgb, energy_color.rgb, rim * (0.50 + tongues * 0.25));
		color = mix(color, core_color.rgb, rim * tongues * 0.20);
	} else if (mode == 1) {
		float core = exp(-dot(p, p) * mix(3.0, 14.0, age));
		float curl = pow(max(sin(angle * 3.0 + phase + r * 9.0 - t * 3.0), 0.0), 5.0) * (1.0 - r);
		alpha = (core * 0.42 + curl * 0.28) * (0.15 + age * 0.85);
		light = core * age * 0.08;
		color = mix(shell_color.rgb, energy_color.rgb, core * age);
	} else if (mode == 2 || mode == 6) {
		vec2 q = p / vec2(0.38 + n * 0.15, 0.66);
		float flame = exp(-dot(q, q) * 1.8) * smoothstep(0.18, 0.72, n);
		float flash = exp(-dot(p, p) * 12.0) * (1.0 - smoothstep(0.02, 0.32, age));
		alpha = (flame * 0.64 + flash * 0.78) * fade;
		light = flash * 0.12 * fade;
		color = mix(shell_color.rgb, core_color.rgb, flash * 0.70);
		if (mode == 6) { alpha *= 0.68; light *= 0.6; }
	} else if (mode == 3) {
		// Broken warm traces at a slowed actor, never an icy/full damage ring.
		float marks = pow(max(sin(angle * 5.0 + phase), 0.0), 10.0);
		float arc = exp(-pow((r - 0.62 - n * 0.08) * 20.0, 2.0));
		alpha = arc * marks * 0.65;
		light = alpha * 0.015;
		color = mix(edge_color.rgb, ember_color.rgb, 0.62);
	} else if (mode == 4) {
		// UV +X is the actual movement direction; flecks stream backwards.
		float envelope = smoothstep(-1.0, -0.65, p.x) * (1.0 - smoothstep(0.05, 0.45, p.x));
		float width = mix(0.07, 0.15, smoothstep(-0.85, 0.3, p.x));
		for (int i = 0; i < 3; i++) {
			float lane = (float(i) - 1.0) * 0.22;
			float streak = exp(-pow((p.y - lane + sin(p.x * 4.0 + phase - t * 6.0) * 0.05) / width, 2.0));
			float flow = 0.32 + 0.68 * smoothstep(-0.25, 0.75, sin(p.x * 13.0 + t * 12.0 + phase + float(i) * 2.0));
			alpha += streak * flow * envelope * 0.28;
		}
		light = alpha * 0.035;
		color = mix(ember_color.rgb, energy_color.rgb, 0.28);
	} else {
		for (int i = 0; i < 5; i++) {
			float a = float(i) * 2.39996 + phase;
			vec2 at = vec2(cos(a), sin(a)) * (0.26 + (mode == 7 ? age * 0.34 : 0.02));
			vec2 q = (p - at) / vec2(0.035, 0.025);
			float flicker = reduced_motion ? 0.60 : 0.40 + 0.30 * sin(t * 3.0 + float(i));
			alpha += exp(-dot(q, q)) * (mode == 7 ? fade : flicker);
		}
		light = alpha * 0.035;
		color = mix(ember_color.rgb, edge_color.rgb, mode == 7 ? age : 0.25);
	}
	float strength = wave_data.a * edge;
	alpha = clamp(alpha, 0.0, 0.94) * strength;
	COLOR = vec4(color * alpha + energy_color.rgb * light * strength, alpha);
}
