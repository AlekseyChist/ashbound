extends Node
## Coordinator QA: tests the real actor, camera and collision, not worker assertions.
const WorldScene = preload("res://scenes/world/world_graybox.tscn")
const Geometry = preload("res://scripts/world/world_graybox_geometry.gd")
const Shapes = preload("res://scripts/world/world_graybox_shapes.gd")
var world: Node3D
var failures: Array[String] = []
var routes: Array[Dictionary] = []
var output := "user://world-graybox-qa"
var capture := false
var starter_cases := 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("WORLD_QA_FAIL ", message)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	capture = DisplayServer.get_name() != "headless"
	if args.has("--output"):
		output = args[args.find("--output") + 1]
	DirAccess.make_dir_recursive_absolute(output)
	world = WorldScene.instantiate()
	add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(world.terrain.get_child_count() == 100, "100 terrain chunks")
	check(world.player.get_node("Visual/Body").sprite_frames == world.AcceptedFrames, "accepted hero resource")
	await _geometry_fixture()
	await _surfaces_and_ui()
	await _headwaters()
	await _starter_region()
	if not args.has("--screens-only") and not ProjectSettings.get_setting("ashbound/qa/screens_only", false):
		await _cross_road()
		await _routes()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	world.set_overview(true)
	world.reset_overview()
	var touch := InputEventScreenTouch.new()
	touch.index = 7
	touch.pressed = true
	world._unhandled_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 7
	drag.relative = Vector2(100, 0)
	world._input(drag)
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	world._unhandled_input(mouse)
	var motion := InputEventMouseMotion.new()
	motion.device = InputEvent.DEVICE_ID_EMULATION
	motion.relative = Vector2(100, 0)
	world._input(motion)
	check(is_equal_approx(world.overview_yaw, -0.5) and not world.mouse_drag, "one rotation per touch, emulated mouse ignored")
	touch.pressed = false
	world._input(touch)
	check(world.drag_touch == -1, "touch release over UI clears orbit")
	world.reset_overview()
	await _screenshot("overview-final")
	var report := {"failures": failures, "routes": routes, "starter_cases": starter_cases, "platform": OS.get_name(), "rendering": RenderingServer.get_current_rendering_method(), "version": world.layout.version}
	var f := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("WORLD_GRAYBOX_QA_COMPLETE failures=%d routes=%d output=%s" % [failures.size(), routes.size(), ProjectSettings.globalize_path(output)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _ray(x: float, z: float, top: float = 900) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -80, z), 1)
	return world.get_world_3d().direct_space_state.intersect_ray(q)

