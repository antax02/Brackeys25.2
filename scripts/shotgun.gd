extends Node3D

# === WEAPON STATS ===
@export var damage_per_pellet = 20
@export var pellet_count = 8
@export var fire_rate = 0.3
@export var max_range = 50.0
@export var spread_angle = 9.0
@export var max_ammo = 2
@export var reload_time = 0.5

# === VISUAL EFFECTS ===
@export var muzzle_flash_intensity = 5.0
@export var muzzle_flash_duration = 0.083
@export var muzzle_flash_color = Color.LIGHT_GOLDENROD

@export var recoil_strength = 0.15
@export var recoil_duration = 0.10
@export var reload_drop_distance = 1.5

@export var bullet_hole_texture: Texture2D
@export var decal_size = Vector3(0.3, 0.3, 0.5)
@export var max_decals = 50

# === AIM DOWN SIGHTS ===
@export var ads_fov = 60.0
@export var ads_transition_speed = 8.0
@export var ads_spread_reduction = 0.3
@export var ads_distance_from_camera = 0.5
@export var ads_position_offset = Vector3(0.0, -0.03, -0.15)
@export var can_run_while_ads = false

# === AUDIO ===
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_click_sound: AudioStream
@export var shell_drop_sounds: Array[AudioStream] = []
@export var sound_volume = 0.0

# === NODE REFERENCES ===
@onready var muzzle_point = $MuzzlePoint
@onready var muzzle_flash_light = $MuzzlePoint/MuzzleFlash
@onready var gun_mesh = $"Super Shotgun"
@onready var audio_player = $AudioStreamPlayer3D
@onready var click_audio_player = $ClickAudioStreamPlayer3D

# === STATE VARIABLES ===
var can_fire = true
var fire_timer = 0.0
var current_ammo = 2
var is_reloading = false
var camera: Camera3D
var original_gun_position: Vector3
var original_gun_rotation: Vector3
var is_aiming = false
var original_fov = 75.0
var ads_transition_progress = 0.0
var decals = []
var last_empty_click_time = 0.0
var empty_click_cooldown = 0.3

func _ready():
	# Setup muzzle flash light
	muzzle_flash_light.light_energy = 0.0
	muzzle_flash_light.omni_range = 15.0
	muzzle_flash_light.light_color = muzzle_flash_color
	
	# Store original gun transform
	if gun_mesh:
		original_gun_position = gun_mesh.position
		original_gun_rotation = gun_mesh.rotation
	
	# Get camera reference
	var camera_node = get_node("%Camera3D")
	if camera_node:
		camera = camera_node
		original_fov = camera.fov
	
	# Setup audio
	if audio_player:
		audio_player.volume_db = sound_volume
	if click_audio_player:
		click_audio_player.volume_db = sound_volume

func _process(delta):
	# Handle fire rate cooldown
	if not can_fire and not is_reloading:
		fire_timer += delta
		if fire_timer >= fire_rate:
			can_fire = true
			fire_timer = 0.0
	
	# Handle ADS toggle
	var aim_input = Input.is_action_pressed("aim")
	if aim_input != is_aiming and not is_reloading:
		toggle_ads(aim_input)
	
	# Update gun position during ADS transition
	if ads_transition_progress > 0.0:
		update_ads_position()

func _input(event):
	if event.is_action_pressed("fire"):
		if can_fire and current_ammo > 0 and not is_reloading:
			fire()
		elif current_ammo <= 0 and not is_reloading:
			# Empty click with cooldown to prevent spam
			var current_time = Time.get_ticks_msec() / 1000.0
			if current_time - last_empty_click_time > empty_click_cooldown:
				play_click_sound(empty_click_sound)
				last_empty_click_time = current_time
	
	if event.is_action_pressed("reload") and current_ammo < max_ammo and not is_reloading:
		reload()

# === FIRING SYSTEM ===
func fire():
	if not can_fire or current_ammo <= 0 or is_reloading:
		return
		
	can_fire = false
	current_ammo -= 1
	
	play_sound(fire_sound)
	
	var hit_results = fire_pellets()
	trigger_muzzle_flash()
	trigger_recoil()
	
	# Delayed shell casing drop
	get_tree().create_timer(0.2).timeout.connect(drop_shell_casing)
	
	for result in hit_results:
		if result.has("collider"):
			handle_hit(result)

