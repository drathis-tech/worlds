extends Node3D
## Demo: walk around the planet with the test character.
##
## Extra modes (used to check the planet without playing):
##   godot --path godot -- --shots       saves preview screenshots to user://
##   godot --path godot -- --test-walk   checks landing, walking and running

@onready var planet: Planet = $Planet


func _ready() -> void:
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots.call_deferred()
	elif "--test-walk" in OS.get_cmdline_user_args():
		_test_walk.call_deferred()


## Checks the walker lands, stands on the ground and can walk. Prints results.
func _test_walk() -> void:
	var walker: PlanetWalker = $Walker
	var t0 := Time.get_ticks_msec()
	await planet.loaded
	print("Ground around the walker loaded in %d ms" % (Time.get_ticks_msec() - t0))
	var bodies := 0
	var faces := 0
	for c in planet.terrain.get_children():
		if c is StaticBody3D:
			bodies += 1
			faces += (c.get_child(0).shape as ConcavePolygonShape3D).get_faces().size() / 3
	print("Collision pieces near the walker: %d (%d triangles)" % [bodies, faces])
	await get_tree().create_timer(3.0).timeout
	var ground := planet.ground_height_at(walker.global_position)
	print("After landing: feet %.2f m above ground, on floor: %s" % [planet.altitude_of(walker.global_position) - ground, walker.is_on_floor()])

	var start := walker.global_position
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().create_timer(10.0).timeout
	key.pressed = false
	Input.parse_input_event(key)
	await get_tree().create_timer(1.0).timeout
	var moved := walker.global_position.distance_to(start)
	ground = planet.ground_height_at(walker.global_position)
	print("After 10 s walking: moved %.1f m, feet %.2f m above ground, on floor: %s" % [moved, planet.altitude_of(walker.global_position) - ground, walker.is_on_floor()])

	# Run (Shift + W) for 40 s to check the ground keeps loading ahead.
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	key.pressed = true
	Input.parse_input_event(key)
	start = walker.global_position
	var lowest := INF
	var last := walker.global_position
	for i in 40:
		await get_tree().create_timer(1.0).timeout
		lowest = minf(lowest, planet.altitude_of(walker.global_position) - planet.ground_height_at(walker.global_position))
		if walker.global_position.distance_to(last) < 3.0:
			walker.rotate_object_local(Vector3.UP, 0.9)  # bumped into a tree or rock: turn
		last = walker.global_position
	key.pressed = false
	Input.parse_input_event(key)
	shift.pressed = false
	Input.parse_input_event(shift)
	print("After 40 s running: now %.1f m from start, lowest feet height %.2f m, on floor: %s" % [walker.global_position.distance_to(start), lowest, walker.is_on_floor()])
	get_tree().quit()


func _take_shots() -> void:
	var start := Time.get_ticks_msec()
	await planet.loaded
	print("First load: %d ms" % (Time.get_ticks_msec() - start))

	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 20000.0
	cam.fov = 65.0
	add_child(cam)
	cam.current = true
	planet.terrain.focus = cam

	var R := planet.radius
	var site := planet.landing_sites[0]
	var p := site.global_position
	var up := site.global_basis.y.normalized()
	var toward := _toward_highest(p, up, 350.0)

	var shots := [
		["ground", p + up * 1.7 - toward * 2.0, p + toward * 120.0 + up * 8.0],
		["low_flight", p + up * 45.0 - toward * 70.0, p + toward * 260.0],
		["mountain", _ground(p + toward * 200.0) + up * 70.0 - toward * 40.0, _ground(p + toward * 360.0) + up * 30.0],
		["orbit", up * R * 2.8 + toward * R * 0.9, Vector3.ZERO],
	]
	for shot in shots:
		var eye: Vector3 = shot[1]
		var target: Vector3 = shot[2]
		var cam_up := up if eye.length() < R * 1.5 else eye.normalized().cross(toward).cross(eye.normalized()).normalized()
		cam.look_at_from_position(eye, target, cam_up)
		var t := Time.get_ticks_msec()
		for i in 600:
			await get_tree().process_frame
			if i > 5 and planet.terrain.is_idle():
				break
		for i in 10:
			await get_tree().process_frame
		var path := "user://shot_%s.png" % shot[0]
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved %s (%d ms, %d nodes)" % [ProjectSettings.globalize_path(path), Time.get_ticks_msec() - t, planet.terrain.get_child_count()])
	get_tree().quit()


func _ground(world_pos: Vector3) -> Vector3:
	var d := planet.to_local(world_pos).normalized()
	return planet.to_global(d * (planet.radius + planet.shape.height(d)))


## Direction along the ground from `p` toward the tallest nearby land.
func _toward_highest(p: Vector3, up: Vector3, dist: float) -> Vector3:
	var t1 := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var best := t1
	var best_h := -INF
	for k in 24:
		var dir := t1.rotated(up, k * TAU / 24.0)
		var h := planet.ground_height_at(p + dir * dist)
		if h > best_h:
			best_h = h
			best = dir
	return best
