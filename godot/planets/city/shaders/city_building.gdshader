shader_type spatial;
// Skyscrapers: rows of lit windows (warm and cool, some dark floors), glowing
// shopfronts at street level, neon trims up the corners and around the top
// of each section, and blinking red lights on spires. Every building gets its
// own look from where it stands.
render_mode diffuse_lambert_wrap;

uniform float planet_radius = 1000.0;
uniform vec3 planet_center = vec3(0.0);
uniform float window_glow = 2.6;
uniform float floor_height = 3.6;

varying vec3 v_local;   // position on the box, in metres from its centre
varying vec3 v_scale;   // box size in metres
varying vec3 v_nrm;     // box-space normal
varying vec3 v_world;
varying float v_id;     // 0..1, same for every section of one building

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
	v_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_local = VERTEX * v_scale;
	v_nrm = NORMAL;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - planet_center;
	v_id = hash(floor(normalize(o) * planet_radius * 0.5) + 0.5);
}

void fragment() {
	vec3 n = normalize(v_nrm);
	float alt = length(v_world - planet_center) - planet_radius;
	float dist = length(VERTEX);
	float id = v_id;

	float lit_ratio = 0.2 + 0.55 * hash(vec3(id * 91.0, 1.0, 2.0));
	vec3 facade = mix(vec3(0.04, 0.045, 0.06), vec3(0.1, 0.095, 0.095), hash(vec3(id * 13.0, 3.0, 1.0)));
	bool glassy = hash(vec3(id * 7.0, 5.0, 9.0)) < 0.35;
	vec3 neon = neon_color(hash(vec3(id * 3.0, 8.0, 4.0)));
	bool thin = v_scale.x < 2.0;   // spires and antennas

	vec3 albedo = facade;
	vec3 emit = vec3(0.0);
	float rough = 0.75;
	float metal = 0.0;
	float top = v_scale.y * 0.5 - v_local.y;   // metres below the top of this section

	if (thin) {
		albedo = vec3(0.12, 0.12, 0.14);
		metal = 0.7;
		float blink = step(0.5, fract(TIME * 0.6 + id * 5.0));
		emit = vec3(1.0, 0.08, 0.04) * 7.0 * blink * (1.0 - step(2.0, top));
	} else if (abs(n.y) < 0.5) {
		// --- walls: a grid of windows, one row per floor
		bool xface = abs(n.x) > 0.5;
		float hc = xface ? v_local.z : v_local.x;
		float W = xface ? v_scale.z : v_scale.x;
		float side = xface ? (n.x > 0.0 ? 0.0 : 1.0) : (n.z > 0.0 ? 2.0 : 3.0);
		float colw = W / max(1.0, floor(W / 3.0));
		float cu = (hc + W * 0.5) / colw;
		float col = floor(cu);
		float fu = fract(cu);
		float fl = floor(alt / floor_height);
		float fv = fract(alt / floor_height);
		float win = step(0.14, fu) * step(fu, 0.86) * step(0.22, fv) * step(fv, 0.82);
		float r = hash(vec3(id * 57.0 + side, fl, col));
		float floor_on = step(0.06, hash(vec3(id, fl * 0.37, 7.0)));   // the odd empty floor
		float lit = step(r, lit_ratio) * floor_on;
		vec3 wc = mix(vec3(1.0, 0.72, 0.42), vec3(0.62, 0.82, 1.0), step(0.6, hash(vec3(id * 5.0 + fl, col, 3.0))));
		wc = mix(wc, neon, step(0.95, hash(vec3(col, fl, id))) * 0.8);
		vec3 pattern = win * lit * wc * window_glow * (0.65 + 0.7 * hash(vec3(fl, col, id * 3.0)));
		vec3 glass = glassy ? vec3(0.05, 0.08, 0.13) : vec3(0.025, 0.03, 0.045);
		albedo = mix(facade, glass, win);
		rough = mix(0.8, 0.12, win);
		metal = glassy ? 0.4 * win : 0.0;
		// far away, the tiny windows would shimmer: blend to their average glow
		float far = smoothstep(80.0, 550.0, dist);
		vec3 avg = mix(vec3(1.0, 0.72, 0.42), vec3(0.62, 0.82, 1.0), 0.4) * lit_ratio * 0.16 * window_glow;
		emit = mix(pattern, avg, far) * (1.0 - 0.6 * smoothstep(900.0, 2200.0, dist));
		albedo = mix(albedo, mix(facade, glass, 0.4) * 0.6, far);

		// shopfronts glowing at street level
		if (alt < 5.0) {
			float shop = step(0.06, fu) * step(fu, 0.94) * step(0.3, alt) * step(alt, 4.2);
			float open = step(0.3, hash(vec3(col, side, id)));
			vec3 sc = neon_color(hash(vec3(col, id * 11.0, side))) * 0.9 + vec3(0.5, 0.45, 0.4);
			emit = mix(emit, sc * 1.7, shop * open);
			albedo = mix(albedo, vec3(0.02), shop * open);
		}
		// neon trims up the corners
		float edge = W * 0.5 - abs(hc);
		emit += neon * 3.0 * step(hash(vec3(id * 17.0, 2.0, 5.0)), 0.3) * (1.0 - smoothstep(0.25, 0.45, edge));
		// a glowing band around the top of each section
		emit += neon * 2.6 * step(hash(vec3(id * 23.0, 4.0, 1.0)), 0.4) * (1.0 - smoothstep(0.3, 0.6, top)) * step(0.0, top);
	} else if (n.y > 0.5) {
		// --- roofs: dark, with a glowing rim on some
		albedo = vec3(0.06, 0.06, 0.07) * (0.8 + 0.4 * hash(floor(v_local * 0.5)));
		float rim = min(v_scale.x * 0.5 - abs(v_local.x), v_scale.z * 0.5 - abs(v_local.z));
		emit = neon * 1.6 * (1.0 - smoothstep(0.3, 0.55, rim)) * step(hash(vec3(id * 23.0, 4.0, 1.0)), 0.4);
		// a blinking light in the middle of tall roofs
		float blink = step(0.5, fract(TIME * 0.5 + id * 3.0));
		emit += vec3(1.0, 0.1, 0.05) * 5.0 * blink * step(120.0, alt) * (1.0 - step(0.8, length(v_local.xz)));
	}

	ALBEDO = albedo;
	EMISSION = emit;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
}
