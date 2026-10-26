shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform float tail_alpha;
varying vec4 trail_data;

void vertex() {
	trail_data = COLOR;
}
void fragment() {
	float u = UV.x;
	float y = UV.y * 2.0 - 1.0;
	float t = reduced_motion ? 0.0 : core_time;
	float phase = trail_data.r * 6.283185;
	float curl = sin(u * 10.0 - t * 14.0 + phase) * 0.20 + sin(u * 19.0 - t * 9.0 + phase) * 0.08;
	float side = 1.0 - smoothstep(0.55, 1.0, abs(y + curl * u));
	float flow1 = exp(-pow((y - sin(u * 8.0 - t * 12.0 + phase) * 0.40) / 0.25, 2.0));
	float flow2 = exp(-pow((y + sin(u * 13.0 - t * 10.0 + phase) * 0.43) / 0.16, 2.0));
	float spine = exp(-pow(y / 0.28, 2.0));
	float breaks = mix(1.0, smoothstep(-0.5, 0.55, sin(u * 21.0 - t * 11.0 + phase)), smoothstep(0.25, 0.9, u) * 0.7);
	float end_fade = 1.0 - smoothstep(0.58, 1.0, u);
	float envelope = side * end_fade * trail_data.a;
	float alpha = tail_alpha * envelope * (0.20 + flow1 * 0.38 + flow2 * 0.20) * breaks;
	float light = (spine * 0.16 + flow1 * 0.20 + flow2 * 0.13) * envelope * breaks;
	vec3 color = mix(shell_color.rgb, energy_color.rgb, clamp(flow1 * 0.65 + spine * 0.25, 0.0, 1.0));
	color = mix(color, edge_color.rgb, smoothstep(0.50, 1.0, abs(y)) * 0.45);
	COLOR = vec4(color * alpha + energy_color.rgb * light, alpha);
}
