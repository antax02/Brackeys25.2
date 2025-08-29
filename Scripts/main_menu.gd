extends Control

var level_scene: PackedScene = preload("res://Scenes/world.tscn")

func _on_button_play_pressed() -> void:
	get_tree().change_scene_to_packed(level_scene)

func _on_button_quit_pressed() -> void:
	get_tree().quit()

func _on_button_credits_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/credits.tscn")
