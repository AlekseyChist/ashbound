extends SceneTree
## Headless tool: builds reusable SpriteFrames resources from the courtyard PNG atlases.
## Run: godot --headless --script res://scripts/tools/build_courtyard_frames.gd

const HERO_TEX_PATH := "res://assets/characters/courtyard/traveler-v1.png"
const NPC_TEX_PATH := "res://assets/characters/courtyard/residents-v1.png"

const HERO_OUT_DIR := "res://assets/characters/courtyard"
const HERO_OUT_PATH := "res://assets/characters/courtyard/traveler_frames.tres"
const INNKEEPER_OUT_PATH := "res://assets/characters/courtyard/innkeeper_frames.tres"
const WATCHMAN_OUT_PATH := "res://assets/characters/courtyard/watchman_frames.tres"

# Absolute alpha bounding boxes (x, y, w, h) for the 4x4 hero atlas.
const HERO_RECTS: Array = [
	[86, 7, 150, 292],
	[389, 7, 146, 292],
	[713, 7, 172, 290],
	[1015, 6, 182, 294],
	[71, 321, 173, 288],
	[398, 321, 128, 291],
	[712, 321, 171, 289],
	[1030, 320, 157, 291],
	[106, 632, 109, 302],
	[421, 631, 109, 303],
	[736, 629, 108, 305],
	[1050, 630, 107, 304],
	[79, 950, 168, 286],
	[378, 950, 239, 287],
	[700, 950, 204, 286],
	[1032, 949, 157, 287],
]

# Absolute alpha bounding boxes (x, y, w, h) for the 4x2 NPC atlas.
const NPC_RECTS: Array = [
	[129, 6, 189, 431],
	[572, 6, 189, 431],
	[1016, 6, 189, 431],
	[1459, 6, 189, 431],
	[133, 445, 186, 434],
	[577, 445, 184, 434],
	[1020, 446, 185, 434],
	[1463, 446, 185, 434],
]


func _initialize() -> void:
	_generate_deferred.call_deferred()


func _generate_deferred() -> void:
	var ok := bool(_build_all())
	if ok:
		print("ASHBOUND_COURTYARD_FRAMES_READY")
		quit(0)
	else:
		push_error("Courtyard frames build failed.")
		quit(1)


func _build_all() -> bool:
	var hero_tex: Texture2D = load(HERO_TEX_PATH) as Texture2D
	if hero_tex == null:
		push_error("Failed to load hero atlas: " + HERO_TEX_PATH)
		return false

	var npc_tex: Texture2D = load(NPC_TEX_PATH) as Texture2D
	if npc_tex == null:
		push_error("Failed to load NPC atlas: " + NPC_TEX_PATH)
		return false

	var traveler_frames: SpriteFrames = _build_traveler_frames(hero_tex)
	if traveler_frames == null:
		return false

	var innkeeper_frames: SpriteFrames = _build_npc_frames(npc_tex, 0, 4)
	if innkeeper_frames == null:
		return false

	var watchman_frames: SpriteFrames = _build_npc_frames(npc_tex, 4, 8)
	if watchman_frames == null:
		return false

	if not _save_resource(traveler_frames, HERO_OUT_PATH):
		return false
	if not _save_resource(innkeeper_frames, INNKEEPER_OUT_PATH):
		return false
	if not _save_resource(watchman_frames, WATCHMAN_OUT_PATH):
		return false

	return true


func _build_traveler_frames(tex: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("walk")
	frames.add_animation("idle")
	frames.add_animation("attack")

	# Walk cycle: frames 0..7, 15 fps, looping.
	_add_hero_animation(frames, "walk", tex, 0, 8, 15.0, true)
	# Idle: frames 8..11, 4 fps, looping.
	_add_hero_animation(frames, "idle", tex, 8, 12, 4.0, true)
	# Attack: frames 12..15, 12 fps, non-looping.
	_add_hero_animation(frames, "attack", tex, 12, 16, 12.0, false)

	return frames


func _add_hero_animation(
	frames: SpriteFrames,
	anim_name: String,
	tex: Texture2D,
	start_index: int,
	end_index: int,
	fps: float,
	loop: bool
) -> void:
	var canvas_w := 320.0
	var canvas_h := 320.0
	var cell_w := 1254.0 / 4.0

	for i in range(start_index, end_index):
		var rect_arr: Array = HERO_RECTS[i]
		var rx: float = float(rect_arr[0])
		var ry: float = float(rect_arr[1])
		var rw: float = float(rect_arr[2])
		var rh: float = float(rect_arr[3])

		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(rx, ry, rw, rh)
		at.filter_clip = true

		var margin := Rect2()
		margin.size = Vector2(canvas_w - rw, canvas_h - rh)
		margin.position.x = (rx - round(float(i % 4) * cell_w)) + 3.0
		margin.position.y = 310.0 - rh
		at.margin = margin

		frames.add_frame(anim_name, at, 1.0)

	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, loop)


func _build_npc_frames(tex: Texture2D, start_index: int, end_index: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")

	var anim_name := "idle"
	var canvas_w := 448.0
	var canvas_h := 448.0
	var cell_w := 1774.0 / 4.0

	for i in range(start_index, end_index):
		var rect_arr: Array = NPC_RECTS[i]
		var rx: float = float(rect_arr[0])
		var ry: float = float(rect_arr[1])
		var rw: float = float(rect_arr[2])
		var rh: float = float(rect_arr[3])

		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(rx, ry, rw, rh)
		at.filter_clip = true

		var margin := Rect2()
		margin.size = Vector2(canvas_w - rw, canvas_h - rh)
		margin.position.x = (rx - round(float(i % 4) * cell_w)) + 2.0
		margin.position.y = 438.0 - rh
		at.margin = margin

		frames.add_frame(anim_name, at, 1.0)

	frames.set_animation_speed(anim_name, 3.0)
	frames.set_animation_loop(anim_name, true)

	return frames


func _save_resource(res: Resource, path: String) -> bool:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [path, err])
		return false
	print("Saved: " + path)
	return true
