class_name CityPlanet
extends Node3D
## A planet that is one huge city: skyscrapers everywhere, always night
## (it drifts alone, far from any star), neon signs, flying traffic and rain.
##
## Works like Planet: same gravity, landing sites and helper functions, so
## the walker, ships and HUD work on both.

signal loaded  ## The city is built and collision is ready around the focus.

## Different number = different city.
@export var planet_seed: int = 3
## Radius in metres. 1000 m = about 20 minutes to walk around.
@export var radius: float = 1000.0
## Gets collision (player, ship or camera). Empty = the active camera.
@export var focus: Node3D
## Gravity at ground level, in m/s².
@export var surface_gravity: float = 9.8
## Optional: a ship or player placed on the first landing pad at the start.
@export var start_at_landing_site: Node3D

@export_group("City")
## Tallest towers, in metres.
@export var max_height: float = 420.0
## Flying cars in lanes over the avenues.
@export var traffic: bool = true
## Rain falling around the camera.
@export var rain: bool = true
## Haze: at this distance things are half hidden. 0 = no haze.
@export var haze_distance: float = 600.0
## Glowing clouds drifting over the city.
@export var clouds: bool = true
## Let characters climb up the outside of buildings (like cliffs).
@export var climbable_buildings: bool = true

var landing_sites: Array[Marker3D] = []
## [direction, height] of the tallest tower, handy for cameras.
var tallest := [Vector3.UP, 0.0]

var _cores: Array[Vector3] = []
var _density: FastNoiseLite
var _rng := RandomNumberGenerator.new()
var _regions := {}        # region id -> {"center": Vector3, "boxes": Array}
var _collision_body: StaticBody3D
var _last_collide := Vector3(INF, INF, INF)
var _sky_material: ShaderMaterial
var _environment: Environment
var _atmosphere: MeshInstance3D
var _rain: CPUParticles3D
var _mats := {}

const CORE_COUNT := 9
const COLLIDE_REACH := 150.0


func _ready() -> void:
	add_to_group("planets")
	_rng.seed = planet_seed * 92821 + 7
	_density = FastNoiseLite.new()
	_density.seed = planet_seed * 31
	_density.frequency = 2.2
	_density.fractal_octaves = 3
	for _i in CORE_COUNT:
		_cores.append(Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()).normalized())

	_make_materials()
	_build_ground()
	_build_city()
	if traffic:
		_build_traffic()
	if clouds:
		_build_clouds()
	_add_gravity()
	_add_atmosphere()
	_setup_sky()
	if rain:
		_make_rain()
	_collision_body = StaticBody3D.new()
	_collision_body.name = "BuildingCollision"
	if climbable_buildings:
		_collision_body.add_to_group("planet_ground")
	add_child(_collision_body)
	if start_at_landing_site != null:
		place_at_landing_site.call_deferred(start_at_landing_site)
	_finish_loading.call_deferred()


func _finish_loading() -> void:
	await get_tree().physics_frame
	_update_collision(true)
	await get_tree().physics_frame
	loaded.emit()


# ---------------------------------------------------------------------------
# Helpers (same as Planet)
# ---------------------------------------------------------------------------
## The city ground is flat: always 0 m.
func ground_height_at(_world_position: Vector3) -> float:
	return 0.0


func up_at(world_position: Vector3) -> Vector3:
	return (world_position - global_position).normalized()


func altitude_of(world_position: Vector3) -> float:
	return to_local(world_position).length() - radius


func place_at_landing_site(node: Node3D, index: int = 0, height: float = 1.0) -> void:
	if landing_sites.is_empty():
		return
	var site := landing_sites[index % landing_sites.size()]
	var b := site.global_transform.basis.orthonormalized()
	node.global_transform = Transform3D(b, site.global_position + b.y * height)
	if node is CharacterBody3D:
		node.velocity = Vector3.ZERO
	_update_collision(true)


func _focus_position() -> Vector3:
	var node := focus
	if node == null:
		node = get_viewport().get_camera_3d()
	if node == null:
		return Vector3(0, 0, radius * 3.0)
	return to_local(node.global_position)


