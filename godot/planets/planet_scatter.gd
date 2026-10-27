class_name PlanetScatter
extends RefCounted
## Places trees, bushes, rocks and grass on the ground near the focus.
## make_data() runs on worker threads, build_node() on the main thread.

var shape: PlanetShape
var preset: PlanetPreset
var planet_seed: int
var draw_distance: float
var meshes := {}   # model name -> Mesh
var _solid: StandardMaterial3D
var _two_sided: StandardMaterial3D

# Grass is only drawn close by; it's the most numerous thing.
const GRASS_DISTANCE := 70.0
const GRASS_DENSITY := 0.35   # tufts per square metre on open grass


func _init(p_shape: PlanetShape, p_preset: PlanetPreset, p_seed: int, props: PackedScene, p_draw_distance: float) -> void:
	shape = p_shape
	preset = p_preset
	planet_seed = p_seed
	draw_distance = p_draw_distance
	if props == null:
		return
	var root := props.instantiate()
	_collect_meshes(root)
	root.free()
	# The models keep their colours in the mesh ("vertex colours").
	_solid = StandardMaterial3D.new()
	_solid.vertex_color_use_as_albedo = true
	_solid.roughness = 0.9
	_solid.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_two_sided = _solid.duplicate()
	_two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		meshes[String(node.name)] = node.mesh
	for c in node.get_children():
		_collect_meshes(c)


func has_props() -> bool:
	return not meshes.is_empty()


static func basis_with_up(up: Vector3) -> Basis:
	var helper := Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP
	var x := helper.cross(up).normalized()
	return Basis(x, up, x.cross(up))


