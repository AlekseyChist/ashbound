extends SceneTree
## Validate the actual full resource; does not claim artistic or scene acceptance.
var failures: Array[String] = []
const VIEWS := ["front", "back", "side"]
const ACTIONS := ["idle", "walk", "run", "windup", "attack", "hit", "out", "guard"]
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("DAUGHTER_FAIL ",label)
func run() -> void:
	var frames := load("res://assets/characters/inn-v1/daughter_frames.tres") as SpriteFrames
	if frames == null:
		printerr("DAUGHTER_FAIL resource import")
		quit(1)
		return
	check(frames.get_animation_names().size()==24,"exactly24 clips")
	check(is_equal_approx(float(frames.get_meta("baseline_offset_pixels",0)),248.0),"shared feet anchor")
	var checked := 0
	for action in ACTIONS:
		for view in VIEWS:
			var clip := StringName(action+"_"+view)
			if not frames.has_animation(clip):
				check(false,"missing "+str(clip))
				continue
			var moving: bool = action in ["walk","run"]
			var count: int = 8 if moving else 1
			check(frames.get_frame_count(clip)==count,"frame count "+str(clip))
			check(frames.get_animation_loop(clip)==(action in ["idle","walk","run"]),"loop contract "+str(clip))
			check(is_equal_approx(frames.get_animation_speed(clip),15.0),"cadence "+str(clip))
			var ppu := float(frames.get_meta("pixel_size_"+str(clip),0))
			check(ppu>.003 and ppu<.005,"one calibrated scale "+str(clip))
			var distinct := {}
			for i in range(frames.get_frame_count(clip)):
				var texture := frames.get_frame_texture(clip,i) as AtlasTexture
				if texture == null:
					check(false,"whole atlas pose "+str(clip))
					continue
				check(texture.filter_clip and texture.margin==Rect2(),"isolated whole cell "+str(clip))
				check(texture.get_size()==Vector2(384,512),"cell size "+str(clip))
				check(Rect2(Vector2.ZERO,texture.atlas.get_size()).encloses(texture.region),"region inside source "+str(clip))
				var image := texture.get_image()
				image.convert(Image.FORMAT_RGBA8)
				distinct[image.get_data().hex_encode().sha256_text()] = true
				var edges := 0
				var ground := 0
				var visible := 0
				for y in range(512):
					for x in range(384):
						if image.get_pixel(x,y).a < .25:
							continue
						visible += 1
						if x==0 or x==383 or y==0 or y==511:
							edges += 1
						if y>=498 and y<=509:
							ground += 1
				check(visible>1000 and edges==0,"intact visible pose %s/%d"%[clip,i])
				# Running flight is intentionally above the floor; only contacts0/4 required.
				if action!="run" or i in [0,4]:
					check(ground>0,"floor support %s/%d"%[clip,i])
				checked += 1
			check(distinct.size()==count,"distinct phases "+str(clip))
		print("DAUGHTER_ACTION_CHECKED ",action)
	print("DAUGHTER_FULL_CHECKS failures=",failures.size()," whole_poses=",checked)
	quit(0 if failures.is_empty() else 1)
