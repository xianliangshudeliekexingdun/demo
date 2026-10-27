shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float core_time = 0.0;
uniform bool reduced_motion = false;
uniform float flow_speed;
uniform vec4 edge_color : source_color;
uniform vec4 shell_color : source_color;
uniform vec4 energy_color : source_color;
uniform vec4 core_color : source_color;
uniform vec4 buff_color : source_color;
uniform vec4 rune_color : source_color;
uniform vec4 rune_hot_color : source_color;
uniform vec4 rune_glow_color : source_color;
uniform vec4 ember_color : source_color;
uniform float rune_line_width;
uniform float rune_flow_speed;
uniform float rune_glow_strength;
varying vec4 field_data;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
float ring(float r, float at, float width) { return exp(-pow((r - at) / width, 2.0)); }
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 v = b - a;
	return length(p - a - v * clamp(dot(p - a, v) / dot(v, v), 0.0, 1.0));
}
float flame_rune(vec2 p) {
	// One folded sector contains one small flame glyph, with a separate wick.
	float d = segment(p, vec2(0.018, 0.13), vec2(-0.015, 0.075));
	d = min(d, segment(p, vec2(-0.015, 0.075), vec2(-0.080, 0.020)));
	d = min(d, segment(p, vec2(-0.080, 0.020), vec2(-0.095, -0.045)));
	d = min(d, segment(p, vec2(-0.095, -0.045), vec2(-0.052, -0.105)));
	d = min(d, segment(p, vec2(-0.052, -0.105), vec2(0.045, -0.102)));
	d = min(d, segment(p, vec2(0.045, -0.102), vec2(0.092, -0.045)));
	d = min(d, segment(p, vec2(0.092, -0.045), vec2(0.075, 0.028)));
	d = min(d, segment(p, vec2(0.075, 0.028), vec2(0.026, -0.015)));
	d = min(d, segment(p, vec2(0.026, -0.015), vec2(0.018, 0.13)));
	return min(d, segment(p, vec2(-0.010, -0.072), vec2(0.012, 0.006)));
}
float ink(float d, float width) {
	float aa = max(fwidth(d) * 0.75, 0.0008);
	return 1.0 - smoothstep(max(0.0, width - aa), width + aa, d);
}
void vertex() { field_data = INSTANCE_CUSTOM; }
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float progress = clamp(field_data.g, 0.0, 1.0);
	int mode = int(floor(field_data.b * 8.0 + 0.5));
	float phase = mode == 0 ? 0.0 : field_data.r * 6.283185;
	float t = reduced_motion ? 0.0 : core_time * flow_speed;
	float cut = 1.0 - smoothstep(0.99, 1.0, r);
	float n = noise(p * 5.0 + vec2(sin(t * 0.3 + phase), -t * 0.55));
	float alpha = 0.0;
	float heat = 0.0;
	float glow = 0.0;
	vec3 color = shell_color.rgb;
	if (mode == 0) {
		// R is per-field reveal; G remains the actual eligible maturity charge.
		// All distance geometry is independent of core_time: only light travels.
		float reveal = clamp(field_data.r, 0.0, 1.0);
		float sector_angle = 1.04719755;
		float sector = mod(floor((a + sector_angle * 0.5 + 6.283185) / sector_angle), 6.0);
		float local_a = mod(a + sector_angle * 0.5 + 6.283185, sector_angle) - sector_angle * 0.5;
		vec2 q = vec2(sin(local_a) * r, cos(local_a) * r - 0.64);
		float glyph_distance = 1.0;
		if (r > 0.47 && r < 0.81) { glyph_distance = flame_rune(q); }
		float center_distance = 1.0;
		if (r < 0.23) { center_distance = flame_rune(p * 0.84); }
		float glyph_reveal = smoothstep(0.10 + sector * 0.075, 0.35 + sector * 0.075, reveal);
		float center_reveal = smoothstep(0.50, 0.95, reveal);
		float arc_reveal = smoothstep(0.02, 0.45, reveal);
		float arc_mask = smoothstep(0.08, 0.32, cos(a * 6.0 - 0.25));
		float inner_mask = smoothstep(-0.12, 0.22, cos(a * 6.0 + 0.50));
		float outer = ink(abs(r - 0.98), rune_line_width * 0.55);
		float arcs = ink(abs(r - 0.84), rune_line_width * 0.75) * arc_mask * arc_reveal;
		float inner = ink(abs(r - 0.47), rune_line_width * 0.70) * inner_mask * smoothstep(0.20, 0.70, reveal);
		float glyph = ink(glyph_distance, rune_line_width) * glyph_reveal;
		float center = ink(center_distance, rune_line_width * 0.85) * center_reveal;
		float travel = pow(max(0.0, cos(a - t * rune_flow_speed)), 22.0);
		float node_light = 0.65 + 0.35 * sin(t * rune_flow_speed - sector * 0.85);
		float glyph_light = 0.66 + node_light * 0.20 + travel * 0.14;
		float line = outer * 0.37 + arcs * (0.42 + travel * 0.27) + inner * (0.32 + progress * 0.20);
		line += glyph * glyph_light + center * (0.40 + progress * 0.37);
		float halo = ring(r, 0.84, rune_line_width * 3.8) * arc_mask * arc_reveal * 0.28;
		halo += exp(-pow(glyph_distance / (rune_line_width * 4.0), 2.0)) * glyph_reveal * (0.48 + node_light * 0.14);
		halo += exp(-pow(center_distance / (rune_line_width * 4.2), 2.0)) * center_reveal * (0.20 + progress * 0.30);
		halo *= rune_glow_strength;
		alpha = line + halo;
		float hot_line = ink(glyph_distance, rune_line_width * 0.30) * glyph_reveal;
		heat = clamp(hot_line * (0.20 + travel * 0.55) + inner * progress * 0.28 + center * progress * 0.46, 0.0, 1.0);
		color = mix(rune_glow_color.rgb, rune_color.rgb, clamp(line / max(alpha, 0.0001), 0.0, 1.0));
		color = mix(color, rune_hot_color.rgb, heat);
		glow = heat * rune_glow_strength * 0.12;
	} else if (mode == 1) {
		alpha = (ring(r, 0.36 + progress * 0.43, 0.065) * 0.7 + exp(-r * r * 10.0) * 0.6) * (1.0 - progress);
		heat = 0.65;
	} else if (mode == 2 || mode == 6) {
		float rays = pow(max(0.0, cos(a * 5.0 + phase)), 6.0) * exp(-r * 3.0);
		alpha = (exp(-r * r * 13.0) + rays * 0.65) * pow(1.0 - progress, 1.3);
		heat = 0.95;
	} else if (mode == 3) {
		float arcs = ring(r, 0.78, 0.040) * smoothstep(-0.4, 0.3, sin(a * 3.0 + phase));
		alpha = arcs * 0.82 + ring(r, 0.53, 0.032) * 0.45;
		color = buff_color.rgb;
		heat = 0.15;
	} else if (mode == 4) {
		alpha = ring(length(p + vec2(0.17, 0.0)), 0.64, 0.045) + ring(length(p - vec2(0.17, 0.0)), 0.64, 0.045);
		alpha *= 0.55 + n * 0.20;
		heat = 0.65;
	} else if (mode == 5) {
		float front = 0.12 + sqrt(progress) * 0.78;
		float wave = ring(r + (n - 0.5) * 0.075, front, 0.045 + (1.0 - progress) * 0.025);
		float core = exp(-r * r * (5.0 + progress * 13.0));
		float tongues = pow(max(0.0, sin(a * 7.0 + n * 4.0 + phase)), 4.0) * ring(r, front * 0.72, 0.16);
		alpha = (wave * 0.90 + core * 0.65 + tongues * 0.38) * pow(1.0 - progress, 1.15);
		heat = clamp(core * 0.85 + wave * 0.60, 0.0, 1.0);
	} else if (mode == 8) {
		vec2 head = vec2(p.x / 0.32, (p.y - 0.25) / 0.36);
		float hot = exp(-dot(head, head) * 2.0);
		float tail = exp(-pow(p.x / (0.13 + n * 0.07), 2.0));
		tail *= smoothstep(-0.96, -0.36, p.y) * (1.0 - smoothstep(0.12, 0.42, p.y));
		alpha = hot * 0.92 + tail * 0.38;
		color = mix(ember_color.rgb, rune_hot_color.rgb, hot * 0.85);
		glow = hot * 0.16;
	} else {
		float flecks = smoothstep(0.72, 0.96, n) * (1.0 - smoothstep(0.35, 0.90, r));
		float remnant = ring(r, 0.48, 0.018) * smoothstep(0.12, 0.75, sin(a * 6.0 + phase));
		alpha = (flecks * 0.35 + remnant * 0.18) * pow(1.0 - progress, 1.5);
		heat = 0.16;
	}
	if (mode != 0 && mode != 8) {
		color = mix(color, energy_color.rgb, heat * 0.82);
		color = mix(color, core_color.rgb, (mode == 2 || mode == 5 || mode == 6) ? heat * heat * 0.47 : heat * 0.09);
		glow = heat * ((mode == 5 || mode == 2) ? 0.12 : 0.045);
	}
	alpha = clamp(alpha * cut * field_data.a, 0.0, 0.94);
	vec3 light_color = mode == 0 || mode == 8 ? rune_hot_color.rgb : energy_color.rgb;
	COLOR = vec4(color * alpha + light_color * glow * alpha, alpha);
}
