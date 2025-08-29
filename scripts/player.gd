extends CharacterBody3D

# === MOVEMENT SETTINGS ===
@export var speed = 3.5
@export var sprint_speed = 6.5
@export var jump_velocity = 3.5
@export var acceleration = 13.0
@export var friction = 15.0
@export var air_control = false

# === CAMERA SETTINGS ===
@export var mouse_sensitivity = 0.002
@export var camera_smoothing = 10.0

# === HEADBOB SETTINGS ===
@export var headbob_enabled = true
@export var headbob_intensity = 0.02
@export var headbob_frequency = 2.0
@export var headbob_sprint_multiplier = 1.4
@export var headbob_tilt_intensity = 0.5
@export var headbob_smoothing = 8.0

# === NODE REFERENCES ===
@onready var camera_pivot = $CameraPivot
@onready var camera = camera_pivot.get_node("Camera3D")
@onready var weapon = $CameraPivot/shotgun

# === STATE VARIABLES ===
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting = false
var headbob_time = 0.0
var headbob_offset = Vector3.ZERO
var headbob_tilt = 0.0
var original_camera_position: Vector3
var health = 200

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	original_camera_position = camera.position
	add_to_group("player")

func _input(event):
	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.5, 1.5)
	
	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Handle jumping
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	
	# Get movement input
	var input_dir = Vector2.ZERO
	if is_on_floor() or air_control:
		if Input.is_action_pressed("move_left"):
			input_dir.x -= 1
		if Input.is_action_pressed("move_right"):
			input_dir.x += 1
		if Input.is_action_pressed("move_forward"):
			input_dir.y -= 1
		if Input.is_action_pressed("move_backward"):
			input_dir.y += 1
		input_dir = input_dir.normalized()
	
	var is_moving_backward = Input.is_action_pressed("move_backward") and not Input.is_action_pressed("move_forward")
	is_sprinting = Input.is_action_pressed("sprint") and is_on_floor() and weapon.can_player_run() and not is_moving_backward
	var current_speed = sprint_speed if is_sprinting else speed
	
	# Convert input to world direction
	var direction = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply movement
	if is_on_floor() or air_control:
		if direction != Vector3.ZERO:
			velocity.x = move_toward(velocity.x, direction.x * current_speed, acceleration * delta)
			velocity.z = move_toward(velocity.z, direction.z * current_speed, acceleration * delta)
		else:
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0, friction * delta)
				velocity.z = move_toward(velocity.z, 0, friction * delta)
	
	update_headbob(delta, input_dir)
	move_and_slide()

# === HEADBOB SYSTEM ===
func update_headbob(delta: float, input_dir: Vector2):
	if not headbob_enabled or not camera:
		return
	
	var move_speed = get_move_speed()
	var is_moving_on_ground = is_moving() and is_on_floor() and input_dir != Vector2.ZERO
	
	if is_moving_on_ground:
		# Calculate frequency based on movement speed
		var speed_factor = move_speed / speed
		var current_frequency = headbob_frequency * speed_factor
		
		if is_sprinting:
			current_frequency *= headbob_sprint_multiplier
		
		headbob_time += delta * current_frequency
		
		# Calculate bobbing motions
		var vertical_bob = sin(headbob_time * PI * 2.0) * headbob_intensity * speed_factor
		var horizontal_sway = cos(headbob_time * PI) * headbob_intensity * 0.5 * speed_factor
		
		# Calculate head tilt from strafe movement
		var target_tilt = 0.0
		if input_dir.x != 0:
			target_tilt = -input_dir.x * headbob_tilt_intensity * deg_to_rad(1.0) * speed_factor
		
		headbob_tilt = lerp(headbob_tilt, target_tilt, headbob_smoothing * delta)
		
		var target_offset = Vector3(horizontal_sway, vertical_bob, 0)
		headbob_offset = headbob_offset.lerp(target_offset, headbob_smoothing * delta)
	else:
		# Return to neutral position when not moving
		headbob_offset = headbob_offset.lerp(Vector3.ZERO, headbob_smoothing * delta)
		headbob_tilt = lerp(headbob_tilt, 0.0, headbob_smoothing * delta)
		
		if move_speed < 0.1:
			headbob_time = 0.0
	
	# Apply headbob to camera
	camera.position = original_camera_position + headbob_offset
	camera.rotation.z = headbob_tilt

func take_damage(amount: float):
	health -= amount
	if (health <= 0):
		die()
	
func add_trauma(amount: float):
	pass
	
func die():
	print(die)
	
# === UTILITY FUNCTIONS ===
func get_move_speed():
	return Vector2(velocity.x, velocity.z).length()

func is_moving():
	return get_move_speed() > 0.1

func get_camera():
	return camera
