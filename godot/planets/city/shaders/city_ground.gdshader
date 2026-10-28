shader_type spatial;
// The city's streets, painted on a smooth sphere: wet asphalt with lane
// markings and crosswalks, puddles catching the neon, sidewalks, pools of
// light under the street lamps, and glowing landing pads on the plazas.
// Uses the same grid maths as city_layout.gd, so it lines up with the
// buildings. From far away, the streets glow as lines of light.
render_mode diffuse_lambert_wrap;

uniform float planet_radius = 1000.0;
uniform int blocks = 24;
uniform int avenue_every = 4;
uniform float street_half = 5.0;
uniform float avenue_half = 9.0;
uniform float sidewalk = 3.0;
uniform int city_seed = 3;

varying vec3 v_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 neon_color(float h) {
	if (h < 0.2) return vec3(1.0, 0.18, 0.55);
	if (h < 0.4) return vec3(0.2, 0.85, 1.0);
	if (h < 0.6) return vec3(0.65, 0.3, 1.0);
	if (h < 0.8) return vec3(1.0, 0.5, 0.12);
	return vec3(0.3, 1.0, 0.55);
}

// Which cube side, and where on it (-1..1), for a direction.
void cube_coords(vec3 d, out int face, out vec2 xy) {
	vec3 a = abs(d);
	vec3 n;
	vec3 u;
	vec3 v;
	if (a.x >= a.y && a.x >= a.z) {
		if (d.x > 0.0) { face = 0; n = vec3(1, 0, 0); u = vec3(0, 1, 0); v = vec3(0, 0, 1); }
		else { face = 1; n = vec3(-1, 0, 0); u = vec3(0, 0, 1); v = vec3(0, 1, 0); }
	} else if (a.y >= a.z) {
		if (d.y > 0.0) { face = 2; n = vec3(0, 1, 0); u = vec3(0, 0, 1); v = vec3(1, 0, 0); }
		else { face = 3; n = vec3(0, -1, 0); u = vec3(1, 0, 0); v = vec3(0, 0, 1); }
	} else {
		if (d.z > 0.0) { face = 4; n = vec3(0, 0, 1); u = vec3(1, 0, 0); v = vec3(0, 1, 0); }
		else { face = 5; n = vec3(0, 0, -1); u = vec3(0, 1, 0); v = vec3(1, 0, 0); }
	}
	float dn = dot(d, n);
	xy = vec2(atan(dot(d, u) / dn), atan(dot(d, v) / dn)) * (4.0 / PI);
}

