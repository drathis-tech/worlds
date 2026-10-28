class_name Planet
extends Node3D
## A full-size, explorable planet, built while the game runs.
##
## Drop a Planet node into a scene and press Play. Change the seed for a
## different planet. Set Focus to your player or ship so the ground near
## them gets the most detail (if empty, the active camera is used).

signal loaded  ## The ground around the focus has finished loading.

@export var preset: PlanetPreset = preload("presets/earthlike.tres")
## Different number = different planet.
@export var planet_seed: int = 7
## Radius in metres. 2300 m = about 20 minutes to run around (48 minutes walking).
@export var radius: float = 2300.0
## Gets the most ground detail. Empty = the active camera.
@export var focus: Node3D
## Gravity at ground level, in m/s². Earth is 9.8.
@export var surface_gravity: float = 9.8
## Optional: a ship or player placed on the first landing site at the start.
@export var start_at_landing_site: Node3D

@export_group("Detail")
## How finely the ground near the focus is built. 7 = about 0.9 m on a 2.3 km planet.
@export_range(3, 9) var ground_detail: int = 7
## Higher = detailed ground reaches further out (slower).
@export_range(1.5, 4.0) var detail_distance: float = 2.2
## Trees, bushes and rocks.
@export var props: PackedScene = preload("models/props.glb")
## Props further away than this are hidden.
@export var prop_draw_distance: float = 380.0
## How many places are tried for big rock formations (per 1 km of radius squared).
@export var rock_formations: int = 12000

@export_group("Sky")
## Let this planet control the sky, sun, shadows and haze while the camera is near it.
@export var control_sky: bool = true
## The lighting mood: golden_hour, pink_dusk or day (in presets/).
@export var lighting: PlanetLighting = preload("presets/golden_hour.tres")
## The sun. Empty = the first DirectionalLight3D in the scene.
@export var sun: DirectionalLight3D
## Turn the sun so it sits at the lighting's height over the first landing site.
@export var aim_sun_at_start: bool = true
## Low clouds that drift around mountain tops.
@export var low_clouds: bool = true

var shape: PlanetShape
var terrain: PlanetTerrain
var landing_sites: Array[Marker3D] = []

var _ocean: MeshInstance3D
var _atmosphere: MeshInstance3D
var _clouds: MultiMeshInstance3D
var _sky_material: ShaderMaterial
var _environment: Environment
var _scatter: PlanetScatter


func _ready() -> void:
	add_to_group("planets")
	shape = PlanetShape.new(preset, radius, planet_seed)
	var sites := shape.find_landing_sites(preset.landing_sites, 30.0, planet_seed)

	_scatter = PlanetScatter.new(shape, preset, planet_seed, props, prop_draw_distance)

	terrain = PlanetTerrain.new()
	terrain.name = "Terrain"
	terrain.max_depth = ground_detail
	terrain.collision_depth = ground_detail - 1
	terrain.scatter_depth = maxi(2, ground_detail - 2)
	terrain.split_distance = detail_distance
	terrain.focus = focus
	if _scatter.has_props():
		terrain.scatter_maker = _scatter.make_data
		terrain.scatter_builder = _scatter.build_node
	terrain.setup(shape, _terrain_material())
	terrain.first_load_finished.connect(_on_first_load)
	add_child(terrain)

	_add_ocean()
	_add_atmosphere()
	_add_clouds()
	_add_gravity()
	_add_landing_sites(sites)
	_add_rock_formations()
	if control_sky:
		_setup_sky()
		_setup_sun()
	if start_at_landing_site != null:
		# Put it on the site now, so the ground there loads first, and hold it
		# still until there is ground to stand on.
		place_at_landing_site.call_deferred(start_at_landing_site)
		start_at_landing_site.process_mode = Node.PROCESS_MODE_DISABLED


func _on_first_load() -> void:
	if start_at_landing_site != null:
		place_at_landing_site(start_at_landing_site)
		start_at_landing_site.process_mode = Node.PROCESS_MODE_INHERIT
	loaded.emit()


