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
## Radius in metres. 1000 m = about 20 minutes to walk around at 5 m/s.
@export var radius: float = 1000.0
## Gets the most ground detail. Empty = the active camera.
@export var focus: Node3D
## Gravity at ground level, in m/s². Earth is 9.8.
@export var surface_gravity: float = 9.8
## Optional: a ship or player placed on the first landing site at the start.
@export var start_at_landing_site: Node3D

@export_group("Detail")
## How finely the ground near the focus is built. 6 = about 0.8 m on a 1 km planet.
@export_range(3, 8) var ground_detail: int = 6
## Higher = detailed ground reaches further out (slower).
@export_range(1.5, 4.0) var detail_distance: float = 2.2
## Trees, bushes and rocks.
@export var props: PackedScene = preload("models/props.glb")
## Props further away than this are hidden.
@export var prop_draw_distance: float = 380.0

@export_group("Sky")
## Let this planet control the sky, sun haze and fog while the camera is near it.
@export var control_sky: bool = true
## Fog thickness on the ground. 0 = no fog.
@export var fog_density: float = 0.0005

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
	if control_sky:
		_setup_sky()
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
			"snow", "sand", "shallow_water", "deep_water"]:
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
	m.set_shader_parameter("rim_color", preset.horizon)
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
	for _c in preset.cloud_count:
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
	_sky_material.set_shader_parameter("sky_color", preset.sky)
	_sky_material.set_shader_parameter("horizon_color", preset.horizon)
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_sky_contribution = 0.5
	_environment.ambient_light_color = Color(0.35, 0.4, 0.5)
	_environment.ambient_light_energy = 1.0
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = 1.0
	_environment.adjustment_contrast = 1.04
	_environment.fog_enabled = fog_density > 0.0
	_environment.fog_light_color = preset.horizon
	_environment.fog_sky_affect = 0.0
	_environment.fog_aerial_perspective = 0.0


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
		_environment.fog_density = fog_density * (1.0 - space)
