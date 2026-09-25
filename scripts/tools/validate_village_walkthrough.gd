extends Node
## Coordinator acceptance: real CharacterBody traversal and the actual input path.
const Scene = preload("res://scenes/world/village_walkthrough.tscn")
var world: Node3D
var failures: Array[String] = []
var checks := 0
var completed: Array[String] = []
var output := "user://village-qa"
var capture := false
var measuring := false
var frame_ms: Array[float] = []

func _process(delta: float) -> void:
	if measuring and capture: frame_ms.append(delta * 1000.0)

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("VILLAGE_QA_FAIL ", label)

func settle(seconds: float = 0.2) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

func place(at: Vector3) -> void:
	world.player.stop_input()
	world.player.velocity = Vector3.ZERO
	world.player.global_position = at + Vector3.UP * 0.03
	world.camera_rig.reset_view()
	await settle(0.4)

func walk(direction: Vector2, seconds: float) -> void:
	measuring = true
	world.player.set_move_input(direction)
	await settle(seconds)
	world.player.set_move_input(Vector2.ZERO)
	await settle(0.2)
	measuring = false

func screen(label: String) -> void:
	if not capture: return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
	check(result == OK, "save screenshot " + label)

func touch(at: Vector2, down: bool, index: int = 6) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = down
	event.position = at
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func tap(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	await touch(at, true)
	await touch(at, false)

func key_interact(cyrillic: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = 1059 if cyrillic else KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event, true)

func click_interact() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = world.interact_button.get_global_rect().get_center()
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event, true)

