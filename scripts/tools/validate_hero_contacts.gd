extends SceneTree
## Owner's reproductions: walk into the actual dummy and watchtower at maximum pitch.
var failures: Array[String] = []
var completed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("HERO_CONTACTS_FAIL: " + label)

func shot() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("HERO_CONTACTS_FAIL: graphical renderer required")
		quit(1)
		return
	root.size = Vector2i(1440, 810)
	var level: Node = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var player: CharacterBody3D = level.get_node("Actors/Player")
	var visual: Node3D = player.get_node("Visual")
	var rig: Node3D = level.get_node("CameraRig")
	rig.set_mouse_capture(false)
	for fixture in [
		{"name":"dummy", "start":Vector3(7,0.1,6), "path":"Environment/Props/Dummy", "minimum_z":3.575},
		{"name":"tower", "start":Vector3(9,0.1,-3), "path":"Environment/Buildings/Watchtower", "minimum_z":-6.125}
	]:
		player.global_position = fixture.start
		player.velocity = Vector3.ZERO
		player.set_physics_process(true)
		rig.reset_view()
		rig.rotate_view(Vector2(0,10000))
		rig.snap_to_target()
		player.set_move_input(Vector2.UP)
		for i in 100:
			await physics_frame
		player.stop_input()
		player.set_physics_process(false)
		check(player.global_position.z >= float(fixture.minimum_z) and player.global_position.z < float(fixture.minimum_z) + 0.1, str(fixture.name) + " stops at actual collision")
		visual.update_visual(&"idle", Vector3.FORWARD)
		var body: AnimatedSprite3D = visual.get_node("Body")
		body.pause()
		body.frame = 0
		rig.snap_to_target()
		var target: Node3D = level.get_node(fixture.path)
		target.hide()
		var reference := await shot()
		target.show()
		var actual := await shot()
		var camera: Camera3D = rig.get_camera()
		var covered := 0
		var samples := 0
		var output_scale := Vector2(actual.get_size()) / root.get_visible_rect().size
		for height in [0.6,0.85,1.1,1.35,1.6]:
			for x in [-0.08,0.0,0.08]:
				var point := camera.unproject_position(visual.to_global(Vector3(x,height,0)))
				var pos := Vector2i((point * output_scale).round())
				check(Rect2i(Vector2i.ZERO, actual.get_size()).has_point(pos), "probe on screen")
				var a := reference.get_pixelv(pos)
				var b := actual.get_pixelv(pos)
				if Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b)) > 0.12:
					covered += 1
				samples += 1
		check(covered == 0, str(fixture.name) + " background object cuts hero: " + str(covered) + "/" + str(samples))
		check(actual.save_png("res://.tools/hero-contact-" + str(fixture.name) + ".png") == OK, "contact capture")
		completed += 1
	level.queue_free()
	await process_frame
	if failures.is_empty() and completed == 2:
		print("ASHBOUND_HERO_CONTACTS_OK actual_colliders=2 torso_probes=30")
		quit(0)
	else:
		quit(1)