static func _basis_with_up(up: Vector3) -> Basis:
	return PlanetScatter.basis_with_up(up)


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
func _make_materials() -> void:
	var b := ShaderMaterial.new()
	b.shader = preload("shaders/city_building.gdshader")
	b.set_shader_parameter("planet_radius", radius)
	_mats["building"] = b
	var s := ShaderMaterial.new()
	s.shader = preload("shaders/city_sign.gdshader")
	_mats["sign"] = s
	var h := s.duplicate()
	h.set_shader_parameter("holo", true)
	_mats["holo"] = h
	var pole := StandardMaterial3D.new()
	pole.albedo_color = Color(0.1, 0.1, 0.12)
	pole.metallic = 0.6
	pole.roughness = 0.4
	_mats["pole"] = pole
	var head := StandardMaterial3D.new()
	head.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head.albedo_color = Color(1.0, 0.8, 0.55)
	_mats["head"] = head
	var bollard := head.duplicate()
	bollard.albedo_color = Color(0.3, 0.95, 1.0)
	_mats["bollard"] = bollard


func _set_center_uniforms() -> void:
	for key in ["building"]:
		(_mats[key] as ShaderMaterial).set_shader_parameter("planet_center", global_position)


# ---------------------------------------------------------------------------
# Ground: a smooth sphere with roads painted on by the shader
# ---------------------------------------------------------------------------
func _build_ground() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 384
	sphere.rings = 192
	var m := ShaderMaterial.new()
	m.shader = preload("shaders/city_ground.gdshader")
	m.set_shader_parameter("planet_radius", radius)
	m.set_shader_parameter("blocks", CityLayout.BLOCKS)
	m.set_shader_parameter("avenue_every", CityLayout.AVENUE_EVERY)
	m.set_shader_parameter("street_half", CityLayout.STREET_HALF)
	m.set_shader_parameter("avenue_half", CityLayout.AVENUE_HALF)
	m.set_shader_parameter("sidewalk", CityLayout.SIDEWALK)
	m.set_shader_parameter("city_seed", planet_seed)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = sphere
	ground.material_override = m
	add_child(ground)
	# The ground is a perfect sphere, so its collision is a sphere too (cheap).
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	body.add_to_group("planet_ground")
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	add_child(body)


# ---------------------------------------------------------------------------
# Buildings, signs, street lights, plazas
# ---------------------------------------------------------------------------
func _core_strength(d: Vector3) -> float:
	var sigma := 170.0 / radius
	var best := 0.0
	for c in _cores:
		best = maxf(best, exp(-2.0 * (1.0 - d.dot(c)) / (sigma * sigma)))
	return best


func _region(rid: int) -> Dictionary:
	if not _regions.has(rid):
		_regions[rid] = {"center": Vector3.ZERO, "boxes": [], "b": [], "s": [], "holo": [],
				"pole": [], "head": [], "bollard": []}
	return _regions[rid]


func _build_city() -> void:
	var N := CityLayout.BLOCKS
	var per_region := N / 4
	for f in 6:
		for i in N:
			for j in N:
				var reg := _region(f * 16 + (i / per_region) * 4 + (j / per_region))
				_build_block(f, i, j, reg)
	# Landing pads near the middle of a cube side come first: the streets there
	# meet at right angles, which makes the nicest place to start.
	landing_sites.sort_custom(func(a: Marker3D, b: Marker3D) -> bool:
		var ca := CityLayout.coords(a.position.normalized())
		var cb := CityLayout.coords(b.position.normalized())
		return absf(ca.y) + absf(ca.z) < absf(cb.y) + absf(cb.z))
	for rid in _regions:
		var reg: Dictionary = _regions[rid]
		var f: int = rid / 16
		var ri: int = (rid % 16) / 4
		var rj: int = rid % 4
		reg["center"] = CityLayout.dir_from(f, ((ri + 0.5) / 4.0) * 2.0 - 1.0, ((rj + 0.5) / 4.0) * 2.0 - 1.0) * radius
		_make_multimesh(reg["b"], _unit_box(), _mats["building"], 0.0, "Buildings")
		_make_multimesh(reg["s"], _unit_quad(), _mats["sign"], 900.0, "Signs")
		_make_multimesh(reg["holo"], _unit_quad(), _mats["holo"], 0.0, "Billboards")
		_make_multimesh(reg["pole"], _box(Vector3(0.16, 6.0, 0.16)), _mats["pole"], 450.0, "LampPoles")
		_make_multimesh(reg["head"], _box(Vector3(0.9, 0.22, 0.38)), _mats["head"], 700.0, "LampHeads")
		_make_multimesh(reg["bollard"], _box(Vector3(0.3, 1.0, 0.3)), _mats["bollard"], 500.0, "Bollards")
		for key in ["b", "s", "holo", "pole", "head", "bollard"]:
			reg.erase(key)   # only the collision boxes are kept