func check_leaf_side(building: Node3D, outside: bool, label: String) -> void:
	# Independent observation of rendered geometry, not the controller's chosen sign.
	for leaf in building.door.leaves:
		var mesh: MeshInstance3D = leaf.mesh
		var center: Vector3 = building.to_local(mesh.to_global(mesh.get_aabb().get_center()))
		var side: float = center.z - building.record.entry.z
		check(side > 0.35 if outside else side < -0.35, str(building.record.id) + label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--output"): output = args[args.find("--output") + 1]
	DirAccess.make_dir_recursive_absolute(output)
	capture = DisplayServer.get_name() != "headless"
	world = Scene.instantiate()
	add_child(world)
	await settle(0.5)
	check(world.buildings.size() == 3, "three buildings")
	check(world.player.get_node("Visual/Body").sprite_frames == preload("res://assets/characters/world-graybox-v1/traveler_frames.tres"), "accepted traveler unchanged")
	check(world.hud.get_node("RootControl").theme == preload("res://assets/ui/ashbound_ui.tres"), "shared UI book")
	for language in ["ru", "en"]:
		Localization.set_language(language)
		await settle()
		var bounds: Rect2 = world.hud.get_node("RootControl").get_global_rect()
		var controls: Array[Control] = [world.picker, world.language_button, world.interact_button, world.hud.get_node("RootControl/TopRightPanel/RestartButton")]
		for control in controls:
			check(bounds.encloses(control.get_global_rect()), "safe HUD " + language + " " + str(control.name))
			check(not control.text.begins_with("VILLAGE_"), "translated " + str(control.name))
		for a in range(controls.size()):
			for b in range(a + 1, controls.size()):
				check(not controls[a].get_global_rect().intersects(controls[b].get_global_rect()), "nonoverlapping toolbar " + language)
		await screen("hud-" + language)
	Localization.set_language("ru")
	# Touch runs through the viewport/HUD, not signals called by the test.
	await tap(world.picker)
	check(world.selected == 1, "touch next building")
	await tap(world.language_button)
	check(Localization.get_language() == "en", "touch language")
	Localization.set_language("ru")
	for i in range(3): await building_route(i)
	await focus_and_occupancy()
	world.select_building(0)
	await settle()
	await screen("ready")
	frame_ms.sort()
	var timings := {} if frame_ms.is_empty() else {"frames": frame_ms.size(), "p50_ms": frame_ms[frame_ms.size()/2], "p95_ms": frame_ms[int(frame_ms.size()*0.95)], "static_memory_bytes": OS.get_static_memory_usage()}
	var report := {"failures": failures, "checks": checks, "completed": completed, "platform": OS.get_name(), "rendering": RenderingServer.get_current_rendering_method(), "version": "0.22.1", "walk_timings": timings}
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("VILLAGE_QA_COMPLETE failures=%d buildings=%d checks=%d output=%s" % [failures.size(), completed.size(), checks, ProjectSettings.globalize_path(output)])
	get_tree().quit(0 if failures.is_empty() else 1)

func building_route(index: int) -> void:
	world.select_building(index)
	var building: Node3D = world.buildings[index]
	var door: Node3D = building.door
	var id: String = building.record.id
	var entry: Vector3 = building.to_global(building.record.entry)
	check(door.leaves.size() == (1 if index == 0 else 2), id + " imported hinges")
	var furniture_count := 0
	for mesh in building.model.find_children("*", "MeshInstance3D", true, false):
		var metadata: Dictionary = mesh.get_meta("extras", {})
		if metadata.get("part_role", "") == "furniture":
			furniture_count += 1
			check(mesh.get_node("StaticCollision").collision_layer == 9, id + " furniture obstructs leaf " + str(mesh.name))
		if index < 2 and metadata.get("part_role", "") == "foundation":
			check(not mesh.has_node("StaticCollision"), id + " stair proxy replaces original foundation collision")
	check(furniture_count > 0, id + " imported furniture roles available")
	await place(entry + Vector3(0, 0, 3.4))
	check(not door.try_toggle(world.player), id + " rejects distant interaction")
	await place(entry + Vector3(0, 0, 2.5))
	await screen(id + "-closed")
	# Attempt to walk through a closed door; a real collider must stop the actor.
	await walk(Vector2.UP, 1.1)
	check(world.player.global_position.z > entry.z + 0.2, id + " closed door blocks actor")
	check(world.player.global_position.z < entry.z + 0.45, id + " fixture touches closed door")
	var contact: Vector3 = world.player.global_position
	var previous_mode := Input.mouse_mode
	if index == 0:
		if capture and OS.get_name() != "Android": Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await key_interact(true)
	elif index == 1:
		if capture: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await click_interact()
	else:
		await tap(world.interact_button)
	if capture: Input.mouse_mode = previous_mode
	check(door.moving, id + " input starts door at contact")
	check(not door.try_toggle(world.player), id + " repeated press does not reverse")
	await settle(0.85)
	check(door.fraction > 0.99 and not door.moving, id + " fully open")
	check_leaf_side(building, false, " opens inward from outside")
	check(world.player.global_position.distance_to(contact) < 0.03, id + " opening does not push actor")
	await screen(id + "-open")
	await walk(Vector2.UP, 0.6)
	var inside: Vector3 = building.to_local(world.player.global_position)
	check(inside.z < building.record.entry.z - 1.5, id + " walks inside, actual=" + str(inside))
	check(world.player.is_on_floor() and absf(inside.y - float(building.record.floor_height)) < 0.08, id + " interior grounded")
	check(building.contains(world.player.global_position), id + " interior state")
	check_leaf_side(building, false, " keeps direction after crossing")
	# Inspect three camera headings; ray to camera must not cross solid walls.
	for heading in range(3):
		world.camera_rig.rotate_view(Vector2(450,0))
		await settle(0.3)
		var camera: Camera3D = world.camera_rig.get_camera()
		var query := PhysicsRayQueryParameters3D.create(world.camera_rig.global_position, camera.global_position, 1)
		check(world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), id + " camera stays before walls " + str(heading))
		await screen(id + "-inside-" + str(heading))
	world.camera_rig.reset_view()
	# Exercise actual keyboard dispatch, in addition to the touch route above.
	await key_interact()
	check(door.moving, id + " inside interaction")
	await settle(0.85)
	check(door.fraction < 0.01, id + " closes from inside")
	await walk(Vector2.DOWN, 0.7)
	check(world.player.global_position.z > entry.z - 0.45 and world.player.global_position.z < entry.z - 0.2, id + " inside contact fixture")
	contact = world.player.global_position
	await tap(world.interact_button)
	await settle(0.85)
	check(door.fraction > 0.99, id + " reopens from inside")
	check_leaf_side(building, true, " opens outward from inside")
	check(world.player.global_position.distance_to(contact) < 0.03, id + " inside opening does not push actor before=" + str(contact) + " after=" + str(world.player.global_position))
	await screen(id + "-inside-open")
	await walk(Vector2.DOWN, 1.35)
	check(world.player.global_position.z > entry.z + 2.2, id + " exits without transition")
	check(world.player.is_on_floor(), id + " exterior grounded")
	# Close each one, leaving no state behind for the next building.
	await place(entry + Vector3(0, 0, 2.5))
	world.interact()
	await settle(0.85)
	check(door.fraction < 0.01, id + " closed after route")
	completed.append(id)
	print("VILLAGE_ROUTE_DONE ", id)