## Height of the ground in metres above sea level, under a world position.
func ground_height_at(world_position: Vector3) -> float:
	return shape.height(to_local(world_position).normalized())


## The "up" direction (away from the planet centre) at a world position.
func up_at(world_position: Vector3) -> Vector3:
	return (world_position - global_position).normalized()


## Altitude above sea level of a world position, in metres.
func altitude_of(world_position: Vector3) -> float:
	return to_local(world_position).length() - radius


## Moves a ship or player onto a landing site, standing upright.
func place_at_landing_site(node: Node3D, index: int = 0, height: float = 1.5) -> void:
	if landing_sites.is_empty():
		push_warning("Planet: no landing sites found")
		return
	var site := landing_sites[index % landing_sites.size()]
	var b := site.global_transform.basis.orthonormalized()
	node.global_transform = Transform3D(b, site.global_position + b.y * height)
	if node is CharacterBody3D or node is RigidBody3D:
		node.set("velocity", Vector3.ZERO)
		node.set("linear_velocity", Vector3.ZERO)


func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("shaders/terrain.gdshader")
	m.set_shader_parameter("planet_radius", radius)
	m.set_shader_parameter("snow_line", preset.snow_line * radius)
	for p in ["grass_light", "grass_dark", "grass_dry", "forest_floor", "rock_light", "rock_dark",
			"snow", "snow_shadow", "ice", "taiga_grass", "sand", "shallow_water", "deep_water",
			"dirt", "dirt_dark"]:
		m.set_shader_parameter(p, preset.get(p))
	return m


func _add_ocean() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 384
	sphere.rings = 192
	var m := ShaderMaterial.new()
	m.shader = preload("shaders/water.gdshader")
	m.set_shader_parameter("water_color", preset.water)
	m.set_shader_parameter("rim_color", lighting.horizon_sun.lerp(lighting.sky_top, 0.3))
	_ocean = MeshInstance3D.new()
	_ocean.name = "Ocean"
	_ocean.mesh = sphere
	_ocean.material_override = m
	_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ocean)


func _add_atmosphere() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius * 1.18
	sphere.height = radius * 2.36
	sphere.radial_segments = 96
	sphere.rings = 48
	var m := ShaderMaterial.new()
	m.shader = preload("shaders/atmosphere.gdshader")
	m.set_shader_parameter("glow_color", preset.atmosphere)
	_atmosphere = MeshInstance3D.new()
	_atmosphere.name = "Atmosphere"
	_atmosphere.mesh = sphere
	_atmosphere.material_override = m
	_atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_atmosphere)


