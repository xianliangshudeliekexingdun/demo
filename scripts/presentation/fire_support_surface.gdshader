shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform float flow_speed;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec4 guard_color : source_color;
varying vec4 support_data;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() { support_data = INSTANCE_CUSTOM; }
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	int mode = int(floor(support_data.b * 8.0 + 0.5));
	float progress = clamp(support_data.g, 0.0, 1.0);
	float t = reduced_motion ? 0.0 : core_time * flow_speed;
	float n = noise(p * 5.0 + vec2(support_data.r * 7.0, -t * 0.60));
	float alpha = 0.0;
	float heat = 0.0;
	vec3 color = guard_color.rgb;
	if (mode == 0) {
		float arcs = exp(-pow((r - 0.64) / 0.045, 2.0)) * smoothstep(-0.3, 0.3, sin(a * 3.0 + support_data.r * 6.28));
		alpha = arcs * 0.55 + exp(-r * r * 14.0) * 0.28;
		heat = 0.28 + n * 0.15;
	} else if (mode == 1) {
		// Only two open side arcs: Lina's face/body and the ground remain clear.
		float d = length(vec2(p.x, p.y * 0.88));
		float side = smoothstep(0.30, 0.52, abs(p.x));
		float ends = 1.0 - smoothstep(0.65, 0.88, abs(p.y));
		float rim = exp(-pow((d - 0.79) / 0.027, 2.0));
		float halo = exp(-pow((d - 0.77) / 0.09, 2.0));
		float inner = exp(-pow((d - 0.67) / 0.020, 2.0)) * 0.30;
		float light = 0.68 + 0.32 * sin(a * 4.0 - t * 0.60 + n * 1.3);
		alpha = (rim * light + halo * 0.21 + inner * support_data.r) * side * ends;
		heat = clamp(rim * (0.55 + support_data.r * 0.25), 0.0, 1.0);
	} else if (mode == 2) {
		float arc = exp(-pow((r - 0.69) / 0.025, 2.0)) * smoothstep(-0.15, 0.30, cos(a * 3.0));
		float along = (p.y + 0.02) / 0.43;
		float seal = exp(-pow(p.x / (0.11 + max(0.0, p.y) * 0.13), 2.0)) * exp(-along * along * along * along);
		float ranks = exp(-pow((r - 0.42) / 0.038, 2.0)) * pow(max(0.0, cos(a * (1.0 + support_data.r * 2.0))), 16.0);
		alpha = arc * 0.40 + seal * 0.52 + ranks * 0.40;
		color = mix(shell_color.rgb, energy_color.rgb, 0.65);
		heat = clamp(seal * 0.50 + ranks * 0.32, 0.0, 1.0);
	} else {
		vec2 point = vec2(p.x / 0.34, (p.y + 0.14) / 0.42);
		float hot = exp(-dot(point, point) * 2.0);
		float tail = exp(-pow(p.x / 0.17, 2.0)) * smoothstep(-0.15, 0.20, p.y) * (1.0 - smoothstep(0.45, 0.92, p.y));
		alpha = hot * 0.90 + tail * 0.30;
		heat = hot * 0.90;
	}
	color = mix(color, core_color.rgb, heat * 0.64);
	float cut = 1.0 - smoothstep(0.94, 1.0, max(abs(p.x), abs(p.y)));
	alpha = clamp(alpha * support_data.a * cut, 0.0, 0.92);
	COLOR = vec4(color * alpha + energy_color.rgb * heat * alpha * 0.07, alpha);
}