func fire_pellets() -> Array:
	var results = []
	var space_state = get_world_3d().direct_space_state
	var camera_node = get_node("%Camera3D")
	if not camera_node:
		return results
	
	for i in pellet_count:
		# Calculate spread (reduced when aiming)
		var current_spread = spread_angle
		if is_aiming:
			current_spread *= ads_spread_reduction
		
		var spread_x = randf_range(-current_spread, current_spread)
		var spread_y = randf_range(-current_spread, current_spread)
		var spread_rad_x = deg_to_rad(spread_x)
		var spread_rad_y = deg_to_rad(spread_y)
		
		# Raycast with spread
		var from = camera_node.global_position
		var forward = -camera_node.global_transform.basis.z
		var right = camera_node.global_transform.basis.x
		var up = camera_node.global_transform.basis.y
		var spread_direction = (forward + right * sin(spread_rad_x) + up * sin(spread_rad_y)).normalized()
		var to = from + spread_direction * max_range
		
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = [get_parent()]
		
		var result = space_state.intersect_ray(query)
		if result:
			results.append(result)
	
	return results

# === VISUAL EFFECTS ===
func trigger_muzzle_flash():
	muzzle_flash_light.light_energy = muzzle_flash_intensity
	var tween = create_tween()
	tween.tween_property(muzzle_flash_light, "light_energy", 0.0, muzzle_flash_duration)

func trigger_recoil():
	if not gun_mesh:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Position recoil (only when not aiming)
	if not is_aiming:
		var recoil_offset = Vector3(0, recoil_strength * 0.5, recoil_strength)
		tween.tween_property(gun_mesh, "position", original_gun_position + recoil_offset, recoil_duration * 0.3)
		tween.tween_property(gun_mesh, "position", original_gun_position, recoil_duration * 0.7).set_delay(recoil_duration * 0.3)
	
	# Rotation recoil
	var current_rotation = gun_mesh.rotation
	var recoil_rotation = Vector3(deg_to_rad(-8), 0, 0)
	tween.tween_property(gun_mesh, "rotation", current_rotation + recoil_rotation, recoil_duration * 0.3)
	tween.tween_property(gun_mesh, "rotation", current_rotation, recoil_duration * 0.7).set_delay(recoil_duration * 0.3)

func handle_hit(hit_result: Dictionary):
	var hit_point = hit_result.get("position", Vector3.ZERO)
	var hit_normal = hit_result.get("normal", Vector3.UP)
	var collider = hit_result.get("collider")
	
	if collider and collider.has_method("take_damage"):
		collider.take_damage(damage_per_pellet)
	
	create_hit_effect(hit_point, hit_normal)

func create_hit_effect(hit_position: Vector3, normal: Vector3):
	if not bullet_hole_texture:
		return
	
	var decal = Decal.new()
	decal.texture_albedo = bullet_hole_texture
	decal.size = decal_size
	
	# Position decal slightly offset from surface
	var decal_position = hit_position + normal * 0.01
	
	# Align decal with surface normal
	var decal_up = normal
	var decal_forward = Vector3.FORWARD
	
	# Handle edge case where normal is parallel to forward
	if abs(normal.dot(Vector3.FORWARD)) > 0.99:
		decal_forward = Vector3.RIGHT
	
	# Create orthogonal basis
	var decal_right = decal_up.cross(decal_forward).normalized()
	decal_forward = decal_right.cross(decal_up).normalized()
	var decal_basis = Basis(decal_right, decal_up, decal_forward)
	decal.transform = Transform3D(decal_basis, decal_position)
	
	get_tree().current_scene.add_child(decal)
	decals.append(decal)
	
	# Manage decal limit
	if decals.size() > max_decals:
		var old_decal = decals.pop_front()
		if is_instance_valid(old_decal):
			old_decal.queue_free()

