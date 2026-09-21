extends SceneTree
## Independent QA: real projected artwork, foot anchoring and unchanged gameplay transform.
var failures: Array[String] = []
var cases := 0
var rendered := 0
var viewport: SubViewport
var camera: Camera3D
var actor: CharacterBody3D
var visual: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("HERO_PROJECTION_FAIL: " + label)

func settle() -> void:
	await process_frame
	await process_frame

func set_camera(pitch: float, yaw: float, distance: float = 3.0) -> void:
	camera.basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	camera.position = Vector3(0, 1.45, 0) + camera.basis.z * distance

func project(sprite: AnimatedSprite3D, point: Vector2) -> Vector2:
	return camera.unproject_position(sprite.to_global(Vector3(point.x, point.y, 0) * sprite.pixel_size))

func check_geometry(sprite: AnimatedSprite3D, label: String) -> void:
	# A rigid 100px square must stay square anywhere on the artwork, including its feet.
	# This checks output geometry, not equality with the implementation's camera basis.
	for y in [-120.0, 0.0, 120.0]:
		var left := project(sprite, Vector2(-50, y))
		var right := project(sprite, Vector2(50, y))
		var up := project(sprite, Vector2(0, y + 50))
		var down := project(sprite, Vector2(0, y - 50))
		check(absf(left.distance_to(right) / up.distance_to(down) - 1.0) < 0.002, label + " undistorted landmarks " + str(y))
		check(absf(left.y - right.y) < 0.05, label + " horizontal shoulders")
	var baseline := float(sprite.sprite_frames.get_meta("baseline_offset_pixels", 0))
	var feet := sprite.to_global(Vector3(0, -baseline * sprite.pixel_size, 0))
	check(feet.distance_to(actor.global_position) < 0.0001, label + " foot pivot stays at ground origin")
	check(sprite.billboard == BaseMaterial3D.BILLBOARD_DISABLED, label + " renderer does not override measured geometry")
	check(not sprite.no_depth_test and not sprite.fixed_size, label + " normal depth and distance scaling")
	var shadow := visual.get_node_or_null("BodyShadow" if sprite.name == "Body" else "PocketShadow") as AnimatedSprite3D
	check(shadow != null, label + " shadow caster exists")
	if shadow != null:
		check(shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, label + " shadow drawn once, no visible duplicate")
		check(shadow.global_basis.y.is_equal_approx(Vector3.UP), label + " shadow stays upright at any pitch")
		check(shadow.sprite_frames == sprite.sprite_frames and shadow.animation == sprite.animation and shadow.frame == sprite.frame and shadow.flip_h == sprite.flip_h and shadow.visible == sprite.visible, label + " shadow uses actual equipped pose")
		check(is_equal_approx(shadow.pixel_size, sprite.pixel_size) and shadow.global_position.is_equal_approx(actor.to_global(sprite.position)), label + " shadow retains authored height and feet")

