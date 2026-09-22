extends SceneTree
## Offline builder for the courtyard fist-defense poses.
## Builds four SpriteFrames (novice/trained x bare/pack) from the six-pose
## 3x2 atlases in assets/characters/courtyard/fist-defense/.
## All pixel measurements are done on ORIGINAL PNG files loaded from disk,
## never on compressed get_image() output of imported textures.
## No source mutation: old fist-preview resources are only duplicated.

const REF_DIR := "res://assets/characters/courtyard/fist-preview/"
const DEFAULT_SRC_DIR := "res://assets/characters/courtyard/fist-defense/"
const DEFAULT_OUT_DIR := "res://assets/characters/courtyard/fist-defense/"
const TOOLS_FIXTURE_DIR := "res://.tools/fixtures/fist-defense/"

const TECHNIQUES: Array[String] = ["novice", "trained"]
const PACKS: Array[bool] = [false, true]
const VIEWS: Array[String] = ["front", "back", "side"]
const ROWS: Array[String] = ["guard", "hit"]

const ALPHA_THRESHOLD := 0.2
const ATLAS_PX := 1254
const COLS := 3
const ROWS_COUNT := 2
const CANVAS_PX := 640
const SOLE_Y := 620
const FOOT_ANCHOR_X := 320
const BASELINE_OFFSET := 300.0 # 620 - 640/2
const FOOT_BAND_FRACTION := 0.125

var _src_dir: String = DEFAULT_SRC_DIR
var _out_dir: String = DEFAULT_OUT_DIR


func _initialize() -> void:
	if _parse_args():
		call_deferred("_run")


func _parse_args() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var errors: Array[String] = []
	var i := 0
	while i < args.size():
		var arg: String = args[i]
		if arg.begins_with("--out-dir="):
			_out_dir = arg.substr("--out-dir=".length())
		elif arg == "--out-dir":
			i += 1
			if i >= args.size():
				_fail("missing value for --out-dir")
				return false
			_out_dir = args[i]
		elif arg.begins_with("--source-dir="):
			_src_dir = arg.substr("--source-dir=".length())
		elif arg == "--source-dir":
			i += 1
			if i >= args.size():
				_fail("missing value for --source-dir")
				return false
			_src_dir = args[i]
		else:
			_fail("unknown argument: " + arg)
			return false
		i += 1
	_validate_dir_arg("--out-dir", _out_dir, [DEFAULT_OUT_DIR, "res://.tools/"], errors)
	if not errors.is_empty():
		_fail(errors[0])
		return false
	_validate_dir_arg("--source-dir", _src_dir, [DEFAULT_SRC_DIR, "res://.tools/"], errors)
	if not errors.is_empty():
		_fail(errors[0])
		return false
	_out_dir = _normalize_dir(_out_dir)
	_src_dir = _normalize_dir(_src_dir)
	return true


func _validate_dir_arg(flag: String, raw: String, allowed_prefixes: Array[String], errors: Array[String]) -> void:
	if raw.is_empty():
		errors.push_back("%s: empty path" % flag)
		return
	if raw.contains("\\"):
		errors.push_back("%s: backslash not allowed: %s" % [flag, raw])
		return
	if raw.contains(".."):
		errors.push_back("%s: '..' segment not allowed: %s" % [flag, raw])
		return
	if not raw.begins_with("res://"):
		errors.push_back("%s: must be a res:// path: %s" % [flag, raw])
		return
	var norm := _normalize_dir(raw)
	for prefix in allowed_prefixes:
		if norm == prefix or norm.begins_with(prefix):
			return
	errors.push_back("%s: path not under an allowed directory: %s" % [flag, raw])


func _normalize_dir(path: String) -> String:
	var norm := path
	while norm.ends_with("/"):
		norm = norm.trim_suffix("/")
	return norm + "/"


func _fail(message: String) -> void:
	printerr("ASHBOUND_FIST_DEFENSE_FRAMES_FAILED: " + message)
	quit(1)


func _run() -> void:
	var errors: Array[String] = []
	_build(errors)
	if not errors.is_empty():
		for e in errors:
			printerr("ASHBOUND_FIST_DEFENSE_FRAMES_FAILED: " + e)
		quit(1)
	else:
		print("ASHBOUND_FIST_DEFENSE_FRAMES_OK poses=24")
		quit(0)