func _build_block(f: int, i: int, j: int, reg: Dictionary) -> void:
	var x0 := CityLayout.line_coord(i)
	var x1 := CityLayout.line_coord(i + 1)
	var y0 := CityLayout.line_coord(j)
	var y1 := CityLayout.line_coord(j + 1)
	var xm := (x0 + x1) * 0.5
	var ym := (y0 + y1) * 0.5
	var c := CityLayout.dir_from(f, xm, ym)
	# true size of this block in metres
	var ex := CityLayout.dir_from(f, x1, ym) - CityLayout.dir_from(f, x0, ym)
	var ny := CityLayout.dir_from(f, xm, y1) - CityLayout.dir_from(f, xm, y0)
	var width_m := ex.length() * radius
	var height_m := ny.length() * radius
	var east := (ex - c * ex.dot(c)).normalized()
	var north := east.cross(c)                    # right-handed with (east, up, north)
	var grid_n := north if north.dot(ny) > 0.0 else -north
	var skew := absf(east.dot(ny.normalized()))   # grid lines meet at an angle near cube corners

	var hl := CityLayout.road_half(i)
	var hr := CityLayout.road_half(i + 1)
	var hb := CityLayout.road_half(j)
	var ht := CityLayout.road_half(j + 1)

	# Street lights on the sidewalks, on all four sides.
	for p in [1.0 / 6.0, 0.5, 5.0 / 6.0]:
		_lamp(reg, CityLayout.dir_from(f, CityLayout.line_coord(i + (hl + 0.8) / width_m), CityLayout.line_coord(j + p)), -east)
		_lamp(reg, CityLayout.dir_from(f, CityLayout.line_coord(i + 1 - (hr + 0.8) / width_m), CityLayout.line_coord(j + p)), east)
		_lamp(reg, CityLayout.dir_from(f, CityLayout.line_coord(i + p), CityLayout.line_coord(j + (hb + 0.8) / height_m)), -grid_n)
		_lamp(reg, CityLayout.dir_from(f, CityLayout.line_coord(i + p), CityLayout.line_coord(j + 1 - (ht + 0.8) / height_m)), grid_n)

	if CityLayout.is_plaza(f, i, j, planet_seed):
		_build_plaza(reg, c, east, north)
		return

	# The buildable area inside the sidewalks, in grid units.
	var u0 := i + (hl + CityLayout.SIDEWALK) / width_m
	var u1 := i + 1 - (hr + CityLayout.SIDEWALK) / width_m
	var v0 := j + (hb + CityLayout.SIDEWALK) / height_m
	var v1 := j + 1 - (ht + CityLayout.SIDEWALK) / height_m
	var dens := clampf(_density.get_noise_3dv(c) * 0.7 + 0.5, 0.0, 1.0)
	var core := _core_strength(c)
	var k := 1 if core > 0.45 else (2 if dens > 0.55 or _rng.randf() < 0.3 else 3)
	var alley := 2.0
	for a in k:
		for b in k:
			var gu := u0 + (u1 - u0) * (a + 0.5) / k
			var gv := v0 + (v1 - v0) * (b + 0.5) / k
			var d := CityLayout.dir_from(f, CityLayout.line_coord(gu), CityLayout.line_coord(gv))
			var lw := ((u1 - u0) / k * width_m - alley) * (1.0 - skew * 0.9)
			var ld := ((v1 - v0) / k * height_m - alley) * (1.0 - skew * 0.9)
			var lot_core := _core_strength(d)
			_building(reg, d, east, north, lw, ld, dens, lot_core)


