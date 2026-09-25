extends SceneTree
## Codex-owned independent checks for the isolated technique preview.
const DIR := "res://assets/characters/courtyard/fist-preview/"
const SOURCE := "res://assets/characters/courtyard/"
var errors: Array[String] = []
var groups := 0
var transitions := 0
var strikes := 0
var pairs: Dictionary = {}
var inv: Node
var player: Node
var visual: Node
var body: AnimatedSprite3D
var images: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("FIST_TECHNIQUES_FAIL: " + message)

func group(message: String) -> void:
	groups += 1
	print("FIST_GROUP %d %s" % [groups, message])

func phase() -> Array:
	return [body.animation, body.frame, body.frame_progress, body.is_playing(), body.speed_scale, body.flip_h, body.visible]

func alpha_bounds(image: Image) -> Rect2i:
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.2:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	return Rect2i(low, high - low + Vector2i.ONE) if high.x >= 0 else Rect2i()

func texture_bounds(texture: Texture2D) -> Rect2i:
	var atlas := texture as AtlasTexture
	if atlas == null:
		var image := texture.get_image()
		if image.is_compressed(): check(image.decompress() == OK, "decode QA image")
		return alpha_bounds(image)
	var path := atlas.atlas.resource_path
	if not images.has(path):
		var image := atlas.atlas.get_image()
		if image.is_compressed(): check(image.decompress() == OK, "decode QA atlas")
		images[path] = image
	var source: Image = images[path]
	var bounds := alpha_bounds(source.get_region(Rect2i(atlas.region)))
	bounds.position += Vector2i(atlas.margin.position)
	return bounds

func check_assets() -> void:
	var bare: SpriteFrames = load(SOURCE + "traveler_frames.tres")
	var pack: SpriteFrames = load(SOURCE + "traveler_backpack_frames.tres")
	for technique in ["novice", "trained"]:
		var variants: Array[SpriteFrames] = []
		for worn in [false, true]:
			var frames: SpriteFrames = load(DIR + technique + ("_pack" if worn else "") + "_frames.tres")
			check(frames != null, "resource exists " + technique + str(worn))
			if frames == null: continue
			variants.append(frames)
			var source: SpriteFrames = pack if worn else bare
			check(frames.get_meta("fist_preview_technique", "") == technique, "technique metadata")
			check(frames.get_meta("fist_preview_backpack", not worn) == worn, "backpack metadata")
			check(frames.get_animation_names() == source.get_animation_names(), "complete animation catalog")
			var alias: String = "attack" if technique == "novice" else "idle"
			for index in frames.get_frame_count(alias):
				var alias_tex := frames.get_frame_texture(alias, index) as AtlasTexture
				var side_tex := frames.get_frame_texture("attack_side", index if technique == "novice" else 0) as AtlasTexture
				check(alias_tex.atlas.resource_path == side_tex.atlas.resource_path and alias_tex.region == side_tex.region, "alias follows selected technique")
			for clip in source.get_animation_names():
				check(frames.has_animation(clip), "clip exists " + clip)
				if not frames.has_animation(clip): continue
				check(frames.get_frame_count(clip) == source.get_frame_count(clip), "count " + clip)
				check(frames.get_animation_speed(clip) == source.get_animation_speed(clip), "speed " + clip)
				check(frames.get_animation_loop(clip) == source.get_animation_loop(clip), "loop " + clip)
				for index in mini(frames.get_frame_count(clip), source.get_frame_count(clip)):
					var texture := frames.get_frame_texture(clip, index)
					check(texture != null, "texture " + clip)
					check(frames.get_frame_duration(clip, index) == source.get_frame_duration(clip, index), "duration " + clip)
					if clip.begins_with("walk") or clip.begins_with("run") or (technique == "trained" and clip.begins_with("attack")):
						var original := source.get_frame_texture(clip, index) as AtlasTexture
						var actual := texture as AtlasTexture
						check(actual != null and original != null and actual.atlas.resource_path == original.atlas.resource_path and actual.region == original.region and actual.margin == original.margin, "reused whole frame " + clip)
			for view in ["back", "front", "side"]:
				var clip: String = "attack_" + view
				if technique == "novice":
					var pixel: float = frames.get_meta("pixel_size_attack_" + view, 0.0)
					check(is_finite(pixel) and pixel > 0.002 and pixel < 0.01, "reasonable attack scale " + view)
					var grid_size := frames.get_frame_texture(clip, 0).get_size()
					check(float(frames.get_meta("baseline_offset_pixels_attack", 0)) == grid_size.y / 2.0, "feet baseline at virtual canvas bottom")
					for index in 4:
						var texture := frames.get_frame_texture(clip, index) as AtlasTexture
						check(texture != null, "attack is atlas")
						if texture == null: continue
						check(texture.atlas.resource_path == DIR + "novice-" + view + ("-pack" if worn else "") + ".png", "correct whole artwork " + view)
						var cell_size: Vector2 = texture.atlas.get_size() / 2.0
						var cell := Rect2(Vector2(index % 2, floori(float(index) / 2.0)) * cell_size, cell_size)
						check(cell.encloses(texture.region), "frame stays in its phase cell " + view + str(index))
						check(texture.get_size() == cell_size, "stable virtual canvas")
						var bounds := texture_bounds(texture)
						check(bounds.size.y > 300 and bounds.size.x > 70, "visible full character")
						check(abs(cell_size.y - bounds.end.y) <= 4, "soles anchored " + view + str(index))
					if not worn:
						var reference_height: float = texture_bounds(bare.get_frame_texture("idle_" + view, 0)).size.y * float(bare.get_meta("pixel_size_" + view))
						var actual_height: float = texture_bounds(frames.get_frame_texture(clip, 3)).size.y * pixel
						check(abs(reference_height - actual_height) < 0.025, "upright body height calibrated " + view)
				else:
					var guard := source.get_frame_texture(clip, 0) as AtlasTexture
					for index in frames.get_frame_count("idle_" + view):
						var idle := frames.get_frame_texture("idle_" + view, index) as AtlasTexture
						check(idle.region == guard.region and idle.atlas.resource_path == guard.atlas.resource_path, "trained guard stance " + view)
		pairs[technique] = variants
		if variants.size() == 2 and technique == "novice":
			for view in ["back", "front", "side"]:
				check(variants[0].get_meta("pixel_size_attack_" + view) == variants[1].get_meta("pixel_size_attack_" + view), "pack cannot rescale body " + view)
	group("artwork coverage, phase cells, timing, foot anchors and scale")

