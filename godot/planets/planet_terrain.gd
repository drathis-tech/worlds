class_name PlanetTerrain
extends Node3D
## The planet's ground. It is built while the game runs, in pieces: lots of
## detail near the player, less far away. Pieces are built on worker threads
## so the game keeps running smoothly.

signal first_load_finished

## Ground points per piece side. 32 is a good balance.
const RES := 32

var shape: PlanetShape
var material: Material
## Material for the flowing river water (drawn as a second surface).
var river_material: Material
## The node that gets the most detail (player, ship or camera).
var focus: Node3D
## How many times a cube side can be split. 6 gives about 0.8 m detail on a 1 km planet.
var max_depth := 6
## Never show less detail than this (keeps the planet round from orbit).
var min_depth := 1
## Split a piece when the focus is closer than this many piece-widths.
var split_distance := 2.2
## Pieces this deep or deeper get collision.
var collision_depth := 5
## Pieces at exactly this depth carry the trees and rocks.
var scatter_depth := 4
## Called on the main thread to turn scatter data into nodes: func(data) -> Node3D.
var scatter_builder: Callable
## Called on a worker thread to make scatter data: func(face, a0, b0, size) -> Variant.
var scatter_maker: Callable

var _roots: Array = []
var _jobs := {}          # node instance id -> task id (being built)
var _done := []          # finished jobs waiting to be turned into meshes
var _done_lock := Mutex.new()
var _max_jobs := 4
var _last_focus := Vector3(INF, INF, INF)
var _loaded_once := false
var _queue_list: Array = []


class QuadNode:
	var face: int
	var a0: float
	var b0: float
	var size: float       # width in cube units (a whole side is 2)
	var depth: int
	var key: String
	var center: Vector3   # centre direction
	var children: Array = []
	var mesh_instance: MeshInstance3D
	var body: StaticBody3D
	var scatter: Node3D
	var ready := false
	var queued := false


func setup(p_shape: PlanetShape, p_material: Material) -> void:
	shape = p_shape
	material = p_material
	_max_jobs = maxi(2, OS.get_processor_count() - 1)
	for f in 6:
		_roots.append(_make_node(f, -1.0, -1.0, 2.0, 0))


func _make_node(face: int, a0: float, b0: float, size: float, depth: int) -> QuadNode:
	var n := QuadNode.new()
	n.face = face
	n.a0 = a0
	n.b0 = b0
	n.size = size
	n.depth = depth
	n.key = "%d_%d_%s_%s" % [face, depth, str(a0), str(b0)]
	n.center = PlanetShape.cube_dir(face, a0 + size * 0.5, b0 + size * 0.5)
	return n


## Width of a piece on the ground, in metres.
func node_width(n: QuadNode) -> float:
	return n.size * shape.radius * PI * 0.25


func _process(_delta: float) -> void:
	if shape == null:
		return
	_apply_finished(4)
	var f := _focus_position()
	# Only rework the tree when the focus has moved a bit (or jobs finished).
	if f.distance_to(_last_focus) > 1.0 or not _jobs.is_empty() or not _queue_list.is_empty() or not _loaded_once:
		_last_focus = f
		var all_drawn := true
		for r in _roots:
			all_drawn = _update(r, f) and all_drawn
		_start_jobs(f)
		if all_drawn and not _loaded_once and _jobs.is_empty():
			_loaded_once = true
			first_load_finished.emit()


func _focus_position() -> Vector3:
	var node := focus
	if node == null:
		node = get_viewport().get_camera_3d()
	if node == null:
		return Vector3(0, 0, shape.radius * 3.0)
	return to_local(node.global_position)


func is_loaded() -> bool:
	return _loaded_once


## True when nothing is waiting to be built.
func is_idle() -> bool:
	_done_lock.lock()
	var none_done := _done.is_empty()
	_done_lock.unlock()
	return _jobs.is_empty() and _queue_list.is_empty() and none_done


func _wants_split(n: QuadNode, f: Vector3) -> bool:
	if n.depth < min_depth:
		return true
	if n.depth >= max_depth:
		return false
	var surface := n.center * shape.radius
	return f.distance_to(surface) < node_width(n) * split_distance


## Returns true when this node's area is fully drawn.
func _update(n: QuadNode, f: Vector3) -> bool:
	if _wants_split(n, f):
		if n.children.is_empty():
			var h := n.size * 0.5
			for i in 2:
				for j in 2:
					n.children.append(_make_node(n.face, n.a0 + h * i, n.b0 + h * j, h, n.depth + 1))
		var all_ok := true
		for c in n.children:
			all_ok = _update(c, f) and all_ok
		# scatter lives on its own depth even when children are drawn
		if n.depth == scatter_depth and not n.ready:
			_queue(n)
		if all_ok:
			_show(n, false)
			return true
		for c in n.children:
			_hide_tree(c)
		if n.ready:
			_show(n, true)
			return true
		_queue(n)
		return false

	if not n.ready:
		_queue(n)
		# keep showing the children until this piece is ready
		return not n.children.is_empty()
	_show(n, true)
	for c in n.children:
		_free_tree(c)
	n.children.clear()
	return true