# === RELOAD SYSTEM ===
func reload():
	if is_reloading or current_ammo >= max_ammo:
		return
	
	if is_aiming:
		toggle_ads(false)
	
	is_reloading = true
	can_fire = false
	
	play_sound(reload_sound)
	
	if not gun_mesh:
		await get_tree().create_timer(reload_time).timeout
		current_ammo = max_ammo
		is_reloading = false
		can_fire = true
		return
	
	# Animate gun dropping down
	var tween = create_tween()
	tween.set_parallel(true)
	
	var reload_position = original_gun_position + Vector3(0, -reload_drop_distance, 0)
	tween.tween_property(gun_mesh, "position", reload_position, reload_time * 0.4)
	
	var reload_rotation = Vector3(deg_to_rad(15), 0, 0)
	tween.tween_property(gun_mesh, "rotation", original_gun_rotation + reload_rotation, reload_time * 0.4)
	
	await tween.finished
	await get_tree().create_timer(reload_time * 0.2).timeout
	
	# Animate gun returning to position
	var return_tween = create_tween()
	return_tween.set_parallel(true)
	return_tween.tween_property(gun_mesh, "position", original_gun_position, reload_time * 0.4)
	return_tween.tween_property(gun_mesh, "rotation", original_gun_rotation, reload_time * 0.4)
	
	await return_tween.finished
	
	current_ammo = max_ammo
	is_reloading = false
	can_fire = true

# === AIM DOWN SIGHTS ===
func update_ads_position():
	if not camera or not gun_mesh:
		return
	
	var camera_forward = -camera.global_transform.basis.z
	var camera_right = camera.global_transform.basis.x
	var camera_up = camera.global_transform.basis.y
	
	var base_ads_position = camera.global_position + camera_forward * ads_distance_from_camera
	var offset_ads_position = base_ads_position + (
		camera_right * ads_position_offset.x + 
		camera_up * ads_position_offset.y + 
		camera_forward * ads_position_offset.z
	)
	
	var hip_world_position = global_transform * original_gun_position
	var target_position = hip_world_position.lerp(offset_ads_position, ads_transition_progress)
	
	gun_mesh.global_position = target_position

func toggle_ads(aiming: bool):
	if not camera or not gun_mesh:
		return
	
	is_aiming = aiming
	var tween = create_tween()
	tween.set_parallel(true)
	
	if is_aiming:
		tween.tween_property(camera, "fov", ads_fov, 1.0 / ads_transition_speed)
		tween.tween_property(self, "ads_transition_progress", 1.0, 1.0 / ads_transition_speed)
	else:
		tween.tween_property(camera, "fov", original_fov, 1.0 / ads_transition_speed)
		tween.tween_property(self, "ads_transition_progress", 0.0, 1.0 / ads_transition_speed)
		
		# Reset gun position when ADS transition completes
		tween.tween_callback(func(): 
			if ads_transition_progress <= 0.0:
				gun_mesh.position = original_gun_position
				gun_mesh.rotation = original_gun_rotation
		).set_delay(1.0 / ads_transition_speed)

# === AUDIO SYSTEM ===
func play_sound(sound: AudioStream):
	if sound and audio_player:
		audio_player.stop()
		audio_player.stream = sound
		audio_player.play()

func play_click_sound(sound: AudioStream):
	if sound and click_audio_player:
		click_audio_player.stop()
		click_audio_player.stream = sound
		click_audio_player.play()

func drop_shell_casing():
	if shell_drop_sounds.size() > 0:
		var random_shell_sound = shell_drop_sounds[randi() % shell_drop_sounds.size()]
		
		# Temporary audio player for shell sounds
		var shell_audio = AudioStreamPlayer3D.new()
		add_child(shell_audio)
		shell_audio.stream = random_shell_sound
		shell_audio.volume_db = sound_volume - 10
		shell_audio.play()
		
		shell_audio.finished.connect(func(): shell_audio.queue_free())

# === PUBLIC API ===
func get_ammo_count() -> int:
	return current_ammo

func get_max_ammo() -> int:
	return max_ammo

func is_empty() -> bool:
	return current_ammo <= 0

func force_reload():
	reload()

func can_player_run() -> bool:
	if is_aiming:
		return can_run_while_ads
	return true
