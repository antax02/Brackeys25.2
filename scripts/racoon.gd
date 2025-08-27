extends Node3D

class_name Enemy

@export var max_health = 100 

# === STATE VARIABLES ===
var health

func _ready() -> void:
	health = max_health


func _process(delta: float) -> void:
	pass
	
	
func _physics_process(delta: float) -> void:
	pass
	
	
func take_damage(damage: int):
	health -= damage
	
	if health <= 0:
		die()
	
	
func die():
	queue_free()
