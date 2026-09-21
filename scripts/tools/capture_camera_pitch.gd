extends SceneTree
## Independent graphical QA: extreme input, reverse input, yaw and modal ownership.
var scene: Node
var rig: Node
var failures: Array[String] = []
var captures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("CAMERA_PITCH_FAIL: " + label)

func shot(label: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.tools/camera-pitch-" + label + ".png") == OK, "save " + label)
	captures += 1

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("CAMERA_PITCH_FAIL: requires graphical window")
		quit(1)
		return
	root.size = Vector2i(1440, 810)
	scene = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.3).timeout
	rig = scene.get_node("CameraRig")
	rig.set_mouse_capture(false)
	var arm: SpringArm3D = rig.get_node("SpringArm3D")
	check(is_equal_approx(rad_to_deg(arm.rotation.x), -12.0), "initial angle unchanged")
	await shot("default")
	for touch in [false, true]:
		rig.rotate_view(Vector2(0, 100000), touch)
		check(absf(rad_to_deg(arm.rotation.x) + 28.0) < 0.01, "downward limit with mouse/touch")
		rig.rotate_view(Vector2(0, -1), touch)
		check(rad_to_deg(arm.rotation.x) > -28.0, "reverse input immediately leaves limit")
		rig.rotate_view(Vector2(0, -100000), touch)
		check(absf(rad_to_deg(arm.rotation.x) - 5.0) < 0.01, "upward limit with mouse/touch")
	await shot("up")
	rig.rotate_view(Vector2(0, 100000))
	await shot("down")
	rig.rotate_view(Vector2(PI / rig.mouse_sensitivity, 0))
	check(absf(absf(rig.rotation.y) - PI) < 0.01, "horizontal half-turn remains available at limit")
	await shot("down-reverse")
	var menu: Node = scene.get_node("InventoryMenu")
	check(menu.request_open(), "inventory opens at extreme camera angle")
	var rotation_before: Vector3 = arm.rotation
	rig.rotate_view(Vector2(1000, -1000), true)
	check(arm.rotation.is_equal_approx(rotation_before), "menu retains camera input lock")
	menu.close_menu()
	rig.reset_view()
	check(absf(rad_to_deg(arm.rotation.x) + 12.0) < 0.01 and is_zero_approx(rig.rotation.y), "reset restores default")
	scene.queue_free()
	await process_frame
	if failures.is_empty() and captures == 4:
		print("ASHBOUND_CAMERA_PITCH_OK captures=4")
		quit(0)
	else:
		quit(1)
