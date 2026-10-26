shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform float tail_alpha;
uniform float flow_alpha;
varying vec4 trail_data;

void vertex() {
	trail_data = COLOR;
}

void fragment() {
	float u = UV.x;
	float y = UV.y * 2.0 - 1.0;
	float t = reduced_motion ? 0.0 : core_time;
	float phase = trail_data.r * 6.283185;
	float side = 1.0 - smoothstep(0.55, 1.0, abs(y));
	float spine = exp(-pow(y / 0.28, 2.0));
	float s1 = sin(u * 7.0 - t * 8.0 + phase) * 0.32;
	float s2 = sin(u * 5.3 - t * 6.8 + phase + 2.6) * 0.43;
	float strands = exp(-pow((y - s1) / 0.18, 2.0))
		+ exp(-pow((y - s2) / 0.15, 2.0)) * 0.6;
	// Geometry tapers; alpha stays readable until the last part of the ribbon.
	float end_fade = 1.0 - smoothstep(0.55, 1.0, u);
	float envelope = end_fade * trail_data.a * side;
	float body_alpha = tail_alpha * 0.30 * envelope;
	float emission = (spine * 0.30 + strands * flow_alpha * 0.75) * envelope;
	float packet = 0.72 + 0.28 * sin(u * 11.0 - t * 7.0 + phase);
	vec3 light_color = mix(energy_color.rgb, core_color.rgb, spine * 0.55);
	vec3 base = mix(edge_color.rgb, shell_color.rgb, side * 0.5);
	// Premultiplied base plus light: both vanish at the mesh edge.
	COLOR = vec4(base * body_alpha + light_color * emission * packet, body_alpha);
}
