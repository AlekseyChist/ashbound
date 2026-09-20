extends SceneTree
## Headless tool: builds reusable SpriteFrames resources from the courtyard PNG atlases.
## Run: godot --headless --script res://scripts/tools/build_courtyard_frames.gd

const HERO_TEX_PATH := "res://assets/characters/courtyard/traveler-v1.png"
const HERO_BACK_TEX_PATH := "res://assets/characters/courtyard/traveler-back-v1.png"
const HERO_FRONT_TEX_PATH := "res://assets/characters/courtyard/traveler-front-v1.png"
const NPC_TEX_PATH := "res://assets/characters/courtyard/residents-v1.png"

const HERO_OUT_DIR := "res://assets/characters/courtyard"
const HERO_OUT_PATH := "res://assets/characters/courtyard/traveler_frames.tres"
const INNKEEPER_OUT_PATH := "res://assets/characters/courtyard/innkeeper_frames.tres"
const WATCHMAN_OUT_PATH := "res://assets/characters/courtyard/watchman_frames.tres"

# Absolute alpha bounding boxes (x, y, w, h, anchorX) for the 4x4 hero SIDE atlas.
const HERO_RECTS: Array = [
	[86, 7, 150, 292, 160.5],
	[389, 7, 146, 292, 461.5],
	[713, 7, 172, 290, 798.5],
	[1015, 6, 182, 294, 1105.5],
	[71, 321, 173, 288, 157],
	[398, 321, 128, 291, 461.5],
	[712, 321, 171, 289, 797],
	[1030, 320, 157, 291, 1108],
	[106, 632, 109, 302, 160],
	[421, 631, 109, 303, 477],
	[736, 629, 108, 305, 790],
	[1050, 630, 107, 304, 1104],
	[79, 950, 168, 286, 162.5],
	[378, 950, 239, 287, 464],
	[700, 950, 204, 286, 782.5],
	[1032, 949, 157, 287, 1110],
]

# Absolute alpha bounding boxes (x, y, w, h, anchorX) for the 4x4 hero BACK atlas.
const HERO_BACK_RECTS: Array = [
	[134, 17, 125, 290, 192.5],
	[426, 13, 125, 293, 483],
	[711, 18, 123, 289, 779],
	[1010, 16, 124, 290, 1080],
	[114, 330, 124, 289, 182],
	[422, 325, 124, 294, 489],
	[720, 328, 122, 293, 775],
	[1015, 326, 126, 292, 1072],
	[125, 637, 119, 299, 184.5],
	[424, 635, 122, 303, 483.5],
	[713, 637, 121, 300, 772.5],
	[1016, 637, 118, 300, 1072],
	[111, 951, 142, 283, 181.5],
	[410, 950, 162, 283, 485.5],
	[701, 956, 149, 277, 775],
	[1004, 952, 148, 281, 1077.5],
]

