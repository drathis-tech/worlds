shader_type spatial;
// Colours the ground per pixel from height and steepness: grass, forest,
// layered rock, snow on flat high ground, sand at the shore, and the sea floor.
render_mode diffuse_lambert_wrap;

uniform float planet_radius = 1000.0;
uniform float snow_line = 85.0;          // metres above sea level
uniform float rock_slope = 0.62;         // steeper than this shows rock (1 = flat, 0.62 = about 52 degrees)
uniform vec4 grass_light : source_color = vec4(0.56, 0.82, 0.31, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.31, 0.66, 0.24, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.70, 0.77, 0.35, 1.0);
uniform vec4 forest_floor : source_color = vec4(0.24, 0.56, 0.22, 1.0);
uniform vec4 rock_light : source_color = vec4(0.79, 0.77, 0.73, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.54, 0.53, 0.51, 1.0);
uniform vec4 snow : source_color = vec4(0.96, 0.97, 0.99, 1.0);
uniform vec4 snow_shadow : source_color = vec4(0.81, 0.87, 0.94, 1.0);
uniform vec4 ice : source_color = vec4(0.75, 0.9, 0.96, 1.0);
uniform vec4 taiga_grass : source_color = vec4(0.31, 0.54, 0.29, 1.0);
uniform vec4 sand : source_color = vec4(0.92, 0.86, 0.65, 1.0);
uniform vec4 shallow_water : source_color = vec4(0.44, 0.88, 0.86, 1.0);
uniform vec4 deep_water : source_color = vec4(0.12, 0.47, 0.69, 1.0);
uniform vec4 dirt : source_color = vec4(0.58, 0.45, 0.31, 1.0);
uniform vec4 dirt_dark : source_color = vec4(0.40, 0.30, 0.21, 1.0);

varying vec3 v_pos;     // position in planet space
varying vec3 v_normal;  // normal in planet space
varying float v_forest;
varying float v_cold;   // 0 warm .. 1 frozen (poles and snowy biomes)
varying float v_ice;    // frozen sea
varying float v_trail;  // dirt trail
varying float v_gorge;  // stony floor of a river gorge

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

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return sum / 0.9375;
}

void vertex() {
	v_pos = VERTEX;
	v_normal = NORMAL;
	v_forest = COLOR.r;
	v_cold = COLOR.g;
	v_ice = COLOR.b;
	v_trail = COLOR.a;
	v_gorge = UV.x;
}