func _build(errors: Array[String]) -> void:
	if not _check_out_dir(errors):
		return

	# Load all eight source PNGs (original pixels, never compressed textures).
	var imgs := {} # "tech-pack" -> Image
	for tech in TECHNIQUES:
		for pack in PACKS:
			var name := tech + ("-pack" if pack else "")
			if not FileAccess.file_exists(ProjectSettings.globalize_path(_src_dir + name + ".png")):
				errors.push_back("%s: missing source png: %s" % [name, _src_dir + name + ".png"])
				return
			var img := _load_png(_src_dir + name + ".png", errors, name)
			if img == null:
				return
			imgs[name] = img

	# Validate paired sizes and every cell of every atlas.
	for tech in TECHNIQUES:
		var bare: Image = imgs[tech]
		var pack: Image = imgs[tech + "-pack"]
		if bare.get_width() != pack.get_width() or bare.get_height() != pack.get_height():
			errors.push_back("%s: paired atlases differ in size" % tech)
			return
	for name in imgs.keys():
		var img: Image = imgs[name]
		if not _validate_atlas(img, name, errors):
			return

	# Load reference old fist-preview resources (fixed path, never mutated).
	# Reference file names use underscores: "novice_pack_frames.tres".
	var refs := {} # "tech-pack" -> SpriteFrames
	for tech in TECHNIQUES:
		for pack in PACKS:
			var name := tech + ("-pack" if pack else "")
			var ref_path: String = REF_DIR + String(name).replace("-pack", "_pack") + "_frames.tres"
			if not FileAccess.file_exists(ProjectSettings.globalize_path(ref_path)):
				errors.push_back("%s: missing reference: %s" % [name, ref_path])
				return
			var ref := _load_frames(ref_path, errors, name)
			if ref == null:
				return
			refs[name] = ref

	# Calibrate per-technique, per-view pixel size from BARE guard height vs old idle_<view>.
	var px_sizes := {} # tech -> { view -> float }
	for tech in TECHNIQUES:
		var views_px := {}
		for view in VIEWS:
			var px := _calibrate_view(imgs[tech], refs[tech], view, errors)
			if not is_finite(px) or px <= 0.0:
				return
			views_px[view] = px
		px_sizes[tech] = views_px

	# Build all four output resources in memory before saving anything.
	var outputs := {} # "tech-pack" -> SpriteFrames
	for tech in TECHNIQUES:
		for pack in PACKS:
			var name := tech + ("-pack" if pack else "")
			var out := _build_one(imgs[name], refs[name], px_sizes[tech], name, errors)
			if out == null:
				return
			outputs[name] = out

	# Save all four.
	var out_abs := ProjectSettings.globalize_path(_out_dir)
	if not DirAccess.dir_exists_absolute(out_abs):
		DirAccess.make_dir_recursive_absolute(out_abs)
	for name in outputs.keys():
		var path: String = _out_dir + String(name).replace("-pack", "_pack") + "_frames.tres"
		var err: int = ResourceSaver.save(outputs[name], ProjectSettings.globalize_path(path))
		if err != OK:
			errors.push_back("failed to save %s (err=%d)" % [path, err])


func _check_out_dir(errors: Array[String]) -> bool:
	var norm := _normalize_dir(_out_dir)
	if not (norm == _normalize_dir(DEFAULT_OUT_DIR) or norm.begins_with("res://.tools/")):
		errors.push_back("out-dir must be the fist-defense dir or under res://.tools/, got: " + _out_dir)
		return false
	if norm.begins_with(REF_DIR):
		errors.push_back("out-dir must never be the old fist-preview dir")
		return false
	return true


func _load_frames(path: String, errors: Array[String], label: String) -> SpriteFrames:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		errors.push_back("%s: missing reference: %s" % [label, path])
		return null
	var res := load(path)
	if res == null or not (res is SpriteFrames):
		errors.push_back("%s: missing or invalid reference: %s" % [label, path])
		return null
	return res as SpriteFrames


func _load_png(res_path: String, errors: Array[String], label: String) -> Image:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(res_path)):
		errors.push_back("%s: missing file: %s" % [label, res_path])
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	if img == null:
		errors.push_back("%s: cannot load original png: %s" % [label, res_path])
		return null
	if img.detect_alpha() == Image.ALPHA_NONE:
		errors.push_back("%s: png has no alpha channel: %s" % [label, res_path])
		return null
	return img


