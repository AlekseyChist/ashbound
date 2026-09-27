extends Node
## Codex acceptance: real playback plus phase/view/equipment transitions.
const Route := preload("res://scenes/world/forest_route.tscn")
const Bare := preload("res://assets/characters/courtyard/traveler_frames.tres")
const Pack := preload("res://assets/characters/courtyard/traveler_backpack_frames.tres")
var route: Node3D
var failures: Array[String] = []
var traces: Array[Dictionary] = []
var groups := 0

func _ready() -> void:
	Engine.max_fps = 120
	process_priority = 1000
	get_tree().create_timer(90).timeout.connect(func():
		push_error("SIDE_GAIT_TIMEOUT")
		get_tree().quit(1))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	route = Route.instantiate()
	add_child(route)
	await get_tree().create_timer(0.5).timeout
	for frames in [Bare, Pack]:
		for clip in [&"walk", &"walk_side", &"run_side"]:
			check(frames.get_frame_count(clip) == 8, "eight phases " + clip)
			check(frames.get_animation_loop(clip), "loop " + clip)
			check(frames.get_animation_speed(clip) == 15.0, "original pose rate " + clip)
			for i in range(8):
				var texture := frames.get_frame_texture(clip, i) as AtlasTexture
				check(texture != null, "atlas texture")
				if texture != null:
					check(texture.region == Rect2((i % 4) * 384, (i / 4) * 384, 384, 384), "ordered complete cell")
					check(texture.margin == Rect2() and texture.filter_clip, "no bounding-box rescale")
					check("side-gait-v1" in texture.atlas.resource_path, "new side atlas used")
				check(frames.get_frame_duration(clip, i) == 1.0, "original phase duration")
			groups += 1
	for packed in [false, true]:
		for running in [false, true]:
			for direction in [Vector2.RIGHT, Vector2.LEFT]:
				await _playback(packed, running, direction)
	await _transitions()
	await _capture_poses()
	var result := {"platform": OS.get_name(), "groups": groups, "traces": traces, "failures": failures}
	var file := FileAccess.open("user://side-gait-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	if failures.is_empty():
		print("ASHBOUND_SIDE_GAIT_OK groups=%d" % groups)
	else:
		for error in failures:
			push_error("SIDE_GAIT_FAIL " + error)
	get_tree().quit(0 if failures.is_empty() else 1)

func _playback(packed: bool, running: bool, direction: Vector2) -> void:
	route.reset_route()
	var visual: Node3D = route.player.get_node("Visual")
	var body: AnimatedSprite3D = visual.get_node("Body")
	visual.set_appearance_frames(Pack if packed else Bare)
	route.player.set_run_input(running)
	route.player.set_move_input(direction)
	await get_tree().create_timer(0.25).timeout
	body.play()
	var seen: Array[int] = []
	var transitions: Array[int] = []
	var last := -1
	var wraps := 0
	var label := ("pack" if packed else "bare") + ("-run" if running else "-walk") + ("-right" if direction.x > 0 else "-left")
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1200:
		await get_tree().process_frame
		check(body.animation == (&"run_side" if running else &"walk_side"), label + " side clip remains active")
		if body.frame != last:
			if last >= 0:
				check(body.frame == (last + 1) % 8, label + " no skipped/restarted phase")
				if last == 7 and body.frame == 0:
					wraps += 1
			last = body.frame
			transitions.append(last)
			if not seen.has(last):
				seen.append(last)
	check(seen.size() == 8 and wraps >= 1, label + " both steps and wrap actually played")
	check(absf(Vector2(route.player.velocity.x, route.player.velocity.z).length() - (6.4 if running else 4.2)) < 0.05, label + " movement unchanged")
	traces.append({"case": label, "seen": seen, "sequence": transitions, "wraps": wraps})
	groups += 1
	route.player.stop_input()

func _transitions() -> void:
	route.reset_route()
	route.player.set_physics_process(false)
	var visual: Node3D = route.player.get_node("Visual")
	var body: AnimatedSprite3D = visual.get_node("Body")
	for action in [&"walk", &"run"]:
		visual.update_visual(action, Vector3.RIGHT)
		for i in range(8):
			body.pause()
			body.set_frame_and_progress(i, 0.4)
			visual.set_appearance_frames(Pack)
			check(body.frame == i and is_equal_approx(body.frame_progress, 0.4) and not body.is_playing(), "equipping preserves paused phase")
			visual.update_visual(action, Vector3.LEFT)
			check(body.frame == i and is_equal_approx(body.frame_progress, 0.4), "left view preserves phase")
			visual.update_visual(action, Vector3.FORWARD)
			check(body.frame == i and is_equal_approx(body.frame_progress, 0.4), "back view preserves phase")
			visual.update_visual(action, Vector3.RIGHT)
			visual.set_appearance_frames(Bare)
			check(body.frame == i and is_equal_approx(body.frame_progress, 0.4), "return side/bare preserves phase")
		groups += 1
	route.player.set_physics_process(true)
	route.reset_route()
	body.play()

func _capture_poses() -> void:
	# Readback/PNG encoding is intentionally outside real-time playback sampling.
	if DisplayServer.get_name() == "headless":
		return
	route.reset_route()
	route.player.set_physics_process(false)
	var visual: Node3D = route.player.get_node("Visual")
	var body: AnimatedSprite3D = visual.get_node("Body")
	for packed in [false, true]:
		visual.set_appearance_frames(Pack if packed else Bare)
		for action in [&"walk", &"run"]:
			for facing in [Vector3.RIGHT, Vector3.LEFT]:
				visual.update_visual(action, facing)
				body.pause()
				var label := ("pack" if packed else "bare") + "-" + String(action) + ("-right" if facing.x > 0 else "-left")
				for i in [0, 2, 4, 6]:
					body.set_frame_and_progress(i, 0.0)
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("user://gait-%s-%d.png" % [label, i])
	route.player.set_physics_process(true)