void fragment() {
	vec3 up = normalize(v_pos);
	vec3 n = normalize(v_normal);
	float h = length(v_pos) - planet_radius;
	float slope = dot(n, up);
	float dist = length(VERTEX);
	// fine detail fades out with distance so it doesn't shimmer
	float near = 1.0 - smoothstep(40.0, 160.0, dist);

	float big = fbm(v_pos * 0.012);
	float mid = fbm(v_pos * 0.09);
	float fine = mix(0.5, fbm(v_pos * 0.8), near);

	// Grass: big soft patches, darker under forests.
	vec3 grass = mix(grass_light.rgb, grass_dark.rgb, clamp((big - 0.35) * 2.2 + (mid - 0.5) * 0.6, 0.0, 1.0));
	// Painterly patches of golden grass with soft but clear edges, like
	// brush strokes, broken up by smaller blobs inside.
	float patch_n = fbm(v_pos * 0.0065 + vec3(4.0)) + (fbm(v_pos * 0.035) - 0.5) * 0.35 + (mid - 0.5) * 0.12;
	float dry = smoothstep(0.5, 0.56, patch_n) * (1.0 - v_forest * 0.8);
	grass = mix(grass, grass_dry.rgb * (0.92 + fine * 0.16), dry * 0.9);
	grass = mix(grass, forest_floor.rgb, v_forest * 0.85);
	// colder places and high mountain ledges: darker, bluer alpine grass
	float line0 = snow_line * (1.0 - smoothstep(0.3, 0.7, v_cold) * 0.85);
	float alpine = max(smoothstep(0.15, 0.45, v_cold), smoothstep(line0 * 0.35, line0 * 0.75, h));
	grass = mix(grass, taiga_grass.rgb * 0.95, alpine * 0.8);
	grass *= 0.93 + fine * 0.14;
	// up close: clumps of lighter and darker grass
	float clump = mix(0.5, vnoise(v_pos * 1.3) * 0.6 + vnoise(v_pos * 3.1) * 0.4, near);
	grass *= 0.9 + clump * 0.2;
	// Large areas each get their own tint, so the land never looks the same
	// for long: bluer greens in some places, warmer yellow-greens in others.
	float region = fbm(v_pos * 0.0028 + vec3(11.0, 3.0, 7.0));
	grass = mix(grass, grass * vec3(0.86, 1.0, 1.08), smoothstep(0.55, 0.75, region));
	grass = mix(grass, grass * vec3(1.12, 1.04, 0.78), smoothstep(0.45, 0.25, region) * (1.0 - v_forest));
	// bare, earthy patches on the forest floor
	float earth = smoothstep(0.55, 0.7, fbm(v_pos * 0.05 + vec3(5.0)) + (fine - 0.5) * 0.3) * v_forest;
	grass = mix(grass, dirt_dark.rgb * 1.1, earth * 0.55 * (1.0 - smoothstep(200.0, 400.0, dist)));
	// beyond where flowers are drawn, little dots of colour keep meadows lively
	float mid_range = smoothstep(30.0, 50.0, dist) * (1.0 - smoothstep(140.0, 220.0, dist));
	vec3 cell = floor(v_pos * 1.5);
	float speck = step(0.982, hash(cell)) * (1.0 - v_forest) * (1.0 - smoothstep(0.1, 0.3, v_cold)) * mid_range;
	vec3 petal = mix(vec3(1.0, 0.85, 0.3), vec3(0.95, 0.55, 0.75), step(0.5, hash(cell + 3.3)));
	grass = mix(grass, petal, speck * 0.8);

	// Rock: horizontal layers that follow the ledges, broken up by noise.
	float layers = sin(h * 0.45 + mid * 6.0 + big * 4.0) * 0.5 + 0.5;
	vec3 rock = mix(rock_dark.rgb, rock_light.rgb, clamp(layers * 0.25 + mid * 0.35 + fine * 0.35 + (big - 0.5) * 0.4, 0.0, 1.0));
	// darker in crevices (steeper parts)
	rock *= mix(0.8, 1.05, smoothstep(0.2, 0.7, slope));
	// big vertical streaks and gullies down the cliffs, visible from far away
	vec3 flat_pos = v_pos - up * h;
	float streak = fbm(flat_pos * 0.06 + vec3(0.0, h * 0.004, 0.0)) * 0.7 + fbm(flat_pos * 0.18 + vec3(h * 0.01)) * 0.3;
	rock *= 0.72 + 0.42 * smoothstep(0.32, 0.68, streak);
	// flatter ledges on the cliffs catch more light
	rock = mix(rock, rock * 1.15 + vec3(0.03), smoothstep(0.55, 0.7, slope) * 0.6);
	// warm sandstone low down turning to cool mauve towards the peaks
	rock = mix(rock, rock * vec3(0.86, 0.8, 1.02), smoothstep(snow_line * 0.25, snow_line * 0.9, h));

	vec3 col = grass;

	// Sand on the shore.
	float sand_t = 1.0 - smoothstep(0.6, 2.2 + mid * 1.5, h);
	col = mix(col, sand.rgb * (0.95 + fine * 0.1), sand_t);

	// River gorges: a stony floor of grey-pink stones and gravel instead of sand.
	if (v_gorge > 0.01) {
		float stones = fbm(flat_pos * 1.1 + vec3(3.0));
		float gravel = fbm(flat_pos * 4.0);
		vec3 stony = mix(rock * 0.62, rock * 1.05, smoothstep(0.42, 0.58, stones));
		stony *= 0.9 + 0.2 * gravel;
		stony = mix(stony, grass * 0.8, smoothstep(0.66, 0.76, fbm(flat_pos * 0.35 + vec3(8.0))) * 0.7);   // tufts of grass
		col = mix(col, stony, v_gorge * (1.0 - smoothstep(2.5, 5.0, h)));
	}

	// Rock on steep ground and high up.
	float rock_t = 1.0 - smoothstep(rock_slope - 0.05, rock_slope + 0.05, slope + (mid - 0.5) * 0.15);
	// Just below the snow line, bare rock shows through on sloping ground.
	float line = snow_line * (1.0 - smoothstep(0.3, 0.7, v_cold) * 0.85);
	float high = smoothstep(line * 0.75, line * 0.95, h + (mid - 0.5) * 12.0);
	rock_t = max(rock_t, high * (1.0 - smoothstep(0.8, 0.92, slope)));
	// Cracks: a few dark lines running mostly down the cliffs, only in some
	// areas, fading out with distance.
	vec3 cp = flat_pos * 0.07 + up * h * 0.012;
	float crack_line = abs(vnoise(cp + vec3(1.3, 7.1, 2.9)) - 0.5);
	float crack_zone = smoothstep(0.55, 0.7, vnoise(flat_pos * 0.02 + vec3(4.0)));
	float cracks = (1.0 - smoothstep(0.0, 0.02, crack_line)) * crack_zone;
	rock *= 1.0 - 0.5 * cracks * (1.0 - smoothstep(120.0, 320.0, dist));
	col = mix(col, rock, rock_t * step(0.0, h));
	// Grass clinging to ledges and gentler bits of the mountains.
	float ledge_grass = smoothstep(0.36, 0.5, slope + (fbm(v_pos * 0.05 + vec3(2.0)) - 0.5) * 0.4)
			* smoothstep(0.36, 0.48, fbm(v_pos * 0.02 + vec3(7.0)))
			* (1.0 - smoothstep(line * 0.7, line * 0.9, h));
	vec3 alpine_grass = mix(taiga_grass.rgb, grass_dry.rgb, 0.35 + 0.3 * fine) * (0.9 + 0.2 * mid);
	col = mix(col, alpine_grass, rock_t * ledge_grass * step(0.0, h));

	// Snow settles on flat-ish high ground, on top of rock ledges, and
	// everywhere flat in cold places. The snow line drops towards the poles.
	float snow_h = smoothstep(line - 4.0, line + 8.0, h + (mid - 0.5) * 30.0);
	float snow_cold = smoothstep(0.42, 0.55, v_cold + (mid - 0.5) * 0.25);
	float snow_flat = smoothstep(0.66, 0.84, slope + (fine - 0.5) * 0.25 + (mid - 0.5) * 0.15);
	// patches of old snow on ledges high on the mountains, below the snow line
	float snow_patch = smoothstep(line * 0.6, line * 0.8, h) * smoothstep(0.55, 0.7, fbm(v_pos * 0.03 + vec3(9.0))) * smoothstep(0.6, 0.75, slope);
	float snow_t = max(max(snow_h, snow_cold) * snow_flat, snow_patch) * step(-0.5, h);
	// soft blue shading in dips and on steeper snow, like real snowdrifts
	vec3 snow_col = mix(snow_shadow.rgb, snow.rgb, clamp(smoothstep(0.35, 0.8, slope) * (0.85 + fine * 0.15) + (big - 0.5) * 0.2, 0.0, 1.0));
	col = mix(col, snow_col, snow_t);

	// Frozen sea: pale blue ice with cracks and patches of snow.
	if (v_ice > 0.01) {
		float cracks = smoothstep(0.47, 0.5, vnoise(v_pos * 0.08)) * (1.0 - smoothstep(0.5, 0.53, vnoise(v_pos * 0.08)));
		vec3 ice_col = mix(ice.rgb, ice.rgb * 0.82, cracks * near);
		ice_col = mix(ice_col, snow.rgb, smoothstep(0.55, 0.75, mid + big * 0.3));
		col = mix(col, ice_col, smoothstep(0.3, 0.9, v_ice) * step(0.0, h));
	}

	// Dirt trails: worn earth with ragged grassy edges and little stones.
	float trail = smoothstep(0.3, 0.65, v_trail + (fine - 0.5) * 0.35 + (mid - 0.5) * 0.15) * step(0.2, h);
	trail *= smoothstep(0.8, 0.93, slope);   // trails stay on gentle ground
	trail *= 1.0 - smoothstep(250.0, 450.0, dist);   // too thin to see from far away
	if (trail > 0.01) {
		float worn = vnoise(v_pos * 0.6) * 0.6 + vnoise(v_pos * 2.3) * 0.4;
		vec3 path = mix(dirt_dark.rgb, dirt.rgb, clamp(worn * 1.2 + (v_trail - 0.6) * 0.8, 0.0, 1.0));
		vec3 sc = v_pos * 1.7;
		vec3 sid = floor(sc);
		vec3 sp = vec3(hash(sid), hash(sid + 1.7), hash(sid + 4.1)) * 0.6 + 0.2;
		float stones = step(0.72, hash(sid + 9.3)) * (1.0 - smoothstep(0.07, 0.12, length(fract(sc) - sp) - hash(sid) * 0.06)) * near;
		path = mix(path, mix(rock_dark.rgb, rock_light.rgb, hash(sid + 2.2)), stones * 0.9);
		// on snow, trails are trodden-down grey snow instead
		path = mix(path, mix(snow_shadow.rgb, dirt.rgb, 0.25), snow_t * 0.85);
		col = mix(col, path, trail);
	}

	// A white line of foam where the water meets the shore, gently moving.
	if (v_ice < 0.3) {
		float wave = sin(TIME * 0.8 + mid * 18.0) * 0.12;
		float foam_line = 1.0 - smoothstep(0.08, 0.22, abs(h + 0.08 + wave));
		float foam_breaks = smoothstep(0.35, 0.5, vnoise(v_pos * 0.5 + vec3(TIME * 0.1)));
		col = mix(col, vec3(0.97, 0.98, 1.0), foam_line * foam_breaks * (1.0 - smoothstep(300.0, 600.0, dist)));
	}

	// Under water: sea floor tinted towards the water colour.
	if (h < 0.0) {
		vec3 floor_col = mix(shallow_water.rgb, deep_water.rgb, smoothstep(0.0, 22.0, -h));
		col = mix(sand.rgb, floor_col, smoothstep(0.0, 2.5, -h));
	}

	// Up close, tilt the lighting with noise: chiselled rock, lumpy ground.
	float rock_amount = rock_t * (1.0 - snow_t) * step(0.0, h) * near;
	float ground_amount = (1.0 - rock_t) * (1.0 - snow_t * 0.6) * step(0.3, h) * near;
	float bump = rock_amount * 0.55 + ground_amount * 0.22;
	if (bump > 0.01) {
		vec3 q = v_pos * mix(0.9, 0.22, rock_t);
		float e = 0.35;
		float n0 = vnoise(q) + 0.5 * vnoise(q * 2.7);
		vec3 grad = vec3(
			vnoise(q + vec3(e, 0, 0)) + 0.5 * vnoise((q + vec3(e, 0, 0)) * 2.7) - n0,
			vnoise(q + vec3(0, e, 0)) + 0.5 * vnoise((q + vec3(0, e, 0)) * 2.7) - n0,
			vnoise(q + vec3(0, 0, e)) + 0.5 * vnoise((q + vec3(0, 0, e)) * 2.7) - n0) / e;
		grad -= n * dot(grad, n);
		vec3 bumped = normalize(n - grad * bump);
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bumped, 0.0)).xyz);
		col *= 1.0 - 0.12 * rock_amount * (1.0 - n0 / 1.5);
	}

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.95, 0.55, snow_t), 0.25, smoothstep(0.3, 0.9, v_ice));
	SPECULAR = 0.25;
}
