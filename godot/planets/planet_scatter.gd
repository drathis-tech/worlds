class_name PlanetScatter
extends RefCounted
## Places trees, bushes, rocks, logs, grass, flowers, ferns, reeds, mushrooms
## and pebbles near the focus. make_data() runs on worker threads,
## build_node() on the main thread.
##
## To stop things looking copy-pasted, every prop:
##   - picks one of several model versions ("Pine", "Pine_2", "Pine_3", ...)
##   - gets its own height, width and turn, rocks also a tilt
##   - gets its own colour tint (lighter, darker, warmer, cooler), picked in
##     the shader from where it stands

var shape: PlanetShape
var preset: PlanetPreset
var planet_seed: int
var draw_distance: float
var variants := {}    # base model name -> Array[Mesh]
var _materials := {}  # base model name -> Material

# Small things are numerous, so they are only drawn close by and are split
# into cells so only nearby cells draw.
# kind: [per square metre, fade start, fade end]
const SMALL := {
	"Grass": [0.7, 38.0, 52.0],
	"GrassShort": [0.6, 30.0, 42.0],
	"GrassClump": [0.22, 45.0, 60.0],
	"LeafyBush": [0.05, 55.0, 75.0],
	"WhiteFlowers": [0.07, 35.0, 50.0],
	"TallGrass": [0.07, 45.0, 62.0],
	"Flowers": [0.05, 45.0, 60.0],
	"Fern": [0.09, 60.0, 80.0],
	"Reeds": [0.25, 55.0, 75.0],
	"Mushrooms": [0.025, 25.0, 35.0],
	"Pebbles": [0.03, 45.0, 60.0],
	"Clover": [0.1, 30.0, 42.0],
	"Heather": [0.08, 45.0, 60.0],
	"BerryBush": [0.012, 60.0, 80.0],
	"Lupines": [0.035, 50.0, 65.0],
	"Dandelions": [0.05, 30.0, 42.0],
	"Moss": [0.07, 35.0, 48.0],
}
const SWAYING := ["Grass", "GrassShort", "GrassClump", "TallGrass", "Flowers", "WhiteFlowers", "Fern", "Reeds", "LeafyBush",
		"Clover", "Heather", "BerryBush", "Lupines", "Dandelions", "Moss"]
# how much each kind moves in the wind (the default is 0.12)
const SWAY := {"Fern": 0.05, "LeafyBush": 0.05, "TallGrass": 0.06, "GrassClump": 0.06, "Clover": 0.04,
		"Heather": 0.03, "BerryBush": 0.02, "Lupines": 0.08, "Moss": 0.0}
const ROCKS := ["Rock", "RockFlat", "Boulder", "RockSnowy", "Pebbles", "CliffSlab", "CliffBlock", "CliffPillar", "CliffRound", "CliffWedge"]
const CELLS := 3            # small things: CELLS x CELLS groups per piece
const LATTICE_M := 2.0      # spacing of the height grid used for small things
const TREES := ["Pine", "PineTall", "PineSnowy", "Fir", "FirSnowy", "Birch", "RoundTree", "Bush", "DeadTree",
		"Larch", "AutumnTree", "AutumnBush", "BirchSnowy", "BushSnowy", "DeadTreeSnowy"]


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
	var rocks := still.duplicate()
	rocks.set_shader_parameter("rocky", true)
	for kind in variants:
		_materials[kind] = trees if kind in TREES else (rocks if kind in ROCKS else still)
	for kind in SWAYING:
		var m := ShaderMaterial.new()
		m.shader = preload("shaders/foliage.gdshader")
		m.set_shader_parameter("fade_start", SMALL[kind][1])
		m.set_shader_parameter("fade_end", SMALL[kind][2])
		m.set_shader_parameter("sway", SWAY.get(kind, 0.12))
		m.set_shader_parameter("dry_color", preset.grass_dry)
		m.set_shader_parameter("golden", kind in ["Grass", "GrassShort", "GrassClump", "TallGrass"])
		_materials[kind] = m


