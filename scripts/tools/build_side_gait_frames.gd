extends SceneTree
## Tool: bake side walk/run atlas frames into existing SpriteFrames resources.
## Run: godot --headless --script res://scripts/tools/build_side_gait_frames.gd
## Data-only builder; no runtime gameplay logic.

const BARE_PATH := "res://assets/characters/courtyard/traveler_frames.tres"
const PACK_PATH := "res://assets/characters/courtyard/traveler_backpack_frames.tres"

const WALK_BARE_TEX := "res://assets/characters/courtyard/side-gait-v1/walk-bare.png"
const WALK_PACK_TEX := "res://assets/characters/courtyard/side-gait-v1/walk-pack.png"
const RUN_BARE_TEX := "res://assets/characters/courtyard/side-gait-v1/run-bare.png"
const RUN_PACK_TEX := "res://assets/characters/courtyard/side-gait-v1/run-pack.png"

const FRAME_COUNT := 8
const CELL_SIZE := 384
const ATLAS_SIZE := Vector2i(1536, 768)
const COLS := 4
const ROWS := 2

# Clip -> atlas texture mapping (walk atlas for walk and walk_side, run atlas for run_side).
const CLIP_TO_TEX: Array = [
	["walk", WALK_BARE_TEX],
	["walk_side", WALK_BARE_TEX],
	["run_side", RUN_BARE_TEX],
]

var _errors: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var bare_frames := _load_sprite_frames(BARE_PATH)
	var pack_frames := _load_sprite_frames(PACK_PATH)
	if bare_frames == null or pack_frames == null:
		_fail()
		return

	var walk_bare_tex := _load_texture(WALK_BARE_TEX)
	var walk_pack_tex := _load_texture(WALK_PACK_TEX)
	var run_bare_tex := _load_texture(RUN_BARE_TEX)
	var run_pack_tex := _load_texture(RUN_PACK_TEX)
	if walk_bare_tex == null or walk_pack_tex == null or run_bare_tex == null or run_pack_tex == null:
		_fail()
		return

	# Preflight: required clips exist with exactly 8 frames in both resources.
	for clip_name: Array in CLIP_TO_TEX:
		var anim_name: String = clip_name[0]
		if not bare_frames.has_animation(anim_name) or bare_frames.get_frame_count(anim_name) != FRAME_COUNT:
			_errors.append("bare: clip '%s' missing or frame count != %d" % [anim_name, FRAME_COUNT])
		if not pack_frames.has_animation(anim_name) or pack_frames.get_frame_count(anim_name) != FRAME_COUNT:
			_errors.append("pack: clip '%s' missing or frame count != %d" % [anim_name, FRAME_COUNT])

	if _errors.size() > 0:
		_fail()
		return

	# Replace only the three clips' textures; retain per-frame durations, speed and loop.
	var bare_walk_tex: Texture2D = walk_bare_tex
	var pack_walk_tex: Texture2D = walk_pack_tex
	var bare_run_tex: Texture2D = run_bare_tex
	var pack_run_tex: Texture2D = run_pack_tex

	_apply_clips(bare_frames, "walk", bare_walk_tex)
	_apply_clips(bare_frames, "walk_side", bare_walk_tex)
	_apply_clips(bare_frames, "run_side", bare_run_tex)

	_apply_clips(pack_frames, "walk", pack_walk_tex)
	_apply_clips(pack_frames, "walk_side", pack_walk_tex)
	_apply_clips(pack_frames, "run_side", pack_run_tex)

	var err_bare: int = ResourceSaver.save(bare_frames, BARE_PATH)
	if err_bare != OK:
		push_error("Failed to save %s (err=%d)" % [BARE_PATH, err_bare])
		quit(1)
		return
	var err_pack: int = ResourceSaver.save(pack_frames, PACK_PATH)
	if err_pack != OK:
		push_error("Failed to save %s (err=%d)" % [PACK_PATH, err_pack])
		quit(1)
		return

	print("ASHBOUND_SIDE_GAIT_FRAMES_OK resources=2 clips=6")
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
		# Codex QA follow-up: deterministic identifiers make repeated builds byte-stable.
		at.resource_scene_unique_id = "SideGait_%s_%d" % [anim_name, i]
		at.atlas = atlas
		at.region = Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)
		at.filter_clip = true
		var duration: float = frames.get_frame_duration(anim_name, i)
		frames.set_frame(anim_name, i, at, duration)


func _fail() -> void:
	for e in _errors:
		push_error(e)
	quit(1)
