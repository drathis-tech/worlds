extends Node3D
## Demo: walk around the planet with the test character.
##
## Extra modes (used to check the planet without playing):
##   godot --path godot -- --shots       saves preview screenshots to user://
##   godot --path godot -- --test-walk   checks landing, walking and running
##   godot --path godot -- --test-swim   checks swimming to a shore and climbing out
##   godot --path godot -- --test-climb  checks climbing a steep rock face
##   godot --path godot -- --test-fly    flies up to space and back down

@onready var planet: Planet = $Planet


func _ready() -> void:
	if not "--shots" in OS.get_cmdline_user_args():
		_make_hud()
	if "--shots" in OS.get_cmdline_user_args():
		_take_shots.call_deferred()
	elif "--test-walk" in OS.get_cmdline_user_args():
		_test_walk.call_deferred()
	elif "--test-swim" in OS.get_cmdline_user_args():
		_test_swim.call_deferred()
	elif "--test-climb" in OS.get_cmdline_user_args():
		_test_climb.call_deferred()
	elif "--test-fly" in OS.get_cmdline_user_args():
		_test_fly.call_deferred()


## On-screen info: what you're doing, altitude, speed and the controls.
func _make_hud() -> void:
	var hud := PlanetHud.new()
	hud.walker = $Walker
	add_child(hud)


## Flies straight up to space and checks nothing breaks on the way.
func _test_fly() -> void:
	var walker: PlanetWalker = $Walker
	await planet.loaded
	walker.set_flying(true)
	_press(KEY_SPACE, true)
	_press(KEY_SHIFT, true)
	var t0 := Time.get_ticks_msec()
	var reached := -1.0
	for i in 40 * 60:
		await get_tree().physics_frame
		if walker.altitude() > planet.radius * 1.5:
			reached = (Time.get_ticks_msec() - t0) / 1000.0
			break
	_press(KEY_SPACE, false)
	_press(KEY_SHIFT, false)
	walker.velocity = Vector3.ZERO
	if reached < 0.0:
		print("Fly test FAILED: only got to %d m" % roundi(walker.altitude()))
		get_tree().quit()
		return
	print("Fly test: reached space (%d m up) in %.1f s" % [roundi(walker.altitude()), reached])
	# look back down at the planet and let the far-away ground settle
	walker.camera.rotation.x = -1.35
	for i in 600:
		await get_tree().process_frame
		if i > 10 and planet.terrain.is_idle():
			break
	var pieces := 0
	for c in planet.terrain.get_children():
		if c is MeshInstance3D and c.visible:
			pieces += 1
	print("From space: %d ground pieces showing (detail drops far away, as it should)" % pieces)
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("user://shot_space_from_walker.png")
		print("Saved ", ProjectSettings.globalize_path("user://shot_space_from_walker.png"))
	# fly back down and check the ground comes back in detail
	walker.camera.rotation.x = 0.0
	_press(KEY_C, true)
	for i in 60 * 60:
		await get_tree().physics_frame
		if walker.altitude() < 120.0:
			break
	_press(KEY_C, false)
	walker.velocity = Vector3.ZERO
	await get_tree().create_timer(1.0).timeout
	print("Back down at %d m altitude" % roundi(walker.altitude()))
	get_tree().quit()


