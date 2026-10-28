shader_type spatial;
// See-through ocean with small moving waves and a brighter rim at low angles.
render_mode blend_mix, cull_back, diffuse_lambert_wrap;

uniform vec4 water_color : source_color = vec4(0.18, 0.73, 0.91, 1.0);
uniform vec4 rim_color : source_color = vec4(0.8, 0.93, 0.98, 1.0);
uniform float clarity : hint_range(0.0, 1.0) = 0.28;   // 1 = very see-through
uniform float wave_strength = 0.12;
uniform float wave_speed = 0.25;

varying vec3 v_pos;

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
	// Seen from far away, sink the water a little under the ground so coasts
	// and polar ice don't flicker (the depth buffer gets coarse with distance).
	float cam_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX -= normalize(VERTEX) * clamp((cam_dist - 300.0) * 0.003, 0.0, 8.0);
}

void fragment() {
	// Wobble the surface normal with two moving noise layers.
	float t = TIME * wave_speed;
	vec3 p = v_pos * 0.35;
	float e = 0.5;
	vec3 o1 = vec3(t, t * 0.7, -t * 0.4);
	float n0 = vnoise(p + o1) + vnoise(p * 2.3 - o1);
	vec3 grad = vec3(
		vnoise(p + vec3(e, 0, 0) + o1) + vnoise((p + vec3(e, 0, 0)) * 2.3 - o1) - n0,
		vnoise(p + vec3(0, e, 0) + o1) + vnoise((p + vec3(0, e, 0)) * 2.3 - o1) - n0,
		vnoise(p + vec3(0, 0, e) + o1) + vnoise((p + vec3(0, 0, e)) * 2.3 - o1) - n0);
	vec3 up = normalize(v_pos);
	grad -= up * dot(grad, up);
	float fade = 1.0 - smoothstep(30.0, 200.0, length(VERTEX));
	vec3 n_local = normalize(up - grad * wave_strength * fade);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_local, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// looking across the water it mirrors the sky colour
	ALBEDO = mix(water_color.rgb, rim_color.rgb, fresnel * 0.85);
	ALPHA = mix(1.0 - clarity, 0.97, fresnel);
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
}