func _box_entry(reg: Dictionary, up: Vector3, east: Vector3, north: Vector3, sx: float, th: float, sz: float, bottom: float) -> Vector3:
	var origin := up * (radius + bottom + th * 0.5)
	reg["b"].append(Transform3D(Basis(east * sx, up * th, north * sz), origin))
	reg["boxes"].append([Transform3D(Basis(east, up, north), origin), Vector3(sx, th, sz) * 0.5])
	return origin


func _building(reg: Dictionary, up: Vector3, east: Vector3, north: Vector3, lw: float, ld: float, dens: float, core: float) -> void:
	var h := lerpf(14.0, 95.0, pow(dens, 1.4)) * _rng.randf_range(0.55, 1.45)
	h += core * _rng.randf_range(150.0, max_height - 40.0)
	if _rng.randf() < 0.06 and dens > 0.45:
		h *= 1.9   # the odd lone tower sticking up out of its district
	h = clampf(h, 9.0, max_height)
	var w := lw * _rng.randf_range(0.72, 0.97)
	var dp := ld * _rng.randf_range(0.72, 0.97)
	if h > 160.0:
		w *= 0.85
		dp *= 0.85
	if w < 4.0 or dp < 4.0:
		return
	var tiers := 1 if h < 60.0 else (2 if h < 160.0 else 3)
	var fractions: Array = [[1.0], [0.62, 0.38], [0.5, 0.3, 0.2]][tiers - 1]
	var scales := [1.0, _rng.randf_range(0.68, 0.85), _rng.randf_range(0.45, 0.62)]
	var bottom := -1.0
	for t in tiers:
		var th: float = h * fractions[t] + (1.0 if t == 0 else 0.0)
		var sx: float = w * scales[t]
		var sz: float = dp * scales[t]
		_box_entry(reg, up, east, north, sx, th, sz, bottom)
		if t == 0:
			_signs(reg, up, east, north, sx, sz, th, dens)
		if h > 150.0 and t < 2 and _rng.randf() < 0.45:
			_billboard(reg, up, east, north, sx, sz, bottom, th)
		bottom += th
	if h > 170.0 and _rng.randf() < 0.65:
		var sh := _rng.randf_range(18.0, 45.0)
		_box_entry(reg, up, east, north, 1.4, sh, 1.4, bottom)
		bottom += sh
	if bottom > tallest[1]:
		tallest = [up, bottom]