func _press(code: Key, down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = down
	Input.parse_input_event(key)


## Puts the walker at a spot facing `toward`, then waits for the ground there.
func _teleport(walker: PlanetWalker, pos: Vector3, toward: Vector3) -> void:
	var up := planet.up_at(pos)
	var fwd := (toward - up * toward.dot(up)).normalized()
	var x := up.cross(-fwd).normalized()
	walker.process_mode = Node.PROCESS_MODE_DISABLED
	walker.velocity = Vector3.ZERO
	walker.global_transform = Transform3D(Basis(x, up, -fwd), pos)
	for i in 3000:
		await get_tree().process_frame
		if i > 10 and planet.terrain.is_idle():
			break
	walker.process_mode = Node.PROCESS_MODE_INHERIT


## Searches outward from the first landing site for something along the ground.
## `test` gets (ground height) for each step; returns [position, direction, step] or [].
func _search(test: Callable, max_dist: float = 600.0) -> Array:
	var site := planet.landing_sites[0]
	var p := site.global_position
	var up := site.global_basis.y.normalized()
	var t1 := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	for k in 48:
		var dir := t1.rotated(up, k * TAU / 48.0)
		var prev_h := planet.ground_height_at(p)
		var d := 2.0
		while d < max_dist:
			var q := p + dir * d
			var h := planet.ground_height_at(q)
			if test.call(prev_h, h):
				return [q, dir, d]
			prev_h = h
			d += 2.0
	return []


## Swims to the nearest shore and checks the walker climbs out.
func _test_swim() -> void:
	var walker: PlanetWalker = $Walker
	await planet.loaded
	# a place where land drops into water at least 3 m deep
	var found := _search(func(a, b): return a > 0.5 and b < -3.0)
	if found.is_empty():
		print("Swim test: no shore found nearby")
		get_tree().quit()
		return
	var shore: Vector3 = found[0]
	var dir: Vector3 = found[1]
	var start := _ground(shore + dir * 14.0)
	start = planet.to_global(planet.to_local(start).normalized() * planet.radius)  # water surface
	await _teleport(walker, start, -dir)
	await get_tree().create_timer(2.0).timeout
	print("In the water: swimming %s, depth %.1f m, ground below %.1f m" % [walker.swimming, walker.water_depth(), planet.ground_height_at(walker.global_position)])
	_press(KEY_W, true)
	var out_at := -1.0
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		if not walker.swimming and walker.is_on_floor() and planet.altitude_of(walker.global_position) > 0.0:
			out_at = i + 1
			break
	_press(KEY_W, false)
	if out_at > 0:
		print("Climbed out of the water after %d s, standing %.1f m above sea level" % [out_at, planet.altitude_of(walker.global_position)])
	else:
		print("FAILED to get out: swimming %s, altitude %.1f m, ground %.1f m" % [walker.swimming, planet.altitude_of(walker.global_position), planet.ground_height_at(walker.global_position)])
	get_tree().quit()


## Walks into a steep slope and checks the walker climbs it.
func _test_climb() -> void:
	var walker: PlanetWalker = $Walker
	await planet.loaded
	# a spot where the ground rises more than 2.2 m over 2 m (about 48 degrees+)
	var found := _search(func(a, b): return b - a > 2.2 and a > 1.0, 900.0)
	if found.is_empty():
		print("Climb test: no steep slope found nearby")
		get_tree().quit()
		return
	var dir: Vector3 = found[1]
	var base := _ground(found[0] - dir * 4.0)
	await _teleport(walker, base + planet.up_at(base) * 0.3, dir)
	await get_tree().create_timer(1.0).timeout
	var h0 := planet.altitude_of(walker.global_position)
	_press(KEY_W, true)
	var climbed_any := false
	for i in 20:
		await get_tree().physics_frame
	var top := h0
	var reached_top_at := -1
	var t_start := Time.get_ticks_msec()
	for i in 12 * 60:
		await get_tree().physics_frame
		climbed_any = climbed_any or walker.climbing
		var alt := planet.altitude_of(walker.global_position)
		top = maxf(top, alt)
		# made it up: standing again after climbing, at least 4 m higher
		if climbed_any and walker.is_on_floor() and alt - h0 > 4.0:
			reached_top_at = ceili((Time.get_ticks_msec() - t_start) / 1000.0)
			break
	_press(KEY_W, false)
	if reached_top_at > 0:
		print("Climb test: climbed a steep face from %.1f m to %.1f m in %d s (used climbing: %s)" % [h0, top, reached_top_at, climbed_any])
	else:
		print("Climb test FAILED: started at %.1f m, highest %.1f m" % [h0, top])
	get_tree().quit()


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
	# A snowy biome: cold land, not too close to the pole.
	var snowy := _find_spot(func(d: Vector3) -> bool:
		return planet.shape.coldness(d) > 0.7 and absf(d.y) < 0.75 and planet.shape.height(d) > 12.0)
	if snowy != Vector3.ZERO:
		var su := planet.up_at(snowy)
		var sf := su.cross(Vector3.UP if absf(su.y) < 0.9 else Vector3.RIGHT).normalized()
		shots.append(["snow", snowy + su * 25.0 - sf * 40.0, snowy + sf * 120.0])
	# The frozen polar sea, looking from the ice towards land.
	var icy := _find_spot(func(d: Vector3) -> bool:
		return planet.shape.ice(d) > 0.9 and planet.shape.height(_offset(d, 120.0)) > 8.0)
	if icy != Vector3.ZERO:
		var iu := planet.up_at(icy)
		var land := _ground(planet.to_global(_offset(planet.to_local(icy).normalized(), 120.0) * planet.radius))
		var dir := (land - icy)
		dir = (dir - iu * dir.dot(iu)).normalized()
		shots.append(["ice", icy + iu * 6.0 - dir * 20.0, land + iu * 10.0])
	# Standing on a dirt trail, looking along it.
	var trail_spot := Vector3.ZERO
	for i in 20000:
		var d := PlanetShape.fibonacci_dir(i, 20000)
		var sm := planet.shape.sample(d)
		if sm.z > 0.8 and sm.x > 4.0 and planet.shape.coldness(d) < 0.2 and planet.shape.forest(d) > 0.25:
			trail_spot = planet.to_global(d * (planet.radius + sm.x))
			break
	if trail_spot != Vector3.ZERO:
		var tu2 := planet.up_at(trail_spot)
		var t1 := tu2.cross(Vector3.UP if absf(tu2.y) < 0.9 else Vector3.RIGHT).normalized()
		var best_dir2 := t1
		var best_score := -1.0
		for k in 36:
			var dir3 := t1.rotated(tu2, k * TAU / 36.0)
			var score := 0.0
			for step in [10.0, 20.0, 30.0]:
				score += planet.shape.sample(planet.to_local(trail_spot + dir3 * step).normalized()).z
			if score > best_score:
				best_score = score
				best_dir2 = dir3
		shots.insert(1, ["trail", trail_spot + tu2 * 1.7 - best_dir2 * 3.0, trail_spot + best_dir2 * 40.0 + tu2 * 1.0])
		shots.insert(2, ["trail_above", trail_spot + tu2 * 28.0 - best_dir2 * 25.0, trail_spot + best_dir2 * 50.0])
	# Inside a forest, at eye level.
	var forest_spot := _find_spot(func(d: Vector3) -> bool:
		return planet.shape.forest(d) > 0.8 and planet.shape.coldness(d) < 0.1 and planet.shape.sample(d).z < 0.1 \
				and planet.shape.height(d) > 6.0 and planet.shape.raw_height(d).y < 0.1)
	if forest_spot != Vector3.ZERO:
		var fu := planet.up_at(forest_spot)
		var ff := fu.cross(Vector3.UP if absf(fu.y) < 0.9 else Vector3.RIGHT).normalized()
		shots.insert(3, ["forest", forest_spot + fu * 1.7, forest_spot + ff * 30.0 + fu * 2.5])
	# From the top of the highest nearby hill, looking out over the land.
	var best_top := p
	var best_dir := toward
	for k in 24:
		var dir2 := toward.rotated(up, k * TAU / 24.0)
		for step in range(1, 13):
			var q := _ground(p + dir2 * step * 45.0)
			if planet.altitude_of(q) > planet.altitude_of(best_top):
				best_top = q
				best_dir = dir2
	var tu := planet.up_at(best_top)
	shots.insert(1, ["vista", best_top + tu * 12.0 - best_dir * 5.0, _ground(best_top + best_dir * 350.0) + tu * 20.0])
	shots.append(["orbit_pole", Vector3(0.35, 1.0, 0.6).normalized() * R * 2.9, Vector3.ZERO])
	var only := OS.get_environment("SHOTS")
	if only != "":
		shots = shots.filter(func(sh): return sh[0] in only.split(","))
	for shot in shots:
		var eye: Vector3 = shot[1]
		var target: Vector3 = shot[2]
		var near_up := planet.up_at(eye)
		var cam_up := near_up if eye.length() < R * 1.5 else eye.normalized().cross(toward).cross(eye.normalized()).normalized()
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


## First evenly-spread spot on the planet where `test(direction)` is true (world position on the ground).
func _find_spot(test: Callable) -> Vector3:
	for i in 6000:
		var d := PlanetShape.fibonacci_dir(i, 6000)
		if test.call(d):
			return planet.to_global(d * (planet.radius + planet.shape.height(d)))
	return Vector3.ZERO


## Direction `metres` away from `d` along the ground, towards the equator.
func _offset(d: Vector3, metres: float) -> Vector3:
	var toward_equator := (Vector3(0, -signf(d.y), 0) - d * d.dot(Vector3(0, -signf(d.y), 0))).normalized()
	return (d + toward_equator * (metres / planet.radius)).normalized()


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
