shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec4 ember_color : source_color;
varying vec4 blast_data;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() { blast_data = INSTANCE_CUSTOM; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float age = clamp(blast_data.g, 0.0, 1.0);
	float phase = blast_data.r * 6.283185;
	int mode = int(floor(blast_data.b * 8.0 + 0.5));
	float t = reduced_motion ? 0.0 : core_time;
	float edge = 1.0 - smoothstep(0.94, 1.0, r);
	float fade = pow(1.0 - age, 1.5);
	float n = noise(p * 6.0 + vec2(phase, -t * 1.5));
	float alpha = 0.0;
	float light = 0.0;
	vec3 color = shell_color.rgb;
	if (mode == 0 || mode == 7) {
		float core = exp(-dot(p, p) * (mode == 0 ? mix(3.0, 15.0, age) : 12.0));
		float curls = pow(max(sin(angle * 3.0 + phase + r * 8.0 - t * 3.0), 0.0), 5.0) * (1.0 - r);
		float strength = mode == 0 ? 0.2 + age * 0.8 : fade;
		alpha = (core * 0.64 + curls * 0.38) * strength;
		light = core * strength * 0.16;
		color = mix(energy_color.rgb, core_color.rgb, core * age);
	} else if (mode == 1) {
		// The mesh is the actual inner damage radius, not a second hit.
		float flash = exp(-dot(p, p) * 4.8) * (1.0 - smoothstep(0.02, 0.24, age));
		float fire = smoothstep(0.24, 0.70, n) * (1.0 - smoothstep(0.50, 1.0, r));
		float tongues = pow(max(sin(angle * 7.0 + phase - t * 3.0 + r * 5.0), 0.0), 4.0);
		alpha = (flash * 0.96 + fire * (0.48 + tongues * 0.38)) * fade;
		light = flash * 0.28 * fade + fire * 0.06 * fade;
		color = mix(shell_color.rgb, energy_color.rgb, fire);
		color = mix(color, core_color.rgb, flash);
	} else if (mode == 2 || mode == 3) {
		// Outward fire is decorative: all authoritative area hits already ran.
		float wave_radius = 0.10 + pow(age, 0.42) * 0.82;
		float rim = exp(-pow((r - wave_radius - (n - 0.5) * 0.09) * 22.0, 2.0));
		float tongues = pow(max(sin(angle * 10.0 + phase + r * 5.0 - t * 2.5), 0.0), 4.0);
		float warmth = exp(-dot(p, p) * 1.8) * (1.0 - smoothstep(0.02, 0.18, age)) * 0.14;
		float sparks = 0.0;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 2.39996 + phase;
			vec2 at = vec2(cos(a), sin(a)) * age * (0.60 + hash(vec2(float(i), phase)) * 0.30);
			vec2 q = (p - at) / vec2(0.025, 0.04);
			sparks += exp(-dot(q, q));
		}
		alpha = (rim * (0.52 + tongues * 0.35) + warmth + sparks * (reduced_motion ? 0.0 : 0.5)) * fade;
		light = (rim * 0.09 + warmth * 0.08) * fade;
		color = mix(shell_color.rgb, energy_color.rgb, clamp(rim * 0.65 + warmth, 0.0, 1.0));
		if (mode == 3) { alpha *= 0.64; light *= 0.45; color = mix(ember_color.rgb, shell_color.rgb, rim); }
	} else if (mode == 4 || mode == 5) {
		// Target-local fuel discharge/reignite has no radial area footprint.
		vec2 q = (p - vec2(0.0, -age * 0.20)) / vec2(0.30 + n * 0.12, 0.64);
		float flame = exp(-dot(q, q) * 1.6) * smoothstep(0.16, 0.74, n);
		float flash = exp(-pow(p.x / 0.22, 2.0) - pow(p.y / 0.42, 2.0)) * (1.0 - smoothstep(0.02, 0.35, age));
		alpha = (flame * 0.75 + flash * 0.88) * fade;
		light = flash * 0.20 * fade;
		color = mix(shell_color.rgb, core_color.rgb, flash);
		if (mode == 5) { alpha *= 0.66; light *= 0.55; }
	} else {
		for (int i = 0; i < 5; i++) {
			float a = float(i) * 2.39996 + phase;
			vec2 at = vec2(cos(a), sin(a)) * (0.18 + age * 0.40);
			at.y -= age * 0.18;
			vec2 q = (p - at) / vec2(0.045, 0.025);
			alpha += exp(-dot(q, q)) * fade;
		}
		light = alpha * 0.08;
		color = mix(ember_color.rgb, edge_color.rgb, age);
	}
	float strength = blast_data.a * edge;
	alpha = clamp(alpha, 0.0, 0.94) * strength;
	COLOR = vec4(color * alpha + energy_color.rgb * light * strength, alpha);
}
