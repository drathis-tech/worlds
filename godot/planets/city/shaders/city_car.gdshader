shader_type spatial;
// Flying cars. Each lane is one MultiMesh whose node is turned so the lane
// circles around its Y axis; the shader slides every car along the lane, so
// the traffic costs nothing on the CPU. White headlights, red tail lights and
// a coloured underglow.
render_mode unshaded;

uniform float lane_r = 1030.0;      // lane distance from the planet centre
uniform float lane_range = 1.5;     // length of the lane, as an angle
uniform float speed = 14.0;         // m/s, negative = the other way
uniform float count = 40.0;
uniform float phase = 0.0;
uniform float side = 0.0;           // sideways offset in metres

varying vec3 v_loc;
varying float v_id;

vec3 neon_color(float h) {
	if (h < 0.2) return vec3(1.0, 0.18, 0.55);
	if (h < 0.4) return vec3(0.2, 0.85, 1.0);
	if (h < 0.6) return vec3(0.65, 0.3, 1.0);
	if (h < 0.8) return vec3(1.0, 0.5, 0.12);
	return vec3(0.3, 1.0, 0.55);
}

void vertex() {
	float i = float(INSTANCE_ID);
	float a = mod(TIME * speed / lane_r + i / count * lane_range + phase, lane_range) - lane_range * 0.5;
	vec3 radial = vec3(cos(a), 0.0, sin(a));
	vec3 fwd = vec3(-sin(a), 0.0, cos(a)) * sign(speed);
	vec3 right = normalize(cross(radial, fwd));
	v_loc = VERTEX;
	VERTEX = right * VERTEX.x + radial * VERTEX.y + fwd * VERTEX.z + radial * lane_r + vec3(0.0, side, 0.0);
	NORMAL = right * NORMAL.x + radial * NORMAL.y + fwd * NORMAL.z;
	v_id = fract(i * 0.618 + phase * 3.1);
}

void fragment() {
	vec3 col = vec3(0.05, 0.05, 0.07);
	if (v_loc.z > 1.6) {
		col = vec3(2.2, 2.2, 1.9);          // headlights
	} else if (v_loc.z < -1.6) {
		col = vec3(2.2, 0.15, 0.08);        // tail lights
	} else if (v_loc.y < -0.25) {
		col = neon_color(v_id) * 1.4;       // underglow
	}
	ALBEDO = col;
}