## Works out what grows on one piece of ground. Worker thread.
func make_data(face: int, a0: float, b0: float, size: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([planet_seed, face, a0, b0])
	var R := shape.radius
	var width := size * R * PI * 0.25
	var area := width * width
	var snow := preset.snow_line * R
	var placed := {}      # model name -> Array[Transform3D]
	var colliders := []   # [Transform3D, radius, height] (height 0 = ball)

	var tree_max := maxf(preset.forest_density, preset.open_tree_density)
	var tries := int(area * (tree_max + preset.rock_density))
	for _i in tries:
		var d := PlanetShape.cube_dir(face, a0 + rng.randf() * size, b0 + rng.randf() * size)
		var h := shape.height(d)
		if h < 1.2 or shape.in_landing_site(d):
			continue
		var cold := shape.coldness(d)
		var frozen_sea := shape.ice(d) > 0.3
		var slope := _slope(d, h)
		var snow_here := shape.snow_line_m(cold)
		var kind := ""
		var s := 1.0
		if rng.randf() < preset.rock_density / (preset.rock_density + tree_max):
			# Rocks and boulders
			if slope < 0.55:
				continue
			var r := rng.randf()
			if cold > 0.45 or h > snow_here:
				kind = "Boulder" if r < 0.12 else "RockSnowy"
			else:
				kind = "Boulder" if r < 0.15 else ("RockFlat" if r < 0.5 else "Rock")
			s = rng.randf_range(0.6, 1.5)
		else:
			# Trees, bushes, logs and flowers, depending on the biome
			if frozen_sea or slope < 0.86 or h > snow_here * 0.95:
				continue
			var f := shape.forest(d)
			var density := lerpf(preset.open_tree_density, preset.forest_density, f)
			if cold > 0.5:
				density *= 0.35   # snowfields: scattered trees
			if rng.randf() * tree_max > density:
				continue
			var r := rng.randf()
			if cold > 0.5 or h > snow_here * 0.6:
				kind = "FirSnowy" if r < 0.55 else "PineSnowy"
			elif cold > 0.2:
				# taiga: dark firs and pines, a little snow
				kind = "Fir" if r < 0.5 else ("PineSnowy" if r < 0.65 else ("Pine" if r < 0.92 else "Log"))
			elif f > 0.35:
				# forest: mixed pines and birches, fallen logs
				kind = "PineTall" if r < 0.3 else ("Pine" if r < 0.6 else ("Birch" if r < 0.85 else ("Log" if r < 0.93 else "Bush")))
			else:
				# meadow: round trees, birches, bushes and flowers
				kind = "RoundTree" if r < 0.3 else ("Birch" if r < 0.45 else ("Bush" if r < 0.7 else "Flowers"))
			s = rng.randf_range(0.75, 1.3)
		if not meshes.has(kind):
			continue
		var up := d
		var b := basis_with_up(up).rotated(up, rng.randf() * TAU).scaled(Vector3.ONE * s)
		var t := Transform3D(b, d * (R + h) - d * 0.15)
		if not placed.has(kind):
			placed[kind] = []
		placed[kind].append(t)
		if kind.begins_with("Pine") or kind.begins_with("Fir") or kind == "RoundTree" or kind == "Birch":
			colliders.append([t.origin + up * 2.0 * s, 0.35 * s, 4.0 * s])
		elif kind == "Boulder" or ((kind == "Rock" or kind == "RockSnowy") and s > 1.0):
			var size_m := (4.5 if kind == "Boulder" else 1.4) * s
			colliders.append([t.origin + up * size_m * 0.2, size_m * 0.42, 0.0])

	# Grass tufts and wild flowers on gentle, low, open, warm ground.
	if meshes.has("Grass"):
		var grass := []
		var flowers := []
		var tufts := int(area * GRASS_DENSITY)
		for _i in tufts:
			var d := PlanetShape.cube_dir(face, a0 + rng.randf() * size, b0 + rng.randf() * size)
			var h := shape.height(d)
			if h < 1.5 or h > snow * 0.6 or shape.in_landing_site(d):
				continue
			if shape.coldness(d) > 0.42 or _slope(d, h) < 0.88:
				continue
			var b := basis_with_up(d).rotated(d, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
			if meshes.has("Flowers") and rng.randf() < 0.04 and shape.forest(d) < 0.3:
				flowers.append(Transform3D(b, d * (R + h)))
			else:
				grass.append(Transform3D(b, d * (R + h)))
		placed["Grass"] = grass
		if not flowers.is_empty():
			if not placed.has("Flowers"):
				placed["Flowers"] = []
			placed["Flowers"].append_array(flowers)

	return {"placed": placed, "colliders": colliders}


func _slope(d: Vector3, h: float) -> float:
	var R := shape.radius
	var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := d.cross(t1)
	var e := 1.5
	var p0 := d * (R + h)
	var d1 := (d + t1 * (e / R)).normalized()
	var d2 := (d + t2 * (e / R)).normalized()
	var p1 := d1 * (R + shape.height(d1))
	var p2 := d2 * (R + shape.height(d2))
	return absf((p1 - p0).cross(p2 - p0).normalized().dot(d))


## Turns the data into MultiMeshes and colliders. Main thread.
func build_node(data: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Props"
	var placed: Dictionary = data["placed"]
	for kind in placed:
		var list: Array = placed[kind]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var small: bool = kind == "Grass" or kind == "Flowers"
		mmi.material_override = _two_sided if small else _solid
		var dist := GRASS_DISTANCE if small else draw_distance
		mmi.visibility_range_end = dist
		mmi.visibility_range_end_margin = dist * 0.1
		if small:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)

	var colliders: Array = data["colliders"]
	if not colliders.is_empty():
		var body := StaticBody3D.new()
		for c in colliders:
			var col := CollisionShape3D.new()
			var origin: Vector3 = c[0]
			if c[2] > 0.0:
				var cyl := CylinderShape3D.new()
				cyl.radius = c[1]
				cyl.height = c[2]
				col.shape = cyl
				col.transform = Transform3D(basis_with_up(origin.normalized()), origin)
			else:
				var ball := SphereShape3D.new()
				ball.radius = c[1]
				col.shape = ball
				col.position = origin
			body.add_child(col)
		holder.add_child(body)
	return holder