func _show(n: QuadNode, on: bool) -> void:
	if n.mesh_instance:
		n.mesh_instance.visible = on


func _hide_tree(n: QuadNode) -> void:
	_show(n, false)
	for c in n.children:
		_hide_tree(c)


func _free_tree(n: QuadNode) -> void:
	for c in n.children:
		_free_tree(c)
	n.children.clear()
	if n.mesh_instance:
		n.mesh_instance.queue_free()
	if n.body:
		n.body.queue_free()
	if n.scatter:
		n.scatter.queue_free()
	n.mesh_instance = null
	n.body = null
	n.scatter = null
	n.ready = false
	n.queued = false



func _queue(n: QuadNode) -> void:
	if not n.queued:
		n.queued = true
		_queue_list.append(n)


func _start_jobs(f: Vector3) -> void:
	if _queue_list.is_empty() or _jobs.size() >= _max_jobs:
		return
	# Drop nodes that were freed while waiting, then build the closest first.
	_queue_list = _queue_list.filter(func(n): return n.queued and not n.ready)
	_queue_list.sort_custom(func(x, y): return _priority(x, f) < _priority(y, f))
	while not _queue_list.is_empty() and _jobs.size() < _max_jobs:
		var n: QuadNode = _queue_list.pop_front()
		if _jobs.has(n.get_instance_id()):
			continue
		var job := {
			"node": n, "face": n.face, "a0": n.a0, "b0": n.b0, "size": n.size,
			"depth": n.depth, "collide": n.depth >= collision_depth,
			"scatter": n.depth == scatter_depth and scatter_maker.is_valid(),
		}
		_jobs[n.get_instance_id()] = WorkerThreadPool.add_task(_build.bind(job), false, "planet piece")


func _priority(n: QuadNode, f: Vector3) -> float:
	# Coarse pieces first (so there are never holes), then the nearest.
	return n.depth * 100000.0 + f.distance_to(n.center * shape.radius)


func _apply_finished(limit: int) -> void:
	_done_lock.lock()
	var batch := _done.slice(0, limit)
	_done = _done.slice(limit)
	_done_lock.unlock()
	for job in batch:
		var n: QuadNode = job["node"]
		var id := n.get_instance_id()
		WorkerThreadPool.wait_for_task_completion(_jobs[id])
		_jobs.erase(id)
		if not n.queued:
			continue  # freed while it was being built
		_make_piece(n, job)


