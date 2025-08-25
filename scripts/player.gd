extends CharacterBody3D

# Movement
@export var speed = 3.5
@export var sprint_speed = 6.5
@export var jump_velocity = 3.5
@export var acceleration = 13.0
@export var friction = 15.0
@export var air_control = false

# Camera
@export var mouse_sensitivity = 0.002
@export var camera_smoothing = 10.0

# Physics
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting = false

# Camera nodes
@onready var camera_pivot = $CameraPivot
@onready var camera = $CameraPivot/Camera3D

func _ready():
	# Capture mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	# Handle mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate the character horizontally
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Rotate the camera vertically
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		# Clamp the camera's vertical rotation
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.5, 1.5)
	
	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	# Handle gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Handle sprint
	is_sprinting = Input.is_action_pressed("sprint") and is_on_floor()
	var current_speed = sprint_speed if is_sprinting else speed

	# Get input direction
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
		
		# Normalize diagonal movement
		input_dir = input_dir.normalized()
	
	# Calculate movement direction relative to character's rotation
	var direction = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply movement with acceleration/friction
	if is_on_floor() or air_control:
		if direction != Vector3.ZERO:
			velocity.x = move_toward(velocity.x, direction.x * current_speed, acceleration * delta)
			velocity.z = move_toward(velocity.z, direction.z * current_speed, acceleration * delta)
		else:
			# Only apply friction on ground
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0, friction * delta)
				velocity.z = move_toward(velocity.z, 0, friction * delta)

	move_and_slide()
