shader_type canvas_item;
render_mode unshaded, blend_mix;

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
uniform float warp_amount;
varying vec4 missile_data;

void vertex() {
	missile_data = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * quad_radii;
	float phase = missile_data.x * 6.283185;
	float t = reduced_motion ? 0.0 : core_time * flow_speed;
	// Concentration at the real projectile center, pulled energy behind it.
	// No sphere normal, specular highlight or opaque gemstone surface.
	float x_axis = body_axes.x * (p.x < 0.0 ? rear_stretch : 1.0);
	float rear_width = mix(0.52, 1.0, smoothstep(-body_axes.x * rear_stretch, -0.2, p.x));
	vec2 q = vec2(p.x / x_axis, p.y / (body_axes.y * rear_width));
	float rear = 1.0 - smoothstep(-0.2, 0.55, p.x);
	float bend = sin(p.x * 2.8 + t + phase) * sin(p.y * 3.3 + phase);
	float d = length(q) + warp_amount * bend * rear;
	float aa = max(fwidth(d), 0.035);
	float mask = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
	// Broad streams survive the normal gameplay pixel size.
	float c1 = sin(p.x * 2.4 + t + phase) * 0.22;
	float c2 = sin(p.x * 1.8 + t * 0.85 + phase + 2.5) * 0.34;
	float band1 = exp(-pow((p.y - c1) / 0.19, 2.0));
	float band2 = exp(-pow((p.y - c2) / 0.14, 2.0)) * 0.62;
	float flow = clamp(band1 + band2, 0.0, 1.0);
	vec2 nucleus = (p - vec2(0.08, 0.0)) / core_axes;
	float core = exp(-dot(nucleus, nucleus) * 1.6);
	float jet = exp(-pow((p.y + sin(p.x * 2.0 + phase) * 0.035) / 0.18, 2.0))
		* smoothstep(-1.05, -0.48, p.x) * (1.0 - smoothstep(0.42, 0.95, p.x));
	vec3 color = mix(shell_color.rgb, energy_color.rgb, flow * 0.72);
	color = mix(color, core_color.rgb, clamp(core + jet * 0.82, 0.0, 1.0));
	float separation = smoothstep(0.72, 1.0, d) * (1.0 - flow) * 0.25;
	color = mix(color, edge_color.rgb, separation);
	float opacity = mask * clamp(0.14 + flow * 0.46 + core * 0.88 + jet * 0.40, 0.0, 0.96);
	COLOR = vec4(color, opacity * missile_data.a);
}
