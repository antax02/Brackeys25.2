extends Node3D


@onready var hint = $Label
var can_enter = false
var boss_scene: PackedScene = preload("res://Scenes/boss_test.tscn")


func _on_area_3d_area_entered(area: Area3D) -> void:
	hint.text = "Press F to enter"
	can_enter = true

func _on_area_3d_area_exited(area: Area3D) -> void:
	hint.text = ""
	can_enter = false

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("enter") and can_enter:
		get_tree().change_scene_to_packed(boss_scene)
