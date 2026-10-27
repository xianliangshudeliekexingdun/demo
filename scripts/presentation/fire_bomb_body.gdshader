shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform float quad_radii;
uniform float flow_speed;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
varying vec4 molten_data;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() { molten_data = INSTANCE_CUSTOM; }
void fragment() {
	vec2 p = (UV - vec2(0.5)) * quad_radii;
	float phase = molten_data.r * 6.283185;
	float t = reduced_motion ? 0.0 : core_time * flow_speed;
	bool upright = molten_data.b > 0.5;
	float n = noise(p * 3.4 + vec2(t * 0.30, phase));
	float alpha = 0.0;
	float light = 0.0;
	vec3 color = shell_color.rgb;
	if (upright) {
		float along = -p.x;
		float rear = 1.0 - smoothstep(-0.6, 0.2, along);
		float width = mix(0.18, 0.68, smoothstep(-2.0, -0.05, along));
		float d = length(vec2(along / (along < 0.0 ? 2.0 : 0.65), (p.y + sin(along * 3.0 + t + phase) * 0.14 * rear) / width));
		d += (n - 0.45) * (0.18 + rear * 0.65);
		float shell = 1.0 - smoothstep(0.88, 1.06, d);
		float core = exp(-pow(along / 0.38, 2.0) - pow(p.y / 0.25, 2.0));
		alpha = shell * mix(0.90, smoothstep(0.20, 0.65, n), rear * 0.70) + core * 0.18;
		light = core * 0.17 + shell * 0.05;
		color = mix(shell_color.rgb, energy_color.rgb, clamp(n * 0.7 + core, 0.0, 1.0));
		color = mix(color, core_color.rgb, core * 0.75);
	} else {
		// Compact molten mass, rolling hot veins and a short torn flame collar.
		float d = length(p / vec2(1.0, 0.88)) + (n - 0.5) * 0.14;
		float shell = 1.0 - smoothstep(0.90, 1.04, d);
		float veins = pow(1.0 - abs(sin(n * 15.0 + p.x * 2.2 - t * 0.8)), 10.0);
		float hot = exp(-dot(p - vec2(0.13, 0.0), p - vec2(0.13, 0.0)) * 7.0);
		float collar = exp(-pow((p.y + sin(p.x * 3.3 + t + phase) * 0.18) / 0.35, 2.0));
		collar *= smoothstep(-2.0, -1.0, p.x) * (1.0 - smoothstep(-0.9, -0.2, p.x));
		alpha = shell * 0.93 + collar * smoothstep(0.18, 0.72, n) * 0.58;
		light = shell * (veins * 0.08 + hot * 0.17);
		color = mix(edge_color.rgb, shell_color.rgb, clamp(0.50 + n * 0.40, 0.0, 1.0));
		color = mix(color, energy_color.rgb, veins * 0.76);
		color = mix(color, core_color.rgb, hot * 0.86);
	}
	float edge = 1.0 - smoothstep(0.88, 1.0, max(abs(UV.x * 2.0 - 1.0), abs(UV.y * 2.0 - 1.0)));
	alpha = clamp(alpha, 0.0, 0.96) * molten_data.a * edge;
	COLOR = vec4(color * alpha + energy_color.rgb * light * molten_data.a * edge, alpha);
}
