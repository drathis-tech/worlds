shader_type spatial;
// Neon signs and holographic billboards. Signs get a bright border and rows
// of glowing made-up letters; some scroll and some flicker. Billboards show
// a slowly shifting gradient with scan lines and a pulsing logo.
render_mode unshaded, cull_disabled;

uniform bool holo = false;

varying float v_id;
varying vec2 v_size;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 neon_color(float h) {
	if (h < 0.2) return vec3(1.0, 0.18, 0.55);
	if (h < 0.4) return vec3(0.2, 0.85, 1.0);
	if (h < 0.6) return vec3(0.65, 0.3, 1.0);
	if (h < 0.8) return vec3(1.0, 0.5, 0.12);
	return vec3(0.3, 1.0, 0.55);
}

void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_id = hash(floor(o * 2.0) + 0.5);
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
}

void fragment() {
	vec3 c = neon_color(v_id);
	vec2 uv = UV;
	if (holo) {
		vec3 c2 = neon_color(fract(v_id * 7.31));
		float scan = 0.75 + 0.25 * sin(uv.y * v_size.y * 5.0 - TIME * 3.0);
		vec3 g = mix(c, c2, clamp(uv.y + 0.25 * sin(TIME * 0.5 + v_id * 6.0), 0.0, 1.0));
		vec2 p = (uv - vec2(0.5, 0.4)) * vec2(v_size.x / v_size.y, 1.0);
		float logo = 1.0 - smoothstep(0.015, 0.03, abs(length(p) - 0.2 - 0.02 * sin(TIME * 2.0)));
		float frame = 1.0 - step(0.03, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
		ALBEDO = (g * 0.75 * scan + vec3(logo) * 1.2 + c * frame) * 1.6;
		ALPHA = 0.82;
	} else {
		vec2 m = uv * v_size;                                  // metres across the sign
		float edge = min(min(m.x, v_size.x - m.x), min(m.y, v_size.y - m.y));
		float border = 1.0 - step(0.14, edge);
		// letters: a grid of cells, each a 3x3 pattern of glowing bits
		float cell = min(v_size.x, v_size.y) * 0.42;
		vec2 inner = m - 0.32;
		float scroll = step(hash(vec3(v_id * 3.0, 1.0, 1.0)), 0.3) * floor(TIME * 3.0);
		vec2 gc = floor(inner / cell);
		vec2 f = fract(inner / cell);
		vec2 sub = floor(f * 3.0);
		float bit = step(0.45, hash(vec3(gc.x + scroll, gc.y, v_id * 31.0) + vec3(sub, 0.0) * 0.17));
		float in_cell = step(0.1, f.x) * step(f.x, 0.9) * step(0.12, f.y) * step(f.y, 0.88);
		float inside = step(0.3, edge);
		float glyph = bit * in_cell * inside * step(0.25, hash(vec3(gc + 0.5, v_id)));
		// some signs flicker
		float flick = 1.0;
		if (hash(vec3(v_id * 9.0, 2.0, 2.0)) < 0.12) {
			flick = step(0.2, hash(vec3(floor(TIME * 11.0), v_id, 3.0)));
		}
		vec3 c2 = neon_color(fract(v_id * 3.7));
		ALBEDO = (c * border * 2.4 + c2 * glyph * 1.8) * flick + c * 0.06;
	}
}
