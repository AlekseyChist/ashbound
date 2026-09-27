extends "res://scripts/tools/validate_combat_feedback.gd"
## Independent Codex acceptance of hand-painted VFX and their real combat wiring.
var trails: Node3D

func sprites(root: Node) -> Array[Sprite3D]:
	var found: Array[Sprite3D] = []
	for child in root.get_children():
		if child is Sprite3D: found.append(child)
		found.append_array(sprites(child))
	return found

func visible_sprites(root: Node) -> int:
	var result := 0
	for sprite in sprites(root):
		if sprite.is_visible_in_tree(): result += 1
	return result

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var prefix := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(prefix + "painted-" + label + ".png") == OK, "capture " + label)

func run() -> void:
	sandbox = load("res://scripts/tools/painted_combat_sandbox.tscn").instantiate()
	sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sandbox); await settle()
	session = sandbox.defense; player = sandbox.level.get_node("Actors/Player")
	wolf = session.enemies[0]; guard = session.enemies[1]
	session.set_physics_process(false); player.set_physics_process(false)
	session.resolved.connect(func(result: String) -> void: events.append(result))
	fx = session.get_node("CombatFeedbackFX"); trails = session.get_node("SwingTrails")
	check(fx.debug_snapshot().get("painted", false), "painted contact renderer wired")
	check(trails.debug_snapshot().get("painted", false), "painted swing renderer wired")
	check(sprites(fx).size() == 12 and sprites(trails).size() == 6, "bounded 18-sprite scene")
	for sprite in sprites(session):
		check(sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ink has no solid shadow")
		check(not sprite.no_depth_test and not sprite.shaded, "world depth and authored colors")
		check(sprite.hframes == 2 and sprite.vframes == 2, "four registered frames")
	reset(); tick(3)
	check(events.is_empty() and visible_sprites(fx) == 0 and visible_sprites(trails) == 0, "safe spawn has no stale effects")
	group("new preview and bounded transparent sprites")

	var pool: Node = fx.get_node("ImpactPool")
	fx.emit_impact("hit", Vector3(3,2,1), Vector3(20,0,0))
	var s: Sprite3D = sprites(pool)[0]
	check(s.global_position.is_equal_approx(Vector3(3,2,1)) and s.frame == 0, "first frame starts at world contact immediately")
	var expected := [1,2,3]
	for frame in expected:
		fx.advance(.055)
		check(s.frame == frame, "ordered painted animation frame " + str(frame))
	check(s.modulate.a > 0 and s.modulate.a < .9, "paint fades before expiry")
	var before: Dictionary = pool.debug_snapshot().duplicate(true)
	fx.advance(-1); fx.advance(NAN); fx.advance(INF)
	check(pool.debug_snapshot() == before, "invalid time cannot change state")
	var alpha := s.modulate.a
	fx.emit_impact("block", Vector3.ZERO, Vector3.ZERO)
	check(is_equal_approx(s.modulate.a, alpha), "overlapping impacts have independent opacity")
	fx.advance(.31)
	check(pool.debug_snapshot().active == 0 and visible_sprites(pool) == 0, "all effects expire")
	for i in 20: fx.emit_impact("perfect_block", Vector3.ZERO, Vector3.FORWARD)
	check(pool.debug_snapshot().active == 8 and sprites(pool).size() == 8, "effect storm stays bounded")
	fx.clear_all(); fx.emit_impact("hit", Vector3.ZERO, Vector3.RIGHT)
	check(s.frame == 0 and is_equal_approx(s.modulate.a,1), "reuse resets frame and opacity")
	before = pool.debug_snapshot().duplicate(true)
	fx.emit_impact("miss", Vector3.ZERO, Vector3.ZERO)
	check(pool.debug_snapshot() == before, "miss creates no impact")
	pool.emit("hit", Vector3(NAN,0,0), Vector3.RIGHT, .2, 1)
	pool.emit("hit", Vector3.ZERO, Vector3.RIGHT, -1, 1)
	pool.emit("hit", Vector3.ZERO, Vector3.RIGHT, .2, INF)
	check(pool.debug_snapshot() == before, "invalid emission cannot corrupt pool")
	pool.position = Vector3(6,2,4)
	fx.clear_all(); pool.emit("hit", Vector3(3,2,1), Vector3(20,0,0), .2, 1, .4)
	check(s.global_position.is_equal_approx(Vector3(3,2,1)), "translated parent preserves world anchor")
	pool.advance(.1)
	check(s.global_position.distance_to(Vector3(3.2,2,1)) < .001, "travel normalizes input direction")
	var anchor := s.global_position
	var camera := get_viewport().get_camera_3d()
	var camera_transform := camera.global_transform
	before = pool.debug_snapshot().duplicate(true)
	for offset in [Vector3(3,2,4), Vector3(-3,1,2), Vector3(0,4,0)]:
		camera.global_position = anchor + offset
		for i in 10: pool._process(.1)
		var normal: Vector3 = offset.normalized()
		check(s.global_basis.z.normalized().dot(normal) > .99 and s.global_basis.determinant() > .1, "visible right-handed camera-facing plane")
		check(s.global_position.distance_to(anchor) < .001, "orientation never drifts position")
	check(pool.debug_snapshot() == before, "orientation never advances animation")
	camera.global_transform = camera_transform
	pool.position = Vector3.ZERO
	fx.clear_all(); group("animation, reuse, independent fade and invalid time")

	fx.update_cue("test", Vector3(0,1,0), Vector3.FORWARD, .15, false, "guard")
	check(fx.debug_snapshot().visible_cues == 1 and visible_sprites(fx) == 1, "early windup is visible")
	var early_frames: Array = fx.debug_snapshot().cue_frames
	var cue_stroke: Sprite3D = fx.get_node("Cue0/Stroke")
	var cue_flash: Sprite3D = fx.get_node("Cue0/ArmedFlash")
	check(is_equal_approx(cue_stroke.pixel_size * cue_stroke.texture.get_width() / 2.0, 1.15), "guard cue has authored physical span")
	fx.position = Vector3(4,2,6)
	fx.update_cue("test", Vector3(0,1,0), Vector3.FORWARD, .9, true, "guard")
	check(cue_stroke.global_position.is_equal_approx(Vector3(0,1,0)) and cue_flash.global_position.is_equal_approx(Vector3(0,1,0)), "cue uses world anchor under translated parent")
	check(is_equal_approx(cue_flash.pixel_size * cue_flash.texture.get_width() / 2.0 * cue_flash.scale.x, .4), "armed glint is compact")
	fx.position = Vector3.ZERO
	check(visible_sprites(fx) == 2 and fx.debug_snapshot().cue_frames != early_frames, "armed window changes drawing and adds glint")
	fx.hide_cue("test"); fx._process(.2)
	check(visible_sprites(fx) == 0, "hidden cue cannot reappear from orientation")
	group("drawn windup and distinct block timing cue")

	for actor in [wolf, guard]:
		for outcome in ["hit", "block", "perfect_block"]:
			reset(); place(actor); await settle(); sandbox.level._snap_camera_to_player()
			var rig: Node = sandbox.level.get_node("CameraRig")
			rig.rotate_view(Vector2(deg_to_rad(50)/rig.mouse_sensitivity,0))
			if outcome == "block": session.set_guard(true)
			until_cue()
			check(fx.debug_snapshot().visible_cues == 1, "real windup cue " + actor.kind)
			if outcome == "perfect_block": session.set_guard(true)
			until_contact(actor)
			check(events == [outcome] and fx.debug_snapshot().last_result == outcome, "actual result " + actor.kind + outcome)
			check(fx.debug_snapshot().active_impacts == 1 and session.is_hitstopped(), "one painted impact and same hitstop")
			fx.advance(.065)
			await capture(actor.kind + "-" + outcome)
			tick(.35)
			check(events.size() == 1 and fx.debug_snapshot().active_impacts == 0, "no duplicate contact or stuck effect")
	group("natural hit, block and perfect block against both enemies")

	reset(); player.request_attack()
	for i in 8: player._physics_process(1.0/60)
	check(trails.debug_snapshot().active_trails == 1 and fx.debug_snapshot().active_impacts == 0 and not session.is_hitstopped(), "miss only creates painted swing")
	reset(); place(guard); await settle(); player.request_attack()
	for i in 8: player._physics_process(1.0/60)
	check(guard.hits_received == 1 and trails.debug_snapshot().active_trails == 1 and fx.debug_snapshot().active_impacts == 1, "landed punch shows swing plus hit exactly once")
	group("real outgoing hit and miss")

	for how in ["focus", "app", "tree", "menu", "reset", "technique"]:
		reset(); place(guard); await settle(); until_cue()
		fx.emit_impact("block", Vector3.ZERO, Vector3.FORWARD)
		match how:
			"focus": session.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"app": session.notification(NOTIFICATION_APPLICATION_PAUSED)
			"tree": get_tree().paused = true
			"menu": sandbox.level.get_node("InventoryMenu").request_open(); session.advance(0)
			"reset": session.reset_trial()
			"technique": sandbox.set_technique("novice")
		check(visible_sprites(fx) == 0 and visible_sprites(trails) == 0, "clear all painted effects " + how)
		match how:
			"focus": session.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			"app": session.notification(NOTIFICATION_APPLICATION_RESUMED)
			"tree": get_tree().paused = false
			"menu": sandbox.level.get_node("InventoryMenu").close_menu(false)
		await settle()
	group("menu, focus, pause, reset and technique cancellation")

	for fps in [15,30,60,120]:
		reset(); place(guard); await settle()
		for i in fps: session.advance(1.0/fps)
		check(events == ["hit"], "contact independent of VFX frame rate " + str(fps))
	reset(); fx.emit_impact("hit", Vector3.ZERO, Vector3.FORWARD)
	session._begin_stop(.25, &"attack"); session.advance(.24)
	check(fx.debug_snapshot().active_impacts == 0, "painted effect expires during local stop")
	group("variable update intervals and unscaled effect clock")

	var rig: Node = sandbox.level.get_node("CameraRig")
	for view in 4:
		reset(); rig.rotate_view(Vector2(deg_to_rad(90.0*view)/rig.mouse_sensitivity,0)); await settle()
		player.request_attack()
		for i in 8: player._physics_process(1.0/60)
		trails.advance(.06); await capture("swing-" + str(view))
		for outcome in ["hit", "block", "perfect_block"]:
			fx.clear_all(); fx.emit_impact(outcome, player.global_position + Vector3(0,1.35,0) + Vector3(.45,0,0), player.facing_direction)
			fx.advance(.07); await capture(outcome + "-" + str(view))
	group("painted profiles in four camera directions")
	reset()
	if errors.is_empty() and groups == 8:
		print("ASHBOUND_PAINTED_COMBAT_OK groups=8"); get_tree().quit(0)
	else:
		printerr("PAINTED_INCOMPLETE groups=%d errors=%d" % [groups, errors.size()]); get_tree().quit(1)
