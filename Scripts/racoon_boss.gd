extends CharacterBody3D
class_name RaccoonBoss

# === BASIC STATS ===
@export var max_health := 40.0
@export var move_speed := 4.0
@export var attack_distance := 1.5
@export var damage := 10.0

# === BISCUIT SETTINGS ===
@export_group("Biscuit Settings")
@export var biscuit_scene: PackedScene

# === ADVANCED BEHAVIOR ===
@export_group("Advanced Features")
@export var rage_speed_multiplier := 1.5
@export var lunge_range := 12.0
@export var circle_strafe_detection_time := 2.0
@export var retreat_punishment_speed := 6.0

# === LUNGE SYSTEM ===
@export_group("Lunge Settings")
@export var charge_duration := 1.5
@export var aim_duration := 0.5
@export var lunge_speed := 25.0
@export var lunge_distance := 5.0
@export var lunge_recovery_time := 1.0

# === CORE VARIABLES ===
var health: float
var player: Node3D
var current_state := "IDLE"
var attack_cooldown := 0.0

# === ANIMATION SYSTEM ===
var animation_player: AnimationPlayer
var current_animation := ""
var is_telegraphing := false

# === LUNGE STATE ===
var lunge_state := "NONE"
var lunge_timer := 0.0
var lunge_cooldown := 0.0
var target_position := Vector3.ZERO
var lunge_direction := Vector3.ZERO
var lunge_start_position := Vector3.ZERO

# === ANTI-CHEESE MECHANICS ===
var player_retreat_timer := 0.0
var last_player_position := Vector3.ZERO
var circle_strafe_timer := 0.0
var last_angle_to_player := 0.0
var consecutive_retreats := 0

func _ready():
	health = max_health
	player = get_tree().get_first_node_in_group("player")
	
	if not player:
		push_error("BOSS: No player found! Make sure player is in 'player' group!")
		return
	
	# Setup animation player
	setup_animation_player()
	
	add_to_group("boss")
	setup_basic_collision()
	setup_basic_mesh()
	
	# Start with idle animation
	play_animation("IDLE")

func setup_animation_player():
	animation_player = get_node_or_null("AnimationPlayer")
	if not animation_player:
		push_warning("BOSS: No AnimationPlayer found as child! Animations will not work.")
	else:
		print("BOSS: AnimationPlayer found and connected!")

func play_animation(state_name: String, force: bool = false):
	if not animation_player:
		return
	
	var animation_name = ""
	
	match state_name:
		"IDLE", "IN_RANGE":
			animation_name = "RESET"  # or whatever your idle animation is called
		"HUNTING":
			# Choose between Walk and Run based on speed/rage
			if health < max_health * 0.3 or consecutive_retreats > 2:
				animation_name = "Run"
			else:
				animation_name = "Walk"
		"TELEGRAPHING":
			animation_name = "RESET"  # Brief pause before attack
		"ATTACKING":
			animation_name = "Attack"
		"CHARGING LUNGE":
			animation_name = "charge"
		"AIMING":
			animation_name = "charge"  # Continue charge animation
		"LUNGING!":
			animation_name = "lunge"
		"RECOVERING":
			animation_name = "RESET"  # Back to idle pose
		"DEAD":
			animation_name = "RESET"  # Could add death animation later
	
	# Only change animation if it's different (unless forced)
	if force or current_animation != animation_name:
		current_animation = animation_name
		
		if animation_player.has_animation(animation_name):
			animation_player.play(animation_name)
		else:
			push_warning("BOSS: Animation '" + animation_name + "' not found!")

func setup_basic_collision():
	if not has_node("CollisionShape3D"):
		var collision = CollisionShape3D.new()
		var shape = CapsuleShape3D.new()
		shape.radius = 0.5
		shape.height = 2.0
		collision.shape = shape
		add_child(collision)

func setup_basic_mesh():
	if not has_node("MeshInstance3D"):
		var mesh_instance = MeshInstance3D.new()
		var capsule_mesh = CapsuleMesh.new()
		capsule_mesh.radius = 0.5
		capsule_mesh.height = 2.0
		mesh_instance.mesh = capsule_mesh
		
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.5, 0.2, 0.2)
		mesh_instance.material_override = material
		
		add_child(mesh_instance)

func _physics_process(delta):
	if not player:
		return
	
	# Update cooldowns
	if attack_cooldown > 0:
		attack_cooldown -= delta
	if lunge_cooldown > 0:
		lunge_cooldown -= delta
	
	# Handle lunge state machine first
	if lunge_state != "NONE":
		handle_lunge_state_machine(delta)
		return
	
	# Calculate distance to player
	var distance = global_position.distance_to(player.global_position)
	
	# Detect player behavior patterns
	detect_player_patterns(delta)
	
	# AI behavior
	advanced_ai_behavior(distance, delta)
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= 20 * delta
	else:
		velocity.y = 0
	
	move_and_slide()

# === LUNGE STATE MACHINE ===
func handle_lunge_state_machine(delta: float):
	lunge_timer -= delta
	
	match lunge_state:
		"CHARGING":
			handle_charging_state()
		"AIMING":
			handle_aiming_state()
		"LUNGING":
			handle_lunging_state(delta)
		"RECOVERING":
			handle_recovery_state()
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= 20 * delta
	else:
		velocity.y = 0
	
	move_and_slide()

func handle_charging_state():
	current_state = "CHARGING LUNGE"
	play_animation(current_state)
	
	# Stop all movement during charge
	velocity.x = 0
	velocity.z = 0
	
	# Visual effects for charging
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh and mesh.material_override:
		var charge_progress = (charge_duration - lunge_timer) / charge_duration
		var pulse_intensity = abs(sin(Time.get_ticks_msec() / 100.0)) * charge_progress
		mesh.material_override.albedo_color = Color(1, pulse_intensity * 0.5, pulse_intensity * 0.5)
	
	if lunge_timer <= 0:
		lunge_state = "AIMING"
		lunge_timer = aim_duration
		target_position = player.global_position

func handle_aiming_state():
	current_state = "AIMING"
	play_animation(current_state)
	
	# Still don't move during aiming
	velocity.x = 0
	velocity.z = 0
	
	# Face the locked target position
	var to_target = (target_position - global_position).normalized()
	to_target.y = 0
	if to_target.length() > 0.1:
		look_at(global_position + to_target, Vector3.UP)
	
	# Calculate final lunge direction and endpoint
	lunge_direction = to_target
	
	if lunge_timer <= 0:
		lunge_state = "LUNGING"
		lunge_timer = 2.0
		lunge_start_position = global_position

func handle_lunging_state(delta: float):
	current_state = "LUNGING!"
	play_animation(current_state)
	
	# Fly towards and past the target at high speed
	velocity.x = lunge_direction.x * lunge_speed
	velocity.z = lunge_direction.z * lunge_speed
	
	# Check if we've traveled far enough or hit something
	var distance_traveled = lunge_start_position.distance_to(global_position)
	var target_distance = lunge_start_position.distance_to(target_position) + lunge_distance
	
	# Visual trail effect
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh and mesh.material_override:
		mesh.material_override.albedo_color = Color(1, 1, 0.5)
	
	# Check for player collision during lunge
	if player and global_position.distance_to(player.global_position) < attack_distance * 2.0:
		if player.has_method("take_damage"):
			player.take_damage(damage * 2.0)
	
	# End lunge when we've gone far enough or timer runs out
	if distance_traveled >= target_distance or lunge_timer <= 0:
		lunge_state = "RECOVERING"
		lunge_timer = lunge_recovery_time
		velocity.x = 0
		velocity.z = 0

func handle_recovery_state():
	current_state = "RECOVERING"
	play_animation(current_state)
	
	# Stay still during recovery
	velocity.x = 0
	velocity.z = 0
	
	# Dim visual effects during recovery
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh and mesh.material_override:
		mesh.material_override.albedo_color = Color(0.5, 0.2, 0.2)
		mesh.material_override.emission_enabled = false
	
	if lunge_timer <= 0:
		lunge_state = "NONE"
		lunge_cooldown = 5.0

# === AI BEHAVIOR SYSTEM ===
func advanced_ai_behavior(distance: float, delta: float):
	var is_raging = health < max_health * 0.3
	
	# Check for lunge opportunity
	var can_lunge_distance = distance > attack_distance and distance < lunge_range
	var can_lunge_cooldown = lunge_cooldown <= 0
	var can_lunge_attack_ready = attack_cooldown <= 0
	
	# Lunge decision
	if can_lunge_distance and can_lunge_cooldown and can_lunge_attack_ready:
		var base_chance = 0.3
		var lunge_chance = base_chance
		
		# Punish retreating
		if consecutive_retreats > 1:
			lunge_chance = 0.9
		
		# Punish circle strafing
		elif circle_strafe_timer > 1.0:
			lunge_chance = 0.8
		
		# Rage increases chance
		if is_raging:
			lunge_chance = min(lunge_chance * 1.5, 1.0)
		
		var roll = randf()
		
		if roll < lunge_chance:
			start_dramatic_lunge()
			return
	
	# Otherwise use regular hunting behavior
	simple_ai_behavior(distance, delta)

func start_dramatic_lunge():
	if not player:
		return
	
	lunge_state = "CHARGING"
	lunge_timer = charge_duration
	current_state = "STARTING LUNGE"

