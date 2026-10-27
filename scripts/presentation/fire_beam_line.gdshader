shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform float flow_speed;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
varying vec4 beam_data;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() { beam_data = COLOR; }
void fragment() {
	float u = UV.x;
	float y = UV.y * 2.0 - 1.0;
	float age = clamp(beam_data.g, 0.0, 1.0);
	int mode = int(floor(beam_data.b * 8.0 + 0.5));
	bool paired = mode >= 6;
	bool echo = mode == 2 || mode == 3;
	float phase = beam_data.r * 6.283185 + (echo ? 1.8 : 0.0);
	float t = reduced_motion ? 0.0 : core_time * flow_speed;
	float narrowing = smoothstep(0.40, 1.0, age);
	float width = mix(0.96, 0.10, narrowing);
	float n = noise(vec2(u * 20.0 - t * 2.1, y * 4.2 + phase));
	float curl = sin(u * 19.0 - t * 3.5 + phase) * 0.09;
	float shell = 1.0 - smoothstep(width * 0.56, width, abs(y + curl * (0.4 + n * 0.6)));
	float flow1 = exp(-pow((y - sin(u * 24.0 - t * 5.0 + phase) * width * 0.36) / max(0.04, width * 0.18), 2.0));
	float flow2 = exp(-pow((y + sin(u * 31.0 - t * 4.0 + phase) * width * 0.42) / max(0.025, width * 0.12), 2.0));
	float core_width = mix(0.13, 0.028, narrowing);
	float core = exp(-pow(y / core_width, 2.0));
	if (paired) {
		// Two distinct hot streams stay inside the same real beam footprint.
		float lane = 0.17 * (1.0 - narrowing);
		core = max(exp(-pow((y - lane) / (core_width * 0.65), 2.0)), exp(-pow((y + lane) / (core_width * 0.65), 2.0)));
		flow2 = max(flow2, exp(-pow((y - sin(u * 27.0 - t * 4.5 + phase + 2.3) * width * 0.30) / max(0.025, width * 0.13), 2.0)));
	}
	float end_caps = smoothstep(0.0, 0.025, u) * (1.0 - smoothstep(0.975, 1.0, u));
	float boundary = 1.0 - smoothstep(0.94, 1.0, abs(y));
	float fade = 1.0 - smoothstep(0.50, 1.0, age);
	float flash = 1.0 - smoothstep(0.02, 0.18, age);
	float torn = mix(1.0, smoothstep(0.28, 0.69, n), narrowing * 0.65);
	float alpha = (shell * (0.25 + flow1 * 0.20 + flow2 * 0.17) * torn + core * (0.65 + flash * 0.20)) * fade;
	float light = (core * 0.14 + shell * flow1 * 0.05) * fade;
	vec3 color = mix(shell_color.rgb, energy_color.rgb, clamp(flow1 * 0.55 + flow2 * 0.32, 0.0, 1.0));
	color = mix(color, core_color.rgb, core * 0.96);
	color = mix(color, edge_color.rgb, smoothstep(width * 0.62, width, abs(y)) * 0.45);
	float strength = beam_data.a * end_caps * boundary;
	alpha = clamp(alpha, 0.0, 0.94) * strength;
	COLOR = vec4(color * alpha + energy_color.rgb * light * strength, alpha);
}