func check_boundaries() -> void:
	# D-057: no backpack layer; techniques switch whole bare frame sets.
	check(visual.set_appearance_frames(pairs.trained[0]), "switch to trained frames")
	check(body.sprite_frames == pairs.trained[0], "trained frames active immediately")
	visual._current_view = &"right"
	visual._current_action = &"attack"
	body.animation = &"attack_side"
	for invalid in [NAN, INF, -1.0, 0.0, "invalid"]:
		var resource: SpriteFrames = pairs.novice[0].duplicate(true)
		resource.set_meta("pixel_size_attack_side", invalid)
		resource.set_meta("baseline_offset_pixels_attack", invalid)
		body.sprite_frames = resource
		body.animation = &"attack_side"
		visual._apply_sprite_scale(body)
		var expected: float = resource.get_meta("pixel_size_side")
		check(is_equal_approx(body.pixel_size, expected) and is_equal_approx(body.position.y, expected * float(resource.get_meta("baseline_offset_pixels"))), "invalid action metadata falls back")
		resource.set_meta("pixel_size_side", invalid)
		resource.set_meta("baseline_offset_pixels", invalid)
		visual._apply_sprite_scale(body)
		check(is_equal_approx(body.pixel_size, 0.006) and is_equal_approx(body.position.y, 0.9), "invalid base metadata uses finite defaults")
	check(visual.set_appearance_frames(pairs.novice[0]), "restore novice frames")
	visual._current_action = &""
	body.animation = &"run_side"
	visual._apply_sprite_scale(body)
	check(is_equal_approx(body.pixel_size, float(body.sprite_frames.get_meta("pixel_size_run_side"))), "empty action uses clip prefix")
	group("unready calls, same-frame ownership and finite scale fallbacks")

func check_attack() -> void:
	player.strike_requested.connect(func(): strikes += 1)
	for delta in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0]:
		player.stop_input()
		player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		player.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		player.input_enabled = true
		strikes = 0
		player.request_attack()
		for step in int(ceil(0.5 / delta)):
			var technique: String = "novice" if step % 2 == 0 else "trained"
			check(visual.set_appearance_frames(pairs[technique][0]), "mid-attack technique switch")
			player.request_attack()
			player._physics_process(delta)
		check(strikes == 1 and not player.is_attacking(), "one hit despite switching/spam at " + str(delta))
	group("technique switches do not restart attacks or duplicate contact")

func run() -> void:
	check_assets()
	if pairs.get("novice", []).size() != 2 or pairs.get("trained", []).size() != 2:
		quit(1)
		return
	inv = root.get_node("Inventory")
	check(inv.configure_storage([{"id":"traveler_clothing_pocket", "kind":"pocket", "capacity":6}]), "fixture pocket")
	player = load("res://scenes/courtyard/courtyard_player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	visual = player.get_node("Visual")
	visual.set_process(false)
	body = visual.get_node("Body")
	check_boundaries()
	check_attack()
	player.queue_free()
	await process_frame
	check(groups == 3, "all expected groups finished (pair/backpack groups removed, D-057)")
	if errors.is_empty():
		print("ASHBOUND_FIST_TECHNIQUES_OK groups=%d" % groups)
		quit(0)
	else:
		quit(1)
