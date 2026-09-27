extends "res://scripts/tools/validate_fist_defense_poses.gd"
## Codex QA: same camera, real input transitions and no action-specific tint.

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var prefix := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(prefix + "palette-" + label + ".png") == OK, "capture " + label)

func run() -> void:
	sandbox = load("res://scripts/tools/painted_combat_sandbox.tscn").instantiate()
	add_child(sandbox); await settle()
	player = sandbox.level.get_node("Actors/Player")
	visual = player.get_node("Visual"); body = visual.get_node("Body")
	defense = sandbox.defense
	player.set_physics_process(false); defense.set_physics_process(false)
	var rig: Node = sandbox.level.get_node("CameraRig")
	var seen := {}
	for pack in [false]: # D-057: no backpack variant any more
		sandbox.set_technique("trained"); sandbox.set_backpack_enabled(pack)
		defense.reset_trial()
		# Enemy preview resets facing and camera to cardinal zero (old pose fixture used 45 degrees).
		await get_tree().physics_frame; await settle()
		for view in 4:
			player.stop_input(); defense.set_guard(false); draw_pose(); body.pause()
			check(action() == "idle", "idle before guard")
			var color := body.modulate
			var shader: Shader = (body.material_override as ShaderMaterial).shader
			await capture(("pack-" if pack else "bare-") + str(view) + "-idle")
			defense.set_guard(true); draw_pose(); body.pause()
			check(action() == "guard", "guard via real input")
			seen[str(visual._current_view)] = true
			check(body.modulate == color and (body.material_override as ShaderMaterial).shader == shader, "palette uses same material and tint")
			var texture := body.sprite_frames.get_frame_texture(body.animation,0) as AtlasTexture
			check(texture.atlas.resource_path.ends_with("/trained-pack.png" if pack else "/trained.png"), "whole corrected atlas selected")
			await capture(("pack-" if pack else "bare-") + str(view) + "-guard")
			defense.set_guard(false); player.request_attack(); draw_pose(); body.pause()
			check(action() == "attack", "attack after release")
			check(body.modulate == color and (body.material_override as ShaderMaterial).shader == shader, "attack does not inherit a palette tint")
			await capture(("pack-" if pack else "bare-") + str(view) + "-attack")
			player.stop_input(); draw_pose()
			check(action() == "idle", "idle restored")
			group("same-camera transitions pack=%s view=%d" % [pack,view])
			rig.rotate_view(Vector2(deg_to_rad(90.0)/rig.mouse_sensitivity,0))
			await get_tree().physics_frame; await settle()
	check(seen.size()==4, "all four directions including mirrored left")
	if errors.is_empty() and groups==4: # D-057: bare hero only (was 8 groups with the backpack)
		print("ASHBOUND_GUARD_PALETTE_RUNTIME_OK groups=4"); get_tree().quit(0)
	else:
		printerr("PALETTE_INCOMPLETE groups=%d errors=%d" % [groups,errors.size()]); get_tree().quit(1)
