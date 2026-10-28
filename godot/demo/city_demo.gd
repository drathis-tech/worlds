extends Node3D
## Demo: walk and fly around the city planet with the test character.
##
## Extra modes (used to check the city without playing):
##   godot --path godot res://demo/city_demo.tscn -- --shots        screenshots to user://
##   godot --path godot res://demo/city_demo.tscn -- --test-walk    walks the streets
##   godot --path godot res://demo/city_demo.tscn -- --test-fly     flies up to space and back

@onready var city: CityPlanet = $CityPlanet
@onready var walker: PlanetWalker = $Walker


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--shots" in args:
		var hud := PlanetHud.new()
		hud.walker = walker
		add_child(hud)
	if "--shots" in args:
		_take_shots.call_deferred()
	elif "--test-walk" in args:
		_test_walk.call_deferred()
	elif "--test-fly" in args:
		_test_fly.call_deferred()


func _press(code: Key, down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = down
	Input.parse_input_event(key)


func _face(dir: Vector3) -> void:
	var up := city.up_at(walker.global_position)
	var fwd := (dir - up * dir.dot(up)).normalized()
	walker.global_transform.basis = Basis(up.cross(-fwd).normalized(), up, -fwd)


## Walks down a street, then into a row of buildings to check they block the way.
func _test_walk() -> void:
	var t0 := Time.get_ticks_msec()
	await city.loaded
	print("City built in %d ms: %d landing pads, tallest tower %d m" % [Time.get_ticks_msec() - t0, city.landing_sites.size(), roundi(city.tallest[1])])
	await get_tree().create_timer(2.0).timeout
	print("After landing: altitude %.2f m, on floor: %s" % [walker.altitude(), walker.is_on_floor()])
	var site := city.landing_sites[0]
	var east := site.global_basis.x
	var north := site.global_basis.z
	# walk along the plaza and out onto the street
	_face(north)
	var start := walker.global_position
	_press(KEY_W, true)
	await get_tree().create_timer(8.0).timeout
	_press(KEY_W, false)
	await get_tree().create_timer(0.5).timeout
	print("Walked %.1f m in 8 s, altitude %.2f m, on floor: %s" % [walker.global_position.distance_to(start), walker.altitude(), walker.is_on_floor()])
	# back to the plaza, then walk straight at the next block's buildings for
	# 20 s (100 m if nothing stops us)
	city.place_at_landing_site(walker)
	await get_tree().create_timer(1.0).timeout
	_face(east)
	start = walker.global_position
	var climbed := false
	_press(KEY_W, true)
	for i in 20 * 60:
		await get_tree().physics_frame
		climbed = climbed or walker.climbing
	_press(KEY_W, false)
	var flat := walker.global_position - start
	var up := city.up_at(walker.global_position)
	var along := (flat - up * flat.dot(up)).length()
	print("Walking into buildings for 20 s: %.1f m along the ground, now %.1f m up, climbed a wall: %s" % [along, walker.altitude(), climbed])
	get_tree().quit()


func _test_fly() -> void:
	await city.loaded
	walker.set_flying(true)
	_press(KEY_SPACE, true)
	_press(KEY_SHIFT, true)
	var t0 := Time.get_ticks_msec()
	var reached := -1.0
	for i in 40 * 60:
		await get_tree().physics_frame
		if walker.altitude() > city.radius * 1.5:
			reached = (Time.get_ticks_msec() - t0) / 1000.0
			break
	_press(KEY_SPACE, false)
	_press(KEY_SHIFT, false)
	walker.velocity = Vector3.ZERO
	print("Fly test: %s" % ("reached space in %.1f s" % reached if reached > 0.0 else "FAILED"))
	walker.camera.rotation.x = -1.35
	for i in 30:
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("user://city_space_from_walker.png")
		print("Saved ", ProjectSettings.globalize_path("user://city_space_from_walker.png"))
	walker.camera.rotation.x = 0.0
	_press(KEY_C, true)
	for i in 60 * 60:
		await get_tree().physics_frame
		if walker.altitude() < 80.0:
			break
	_press(KEY_C, false)
	print("Back down at %d m" % roundi(walker.altitude()))
	get_tree().quit()


func _take_shots() -> void:
	await city.loaded
	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 20000.0
	cam.fov = 68.0
	add_child(cam)
	cam.current = true
	city.focus = cam
	walker.visible = false

	var R := city.radius
	var site := city.landing_sites[0]
	var p := site.global_position
	var up := site.global_basis.y
	var east := site.global_basis.x
	var north := site.global_basis.z
	var cell := R * PI * 0.5 / CityLayout.BLOCKS
	var street := p + east * cell * 0.5          # centre of the road beside the plaza
	var top_dir: Vector3 = city.tallest[0]
	var top := city.to_global(top_dir * (R + city.tallest[1]))
	var tu := city.up_at(top)
	var t_side := tu.cross(Vector3.UP if absf(tu.y) < 0.9 else Vector3.RIGHT).normalized()

	var shots := [
		["city_street", street + up * 1.7 - north * 10.0, street + north * 120.0 + up * 30.0, up],
		["city_plaza", p - north * 18.0 + up * 4.0, p + north * 60.0 + up * 25.0, up],
		["city_canyon", street + up * 30.0 - north * 30.0, street + north * 250.0 + up * 25.0, up],
		["city_rooftop", top + tu * 6.0 + t_side * 12.0, top + t_side * 500.0 - tu * 120.0, tu],
		["city_skyline", p + up * 520.0 - north * 380.0, p + north * 500.0 + up * 40.0, up],
		["city_orbit", city.to_global(up * R * 2.6 + east * R * 0.8), city.global_position, north],
	]
	var only := OS.get_environment("SHOTS")
	if only != "":
		shots = shots.filter(func(sh): return sh[0] in only.split(","))
	for shot in shots:
		cam.look_at_from_position(shot[1], shot[2], shot[3])
		for i in 30:
			await get_tree().process_frame
		var path := "user://%s.png" % shot[0]
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved ", ProjectSettings.globalize_path(path))
	get_tree().quit()
