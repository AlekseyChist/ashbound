extends Node
## Codex QA of the staged playable preview, not a replacement for owner art review.
const Route = preload("res://scenes/world/forest_route.tscn")
var failures: Array[String] = []
var traces: Array[Dictionary] = []

func _ready() -> void:
	Engine.max_fps = 60
	get_tree().create_timer(45).timeout.connect(func():
		push_error("WALK_PHONE_TIMEOUT")
		get_tree().quit(1))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	var route = Route.instantiate()
	add_child(route)
	await get_tree().create_timer(0.5).timeout
	var body: AnimatedSprite3D = route.player.get_node("Visual/Body")
	var frames := body.sprite_frames
	for clip in [&"walk", &"walk_side"]:
		check(frames.get_frame_count(clip) == 8, "eight walk poses")
		for i in range(8):
			var tex: AtlasTexture = frames.get_frame_texture(clip, i)
			check(tex.atlas.resource_path.ends_with("walk-phone-preview/walk.png"), "new walking atlas")
			check(tex.region == Rect2(i % 4 * 384, i / 4 * 384, 384, 384), "pose order")
	for running in [false, true]:
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			route.reset_route()
			route.player.set_run_input(running)
			route.player.set_move_input(direction)
			await get_tree().create_timer(0.3).timeout
			var side: bool = direction.x != 0
			var action := "run" if running else "walk"
			var view := "side" if side else ("back" if direction.y < 0 else "front")
			check(String(body.animation) == action + "_" + view, "runtime selected clip " + action + view)
			var expected: float = {"side": 0.00593080724876441, "back": 0.0059900166389351, "front": 0.00577849117174959}[view]
			if side:
				expected = 0.00533772652388796 * 0.9 if running else expected * 0.95
			check(is_equal_approx(body.pixel_size, expected), "selected presentation scale " + action + view)
			check(is_equal_approx(body.position.y, 182.0 * expected), "ground anchor")
			check(body.flip_h == (direction.x < 0), "left/right orientation")
			var seen: Array[int] = []
			var transitions: Array[int] = []
			var last := -1
			var wraps := 0
			var start := Time.get_ticks_msec()
			while Time.get_ticks_msec() - start < 1300:
				await get_tree().process_frame
				if body.frame != last:
					if last >= 0:
						check(body.frame == (last + 1) % frames.get_frame_count(body.animation), "phase continuity")
						if body.frame == 0:
							wraps += 1
					last = body.frame
					transitions.append(last)
					if not seen.has(last):
						seen.append(last)
			check(seen.size() == frames.get_frame_count(body.animation) and wraps >= 1, "complete cycle")
			check(absf(Vector2(route.player.velocity.x, route.player.velocity.z).length() - (6.4 if running else 4.2)) < 0.05, "unchanged movement speed")
			traces.append({"action": action, "view": view, "left": direction.x < 0, "seen": seen, "wraps": wraps, "scale": body.pixel_size, "sequence": transitions})
			route.player.stop_input()
			await get_tree().create_timer(0.2).timeout
			check(String(body.animation).begins_with("idle"), "stop returns idle")
			check(route.player.velocity.length() < 0.05, "stop removes velocity")
		route.reset_route()
		await get_tree().create_timer(0.2).timeout
		check(body.sprite_frames == frames, "reset preserves preview")
	check(traces.size() == 8, "all movement scenarios completed")
	var f := FileAccess.open("user://walk-phone-results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"platform": OS.get_name(), "traces": traces, "failures": failures}, "  "))
	f.close()
	for error in failures:
		push_error("WALK_PHONE_FAIL " + error)
	if failures.is_empty():
		print("ASHBOUND_WALK_PHONE_OK cases=8")
	get_tree().quit(0 if failures.is_empty() else 1)
