extends Node3D
class_name Enemy

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

# === HEALTH SETTINGS ===
@export var max_health = 100 
@export var explosion_force: float = 20

# === BLOOD DECAL SETTINGS ===
@export var blood_decal_count: int = 200
@export var decal_size: float = 5.0
@export var decal_distance: float = 40.0

# === NODE REFERENCES ===
@onready var mesh_instance = $Armature/Skeleton3D/Plane

# === STATE VARIABLES ===
var health
var is_dead = false

func _ready() -> void:
	health = max_health
	load_blood_textures()

func load_blood_textures():
	for i in range(1, 12):
		var texture_path = "res://Assets/Decals/Blood/blood" + str(i) + ".png"
		var texture = load(texture_path)
		if texture:
			blood_textures.append(texture)

func _process(delta: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	pass

func spawn_blood_decals():
	if blood_textures.is_empty():
		return
	
	var space_state = get_world_3d().direct_space_state
	
	for i in range(blood_decal_count):
		var random_direction: Vector3
		
		# Different ray patterns for better surface coverage
		if i < blood_decal_count / 3:
			# Downward rays (floors)
			random_direction = Vector3(
				randf_range(-0.5, 0.5),
				randf_range(-1.0, -0.3),
				randf_range(-0.5, 0.5)
			).normalized()
		elif i < (blood_decal_count * 2) / 3:
			# Horizontal rays (walls)
			random_direction = Vector3(
				randf_range(-1.0, 1.0),
				randf_range(-0.2, 0.2),
				randf_range(-1.0, 1.0)
			).normalized()
		else:
			# Random directions
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

func create_blood_decal(position: Vector3, normal: Vector3):
	var decal = Decal.new()
	get_parent().add_child(decal)
	
	# Set decal properties with size variation
	var size_variation = randf_range(0.8, 1.5)
	decal.global_position = position
	decal.size = Vector3(decal_size * size_variation, decal_size * size_variation, decal_size)
	
	# Random rotation for variety
	var random_rotation = randf_range(0, 2 * PI)
	decal.rotation.z = random_rotation
	
	# Align with surface
	decal.look_at(position + normal, Vector3.UP)
	decal.global_position += normal * 0.01
	
	# Apply random blood texture
	var random_texture = blood_textures[randi() % blood_textures.size()]
	decal.texture_albedo = random_texture
	
	# Decal appearance properties
	decal.albedo_mix = 1.0
	decal.modulate = Color(0.8, 0.1, 0.1, randf_range(0.8, 1.0))
	decal.normal_fade = 0.5

func explode_into_parts():
	mesh_instance.visible = false
	spawn_blood_decals()
	
	var player = get_node("%Player")
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
