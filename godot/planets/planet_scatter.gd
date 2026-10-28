class_name PlanetScatter
extends RefCounted
## Places trees, bushes, rocks, grass, flowers, ferns and pebbles near the focus.
## make_data() runs on worker threads, build_node() on the main thread.

var shape: PlanetShape
var preset: PlanetPreset
var planet_seed: int
var draw_distance: float
var meshes := {}   # model name -> Mesh
var _materials := {}  # model name -> Material

# Small things (grass, flowers, ferns, pebbles) are numerous, so they are only
# drawn close by and are split into small cells so only nearby cells draw.
# kind: [per square metre, fade start, fade end]
const SMALL := {
	"Grass": [1.1, 38.0, 52.0],
	"Flowers": [0.05, 45.0, 60.0],
	"Fern": [0.09, 60.0, 80.0],
	"Pebbles": [0.03, 45.0, 60.0],
}
const CELLS := 4            # small things: CELLS x CELLS groups per piece
const LATTICE_M := 2.0      # spacing of the height grid used for small things
const TREES := ["Pine", "PineTall", "PineSnowy", "Fir", "FirSnowy", "Birch", "RoundTree", "Bush"]


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
	var still := ShaderMaterial.new()
	still.shader = preload("shaders/props.gdshader")
	var trees := still.duplicate()
	trees.set_shader_parameter("sway", 0.012)
	for kind in meshes:
		_materials[kind] = trees if kind in TREES else still
	for kind in ["Grass", "Flowers", "Fern"]:
		var m := ShaderMaterial.new()
		m.shader = preload("shaders/foliage.gdshader")
		m.set_shader_parameter("fade_start", SMALL[kind][1])
		m.set_shader_parameter("fade_end", SMALL[kind][2])
		m.set_shader_parameter("sway", 0.05 if kind == "Fern" else 0.12)
		_materials[kind] = m


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
				kind = "RoundTree" if r < 0.35 else ("Birch" if r < 0.55 else "Bush")
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

	_place_small(face, a0, b0, size, width, rng, placed)

	return {"placed": placed, "colliders": colliders, "width": width}


## Grass, flowers, ferns and pebbles. Uses a coarse height grid instead of
## working out the exact height for every tuft, which keeps it fast.
func _place_small(face: int, a0: float, b0: float, size: float, width: float, rng: RandomNumberGenerator, placed: Dictionary) -> void:
	var R := shape.radius
	var n := maxi(4, int(ceil(width / LATTICE_M))) + 1
	var cell := width / (n - 1)
	var hs := PackedFloat32Array()
	var colds := PackedFloat32Array()
	var forests := PackedFloat32Array()
	hs.resize(n * n)
	colds.resize(n * n)
	forests.resize(n * n)
	for i in n:
		for j in n:
			var d := PlanetShape.cube_dir(face, a0 + size * i / (n - 1), b0 + size * j / (n - 1))
			var k := i * n + j
			hs[k] = shape.height(d)
			colds[k] = shape.coldness(d)
			forests[k] = shape.forest(d)
	var snow := preset.snow_line * R
	var area := width * width

	for kind in SMALL:
		if not meshes.has(kind):
			continue
		var cells := {}
		for _t in int(area * SMALL[kind][0]):
			var u := rng.randf()
			var v := rng.randf()
			var gu := u * (n - 1)
			var gv := v * (n - 1)
			var i := mini(int(gu), n - 2)
			var j := mini(int(gv), n - 2)
			var fu := gu - i
			var fv := gv - j
			var k := i * n + j
			var h := lerpf(lerpf(hs[k], hs[k + n], fu), lerpf(hs[k + 1], hs[k + n + 1], fu), fv)
			var cold := colds[k]
			var forest := forests[k]
			var gx := (hs[k + n] - hs[k]) / cell
			var gy := (hs[k + 1] - hs[k]) / cell
			var slope := 1.0 / sqrt(1.0 + gx * gx + gy * gy)
			var ok := false
			match kind:
				"Grass":
					# thinner under trees, where ferns grow instead
					ok = h > 1.2 and h < snow * 0.6 and cold < 0.42 and slope > 0.82 \
							and rng.randf() < 1.0 - forest * 0.6
				"Flowers":
					ok = h > 1.5 and h < snow * 0.4 and cold < 0.25 and forest < 0.3 and slope > 0.88
				"Fern":
					ok = h > 1.5 and h < shape.snow_line_m(cold) * 0.55 and forest > 0.45 and cold < 0.45 and slope > 0.8
				"Pebbles":
					var shore := h > 0.2 and h < 2.5
					ok = cold < 0.6 and (shore or (slope > 0.5 and slope < 0.9)) and h > 0.2 and h < shape.snow_line_m(cold)
			if not ok:
				continue
			var d := PlanetShape.cube_dir(face, a0 + u * size, b0 + v * size)
			var sc := rng.randf_range(0.7, 1.4)
			var b := basis_with_up(d).rotated(d, rng.randf() * TAU).scaled(Vector3.ONE * sc)
			var key := "%s#%d" % [kind, int(u * CELLS) * CELLS + int(v * CELLS)]
			if not cells.has(key):
				cells[key] = []
			cells[key].append(Transform3D(b, d * (R + h)))
		placed.merge(cells)


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
	for key in placed:
		var list: Array = placed[key]
		if list.is_empty():
			continue
		var kind: String = String(key).get_slice("#", 0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _materials[kind]
		if SMALL.has(kind):
			# cells are measured from their middle, so allow for their size
			var cell_half := 0.5 * 1.42 * float(data.get("width", 100.0)) / CELLS
			mmi.visibility_range_end = SMALL[kind][2] + cell_half
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.visibility_range_end = draw_distance
			mmi.visibility_range_end_margin = draw_distance * 0.1
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
