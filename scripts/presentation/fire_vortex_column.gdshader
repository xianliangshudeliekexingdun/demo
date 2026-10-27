shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform float flow_speed;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec2 body_axes;
uniform vec2 core_axes;
uniform float rear_stretch;
uniform float quad_radii;
uniform float interior_flame_light_boost;
varying vec4 column_data;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() { column_data = COLOR; }
vec4 interior_flame(vec2 uv, vec4 fire_data) {
	vec2 p = (uv - vec2(0.5)) * quad_radii;
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
	float edge = 1.0 - smoothstep(0.88, 1.0, max(abs(uv.x * 2.0 - 1.0), abs(uv.y * 2.0 - 1.0)));
	float alpha = clamp(flame * (0.48 + heat * 0.43) + hot * 0.2, 0.0, 0.96) * fire_data.a * edge;
	float light = flame * (stream * 0.20 + hot * 0.24) * fire_data.a * edge;
	return vec4(color * alpha + energy_color.rgb * light, alpha);
}
void fragment() {
	if (column_data.g > 0.9) {
		vec4 flame = interior_flame(UV, column_data);
		COLOR = vec4(flame.rgb * interior_flame_light_boost, flame.a);
	} else {
		float v = clamp(UV.y, 0.0, 1.0);
		float phase = column_data.r * 6.283185;
		bool inner = column_data.g > 0.45;
		bool hold = mod(column_data.g, 0.5) > 0.12;
		float t = reduced_motion ? 0.0 : core_time * flow_speed * (hold ? 0.82 : 1.0);
		float a = UV.x * 6.283185 + v * 6.4 - t * 0.72 + phase + (inner ? 1.7 : 0.0);
		// Broad advected plumes carry the turn; no luminous wire-like helix outlines.
		vec2 around = vec2(cos(a), sin(a));
		float warp = noise(around * 1.7 + vec2(v * 3.2, -t * 0.65));
		vec2 rolling = vec2(cos(a + warp * 1.5), sin(a + warp * 1.5));
		float billow = noise(rolling * 3.0 + vec2(v * 5.5 - t * 1.1, phase));
		float fine = noise(rolling * 6.5 + vec2(v * 11.0 - t * 1.7, phase * 2.0));
		float fuel = warp * 0.34 + billow * 0.48 + fine * 0.18;
		float turn = 0.5 + 0.5 * sin(a * 2.0 - v * 6.0 + warp * 4.0 + billow * 1.3);
		float plume = smoothstep(0.22, 0.80, fuel * 0.72 + turn * 0.28);
		float torn_top = 0.72 + noise(vec2(cos(a) * 4.0, sin(a) * 4.0 - t * 0.55)) * 0.26;
		float top = 1.0 - smoothstep(torn_top - 0.17, torn_top, v);
		float foot = smoothstep(0.0, 0.065, v);
		float body = 0.48 + plume * 0.52;
		float gaps = mix(0.68, 1.0, smoothstep(0.12, 0.50, fuel + turn * 0.10));
		float alpha = body * gaps * top * foot * column_data.a;
		float heat = clamp(smoothstep(0.34, 0.88, fuel + turn * 0.09) + (1.0 - v) * 0.10 + (inner ? 0.10 : 0.0), 0.0, 1.0);
		vec3 color = mix(edge_color.rgb, shell_color.rgb, 0.78 + column_data.b * 0.18);
		color = mix(color, energy_color.rgb, heat * 0.84);
		color = mix(color, core_color.rgb, pow(heat, 5.0) * (inner ? 0.14 : 0.07));
		float light = heat * heat * 0.035 * top * foot * column_data.a;
		alpha = clamp(alpha, 0.0, 0.89);
		COLOR = vec4(color * alpha + energy_color.rgb * light, alpha);
	}
}
