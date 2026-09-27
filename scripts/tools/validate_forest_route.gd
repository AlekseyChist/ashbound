extends Node
## Coordinator QA: real controller + physics, never teleport during a measured leg.
const Scene := preload("res://scenes/world/forest_route.tscn")
const Layout := preload("res://scripts/world/forest_route_layout.gd")
var route: Node3D
var failures: Array[String] = []
var groups := 0
var journeys: Array[Dictionary] = []
var frame_ms: Array[float] = []
var measure_frames := false
var last_progress := 0
var max_draw_calls := 0
var max_primitives := 0

func _ready() -> void:
	get_tree().create_timer(720.0).timeout.connect(func():
		push_error("FOREST_QA_TIMEOUT groups=%d" % groups)
		get_tree().quit(1))
	call_deferred("_run")

func _process(delta: float) -> void:
	if measure_frames and DisplayServer.get_name() != "headless":
		frame_ms.append(delta * 1000.0)
		max_draw_calls = maxi(max_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		max_primitives = maxi(max_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))

func _run() -> void:
	route = Scene.instantiate()
	add_child(route)
	await _frames(30)
	_check(route.player != null and route.camera_rig != null and route.hud != null, "required integration nodes")
	_check(is_equal_approx(route.player.move_speed, 4.2) and is_equal_approx(route.player.run_speed, 6.4), "original movement speeds")
	_check(Layout.length_of(Layout.main_path()) >= 600 and Layout.length_of(Layout.main_path()) <= 800, "600..800 metre main route")
	for part in ["Ground", "Forest", "Rocks", "Bridge", "River", "Outskirts", "CityVista"]:
		_check(route.terrain.has_node(part), "missing geometry group " + part)
	_group("scene")

	for path in [Layout.main_path(), Layout.loop_path()]:
		for i in range(1, path.size()):
			var a: Vector3 = path[i - 1]
			var b: Vector3 = path[i]
			var steps := ceili(a.distance_to(b) / 2.0)
			for step in range(steps + 1):
				var p := a.lerp(b, float(step) / steps)
				var hit := _ray(p + Vector3.UP * 5, p - Vector3.UP * 5)
				_check(not hit.is_empty(), "floor missing " + str(p))
				if not hit.is_empty():
					_check(absf(hit.position.y - p.y) < 1.5 and hit.normal.y > 0.7, "walkable floor " + str(p))
	_group("floor coverage every 2 metres")
	var deck := _ray(Vector3(35, 8, -324), Vector3(35, -6, -324))
	var channel := _ray(Vector3(49, 8, -324), Vector3(49, -6, -324))
	_check(not deck.is_empty() and absf(deck.position.y - 3.0) < 0.06, "bridge deck matches banks")
	_check(not channel.is_empty() and channel.position.y < -1.0, "river channel below visible water")
	for x in [30.0, 40.0]:
		_check(not _ray(Vector3(35, 3.6, -324), Vector3(x, 3.6, -324)).is_empty(), "bridge side rail collision")
	_group("bridge boundaries")
	await _input_and_locale()
	_group("touch, camera, focus, localization")
	if not failures.is_empty():
		_finish()
		return

	route.reset_route()
	await _frames(10)
	await _capture("start")
	measure_frames = true
	var main := Layout.main_path()
	var walked := await _travel(main, false, "main-walk", true)
	_check(walked and route.reached_lookout, "continuous main walk reaches lookout")
	_group("main walk")
	if not walked:
		_finish()
		return
	var back := main.duplicate()
	back.reverse()
	_check(await _travel(back, true, "main-return", false), "continuous run returns on main road")
	_group("main return")

	var loop := Layout.loop_path()
	var branch := PackedVector3Array([main[0], main[1], main[2]])
	for i in range(1, loop.size()):
		branch.append(loop[i])
	for i in range(loop.size() - 2, -1, -1):
		branch.append(loop[i])
	branch.append(main[1])
	branch.append(main[0])
	_check(await _travel(branch, true, "branch-both-ways", false), "continuous branch both ways and return")
	_group("branch loop")
	measure_frames = false
	route.hud._set_run_mode(true, true)
	route.player.set_move_input(Vector2.UP)
	route.reset_route()
	await _frames(30)
	_check(route.player.position.distance_to(Vector3.ZERO) < 0.2, "reset at original ground")
	_check(route.player._touch_move == Vector2.ZERO and not route.player._touch_run, "reset clears movement/run")
	_check(not route.reached_lookout, "reset clears route completion")
	await _capture("reset")
	_group("reset")
	_finish()

