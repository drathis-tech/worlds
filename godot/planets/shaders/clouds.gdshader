shader_type spatial;
// Soft, puffy clouds: white on top, bluish underneath, light wraps round them.
render_mode blend_mix, diffuse_lambert_wrap, specular_disabled, cull_back;

uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.76, 0.84, 0.91, 1.0);
uniform float glow = 0.25;

varying float v_height;

void vertex() {
	v_height = VERTEX.y;  // each puff's local up points away from the planet
}

void fragment() {
	vec3 col = mix(bottom_color.rgb, top_color.rgb, smoothstep(-0.7, 0.6, v_height));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	EMISSION = col * glow;
	BACKLIGHT = vec3(0.35);
	// soft, see-through edges make the puffs look fluffy
	ALPHA = smoothstep(0.0, 0.55, dot(NORMAL, VIEW));
}