func _add_clouds() -> void:
	if preset.cloud_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = planet_seed * 31 + 5
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 20
	puff.rings = 10
	var transforms: Array[Transform3D] = []
	var altitude := radius * (1.0 + preset.mountain_height) + 60.0
	for _c in int(preset.cloud_count * pow(radius / 1000.0, 2.0)):
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := d.cross(t1)
		var spin := rng.randf() * TAU
		var along := t1.rotated(d, spin)
		var across := t2.rotated(d, spin)
		var length := rng.randf_range(60.0, 200.0)
		var puffs := int(length / 9.0) + rng.randi_range(3, 6)
		for _p in puffs:
			var x := rng.randf_range(-1.0, 1.0)
			var y := rng.randf_range(-0.35, 0.35) * (1.0 - absf(x))
			var s := rng.randf_range(14.0, 30.0) * (1.0 - absf(x) * 0.55)
			var p := (d * altitude + along * x * length + across * y * length).normalized()
			var b := PlanetScatter.basis_with_up(p)
			b = b.scaled(Vector3(s * 1.2, s * 0.6, s))
			transforms.append(Transform3D(b, p * (altitude + s * 0.2)))
	if low_clouds:
		# Smaller, lower clouds that cling to mountains, like in the reference.
		var placed := 0
		for _try in 20000:
			if placed >= int(preset.cloud_count * pow(radius / 1000.0, 2.0)) / 2:
				break
			var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
			var ground := shape.height(d)
			if ground < radius * preset.mountain_height * 0.35:
				continue
			placed += 1
			var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			var along := t1.rotated(d, rng.randf() * TAU)
			var across := d.cross(along)
			var length := rng.randf_range(30.0, 90.0)
			var alt := radius + ground + rng.randf_range(-15.0, 25.0)
			for _p in int(length / 7.0) + rng.randi_range(2, 4):
				var x := rng.randf_range(-1.0, 1.0)
				var y := rng.randf_range(-0.3, 0.3) * (1.0 - absf(x))
				var s := rng.randf_range(7.0, 16.0) * (1.0 - absf(x) * 0.5)
				var p := (d * alt + along * x * length + across * y * length).normalized()
				var b := PlanetScatter.basis_with_up(p).scaled(Vector3(s * 1.5, s * 0.5, s * 1.1))
				transforms.append(Transform3D(b, p * (alt + s * 0.1)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = puff
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var m := ShaderMaterial.new()
	m.shader = preload("shaders/clouds.gdshader")
	m.set_shader_parameter("top_color", preset.cloud)
	m.set_shader_parameter("bottom_color", preset.cloud_shadow)
	_clouds = MultiMeshInstance3D.new()
	_clouds.name = "Clouds"
	_clouds.multimesh = mm
	_clouds.material_override = m
	add_child(_clouds)


func _add_gravity() -> void:
	var area := Area3D.new()
	area.name = "Gravity"
	area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	area.gravity_point = true
	area.gravity_point_center = Vector3.ZERO
	# Full strength at the surface, weaker further out, like real gravity.
	area.gravity_point_unit_distance = radius
	area.gravity = surface_gravity
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius * 4.0
	col.shape = sphere
	area.add_child(col)
	add_child(area)


## Big rock formations on the mountain slopes. Each one is built from a
## random pile of five different rock shapes (slab, block, pillar, round,
## wedge), each piece with its own size, turn and tilt, so no two formations
## are alike. They are placed over the whole planet at the start (not just
## near the player), so you can see them from far away, and you can climb them.
const CLIFF_ROCKS := ["CliffSlab", "CliffBlock", "CliffPillar", "CliffRound", "CliffWedge"]


func _add_rock_formations() -> void:
	var kinds: Array[String] = []
	for k in CLIFF_ROCKS:
		if _scatter.variants.has(k):
			kinds.append(k)
	if kinds.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = planet_seed * 7703 + 11
	var buckets := {}   # area of the planet -> rock kind -> Array[Transform3D]
	var body := StaticBody3D.new()
	body.name = "RockFormationCollision"
	body.add_to_group("planet_ground")   # climbable, like cliffs
	var tries := int(rock_formations * pow(radius / 1000.0, 2.0))
	for _i in tries:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var sm := shape.sample(d)
		var h := sm.x
		if h < 6.0 or sm.z > 0.2 or shape.in_landing_site(d) or shape.ice(d) > 0.3:
			continue
		# which way the ground faces here
		var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := d.cross(t1)
		var e := 6.0 / radius
		var d1 := (d + t1 * e).normalized()
		var d2 := (d + t2 * e).normalized()
		var p0 := d * (radius + h)
		var n := (d1 * (radius + shape.height(d1)) - p0).cross(d2 * (radius + shape.height(d2)) - p0).normalized()
		if n.dot(d) < 0.0:
			n = -n
		var slope := n.dot(d)
		var mountain := sm.y
		# on mountain sides (not on the ridge tops), a few on steep hills elsewhere
		var want := mountain > 0.2 and slope > 0.35 and slope < 0.85
		want = want or (slope > 0.4 and slope < 0.75 and rng.randf() < 0.2)
		if not want:
			continue

		var size := rng.randf_range(0.8, 2.4) * lerpf(0.8, 1.3, mountain)
		var up := (d * 0.45 + n * 0.55).normalized()
		var frame := PlanetScatter.basis_with_up(up).rotated(up, rng.randf() * TAU)
		var key := Vector3i(((d + Vector3.ONE) * 2.0).floor())
		if not buckets.has(key):
			buckets[key] = {}
		# a random pile: big pieces at the bottom, smaller ones stacked on top
		var pieces := rng.randi_range(2, 7)
		var spread := 5.0 * size
		var top := 0.0
		for k in pieces:
			var kind: String = kinds[rng.randi() % kinds.size()]
			var layer := float(k) / pieces
			var s := size * rng.randf_range(0.55, 1.15) * (1.0 - layer * 0.45)
			var local := Vector3(rng.randf_range(-1.0, 1.0) * spread * (1.0 - layer * 0.6),
					0.0, rng.randf_range(-1.0, 1.0) * spread * (1.0 - layer * 0.6))
			# pieces after the first few climb on top of the pile
			local.y = -2.5 * s if k == 0 else (top * rng.randf_range(0.35, 0.8) - s * 1.2)
			var axis := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)).normalized()
			var piece_basis := frame * Basis(Vector3.UP, rng.randf() * TAU)
			if axis.length() > 0.1:
				piece_basis = piece_basis * Basis(axis, rng.randf_range(-0.35, 0.35))
			piece_basis = piece_basis * Basis.from_scale(Vector3(
					s * rng.randf_range(0.75, 1.3), s * rng.randf_range(0.7, 1.25), s * rng.randf_range(0.75, 1.3)))
			var origin := p0 + frame * local
			if not buckets[key].has(kind):
				buckets[key][kind] = []
			buckets[key][kind].append(Transform3D(piece_basis, origin))
			top = maxf(top, local.y + 7.0 * s)
		# a box roughly the size of the pile, to stand on and climb
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(spread * 1.6, maxf(top, 4.0 * size), spread * 1.6)
		col.shape = box
		col.transform = Transform3D(frame, p0 + up * (top * 0.5 - 2.0 * size))
		body.add_child(col)
	var mat := ShaderMaterial.new()
	mat.shader = preload("shaders/props.gdshader")
	var holder := Node3D.new()
	holder.name = "RockFormations"
	add_child(holder)
	for key in buckets:
		for kind in buckets[key]:
			var list: Array = buckets[key][kind]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _scatter.variants[kind][0]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.visibility_range_end = 2400.0
			holder.add_child(mmi)
	add_child(body)


