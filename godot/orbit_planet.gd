class_name OrbitPlanet
extends Node3D
## Makes an Orbit Oafs planet playable: gravity that pulls toward the centre,
## trees, and landing sites.
##
## How to use:
##   1. Make a new scene with a Node3D root and attach this script to it.
##   2. Drag the planet .glb (for example earthlike_seed7.glb) in as a child.
##   3. In the Inspector, set Trees File to the matching _trees.json and
##      Tree Models to trees_earthlike.glb.
##
## The ground already has collision: Godot adds it on import because the
## terrain pieces are named "...-col".

## Planet radius in metres. Must match the radius used in Blender.
@export var radius: float = 500.0
## Gravity at ground level, in m/s². Earth is 9.8.
@export var surface_gravity: float = 9.8
## How far gravity reaches, in planet radii from the centre.
@export var gravity_reach: float = 4.0
## The _trees.json file exported next to the planet.
@export_file("*.json") var trees_file: String = ""
## The trees_<type>.glb file with the tree models.
@export var tree_models: PackedScene
## Trees further away than this (metres) are hidden to save performance.
@export var tree_draw_distance: float = 450.0
## Optional: a ship or player that starts at the first landing site.
@export var start_at_landing_site: Node3D

var _landing_sites: Array[Node3D] = []


func _ready() -> void:
	_add_gravity()
	_find_landing_sites(self)
	if trees_file != "" and tree_models != null:
		_spawn_trees()
	if start_at_landing_site != null:
		place_at_landing_site(start_at_landing_site)


## The "up" direction (away from the planet) at a world position.
func up_at(world_position: Vector3) -> Vector3:
	return (world_position - global_position).normalized()


## Flat spots where a ship can land. Each marker's +Y axis points up.
func get_landing_sites() -> Array[Node3D]:
	return _landing_sites


## Moves a ship or player to a landing site, standing upright.
func place_at_landing_site(node: Node3D, index: int = 0, height: float = 2.0) -> void:
	if _landing_sites.is_empty():
		push_warning("OrbitPlanet: no landing sites found")
		return
	var site := _landing_sites[index % _landing_sites.size()]
	var b := site.global_transform.basis.orthonormalized()
	node.global_transform = Transform3D(b, site.global_position + b.y * height)


func _add_gravity() -> void:
	var area := Area3D.new()
	area.name = "Gravity"
	area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	area.gravity_point = true
	area.gravity_point_center = Vector3.ZERO
	# Full strength at the surface, weaker further out (like real gravity).
	area.gravity_point_unit_distance = radius
	area.gravity = surface_gravity
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius * gravity_reach
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)


func _find_landing_sites(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and String(child.name).begins_with("LandingSite"):
			_landing_sites.append(child)
		_find_landing_sites(child)


func _spawn_trees() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(trees_file))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("OrbitPlanet: could not read trees file " + trees_file)
		return

	# Grab the tree meshes out of the tree models scene.
	var models := tree_models.instantiate()
	var meshes: Array[Mesh] = []
	for model_name in data["tree_models"]:
		var found := models.find_child(String(model_name), true, false) as MeshInstance3D
		meshes.append(found.mesh if found != null else null)
	models.free()

	# One MultiMesh per ground piece and tree kind: cheap to draw, and far
	# pieces get hidden by the draw distance.
	var groups := {}
	for t in data["trees"]:
		var key := Vector2i(int(t[0]), int(t[1]))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(t)

	var holder := Node3D.new()
	holder.name = "Trees"
	add_child(holder)
	for key in groups:
		var kind: int = key.y
		if kind >= meshes.size() or meshes[kind] == null:
			continue
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[kind]
		mm.instance_count = list.size()
		for i in list.size():
			var t: Array = list[i]
			var pos := Vector3(t[2], t[3], t[4])
			var up := pos.normalized()
			var b := _basis_with_up(up).rotated(up, float(t[5])).scaled(Vector3.ONE * float(t[6]))
			mm.set_instance_transform(i, Transform3D(b, pos))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = tree_draw_distance
		mmi.visibility_range_end_margin = tree_draw_distance * 0.1
		holder.add_child(mmi)


static func _basis_with_up(up: Vector3) -> Basis:
	var helper := Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP
	var x := helper.cross(up).normalized()
	return Basis(x, up, x.cross(up))