func _make_piece(n: QuadNode, job: Dictionary) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job["arrays"])
	mesh.surface_set_material(0, material)
	if job.has("river") and river_material != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job["river"])
		mesh.surface_set_material(1, river_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visible = false
	add_child(mi)
	n.mesh_instance = mi
	if job.has("faces"):
		var shape_res := ConcavePolygonShape3D.new()
		shape_res.set_faces(job["faces"])
		shape_res.backface_collision = true
		var body := StaticBody3D.new()
		body.add_to_group("planet_ground")   # lets characters know it's climbable ground
		var col := CollisionShape3D.new()
		col.shape = shape_res
		body.add_child(col)
		add_child(body)
		n.body = body
	if job.has("scatter_data") and scatter_builder.is_valid():
		n.scatter = scatter_builder.call(job["scatter_data"])
		if n.scatter:
			add_child(n.scatter)
	n.ready = true


func _exit_tree() -> void:
	for key in _jobs:
		WorkerThreadPool.wait_for_task_completion(_jobs[key])
	_jobs.clear()


# ---------------------------------------------------------------------------
# Building one piece (runs on a worker thread)
# ---------------------------------------------------------------------------
func _build(job: Dictionary) -> void:
	var face: int = job["face"]
	var a0: float = job["a0"]
	var b0: float = job["b0"]
	var size: float = job["size"]
	var n := RES
	var w := n + 3   # one extra ring of points all round, for seamless normals
	var step := size / n
	var R := shape.radius

	var pos := PackedVector3Array()
	pos.resize(w * w)
	var dirs := PackedVector3Array()
	dirs.resize(w * w)
	var trails := PackedFloat32Array()
	trails.resize(w * w)
	for i in w:
		for j in w:
			var d := PlanetShape.cube_dir(face, a0 + (i - 1) * step, b0 + (j - 1) * step)
			var sm := shape.sample(d)
			dirs[i * w + j] = d
			trails[i * w + j] = sm.z
			pos[i * w + j] = d * (R + sm.x)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var count := (n + 1) * (n + 1)
	verts.resize(count)
	normals.resize(count)
	colors.resize(count)
	for i in n + 1:
		for j in n + 1:
			var k := (i + 1) * w + (j + 1)
			var du := pos[k + w] - pos[k - w]
			var dv := pos[k + 1] - pos[k - 1]
			var v := i * (n + 1) + j
			verts[v] = pos[k]
			normals[v] = du.cross(dv).normalized()
			var d := dirs[k]
			# Extra data for the shader: forest amount, coldness, frozen sea, trail.
			var cold := shape.coldness(d)
			var frozen := shape.ice(d) if cold > 0.6 else 0.0
			colors[v] = Color(shape.forest(d), cold, frozen, trails[k])

	var idx := PackedInt32Array()
	for i in n:
		for j in n:
			var v00 := i * (n + 1) + j
			var v10 := v00 + n + 1
			var v01 := v00 + 1
			var v11 := v10 + 1
			# Godot treats clockwise triangles as the front side.
			idx.append_array([v00, v11, v10, v00, v01, v11])

	var faces := PackedVector3Array()
	if job["collide"]:
		faces.resize(idx.size())
		for t in idx.size():
			faces[t] = verts[idx[t]]

	# Skirts: short walls hanging down from each edge. They hide hairline
	# gaps where a detailed piece meets a less detailed one.
	# (kept short, so they don't show through the see-through water from far away)
	var skirt := minf(node_width_from_size(size) / n + 0.5, 6.0)
	var edges := [[], [], [], []]
	for t in n + 1:
		edges[0].append(t)                       # i = 0
		edges[1].append(n * (n + 1) + t)         # i = n
		edges[2].append(t * (n + 1))             # j = 0
		edges[3].append(t * (n + 1) + n)         # j = n
	for edge in edges:
		var low := []
		for vi in edge:
			low.append(verts.size())
			verts.append(verts[vi] - verts[vi].normalized() * skirt)
			normals.append(normals[vi])
			colors.append(colors[vi])
		for e in edge.size() - 1:
			var a: int = edge[e]
			var b: int = edge[e + 1]
			var la: int = low[e]
			var lb: int = low[e + 1]
			# both sides, so it works whichever way it is seen
			idx.append_array([a, la, b, b, la, lb, a, b, la, b, lb, la])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	job["arrays"] = arrays
	var river := _build_river(face, a0, b0, size, n, w, pos, dirs)
	if not river.is_empty():
		job["river"] = river
	if job["collide"]:
		job["faces"] = faces
	if job["scatter"]:
		job["scatter_data"] = scatter_maker.call(face, a0, b0, size)

	_done_lock.lock()
	_done.append(job)
	_done_lock.unlock()


func node_width_from_size(size: float) -> float:
	return size * shape.radius * PI * 0.25


## River water: a sheet just above sea level over the river channels, with
## the flow direction and amount stored per corner for the river shader.
## Empty if there is no river in this piece.
func _build_river(face: int, a0: float, b0: float, size: float, n: int, w: int, pos: PackedVector3Array, dirs: PackedVector3Array) -> Array:
	var R := shape.radius
	var flows := {}   # grid index -> Vector4
	var any := false
	for i in n + 1:
		for j in n + 1:
			var k := (i + 1) * w + (j + 1)
			if pos[k].length() - R > 3.0:
				continue
			var f := shape.river_flow(dirs[k])
			if f.w > 0.0:
				flows[i * (n + 1) + j] = f
				any = true
	if not any:
		return []
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var remap := {}
	for i in n:
		for j in n:
			var corners := [i * (n + 1) + j, (i + 1) * (n + 1) + j, (i + 1) * (n + 1) + j + 1, i * (n + 1) + j + 1]
			var has := false
			for c in corners:
				if flows.has(c):
					has = true
			if not has:
				continue
			for c in corners:
				if not remap.has(c):
					remap[c] = verts.size()
					var ci: int = c / (n + 1)
					var cj: int = c % (n + 1)
					var d := dirs[(ci + 1) * w + (cj + 1)]
					var f: Vector4 = flows.get(c, Vector4(0, 0, 0, 0))
					verts.append(d * (R + 0.06))
					normals.append(d)
					colors.append(Color(f.x * 0.5 + 0.5, f.y * 0.5 + 0.5, f.z * 0.5 + 0.5, f.w))
			# same winding as the ground (clockwise is the front side)
			idx.append_array([remap[corners[0]], remap[corners[2]], remap[corners[1]],
					remap[corners[0]], remap[corners[3]], remap[corners[2]]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays
