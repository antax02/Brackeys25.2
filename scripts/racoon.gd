extends CharacterBody3D
class_name EnemyAI

var part_scenes = [
	preload("res://Scenes/RacoonParts/racoon_bl.tscn"),
	preload("res://Scenes/RacoonParts/racoon_br.tscn"),
	preload("res://Scenes/RacoonParts/racoon_fr.tscn"),
	preload("res://Scenes/RacoonParts/racoon_fl.tscn"),
	preload("res://Scenes/RacoonParts/racoon_tail.tscn"),
	preload("res://Scenes/RacoonParts/racoon_torso.tscn"),
	preload("res://Scenes/RacoonParts/racoon_head.tscn")
]

var blood_textures = []

# Health and explosion settings
@export var max_health = 100 
@export var explosion_force: float = 20

# Blood decal settings
@export var blood_decal_count: int = 200
@export var decal_size: float = 5.0
@export var decal_distance: float = 40.0

# AI behavior settings
@export_group("AI Settings")
@export var movement_speed: float = 3.0
@export var chase_speed: float = 5.0
@export var detection_range: float = 15.0
@export var attack_range: float = 2.0
@export var fov_angle: float = 360.0
@export var patrol_wait_time: float = 3.0
@export var lose_target_time: float = 5.0

# Patrol behavior settings
@export_group("Patrol Settings")
@export var patrol_points: Array[Vector3] = []
@export var patrol_radius: float = 10.0
@export var random_patrol: bool = true

# Node references
@onready var mesh_instance = $Armature/Skeleton3D/Plane
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var vision_raycast: RayCast3D = $VisionRaycast
@onready var attack_timer: Timer = $AttackTimer
@onready var patrol_timer: Timer = $PatrolTimer
@onready var lose_target_timer: Timer = $LoseTargetTimer
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# State variables
var health
var is_dead = false

# AI state variables
enum AIState { PATROL, CHASE, ATTACK, SEARCH, WAIT }
var current_state = AIState.PATROL
var target_player: CharacterBody3D
var last_known_player_position: Vector3
var spawn_position: Vector3
var current_patrol_index: int = 0
var is_waiting: bool = false
var navigation_ready: bool = false
var time_since_lost_target: float = 0.0
var current_animation: String = ""
var nav_mesh_height: float = 0.0

func _ready() -> void:
	health = max_health
	load_blood_textures()
	setup_ai()
	setup_navigation()

func setup_ai():
	spawn_position = global_position
	
	# Configure timers
	attack_timer.wait_time = 1.5
	attack_timer.one_shot = true
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	
	patrol_timer.wait_time = patrol_wait_time
	patrol_timer.one_shot = true
	patrol_timer.timeout.connect(_on_patrol_timer_timeout)
	
	lose_target_timer.wait_time = lose_target_time
	lose_target_timer.one_shot = true
	lose_target_timer.timeout.connect(_on_lose_target_timer_timeout)
	
	# Configure vision raycast
	vision_raycast.enabled = true
	vision_raycast.collision_mask = 1

func setup_navigation():
	# Configure navigation agent
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 0.5
	navigation_agent.path_max_distance = 3.0
	navigation_agent.avoidance_enabled = true
	
	call_deferred("_navigation_setup")

func _navigation_setup():
	await get_tree().physics_frame
	
	# Wait for navigation map to be ready
	var nav_map = navigation_agent.get_navigation_map()
	while NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		await get_tree().process_frame
	
	navigation_ready = true
	
	# Store nav mesh height and set initial position
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, spawn_position)
	nav_mesh_height = closest_point.y
	global_position.y = nav_mesh_height
	
	# Generate patrol points if none are set
	if patrol_points.is_empty():
		generate_patrol_points()
	
	set_next_patrol_target()

func generate_patrol_points():
	var point_count = 4
	for i in point_count:
		var angle = (i * 2 * PI) / point_count
		var offset = Vector3(
			cos(angle) * patrol_radius,
			0,
			sin(angle) * patrol_radius
		)
		patrol_points.append(spawn_position + offset)

func _physics_process(delta: float) -> void:
	if is_dead or not navigation_ready:
		return
	
	update_ai_state(delta)
	handle_movement(delta)

func update_ai_state(delta: float):
	var player = find_player()
	var can_see_player = false
	
	if player:
		can_see_player = check_line_of_sight(player)
		if can_see_player:
			target_player = player
			last_known_player_position = player.global_position
			time_since_lost_target = 0.0
			lose_target_timer.stop()
		else:
			if target_player:
				time_since_lost_target += delta
	
	# State machine
	match current_state:
		AIState.PATROL:
			handle_patrol_state(can_see_player)
		AIState.CHASE:
			handle_chase_state(can_see_player, delta)
		AIState.ATTACK:
			handle_attack_state(can_see_player)
		AIState.SEARCH:
			handle_search_state(can_see_player)
		AIState.WAIT:
			handle_wait_state(can_see_player)

func handle_patrol_state(can_see_player: bool):
	if can_see_player:
		change_state(AIState.CHASE)
		return
	
	if navigation_agent.is_navigation_finished():
		if not is_waiting:
			is_waiting = true
			patrol_timer.start()

func handle_chase_state(can_see_player: bool, delta: float):
	if can_see_player and target_player:
		navigation_agent.target_position = target_player.global_position
		last_known_player_position = target_player.global_position
		
		if global_position.distance_to(target_player.global_position) <= attack_range:
			change_state(AIState.ATTACK)
			return
	else:
		if time_since_lost_target >= lose_target_time:
			change_state(AIState.SEARCH)

func handle_attack_state(can_see_player: bool):
	if not can_see_player or not target_player:
		change_state(AIState.CHASE)
		return
		
	var distance_to_player = global_position.distance_to(target_player.global_position)
	if distance_to_player > attack_range:
		change_state(AIState.CHASE)
		return
	
	# Keep facing the player while attacking
	if target_player:
		var to_player = (target_player.global_position - global_position)
		to_player.y = 0
		if to_player.length() > 0.1:
			to_player = to_player.normalized()
			var target_rotation = atan2(-to_player.x, -to_player.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, get_physics_process_delta_time() * 3.0)
	
	if attack_timer.is_stopped():
		perform_attack()
		attack_timer.start()

func handle_search_state(can_see_player: bool):
	if can_see_player:
		change_state(AIState.CHASE)
		return
	
	if navigation_agent.is_navigation_finished():
		if global_position.distance_to(last_known_player_position) < 2.0:
			change_state(AIState.WAIT)

func handle_wait_state(can_see_player: bool):
	if can_see_player:
		change_state(AIState.CHASE)
		return
	
	if not patrol_timer.time_left > 0:
		change_state(AIState.PATROL)

func change_state(new_state: AIState):
	current_state = new_state
	
	match new_state:
		AIState.PATROL:
			set_next_patrol_target()
			is_waiting = false
			target_player = null
		AIState.CHASE:
			if target_player:
				navigation_agent.target_position = target_player.global_position
		AIState.ATTACK:
			navigation_agent.target_position = global_position
		AIState.SEARCH:
			navigation_agent.target_position = last_known_player_position
		AIState.WAIT:
			patrol_timer.start()
			navigation_agent.target_position = global_position

func handle_movement(delta: float):
	var horizontal_velocity = Vector3.ZERO
	var should_rotate = false
	
	match current_state:
		AIState.ATTACK:
			horizontal_velocity = Vector3.ZERO
			play_animation("Attack")
		AIState.WAIT:
			horizontal_velocity = Vector3.ZERO
			play_animation("Walk")
		_:  # PATROL, CHASE, SEARCH states
			if navigation_agent.is_navigation_finished():
				horizontal_velocity = Vector3.ZERO
				play_animation("Walk")
			else:
				var next_path_position = navigation_agent.get_next_path_position()
				var direction = (next_path_position - global_position).normalized()
				
				direction.y = 0
				direction = direction.normalized()
				
				var speed = movement_speed
				if current_state == AIState.CHASE:
					speed = chase_speed
					play_animation("Run")
				else:
					play_animation("Walk")
				
				horizontal_velocity = direction * speed
				should_rotate = true
	
	# Apply movement
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	velocity.y = 0
	
	# Handle rotation
	if should_rotate and horizontal_velocity.length() > 0.1:
		var look_direction = horizontal_velocity.normalized()
		var target_rotation = atan2(-look_direction.x, -look_direction.z)
		var current_rotation = rotation.y
		rotation.y = lerp_angle(current_rotation, target_rotation, delta * 5.0)
	
	move_and_slide()
	global_position.y = nav_mesh_height

func play_animation(anim_name: String):
	if current_animation == anim_name:
		return
		
	if animation_player and animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		current_animation = anim_name

func find_player() -> CharacterBody3D:
	# Try to find player by unique name first
	var player = get_node_or_null("%Player")
	if player:
		return player
	
	# Fallback: search in scene
	player = get_tree().get_first_node_in_group("player")
	if player:
		return player
	
	# Last resort: find by class name
	var nodes = get_tree().get_nodes_in_group("player")
	if nodes.size() > 0:
		return nodes[0]
	
	return null

func check_line_of_sight(player: CharacterBody3D) -> bool:
	if not player:
		return false
	
	var distance = global_position.distance_to(player.global_position)
	
	if distance > detection_range:
		return false
	
	# FOV check (skip for 360-degree detection)
	if fov_angle < 360.0:
		var to_player = player.global_position - global_position
		to_player.y = 0
		var forward = -transform.basis.z
		forward.y = 0
		
		if to_player.length() < 0.1 or forward.length() < 0.1:
			return false
		
		var angle = rad_to_deg(forward.angle_to(to_player.normalized()))
		
		if angle > fov_angle / 2:
			return false
	
	# Raycast check
	var eye_position = global_position + Vector3.UP * 1.5
	var player_center = player.global_position + Vector3.UP * 1.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(eye_position, player_center)
	query.collision_mask = 0b00000011
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		if collider == player:
			return true
		else:
			return false
	else:
		return true

func perform_attack():
	if not target_player:
		return
	
	print("Enemy attacking player!")
	# Implement attack mechanics here
	# Example: target_player.take_damage(10)

func set_next_patrol_target():
	if patrol_points.is_empty():
		return
	
	if random_patrol:
		var available_indices = []
		for i in range(patrol_points.size()):
			if i != current_patrol_index:
				available_indices.append(i)
		
		if available_indices.size() > 0:
			current_patrol_index = available_indices[randi() % available_indices.size()]
	else:
		current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
	
	navigation_agent.target_position = patrol_points[current_patrol_index]

# Timer callbacks
func _on_attack_timer_timeout():
	pass

func _on_patrol_timer_timeout():
	is_waiting = false
	if current_state == AIState.WAIT:
		change_state(AIState.PATROL)
	elif current_state == AIState.PATROL:
		set_next_patrol_target()

func _on_lose_target_timer_timeout():
	target_player = null
	change_state(AIState.PATROL)

# Your existing functions (kept unchanged)
func load_blood_textures():
	for i in range(1, 12):
		var texture_path = "res://Assets/Decals/Blood/blood" + str(i) + ".png"
		var texture = load(texture_path)
		if texture:
			blood_textures.append(texture)

func spawn_blood_decals():
	if blood_textures.is_empty():
		return
	
	var space_state = get_world_3d().direct_space_state
	
	for i in range(blood_decal_count):
		var random_direction: Vector3
		
		if i < blood_decal_count / 3:
			random_direction = Vector3(
				randf_range(-0.5, 0.5),
				randf_range(-1.0, -0.3),
				randf_range(-0.5, 0.5)
			).normalized()
		elif i < (blood_decal_count * 2) / 3:
			random_direction = Vector3(
				randf_range(-1.0, 1.0),
				randf_range(-0.2, 0.2),
				randf_range(-1.0, 1.0)
			).normalized()
		else:
			random_direction = Vector3(
				randf_range(-1.0, 1.0),
				randf_range(-0.5, 0.5),
				randf_range(-1.0, 1.0)
			).normalized()
		
		var ray_start = global_position
		var ray_end = global_position + random_direction * decal_distance
		
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		
		if result:
			create_blood_decal(result.position, result.normal)

func create_blood_decal(pos: Vector3, normal: Vector3):
	var decal = Decal.new()
	get_parent().add_child(decal)
	
	var size_variation = randf_range(0.8, 1.5)
	decal.global_position = pos
	decal.size = Vector3(decal_size * size_variation, decal_size * size_variation, decal_size)
	
	var random_rotation = randf_range(0, 2 * PI)
	decal.rotation.z = random_rotation
	
	# Safe look_at - handle edge cases
	if normal.length() > 0.1:
		var up_vector = Vector3.UP
		if abs(normal.dot(Vector3.UP)) > 0.99:
			up_vector = Vector3.RIGHT
		
		decal.look_at(pos + normal, up_vector)
	
	decal.global_position += normal * 0.01
	
	var random_texture = blood_textures[randi() % blood_textures.size()]
	decal.texture_albedo = random_texture
	
	decal.albedo_mix = 1.0
	decal.modulate = Color(0.8, 0.1, 0.1, randf_range(0.8, 1.0))
	decal.normal_fade = 0.5

func explode_into_parts():
	mesh_instance.visible = false
	spawn_blood_decals()
	
	var player = get_node_or_null("%Player")
	if not player:
		explode_randomly()
		return
	
	var player_position = player.global_position
	
	for part_scene in part_scenes:
		var part = part_scene.instantiate()
		get_parent().add_child(part)
		part.global_position = global_position
		
		var away_from_player = global_position - player_position
		away_from_player.y = 0
		away_from_player = away_from_player.normalized()
		
		var random_horizontal_angle = randf_range(-35.0, 35.0)
		var horizontal_rotation = deg_to_rad(random_horizontal_angle)
		
		var final_direction = away_from_player.rotated(Vector3.UP, horizontal_rotation)
		
		final_direction.y = randf_range(0.1, 0.4)
		final_direction = final_direction.normalized()
		
		if part is RigidBody3D:
			part.apply_impulse(final_direction * explosion_force, Vector3.ZERO)

func explode_randomly():
	spawn_blood_decals()
	
	for part_scene in part_scenes:
		var part = part_scene.instantiate()
		get_parent().add_child(part)
		part.global_position = global_position
		
		var random_direction = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.2, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		if part is RigidBody3D:
			part.apply_impulse(random_direction * explosion_force, Vector3.ZERO)

func take_damage(damage: int):
	health -= damage
	
	if health <= 0:
		die()

func die():
	if not is_dead:
		explode_into_parts()
		queue_free()
	is_dead = true
