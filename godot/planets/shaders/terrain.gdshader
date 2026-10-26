shader_type spatial;
// Colours the ground per pixel from height and steepness: grass, forest,
// layered rock, snow on flat high ground, sand at the shore, and the sea floor.
render_mode diffuse_lambert_wrap;

uniform float planet_radius = 1000.0;
uniform float snow_line = 85.0;          // metres above sea level
uniform float rock_slope = 0.72;         // steeper than this shows rock (1 = flat)
uniform vec4 grass_light : source_color = vec4(0.56, 0.82, 0.31, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.31, 0.66, 0.24, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.70, 0.77, 0.35, 1.0);
uniform vec4 forest_floor : source_color = vec4(0.24, 0.56, 0.22, 1.0);
uniform vec4 rock_light : source_color = vec4(0.79, 0.77, 0.73, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.54, 0.53, 0.51, 1.0);
uniform vec4 snow : source_color = vec4(0.96, 0.97, 0.99, 1.0);
uniform vec4 sand : source_color = vec4(0.92, 0.86, 0.65, 1.0);
uniform vec4 shallow_water : source_color = vec4(0.44, 0.88, 0.86, 1.0);
uniform vec4 deep_water : source_color = vec4(0.12, 0.47, 0.69, 1.0);

varying vec3 v_pos;     // position in planet space
varying vec3 v_normal;  // normal in planet space
varying float v_forest;

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
	// sunny, drier patches away from forests
	float dry = smoothstep(0.55, 0.75, fbm(v_pos * 0.006 + vec3(4.0)) + (mid - 0.5) * 0.3) * (1.0 - v_forest);
	grass = mix(grass, grass_dry.rgb, dry * 0.6);
	grass = mix(grass, forest_floor.rgb, v_forest * 0.85);
	grass *= 0.93 + fine * 0.14;

	// Rock: horizontal layers that follow the ledges, broken up by noise.
	float layers = sin(h * 0.45 + mid * 6.0 + big * 4.0) * 0.5 + 0.5;
	vec3 rock = mix(rock_dark.rgb, rock_light.rgb, clamp(layers * 0.25 + mid * 0.35 + fine * 0.35 + (big - 0.5) * 0.4, 0.0, 1.0));
	// darker in crevices (steeper parts)
	rock *= mix(0.8, 1.05, smoothstep(0.2, 0.7, slope));

	vec3 col = grass;

	// Sand on the shore.
	float sand_t = 1.0 - smoothstep(0.6, 2.2 + mid * 1.5, h);
	col = mix(col, sand.rgb * (0.95 + fine * 0.1), sand_t);

	// Rock on steep ground and high up.
	float rock_t = 1.0 - smoothstep(rock_slope - 0.05, rock_slope + 0.05, slope + (mid - 0.5) * 0.15);
	rock_t = max(rock_t, smoothstep(snow_line * 0.6, snow_line * 0.85, h + (mid - 0.5) * 12.0));
	col = mix(col, rock, rock_t * step(0.0, h));

	// Snow settles on flat-ish high ground and on top of rock ledges.
	float snow_h = smoothstep(snow_line - 10.0, snow_line + 2.0, h + (mid - 0.5) * 30.0);
	float snow_flat = smoothstep(0.5, 0.72, slope + (fine - 0.5) * 0.25);
	float snow_t = snow_h * snow_flat;
	col = mix(col, snow.rgb, snow_t);

	// Under water: sea floor tinted towards the water colour.
	if (h < 0.0) {
		vec3 floor_col = mix(shallow_water.rgb, deep_water.rgb, smoothstep(0.0, 22.0, -h));
		col = mix(sand.rgb, floor_col, smoothstep(0.0, 2.5, -h));
	}

	// Bumpy, chiselled rock surface: tilt the lighting normal with noise.
	float rock_amount = rock_t * (1.0 - snow_t) * step(0.0, h) * near;
	if (rock_amount > 0.01) {
		vec3 q = v_pos * 0.22;
		float e = 0.35;
		float n0 = vnoise(q) + 0.5 * vnoise(q * 2.7);
		vec3 grad = vec3(
			vnoise(q + vec3(e, 0, 0)) + 0.5 * vnoise((q + vec3(e, 0, 0)) * 2.7) - n0,
			vnoise(q + vec3(0, e, 0)) + 0.5 * vnoise((q + vec3(0, e, 0)) * 2.7) - n0,
			vnoise(q + vec3(0, 0, e)) + 0.5 * vnoise((q + vec3(0, 0, e)) * 2.7) - n0) / e;
		grad -= n * dot(grad, n);
		vec3 bumped = normalize(n - grad * 0.55 * rock_amount);
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bumped, 0.0)).xyz);
		col *= 1.0 - 0.12 * rock_amount * (1.0 - n0 / 1.5);
	}

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, snow_t);
	SPECULAR = 0.25;
}
