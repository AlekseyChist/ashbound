extends SceneTree
## Offline builder: creates full painted backpack-on SpriteFrames counterparts
## of existing courtyard traveler clips, preserving every clip, alias, speed,
## loop, frame duration and metadata. No pixel edits; no input mutation.

const INPUT_MAIN := "res://assets/characters/courtyard/traveler_frames.tres"
const INPUT_POCKET := "res://assets/characters/courtyard/traveler_pocket_frames.tres"
const OUTPUT_MAIN := "res://assets/characters/courtyard/traveler_backpack_frames.tres"
const OUTPUT_POCKET := "res://assets/characters/courtyard/traveler_backpack_pocket_frames.tres"

const ALPHA_THRESHOLD := 0.20
const SEARCH_PAD_X := 60
const SEARCH_PAD_Y := 6

# original texture file name -> painted full-character texture file name
const TEXTURE_MAP: Dictionary = {
	"traveler-v1.png": "painted-backpack/traveler-side-pack.png",
	"traveler-back-v1.png": "painted-backpack/traveler-back-pack.png",
	"traveler-front-v1.png": "painted-backpack/traveler-front-pack.png",
	"traveler-run-back-v3.png": "painted-backpack/traveler-run-back-pack.png",
	"traveler-run-front-v3.png": "painted-backpack/traveler-run-front-pack.png",
	"traveler-run-side-v3.png": "painted-backpack/traveler-run-side-pack.png",
	"traveler-pocket-v1.png": "painted-backpack/traveler-pocket-pack.png",
}

var _image_cache: Dictionary = {}
var _atlas_texture_cache: Dictionary = {}
var _pending_outputs: Array[Resource] = []


func _init() -> void:
	var ok := bool(_run())
	if ok:
		print("ASHBOUND_PAINTED_BACKPACK_FRAMES_READY")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	var main_frames: SpriteFrames = _load_input_sprite_frames(INPUT_MAIN)
	if main_frames == null:
		return false
	var pocket_frames: SpriteFrames = _load_input_sprite_frames(INPUT_POCKET)
	if pocket_frames == null:
		return false

	var out_main: SpriteFrames = _build_backpack_frames(main_frames, "main")
	if out_main == null:
		return false
	var out_pocket: SpriteFrames = _build_backpack_frames(pocket_frames, "pocket")
	if out_pocket == null:
		return false

	# Save only after BOTH outputs are fully built and validated.
	var saved_main := ResourceSaver.save(out_main, OUTPUT_MAIN) == OK
	var saved_pocket := ResourceSaver.save(out_pocket, OUTPUT_POCKET) == OK
	if not saved_main or not saved_pocket:
		push_error("Painted backpack frames: failed to save outputs (main=%s pocket=%s)." % [saved_main, saved_pocket])
		return false
	return true


func _load_input_sprite_frames(path: String) -> SpriteFrames:
	if not ResourceLoader.exists(path):
		push_error("Painted backpack frames: missing input resource: %s" % path)
		return null
	var res: Resource = load(path)
	if res == null or not (res is SpriteFrames):
		push_error("Painted backpack frames: input is not a SpriteFrames resource: %s" % path)
		return null
	var frames: SpriteFrames = res as SpriteFrames
	if frames.get_animation_names().is_empty():
		push_error("Painted backpack frames: input has no animations: %s" % path)
		return null
	return frames


func _build_backpack_frames(src: SpriteFrames, label: String) -> SpriteFrames:
	var out := src.duplicate(true) as SpriteFrames
	if out == null:
		push_error("Painted backpack frames: duplicate failed for %s." % label)
		return null

	var anim_names: PackedStringArray = src.get_animation_names()
	for anim_name in anim_names:
		var frame_count: int = src.get_frame_count(anim_name)
		if frame_count <= 0:
			push_error("Painted backpack frames: animation '%s' has no frames." % anim_name)
			return null
		for i in frame_count:
			var old_tex: Texture2D = src.get_frame_texture(anim_name, i)
			if not (old_tex is AtlasTexture):
				push_error("Painted backpack frames: frame %d of '%s' is not an AtlasTexture." % [i, anim_name])
				return null
			var old_atlas: AtlasTexture = old_tex as AtlasTexture
			var new_atlas := _remap_frame_texture(old_atlas, anim_name, i, label)
			if new_atlas == null:
				return null
			var duration: float = src.get_frame_duration(anim_name, i)
			out.set_frame(anim_name, i, new_atlas, duration)

	# Validate clip parity before saving.
	for anim_name in anim_names:
		if out.get_frame_count(anim_name) != src.get_frame_count(anim_name):
			push_error("Painted backpack frames: frame count mismatch for '%s'." % anim_name)
			return null
		var n: int = src.get_frame_count(anim_name)
		for i in n:
			if not is_equal_approx(out.get_frame_duration(anim_name, i), src.get_frame_duration(anim_name, i)):
				push_error("Painted backpack frames: duration mismatch for '%s' frame %d." % [anim_name, i])
				return null
	_pending_outputs.append(out)
	return out