## Neon signs on the lower part of a building: flat ones on the walls and
## tall ones sticking out at the corners.
func _signs(reg: Dictionary, up: Vector3, east: Vector3, north: Vector3, sx: float, sz: float, th: float, dens: float) -> void:
	var count := _rng.randi_range(0, 2) + (1 if dens > 0.5 else 0)
	for _n in count:
		var side := _rng.randi() % 4
		var normal: Vector3 = [east, -east, north, -north][side]
		var along: Vector3 = [north, north, east, east][side]
		var half_depth: float = [sx, sx, sz, sz][side] * 0.5
		var face_w: float = [sz, sz, sx, sx][side]
		var alt := _rng.randf_range(4.5, minf(th - 2.0, 40.0))
		if alt < 4.5:
			continue
		var base := up * (radius + alt)
		if _rng.randf() < 0.35:
			# a tall sign sticking out from the corner, readable from down the street
			var sw := _rng.randf_range(1.2, 2.0)
			var sh := _rng.randf_range(5.0, 13.0)
			var pos := base + normal * (half_depth + sw * 0.5 + 0.1) + along * (face_w * 0.5 - 0.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
			reg["s"].append(Transform3D(Basis(normal * sw, up * sh, along), pos))
		else:
			var sw := _rng.randf_range(2.5, minf(11.0, face_w * 0.8))
			var sh := _rng.randf_range(1.2, 3.5)
			var slack := maxf(face_w * 0.5 - sw * 0.5 - 0.3, 0.0)
			var pos := base + normal * (half_depth + 0.25) + along * _rng.randf_range(-slack, slack)
			reg["s"].append(Transform3D(Basis(along * sw, up * sh, normal), pos))


## A big glowing holographic billboard on the side of a tall tower.
func _billboard(reg: Dictionary, up: Vector3, east: Vector3, north: Vector3, sx: float, sz: float, bottom: float, th: float) -> void:
	var side := _rng.randi() % 4
	var normal: Vector3 = [east, -east, north, -north][side]
	var along: Vector3 = [north, north, east, east][side]
	var half_depth: float = [sx, sx, sz, sz][side] * 0.5
	var face_w: float = [sz, sz, sx, sx][side]
	var bw := minf(_rng.randf_range(14.0, 22.0), face_w * 0.85)
	var bh := minf(bw * _rng.randf_range(1.2, 1.6), th * 0.7)
	if bw < 8.0 or bh < 8.0:
		return
	var alt := bottom + _rng.randf_range(bh * 0.6, maxf(th - bh * 0.6, bh * 0.6))
	reg["holo"].append(Transform3D(Basis(along * bw, up * bh, normal), up * (radius + alt) + normal * (half_depth + 0.6)))


func _lamp(reg: Dictionary, d: Vector3, toward_road: Vector3) -> void:
	var flat := (toward_road - d * toward_road.dot(d)).normalized()
	reg["pole"].append(Transform3D(_basis_with_up(d), d * (radius + 3.0)))
	# the lamp head's long side points out over the road
	reg["head"].append(Transform3D(Basis(flat, d, flat.cross(d)), d * (radius + 6.0) + flat * 0.45))


func _build_plaza(reg: Dictionary, c: Vector3, east: Vector3, north: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = "LandingSite_%d" % (landing_sites.size() + 1)
	marker.transform = Transform3D(Basis(east, c, north), c * radius)
	marker.gizmo_extents = 10.0
	add_child(marker)
	landing_sites.append(marker)
	# glowing bollards around the landing pad
	for n in 12:
		var a := n * TAU / 12.0
		var p := (c + (east * cos(a) + north * sin(a)) * (15.0 / radius)).normalized()
		reg["bollard"].append(Transform3D(_basis_with_up(p), p * (radius + 0.5)))


func _unit_box() -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3.ONE
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _unit_quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	return q


func _make_multimesh(list: Array, mesh: Mesh, mat: Material, draw_distance: float, name: String) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = mat
	if draw_distance > 0.0:
		mmi.visibility_range_end = draw_distance
		mmi.visibility_range_end_margin = draw_distance * 0.1
	add_child(mmi)


# ---------------------------------------------------------------------------
# Collision: only the buildings near the focus get collision boxes
# ---------------------------------------------------------------------------
func _update_collision(force := false) -> void:
	if _collision_body == null:
		return
	var f := _focus_position()
	if not force and f.distance_to(_last_collide) < 15.0:
		return
	_last_collide = f
	for c in _collision_body.get_children():
		_collision_body.remove_child(c)
		c.free()
	var region_reach := radius * PI * 0.25 * 0.75 + COLLIDE_REACH
	for rid in _regions:
		var reg: Dictionary = _regions[rid]
		if (reg["center"] as Vector3).distance_to(f) > region_reach + 450.0:
			continue
		for box in reg["boxes"]:
			var t: Transform3D = box[0]
			var half: Vector3 = box[1]
			if t.origin.distance_to(f) > COLLIDE_REACH + half.y:
				continue
			var shape := BoxShape3D.new()
			shape.size = half * 2.0
			var col := CollisionShape3D.new()
			col.shape = shape
			col.transform = t
			_collision_body.add_child(col)


# ---------------------------------------------------------------------------
# Flying traffic: lanes of cars over the avenues, moved by the shader
# ---------------------------------------------------------------------------
func _build_traffic() -> void:
	var car := BoxMesh.new()
	car.size = Vector3(1.8, 0.7, 3.8)
	var holder := Node3D.new()
	holder.name = "Traffic"
	add_child(holder)
	var N := CityLayout.BLOCKS
	var big := AABB(Vector3.ONE * -radius * 1.6, Vector3.ONE * radius * 3.2)
	for f in 6:
		for axis in 2:
			for k in range(CityLayout.AVENUE_EVERY, N, CityLayout.AVENUE_EVERY):
				var x := CityLayout.line_coord(k)
				var a := CityLayout.dir_from(f, x, -1.0) if axis == 0 else CityLayout.dir_from(f, -1.0, x)
				var b := CityLayout.dir_from(f, x, 1.0) if axis == 0 else CityLayout.dir_from(f, 1.0, x)
				var c := CityLayout.dir_from(f, x, 0.0) if axis == 0 else CityLayout.dir_from(f, 0.0, x)
				var lane_range := a.angle_to(b)
				var Y := a.cross(b).normalized()
				var Z := c.cross(Y)
				if Z.dot(b) < 0.0:
					Y = -Y
					Z = c.cross(Y)
				var frame := Transform3D(Basis(c, Y, Z), Vector3.ZERO)
				# two low lanes (one each way) down the avenue canyon, one high lane
				var low := 26.0 if axis == 0 else 33.0
				var lanes := [[low, 3.5, 13.0], [low, -3.5, -13.0], [_rng.randf_range(150.0, 260.0), 0.0, 24.0 * (1.0 if _rng.randf() < 0.5 else -1.0)]]
				for lane in lanes:
					var r: float = radius + lane[0]
					var spacing := _rng.randf_range(26.0, 55.0)
					var count := int(r * lane_range / spacing)
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.mesh = car
					mm.instance_count = count
					for n in count:
						mm.set_instance_transform(n, Transform3D.IDENTITY)
					var mat := ShaderMaterial.new()
					mat.shader = preload("shaders/city_car.gdshader")
					mat.set_shader_parameter("lane_r", r)
					mat.set_shader_parameter("lane_range", lane_range)
					mat.set_shader_parameter("speed", lane[2])
					mat.set_shader_parameter("count", float(count))
					mat.set_shader_parameter("phase", _rng.randf() * lane_range)
					mat.set_shader_parameter("side", lane[1])
					var mmi := MultiMeshInstance3D.new()
					mmi.multimesh = mm
					mmi.material_override = mat
					mmi.custom_aabb = big
					mmi.transform = frame
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					holder.add_child(mmi)


# ---------------------------------------------------------------------------
# Clouds, gravity, atmosphere, sky, rain
# ---------------------------------------------------------------------------
func _build_clouds() -> void:
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 16
	puff.rings = 8
	var transforms: Array[Transform3D] = []
	for _c in 45:
		var d := Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()).normalized()
		var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var along := t1.rotated(d, _rng.randf() * TAU)
		var across := d.cross(along)
		var length := _rng.randf_range(80.0, 220.0)
		var alt := radius + max_height + _rng.randf_range(20.0, 90.0)
		for _p in int(length / 10.0) + 3:
			var x := _rng.randf_range(-1.0, 1.0)
			var y := _rng.randf_range(-0.3, 0.3) * (1.0 - absf(x))
			var s := _rng.randf_range(16.0, 34.0) * (1.0 - absf(x) * 0.5)
			var p := (d * alt + along * x * length + across * y * length).normalized()
			transforms.append(Transform3D(_basis_with_up(p).scaled(Vector3(s * 1.3, s * 0.5, s)), p * alt))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = puff
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var m := ShaderMaterial.new()
	m.shader = preload("../shaders/clouds.gdshader")
	# lit from below by the city: dark on top, pink-orange underneath
	m.set_shader_parameter("top_color", Color(0.07, 0.05, 0.12))
	m.set_shader_parameter("bottom_color", Color(0.55, 0.26, 0.45))
	m.set_shader_parameter("glow", 0.4)
	m.set_shader_parameter("opacity", 0.45)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Clouds"
	mmi.multimesh = mm
	mmi.material_override = m
	add_child(mmi)


func _add_gravity() -> void:
	var area := Area3D.new()
	area.name = "Gravity"
	area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	area.gravity_point = true
	area.gravity_point_center = Vector3.ZERO
	area.gravity_point_unit_distance = radius
	area.gravity = surface_gravity
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius * 4.0
	col.shape = sphere
	area.add_child(col)
	add_child(area)


func _add_atmosphere() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius * 1.12
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var m := ShaderMaterial.new()
	m.shader = preload("../shaders/atmosphere.gdshader")
	m.set_shader_parameter("glow_color", Color(0.6, 0.28, 0.9))
	m.set_shader_parameter("strength", 0.9)
	_atmosphere = MeshInstance3D.new()
	_atmosphere.name = "Atmosphere"
	_atmosphere.mesh = sphere
	_atmosphere.material_override = m
	_atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_atmosphere)


