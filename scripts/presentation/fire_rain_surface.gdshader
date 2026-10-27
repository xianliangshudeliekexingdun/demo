shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec4 ember_color : source_color;
varying vec4 rain_data;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() {
	rain_data = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float phase = rain_data.r * 6.283185;
	float age = clamp(rain_data.g, 0.0, 1.0);
	int mode = int(floor(rain_data.b * 8.0 + 0.5));
	float t = reduced_motion ? 0.0 : core_time;
	float edge = 1.0 - smoothstep(0.96, 1.0, r);
	float alpha = 0.0;
	float light = 0.0;
	vec3 color = shell_color.rgb;
	if (mode == 0) {
		// A sparse, stable perimeter: the mesh is the authoritative rain radius.
		float broken = smoothstep(-0.35, 0.25, sin(angle * 11.0 + phase));
		float rim = exp(-pow((r - 0.94) * 38.0, 2.0)) * (0.18 + 0.82 * broken);
		float warmth = smoothstep(0.55, 0.88, noise(p * 5.0 + phase)) * (1.0 - r) * 0.12;
		alpha = rim * 0.58 + warmth;
		light = rim * 0.06;
	} else if (mode == 1 || mode == 5) {
		// One actual landing: compact white heat, upward fire and a low fire lip.
		float fade = pow(1.0 - age, 1.6);
		float flash = exp(-dot(p, p) * 23.0) * (1.0 - smoothstep(0.02, 0.24, age));
		float n = noise(p * 5.5 + vec2(phase, -t * 1.9));
		float lip_radius = 0.18 + sqrt(age) * 0.72;
		float lip = exp(-pow((r - lip_radius - (n - 0.5) * 0.10) * 19.0, 2.0));
		float tongues = pow(max(sin(angle * 7.0 + phase - t * 2.1 + r * 6.0), 0.0), 4.0);
		float sparks = 0.0;
		for (int i = 0; i < 6; i++) {
			float a = float(i) * 2.39996 + phase;
			vec2 at = vec2(cos(a), sin(a)) * age * (0.50 + hash(vec2(float(i), phase)) * 0.35);
			vec2 q = (p - at) / vec2(0.025, 0.045);
			sparks += exp(-dot(q, q)) * fade;
		}
		alpha = flash * 0.92 + lip * (0.47 + tongues * 0.35) * fade + sparks * (reduced_motion ? 0.0 : 0.52);
		light = flash * 0.22 + lip * fade * 0.07;
		color = mix(shell_color.rgb, energy_color.rgb, clamp(lip + sparks * 0.5, 0.0, 1.0));
		color = mix(color, core_color.rgb, flash);
		if (mode == 5) { alpha *= 0.62; light *= 0.5; }
	} else if (mode == 2) {
		// Low, broken coals. Cooling affects the interior, never the live radius.
		float n = noise(p * 5.8 + vec2(phase, -t * 0.18));
		float pockets = smoothstep(0.44, 0.81, n);
		float veins = pow(1.0 - abs(sin(n * 18.0 + r * 3.0)), 12.0);
		float heat = (pockets * 0.19 + veins * 0.23) * (1.0 - age * 0.70);
		float rim = exp(-pow((r - 0.94) * 39.0, 2.0)) * (0.25 + pockets * 0.75);
		alpha = heat + rim * 0.30;
		light = veins * 0.06 * (1.0 - age * 0.8) + rim * 0.035;
		color = mix(edge_color.rgb, shell_color.rgb, clamp(pockets + veins * 0.50, 0.0, 1.0));
	} else if (mode == 4 || mode == 6) {
		float ring_radius = mode == 4 ? mix(0.76, 0.26, age) : mix(0.18, 0.76, age);
		float ring = exp(-pow((r - ring_radius) * 24.0, 2.0));
		float curls = pow(max(sin(angle * 3.0 - t * 4.0 + phase + r * 7.0), 0.0), 5.0);
		float core = exp(-dot(p, p) * 20.0) * (mode == 4 ? age : 1.0 - age);
		float fade = mode == 4 ? 0.3 + age * 0.7 : pow(1.0 - age, 1.3);
		alpha = (ring * 0.24 + curls * (1.0 - r) * 0.20 + core * 0.48) * fade;
		light = core * 0.12 * fade;
		color = mix(energy_color.rgb, core_color.rgb, core);
	} else {
		// Cooling and detached embers have no area ring or renewed fire surface.
		float fade = pow(1.0 - age, 1.8);
		for (int i = 0; i < 5; i++) {
			float a = float(i) * 2.39996 + phase;
			vec2 at = vec2(cos(a), sin(a)) * (0.18 + age * 0.42);
			at.y -= age * 0.20;
			vec2 q = (p - at) / vec2(0.025, 0.045 - age * 0.02);
			alpha += exp(-dot(q, q)) * fade;
		}
		light = alpha * 0.10;
		color = mix(ember_color.rgb, edge_color.rgb, age);
	}
	float strength = rain_data.a * edge;
	alpha = clamp(alpha, 0.0, 0.94) * strength;
	COLOR = vec4(color * alpha + energy_color.rgb * light * strength, alpha);
}
