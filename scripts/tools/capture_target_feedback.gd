extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := ""
	var view := "interact"
	var mobile_preview := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.substr("--output=".length())
		elif arg.begins_with("--view="):
			view = arg.substr(7)
		elif arg == "--mobile-preview":
			mobile_preview = true
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("capture_target_feedback: need --output and non-headless display")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	var level: Node = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	if mobile_preview:
		# Force HUD touch controls before adding to root (isolated QA setup).
		level.get_node("HUD").force_touch_controls = true
	root.add_child(level)
	await process_frame
	for i in 3:
		await physics_frame
	var player := level.get_node("Actors/Player") as CharacterBody3D
	if player == null:
		push_error("capture_target_feedback: Actors/Player not found")
		quit(1)
		return
	player.stop_input()
	if view == "attack":
		level._apply_state(4)
		player.global_position = Vector3(5.7, 0.1, 3.0)
		player.facing_direction = Vector3.RIGHT
	else:
		player.global_position = Vector3(-4.5, 0.1, -2.2)
		player.facing_direction = Vector3.FORWARD
	var rig := level.get_node_or_null("CameraRig")
	if rig and rig.has_method("reset_view"):
		rig.reset_view()
	for i in 12:
		await physics_frame
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var save_error := img.save_png(output)
	if save_error != OK:
		push_error("capture_target_feedback: save_png failed: ", error_string(save_error))
	var focus := ""
	if view == "attack":
		focus = str(level.get_attack_target())
	else:
		focus = str(level.get_interaction_target())
	print("capture_target_feedback: target=", focus, " path=", output)
	level.queue_free()
	await process_frame
	await process_frame
	quit(0 if save_error == OK else 1)
