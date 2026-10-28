class_name PlanetWalker
extends CharacterBody3D
## A simple test character for walking on a round planet. Use it to get a
## feel for the planet's size before the real ship and player are ready.
##
## Set up: a CharacterBody3D with this script, plus a CollisionShape3D
## (capsule, 1.8 m tall, standing on the origin) and a Camera3D (about 1.6 m up).
##
## Controls:
##   WASD / arrows  move          Shift  run          mouse  look
##   Space          jump, or swim up in water
##   C              swim down
##   F              fly on / off. While flying: Space up, C down, Shift fast.
##                  You speed up the higher you go, so space is a few seconds away.
##   Walk into a steep rock face to climb it. At a shore, swim into the bank
##   to climb out. Esc frees the mouse.

## Walking speed in m/s. At 5 m/s a 1 km planet takes about 20 minutes to walk round.
@export var walk_speed: float = 5.0
@export var run_speed: float = 12.0
@export var jump_speed: float = 6.0
@export var swim_speed: float = 3.5
@export var climb_speed: float = 2.5
## Slopes up to this angle are walkable. Steeper ones can be climbed.
@export var max_walk_angle_degrees: float = 52.0
@export var mouse_sensitivity: float = 0.003
## Flying speed near the ground, in m/s. It grows with altitude.
@export var fly_speed: float = 20.0

@onready var camera: Camera3D = $Camera3D

var _pitch: float = 0.0
var _planet: Node3D
## True while in water (oceans and lakes).
var swimming := false
## True while climbing a steep face.
var climbing := false
## True while flying (press F).
var flying := false


func _ready() -> void:
	floor_max_angle = deg_to_rad(max_walk_angle_degrees)
	floor_snap_length = 0.4
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_object_local(Vector3.UP, -event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.4, 1.4)
		camera.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		set_flying(not flying)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_flying(on: bool) -> void:
	flying = on
	velocity = Vector3.ZERO


## Height above sea level in metres (or 0 if there is no planet).
func altitude() -> float:
	if _planet == null:
		_planet = get_tree().get_first_node_in_group("planets") as Node3D
	if _planet == null or not _planet.has_method("altitude_of"):
		return 0.0
	return _planet.altitude_of(global_position)


## How deep the middle of the body is under the water surface (negative = above).
func water_depth() -> float:
	if _planet == null:
		_planet = get_tree().get_first_node_in_group("planets") as Node3D
	if _planet == null or not _planet.has_method("altitude_of"):
		return -INF
	return -_planet.altitude_of(global_position + up_direction * 0.9)


func _physics_process(delta: float) -> void:
	# The planet's gravity area tells us which way is down.
	var gravity := get_gravity()
	if gravity.length() > 0.01:
		up_direction = -gravity.normalized()
		# Turn the body so its feet point at the planet.
		var b := global_transform.basis.orthonormalized()
		var turn := Quaternion(b.y, up_direction)
		global_transform.basis = (Basis(turn) * b).orthonormalized()

	var up := up_direction
	var input := Vector2(
		_axis(KEY_D, KEY_RIGHT) - _axis(KEY_A, KEY_LEFT),
		_axis(KEY_S, KEY_DOWN) - _axis(KEY_W, KEY_UP)).limit_length(1.0)
	var b2 := global_transform.basis
	var wish := b2.x * input.x + b2.z * input.y   # along the ground
	var vertical := up * velocity.dot(up)

	var depth := water_depth()
	swimming = depth > 0.0
	var pushing_wall := is_on_wall() and input.y < -0.1 and _wall_is_steep()
	climbing = pushing_wall and not is_on_floor()

	if flying:
		swimming = false
		climbing = false
		# Fly where the camera looks. Faster the higher you are, so you can
		# reach space quickly but still fly slowly near the ground.
		var look := camera.global_transform.basis
		var dir := -look.z * -input.y + look.x * input.x
		if Input.is_key_pressed(KEY_SPACE):
			dir += up
		if Input.is_key_pressed(KEY_C):
			dir -= up
		var speed := fly_speed * (1.0 + maxf(altitude(), 0.0) / 35.0)
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= 4.0
		speed = minf(speed, 4000.0)
		velocity = velocity.lerp(dir.limit_length(1.0) * speed, 1.0 - exp(-4.0 * delta))
	elif swimming:
		# Float with the head above water; Space swims up, C dives.
		var target := 0.25   # body middle this far under the surface
		var float_force := clampf((depth - target) * 4.0, -6.0, 6.0)
		var swim_vertical := up * velocity.dot(up)
		swim_vertical = swim_vertical.lerp(up * float_force, 1.0 - exp(-3.0 * delta))
		if Input.is_key_pressed(KEY_SPACE):
			swim_vertical = up * swim_speed
		elif Input.is_key_pressed(KEY_C):
			swim_vertical = -up * swim_speed
		# Swimming into a bank near the surface: climb out.
		if pushing_wall and depth < 1.5:
			swim_vertical = up * climb_speed * 1.6
		velocity = wish * swim_speed + swim_vertical
	elif pushing_wall:
		# Walking into a face too steep to walk up: climb it.
		velocity = wish * 1.0 + up * climb_speed
	else:
		vertical += gravity * delta
		if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
			vertical = up * jump_speed
		var speed := run_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
		velocity = wish * speed + vertical

	move_and_slide()


## True when pushing against steep ground or rock (not trees or other things).
func _wall_is_steep() -> bool:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var collider := hit.get_collider() as Node
		if collider == null or not collider.is_in_group("planet_ground"):
			continue
		if hit.get_normal().dot(up_direction) < cos(floor_max_angle):
			return true
	return false


func _axis(key_a: Key, key_b: Key) -> float:
	return 1.0 if Input.is_key_pressed(key_a) or Input.is_key_pressed(key_b) else 0.0
