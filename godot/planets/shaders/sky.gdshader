shader_type sky;
// Blue sky with a soft sun near the ground, fading to starry space higher up.
// The planet script keeps planet_up and space_amount in sync with the camera.

uniform vec3 planet_up = vec3(0.0, 1.0, 0.0);
uniform float space_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 sky_color : source_color = vec4(0.44, 0.71, 0.94, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.81, 0.91, 0.98, 1.0);
uniform vec4 space_color : source_color = vec4(0.012, 0.016, 0.04, 1.0);
uniform float star_density = 0.0025;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float y = dot(dir, normalize(planet_up));
	vec3 day = mix(horizon_color.rgb, sky_color.rgb, smoothstep(-0.02, 0.5, y));
	day = mix(day, horizon_color.rgb * 0.92, smoothstep(0.0, -0.3, y));

	// Stars: tiny bright cells, only visible in space.
	vec3 cell = floor(dir * 420.0);
	float s = hash(cell);
	float star = step(1.0 - star_density, s) * (0.5 + 0.5 * hash(cell + 7.1));
	vec3 space = space_color.rgb + vec3(star);

	vec3 col = mix(day, space, space_amount);

	if (LIGHT0_ENABLED) {
		float c = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		float disk = smoothstep(0.9993, 0.9997, c);
		float glow = pow(c, 200.0) * 0.4 + pow(c, 16.0) * 0.05 * (1.0 - space_amount);
		col += LIGHT0_COLOR * (disk * 4.0 + glow);
	}
	COLOR = col;
}