func _validate_atlas(img: Image, label: String, errors: Array[String]) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	if w != ATLAS_PX or h != ATLAS_PX:
		errors.push_back("%s: expected %dx%d atlas, got %dx%d" % [label, ATLAS_PX, ATLAS_PX, w, h])
		return false
	var cell := w / COLS
	for r in ROWS_COUNT:
		for c in COLS:
			var region := Rect2i(c * cell, r * (w / ROWS_COUNT), cell, w / ROWS_COUNT)
			var bbox := _alpha_bbox(img, region)
			if bbox.size.x <= 0 or bbox.size.y <= 0:
				errors.push_back("%s: empty cell at col=%d row=%d" % [label, c, r])
				return false
			if _touches_border(bbox, region):
				errors.push_back("%s: alpha touches cell border at col=%d row=%d" % [label, c, r])
				return false
	return true


func _touches_border(bbox: Rect2i, region: Rect2i) -> bool:
	# Require at least 2 clear pixels on every cell border.
	if bbox.position.x - region.position.x < 2 or bbox.position.y - region.position.y < 2:
		return true
	if region.end.x - bbox.end.x < 2 or region.end.y - bbox.end.y < 2:
		return true
	return false


func _alpha_bbox(img: Image, region: Rect2i) -> Rect2i:
	var min_x := region.position.x + region.size.x
	var min_y := region.position.y + region.size.y
	var max_x := -1
	var max_y := -1
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if img.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Horizontal anchor from the bottom 12.5% foot band of a cell (global coords).
func _foot_anchor(img: Image, region: Rect2i) -> Vector2:
	var bbox := _alpha_bbox(img, region)
	if bbox.size.y <= 0:
		return Vector2(float(region.position.x + region.size.x / 2), float(region.end.y))
	var band_h := maxi(1, int(ceil(bbox.size.y * FOOT_BAND_FRACTION)))
	var band := Rect2i(bbox.position.x, bbox.end.y - band_h, bbox.size.x, band_h)
	var min_x := band.position.x + band.size.x
	var max_x := -1
	for y in range(band.position.y, band.end.y):
		for x in range(band.position.x, band.end.x):
			if img.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var cx := (float(min_x) + float(max_x)) / 2.0 if max_x >= 0 else float(bbox.position.x + bbox.size.x / 2)
	return Vector2(cx, float(bbox.end.y))


## pixel_size_<view> = old idle world height / bare guard height, per technique+view.
func _calibrate_view(img: Image, ref: SpriteFrames, view: String, errors: Array[String]) -> float:
	var idle_action := "idle_" + view
	if not ref.has_animation(idle_action):
		errors.push_back("reference lacks clip: " + idle_action)
		return -1.0
	var frame0: Texture2D = ref.get_frame_texture(idle_action, 0)
	if frame0 == null or not (frame0 is AtlasTexture):
		errors.push_back("idle_%s frame0 is not an AtlasTexture" % view)
		return -1.0
	var idle_atlas: AtlasTexture = frame0 as AtlasTexture
	if idle_atlas.atlas == null:
		errors.push_back("idle_%s atlas texture missing" % view)
		return -1.0
	var idle_img := _load_png(idle_atlas.atlas.resource_path, errors, "idle_%s atlas" % view)
	if idle_img == null:
		return -1.0
	var idle_bbox := _alpha_bbox(idle_img, idle_atlas.region)
	if idle_bbox.size.y <= 0:
		errors.push_back("idle_%s frame0 has no alpha" % view)
		return -1.0
	var src_px_size := _meta_float(ref, "pixel_size_" + view, 1.0)
	if not (src_px_size > 0.0 and is_finite(src_px_size)):
		errors.push_back("idle_%s source pixel_size invalid: %f" % [view, src_px_size])
		return -1.0
	var world_h := float(idle_bbox.size.y) * src_px_size

	# Bare guard height: top of the guard row bbox (row 0, column = view).
	var cell := ATLAS_PX / COLS
	var region := Rect2i(_view_col(view) * cell, 0, cell, ATLAS_PX / ROWS_COUNT)
	var guard_bbox := _alpha_bbox(img, region)
	if guard_bbox.size.y <= 0:
		errors.push_back("%s %s guard cell empty" % [img.resource_path, view])
		return -1.0
	var px_size := world_h / float(guard_bbox.size.y)
	if not (px_size > 0.0 and is_finite(px_size)):
		errors.push_back("%s calibrated scale invalid: %f" % [view, px_size])
		return -1.0
	return px_size


