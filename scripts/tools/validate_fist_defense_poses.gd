extends Node
## Independent Codex acceptance: resources, state transitions, equipment and camera.
var errors: Array[String] = []
var groups := 0
var sandbox: Node
var player: Node
var defense: Node
var visual: Node
var body: AnimatedSprite3D
var expected_views: Dictionary = {}

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("DEFENSE_POSES_FAIL: " + message)

func group(label: String) -> void:
	groups += 1
	print("DEFENSE_POSES_GROUP %d %s" % [groups, label])

func settle() -> void:
	for i in 3: await get_tree().process_frame

func draw_pose() -> void:
	player._update_visual()
	visual._process(0.0)

func action() -> String:
	return String(body.animation).get_slice("_", 0)

func same_texture(a: Texture2D, b: Texture2D) -> bool:
	if a is AtlasTexture and b is AtlasTexture:
		return a.atlas.resource_path == b.atlas.resource_path and a.region == b.region and a.margin == b.margin
	return a.resource_path == b.resource_path

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var prefix := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(prefix + "defense-pose-" + label + ".png") == OK, "capture " + label)

func run() -> void:
	for tech in ["novice", "trained"]:
		var bare: SpriteFrames = load("res://assets/characters/courtyard/fist-defense/" + tech + "_frames.tres")
		for pack in [false, true]:
			var name: String = tech + ("_pack" if pack else "")
			var frames: SpriteFrames = load("res://assets/characters/courtyard/fist-defense/" + name + "_frames.tres")
			var old: SpriteFrames = load("res://assets/characters/courtyard/fist-preview/" + name + "_frames.tres")
			if frames == null or old == null:
				check(false, "resources missing " + name)
				finish()
				return
			check(frames.get_animation_names().size() == old.get_animation_names().size() + 6, "exactly six new clips " + name)
			for key in old.get_meta_list(): check(frames.get_meta(key) == old.get_meta(key), "old metadata preserved " + name + str(key))
			for clip in old.get_animation_names():
				check(frames.has_animation(clip) and frames.get_frame_count(clip) == old.get_frame_count(clip), "old clip retained " + name + clip)
				check(frames.get_animation_speed(clip) == old.get_animation_speed(clip) and frames.get_animation_loop(clip) == old.get_animation_loop(clip), "old timing " + name + clip)
				for i in old.get_frame_count(clip):
					check(same_texture(frames.get_frame_texture(clip, i), old.get_frame_texture(clip, i)), "old texture " + name + clip)
					check(frames.get_frame_duration(clip, i) == old.get_frame_duration(clip, i), "old duration " + name + clip)
			for state in ["guard", "hit"]:
				check(frames.get_meta("baseline_offset_pixels_" + state, -1) == 300.0, "feet baseline " + name)
				for view in ["front", "back", "side"]:
					var clip: String = state + "_" + view
					check(frames.has_animation(clip) and frames.get_frame_count(clip) == 1, "whole single pose " + name + clip)
					check(not frames.get_animation_loop(clip) and frames.get_animation_speed(clip) == 1.0, "held pose timing")
					var tex := frames.get_frame_texture(clip, 0) as AtlasTexture
					check(tex != null and tex.get_size() == Vector2(640, 640) and tex.filter_clip, "uncut normalized canvas " + name + clip)
					var scale_value: float = frames.get_meta("pixel_size_" + state + "_" + view, -1.0)
					check(is_finite(scale_value) and scale_value > 0 and scale_value < .01, "body scale valid")
					check(scale_value == float(bare.get_meta("pixel_size_guard_" + view, -2.0)), "shared bare scale for equipment and reaction")
	group("24 whole poses and preserved old resources")
	sandbox = load("res://scripts/tools/fist_defense_sandbox.tscn").instantiate()
	add_child(sandbox)
	await settle()
	player = sandbox.level.get_node("Actors/Player")
	visual = player.get_node("Visual")
	body = visual.get_node("Body")
	defense = sandbox.defense
	player.set_physics_process(false)
	defense.set_physics_process(false)
	var rig: Node = sandbox.level.get_node("CameraRig")
	for tech in ["novice", "trained"]:
		check(sandbox.set_technique(tech), "technique " + tech)
		for pack in [false]: # D-057: no backpack variant any more
			check(sandbox.set_backpack_enabled(pack), "hero stays without a backpack")
			defense.reset_trial()
			# Preview starts at 45 degrees: cardinal samples avoid intentionally
			# ambiguous diagonal boundaries in the view selector's hysteresis.
			rig.rotate_view(Vector2(deg_to_rad(45.0) / rig.mouse_sensitivity, 0))
			await get_tree().physics_frame
			await settle()
			player.velocity = Vector3.ZERO
			check(defense.set_guard(true), "guard down")
			var before: Dictionary = defense.snapshot().duplicate(true)
			for i in 4:
				draw_pose()
				check(action() == "guard", "visible guard " + tech)
				expected_views[String(visual._current_view)] = true
				check(body.sprite_frames.get_meta("fist_defense_technique", "") == tech, "correct pose technique")
				check(body.sprite_frames.get_meta("fist_defense_backpack", not pack) == pack, "correct whole equipment")
				if tech == "trained" and pack: await capture("trained-pack-view-" + str(i))
				rig.rotate_view(Vector2(deg_to_rad(90.0) / rig.mouse_sensitivity, 0))
				await get_tree().physics_frame
				await settle()
			check(defense.snapshot() == before, "camera cannot restart defense")
			draw_pose()
			await capture(tech + ("-pack" if pack else "") + "-guard")
			defense.set_guard(false)
			draw_pose()
			check(action() == "idle", "release restores idle")
	check(expected_views.size() == 4, "front back left right all visited")
	group("guard release, four views, both techniques and equipment")
	defense.reset_trial()
	sandbox.set_technique("trained")
	defense.set_guard(true)
	player.velocity = Vector3(1, 0, 0)
	draw_pose()
	check(action() == "walk" and defense.snapshot().guarding, "movement retains locomotion and defense")
	player.velocity = Vector3.ZERO
	draw_pose()
	check(action() == "guard", "stopping restores guard")
	defense.set_guard(false)
	player.request_attack()
	defense.start_swing()
	defense.advance(.81)
	draw_pose()
	check(player.is_attacking() and action() == "attack", "incoming hit cannot conceal active attack")
	player.stop_input()
	defense.cancel_trial()
	draw_pose()
	check(action() == "idle", "cancel leaves no stale visual")
	group("movement and attack priority")
	for tech in ["novice", "trained"]:
		sandbox.set_technique(tech)
		defense.reset_trial()
		defense.start_swing()
		defense.advance(.8)
		draw_pose()
		check(action() == "hit", "hit visibly reacts " + tech)
		var unchanged: Dictionary = defense.snapshot().duplicate(true)
		for i in 50: defense.get_visual_action()
		check(defense.snapshot() == unchanged, "visual getter is read-only")
		await capture(tech + "-hit")
		defense.advance(.199)
		draw_pose()
		check(action() == "hit", "reaction retained before .2 boundary")
		defense.advance(.002)
		draw_pose()
		check(action() == "idle", "reaction expires with simulation clock")
	defense.reset_trial()
	defense.set_guard(true)
	defense.start_swing()
	defense.advance(.81)
	draw_pose()
	check(defense.snapshot().result == "block" and action() == "guard", "blocked contact never plays unblocked hit")
	group("contact reactions, expiry and read-only presentation")
	body.set_frame_and_progress(0, .37)
	var progress := body.frame_progress
	var state: Dictionary = defense.snapshot().duplicate(true)
	sandbox.set_backpack_enabled(not sandbox.is_backpack_enabled())
	draw_pose()
	check(action() == "guard" and is_equal_approx(body.frame_progress, progress), "gear swap preserves pose progress")
	check(defense.snapshot() == state, "gear swap preserves defense time")
	defense.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	draw_pose()
	check(action() == "idle", "focus clears held pose")
	defense.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	defense.reset_trial()
	defense.set_guard(true)
	var menu: Node = sandbox.level.get_node("InventoryMenu")
	check(menu.request_open(), "real pocket menu")
	defense.advance(.01)
	draw_pose()
	check(defense.get_visual_action() == &"", "menu hides combat presentation")
	menu.close_menu(false)
	await settle()
	draw_pose()
	check(action() == "idle", "menu closing cannot resurrect guard")
	group("equipment phase, focus and actual pocket menu")
	sandbox.queue_free()
	await settle()
	var ordinary: Node = load("res://scripts/tools/fist_technique_sandbox.tscn").instantiate()
	add_child(ordinary)
	await settle()
	var old_body: AnimatedSprite3D = ordinary.level.get_node("Actors/Player/Visual/Body")
	check(not old_body.sprite_frames.has_animation("guard_front"), "ordinary comparison stays on its old frame set")
	ordinary.queue_free()
	await settle()
	group("ordinary comparison remains isolated")
	finish()

func finish() -> void:
	if errors.is_empty() and groups == 6:
		print("ASHBOUND_FIST_DEFENSE_POSES_OK groups=6")
		get_tree().quit(0)
	else:
		printerr("DEFENSE_POSES_INCOMPLETE groups=%d errors=%d" % [groups, errors.size()])
		get_tree().quit(1)