func _setup_sky() -> void:
	var scene_root := get_tree().current_scene if get_tree().current_scene else get_parent()
	var world := _find_world_environment(scene_root)
	if world == null:
		world = WorldEnvironment.new()
		world.name = "CitySky"
		add_child(world)
	if world.environment == null:
		world.environment = Environment.new()
	_environment = world.environment
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = preload("shaders/city_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	# no sun: the city is lit by its own lights and a little galaxy glow
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.32, 0.27, 0.48)
	_environment.ambient_light_energy = 0.55
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_exposure = 1.1
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.9
	_environment.glow_strength = 1.1
	_environment.glow_bloom = 0.08
	_environment.glow_hdr_threshold = 0.85
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_environment.fog_enabled = haze_distance > 0.0
	_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_environment.fog_light_color = Color(0.3, 0.15, 0.4)
	_environment.fog_light_energy = 1.0
	_environment.fog_sky_affect = 0.0
	_environment.fog_aerial_perspective = 0.15
	# shiny wet streets (only with the Forward+ renderer)
	_environment.ssr_enabled = true
	_environment.ssr_max_steps = 48


func _find_world_environment(node: Node) -> WorldEnvironment:
	if node == null:
		return null
	if node is WorldEnvironment:
		return node
	for c in node.get_children():
		var found := _find_world_environment(c)
		if found:
			return found
	return null