func _remap_frame_texture(old_atlas: AtlasTexture, anim_name: String, index: int, label: String) -> AtlasTexture:
	var atlas_res: Resource = old_atlas.get_atlas()
	if atlas_res == null or not (atlas_res is Texture2D):
		push_error("Painted backpack frames: frame '%s'[%d] has no atlas texture." % [anim_name, index])
		return null
	var atlas_tex: Texture2D = atlas_res as Texture2D

	var old_path: String = atlas_res.resource_path
	if old_path.is_empty():
		push_error("Painted backpack frames: frame '%s'[%d] has empty source texture path." % [anim_name, index])
		return null
	var file_name: String = old_path.get_file()
	if not TEXTURE_MAP.has(file_name):
		push_error("Painted backpack frames: no painted mapping for source texture '%s' (frame '%s'[%d])." % [file_name, anim_name, index])
		return null

	var cache_key: int = old_atlas.get_instance_id()
	if _atlas_texture_cache.has(cache_key):
		var cached: AtlasTexture = _atlas_texture_cache[cache_key] as AtlasTexture
		if cached != null:
			return cached

	var painted_rel: String = TEXTURE_MAP[file_name] as String
	# Individually corrected frame: idle_front frame 2 was redrawn on a separate sheet.
	if file_name == "traveler-front-v1.png" and anim_name == &"idle_front" and index == 2:
		painted_rel = "painted-backpack/traveler-front-idle-correction.png"
	var painted_path := "res://assets/characters/courtyard/" + painted_rel
	if not ResourceLoader.exists(painted_path):
		push_error("Painted backpack frames: missing painted texture: %s" % painted_path)
		return null
	var painted_res: Resource = load(painted_path)
	if painted_res == null or not (painted_res is Texture2D):
		push_error("Painted backpack frames: painted resource is not a Texture2D: %s" % painted_path)
		return null
	var painted_tex: Texture2D = painted_res as Texture2D

	var old_image: Image = _get_source_image(old_path, atlas_tex)
	if old_image == null:
		return null
	var new_image: Image = _get_source_image(painted_path, painted_tex)
	if new_image == null:
		return null
	if old_image.get_size() != new_image.get_size():
		push_error("Painted backpack frames: dimension mismatch for '%s': original %s vs painted %s." % [
			file_name, str(old_image.get_size()), str(new_image.get_size())])
		return null

	var virtual_size: Vector2 = old_atlas.get_size()
	var old_region: Rect2 = old_atlas.region
	var new_region: Rect2 = _measure_alpha_bbox(new_image, old_region, true)
	if new_region.size.x <= 0.0 or new_region.size.y <= 0.0:
		push_error("Painted backpack frames: empty alpha bbox for '%s' frame '%s'[%d] around %s." % [file_name, anim_name, index, str(old_region)])
		return null

	var old_body_region: Rect2 = _measure_alpha_bbox(old_image, old_region, false)
	if old_body_region.size.x <= 0.0 or old_body_region.size.y <= 0.0:
		push_error("Painted backpack frames: empty original body bbox for '%s' frame '%s'[%d] around %s." % [file_name, anim_name, index, str(old_region)])
		return null

	var old_mean_x: float = _head_centroid_x(old_image, old_body_region)
	if old_mean_x < 0.0:
		push_error("Painted backpack frames: empty head band in original for '%s' frame '%s'[%d] around %s." % [file_name, anim_name, index, str(old_region)])
		return null
	var new_mean_x: float = _head_centroid_x(new_image, new_region)
	if new_mean_x < 0.0:
		push_error("Painted backpack frames: empty head band in painted for '%s' frame '%s'[%d] around %s." % [file_name, anim_name, index, str(new_region)])
		return null

	var head_shift: float = new_mean_x - old_mean_x
	var old_margin: Rect2 = old_atlas.margin
	var new_offset_x: float = old_margin.position.x + new_region.position.x - old_region.position.x - head_shift
	var new_offset_y: float = old_margin.position.y + old_body_region.end.y - old_region.position.y - new_region.size.y

	var new_margin_size: Vector2 = Vector2(
		float(virtual_size.x - new_region.size.x),
		float(virtual_size.y - new_region.size.y))
	if new_margin_size.x < 0.0 or new_margin_size.y < 0.0:
		push_error("Painted backpack frames: region exceeds virtual canvas for '%s' frame '%s'[%d]: margin.size=%s." % [file_name, anim_name, index, str(new_margin_size)])
		return null

	var new_offset: Vector2 = Vector2(new_offset_x, new_offset_y)
	if new_offset.x < 0.0 or new_offset.y < 0.0:
		push_error("Painted backpack frames: negative margin offset (%s) for '%s' frame '%s'[%d]." % [str(new_offset), file_name, anim_name, index])
		return null
	if new_offset.x + new_region.size.x > virtual_size.x or new_offset.y + new_region.size.y > virtual_size.y:
		push_error("Painted backpack frames: remapped region exceeds virtual canvas for '%s' frame '%s'[%d]: offset=%s region=%s canvas=%s." % [file_name, anim_name, index, str(new_offset), str(new_region.size), str(virtual_size)])
		return null

	var new_atlas := AtlasTexture.new()
	new_atlas.set_atlas(painted_tex)
	new_atlas.region = Rect2(Vector2(float(new_region.position.x), float(new_region.position.y)), Vector2(float(new_region.size.x), float(new_region.size.y)))
	new_atlas.margin = Rect2(new_offset, new_margin_size)
	new_atlas.filter_clip = old_atlas.filter_clip

	_atlas_texture_cache[cache_key] = new_atlas
	return new_atlas