func focus_and_occupancy() -> void:
	world.select_building(0)
	var building: Node3D = world.buildings[0]
	var door: Node3D = building.door
	var entry: Vector3 = building.to_global(building.record.entry)
	await place(entry + Vector3(0, 0, 2.5))
	check(door.try_toggle(world.player), "free swing starts")
	await settle(0.12)
	world._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var held: float = door.fraction
	world.interact()
	await settle(0.4)
	check(is_equal_approx(held, door.fraction) and not world.player.input_enabled, "focus loss suspends door and input")
	world._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await settle(0.8)
	check(door.fraction > 0.99 and world.player.input_enabled, "focus restores input and swing")
	check(world.buildings[1].door.fraction < 0.01 and world.buildings[2].door.fraction < 0.01, "independent door state")
	# Walk into the arc after a closing swing has begun. It must stop and resume.
	check(door.try_toggle(world.player), "closing starts with free arc")
	await settle(0.10)
	await place(entry + Vector3(0, 0, -0.55))
	var before: Vector3 = world.player.global_position
	check(door.moving and door.blocked and door.fraction > 0.1, "late occupant stops moving door")
	await settle(0.3)
	check(world.player.global_position.distance_to(before) < 0.04, "stopped swing does not displace occupant")
	await place(entry + Vector3(0, 0, 2.5))
	await settle(0.8)
	check(door.fraction < 0.01 and not door.moving, "swing resumes when path is free")
	# Occupants and furniture beyond the portal stop an already moving leaf.
	for layer in [2, 4, 8]:
		var obstacle := StaticBody3D.new()
		obstacle.collision_layer = layer
		obstacle.collision_mask = 0
		world.add_child(obstacle)
		obstacle.global_position = entry + Vector3(-0.1, 0.8, -0.62)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, 1.2, 0.3)
		shape.shape = box
		obstacle.add_child(shape)
		await settle()
		check(door.try_toggle(world.player), "starts toward obstruction layer=" + str(layer))
		await settle(0.9)
		check(door.blocked and door.moving and door.fraction > 0.05 and door.fraction < 0.95, "stops before obstruction layer=" + str(layer))
		var side: float = door.opening_sign
		if layer == 2:
			check(door.try_toggle(world.player), "blocked swing can return")
			await settle(0.85)
			check(door.fraction < 0.01 and door.opening_sign == side, "return preserves chosen side")
			obstacle.queue_free()
			await settle()
		else:
			obstacle.queue_free()
			await settle(0.85)
			check(door.fraction > 0.99 and not door.blocked, "continues when obstacle removed layer=" + str(layer))
			check(door.try_toggle(world.player), "closes after obstacle removal")
			await settle(0.85)
			check(door.fraction < 0.01, "closed after obstacle tests")
	# A blocked first step can be cancelled without remaining in a moving state.
	var initial_obstacle := StaticBody3D.new()
	initial_obstacle.collision_layer = 8
	initial_obstacle.collision_mask = 0
	world.add_child(initial_obstacle)
	initial_obstacle.global_position = entry + Vector3(0, 1, 0)
	var initial_shape := CollisionShape3D.new()
	var initial_box := BoxShape3D.new()
	initial_box.size = Vector3(0.2, 1.0, 0.2)
	initial_shape.shape = initial_box
	initial_obstacle.add_child(initial_shape)
	await settle()
	check(door.try_toggle(world.player), "initial obstruction accepts action")
	await settle()
	check(door.blocked and is_zero_approx(door.fraction), "initial obstruction blocks first step")
	check(door.try_toggle(world.player), "initial obstruction can cancel opening")
	await settle()
	check(not door.moving and not door.blocked and is_zero_approx(door.fraction), "cancel at rest completes")
	initial_obstacle.queue_free()
	await settle()
	await place(building.to_global(Vector3(-3.5, 0, 3.0)))
	check(Vector2(world.player.global_position.x-entry.x,world.player.global_position.z-entry.z).length() < 2.8, "LOS fixture within range")
	check(not door.can_interact(world.player), "nearby door cannot be used through side wall")
	# A solid side wall remains solid with the entrance open.
	await place(building.to_global(Vector3(2.35, building.record.floor_height, 0)))
	await walk(Vector2.RIGHT, 0.7)
	check(building.to_local(world.player.global_position).x < 2.7, "side wall blocks actor")
	check(not door.can_interact(world.player), "no interaction through wall / out of range")
	await place(building.to_global(Vector3(0.0, building.record.floor_height, -2.25)))
	await walk(Vector2.RIGHT, 0.7)
	check(building.to_local(world.player.global_position).x < 0.85, "bed blocks actor")
	# Held touch is released on focus loss, so returning cannot move automatically.
	await place(entry + Vector3(0, 0, 3.5))
	var up: Button = world.hud.get_node("RootControl/BottomLeft/DpadGrid/Up")
	await touch(up.get_global_rect().get_center(), true, 4)
	await settle(0.12)
	world._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	world._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await settle(0.3)
	check(world.player.velocity.length() < 0.02, "held touch cleared on focus return")
	await touch(up.get_global_rect().get_center(), false, 4)
	world._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(not world.is_input_available() and door.suspended, "application pause suspends interaction")
	await tap(world.picker)
	check(world.selected == 0, "application pause prevents scene selection")
	world._notification(NOTIFICATION_APPLICATION_RESUMED)
	check(world.is_input_available() and not door.suspended, "application resume restores controls")
	await place(entry + Vector3(0,0,2.5))
	check(door.can_interact(world.player), "pause fixture in reach")
	get_tree().paused = true
	check(not world.is_input_available(), "tree pause rejects interaction")
	world.interact()
	check(not door.moving, "paused interaction cannot start a swing")
	get_tree().paused = false
