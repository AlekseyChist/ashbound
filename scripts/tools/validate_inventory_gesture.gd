extends SceneTree

var level: Node
var player: Node
var visual: Node
var body: AnimatedSprite3D
var pocket: AnimatedSprite3D
var failures: Array[String] = []
var completed := 0
var finished_count := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("GESTURE_FAIL: " + message)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Actors/Player")
	visual = player.get_node("Visual")
	body = visual.get_node("Body")
	pocket = visual.get_node("PocketPose")
	visual.inventory_access_finished.connect(func(): finished_count += 1)
	await _frames(3)
	var atlas := Image.load_from_file("res://assets/characters/courtyard/traveler-pocket-v1.png")
	_check(atlas.get_pixel(0, 0).a == 0.0, "atlas has transparent background")
	for view in ["back", "front", "side"]:
		var clip := StringName("pocket_" + view)
		var frames := pocket.sprite_frames
		_check(frames.has_animation(clip), "view exists " + view)
		_check(frames.get_frame_count(clip) == 4, "four drawn poses " + view)
		_check(not frames.get_animation_loop(clip), "one-shot " + view)
		for i in range(frames.get_frame_count(clip)):
			var texture := frames.get_frame_texture(clip, i)
			_check(texture is AtlasTexture, "frame is atlas texture")
			if not texture is AtlasTexture:
				continue
			_check(texture.filter_clip, "atlas sampling stays inside the selected pose")
			_check(texture.get_size().is_equal_approx(Vector2(512, 512)), "stable virtual canvas")
			_check(texture.region.size.x > 80 and texture.region.size.y > 300, "full-body region")
			_check(is_equal_approx(texture.margin.position.y + texture.region.size.y, 496), "same ground baseline")
	completed += 1

	_check(visual.begin_inventory_access(), "gesture starts")
	_check(not visual.begin_inventory_access(), "duplicate start rejected")
	_check(not body.visible and pocket.visible, "drawn pocket pose replaces normal sprite")
	_check(finished_count == 0 and pocket.frame == 0, "no immediate completion")
	await _frames(8)
	_check(finished_count == 0, "window cannot open before gesture")
	await _frames(65)
	_check(finished_count == 1 and pocket.frame == 3, "completion occurs once after final pose")
	_check(visual.is_inventory_access_active(), "final pose held for menu")
	await _frames(60)
	_check(finished_count == 1 and pocket.frame == 3, "no repeated completion while held")
	completed += 1

	for direction in [Vector3(0,0,1), Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,0,-1)]:
		player.facing_direction = direction
		await _frames(3)
		_check(pocket.frame == 3 and not pocket.is_playing(), "view change preserves held final pose")
		_check(finished_count == 1, "view change does not re-complete")
		var view_key := "side" if visual.get_visual_direction() in [&"left", &"right"] else str(visual.get_visual_direction())
		_check(pocket.animation == StringName("pocket_" + view_key), "camera-relative pocket direction")
		_check(pocket.flip_h == (visual.get_visual_direction() == &"left"), "side mirror")
		_check(abs(pocket.position.y - 240 * pocket.pixel_size) < 0.0001, "feet anchored in world")
	visual.end_inventory_access()
	_check(body.visible and not pocket.visible and not visual.is_inventory_access_active(), "close restores normal body")
	completed += 1

	_check(visual.begin_inventory_access(), "second gesture starts")
	await _frames(6)
	visual.end_inventory_access()
	visual.end_inventory_access()
	await _frames(70)
	_check(finished_count == 1, "cancel never produces a late completion")
	_check(body.visible and not pocket.visible, "cancel remains closed")
	completed += 1

	_check(visual.begin_inventory_access(), "pause case starts")
	await _frames(8)
	pocket.pause()
	await _frames(55)
	_check(finished_count == 1, "pausing midway is not animation completion")
	_check(pocket.frame < 3, "paused gesture not forced to last frame")
	pocket.play()
	await _frames(65)
	_check(finished_count == 2, "resumed gesture completes once")
	visual.end_inventory_access()
	completed += 1

	var old_frames := pocket.sprite_frames
	pocket.sprite_frames = SpriteFrames.new()
	_check(not visual.begin_inventory_access(), "missing gesture fails closed")
	_check(not visual.is_inventory_access_active() and body.visible and not pocket.visible, "bad resource leaves presentation untouched")
	pocket.sprite_frames = old_frames
	completed += 1

	var looping: SpriteFrames = old_frames.duplicate()
	looping.set_animation_loop(&"pocket_front", true)
	pocket.sprite_frames = looping
	_check(not visual.begin_inventory_access(), "looping gesture rejected before locking controls")
	visual.end_inventory_access()
	pocket.sprite_frames = old_frames
	completed += 1

	_check(completed == 7, "all seven groups completed")
	level.queue_free()
	await process_frame
	if failures.is_empty():
		print("ASHBOUND_INVENTORY_GESTURE_OK groups=7")
		quit(0)
	else:
		printerr("ASHBOUND_INVENTORY_GESTURE_FAILED groups=%d failures=%d" % [completed, failures.size()])
		quit(1)
