extends SceneTree
## Codex visual QA: render original textures through real player/shadow materials.
var errors: Array[String] = []
var cells := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("FIST_RENDER_FAIL: " + message)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FIST_RENDER_FAIL: graphics required")
		quit(1)
		return
	var inv: Node = root.get_node("Inventory")
	check(inv.configure_storage([{"id":"traveler_clothing_pocket", "kind":"pocket", "capacity":6}]), "fixture")
	check(inv.add_item("traveler_backpack"), "bag instance")
	for worn in [false, true]:
		if worn: check(inv.equip_storage_item({"instance_id":inv.items[0].instance_id}), "equip before render")
		var sheet := SubViewport.new()
		sheet.size = Vector2i(1400, 1800)
		sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(sheet)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 0)
		grid.add_theme_constant_override("v_separation", 0)
		sheet.add_child(grid)
		for technique in ["novice", "trained"]:
			var bare: SpriteFrames = load("res://assets/characters/courtyard/fist-preview/" + technique + "_frames.tres")
			var pack: SpriteFrames = load("res://assets/characters/courtyard/fist-preview/" + technique + "_pack_frames.tres")
			for view in ["back", "front", "side"]:
				for pose in 5:
					var column := VBoxContainer.new()
					column.custom_minimum_size = Vector2(280, 300)
					grid.add_child(column)
					var label := Label.new()
					label.text = "%s %s %s" % [technique, view, "idle" if pose == 0 else str(pose - 1)]
					label.add_theme_font_size_override("font_size", 19)
					column.add_child(label)
					var container := SubViewportContainer.new()
					container.custom_minimum_size = Vector2(280, 270)
					column.add_child(container)
					var viewport := SubViewport.new()
					viewport.size = Vector2i(280, 270)
					viewport.own_world_3d = true
					viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
					container.add_child(viewport)
					var env := WorldEnvironment.new()
					env.environment = Environment.new()
					env.environment.background_mode = Environment.BG_COLOR
					env.environment.background_color = Color(0.14, 0.16, 0.19)
					viewport.add_child(env)
					var camera := Camera3D.new()
					camera.projection = Camera3D.PROJECTION_ORTHOGONAL
					camera.size = 2.3
					viewport.add_child(camera)
					camera.position = Vector3(0, 1.0, 4)
					camera.look_at(Vector3(0, 1.0, 0))
					var actor: Node = load("res://scenes/courtyard/courtyard_player.tscn").instantiate()
					viewport.add_child(actor)
					actor.set_physics_process(false)
					var visual: Node = actor.get_node("Visual")
					var action := "idle" if pose == 0 else "attack"
					visual._current_view = StringName("right" if view == "side" else view)
					visual._current_action = StringName(action)
					var layer: Node = visual.get_node("BackpackLayer")
					check(layer.configure_body_frame_pair(bare, pack), "render pair")
					var body: AnimatedSprite3D = visual.get_node("Body")
					body.animation = StringName(action + "_" + view)
					body.pause()
					body.set_frame_and_progress(maxi(0, pose - 1), 0.0)
					visual._apply_sprite_scale(body)
					check(body.sprite_frames == (pack if worn else bare), "actual worn variant")
					cells += 1
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		check(sheet.get_texture().get_image().save_png("res://.tools/fist-review-" + ("pack" if worn else "bare") + ".png") == OK, "capture sheet")
		sheet.queue_free()
		await process_frame
	check(cells == 60, "all stance and attack cells captured")
	if errors.is_empty():
		print("ASHBOUND_FIST_RENDER_OK cells=60")
		quit(0)
	else:
		quit(1)
