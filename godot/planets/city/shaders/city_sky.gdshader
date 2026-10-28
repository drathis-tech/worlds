shader_type sky;
// Night sky for a planet with no sun: a glowing galaxy band with dark dust
// lanes and thousands of stars. Near the ground the city's light glows pink
// and orange along the horizon and washes out the fainter stars.

uniform vec3 planet_up = vec3(0.0, 1.0, 0.0);
uniform float space_amount : hint_range(0.0, 1.0) = 0.0;
uniform float horizon_dip = 0.0;   // radians: how far below level the planet's edge is
uniform vec4 night_color : source_color = vec4(0.01, 0.01, 0.03, 1.0);
uniform vec4 glow_high : source_color = vec4(0.42, 0.16, 0.45, 1.0);
uniform vec4 glow_low : source_color = vec4(0.95, 0.42, 0.32, 1.0);
uniform vec3 galaxy_normal = vec3(0.35, 0.8, 0.45);
uniform vec3 galaxy_core = vec3(0.8, -0.25, 0.55);

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
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec3(3.1, 1.7, 5.3);
		a *= 0.5;
	}
	return s / 0.9375;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// height above the planet's edge (not above level), so flying high you see stars past it
	float y = dot(dir, normalize(planet_up)) + sin(horizon_dip);
	float pollution = 1.0 - space_amount;
	float clear = 0.35 + 0.65 * space_amount;   // the city's glow hides faint stars

	vec3 col = night_color.rgb;
	// the galaxy: a soft band across the sky, brightest towards its core
	float g = dot(dir, normalize(galaxy_normal));
	float band = exp(-g * g / 0.03);
	float clouds = fbm(dir * 4.0);
	float dust = fbm(dir * 9.0 + 3.0);
	vec3 tint = mix(vec3(0.35, 0.25, 0.6), vec3(0.2, 0.5, 0.75), fbm(dir * 2.5 + 7.0));
	float core = exp(-dot(dir - normalize(galaxy_core), dir - normalize(galaxy_core)) / 0.08);
	vec3 galaxy = tint * band * (0.22 + 0.6 * clouds) + vec3(0.9, 0.75, 0.6) * core * band * 0.5;
	galaxy *= 1.0 - 0.65 * smoothstep(0.45, 0.7, dust);   // dark dust lanes
	col += galaxy * clear;

	// stars, thicker inside the band
	vec3 cell = floor(dir * 520.0);
	float s = hash(cell);
	float density = 0.003 + 0.025 * band;
	col += vec3(step(1.0 - density, s) * (0.35 + 0.65 * hash(cell + 3.1))) * clear;

	// the city's light along the horizon
	vec3 haze = mix(glow_low.rgb, glow_high.rgb, smoothstep(0.0, 0.3, y));
	col = mix(col, haze, pollution * exp(-max(y, 0.0) * 4.5) * 0.85 * step(-0.25, y));
	col = mix(col, glow_low.rgb * 0.55, pollution * smoothstep(0.0, -0.25, y));
	COLOR = col;
}