func _meta_float(frames: SpriteFrames, key: String, default_val: float) -> float:
	var md: Variant = frames.get_meta(key, default_val)
	if md is float:
		return md
	if md is int:
		return float(md)
	return default_val


func _view_col(view: String) -> int:
	match view:
		"front":
			return 0
		"back":
			return 1
		_:
			return 2


## Build one output SpriteFrames from a duplicated reference.
func _build_one(img: Image, ref: SpriteFrames, px_sizes: Dictionary, label: String, errors: Array[String]) -> SpriteFrames:
	var out := ref.duplicate(true) as SpriteFrames
	if out == null:
		errors.push_back("%s: cannot duplicate reference" % label)
		return null
	out.set_meta("fist_defense_technique", "novice" if label.begins_with("novice") else "trained")
	out.set_meta("fist_defense_backpack", label.ends_with("-pack"))

	var tech := "novice" if label.begins_with("novice") else "trained"
	# Bare anchor source is the bare atlas of the same technique (cached once).
	var bare_img: Image = null
	if FileAccess.file_exists(ProjectSettings.globalize_path(_src_dir + tech + ".png")):
		bare_img = Image.load_from_file(ProjectSettings.globalize_path(_src_dir + tech + ".png"))
	if bare_img == null:
		errors.push_back("%s: cannot load bare atlas for anchors: %s" % [label, _src_dir + tech + ".png"])
		return null

	var cell := ATLAS_PX / COLS
	for row in ROWS_COUNT:
		var row_name: String = ROWS[row]
		for view in VIEWS:
			var region := Rect2i(_view_col(view) * cell, row * (ATLAS_PX / ROWS_COUNT), cell, ATLAS_PX / ROWS_COUNT)
			var bbox := _alpha_bbox(img, region)
			if bbox.size.x <= 0 or bbox.size.y <= 0:
				errors.push_back("%s %s_%s: empty cell" % [label, row_name, view])
				return null
			# Shared body anchor/baseline for the pair: measured on the BARE atlas.
			var anchor := _foot_anchor(bare_img, region)
			var bare_bbox := _alpha_bbox(bare_img, region)
			var sole_y := float(bare_bbox.end.y) # original absolute foot baseline (max alpha Y + 1)
			var px_size: float = px_sizes[view]

			var action := row_name + "_" + view
			if not out.has_animation(action):
				out.add_animation(action)
			var tex := _make_frame(img, region, bbox, anchor, sole_y, px_size, label, errors)
			if tex == null:
				return null
			# Exactly one single-frame clip, loop false, speed 1, duration 1.
			out.add_frame(action, tex, 1.0)
			out.set_animation_speed(action, 1.0)
			out.set_animation_loop(action, false)
			# Per technique+view pixel size; never overwrite the old per-view meta.
			out.set_meta("pixel_size_" + row_name + "_" + view, px_size)
			out.set_meta("baseline_offset_pixels_" + row_name, BASELINE_OFFSET)
	return out


func _make_frame(img: Image, region: Rect2i, bbox: Rect2i, anchor: Vector2, sole_y: float, px_size: float, label: String, errors: Array[String]) -> AtlasTexture:
	# Crop = actual alpha bbox (no resampling).
	var crop := bbox
	if crop.position.x < region.position.x or crop.position.y < region.position.y:
		errors.push_back("%s: crop outside cell" % label)
		return null
	if crop.end.x > region.end.x or crop.end.y > region.end.y:
		errors.push_back("%s: crop outside cell" % label)
		return null
	var margin_pos := Vector2(FOOT_ANCHOR_X - (anchor.x - float(crop.position.x)), SOLE_Y - (sole_y - float(crop.position.y)))
	if margin_pos.x < 0.0 or margin_pos.y < 0.0:
		errors.push_back("%s: negative margin position %s" % [label, str(margin_pos)])
		return null
	var out := AtlasTexture.new()
	out.atlas = _atlas_texture_for(img, label, errors)
	if out.atlas == null:
		return null
	out.region = crop
	out.margin = Rect2(margin_pos, Vector2(CANVAS_PX, CANVAS_PX) - Vector2(crop.size))
	out.filter_clip = true
	return out


func _atlas_texture_for(img: Image, label: String, errors: Array[String]) -> Texture2D:
	# The source PNG texture is loaded once per image and shared across frames.
	var path := _src_dir + label + ".png"
	var tex := load(path)
	if tex == null or not (tex is Texture2D):
		errors.push_back("%s: cannot load atlas texture: %s" % [label, path])
		return null
	return tex as Texture2D