func _make_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 2500
	_rain.lifetime = 1.3
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(30.0, 1.0, 30.0)
	_rain.direction = Vector3(0, -1, 0)
	_rain.spread = 4.0
	_rain.initial_velocity_min = 20.0
	_rain.initial_velocity_max = 26.0
	_rain.particle_flag_align_y = true
	var drop := BoxMesh.new()
	drop.size = Vector3(0.02, 0.9, 0.02)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 1.0, 0.3)
	drop.material = m
	_rain.mesh = drop
	add_child(_rain)


func _process(_delta: float) -> void:
	_set_center_uniforms()
	_update_collision()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var local := to_local(cam.global_position)
	var altitude := local.length() - radius
	var up := global_basis * local.normalized()
	var space := smoothstep(radius * 0.3, radius * 0.9, altitude)
	(_atmosphere.material_override as ShaderMaterial).set_shader_parameter("fade", smoothstep(max_height + 300.0, radius * 1.4, altitude))
	if _sky_material:
		_sky_material.set_shader_parameter("planet_up", up.normalized())
		_sky_material.set_shader_parameter("space_amount", space)
		# how far below level the planet's edge is, seen from up here
		_sky_material.set_shader_parameter("horizon_dip", acos(clampf(radius / (radius + maxf(altitude, 0.0)), -1.0, 1.0)))
	if _environment and haze_distance > 0.0:
		_environment.fog_density = 0.6931 / haze_distance * exp(-maxf(altitude, 0.0) / (radius * 0.4)) * (1.0 - space)
	if _rain:
		_rain.emitting = altitude < max_height + 60.0
		_rain.global_transform = Transform3D(_basis_with_up(up), cam.global_position + up * 14.0)
		_rain.gravity = -up * 12.0