func _add_landing_sites(sites: Array) -> void:
	var holder := Node3D.new()
	holder.name = "LandingSites"
	add_child(holder)
	for i in sites.size():
		var d: Vector3 = sites[i][0]
		var marker := Marker3D.new()
		marker.name = "LandingSite_%d" % (i + 1)
		marker.transform = Transform3D(PlanetScatter.basis_with_up(d), d * (radius + shape.height(d)))
		marker.gizmo_extents = 10.0
		holder.add_child(marker)
		landing_sites.append(marker)


# ---------------------------------------------------------------------------
# Sky: blue with haze near the ground, black with stars in space
# ---------------------------------------------------------------------------
func _setup_sky() -> void:
	var world := _find_world_environment(get_tree().current_scene if get_tree().current_scene else get_parent())
	if world == null:
		world = WorldEnvironment.new()
		world.name = "PlanetSky"
		add_child(world)
	if world.environment == null:
		world.environment = Environment.new()
	_environment = world.environment
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = preload("shaders/sky.gdshader")
	_sky_material.set_shader_parameter("sky_top", lighting.sky_top)
	_sky_material.set_shader_parameter("horizon_sun", lighting.horizon_sun)
	_sky_material.set_shader_parameter("horizon_away", lighting.horizon_away)
	_sky_material.set_shader_parameter("sun_glow", lighting.sun_glow)
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	# Shade is lit by a saturated blue/lavender: painterly blue shadows.
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = lighting.shadow_color
	_environment.ambient_light_energy = lighting.shadow_energy
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_exposure = lighting.exposure
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = lighting.saturation
	_environment.adjustment_contrast = lighting.contrast
	# Haze: far land fades into a warm coloured mist, brighter towards the sun.
	_environment.fog_enabled = lighting.haze_distance > 0.0
	_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_environment.fog_light_color = lighting.haze_color
	_environment.fog_light_energy = 1.0
	_environment.fog_sun_scatter = 0.3
	_environment.fog_sky_affect = 0.0
	_environment.fog_aerial_perspective = 0.5
	# A soft glow around bright things (sun, snow, water, clouds).
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.5
	_environment.glow_strength = 1.0
	_environment.glow_bloom = 0.08
	_environment.glow_hdr_threshold = 0.9
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_environment.ssr_enabled = true   # water and wet rock reflect (Forward+ only)


