shader_type spatial;
// Trees, rocks and logs: colours from the model. Trees sway gently in the wind
// (rocks and logs use sway = 0).
render_mode cull_back, diffuse_lambert_wrap;

uniform float sway = 0.0;           // metres of movement per metre of height
uniform float wind_speed = 0.9;

void vertex() {
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
