shader_type spatial;
// Flowing river water. Each corner carries the direction the river flows
// (COLOR.rgb) and how much river is there (COLOR.a). Ripples and streaks of
// foam slide downstream, faster in the middle than at the banks.
render_mode blend_mix, cull_back, diffuse_lambert_wrap;

uniform vec4 water_color : source_color = vec4(0.25, 0.7, 0.8, 1.0);
uniform vec4 sky_color : source_color = vec4(0.85, 0.85, 0.95, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float speed = 1.6;   // metres per second in the middle of the river

varying vec3 v_pos;
varying vec3 v_flow;
varying float v_amount;

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

void vertex() {
	v_pos = VERTEX;
	v_flow = COLOR.rgb * 2.0 - 1.0;
	v_amount = COLOR.a;
}

void fragment() {
	vec3 up = normalize(v_pos);
	vec3 f = v_flow - up * dot(v_flow, up);
	f = length(f) > 0.001 ? normalize(f) : vec3(1.0, 0.0, 0.0);
	vec3 side = cross(up, f);
	float along = dot(v_pos, f);
	float across = dot(v_pos, side);
	float t = TIME * speed * (0.5 + 0.5 * v_amount);   // slower near the banks

	// streaks stretched along the flow, sliding downstream
	vec3 q = vec3(along * 0.18 - t * 0.18, across * 0.9, 0.0);
	float streak = vnoise(q) * 0.6 + vnoise(q * 2.3 + vec3(-t * 0.3, 0.0, 5.0)) * 0.4;
	float foam = smoothstep(0.62, 0.78, streak) * (0.4 + 0.6 * smoothstep(0.2, 0.9, v_amount));

	// ripples: tilt the surface with moving noise
	vec3 r = vec3(along * 0.6 - t * 0.6, across * 0.6, 1.3);
	float e = 0.3;
	float n0 = vnoise(r);
	float nx = vnoise(r + vec3(e, 0.0, 0.0)) - n0;
	float nz = vnoise(r + vec3(0.0, e, 0.0)) - n0;
	vec3 n_local = normalize(up - (f * nx + side * nz) * 0.6);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(water_color.rgb, sky_color.rgb, fresnel * 0.6);
	col = mix(col, foam_color.rgb, foam);
	ALBEDO = col;
	ROUGHNESS = mix(0.08, 0.6, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(v_amount * 1.6, 0.0, 1.0) * mix(0.8, 0.97, max(fresnel, foam));
}
