shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec4 ember_color : source_color;
varying vec4 surface_data;

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
	surface_data = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float seed = surface_data.r;
	float phase = seed * 6.283185;
	float age = clamp(surface_data.g, 0.0, 1.0);
	int mode = int(floor(surface_data.b * 8.0 + 0.5));
	float t = reduced_motion ? 0.0 : core_time;
	float edge = 1.0 - smoothstep(0.88, 1.0, r);
	float alpha = 0.0;
	float light = 0.0;
	vec3 color = shell_color.rgb;
	if (mode == 0 || mode == 6) {
		// Chant contracts toward the release point; a release opens briefly.
		float ring_radius = mode == 0 ? mix(0.75, 0.28, age) : mix(0.18, 0.78, age);
		float ring = exp(-pow((r - ring_radius) * 22.0, 2.0));
		float curls = pow(max(sin(angle * 3.0 - t * 5.0 + phase + r * 8.0), 0.0), 5.0);
		float core = exp(-dot(p, p) * 18.0) * (mode == 0 ? age : 1.0 - age);
		float fade = mode == 0 ? 0.3 + 0.7 * age : pow(1.0 - age, 1.2);
		alpha = (ring * 0.30 + curls * 0.30 * (1.0 - r) + core * 0.70) * fade;
		light = (ring * 0.25 + core * 0.40) * fade;
		color = mix(energy_color.rgb, core_color.rgb, core);
	} else if (mode == 1 || mode == 2 || mode == 4) {
		float fade = pow(1.0 - age, 1.5);
		float flash = exp(-dot(p, p) * (mode == 1 ? 22.0 : 12.0)) * (1.0 - smoothstep(0.02, 0.32, age));
		float uneven = noise(p * 6.0 + vec2(phase, -t * 2.0));
		float ring_radius = 0.28 + age * 0.56;
		float ring = exp(-pow((r - ring_radius - (uneven - 0.5) * 0.12) * 18.0, 2.0));
		float tongues = pow(max(sin(angle * 7.0 + phase + r * 6.0 - t * 3.0), 0.0), 4.0);
		float side = mode == 2 ? smoothstep(-0.08, 0.15, -p.x) : 1.0;
		float fire = (ring * 0.62 + tongues * ring * 0.52) * fade * side;
		float sparks = 0.0;
		for (int i = 0; i < 7; i++) {
			float a = float(i) * 2.39996 + phase;
			vec2 axis = vec2(cos(a), sin(a));
			if (mode == 2) { axis.x = -abs(axis.x); }
			float distance = age * (0.55 + hash(vec2(float(i), seed)) * 0.36);
			vec2 d = p - axis * distance;
			float along = dot(d, axis) / (0.07 + age * 0.06);
			float across = dot(d, vec2(-axis.y, axis.x)) / 0.024;
			sparks += exp(-along * along - across * across) * fade;
		}
		alpha = fire * 0.73 + flash * 0.82 + sparks * (reduced_motion ? 0.0 : 0.62);
		light = flash * 0.35 + sparks * (reduced_motion ? 0.0 : 0.35) + ring * fade * 0.12;
		color = mix(shell_color.rgb, energy_color.rgb, clamp(fire + sparks, 0.0, 1.0));
		color = mix(color, core_color.rgb, flash);
	} else if (mode == 3) {
		// A low, broken molten footprint. Its mesh is the exact live radius.
		float n = noise(p * 5.8 + vec2(phase, -t * 0.35));
		float cracks = pow(1.0 - abs(sin(n * 18.0 + r * 4.0)), 12.0);
		float pockets = smoothstep(0.42, 0.78, n);
		float rim = exp(-pow((r - 0.92) * 35.0, 2.0)) * (0.30 + 0.70 * pockets);
		alpha = (pockets * 0.18 + cracks * 0.26 + rim * 0.28) * edge;
		light = (cracks * 0.13 + rim * 0.09) * edge;
		color = mix(edge_color.rgb, shell_color.rgb, clamp(pockets + cracks * 0.6, 0.0, 1.0));
	} else {
		// Extinction is scattered cooling embers; no expanding damage ring.
		float fade = pow(1.0 - age, 1.8);
		for (int i = 0; i < 5; i++) {
			float a = float(i) * 2.39996 + phase;
			vec2 at = vec2(cos(a), sin(a)) * (0.15 + age * 0.48);
			at.y -= age * 0.18;
			vec2 q = (p - at) / vec2(0.045, 0.025 + age * 0.015);
			alpha += exp(-dot(q, q)) * fade;
		}
		light = alpha * 0.18;
		color = mix(ember_color.rgb, edge_color.rgb, age);
	}
	float strength = surface_data.a * edge;
	alpha = clamp(alpha, 0.0, 0.94) * strength;
	COLOR = vec4(color * alpha + energy_color.rgb * light * strength, alpha);
}
