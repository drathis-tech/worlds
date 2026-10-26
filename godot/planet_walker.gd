extends CharacterBody3D
## A simple test character for walking on a round planet. Use it to get a
## feel for the planet's size before the real ship and player are ready.
##
## Set up: a CharacterBody3D with this script, a CollisionShape3D (capsule)
## and a Camera3D (raise it about 0.7 m) as children.
## Controls: arrow keys to move, mouse to look, Space to jump, Esc frees the mouse.

@export var speed: float = 8.0
@export var jump_speed: float = 6.0
@export var mouse_sensitivity: float = 0.003

@onready var camera: Camera3D = $Camera3D

var _pitch: float = 0.0


func _ready() -> void:
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

	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var b2 := global_transform.basis
	var walk := (b2.x * input.x + b2.z * input.y) * speed

	velocity = walk + fall
	move_and_slide()