func check_pixels(sprite: AnimatedSprite3D, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	var bounds := result.get_used_rect()
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var expected := texture.get_image().get_used_rect()
	var actual_ratio := float(bounds.size.x) / maxf(bounds.size.y, 1)
	var expected_ratio := float(expected.size.x) / maxf(expected.size.y, 1)
	check(bounds.size.y > 100 and bounds.position.y > 0 and bounds.end.y < viewport.size.y, label + " complete visible artwork")
	check(absf(actual_ratio / expected_ratio - 1.0) < 0.035, label + " rendered silhouette ratio: " + str(actual_ratio) + " vs source " + str(expected_ratio))
	check(result.save_png("res://.tools/hero-projection-" + label + ".png") == OK, label + " screenshot")
	rendered += 1

func check_near_wall(body: AnimatedSprite3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var wall := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(8, 8)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.BLUE
	quad.material = material
	wall.mesh = quad
	viewport.add_child(wall)
	for yaw in [0.0,90.0,180.0,270.0]:
		for pitch in [-28.0,-12.0,5.0]:
			set_camera(pitch,yaw)
			visual.update_visual(&"idle", -Vector3(camera.basis.z.x,0,camera.basis.z.z))
			body.pause()
			body.frame = 0
			wall.hide()
			await settle()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var reference := viewport.get_texture().get_image()
			var bounds := reference.get_used_rect()
			var normal := Vector3(camera.basis.z.x,0,camera.basis.z.z).normalized()
			wall.basis = Basis(Vector3.UP,deg_to_rad(yaw))
			for front in [false,true]:
				wall.position = normal * (0.35 if front else -0.35) + Vector3.UP * 1.5
				wall.show()
				await settle()
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var actual := viewport.get_texture().get_image()
				var blue := 0
				var opaque := 0
				for y in range(bounds.position.y,bounds.end.y,2):
					for x in range(bounds.position.x,bounds.end.x,2):
						if reference.get_pixel(x,y).a < 0.99:
							continue
						opaque += 1
						var pixel := actual.get_pixel(x,y)
						if pixel.b > 0.9 and pixel.r < 0.05 and pixel.g < 0.05:
							blue += 1
				var fraction := float(blue) / maxf(opaque,1)
				check(opaque > 1000, "wall fixture contains hero")
				check(fraction > 0.995 if front else fraction < 0.005, "close wall front=" + str(front) + " yaw=" + str(yaw) + " pitch=" + str(pitch) + " occluded fraction=" + str(fraction))
	wall.queue_free()
	await settle()

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(900, 1000)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	camera = Camera3D.new()
	camera.fov = 65
	viewport.add_child(camera)
	camera.make_current()
	set_camera(0, 0)
	actor = load("res://scenes/courtyard/courtyard_player.tscn").instantiate()
	viewport.add_child(actor)
	actor.set_physics_process(false)
	actor.get_node("GroundShadow").hide()
	visual = actor.get_node("Visual")
	var body: AnimatedSprite3D = visual.get_node("Body")
	var pocket: AnimatedSprite3D = visual.get_node("PocketPose")
	var collider: CollisionShape3D = actor.get_node("CollisionShape3D")
	var actor_before := actor.global_transform
	var collision_before := collider.global_transform
	var shadow_before: Transform3D = actor.get_node("GroundShadow").global_transform
	var inv: Node = root.get_node("Inventory")
	check(inv.add_item("traveler_backpack"), "backpack fixture")
	var bag: Dictionary = inv.items[0]
	await settle()
	for worn in [false, true]:
		if worn:
			check(inv.equip_storage_item({"instance_id": bag.instance_id}), "wear real backpack")
			visual.get_node("BackpackLayer").refresh_visual()
		for action in ["idle", "walk", "run", "attack", "pocket"]:
			for view in ["front", "back", "right", "left"]:
				set_camera(0, 0)
				var facing: Vector3 = {"front": Vector3.BACK, "back": Vector3.FORWARD, "right": Vector3.RIGHT, "left": Vector3.LEFT}[view]
				visual.update_visual(&"idle" if action == "pocket" else StringName(action), facing)
				if action == "pocket":
					check(visual.begin_inventory_access(), "begin pocket")
				var sprite := pocket if action == "pocket" else body
				sprite.pause()
				sprite.set_frame_and_progress(mini(1, sprite.sprite_frames.get_frame_count(sprite.animation) - 1), 0.37)
				var phase := [sprite.animation, sprite.frame, sprite.frame_progress, sprite.pixel_size, sprite.flip_h]
				for angle in [-28.0, -12.0, 5.0]:
					set_camera(angle, 0)
					await settle()
					var label: String = ("pack" if worn else "bare") + "-" + action + "-" + view + "-" + str(int(angle))
					check_geometry(sprite, label)
					check(phase == [sprite.animation, sprite.frame, sprite.frame_progress, sprite.pixel_size, sprite.flip_h], label + " pitch preserves animation phase and authored scale")
					if action == "idle" and view == "front":
						await check_pixels(sprite, label)
					elif angle == -28.0 and ((action == "pocket" and view == "back") or (action == "run" and view == "right")):
						await check_pixels(sprite, label)
					var body_shadow := visual.get_node_or_null("BodyShadow") as AnimatedSprite3D
					var pocket_shadow := visual.get_node_or_null("PocketShadow") as AnimatedSprite3D
					if body_shadow != null and pocket_shadow != null:
						check(body_shadow.visible == body.visible and pocket_shadow.visible == pocket.visible, label + " exactly active pose casts shadow")
					cases += 1
				if action == "pocket":
					visual.end_inventory_access()
	# Perspective scaling stays intact, and opaque world geometry still hides the sprite.
	await check_near_wall(body)
	set_camera(0, 0, 2)
	await settle()
	var near_width := project(body, Vector2(-50, 0)).distance_to(project(body, Vector2(50, 0)))
	set_camera(0, 0, 4)
	await settle()
	var far_width := project(body, Vector2(-50, 0)).distance_to(project(body, Vector2(50, 0)))
	check(absf(near_width / far_width - 2.0) < 0.01, "perspective size follows distance")
	if DisplayServer.get_name() != "headless":
		var wall := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(10, 10)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color.BLUE
		quad.material = material
		wall.mesh = quad
		viewport.add_child(wall)
		wall.global_position = camera.global_position - camera.global_basis.z
		await settle()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var pixel := viewport.get_texture().get_image().get_pixel(450, 500)
		check(pixel.b > 0.9 and pixel.r < 0.05 and pixel.g < 0.05, "world geometry occludes hero")
		wall.queue_free()
		await settle()
	# Horizontal orbit and a replacement camera must work without cached transforms.
	for yaw in [90.0, 180.0, 270.0]:
		set_camera(-28, yaw)
		await settle()
		check_geometry(body, "orbit " + str(yaw))
	var second := Camera3D.new()
	viewport.add_child(second)
	second.transform = camera.transform
	second.rotation.x = 0
	second.make_current()
	camera = second
	await settle()
	check_geometry(body, "replacement camera")
	camera.clear_current(false)
	var basis_before := visual.global_basis
	await settle()
	check(visual.global_basis.is_equal_approx(basis_before), "no camera is safe")
	check(actor.global_transform.is_equal_approx(actor_before), "presentation does not rotate or scale actor")
	check(collider.global_transform.is_equal_approx(collision_before), "collision remains upright")
	check(actor.get_node("GroundShadow").global_transform.is_equal_approx(shadow_before), "ground shadow stays on ground")
	check(actor.facing_direction == Vector3.FORWARD, "presentation does not rewrite gameplay facing")
	viewport.queue_free()
	await settle()
	if failures.is_empty() and cases == 120 and (DisplayServer.get_name() == "headless" or rendered == 10):
		print("ASHBOUND_HERO_PROJECTION_OK cases=", cases, " rendered=", rendered)
		quit(0)
	else:
		quit(1)
