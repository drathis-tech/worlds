shader_type spatial;
// Soft blue glow around the planet, seen from space.
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform vec4 glow_color : source_color = vec4(0.56, 0.83, 1.0, 1.0);
uniform float strength = 1.2;
uniform float fade = 1.0;   // 0 on the ground, 1 in space (set by the planet script)

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float glow = pow(rim, 3.0) * strength * fade;
	ALBEDO = glow_color.rgb * glow;
}
