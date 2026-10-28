shader_type spatial;
// Trees, rocks and logs: colours from the model. Trees sway gently in the wind
// (rocks and logs use sway = 0).
render_mode cull_back, diffuse_lambert_wrap;

uniform float sway = 0.0;           // metres of movement per metre of height
uniform float wind_speed = 0.9;

uniform float tint_amount = 0.13;
// Rocks get painted-on texture: blotches of colour, speckles, cracks, lichen
// and moss. It sticks to the rock (measured on the model, not the world).
uniform bool rocky = false;
uniform vec4 lichen_color : source_color = vec4(0.82, 0.74, 0.36, 1.0);
uniform vec4 lichen_orange : source_color = vec4(0.88, 0.55, 0.3, 1.0);
uniform vec4 moss_color : source_color = vec4(0.42, 0.6, 0.25, 1.0);

varying vec3 v_local;
varying vec3 v_local_normal;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	return vnoise(p) * 0.57 + vnoise(p * 2.1 + 3.1) * 0.29 + vnoise(p * 4.3 + 7.7) * 0.14;
}

// A random colour tint per prop, picked from where it stands, so no two
// trees or rocks are quite the same colour. amount = how strong.
vec3 prop_tint(vec3 origin, float amount) {
	vec3 p = fract(origin * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	vec3 r = fract((p.xxy + p.yxx) * p.zyx);   // three random numbers 0..1
	float bright = 1.0 + (r.x - 0.5) * 2.0 * amount;
	float warm = (r.y - 0.5) * 1.6 * amount;
	return vec3(bright * (1.0 + warm * 0.6), bright * (1.0 + warm * 0.15), bright * (1.0 - warm * 0.8));
}

void vertex() {
	v_local = VERTEX;
	v_local_normal = NORMAL;
	// each prop's own colour tint (lighter, darker, warmer, cooler)
	COLOR.rgb *= prop_tint((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, tint_amount);
	if (sway > 0.0) {
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float h = max(VERTEX.y, 0.0);
		float t = TIME * wind_speed + dot(origin, vec3(0.05, 0.03, 0.07));
		VERTEX.xz += vec2(sin(t), cos(t * 0.71)) * sway * h * (h / 10.0);
	}
}

vec3 rock_texture(vec3 col, vec3 p, vec3 n, vec3 seed) {
	p += seed;   // every rock gets a different patch of texture
	float snow = smoothstep(0.78, 0.9, dot(col, vec3(0.33)));
	// big soft blotches of lighter and darker stone
	float blotch = fbm3(p * 0.7);
	col *= 0.84 + 0.32 * blotch;
	// bands of slightly different colour, like layers in the rock
	float band = vnoise(vec3(p.x * 0.3, p.y * 2.2, p.z * 0.3));
	col = mix(col, col * vec3(1.08, 0.98, 0.9), smoothstep(0.55, 0.75, band) * 0.6);
	// speckles: tiny light and dark grains
	float g = hash3(floor(p * 16.0));
	col *= 1.0 + (step(0.93, g) * 0.14 - step(g, 0.06) * 0.16) * (1.0 - snow);
	// cracks: thin dark lines winding over the surface
	float c = abs(vnoise(p * vec3(0.9, 1.6, 0.9) + 11.0) - 0.5);
	float crack = 1.0 - smoothstep(0.012, 0.035, c);
	crack *= smoothstep(0.4, 0.6, vnoise(p * 0.35 + 5.0));   // not everywhere
	col *= 1.0 - crack * 0.45;
	// lichen: crusty yellow and orange spots, mostly on the sides and top
	float lichen = smoothstep(0.62, 0.7, fbm3(p * 1.3 + 21.0)) * smoothstep(-0.3, 0.4, n.y);
	vec3 lc = mix(lichen_color.rgb, lichen_orange.rgb, step(0.5, vnoise(p * 0.4 + 2.0)));
	col = mix(col, lc * (0.85 + 0.3 * g), lichen * 0.75 * (1.0 - snow));
	// moss on the tops
	float moss = smoothstep(0.55, 0.85, n.y) * smoothstep(0.45, 0.6, fbm3(p * 0.9 + 40.0));
	col = mix(col, moss_color.rgb * (0.8 + 0.4 * blotch), moss * 0.8 * (1.0 - snow));
	return col;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	if (rocky) {
		vec3 seed = fract((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz * 0.0137) * 300.0;
		ALBEDO = rock_texture(COLOR.rgb, v_local, normalize(v_local_normal), seed);
	}
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
