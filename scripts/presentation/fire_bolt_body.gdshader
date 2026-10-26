shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec2 body_axes;
uniform vec2 core_axes;
uniform float rear_stretch;
uniform float quad_radii;
uniform float flow_speed;
varying vec4 fire_data;

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
	fire_data = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 p = (UV - vec2(0.5)) * quad_radii;
	float phase = fire_data.x * 6.283185;
	float t = reduced_motion ? 0.0 : core_time * flow_speed;
	bool upright = fire_data.b > 0.5;
	float stretch = upright ? rear_stretch : mix(1.25, rear_stretch, fire_data.g);
	float along = upright ? -p.x : p.x;
	float rear = 1.0 - smoothstep(-0.75, 0.25, along);
	float n1 = noise(vec2(along * 2.3 + t * 1.7, p.y * 3.1 + phase));
	float n2 = noise(vec2(along * 4.8 + t * 2.4, p.y * 5.0 - phase));
	float width = body_axes.y * mix(0.24, 1.0, smoothstep(-body_axes.x * stretch, -0.1, along));
	float bend = sin(along * 2.6 + t + phase) * 0.13 * rear;
	float axis_x = body_axes.x * (along < 0.0 ? stretch : 1.0);
	float d = length(vec2(along / axis_x, (p.y + bend) / max(width, 0.05)));
	d += (n1 - 0.48) * (0.12 + 0.48 * rear);
	float aa = max(fwidth(d), 0.045);
	float shell = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
	// Three irregular tongues split away from the trailing edge; broad flow
	// survives gameplay size without a static cone, sphere highlight or flicker.
	float tongue = 0.0;
	for (int i = 0; i < 3; i++) {
		float k = float(i) - 1.0;
		float lane = k * (0.20 + rear * 0.12) + sin(along * 2.1 + t + phase + k * 2.2) * 0.13;
		float stream = exp(-pow((p.y - lane) / (0.10 + 0.10 * n1), 2.0));
		float tip = -2.3 - sin(t * 0.8 + phase + k * 1.8) * 0.35;
		tongue += stream * smoothstep(tip - 0.25, tip + 0.35, along) * (1.0 - smoothstep(-0.5, 0.35, along));
	}
	float tear = smoothstep(0.23, 0.64, n2 + rear * 0.10);
	float flame = max(shell * mix(1.0, tear, rear * 0.65), tongue * rear * 0.72);
	vec2 nucleus = (vec2(along, p.y) - vec2(0.12, 0.0)) / core_axes;
	float hot = exp(-dot(nucleus, nucleus) * 1.9);
	float stream = exp(-pow((p.y + bend) / 0.20, 2.0)) * shell;
	float heat = clamp(stream * 0.60 + n1 * 0.35 + hot, 0.0, 1.0);
	vec3 color = mix(shell_color.rgb, energy_color.rgb, heat);
	color = mix(color, core_color.rgb, hot * 0.95);
	float rim = smoothstep(0.72, 1.04, d) * (1.0 - hot) * 0.62;
	color = mix(color, edge_color.rgb, rim);
	float edge = 1.0 - smoothstep(0.88, 1.0, max(abs(UV.x * 2.0 - 1.0), abs(UV.y * 2.0 - 1.0)));
	float alpha = clamp(flame * (0.48 + heat * 0.43) + hot * 0.2, 0.0, 0.96) * fire_data.a * edge;
	float light = flame * (stream * 0.20 + hot * 0.24) * fire_data.a * edge;
	COLOR = vec4(color * alpha + energy_color.rgb * light, alpha);
}