func _travel(points: PackedVector3Array, running: bool, id: String, capture: bool) -> bool:
	var started := Time.get_ticks_msec()
	var simulation := 0.0
	var distance := 0.0
	var old: Vector3 = route.player.position
	route.player.set_run_input(running)
	for i in range(1, points.size()):
		var target := points[i]
		var allowance := points[i - 1].distance_to(target) / (6.4 if running else 4.2) * 1.6 + 5.0
		var segment_time := 0.0
		while Vector2(route.player.position.x, route.player.position.z).distance_to(Vector2(target.x, target.z)) > 0.35:
			var dir: Vector3 = (target - route.player.position)
			dir.y = 0
			dir = dir.normalized()
			var desired_yaw := atan2(-dir.x, -dir.z)
			var yaw_delta := wrapf(desired_yaw - route.camera_rig.rotation.y, -PI, PI)
			route.camera_rig.rotate_view(Vector2(-yaw_delta * 0.08 / 0.003, 0))
			var basis: Basis = route.camera_rig.get_camera().global_basis
			var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
			var backward := Vector3(basis.z.x, 0, basis.z.z).normalized()
			route.player.set_move_input(Vector2(dir.dot(right), dir.dot(backward)))
			await get_tree().physics_frame
			var dt: float = get_physics_process_delta_time()
			segment_time += dt
			simulation += dt
			distance += route.player.position.distance_to(old)
			old = route.player.position
			if route.player.position.y < minf(points[i - 1].y, target.y) - 2.0 or segment_time > allowance:
				_check(false, "%s stuck/fell segment%d at%s time%.1f" % [id, i, route.player.position, segment_time])
				route.player.stop_input()
				return false
			if Time.get_ticks_msec() - last_progress > 30000:
				last_progress = Time.get_ticks_msec()
				print("FOREST_PROGRESS %s segment=%d distance=%.1f seconds=%.1f" % [id, i, distance, simulation])
		if capture and i in [1, 2, 5, 6, 8, 10]:
			await _capture("main-%02d" % i)
	route.player.set_move_input(Vector2.ZERO)
	route.player.set_run_input(false)
	await _frames(5)
	journeys.append({"id": id, "running": running, "travelled_m": distance, "simulation_seconds": simulation,
		"wall_seconds": (Time.get_ticks_msec() - started) / 1000.0, "end": str(route.player.position)})
	print("FOREST_JOURNEY " + JSON.stringify(journeys[-1]))
	return true

func _input_and_locale() -> void:
	for lang in ["ru", "en"]:
		_check(Localization.set_language(lang) == OK, "locale set " + lang)
		await _frames(3)
		var root: Control = route.hud.get_node("RootControl")
		var restart: Button = root.get_node("TopRightPanel/RestartButton")
		_check(restart.text == ("На исходную" if lang == "ru" else "Back to start"), "translated reset")
		var safe := Rect2(root.global_position, root.size)
		var geometry: Dictionary = {}
		for button in [restart, root.get_node("BottomRight/VBox/RunButton"), root.get_node("BottomRight/VBox/AttackButton")]:
			_check(button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x < button.size.x - 24, "text fit " + button.name)
			_check(safe.encloses(button.get_global_rect()), "button within safe root " + button.name)
			var centre: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
			geometry[button.name] = [centre.x, centre.y]
		var controls: Array[Control] = [restart, root.get_node("BottomRight/VBox/RunButton"), root.get_node("BottomRight/VBox/AttackButton")]
		for name in ["Up", "Down", "Left", "Right"]:
			var arrow: Button = root.get_node("BottomLeft/DpadGrid/" + name)
			controls.append(arrow)
			_check(safe.encloses(arrow.get_global_rect()), "direction within safe root " + name)
			var centre := arrow.get_global_transform_with_canvas() * (arrow.size * 0.5)
			geometry[name] = [centre.x, centre.y]
		for i in range(controls.size()):
			for j in range(i + 1, controls.size()):
				_check(not controls[i].get_global_rect().intersects(controls[j].get_global_rect()), "controls do not overlap")
		FileAccess.open("user://forest-controls-" + lang + ".json", FileAccess.WRITE).store_string(JSON.stringify(geometry, "  "))
		await _capture("ui-" + lang)
	Localization.set_language("ru")
	var up: Button = route.hud.get_node("RootControl/BottomLeft/DpadGrid/Up")
	var p := up.get_global_transform_with_canvas() * (up.size * 0.5)
	_touch(10, p, true)
	await _frames(30)
	_check(route.player.position.z < -1.0, "real HUD moves player")
	_touch(10, p, false)
	route.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(4)
	_check(route.player._touch_move == Vector2.ZERO and not route.player._touch_run, "focus releases movement")
	route.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var yaw: float = route.camera_rig.rotation.y
	var look_point := get_viewport().get_visible_rect().size * Vector2(0.60, 0.32)
	_touch(11, look_point, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 11
	drag.position = look_point + Vector2(100, 0)
	drag.relative = Vector2(100, 0)
	get_viewport().push_input(drag, true)
	_touch(11, look_point + Vector2(100, 0), false)
	_check(not is_equal_approx(yaw, route.camera_rig.rotation.y), "empty world touch rotates camera")

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	return route.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1))

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func _capture(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png("user://forest-" + id + ".png")
	_check(error == OK, "capture " + id)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("FOREST_FAIL: " + label)

func _group(label: String) -> void:
	groups += 1
	print("FOREST_GROUP %d %s" % [groups, label])

func _finish() -> void:
	var stats := {"renderer": DisplayServer.get_name(), "os": OS.get_name(), "samples": frame_ms.size(),
		"draw_calls_max": max_draw_calls, "primitives_max": max_primitives}
	if not frame_ms.is_empty():
		frame_ms.sort()
		stats["median_frame_ms"] = frame_ms[frame_ms.size() / 2]
		stats["p95_frame_ms"] = frame_ms[int(frame_ms.size() * 0.95)]
	var result := {"version": "0.19.0-forest-route", "groups": groups, "failures": failures, "journeys": journeys, "render": stats}
	FileAccess.open("user://forest-results.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	if failures.is_empty() and groups == 8:
		print("ASHBOUND_FOREST_ROUTE_OK groups=8")
		get_tree().quit(0)
	else:
		print("ASHBOUND_FOREST_ROUTE_FAILED groups=%d failures=%d" % [groups, failures.size()])
		get_tree().quit(1)
