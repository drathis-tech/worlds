shader_type spatial;
// Soft, puffy clouds: white on top, bluish underneath, light wraps round them.
render_mode blend_mix, diffuse_lambert_wrap, specular_disabled, cull_back;

uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.76, 0.84, 0.91, 1.0);
uniform float glow = 0.25;
uniform float opacity = 0.92;

varying float v_height;
varying vec3 v_world;

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
	v_height = VERTEX.y;  // each puff's local up points away from the planet
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = mix(bottom_color.rgb, top_color.rgb, smoothstep(-0.7, 0.6, v_height));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	EMISSION = col * glow;
	BACKLIGHT = vec3(0.35);
	// soft, wispy, see-through edges make the puffs look fluffy
	float wisp = vnoise(v_world * 0.12 + vec3(TIME * 0.05)) * 0.6 + vnoise(v_world * 0.35) * 0.4;
	float facing = dot(NORMAL, VIEW);
	ALPHA = smoothstep(0.05, 0.75, facing + (wisp - 0.5) * 0.55) * opacity;
}
