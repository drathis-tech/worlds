shader_type spatial;
// Small plants (grass, flowers, ferns): colours from the model, swaying in the
// wind, shown from both sides, and shrinking away smoothly at the edge of
// their draw distance instead of popping.
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform float sway = 0.12;          // how far the tips move, per metre of height
uniform float wind_speed = 1.6;
uniform float fade_start = 40.0;    // metres
uniform float fade_end = 55.0;

uniform float tint_amount = 0.12;

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
	// each prop's own colour tint (lighter, darker, warmer, cooler)
	COLOR.rgb *= prop_tint((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, tint_amount);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	// gusts roll across the ground: the phase depends on where the plant is
	float t = TIME * wind_speed + dot(origin, vec3(0.11, 0.07, 0.13));
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + dot(origin, vec3(0.013, 0.009, 0.011)));
	VERTEX.xz += vec2(sin(t), cos(t * 0.83)) * sway * h * h * gust;
	float d = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	VERTEX *= 1.0 - smoothstep(fade_start, fade_end, d);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	// light shining through thin leaves
	BACKLIGHT = COLOR.rgb * 0.35;
}