func _setup_sun() -> void:
	if sun == null:
		sun = _find_sun(get_tree().current_scene if get_tree().current_scene else get_parent())
	if sun == null:
		return
	sun.light_color = lighting.sun_color
	sun.light_energy = lighting.sun_energy
	sun.shadow_enabled = true
	if aim_sun_at_start and not landing_sites.is_empty():
		aim_sun(landing_sites[0].global_position, lighting.sun_elevation, lighting.sun_azimuth)


## Turns the sun so it is `elevation` degrees above the horizon at a place,
## coming from `azimuth` degrees round the horizon.
func aim_sun(world_position: Vector3, elevation: float, azimuth: float) -> void:
	if sun == null:
		return
	var up := up_at(world_position)
	var north := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var flat := north.rotated(up, deg_to_rad(azimuth))
	var to_sun := (up * sin(deg_to_rad(elevation)) + flat * cos(deg_to_rad(elevation))).normalized()
	var helper := Vector3.UP if absf(to_sun.y) < 0.95 else Vector3.RIGHT
	sun.global_basis = Basis.looking_at(-to_sun, helper)


## Same as aim_sun, but the sun comes from a given direction along the ground.
func aim_sun_from(world_position: Vector3, elevation: float, from_direction: Vector3) -> void:
	if sun == null:
		return
	var up := up_at(world_position)
	var flat := (from_direction - up * from_direction.dot(up)).normalized()
	var to_sun := (up * sin(deg_to_rad(elevation)) + flat * cos(deg_to_rad(elevation))).normalized()
	var helper := Vector3.UP if absf(to_sun.y) < 0.95 else Vector3.RIGHT
	sun.global_basis = Basis.looking_at(-to_sun, helper)


func _find_sun(node: Node) -> DirectionalLight3D:
	if node == null:
		return null
	if node is DirectionalLight3D:
		return node
	for c in node.get_children():
		var found := _find_sun(c)
		if found:
			return found
	return null


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


func _process(delta: float) -> void:
	if _scatter:
		_scatter.set_planet_origin(global_position)
	if _clouds:
		_clouds.rotate(Vector3.UP, delta * 0.002)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var local := to_local(cam.global_position)
	var altitude := local.length() - radius
	var space := smoothstep(radius * 0.25, radius * 0.9, altitude)
	(_atmosphere.material_override as ShaderMaterial).set_shader_parameter("fade", smoothstep(radius * 0.1, radius * 0.6, altitude))
	if _sky_material and altitude < radius * 3.0:
		_sky_material.set_shader_parameter("planet_up", (global_basis * local.normalized()).normalized())
		_sky_material.set_shader_parameter("space_amount", space)
		# Under water: thick blue-green fog so it feels like being in water.
		if altitude < -0.05:
			_environment.fog_light_color = preset.deep_water.lerp(preset.water, 0.4)
			_environment.fog_density = 0.09
		else:
			_environment.fog_light_color = lighting.haze_color
			# Thick near the ground, thinning out as you fly higher.
			var base := 0.6931 / lighting.haze_distance if lighting.haze_distance > 0.0 else 0.0
			_environment.fog_density = base * exp(-maxf(altitude, 0.0) / (radius * 0.35)) * (1.0 - space)
		_environment.fog_enabled = _environment.fog_density > 0.0