func _starter_region() -> void:
	var region: Node3D = world.get_node("StarterRegion")
	var forest: Node3D = region.get_node("Forest")
	check(region.get_child_count() == 6 and not world.has_node("start_hamlet"), "five houses replace old hamlet")
	check(forest.get_child_count() == 4, "three forest batches plus trunk collider body")
	for name in ["Trunks", "LowerCrowns", "UpperCrowns"]:
		var batch: MultiMeshInstance3D = forest.get_node(name)
		check(batch.multimesh.instance_count == world.starter_layout.trees.size(), "complete batch " + name)
	var empty: Node3D = region.add_forest([])
	check(empty.get_child_count() == 0, "empty forest safe")
	empty.queue_free()
	await get_tree().physics_frame
	world.set_overview(false)
	for record in world.starter_layout.houses:
		var house: Node3D = region.get_node(record.id)
		var front := house.global_basis.z
		var center: Vector3 = house.global_position + Vector3.UP * (float(record.foundation) + 1.2)
		var from: Vector3 = center + front * (float(record.size[2]) * 0.5 + 2)
		var q := PhysicsRayQueryParameters3D.create(from, center, 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
		check(not hit.is_empty() and hit.collider == house.get_node("Collision"), "solid house " + str(record.id))
		# Extents of the roof must span the walls, meet at the ridge and remain close to the wall tops.
		for roof_name in ["RoofA", "RoofB"]:
			var roof: MeshInstance3D = house.get_node(roof_name)
			check(roof.mesh.size.x > float(record.size[0]) * 0.5, "roof spans half house")
			check(roof.position.y < float(record.foundation) + float(record.size[1]) + 2, "roof not floating")
		starter_cases += 1
	# Real actor approaches a wall, stops, then walks parallel beyond the corner.
	var first: Dictionary = world.starter_layout.houses[0]
	var house: Node3D = region.get_node(first.id)
	var front := house.global_basis.z
	var right := house.global_basis.x
	var start: Vector3 = house.position + front * (float(first.size[2])*0.5 + 3)
	start.y = world.ground_height(start.x, start.z) + .2
	await _place_actor(start)
	await _drive_direction(-front, 1.4)
	var local: Vector3 = house.to_local(world.player.global_position)
	check(local.z > float(first.size[2])*0.5+.2 and local.z < float(first.size[2])*0.5+.8, "actor stops at rotated house wall")
	await _drive_direction(right, 2.0)
	check(house.to_local(world.player.global_position).x > float(first.size[0])*0.5+1, "actor bypasses house corner")
	starter_cases += 1
	# Test an actual nearby trunk, including radius scaled with the mesh.
	var tree: Array = world.starter_layout.trees[0]
	var base := Vector3(tree[0], tree[1], tree[2])
	start = base + Vector3(0, 0, 2)
	start.y = world.ground_height(start.x, start.z) + .2
	await _place_actor(start)
	await _drive_direction(Vector3.FORWARD, 1.2)
	var distance := Vector2(world.player.position.x-base.x, world.player.position.z-base.z).length()
	check(distance > float(tree[3])*.28+.2 and distance < 1.0, "actor stops at scaled tree trunk")
	await _drive_direction(Vector3.RIGHT, .5)
	await _drive_direction(Vector3.FORWARD, 1.1)
	check(world.player.position.z < base.z-1, "actor can go around tree")
	starter_cases += 1
	world.select_city(4)
	await _screenshot("starter-hamlet")
	# Local overhead inspection of the entire district; no production camera behavior changes.
	world.set_overview(true)
	world.overview_center = Vector3(-755, 65, 285)
	world.overview_distance = 560
	world._update_overview_camera()
	await _screenshot("starter-district")
	world.set_overview(false)
	for location in [10, 8]:
		world.select_city(location)
		world.camera_rig.rotate_view(Vector2(PI / world.camera_rig.mouse_sensitivity, 0))
		world.camera_rig.snap_to_target()
		await _screenshot("starter-place-" + str(location+1))
	if capture:
		world.select_city(4)
		var trail: Dictionary
		for road in world.layout.roads:
			if road.id == "start_trail": trail = road
		var points: PackedVector3Array = world.points_of(trail)
		var middle := int(points.size() * .65)
		await _place_actor(points[middle] + Vector3.UP * .2)
		var direction := (points[middle-1] - points[middle]).normalized()
		direction.y = 0
		direction = direction.normalized()
		var yaw := atan2(-direction.x, -direction.z)
		world.camera_rig.rotate_view(Vector2(-yaw / world.camera_rig.mouse_sensitivity, 0))
		world.camera_rig.snap_to_target()
		for i in range(6):
			world.player.set_run_input(true)
			await _drive_direction(direction, .3, false)
			await _screenshot("starter-motion-" + str(i))
		world.player.stop_input()
	world.reset_overview()
	print("WORLD_STARTER_COMPLETE cases=%d trees=%d" % [starter_cases, world.starter_layout.trees.size()])

func _place_actor(position: Vector3) -> void:
	world.player.stop_input()
	world.player.position = position
	world.player.velocity = Vector3.ZERO
	world.camera_rig.reset_view()
	for i in range(20): await get_tree().physics_frame

func _drive_direction(direction: Vector3, seconds: float, stop_after: bool = true) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		var cam: Camera3D = world.camera_rig.get_camera()
		var right := Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
		var back := Vector3(cam.global_basis.z.x, 0, cam.global_basis.z.z).normalized()
		world.player.set_move_input(Vector2(direction.dot(right), direction.dot(back)))
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	if stop_after: world.player.stop_input()

func _geometry_fixture() -> void:
	var g := Geometry.new()
	g.position = Vector3(4000, 0, 4000)
	world.add_child(g)
	var h := PackedFloat32Array()
	var colors := PackedColorArray()
	for z in range(43):
		for x in range(43):
			h.append(float(x) * 0.2 + float(z) * 0.1)
			colors.append(Color.WHITE)
	g.build(h, colors, 43, 1.0)
	check(g.get_child_count() == 4, "partial terrain chunks")
	await get_tree().physics_frame
	for x in [0.25, 18.99, 19.01, 20.8]:
		var hit := _ray(4000 + x, 4000.25)
		check(not hit.is_empty(), "terrain fixture ray")
		if not hit.is_empty(): check(absf(hit.position.y - ((x + 21) * 0.2 + 21.25 * 0.1)) < 0.005, "seam collision matches height")
	g.build(h, colors, 43, 1.0)
	check(g.get_child_count() == 4, "repeat build replaces chunks")
	var s := Shapes.new()
	s.position = Vector3(5000, 0, 5000)
	world.add_child(s)
	s.add_strip(PackedVector3Array([Vector3(0, 10, 0), Vector3(10, 12, 0)]), 4, Color.WHITE, true)
	s.add_strip(PackedVector3Array([Vector3(20, 10, 0), Vector3(20, 12, 10)]), 4, Color.WHITE, true)
	s.add_strip(PackedVector3Array([Vector3(40, 10, 0), Vector3(40, 12, 10)]), 4, Color.WHITE, false)
	s.add_band(PackedVector3Array([Vector3(60, 10, 0), Vector3(60, 12, 10)]), PackedVector3Array([Vector3(64, 8, 0), Vector3(64, 10, 10)]), Color.WHITE, true)
	await get_tree().physics_frame
	for p in [Vector3(5005, 11, 5000), Vector3(5020, 11, 5005)]:
		var hit := _ray(p.x, p.z)
		check(not hit.is_empty(), "strip facing upward and collidable")
		if not hit.is_empty(): check(absf(hit.position.y - p.y) < 0.005, "strip exact height, no extra lift")
	check(_ray(5040, 5005).is_empty(), "water strip has no collision")
	var band_hit := _ray(5062, 5005)
	check(not band_hit.is_empty(), "sloped band collision")
	if not band_hit.is_empty(): check(absf(band_hit.position.y - 10) < 0.005, "sloped band exact vertices")
	g.queue_free()
	s.queue_free()
	await get_tree().physics_frame

func _surfaces_and_ui() -> void:
	for x in [-973.3, -800.3, -200.3, 150.3, 600.3, 987.3]:
		for z in [-973.7, -600.7, -100.7, 400.7, 975.7]:
			var hit := _ray(x, z)
			check(not hit.is_empty(), "terrain collision coverage")
			if not hit.is_empty(): check(hit.position.y + 0.01 >= world.ground_height(x, z), "visible terrain not above collision")
	# Check every sampled road center, including all bridge approaches and shared junctions.
	for road in world.layout.roads:
		for p in world.points_of(road):
			var hit := _ray(p.x, p.z)
			if hit.is_empty() or absf(hit.position.y - p.y) > 0.4:
				check(false, "road surface mismatch %s at %s actual=%s" % [road.id, p, hit.get("position", Vector3.INF)])
				break
	for language in ["en", "ru"]:
		Localization.set_language(language)
		await get_tree().process_frame
		check(not world.mode_button.text.begins_with("WORLD_"), "translated mode button")
		check(world.mode_button.theme == null and world.hud.get_node("RootControl").theme == preload("res://assets/ui/ashbound_ui.tres"), "shared UI theme")
		var bounds: Rect2 = world.hud.get_node("RootControl").get_global_rect()
		for control in [world.mode_button, world.city_picker, world.language_button, world.hud.get_node("RootControl/TopRightPanel/RestartButton")]:
			check(bounds.encloses(control.get_global_rect()), "toolbar within safe area " + language)
		await _screenshot("overview-" + language)
	check(world.locations.size() == 16, "four cities, ten exploration sites and two headwaters")
	for site in world.layout.sites:
		if site.kind != "lake" and site.kind != "spring_cave":
			var path := "StarterRegion" if site.id == "start_hamlet" else str(site.id)
			check(world.has_node(NodePath(path)), "landmark exists " + str(site.id))
		check(not str(Localization.text(site.key)).begins_with("WORLD_"), "translated site " + str(site.id))
	for river in world.layout.rivers:
		var river_mesh: MeshInstance3D = world.shapes.get_node(NodePath(river.id))
		var vertices: PackedVector3Array = river_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var actual_width := vertices[0].distance_to(vertices[1])
		check(absf(actual_width - (2.0 if river.id == "east" else 12.0)) < 0.01, "visible upstream water width " + str(river.id))
		check(absf(vertices[-2].distance_to(vertices[-1]) - 12.0) < 0.01, "water widens into lowlands " + str(river.id))
	for city in range(world.locations.size()):
		world.select_city(city)
		world.set_overview(false)
		await get_tree().create_timer(0.3).timeout
		check(world.player.is_on_floor(), "city grounded " + str(city))
		await _screenshot("city-" + str(city))
	world.show_locations(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var bounds: Rect2 = world.hud.get_node("RootControl").get_global_rect()
	check(bounds.encloses(world.locations_panel.get_global_rect()) and world.location_buttons.size() == 16, "bounded scrollable location picker")
	check(not world.player.input_enabled and not world.camera_rig.input_enabled, "location chooser owns input")
	world.locations_scroll.ensure_control_visible(world.location_buttons[-1])
	await get_tree().process_frame
	check(world.locations_scroll.get_global_rect().intersects(world.location_buttons[-1].get_global_rect()), "last destination visible after scroll")
	await _screenshot("locations-popup")
	world.location_buttons[-1].pressed.emit()
	check(world.selected_city == 15 and not world.locations_overlay.visible, "last destination selection closes chooser")
	await _location_gestures()
	world.player.set_run_input(true)
	world.player.set_move_input(Vector2(1, 0))
	world.set_overview(true)
	check(not world.player.input_enabled and world.player._touch_move == Vector2.ZERO and not world.player._touch_run, "mode clears movement/run")
	world.nav_input = Vector2.ONE
	world.drag_touch = 4
	world._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(world.nav_input == Vector2.ZERO and world.drag_touch == -1 and not world.focused, "focus loss cancels overview input")
	world._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	world.zoom_overview(0.00001)
	check(world.overview_distance == 180, "minimum zoom")
	world.zoom_overview(10000)
	check(world.overview_distance == 3000, "maximum zoom")
	world.reset_overview()

func _headwaters() -> void:
	var lake: MeshInstance3D = world.get_node("Headwaters/mountain_lake")
	var arrays: Array = lake.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check(vertices.size() == 97 and indices.size() == 288, "closed lake fan")
	for v in vertices:
		check(is_equal_approx(v.y, 260.0), "lake surface level")
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		check((b - a).cross(c - a).y < 0, "lake clockwise facing")
	var lake_bottom := _ray(-670, -640)
	check(not lake_bottom.is_empty() and lake_bottom.position.y < 255, "lake has bed, not water collision")
	var bank := _ray(-575, -660)
	check(not bank.is_empty() and bank.position.y > 262, "lake arrival on dry bank")
	var portal: Node3D = world.get_node("Headwaters/desert_spring")
	var spring: Dictionary = world.layout.springs[0]
	var river: Dictionary = world.layout.rivers.filter(func(r: Dictionary): return r.id == "east")[0]
	var source: Vector3 = world.points_of(river)[0]
	var local_source := portal.to_local(source)
	check(absf(local_source.x) < 0.05 and absf(local_source.z + 9) < 0.05 and absf(local_source.y - 1) < 0.05, "stream begins inside portal")
	check(not spring.interior_implemented, "spring interior remains a plan")
	for index in [14, 15]:
		world.select_city(index)
		world.set_overview(true)
		world.overview_center = Vector3(-670, 260, -640) if index == 14 else Vector3(350, 210, -460)
		world.overview_distance = 320.0 if index == 14 else 160.0
		world.overview_yaw = 0.0 if index == 14 else 0.55
		world.overview_pitch = deg_to_rad(48.0)
		await get_tree().process_frame
		await _screenshot("headwater-" + str(index))
	world.reset_overview()

func _location_gestures() -> void:
	world.select_city(4)
	world.show_locations(true)
	world.locations_scroll.scroll_vertical = 0
	await get_tree().process_frame
	var touch := InputEventScreenTouch.new()
	touch.index = 17
	touch.pressed = true
	touch.position = world.locations_scroll.get_global_rect().get_center() + Vector2(0, 100)
	world._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 17
	drag.position = touch.position - Vector2(0, 220)
	drag.relative = Vector2(0, -220)
	world._input(drag)
	touch.position = drag.position
	touch.pressed = false
	world._input(touch)
	check(world.locations_scroll.scroll_vertical >= 200, "finger drag scrolls choices")
	check(world.selected_city == 4 and world.locations_overlay.visible, "drag does not choose a destination")
	check(not world.hud.is_processing_input(), "modal suspends shared HUD touch dispatcher")
	# Outside tap over the Run area closes without toggling the control underneath.
	touch.position = world.hud.get_node("RootControl/BottomRight").get_global_rect().get_center()
	touch.pressed = true
	world._input(touch)
	check(world.locations_overlay.visible, "outside press does not fall through")
	touch.pressed = false
	world._input(touch)
	check(not world.locations_overlay.visible and not world.player._touch_run, "outside release closes without run")
	world.show_locations(true)
	world.locations_scroll.ensure_control_visible(world.location_buttons[-1])
	await get_tree().process_frame
	touch.position = world.location_buttons[-1].get_global_rect().get_center()
	touch.pressed = true
	world._input(touch)
	touch.pressed = false
	world._input(touch)
	check(world.selected_city == 15 and not world.locations_overlay.visible and world.hud.is_processing_input(), "finger tap chooses last place and restores HUD")
	world.show_locations(true)
	world._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(world.location_touch == -1 and not world.locations_overlay.visible, "focus loss closes modal gesture")
	world._notification(NOTIFICATION_APPLICATION_FOCUS_IN)

func _cross_road() -> void:
	world.set_overview(false)
	var points: PackedVector3Array = world.points_of(world.layout.roads[4])
	var i := int(points.size() / 2)
	var center := points[i]
	var along := points[i + 1] - points[i - 1]
	var across := Vector3(-along.z, 0, along.x).normalized()
	for side in [-1.0, 1.0]:
		var start: Vector3 = center + across * 14 * side
		var goal: Vector3 = center - across * 14 * side
		start.y = world.ground_height(start.x, start.z) + 0.3
		world.player.position = start
		world.player.velocity = Vector3.ZERO
		world.camera_rig.reset_view()
		var elapsed := 0.0
		while elapsed < 12:
			var direction := Vector3(goal.x - world.player.position.x, 0, goal.z - world.player.position.z)
			if direction.length() < 0.5: break
			direction = direction.normalized()
			world.player.set_move_input(Vector2(direction.x, direction.z))
			await get_tree().physics_frame
			elapsed += get_physics_process_delta_time()
		world.player.stop_input()
		check(Vector2(goal.x - world.player.position.x, goal.z - world.player.position.z).length() < 0.5, "walk across both road shoulders " + str(side))
	print("WORLD_SHOULDERS_COMPLETE")

func _routes() -> void:
	# 10x game time, 120 Hz engine -> physical motion steps <= 1/12 s.
	# Real CharacterBody3D/input/gravity/colliders remain in control; no teleport between waypoints.
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 10.0
	world.set_overview(false)
	for road in world.layout.roads:
		for reverse in [false, true]:
			var points: PackedVector3Array = world.points_of(road)
			if reverse: points.reverse()
			var length := 0.0
			for i in range(1, points.size()): length += points[i].distance_to(points[i - 1])
			world.player.stop_input()
			world.player.position = points[0] + Vector3.UP * 0.25
			world.player.velocity = Vector3.ZERO
			world.camera_rig.reset_view()
			for i in range(12): await get_tree().physics_frame
			world.player.set_run_input(true)
			var target := 1
			var elapsed := 0.0
			var max_gap := 0.0
			var last_pos: Vector3 = world.player.position
			var stuck := 0.0
			var grounded := 0
			var steps := 0
			while target < points.size() and elapsed < length / 6.4 * 1.6 + 20 and stuck < 6:
				var p: Vector3 = world.player.position
				var delta_pos := Vector3(points[target].x - p.x, 0, points[target].z - p.z)
				if delta_pos.length() < 0.7:
					target += 1
					continue
				var direction := delta_pos.normalized()
				var cam: Camera3D = world.camera_rig.get_camera()
				var right := Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
				var back := Vector3(cam.global_basis.z.x, 0, cam.global_basis.z.z).normalized()
				world.player.set_move_input(Vector2(direction.dot(right), direction.dot(back)))
				await get_tree().physics_frame
				var dt := get_physics_process_delta_time()
				elapsed += dt
				steps += 1
				if world.player.is_on_floor(): grounded += 1
				var hit := _ray(world.player.position.x, world.player.position.z)
				if not hit.is_empty(): max_gap = maxf(max_gap, absf(world.player.position.y - hit.position.y))
				if world.player.position.distance_to(last_pos) < 0.02: stuck += dt
				else: stuck = 0
				last_pos = world.player.position
			world.player.stop_input()
			var passed := target == points.size()
			check(passed, "route %s reverse=%s stopped at %d/%d %s" % [road.id, reverse, target, points.size(), world.player.position])
			check(max_gap < 1.1, "ground contact " + str(road.id))
			routes.append({"id": road.id, "reverse": reverse, "passed": passed, "length_m": length, "game_seconds": elapsed, "max_ground_gap": max_gap, "grounded_steps": grounded, "steps": steps})
			print("WORLD_ROUTE id=%s reverse=%s pass=%s target=%d/%d seconds=%.1f gap=%.3f" % [road.id, reverse, passed, target, points.size(), elapsed, max_gap])
			if not passed: await _screenshot("failed-" + str(road.id) + str(reverse))

func _screenshot(name: String) -> void:
	if not capture: return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
