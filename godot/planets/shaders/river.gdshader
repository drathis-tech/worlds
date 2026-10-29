shader_type spatial;
// Flowing river water. Each corner carries the direction the river flows
// (COLOR.rgb) and how much river is there (COLOR.a). Ripples and streaks of
// foam slide downstream, faster in the middle than at the banks. Rocky
// stretches (UV.x = rapids) run faster, choppier and white with foam.
render_mode blend_mix, cull_back, diffuse_lambert_wrap;

uniform vec4 water_color : source_color = vec4(0.25, 0.7, 0.8, 1.0);
uniform vec4 sky_color : source_color = vec4(0.85, 0.85, 0.95, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float speed = 1.6;   // metres per second in the middle of the river

varying vec3 v_pos;
varying vec3 v_flow;
varying float v_amount;
varying float v_rapids;

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
	v_rapids = UV.x;
}

void fragment() {
	vec3 up = normalize(v_pos);
	vec3 f = v_flow - up * dot(v_flow, up);
	f = length(f) > 0.001 ? normalize(f) : vec3(1.0, 0.0, 0.0);
	vec3 side = cross(up, f);
	float t = TIME * speed * (0.5 + 0.5 * v_amount) * (1.0 + v_rapids * 1.5);   // slower near the banks, fast in rapids
	// The patterns are 3D noise drifting downstream. Averaging a few samples
	// spaced along the flow stretches them into streaks.
	vec3 q = v_pos * 0.22 - f * t * 0.22;
	float stretched = (vnoise(q) + vnoise(q + f * 0.7) + vnoise(q + f * 1.4) + vnoise(q + f * 2.1)) * 0.25;
	float streak = stretched * 0.6 + vnoise(q * 2.3 + vec3(5.0) - f * t * 0.15) * 0.4;
	float foam = smoothstep(0.6, 0.74, streak) * (0.4 + 0.6 * smoothstep(0.2, 0.9, v_amount));
	// rapids: churning white water, broken up into patches and standing waves
	vec3 qr = v_pos * 0.7 - f * t * 0.7;
	float churn = (vnoise(qr) + vnoise(qr + f * 0.6)) * 0.3 + vnoise(qr * 2.7 + vec3(9.0)) * 0.4;
	foam = max(foam, smoothstep(0.62 - v_rapids * 0.1, 0.74 - v_rapids * 0.08, churn) * v_rapids * 0.9);

	// ripples: tilt the surface with moving noise
	vec3 r = v_pos * 0.6 - f * t * 0.6 + vec3(1.3);
	float e = 0.3;
	float n0 = vnoise(r);
	float nx = vnoise(r + f * e) - n0;
	float nz = vnoise(r + side * e) - n0;
	vec3 n_local = normalize(up - (f * nx + side * nz) * (0.6 + v_rapids * 1.4));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(water_color.rgb, sky_color.rgb, fresnel * 0.35);
	col = mix(col, foam_color.rgb, foam);
	ALBEDO = col;
	ROUGHNESS = mix(0.08, 0.6, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(v_amount * 1.6, 0.0, 1.0) * mix(0.8, 0.97, max(fresnel, foam));
}