func simple_ai_behavior(distance: float, delta: float):
	if distance > attack_distance:
		current_state = "HUNTING"
		play_animation(current_state)
		
		var target_position = player.global_position
		
		# Enhanced prediction
		if player.has_method("velocity") or "velocity" in player:
			var player_velocity = player.velocity if "velocity" in player else Vector3.ZERO
			if player_velocity.length() > 0.1:
				var time_to_reach = distance / move_speed
				var prediction_strength = 0.5
				
				# Punish retreat
				var to_player = (player.global_position - global_position).normalized()
				var retreat_dot = player_velocity.normalized().dot(-to_player)
				if retreat_dot > 0.5:
					prediction_strength = 0.8
				
				target_position += player_velocity * time_to_reach * prediction_strength
		
		var direction = (target_position - global_position).normalized()
		direction.y = 0
		
		# Rotate to face target
		if direction.length() > 0.1:
			look_at(global_position + direction, Vector3.UP)
		
		# Dynamic speed
		var current_speed = move_speed
		if health < max_health * 0.3:
			current_speed *= rage_speed_multiplier
		if consecutive_retreats > 2:
			current_speed = retreat_punishment_speed
		
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
	else:
		current_state = "IN_RANGE"
		play_animation(current_state)
		velocity.x = 0
		velocity.z = 0
		
		var actual_cooldown = 2.0
		if health < max_health * 0.3:
			actual_cooldown = 1.2
		
		if attack_cooldown <= 0:
			if not is_telegraphing:
				current_state = "TELEGRAPHING"
				play_animation(current_state)
				is_telegraphing = true
				attack_cooldown = 0.3
				return
			
			perform_simple_attack()
			is_telegraphing = false
			attack_cooldown = actual_cooldown

func perform_simple_attack():
	current_state = "ATTACKING"
	play_animation(current_state, true)  # Force the attack animation
	attack_cooldown = 2.0
	
	# Flash red to show attack
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh and mesh.material_override:
		var original_color = mesh.material_override.albedo_color
		mesh.material_override.albedo_color = Color(1, 0, 0)
		get_tree().create_timer(0.2).timeout.connect(func(): 
			if mesh and mesh.material_override:
				mesh.material_override.albedo_color = original_color
		)
	
	# Deal damage if player has the method
	if player.has_method("take_damage"):
		player.take_damage(damage)
	else:
		push_warning("Player doesn't have take_damage method!")
	
	# Wait for attack animation to finish before returning to idle
	if animation_player and animation_player.has_animation("Attack"):
		var attack_length = animation_player.get_animation("Attack").length
		await get_tree().create_timer(attack_length * 0.8).timeout  # Slightly shorter than full animation
		if current_state == "ATTACKING":  # Make sure we're still in attack state
			current_state = "IN_RANGE"
			play_animation(current_state)

# === DAMAGE AND DEATH SYSTEM ===
func take_damage(amount: float):
	if current_state == "DEAD":
		return
		
	health -= amount
	
	# Flash white when hit
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh and mesh.material_override:
		var original_color = mesh.material_override.albedo_color
		mesh.material_override.albedo_color = Color(1, 1, 1)
		get_tree().create_timer(0.1).timeout.connect(func():
			if mesh and mesh.material_override:
				mesh.material_override.albedo_color = original_color
		)
	
	if health <= 0:
		die()

func die():
	if current_state == "DEAD":
		return
	
	current_state = "DEAD"
	lunge_state = "NONE"
	play_animation(current_state)
	
	# Simple death - fall over
	rotation.z = deg_to_rad(90)
	set_physics_process(false)
	
	drop_biscuit()
	
	# Remove boss after 3 seconds
	await get_tree().create_timer(3.0).timeout
	queue_free()

func drop_biscuit():
	if biscuit_scene:
		var biscuit = biscuit_scene.instantiate()
		get_parent().add_child(biscuit)
		biscuit.global_position = global_position + Vector3(0, 1, 0)
	else:
		push_warning("No biscuit scene assigned to boss!")

# === ANTI-CHEESE DETECTION ===
func detect_player_patterns(delta: float):
	if not player:
		return
	
	var current_player_pos = player.global_position
	var to_player = (current_player_pos - global_position).normalized()
	
	# Retreat detection
	if "velocity" in player:
		var player_velocity = player.velocity
		if player_velocity.length() > 1.0:
			var retreat_dot = player_velocity.normalized().dot(-to_player)
			
			if retreat_dot > 0.6:
				player_retreat_timer += delta
				if player_retreat_timer > 1.5:
					consecutive_retreats += 1
					player_retreat_timer = 0.0
			else:
				player_retreat_timer = 0.0
				if consecutive_retreats > 0:
					consecutive_retreats -= 1
	
	# Circle strafe detection
	var current_angle = atan2(to_player.x, to_player.z)
	var angle_change = abs(current_angle - last_angle_to_player)
	
	if angle_change > PI:
		angle_change = 2 * PI - angle_change
	
	if angle_change > 0.3 and global_position.distance_to(current_player_pos) < 8.0:
		circle_strafe_timer += delta
		if circle_strafe_timer > circle_strafe_detection_time:
			pass  # Circle strafing detected
	else:
		circle_strafe_timer = max(0, circle_strafe_timer - delta * 2)
	
	last_angle_to_player = current_angle
	last_player_position = current_player_pos
