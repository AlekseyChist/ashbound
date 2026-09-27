extends SceneTree
## Tool: bake painted-motion-v2 side walk/run atlas frames into existing SpriteFrames resource.
## Run: godot --headless --script res://scripts/tools/build_painted_motion_frames.gd
## Data-only builder; no runtime gameplay logic.

const BARE_PATH := "res://assets/characters/courtyard/traveler_frames.tres"

const WALK_TEX := "res://assets/characters/courtyard/painted-motion-v2/walk.png"
const RUN_TEX := "res://assets/characters/courtyard/painted-motion-v2/run.png"

const FRAME_COUNT := 8
const CELL_SIZE := 384
const ATLAS_SIZE := Vector2i(1536, 768)
const COLS := 4
const ROWS := 2

# Clip -> atlas texture mapping (walk atlas for walk and walk_side, run atlas for run_side).
const CLIP_TO_TEX: Array = [
	["walk", WALK_TEX],
	["walk_side", WALK_TEX],
	["run_side", RUN_TEX],
]

var _errors: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var frames := _load_sprite_frames(BARE_PATH)
	if frames == null:
		_fail()
		return

	var walk_tex := _load_texture(WALK_TEX)
	var run_tex := _load_texture(RUN_TEX)
	if walk_tex == null or run_tex == null:
		_fail()
		return

	# Preflight: required clips exist with exactly 8 frames.
	for clip_name: Array in CLIP_TO_TEX:
		var anim_name: String = clip_name[0]
		if not frames.has_animation(anim_name) or frames.get_frame_count(anim_name) != FRAME_COUNT:
			_errors.append("clip '%s' missing or frame count != %d" % [anim_name, FRAME_COUNT])

	# Preflight: retain a valid legacy scale contract; artwork packing compensates
	# for the existing run-to-walk ratio without changing runtime metadata.
	var pixel_size_side: Variant = frames.get_meta("pixel_size_side", -1.0)
	if not _is_positive_finite_number(pixel_size_side):
		_errors.append("metadata 'pixel_size_side' missing or not a positive finite number: %s" % str(pixel_size_side))

	if _errors.size() > 0:
		_fail()
		return

	# Replace only the three clips' textures; retain per-frame durations, speed and loop.
	var walk_atlas: Texture2D = walk_tex
	var run_atlas: Texture2D = run_tex

	_apply_clips(frames, "walk", walk_atlas)
	_apply_clips(frames, "walk_side", walk_atlas)
	_apply_clips(frames, "run_side", run_atlas)

	# Codex integration correction: retain runtime scale metadata for compatibility
	# with legacy equipment. The complete run artwork is packed at the inverse
	# 0.9 scale ratio; displayed body size remains consistent without runtime edits.

	var err: int = ResourceSaver.save(frames, BARE_PATH)
	if err != OK:
		push_error("Failed to save %s (err=%d)" % [BARE_PATH, err])
		quit(1)
		return

	print("ASHBOUND_PAINTED_MOTION_BUILD_OK")
	quit(0)


func _load_sprite_frames(path: String) -> SpriteFrames:
	var res: Resource = load(path)
	if res == null:
		_errors.append("Failed to load resource: %s" % path)
		return null
	if not (res is SpriteFrames):
		_errors.append("Resource is not SpriteFrames: %s" % path)
		return null
	var frames := res as SpriteFrames
	return frames


func _load_texture(path: String) -> Texture2D:
	var res: Resource = load(path)
	if res == null:
		_errors.append("Failed to load texture: %s" % path)
		return null
	if not (res is Texture2D):
		_errors.append("Resource is not Texture2D: %s" % path)
		return null
	var tex := res as Texture2D
	var size := tex.get_size()
	if Vector2i(size) != ATLAS_SIZE:
		_errors.append("Atlas %s has wrong size %s, expected %s" % [path, str(Vector2i(size)), str(ATLAS_SIZE)])
		return null
	return tex


func _apply_clips(frames: SpriteFrames, anim_name: String, atlas: Texture2D) -> void:
	var count: int = frames.get_frame_count(anim_name)
	for i in range(count):
		var col: int = i % COLS
		var row: int = i / COLS
		var at := AtlasTexture.new()
		# Deterministic identifiers make repeated builds byte-stable.
		at.resource_scene_unique_id = "PaintedMotion_%s_%d" % [anim_name, i]
		at.atlas = atlas
		at.region = Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)
		at.filter_clip = true
		var duration: float = frames.get_frame_duration(anim_name, i)
		frames.set_frame(anim_name, i, at, duration)


func _is_positive_finite_number(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var num := float(value)
	return is_finite(num) and num > 0.0


func _fail() -> void:
	for e in _errors:
		push_error(e)
	quit(1)
