extends SceneTree
## Check real resource import, whole-cell safety and feet support before scene integration.
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("DAUGHTER_WALK_FAIL ", label)
func run() -> void:
	for view in ["side","back"]:
		validate_view(view)
	print("DAUGHTER_WALK_CHECKS failures=",failures.size()," views=2")
	quit(0 if failures.is_empty() else 1)
func validate_view(view: String) -> void:
	var clip := StringName("walk_"+view)
	var frames := load("res://assets/characters/inn-v1/daughter_walk_%s_frames.tres"%view) as SpriteFrames
	if frames == null:
		check(false,"resource import "+view)
		return
	check(frames.has_animation(clip), "clip exists "+view)
	check(frames.get_frame_count(clip) == 8, "eight whole poses "+view)
	check(frames.get_animation_loop(clip), "loop enabled "+view)
	check(is_equal_approx(frames.get_animation_speed(clip),15.0), "accepted preview cadence "+view)
	var ppu := float(frames.get_meta("pixel_size_walk_"+view,0))
	var baseline := float(frames.get_meta("baseline_offset_pixels",0))
	check(ppu>.003 and ppu<.005 and is_equal_approx(baseline,248), "one scale and shared feet anchor")
	var distinct := {}
	for i in range(frames.get_frame_count(clip)):
		var texture := frames.get_frame_texture(clip,i) as AtlasTexture
		if texture == null:
			check(false,"atlas cell %d"%i)
			continue
		check(texture.filter_clip,"no sampling neighbouring pose %d"%i)
		check(texture.get_size()==Vector2(384,512),"cell size %d"%i)
		check(Rect2(Vector2.ZERO,texture.atlas.get_size()).encloses(texture.region),"region inside source %d"%i)
		var image := texture.get_image()
		image.convert(Image.FORMAT_RGBA8)
		distinct[image.get_data().hex_encode().sha256_text()] = true
		var ground_pixels := 0
		var edge_pixels := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x,y).a < .25:
					continue
				if y>=498 and y<=509:
					ground_pixels += 1
				if x==0 or y==0 or x==383 or y==511:
					edge_pixels += 1
		check(edge_pixels==0,"no visible clipping %d"%i)
		check(ground_pixels>0,"walking support reaches common ground band %d"%i)
	check(distinct.size()==8,"not eight copies of one pose")
	print("DAUGHTER_WALK_VIEW ",view," distinct=",distinct.size())