## Grass and plants take on the ground's golden patches; they need to know
## where the planet is to line the patches up.
func set_planet_origin(origin: Vector3) -> void:
	for kind in SWAYING:
		if _materials.has(kind):
			(_materials[kind] as ShaderMaterial).set_shader_parameter("planet_origin", origin)


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var name := String(node.name)
		# "Pine_2" is a second version of "Pine"
		var base := name
		var cut := name.rfind("_")
		if cut > 0 and name.substr(cut + 1).is_valid_int():
			base = name.substr(0, cut)
		if not variants.has(base):
			variants[base] = []
		variants[base].append(node.mesh)
	for c in node.get_children():
		_collect_meshes(c)


func has_props() -> bool:
	return not variants.is_empty()


static func basis_with_up(up: Vector3) -> Basis:
	var helper := Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP
	var x := helper.cross(up).normalized()
	return Basis(x, up, x.cross(up))


## Adds one prop, as a random one of the model's versions. Small plants
## use two versions per cell (cells next to each other pick different ones),
## which keeps the number of things to draw down.
func _add(placed: Dictionary, kind: String, t: Transform3D, rng: RandomNumberGenerator, cell := -1) -> void:
	var n: int = variants[kind].size()
	var version := rng.randi() % n
	if cell >= 0:
		var first := absi(hash([kind, cell, t.origin.snapped(Vector3.ONE * 200.0)])) % n
		version = (first + rng.randi() % 2) % n
	var key := "%s|%d" % [kind, version]
	if cell >= 0:
		key += "#%d" % cell
	if not placed.has(key):
		placed[key] = []
	placed[key].append(t)


