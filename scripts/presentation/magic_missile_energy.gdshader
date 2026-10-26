shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform vec4 glow_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform float halo_alpha;
uniform float aura_quad_radii;
uniform float aura_filament_alpha;
varying vec4 energy_data;

void vertex() {
	energy_data = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 uvp = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.78, 1.0, length(uvp));
	float seed = energy_data.x;
	float phase = seed * 6.283185;
	float t = reduced_motion ? 0.0 : core_time;
	vec3 col = glow_color.rgb;
	float alpha = 0.0;
	if (energy_data.z < 0.5) {
		vec2 p = (UV - vec2(0.5)) * aura_quad_radii;
		vec2 scatter_p = (p + vec2(0.45, 0.0)) / vec2(1.85, 1.05);
		float scatter = exp(-dot(scatter_p, scatter_p) * 1.9) * halo_alpha;
		float along = smoothstep(-2.75, -2.10, p.x) * (1.0 - smoothstep(0.65, 1.35, p.x));
		float bow = smoothstep(-2.75, -0.55, p.x) * (1.0 - smoothstep(0.15, 1.30, p.x));
		float c1 = bow * (0.50 + sin(p.x * 2.1 + t * 2.2 + phase) * 0.14);
		float c2 = -bow * (0.39 + sin(p.x * 1.7 + t * 1.9 + phase + 2.4) * 0.12);
		float arcs = exp(-pow((p.y - c1) / 0.14, 2.0))
			+ exp(-pow((p.y - c2) / 0.12, 2.0)) * 0.65;
		float packet = 0.65 + 0.35 * sin(p.x * 4.0 + t * 6.0 + phase);
		float stream = arcs * along * packet * aura_filament_alpha;
		float motes = 0.0;
		if (!reduced_motion) {
			for (int i = 0; i < 2; i++) {
				float life = fract(t * 0.9 + seed + float(i) * 0.5);
				vec2 center = vec2(0.2 - life * 2.4, sin(phase + float(i) * 2.8) * (0.25 + life * 0.2));
				vec2 q = (p - center) / vec2(0.16, 0.075);
				motes += exp(-dot(q, q)) * sin(life * 3.141593) * 0.24;
			}
		}
		alpha = (scatter + stream + motes) * edge;
		col = mix(glow_color.rgb, energy_color.rgb, clamp((stream + motes) * 2.0, 0.0, 0.85));
	} else {
		vec2 p = uvp;
		float r = length(p);
		float age = clamp(energy_data.y, 0.0, 1.0);
		float fade = pow(1.0 - age, 1.5);
		float flash = exp(-dot(p, p) * 16.0) * (1.0 - smoothstep(0.04, 0.32, age));
		float flecks = 0.0;
		for (int i = 0; i < 5; i++) {
			float a = 3.141593 + (float(i) / 4.0 - 0.5) * 2.6 + (seed - 0.5) * 0.3;
			vec2 axis = vec2(cos(a), sin(a));
			float travel = age * (0.52 + float(i) * 0.065);
			vec2 d = p - axis * travel;
			float along = dot(d, axis) / (0.12 + age * 0.05);
			float across = dot(d, vec2(-axis.y, axis.x)) / 0.050;
			flecks += exp(-along * along - across * across) * fade;
		}
		float a = atan(p.y, p.x);
		float arc = exp(-pow((r - age * 0.70) * 23.0, 2.0))
			* pow(max(sin(a * 3.0 + seed * 9.0), 0.0), 5.0) * fade * 0.32
			* (1.0 - smoothstep(-0.1, 0.5, p.x));
		alpha = (flash * 0.95 + flecks * 0.70 + arc) * edge;
		col = mix(energy_color.rgb, core_color.rgb, clamp(flash + flecks * 0.4, 0.0, 1.0));
	}
	COLOR = vec4(col, min(alpha * energy_data.a, 0.90));
}
