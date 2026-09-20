extends SceneTree

var errors: Array[String] = []
var strikes: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func on_strike() -> void:
	strikes += 1

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var level: Node = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await frames(12)

	var player: CharacterBody3D = level.get_node("Actors/Player")
	var body: AnimatedSprite3D = player.get_node("Visual/Body")
	var rig: Node3D = level.get_node("CameraRig")
	var arm: SpringArm3D = rig.get_node("SpringArm3D")
	var camera: Camera3D = arm.get_node("Camera3D")

	# 1. Camera and sprites
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "projection not perspective")
	check(camera.current, "camera not current")
	check(camera.global_position.z > player.global_position.z, "camera not behind player")
	check(absf((camera.global_position.z - player.global_position.z) - float(rig.distance) * cos(arm.rotation.x)) < 0.05, "camera z offset not distance*cos(pitch)")
	check(body.animation == "idle_back", "body not idle_back")
	check(body.billboard == 2, "hero billboard off")
	var innkeeper: AnimatedSprite3D = level.get_node("Actors/Innkeeper/Body")
	var watchman: AnimatedSprite3D = level.get_node("Actors/Watchman/Body")
	check(innkeeper.billboard == 2, "innkeeper billboard off")
	check(watchman.billboard == 2, "watchman billboard off")

	var frames_data: SpriteFrames = body.sprite_frames
	var clips: Array[Array] = [
		["idle_side", 4, true], ["idle_back", 4, true], ["idle_front", 4, true],
		["walk_side", 8, true], ["walk_back", 8, true], ["walk_front", 8, true],
		["attack_side", 4, false], ["attack_back", 4, false], ["attack_front", 4, false],
	]
	for c in clips:
		var name: String = c[0]
		var count: int = c[1]
		var loop: bool = c[2]
		check(frames_data.has_animation(name), "missing clip " + name)
		check(frames_data.get_frame_count(name) == count, "bad count " + name)
		check(frames_data.get_animation_loop(name) == loop, "bad loop " + name)
		var tex: AtlasTexture = frames_data.get_frame_texture(name, 0)
		check(tex != null and tex.atlas != null, "no texture " + name)
	check(frames_data.get_animation_speed("walk_back") == 15.0, "walk speed not 15")
	check(int(frames_data.get_meta("baseline_offset_pixels")) == 182, "baseline offset not 182")

	# 2. Movement
	rig.rotate_view(Vector2(-PI / 2.0 / float(rig.mouse_sensitivity), 0.0))
	await frames(3)
	var start_pos: Vector3 = player.global_position
	player.set_move_input(Vector2.UP)
	await frames(30)
	var delta: Vector3 = player.global_position - start_pos
	check(delta.x < -1.0, "did not move left")
	check(absf(delta.z) < 0.35, "strayed sideways")
	check(body.animation == "walk_back", "not walk_back")
	player.stop_input()
	level.reset_lesson()
	await frames(12)

	# 3. Facing
	var facings: Array[Array] = [
		[Vector3.RIGHT, "idle_side", false],
		[Vector3.LEFT, "idle_side", true],
		[Vector3.BACK, "idle_front", false],
		[Vector3.FORWARD, "idle_back", false],
	]
	for f in facings:
		player.facing_direction = f[0]
		await frames(2)
		var anim: String = body.animation
		var flip: bool = body.flip_h
		check(anim == f[1], "facing anim " + anim)
		check(flip == f[2], "facing flip " + anim)

	# 4. Attack
	player.strike_requested.connect(on_strike)
	player.request_attack()
	await frames(4)
	var saved_time: float = float(player._attack_time)
	var old_frame: int = body.frame
	var old_progress: float = body.frame_progress
	rig.rotate_view(Vector2(PI / float(rig.mouse_sensitivity), 0.0))
	await frames(2)
	check(body.animation == "attack_front", "not attack_front")
	var new_time: float = float(player._attack_time)
	var new_frame: int = body.frame
	var new_progress: float = body.frame_progress
	check(new_time > saved_time, "attack time not advancing")
	check(float(new_frame) + new_progress >= float(old_frame) + old_progress, "frame regressed")
	await frames(30)
	check(strikes == 1, "strikes != 1")

	# 5. Spring arm
	level.reset_lesson()
	await frames(12)
	player.global_position = Vector3(-8.0, 0.1, -3.8)
	rig.rotate_view(Vector2(PI / float(rig.mouse_sensitivity), 0.0))
	rig.snap_to_target()
	await frames(10)
	var house_shape: CollisionShape3D = level.get_node("Environment/Buildings/House/Collision/MainBodyShape")
	var wall_front: float = house_shape.global_position.z + (house_shape.shape as BoxShape3D).size.z / 2.0
	print("camera=", camera.global_position, " arm_hit=", arm.get_hit_length(), " wall_front=", wall_front)
	check(arm.get_hit_length() < float(rig.distance) - 0.1, "arm not shortened near wall")
	check(camera.global_position.z > wall_front + 0.05, "camera inside wall")
	var sphere := SphereShape3D.new()
	sphere.radius = 0.08
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	query.collision_mask = 1
	check(player.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "camera intersects collider")
	level.reset_lesson()
	await frames(12)
	check(absf(arm.get_hit_length() - rig.distance) < 0.05, "arm not at rest length")

	# 6. Pitch limits (custom exported values must work)
	rig.pitch_min_degrees = -25.0
	rig.pitch_max_degrees = 5.0
	rig.rotate_view(Vector2(0.0, 10000.0))
	check(absf(rad_to_deg(arm.rotation.x) + 25.0) < 0.5, "pitch min not clamped")
	rig.rotate_view(Vector2(0.0, -10000.0))
	check(absf(rad_to_deg(arm.rotation.x) - 5.0) < 0.5, "pitch max not clamped")
	# restore defaults
	rig.pitch_min_degrees = -50.0
	rig.pitch_max_degrees = 12.0
	level.reset_lesson()

	level.queue_free()
	await frames(2)
	if errors.is_empty():
		print("ASHBOUND_THIRD_PERSON_OK")
		quit(0)
	else:
		for e in errors:
			push_error(e)
		quit(1)
