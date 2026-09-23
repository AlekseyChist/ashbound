extends Node
## Render-space regression: steady locomotion must not oscillate between physics ticks.
const Route := preload("res://scenes/world/forest_route.tscn")
var route: Node3D
var failures: Array[String] = []
var results: Array[Dictionary] = []
var baseline := false
var capture := false
var groups := 0

func _ready() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	capture = "--capture" in OS.get_cmdline_user_args()
	process_priority = 1000
	Engine.max_fps = 120
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_tree().create_timer(180).timeout.connect(func():
		push_error("SIDE_RUN_TIMEOUT")
		get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	route = Route.instantiate()
	add_child(route)
	await get_tree().create_timer(0.5).timeout
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		await _measure(direction, false)
	await _measure(Vector2.RIGHT, true)
	await _measure(Vector2.LEFT, false, false)
	await _measure(Vector2(1, -1).normalized(), false)
	await _measure(Vector2.RIGHT, false, true, 90.0)
	var visual: Node3D = route.player.get_node("Visual")
	_check(visual.set_appearance_frames(load("res://assets/characters/courtyard/traveler_backpack_frames.tres")), "backpack appearance accepted")
	await _measure(Vector2.LEFT, false)
	_check(visual.set_appearance_frames(load("res://assets/characters/courtyard/traveler_frames.tres")), "bare appearance restored")
	await _boundaries()
	var output := {"baseline": baseline, "samples": results, "failures": failures, "platform": OS.get_name()}
	var file := FileAccess.open("user://side-run-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	if failures.is_empty():
		print("ASHBOUND_SIDE_RUN_OK groups=%d" % groups)
	else:
		for failure in failures:
			push_error("SIDE_RUN_FAIL " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _measure(direction: Vector2, frozen: bool, running: bool = true, yaw: float = 0.0) -> void:
	route.reset_route()
	route.player.position = Vector3(0, 0.2, -70)
	# Keep the diagonal on the 16m clear road. From x=0 it runs into the
	# trees at x>8: SpringArm correctly retracts there, invalidating a steady-view test.
	if absf(direction.x) > 0.1 and absf(direction.y) > 0.1:
		route.player.position.x = -6.0
	route.camera_rig.snap_to_target()
	route.camera_rig.rotate_view(Vector2(-deg_to_rad(yaw) / route.camera_rig.touch_sensitivity, 0), true)
	route.player.set_move_input(direction)
	route.player.set_run_input(running)
	(route.player.get_node("Visual/Body") as AnimatedSprite3D).play()
	await get_tree().create_timer(1.2).timeout
	var visual: Node3D = route.player.get_node("Visual")
	var body: AnimatedSprite3D = visual.get_node("Body")
	if frozen:
		body.pause()
	var points: Array[Vector2] = []
	var samples: Array[Dictionary] = []
	var min_arm_length: float = route.camera_rig.distance
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 1600000:
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		var camera: Camera3D = route.camera_rig.get_camera()
		var point := camera.unproject_position(visual.global_position)
		min_arm_length = minf(min_arm_length, route.camera_rig.get_node("SpringArm3D").get_hit_length())
		points.append(point)
		samples.append({"us": Time.get_ticks_usec(), "x": point.x, "y": point.y,
			"physics": Engine.get_physics_frames(), "pose": body.frame, "view": String(body.animation)})
		if capture and direction == Vector2.RIGHT and not frozen and points.size() <= 24:
			get_viewport().get_texture().get_image().save_png("user://side-run-%03d.png" % points.size())
	var steps: Array[float] = []
	for i in range(1, points.size()):
		steps.append(points[i].distance_to(points[i - 1]))
	steps.sort()
	var p95: float = steps[int(steps.size() * 0.95)]
	var label := str(direction) + (" run" if running else " walk") + (" frozen" if frozen else " animated") + " yaw=" + str(yaw)
	results.append({"case": label, "count": points.size(), "p95_screen_step_px": p95, "min_arm_length": min_arm_length, "trace": samples})
	print("SIDE_RUN_CASE %s samples=%d p95=%.3f" % [label, points.size(), p95])
	if not baseline and p95 > 1.0:
		failures.append(label + " steady screen anchor jitter %.3fpx" % p95)
	if points.size() < 130:
		failures.append(label + " insufficient render samples to test >60Hz")
	_check(absf(Vector2(route.player.velocity.x, route.player.velocity.z).length() - (6.4 if running else 4.2)) < 0.05, label + " physical speed preserved")
	_check(min_arm_length > route.camera_rig.distance - 0.01, label + " unobstructed camera measurement")
	groups += 1
	route.player.stop_input()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _boundaries() -> void:
	var visual: Node3D = route.player.get_node("Visual")
	var body: AnimatedSprite3D = visual.get_node("Body")
	# Resets must never smear from the old position, even without a physics tick.
	route.player.set_physics_process(false)
	route.player.position = Vector3(35, 3.1, -340)
	route.reset_route()
	await _settle()
	_check(visual.global_position.distance_to(route.player.global_position) < 0.0001, "reset presentation immediately at spawn")
	_check((body.material_override as ShaderMaterial).get_shader_parameter("foot_world").distance_to(visual.global_position) < 0.0001, "depth follows displayed foot")
	_check(route.player.get_node("GroundShadow").global_position.distance_to(visual.global_position + Vector3(0, 0.008, 0)) < 0.0001, "ground shadow aligned")
	groups += 1

	# A camera-only turn and appearance/pocket changes never rotate the capsule.
	var actor_transform: Transform3D = route.player.global_transform
	route.camera_rig.rotate_view(Vector2(240, 45), true)
	await _settle()
	_check(route.player.global_transform.is_equal_approx(actor_transform), "camera does not change physics body")
	_check(visual.begin_inventory_access(), "pocket still starts")
	await _settle()
	_check(not body.visible and visual.get_node("PocketPose").visible, "pocket replaces body")
	visual.end_inventory_access()
	_check(body.visible, "body returns after pocket")
	route.player.set_physics_process(true)
	groups += 1

	# Fresh motion after focus loss/pause and an attack still obey the controller.
	route.reset_route()
	route.player.set_move_input(Vector2.RIGHT)
	route.player.set_run_input(true)
	await get_tree().create_timer(0.4).timeout
	route.player.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await get_tree().create_timer(0.15).timeout
	_check(route.player.velocity.length() < 0.2 and route.player._touch_move == Vector2.ZERO, "focus loss stops motion")
	route.player.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	route.player.set_move_input(Vector2.LEFT)
	route.player.set_run_input(true)
	await get_tree().create_timer(0.3).timeout
	route.player.request_attack()
	_check(route.player.is_attacking() and not route.player.is_running(), "attack still suppresses run")
	route.player.stop_input()
	get_tree().paused = true
	await get_tree().create_timer(0.1, true).timeout
	get_tree().paused = false
	route.reset_route()
	await get_tree().create_timer(0.15).timeout
	_check(visual.global_position.distance_to(route.player.global_position) < 0.0001, "resume/reset has no old motion trail")
	groups += 1
