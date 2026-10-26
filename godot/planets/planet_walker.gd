class_name PlanetWalker
extends CharacterBody3D
## A simple test character for walking on a round planet. Use it to get a
## feel for the planet's size before the real ship and player are ready.
##
## Set up: a CharacterBody3D with this script, plus a CollisionShape3D
## (capsule) and a Camera3D (about 0.7 m up) as children.
## Controls: WASD or arrow keys to move, mouse to look, Space to jump,
## Shift to run, Esc frees the mouse.

## Walking speed in m/s. At 5 m/s a 1 km planet takes about 20 minutes to walk round.
@export var walk_speed: float = 5.0
@export var run_speed: float = 12.0
@export var jump_speed: float = 6.0
@export var mouse_sensitivity: float = 0.003

@onready var camera: Camera3D = $Camera3D

var _pitch: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_object_local(Vector3.UP, -event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.4, 1.4)
		camera.rotation.x = _pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	var fall := up * velocity.dot(up) + gravity * delta
	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		fall = up * jump_speed

	var input := Vector2(
		_axis(KEY_D, KEY_RIGHT) - _axis(KEY_A, KEY_LEFT),
		_axis(KEY_S, KEY_DOWN) - _axis(KEY_W, KEY_UP)).limit_length(1.0)
	var speed := run_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	var b2 := global_transform.basis
	var walk := (b2.x * input.x + b2.z * input.y) * speed

	velocity = walk + fall
	move_and_slide()


func _axis(key_a: Key, key_b: Key) -> float:
	return 1.0 if Input.is_key_pressed(key_a) or Input.is_key_pressed(key_b) else 0.0
