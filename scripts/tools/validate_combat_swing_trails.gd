extends "res://scripts/tools/validate_combat_feedback.gd"
## Independent Codex QA. Uses the real sandbox and public input/attack paths.
var trails: Node3D
var toolbar: Node

func mouse(button: MouseButton, pressed: bool, pos: Vector2 = Vector2(700, 500), canceled: bool = false, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = pos
	event.global_position = pos
	event.canceled = canceled
	event.device = device
	get_viewport().push_input(event, true)

func key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.keycode = KEY_G
	event.pressed = pressed
	get_viewport().push_input(event, true)

func touch(pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 7
	event.pressed = pressed
	event.position = toolbar._guard_btn.get_global_rect().get_center()
	toolbar._input(event)

func count() -> int:
	return int(trails.debug_snapshot().total_emitted)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var prefix := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(prefix + "swing-" + label + ".png") == OK, "capture " + label)

func run() -> void:
	sandbox = load("res://scripts/tools/combat_feedback_sandbox.tscn").instantiate()
	sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sandbox)
	await settle()
	session = sandbox.defense
	player = sandbox.level.get_node("Actors/Player")
	wolf = session.enemies[0]; guard = session.enemies[1]
	session.set_physics_process(false); player.set_physics_process(false)
	session.resolved.connect(func(result: String) -> void: events.append(result))
	fx = session.get_node("CombatFeedbackFX")
	trails = session.get_node("SwingTrails")
	for child in sandbox.get_children():
		if child.get_script() == load("res://scripts/tools/corner_enemy_toolbar.gd"): toolbar = child
	check(toolbar != null, "real toolbar exists")
	if toolbar == null: get_tree().quit(1); return
	reset(); await settle()

	mouse(MOUSE_BUTTON_RIGHT, true)
	if OS.has_feature("android"):
		check(not session.snapshot().guarding, "Android ignores physical RMB")
	else:
		check(session.snapshot().guarding, "RMB works over world, outside buttons")
		var press_time: float = session._guard_started
		session.advance(.03); mouse(MOUSE_BUTTON_RIGHT, true)
		check(is_equal_approx(session._guard_started, press_time), "duplicate RMB cannot rearm perfect block")
		mouse(MOUSE_BUTTON_LEFT, false); key(false); touch(false)
		check(session.snapshot().guarding, "unrelated releases cannot steal RMB")
	mouse(MOUSE_BUTTON_RIGHT, false, Vector2(-100, -100))
	check(not session.snapshot().guarding, "outside RMB release clears")
	if not OS.has_feature("android"):
		mouse(MOUSE_BUTTON_RIGHT, true); mouse(MOUSE_BUTTON_RIGHT, true, Vector2.ZERO, true)
		check(not session.snapshot().guarding, "canceled pressed RMB releases")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse(MOUSE_BUTTON_RIGHT, true)
		check(session.snapshot().guarding, "captured RMB works")
		mouse(MOUSE_BUTTON_RIGHT, false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	key(true); mouse(MOUSE_BUTTON_RIGHT, false)
	check(session.snapshot().guarding, "RMB up leaves G owner held")
	key(false)
	touch(true); mouse(MOUSE_BUTTON_RIGHT, false)
	check(session.snapshot().guarding, "RMB up leaves touch owner held")
	touch(false)
	mouse(MOUSE_BUTTON_RIGHT, true, Vector2(700, 500), false, InputEvent.DEVICE_ID_EMULATION)
	check(not session.snapshot().guarding, "emulated mouse cannot duplicate touch")
	if not OS.has_feature("android"):
		for outcome in ["block", "perfect_block"]:
			reset(); place(guard); await settle()
			if outcome == "block": mouse(MOUSE_BUTTON_RIGHT, true)
			until_cue()
			if outcome == "perfect_block": mouse(MOUSE_BUTTON_RIGHT, true)
			until_contact(guard)
			check(events == [outcome], "RMB produces actual " + outcome)
			mouse(MOUSE_BUTTON_RIGHT, false)
	group("RMB world/captured/release/ownership and Android touch")

	for how in ["focus", "app", "tree", "menu"]:
		reset(); await settle(); touch(true)
		check(session.snapshot().guarding, "guard held before " + how)
		match how:
			"focus": toolbar.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"app": toolbar.notification(NOTIFICATION_APPLICATION_PAUSED)
			"tree": get_tree().paused = true
			"menu": check(sandbox.level.get_node("InventoryMenu").request_open(), "menu opens")
		await settle(); toolbar._process(0)
		check(not session.snapshot().guarding, "guard cleared " + how)
		match how:
			"focus": toolbar.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			"app": toolbar.notification(NOTIFICATION_APPLICATION_RESUMED)
			"tree": get_tree().paused = false
			"menu": sandbox.level.get_node("InventoryMenu").close_menu(false)
		await settle(); toolbar._process(0)
		check(not session.snapshot().guarding, "no automatic rearm " + how)
	group("guard lifecycle gates")

	reset(); var vertices := 0
	for mesh in meshes(trails):
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "air has no shadow")
		check(not mesh.material_override.no_depth_test, "air respects walls/depth")
		for surface in mesh.mesh.get_surface_count(): vertices += mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
	check(vertices <= 1000 and meshes(trails).size() == 18, "bounded three-ribbon pool")
	var before := count()
	trails.emit_swing("invalid", Vector3.ZERO, Vector3.ZERO)
	check(count() == before, "unknown kind ignored")
	for i in 20: trails.emit_swing("hero", Vector3.ZERO, Vector3.ZERO)
	check(trails.debug_snapshot().active_trails == 6 and trails.get_child_count() == 6, "pool never grows")
	var snap: Dictionary = trails.debug_snapshot().duplicate(true)
	trails.advance(-1); trails.advance(NAN); trails.advance(INF)
	check(trails.debug_snapshot() == snap, "invalid deltas ignored")
	trails.advance(.3)
	check(visible_meshes(trails) == 0, "trails expire")
	trails.emit_swing("hero", Vector3(0, 1, 0), Vector3.RIGHT); trails.advance(.1)
	var first: MeshInstance3D = meshes(trails)[0]
	var alpha: float = first.material_override.albedo_color.a
	check(alpha > .1 and alpha < .8, "visible non-opaque air")
	trails.emit_swing("guard", Vector3.ONE, Vector3.FORWARD)
	check(is_equal_approx(first.material_override.albedo_color.a, alpha), "independent alpha")
	trails.clear_all(); trails.emit_swing("hero", Vector3.ZERO, Vector3.RIGHT)
	check(is_zero_approx(first.material_override.albedo_color.a), "reused slot resets reveal alpha")
	trails.advance(.05)
	var pos: Vector3 = first.get_parent().global_position
	for i in 20: trails._process(.1)
	check(first.get_parent().global_position.is_equal_approx(pos), "orientation has no second drift clock")
	check(absf(meshes(trails)[1].position.y - first.position.y) >= .09, "streaks visibly separate")
	var positions: Array[Vector3] = []
	for fps in [30, 60, 120]:
		trails.clear_all(); trails.emit_swing("hero", Vector3(3, 2, 1), Vector3.RIGHT)
		for i in int(fps * .1): trails.advance(1.0/fps)
		positions.append(first.get_parent().global_position)
	check(positions[0].distance_to(positions[1]) < .001 and positions[1].distance_to(positions[2]) < .001, "trajectory independent of update frequency")
	trails.position = Vector3(8, 2, 4)
	trails.clear_all(); trails.emit_swing("hero", Vector3(3, 2, 1), Vector3.RIGHT)
	check(first.get_parent().global_position.distance_to(Vector3(3, 2, 1)) < .001, "emission anchor is world space")
	var camera := get_viewport().get_camera_3d()
	var camera_transform := camera.global_transform
	var trail_root := first.get_parent() as Node3D
	var anchor := trail_root.global_position
	for offset in [Vector3(3,2,4), Vector3(-3,1,2), Vector3(0,4,0)]:
		camera.global_position = anchor + offset
		trails._process(0)
		var normal: Vector3 = offset.normalized()
		var projected: Vector3 = Vector3.RIGHT - normal * Vector3.RIGHT.dot(normal)
		check(trail_root.global_transform.basis.z.normalized().dot(normal) > .99, "ribbon plane faces camera")
		check(absf(trail_root.global_transform.basis.x.normalized().dot(projected.normalized())) > .99, "ribbon axis follows projected world swing")
		check(trail_root.global_position.distance_to(anchor) < .001, "translated parent cannot cause drift")
	trails.clear_all(); trails.emit_swing("hero", anchor, Vector3.FORWARD)
	camera.global_position = anchor + Vector3(0, .6, 3)
	trails._process(0)
	check(absf(trail_root.global_basis.x.normalized().dot(camera.global_basis.x.normalized())) > .7, "end-on swing stays a lateral sweep")
	camera.global_transform = camera_transform
	trails.position = Vector3.ZERO; trails.clear_all()
	group("pool, geometry, reveal/fade and single clock")

	reset(); before = count(); player.request_attack()
	for i in 6: player._physics_process(1.0/60)
	check(count() == before, "no trail before swing")
	for i in 2: player._physics_process(1.0/60)
	check(count() == before + 1 and trails.debug_snapshot().last_kind == "hero", "one real miss trail")
	check(not session.is_hitstopped() and fx.debug_snapshot().active_impacts == 0, "miss trail is not contact")
	player.request_attack()
	for i in 35: player._physics_process(1.0/60)
	check(count() == before + 1, "rejected repeat cannot add trail")
	reset(); before = count(); session.set_guard(true); player.request_attack()
	for i in 10: player._physics_process(1.0/60)
	check(count() == before, "guard prevents swing trail")
	group("real outgoing attacks including misses and rejection")

	for actor in [wolf, guard]:
		reset(); place(actor); await settle(); before = count()
		tick(.35); check(count() == before, "early windup has no air " + actor.kind)
		until_cue()
		check(count() == before + 1 and trails.debug_snapshot().last_kind == actor.kind, "one natural enemy swing " + actor.kind)
		until_contact(actor)
		check(events == ["hit"] and count() == before + 1, "one contact without duplicate trail")
		session.advance(.1)
		check(count() == before + 1, "hitstop cannot re-emit enemy trail")
		reset(); place(actor); await settle(); before = count(); tick(.2); session.cancel_trial()
		check(count() == before and visible_meshes(trails) == 0, "early canceled windup has no air")
	group("enemy swing timing and contact separation")

	for how in ["focus", "app", "tree", "menu", "reset", "technique"]:
		reset(); trails.emit_swing("hero", player.global_position + Vector3.UP, Vector3.FORWARD); trails.advance(.05)
		match how:
			"focus": session.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"app": session.notification(NOTIFICATION_APPLICATION_PAUSED)
			"tree": get_tree().paused = true
			"menu": sandbox.level.get_node("InventoryMenu").request_open(); session.advance(0)
			"reset": session.reset_trial()
			"technique": sandbox.set_technique("novice")
		check(visible_meshes(trails) == 0, "trail clears " + how)
		match how:
			"focus": session.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			"app": session.notification(NOTIFICATION_APPLICATION_RESUMED)
			"tree": get_tree().paused = false
			"menu": sandbox.level.get_node("InventoryMenu").close_menu(false)
		await settle()
	reset(); trails.emit_swing("hero", Vector3.ZERO, Vector3.FORWARD)
	session._begin_stop(.25, &"attack"); session.advance(.24)
	check(visible_meshes(trails) == 0, "trail expires in unscaled hitstop")
	group("trail cancellation and hitstop lifetime")

	for fps in [15, 30, 60, 120]:
		reset(); place(guard); await settle(); before = count()
		for i in fps: session.advance(1.0/fps)
		check(count() == before + 1 and events == ["hit"], "one swing/contact at " + str(fps))
	group("variable frame intervals")

	reset(); await settle(); sandbox.level._snap_camera_to_player()
	var rig: Node = sandbox.level.get_node("CameraRig")
	for view in 4:
		reset()
		rig.rotate_view(Vector2(deg_to_rad(90.0 * view)/rig.mouse_sensitivity, 0))
		await settle(); player.request_attack()
		for i in 8: player._physics_process(1.0/60)
		trails.advance(.035); trails._process(0)
		await capture("hero-" + str(view))
	for actor in [wolf, guard]:
		reset(); place(actor); await settle(); sandbox.level._snap_camera_to_player()
		rig.rotate_view(Vector2(deg_to_rad(55)/rig.mouse_sensitivity, 0)); await settle()
		until_cue(); tick(.035); await capture(actor.kind)
	group("rendered hero and enemy trails")
	reset()
	if errors.is_empty() and groups == 8:
		print("ASHBOUND_COMBAT_SWING_OK groups=8"); get_tree().quit(0)
	else:
		printerr("SWING_INCOMPLETE groups=%d errors=%d" % [groups, errors.size()]); get_tree().quit(1)
