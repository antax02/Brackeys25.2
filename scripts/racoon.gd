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

@export var max_health = 100 
@export var explosion_force: float = 10.0

@onready var mesh_instance = $MeshInstance3D

var health
var is_dead = false

func _ready() -> void:
	health = max_health


func _process(delta: float) -> void:
	pass
	
	
func _physics_process(delta: float) -> void:
	pass
	
func explode_into_parts():
	mesh_instance.visible = false
	
	var player = get_tree().get_first_node_in_group("Player")
	if not player:

		_explode_randomly()
		return
	
	var player_position = player.global_position
	
	for part_scene in part_scenes:
		var part = part_scene.instantiate()
		get_parent().add_child(part)
		part.global_position = global_position
		
		var away_from_player = (global_position - player_position).normalized()
		
		var random_angle_degrees = randf_range(-5.0, 5.0)  # Adjust this for more/less randomness
		var random_rotation = deg_to_rad(random_angle_degrees)
		
		var perpendicular = Vector3.UP.cross(away_from_player).normalized()
		if perpendicular.length() < 0.1:  # Handle edge case where away_from_player is parallel to UP
			perpendicular = Vector3.RIGHT.cross(away_from_player).normalized()
		
		var final_direction = away_from_player.rotated(perpendicular, random_rotation)
		
		final_direction.y += randf_range(0.1, 0.3)
		final_direction = final_direction.normalized()
		
		if part is RigidBody3D:
			part.apply_impulse(final_direction * explosion_force)

func _explode_randomly():
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
			part.apply_impulse(random_direction * explosion_force)
	
func take_damage(damage: int):
	health -= damage
	
	if health <= 0:
		die()
	
	
func die():
	if not is_dead:
		explode_into_parts()
		queue_free()
	is_dead = true