// Soft pool of light from the lamps beside one road.
float lamp_pool(float across, float along, float hw, float cell_m) {
	float off = abs(across) - (hw + 0.8);
	float a = min(min(abs(along - 1.0 / 6.0), abs(along - 0.5)), abs(along - 5.0 / 6.0)) * cell_m;
	return exp(-(off * off + a * a) / 30.0);
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec3 d = normalize(v_pos);
	int face;
	vec2 xy;
	cube_coords(d, face, xy);
	float N = float(blocks);
	vec2 g = (xy + 1.0) * 0.5 * N;
	float cell_m = planet_radius * PI * 0.5 / N;
	vec2 k = round(g);
	vec2 dm = (g - k) * cell_m;          // metres from the nearest road centre line
	ivec2 ki = ivec2(k);
	vec2 hw = vec2(ki.x % avenue_every == 0 ? avenue_half : street_half,
			ki.y % avenue_every == 0 ? avenue_half : street_half);
	vec2 ad = abs(dm);
	bool road_x = ad.x < hw.x;           // on the road that runs along y
	bool road_y = ad.y < hw.y;
	bool walk = ad.x < hw.x + sidewalk || ad.y < hw.y + sidewalk;
	ivec2 bi = ivec2(floor(g));
	vec2 fb = fract(g);                   // where inside the block, 0..1
	bool plaza = (bi.x * 131 + bi.y * 197 + face * 311 + city_seed * 17) % 1009 < 36;
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(60.0, 260.0, dist);

	vec3 col = vec3(0.075, 0.072, 0.08) * (0.85 + 0.3 * vnoise(v_pos * 0.4));
	float rough = 0.7;
	vec3 emit = vec3(0.0);

	if (walk) {
		// sidewalk slabs
		vec2 slab = fract(vec2(dm.x, dm.y) / 1.5);
		float gap = step(0.06, min(min(slab.x, 1.0 - slab.x), min(slab.y, 1.0 - slab.y)));
		col = vec3(0.14, 0.135, 0.145) * (0.9 + 0.2 * vnoise(v_pos * 1.7)) * mix(0.75, 1.0, gap * near + (1.0 - near));
		rough = 0.5;
	}
	if (road_x || road_y) {
		col = vec3(0.032, 0.034, 0.042) * (0.8 + 0.4 * vnoise(v_pos * 0.9));
		rough = 0.3;
		if (road_x && !road_y) {
			float dash = step(0.5, fract(fb.y * cell_m / 6.0));
			if (hw.x > 7.0) {
				emit += vec3(1.0, 0.75, 0.2) * 0.9 * (1.0 - step(0.1, abs(ad.x - 0.25)));
				emit += vec3(0.85) * 0.6 * dash * (1.0 - step(0.1, abs(ad.x - 4.5)));
			} else {
				emit += vec3(0.85) * 0.6 * dash * (1.0 - step(0.12, ad.x));
			}
			// crosswalk just before the crossing road
			if (ad.y > hw.y + 0.4 && ad.y < hw.y + 3.2) {
				col = mix(col, vec3(0.75), step(0.5, fract(dm.x * 0.9)) * 0.8);
			}
		}
		if (road_y && !road_x) {
			float dash = step(0.5, fract(fb.x * cell_m / 6.0));
			if (hw.y > 7.0) {
				emit += vec3(1.0, 0.75, 0.2) * 0.9 * (1.0 - step(0.1, abs(ad.y - 0.25)));
				emit += vec3(0.85) * 0.6 * dash * (1.0 - step(0.1, abs(ad.y - 4.5)));
			} else {
				emit += vec3(0.85) * 0.6 * dash * (1.0 - step(0.12, ad.y));
			}
			if (ad.x > hw.x + 0.4 && ad.x < hw.x + 3.2) {
				col = mix(col, vec3(0.75), step(0.5, fract(dm.y * 0.9)) * 0.8);
			}
		}
		emit *= near;
		// puddles, catching the neon
		float pud = smoothstep(0.6, 0.68, vnoise(v_pos * 0.15) * 0.7 + vnoise(v_pos * 0.6) * 0.3);
		rough = mix(rough, 0.04, pud);
		emit += neon_color(vnoise(v_pos * 0.02 + 3.0)) * 0.12 * pud * near;
		col *= 1.0 - 0.45 * pud;
	}
	if (plaza && !walk) {
		vec2 pm = (fb - 0.5) * cell_m;
		vec2 tile = fract(pm / 2.0);
		col = vec3(0.15, 0.14, 0.16) * mix(0.8, 1.0, step(0.05, min(min(tile.x, 1.0 - tile.x), min(tile.y, 1.0 - tile.y))));
		float r = length(pm);
		emit += vec3(0.2, 0.9, 1.0) * 2.2 * (1.0 - smoothstep(0.25, 0.45, abs(r - 12.0)));
		float ring2 = (1.0 - smoothstep(0.15, 0.3, abs(r - 9.0))) * step(0.5, fract(atan(pm.y, pm.x) / PI * 8.0 + TIME * 0.15));
		emit += vec3(0.2, 0.9, 1.0) * 1.3 * ring2;
		rough = 0.35;
	}
	// pools of warm light under the street lamps
	float pool = max(lamp_pool(dm.x, fb.y, hw.x, cell_m), lamp_pool(dm.y, fb.x, hw.y, cell_m));
	emit += vec3(1.0, 0.72, 0.42) * 0.6 * pool;

	// from far away the streets become lines of light
	float far = smoothstep(250.0, 1400.0, dist);
	float line = max(1.0 - smoothstep(hw.x * 0.5, hw.x * 1.6, ad.x), 1.0 - smoothstep(hw.y * 0.5, hw.y * 1.6, ad.y));
	vec3 glow = mix(vec3(1.0, 0.5, 0.22), vec3(1.0, 0.78, 0.5), step(7.0, max(hw.x, hw.y)));
	emit = mix(emit, glow * line * 1.4, far);

	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
	SPECULAR = 0.6;
}
