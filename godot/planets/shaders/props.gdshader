shader_type spatial;
// Trees, rocks and logs: colours from the model. Trees sway gently in the wind
// (rocks and logs use sway = 0).
render_mode cull_back, diffuse_lambert_wrap;

uniform float sway = 0.0;           // metres of movement per metre of height
uniform float wind_speed = 0.9;

uniform float tint_amount = 0.13;

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
	if (sway > 0.0) {
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float h = max(VERTEX.y, 0.0);
		float t = TIME * wind_speed + dot(origin, vec3(0.05, 0.03, 0.07));
		VERTEX.xz += vec2(sin(t), cos(t * 0.71)) * sway * h * (h / 10.0);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