## Works out what grows on one piece of ground. Worker thread.
func make_data(face: int, a0: float, b0: float, size: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([planet_seed, face, a0, b0])
	var R := shape.radius
	var width := size * R * PI * 0.25
	var area := width * width
	var placed := {}      # "kind|version" -> Array[Transform3D]
	var colliders := []   # [origin, radius, height] (height 0 = ball)

	var tree_max := maxf(preset.forest_density, preset.open_tree_density)
	var tries := int(area * (tree_max + preset.rock_density))
	for _i in tries:
		var d := PlanetShape.cube_dir(face, a0 + rng.randf() * size, b0 + rng.randf() * size)
		var sm := shape.sample(d)
		var h := sm.x
		if h < 1.2 or sm.z > 0.25 or shape.in_landing_site(d):
			continue   # no trees or rocks in water, on trails or landing sites
		var cold := shape.coldness(d)
		var frozen_sea := shape.ice(d) > 0.3
		var slope := _slope(d, h)
		var snow_here := shape.snow_line_m(cold)
		var kind := ""
		var s := 1.0
		var is_rock := rng.randf() < preset.rock_density / (preset.rock_density + tree_max)
		if is_rock:
			if slope < 0.55:
				continue
			var r := rng.randf()
			if cold > 0.45 or h > snow_here:
				kind = "Boulder" if r < 0.12 else "RockSnowy"
			else:
				kind = "Boulder" if r < 0.15 else ("RockFlat" if r < 0.5 else "Rock")
			s = rng.randf_range(0.5, 1.6)
		else:
			if frozen_sea or slope < 0.86 or h > snow_here * 0.95:
				continue
			var f := shape.forest(d)
			var density := lerpf(preset.open_tree_density, preset.forest_density, f)
			if cold > 0.5:
				density *= 0.35   # snowfields: scattered trees
			if rng.randf() * tree_max > density:
				continue
			var r := rng.randf()
			var fall := shape.autumn(d)
			if cold <= 0.5 and h <= snow_here * 0.6 and rng.randf() < fall * 0.4:
				# autumn: golden larches among the pines, red trees and bushes in the open
				if f > 0.35:
					kind = "Larch" if r < 0.6 else ("AutumnTree" if r < 0.75 else ("Fir" if r < 0.92 else "AutumnBush"))
				else:
					kind = "AutumnTree" if r < 0.35 else ("AutumnBush" if r < 0.8 else "Larch")
			elif cold > 0.5 or h > snow_here * 0.6:
				# snowfields: snowy firs, pines and birches, snowy bushes, bare dead trees
				kind = "FirSnowy" if r < 0.36 else ("PineSnowy" if r < 0.62 else ("BirchSnowy" if r < 0.78 \
						else ("BushSnowy" if r < 0.92 else ("DeadTreeSnowy" if r < 0.98 else "DeadTree"))))
			elif cold > 0.2:
				# taiga: dark firs and pines, some snow on the colder side, the odd dead tree
				var snowy := rng.randf() < (cold - 0.2) * 2.5
				if snowy:
					kind = "FirSnowy" if r < 0.4 else ("PineSnowy" if r < 0.65 else ("BirchSnowy" if r < 0.82 else ("BushSnowy" if r < 0.95 else "DeadTreeSnowy")))
				else:
					kind = "Fir" if r < 0.45 else ("PineSnowy" if r < 0.55 else ("Pine" if r < 0.8 else ("Birch" if r < 0.86 \
							else ("DeadTree" if r < 0.9 else ("Log" if r < 0.96 else "Stump")))))
			elif f > 0.35:
				# forest: mixed pines and birches, fallen logs and stumps
				kind = "PineTall" if r < 0.28 else ("Pine" if r < 0.55 else ("Birch" if r < 0.8 else ("Log" if r < 0.87 else ("Stump" if r < 0.93 else "Bush"))))
			else:
				# meadow: round trees, birches and bushes
				kind = "RoundTree" if r < 0.35 else ("Birch" if r < 0.55 else ("Bush" if r < 0.95 else "Stump"))
			if kind == "Bush" and rng.randf() < 0.3 and variants.has("BerryBush"):
				kind = "BerryBush"
			s = rng.randf_range(0.75, 1.3)
		if not variants.has(kind):
			continue
		var up := d
		var b := basis_with_up(up).rotated(up, rng.randf() * TAU)
		var sink := 0.15
		if is_rock:
			# rocks lie at any angle, partly buried
			var axis := b.x.rotated(up, rng.randf() * TAU)
			b = b.rotated(axis, rng.randf_range(-0.45, 0.45))
			b = b * Basis.from_scale(Vector3(s * rng.randf_range(0.8, 1.25), s * rng.randf_range(0.7, 1.2), s * rng.randf_range(0.8, 1.25)))
			sink = s * 0.25
		else:
			# trees: their own height and width, a slight lean
			b = b.rotated(b.x.rotated(up, rng.randf() * TAU), rng.randf_range(0.0, 0.06))
			var wide := s * rng.randf_range(0.85, 1.15)
			b = b * Basis.from_scale(Vector3(wide, s * rng.randf_range(0.85, 1.25), wide))
		var t := Transform3D(b, d * (R + h) - d * sink)
		_add(placed, kind, t, rng)
		if kind in TREES and not kind.contains("Bush"):
			colliders.append([t.origin + up * 2.0 * s, 0.35 * s, 4.0 * s])
		elif kind == "Boulder" or ((kind == "Rock" or kind == "RockSnowy") and s > 1.0):
			var size_m := (4.5 if kind == "Boulder" else 1.4) * s
			colliders.append([t.origin + up * size_m * 0.2, size_m * 0.42, 0.0])

	_place_small(face, a0, b0, size, width, rng, placed)
	_place_river_rocks(face, a0, b0, size, width, rng, placed, colliders)

	return {"placed": placed, "colliders": colliders, "width": width}


## Grass, tall grass, flowers, ferns, reeds, mushrooms and pebbles. Uses a
## coarse height grid instead of working out the exact height for every tuft,
## which keeps it fast.
func _place_small(face: int, a0: float, b0: float, size: float, width: float, rng: RandomNumberGenerator, placed: Dictionary) -> void:
	var R := shape.radius
	var n := maxi(4, int(ceil(width / LATTICE_M))) + 1
	var cell := width / (n - 1)
	var hs := PackedFloat32Array()
	var colds := PackedFloat32Array()
	var forests := PackedFloat32Array()
	var trails := PackedFloat32Array()
	hs.resize(n * n)
	colds.resize(n * n)
	forests.resize(n * n)
	trails.resize(n * n)
	for i in n:
		for j in n:
			var d := PlanetShape.cube_dir(face, a0 + size * i / (n - 1), b0 + size * j / (n - 1))
			var k := i * n + j
			var sm := shape.sample(d)
			hs[k] = sm.x
			trails[k] = sm.z
			colds[k] = shape.coldness(d)
			forests[k] = shape.forest(d)
	var snow := preset.snow_line * R
	var area := width * width

	for kind in SMALL:
		if not variants.has(kind):
			continue
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
			var trail := trails[k]
			var gx := (hs[k + n] - hs[k]) / cell
			var gy := (hs[k + 1] - hs[k]) / cell
			var slope := 1.0 / sqrt(1.0 + gx * gx + gy * gy)
			var ok := false
			match kind:
				"Grass":
					# thinner under trees (ferns grow there) and on trails
					ok = h > 1.2 and h < snow * 0.6 and cold < 0.42 and slope > 0.82 \
							and rng.randf() < (1.0 - forest * 0.6) * (1.0 - trail * 0.9)
				"GrassShort":
					ok = h > 1.2 and h < snow * 0.65 and cold < 0.42 and slope > 0.8 and trail < 0.5 \
							and rng.randf() < 1.0 - forest * 0.7
				"GrassClump":
					# lush clumps, thickest around forest edges and along trails
					ok = h > 1.2 and h < snow * 0.55 and cold < 0.4 and slope > 0.8 and trail < 0.3 \
							and rng.randf() < 0.35 + 0.65 * (1.0 - absf(forest - 0.35) * 2.0)
				"LeafyBush":
					ok = h > 1.5 and h < snow * 0.5 and cold < 0.35 and slope > 0.8 and trail < 0.2 and forest > 0.15
				"WhiteFlowers":
					ok = h > 1.5 and h < snow * 0.45 and cold < 0.3 and slope > 0.85 and trail < 0.2 and forest < 0.5
				"TallGrass":
					# at the edges of forests and along trails
					ok = h > 1.5 and h < snow * 0.5 and cold < 0.35 and slope > 0.85 \
							and ((forest > 0.12 and forest < 0.45) or (trail > 0.05 and trail < 0.3))
				"Flowers":
					ok = h > 1.5 and h < snow * 0.4 and cold < 0.25 and forest < 0.3 and slope > 0.88 and trail < 0.2
				"Fern":
					ok = h > 1.5 and h < shape.snow_line_m(cold) * 0.55 and forest > 0.45 and cold < 0.45 \
							and slope > 0.8 and trail < 0.3
				"Reeds":
					# right at the water's edge, some standing in the shallows
					ok = h > -0.5 and h < 0.75 and cold < 0.4 and slope > 0.75 and rng.randf() < 0.7
				"Mushrooms":
					ok = h > 1.5 and forest > 0.5 and cold < 0.45 and slope > 0.8 and trail < 0.2
				"Clover":
					# low carpets in meadows, thinning under trees
					ok = h > 1.2 and h < snow * 0.5 and cold < 0.38 and slope > 0.85 and trail < 0.3 \
							and forest < 0.6 and vnoise_patch(u, v, face, 1) > 0.45
				"Dandelions":
					ok = h > 1.2 and h < snow * 0.45 and cold < 0.3 and slope > 0.86 and trail < 0.4 \
							and forest < 0.35 and vnoise_patch(u, v, face, 2) > 0.5
				"Lupines":
					# drifts of purple, pink and blue spikes on open hillsides
					ok = h > 2.0 and h < snow * 0.55 and cold < 0.4 and slope > 0.8 and trail < 0.2 \
							and forest < 0.3 and vnoise_patch(u, v, face, 3) > 0.62
				"Heather":
					# hillsides and cooler highlands
					ok = h > 4.0 and h < snow * 0.9 and cold < 0.62 and slope > 0.6 and trail < 0.3 and forest < 0.4 \
							and (h > snow * 0.35 or cold > 0.25 or vnoise_patch(u, v, face, 4) > 0.65)
				"BerryBush":
					ok = h > 1.5 and h < snow * 0.5 and cold < 0.4 and slope > 0.82 and trail < 0.2 \
							and forest > 0.1 and forest < 0.6
				"Moss":
					# forest floors, damp shores and cold taiga
					ok = h > 0.6 and h < snow * 0.8 and cold < 0.55 and slope > 0.65 and trail < 0.2 \
							and (forest > 0.4 or h < 3.0 or (cold > 0.25 and cold < 0.55))
				"Pebbles":
					var shore := h > 0.2 and h < 2.5
					ok = cold < 0.6 and h > 0.2 and h < shape.snow_line_m(cold) \
							and (shore or trail > 0.4 or (slope > 0.5 and slope < 0.9))
			if not ok:
				continue
			var d := PlanetShape.cube_dir(face, a0 + u * size, b0 + v * size)
			var sc := rng.randf_range(0.7, 1.4)
			var b := basis_with_up(d).rotated(d, rng.randf() * TAU)
			b = b * Basis.from_scale(Vector3(sc, sc * rng.randf_range(0.7, 1.5), sc))
			_add(placed, kind, Transform3D(b, d * (R + h)), rng, int(u * CELLS) * CELLS + int(v * CELLS))


## Boulders in the river (thickest in the rapids, poking out of the water so
## you can hop across) and fallen rocks on the stony ledges under the cliffs.
func _place_river_rocks(face: int, a0: float, b0: float, size: float, width: float, rng: RandomNumberGenerator, placed: Dictionary, colliders: Array) -> void:
	if preset.rivers <= 0.0:
		return
	var R := shape.radius
	var g := clampi(int(width / 12.0), 2, 14)   # check the piece in g x g cells
	var cell := size / g
	var cell_m := width / g
	for ci in g:
		for cj in g:
			var dc := PlanetShape.cube_dir(face, a0 + cell * (ci + 0.5), b0 + cell * (cj + 0.5))
			var near := shape.river_near(dc)
			if near.x > preset.gorge_width_m + cell_m:
				continue
			for _k in int(cell_m * cell_m / 18.0):
				var d := PlanetShape.cube_dir(face, a0 + cell * (ci + rng.randf()), b0 + cell * (cj + rng.randf()))
				var rv := shape.river_near(d)
				if rv.y <= 0.1:
					continue
				var x := rv.x
				var kind := ""
				var s := 1.0
				var sink := 0.3
				if x < preset.river_width_m:
					# in the water: mostly in the rapids
					if rng.randf() > 0.15 + rv.z * 0.5:
						continue
					var r := rng.randf()
					kind = "Boulder" if r < 0.35 else ("Rock" if r < 0.7 else "CliffRound")
					s = rng.randf_range(0.55, 0.9) if kind == "Boulder" else rng.randf_range(1.4, 2.6)
					if kind == "CliffRound":
						s = rng.randf_range(0.35, 0.6)
				elif x < preset.gorge_width_m - 2.0:
					# the stony ledge under the cliffs
					if rng.randf() > 0.35:
						continue
					var r := rng.randf()
					kind = "Rock" if r < 0.3 else ("RockFlat" if r < 0.5 else ("Pebbles" if r < 0.7 \
							else ("Boulder" if r < 0.8 else ("CliffRound" if r < 0.9 else "CliffBlock"))))
					s = rng.randf_range(0.3, 0.6) if kind == "Boulder" else rng.randf_range(0.6, 1.6)
					if kind.begins_with("Cliff"):
						s = rng.randf_range(0.25, 0.5)
				else:
					continue
				if not variants.has(kind):
					continue
				var h := shape.height(d)
				var b := basis_with_up(d).rotated(d, rng.randf() * TAU)
				b = b.rotated(b.x.rotated(d, rng.randf() * TAU), rng.randf_range(-0.4, 0.4))
				b = b * Basis.from_scale(Vector3(s * rng.randf_range(0.8, 1.25), s * rng.randf_range(0.7, 1.1), s * rng.randf_range(0.8, 1.25)))
				var t := Transform3D(b, d * (R + h - sink * s))
				_add(placed, kind, t, rng)
				if kind == "Boulder" or (kind != "Pebbles" and s > 1.2):
					var size_m := (4.5 if kind == "Boulder" else 1.4) * s
					colliders.append([t.origin + d * size_m * 0.2, size_m * 0.42, 0.0])


## A cheap patchiness value 0..1 for a spot on a piece of ground, so flowers
## and clover grow in drifts instead of evenly everywhere.
func vnoise_patch(u: float, v: float, face: int, layer: int) -> float:
	var x := u * 3.0 + layer * 17.3 + face * 5.1
	var y := v * 3.0 + layer * 9.7
	return 0.5 + 0.25 * sin(x * 2.1 + sin(y * 1.7)) + 0.25 * sin(y * 2.3 + sin(x * 1.3 + layer))


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
	var cell_half := 0.5 * 1.42 * float(data.get("width", 100.0)) / CELLS
	for key in placed:
		var list: Array = placed[key]
		if list.is_empty():
			continue
		var kind_version: String = String(key).get_slice("#", 0)
		var kind := kind_version.get_slice("|", 0)
		var version := int(kind_version.get_slice("|", 1))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[kind][version]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _materials[kind]
		if SMALL.has(kind):
			# cells are measured from their middle, so allow for their size
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