func _head_centroid_x(image: Image, region: Rect2) -> float:
	var x0 := clampi(int(region.position.x), 0, image.get_width())
	var x1 := clampi(int(region.end.x), 0, image.get_width())
	var y0 := clampi(int(region.position.y) + 8, 0, image.get_height())
	var y1 := clampi(mini(int(region.position.y) + 32, int(region.end.y)), 0, image.get_height())
	var sum_x := 0.0
	var count := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var p: Color = image.get_pixel(x, y)
			if p.a > ALPHA_THRESHOLD:
				sum_x += float(x)
				count += 1
	if count == 0:
		return -1.0
	return sum_x / float(count)

func _get_source_image(path: String, tex: Texture2D) -> Image:
	if _image_cache.has(path):
		var cached: Image = _image_cache[path] as Image
		if cached != null:
			return cached
	var img := tex.get_image()
	if img == null or img.is_empty():
		push_error("Painted backpack frames: could not read image for '%s'." % path)
		return null
	_image_cache[path] = img
	return img


func _measure_alpha_bbox(image: Image, original_region: Rect2, expand_search: bool = true) -> Rect2:
	var img_w := int(image.get_width())
	var img_h := int(image.get_height())

	var pad_x := SEARCH_PAD_X if expand_search else 0
	var pad_y := SEARCH_PAD_Y if expand_search else 0
	var left := int(original_region.position.x) - pad_x
	var top := int(original_region.position.y) - pad_y
	var right := int(original_region.end.x) + pad_x
	var bottom := int(original_region.end.y) + pad_y

	left = clampi(left, 0, img_w)
	top = clampi(top, 0, img_h)
	right = clampi(right, 0, img_w)
	bottom = clampi(bottom, 0, img_h)

	var roi_w := right - left
	var roi_h := bottom - top
	if roi_w <= 0 or roi_h <= 0:
		return Rect2()

	var visited := PackedByteArray()
	visited.resize(roi_w * roi_h)
	var best_count := 0
	var best_bbox := Rect2i()

	for sy in range(roi_h):
		var py := top + sy
		for sx in range(roi_w):
			var px := left + sx
			if visited[sy * roi_w + sx] != 0:
				continue
			if image.get_pixel(px, py).a <= ALPHA_THRESHOLD:
				visited[sy * roi_w + sx] = 1
				continue

			var queue: Array[Vector2i] = []
			queue.append(Vector2i(sx, sy))
			visited[sy * roi_w + sx] = 1
			var count := 0
			var min_x := px
			var max_x := px
			var min_y := py
			var max_y := py
			var cursor := 0
			while cursor < queue.size():
				var cell: Vector2i = queue[cursor]
				cursor += 1
				count += 1
				var cx := left + int(cell.x)
				var cy := top + int(cell.y)
				if cx < min_x:
					min_x = cx
				if cx > max_x:
					max_x = cx
				if cy < min_y:
					min_y = cy
				if cy > max_y:
					max_y = cy
				for dy in range(-1, 2):
					var ny := int(cell.y) + dy
					if ny < 0 or ny >= roi_h:
						continue
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var nx := int(cell.x) + dx
						if nx < 0 or nx >= roi_w:
							continue
						var idx := ny * roi_w + nx
						if visited[idx] != 0:
							continue
						if image.get_pixel(left + nx, top + ny).a <= ALPHA_THRESHOLD:
							visited[idx] = 1
							continue
						visited[idx] = 1
						queue.append(Vector2i(nx, ny))

			if count > best_count:
				best_count = count
				best_bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

	if best_count == 0:
		return Rect2()
	return Rect2(Vector2(float(best_bbox.position.x), float(best_bbox.position.y)), Vector2(float(best_bbox.size.x), float(best_bbox.size.y)))

