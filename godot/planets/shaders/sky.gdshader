shader_type sky;
// Painterly sky: a warm glowing horizon on the sun's side, a cooler lavender
// horizon on the other side, a big soft glow around the sun, and starry space
// higher up. On the night side of the planet the sky turns deep blue.
// The planet script keeps planet_up and space_amount in sync with the camera.

uniform vec3 planet_up = vec3(0.0, 1.0, 0.0);
uniform float space_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 sky_top : source_color = vec4(0.42, 0.64, 0.9, 1.0);
uniform vec4 horizon_sun : source_color = vec4(1.0, 0.75, 0.66, 1.0);
uniform vec4 horizon_away : source_color = vec4(0.76, 0.78, 0.94, 1.0);
uniform vec4 sun_glow : source_color = vec4(1.0, 0.82, 0.63, 1.0);
uniform vec4 night_color : source_color = vec4(0.05, 0.07, 0.16, 1.0);
uniform vec4 space_color : source_color = vec4(0.012, 0.016, 0.04, 1.0);
uniform float star_density = 0.0025;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 up = normalize(planet_up);
	float y = dot(dir, up);
	vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : up;
	float c = max(dot(dir, sun), 0.0);

	// which way round the horizon we're looking: 1 = towards the sun
	vec3 flat_dir = normalize(dir - up * y + up * 0.0001);
	vec3 flat_sun = normalize(sun - up * dot(sun, up) + up * 0.0001);
	float towards = dot(flat_dir, flat_sun) * 0.5 + 0.5;
	vec3 horizon = mix(horizon_away.rgb, horizon_sun.rgb, pow(towards, 1.6));

	vec3 day = mix(horizon, sky_top.rgb, pow(smoothstep(-0.03, 0.75, y), 0.65));
	day = mix(day, horizon * 0.9, smoothstep(0.0, -0.3, y));   // below the horizon
	// big soft glow around the sun, and the sun itself
	day += sun_glow.rgb * (pow(c, 6.0) * 0.2 + pow(c, 40.0) * 0.3);
	if (LIGHT0_ENABLED) {
		day += LIGHT0_COLOR * smoothstep(0.9993, 0.9997, c) * 3.0;
	}

	// night side of the planet: deep blue with a little warmth left at the edge
	float sun_height = dot(sun, up);
	float daylight = smoothstep(-0.25, 0.08, sun_height);
	vec3 night = night_color.rgb + horizon_sun.rgb * 0.15 * pow(towards, 3.0) * smoothstep(-0.4, 0.0, sun_height) * (1.0 - smoothstep(0.0, 0.4, y));
	vec3 col = mix(night, day, daylight);

	// stars: tiny bright cells, in space and at night
	vec3 cell = floor(dir * 420.0);
	float s = hash(cell);
	float star = step(1.0 - star_density, s) * (0.5 + 0.5 * hash(cell + 7.1));
	col += vec3(star) * (1.0 - daylight) * 0.8 * step(0.0, y);
	vec3 space = space_color.rgb + vec3(star);
	if (LIGHT0_ENABLED) {
		space += LIGHT0_COLOR * (smoothstep(0.9993, 0.9997, c) * 4.0 + pow(c, 200.0) * 0.4);
	}

	COLOR = mix(col, space, space_amount);
}
