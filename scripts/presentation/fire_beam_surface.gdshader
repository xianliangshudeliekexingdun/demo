shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec4 ember_color : source_color;
varying vec4 feedback_data;

void vertex() { feedback_data = INSTANCE_CUSTOM; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float age = clamp(feedback_data.g, 0.0, 1.0);
	float phase = feedback_data.r * 6.283185;
	int mode = int(floor(feedback_data.b * 8.0 + 0.5));
	float t = reduced_motion ? 0.0 : core_time;
	float fade = pow(1.0 - age, 1.6);
	float edge = 1.0 - smoothstep(0.88, 1.0, max(abs(p.x), abs(p.y)));
	float alpha = 0.0;
	float light = 0.0;
	vec3 color = shell_color.rgb;
	if (mode == 0 || mode == 1) {
		float focus = mode == 0 ? mix(2.5, 12.0, age) : mix(12.0, 5.0, age);
		float core = exp(-dot(p, p) * focus);
		float curl = 0.0;
		for (int i = 0; i < 3; i++) {
			float a = float(i) * 2.0944 + phase + t * 1.8;
			vec2 at = vec2(cos(a), sin(a)) * (mode == 0 ? (1.0 - age) * 0.65 : age * 0.45);
			vec2 q = (p - at) / vec2(0.13, 0.22);
			curl += exp(-dot(q, q));
		}
		float strength = mode == 0 ? 0.2 + age * 0.8 : fade;
		alpha = (core * 0.65 + curl * 0.34) * strength;
		light = core * 0.14 * strength;
		color = mix(energy_color.rgb, core_color.rgb, core);
	} else if (mode == 2 || mode == 4) {
		// Local directional hot cut, never an expanding area explosion.
		float flash = exp(-pow(p.x / 0.48, 2.0) - pow(p.y / 0.20, 2.0)) * (1.0 - smoothstep(0.0, 0.4, age));
		float tongue = exp(-pow((p.y + sin(p.x * 7.0 - t * 9.0 + phase) * 0.12) / 0.18, 2.0));
		tongue *= 1.0 - smoothstep(0.15, 0.95, abs(p.x - age * 0.15));
		float sparks = 0.0;
		for (int i = 0; i < 4; i++) {
			float side = mod(float(i), 2.0) * 2.0 - 1.0;
			vec2 at = vec2(side * age * (0.4 + float(i) * 0.12), sin(phase + float(i) * 2.1) * age * 0.4);
			vec2 q = (p - at) / vec2(0.065, 0.025);
			sparks += exp(-dot(q, q));
		}
		alpha = (flash * 0.85 + tongue * 0.5 + sparks * (reduced_motion ? 0.0 : 0.5)) * fade;
		light = flash * 0.18 * fade;
		color = mix(shell_color.rgb, core_color.rgb, flash);
		if (mode == 4) { alpha *= 0.65; light *= 0.5; }
	} else {
		for (int i = 0; i < 5; i++) {
			float k = float(i) - 2.0;
			vec2 at = vec2(k * (0.14 + age * 0.12), sin(phase + k * 1.8) * 0.22 - age * 0.16);
			vec2 q = (p - at) / vec2(0.055, 0.025);
			alpha += exp(-dot(q, q)) * fade;
		}
		light = alpha * 0.07;
		color = mix(ember_color.rgb, edge_color.rgb, age);
	}
	float strength = feedback_data.a * edge;
	alpha = clamp(alpha, 0.0, 0.94) * strength;
	COLOR = vec4(color * alpha + energy_color.rgb * light * strength, alpha);
}