# Absolute alpha bounding boxes (x, y, w, h, anchorX) for the 4x4 hero FRONT atlas.
const HERO_FRONT_RECTS: Array = [
	[118, 8, 131, 306, 184],
	[420, 5, 130, 308, 485.5],
	[715, 7, 134, 307, 779.5],
	[1027, 7, 134, 306, 1094],
	[112, 317, 135, 310, 178.5],
	[416, 319, 136, 308, 476.5],
	[717, 321, 134, 306, 782],
	[1033, 321, 132, 306, 1097.5],
	[109, 627, 132, 313, 174.5],
	[412, 627, 137, 313, 477.5],
	[714, 633, 132, 307, 779.5],
	[1029, 627, 131, 313, 1095],
	[103, 947, 148, 303, 176.5],
	[407, 946, 144, 303, 478.5],
	[709, 947, 146, 303, 781.5],
	[1021, 947, 146, 302, 1093.5],
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

	var hero_back_tex: Texture2D = load(HERO_BACK_TEX_PATH) as Texture2D
	if hero_back_tex == null:
		push_error("Failed to load hero back atlas: " + HERO_BACK_TEX_PATH)
		return false

	var hero_front_tex: Texture2D = load(HERO_FRONT_TEX_PATH) as Texture2D
	if hero_front_tex == null:
		push_error("Failed to load hero front atlas: " + HERO_FRONT_TEX_PATH)
		return false

	var npc_tex: Texture2D = load(NPC_TEX_PATH) as Texture2D
	if npc_tex == null:
		push_error("Failed to load NPC atlas: " + NPC_TEX_PATH)
		return false

	var traveler_frames: SpriteFrames = _build_traveler_frames(
		hero_tex, HERO_RECTS, "side",
		hero_back_tex, HERO_BACK_RECTS, "back",
		hero_front_tex, HERO_FRONT_RECTS, "front"
	)
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


func _build_traveler_frames(
	side_tex: Texture2D, side_rects: Array, side_prefix: String,
	back_tex: Texture2D, back_rects: Array, back_prefix: String,
	front_tex: Texture2D, front_rects: Array, front_prefix: String
) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	# Per-view animations: walk (0..7, 15 fps loop), idle (8..11, 4 fps loop),
	# attack (12..15, 12 fps non-loop).
	for view in [
		[side_tex, side_rects, side_prefix],
		[back_tex, back_rects, back_prefix],
		[front_tex, front_rects, front_prefix],
	]:
		var tex: Texture2D = view[0]
		var rects: Array = view[1]
		var prefix: String = view[2]

		frames.add_animation("walk_" + prefix)
		frames.add_animation("idle_" + prefix)
		frames.add_animation("attack_" + prefix)

		_add_hero_animation(frames, "walk_" + prefix, tex, rects, 0, 8, 15.0, true)
		_add_hero_animation(frames, "idle_" + prefix, tex, rects, 8, 12, 4.0, true)
		_add_hero_animation(frames, "attack_" + prefix, tex, rects, 12, 16, 12.0, false)

	# Legacy aliases: identical SIDE resources for scene autoplay / backward compatibility.
	frames.add_animation("walk")
	frames.add_animation("idle")
	frames.add_animation("attack")
	_add_hero_animation(frames, "walk", side_tex, side_rects, 0, 8, 15.0, true)
	_add_hero_animation(frames, "idle", side_tex, side_rects, 8, 12, 4.0, true)
	_add_hero_animation(frames, "attack", side_tex, side_rects, 12, 16, 12.0, false)

	# Rendering metadata: scale + vertical offset so the hero stands 1.8 m tall
	# with feet grounded when Body.position.y = baseline_offset_pixels * pixel_size.
	frames.set_meta(StringName("pixel_size_side"), 1.8 / 303.5)
	frames.set_meta(StringName("pixel_size_back"), 1.8 / 300.5)
	frames.set_meta(StringName("pixel_size_front"), 1.8 / 311.5)
	frames.set_meta(StringName("baseline_offset_pixels"), 182.0)

	return frames


func _add_hero_animation(
	frames: SpriteFrames,
	anim_name: String,
	tex: Texture2D,
	rects: Array,
	start_index: int,
	end_index: int,
	fps: float,
	loop: bool
) -> void:
	var canvas_w := 384.0
	var canvas_h := 384.0
	var feet_baseline := 374.0

	for i in range(start_index, end_index):
		var rect_arr: Array = rects[i]
		var rx: float = float(rect_arr[0])
		var ry: float = float(rect_arr[1])
		var rw: float = float(rect_arr[2])
		var rh: float = float(rect_arr[3])
		var anchor_x: float = float(rect_arr[4])

		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(rx, ry, rw, rh)
		at.filter_clip = true

		var margin := Rect2()
		margin.size = Vector2(canvas_w - rw, canvas_h - rh)
		margin.position = Vector2(192.0 - (anchor_x - rx), feet_baseline - rh)
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
