extends SceneTree
## Headless tool: rebuilds ONLY the run_back / run_front / run_side clips in
## res://assets/characters/courtyard/traveler_frames.tres from the measured
## alpha regions of the v3 run atlases. All other clips and metadata are
## preserved. Idempotent: safe to re-run.
## Run: godot --headless --script res://scripts/tools/build_courtyard_run_frames.gd

const FRAMES_PATH := "res://assets/characters/courtyard/traveler_frames.tres"
const RUN_SIDE_TEX_PATH := "res://assets/characters/courtyard/traveler-run-side-v3.png"
const RUN_BACK_TEX_PATH := "res://assets/characters/courtyard/traveler-run-back-v3.png"
const RUN_FRONT_TEX_PATH := "res://assets/characters/courtyard/traveler-run-front-v3.png"

const CANVAS_W := 384.0
const CANVAS_H := 384.0
const FEET_BASELINE := 374.0
const METADATA_OFFSET := 182.0
const RUN_FPS := 15.0

# Measured alpha bounding boxes (top 8 frames (two rows) only; bottom control
# rows are NOT used): [x, y, width, height, anchorX].
const RUN_SIDE_RECTS: Array = [
	[39, 29, 216, 279, 146.5],
	[424, 34, 158, 274, 502.5],
	[669, 25, 219, 282, 778],
	[989, 11, 216, 290, 1096.5],
	[39, 339, 228, 285, 152.5],
	[403, 349, 196, 275, 500.5],
	[676, 337, 220, 286, 785.5],
	[988, 325, 211, 285, 1093],
]

const RUN_BACK_RECTS: Array = [
	[111, 39, 145, 287, 183],
	[403, 46, 154, 284, 479.5],
	[695, 49, 151, 271, 770],
	[1009, 43, 151, 284, 1084],
	[112, 351, 148, 278, 185.5],
	[420, 353, 145, 276, 492],
	[703, 354, 153, 255, 779],
	[1017, 353, 150, 276, 1091.5],
]

const RUN_FRONT_RECTS: Array = [
	[118, 16, 147, 309, 191],
	[405, 26, 151, 297, 480],
	[703, 26, 157, 299, 781],
	[1002, 15, 156, 279, 1079.5],
	[105, 340, 151, 300, 180],
	[401, 348, 154, 292, 477.5],
	[694, 345, 154, 295, 770.5],
	[1004, 335, 152, 278, 1079.5],
]


func _initialize() -> void:
	_run_deferred.call_deferred()


func _run_deferred() -> void:
	var ok := bool(_build())
	if ok:
		print("ASHBOUND_RUN_FRAMES_READY")
		quit(0)
	else:
		push_error("Courtyard run frames build failed.")
		quit(1)


func _build() -> bool:
	var frames_res: Resource = load(FRAMES_PATH)
	if frames_res == null or not (frames_res is SpriteFrames):
		push_error("Failed to load SpriteFrames resource: " + FRAMES_PATH)
		return false
	var frames := frames_res.duplicate(true) as SpriteFrames

	var side_tex: Texture2D = load(RUN_SIDE_TEX_PATH) as Texture2D
	if side_tex == null:
		push_error("Failed to load run side atlas: " + RUN_SIDE_TEX_PATH)
		return false

	var back_tex: Texture2D = load(RUN_BACK_TEX_PATH) as Texture2D
	if back_tex == null:
		push_error("Failed to load run back atlas: " + RUN_BACK_TEX_PATH)
		return false

	var front_tex: Texture2D = load(RUN_FRONT_TEX_PATH) as Texture2D
	if front_tex == null:
		push_error("Failed to load run front atlas: " + RUN_FRONT_TEX_PATH)
		return false

	# Rebuild only the three run clips; everything else stays untouched.
	for anim_name in ["run_back", "run_front", "run_side"]:
		if frames.has_animation(anim_name):
			frames.remove_animation(anim_name)

	var back_ok := _add_run_clip(frames, "run_back", back_tex, RUN_BACK_RECTS)
	var front_ok := _add_run_clip(frames, "run_front", front_tex, RUN_FRONT_RECTS)
	var side_ok := _add_run_clip(frames, "run_side", side_tex, RUN_SIDE_RECTS)
	if not (back_ok and front_ok and side_ok):
		return false

	# Visual calibration of head/torso size against the reference idle, judged
	# by eye in Godot with a fixed camera (not an automatic measurement and not
	# a silhouette normalization to standing height). The 0.90 factors were
	# chosen because side/front at 0.90 matched the original anatomy while back
	# at 1.00 still showed an enlarged head and torso.
	frames.set_meta(StringName("pixel_size_run_back"), (1.8 / 300.5) * 0.90)
	frames.set_meta(StringName("pixel_size_run_front"), (1.8 / 311.5) * 0.90)
	frames.set_meta(StringName("pixel_size_run_side"), (1.8 / 303.5) * 0.90)

	var err := ResourceSaver.save(frames, FRAMES_PATH)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [FRAMES_PATH, err])
		return false
	print("Saved: " + FRAMES_PATH)
	return true


func _add_run_clip(
	frames: SpriteFrames,
	anim_name: String,
	tex: Texture2D,
	rects: Array
) -> bool:
	if rects.size() != 8:
		push_error("Run clip %s expects 8 frames, got %d" % [anim_name, rects.size()])
		return false

	frames.add_animation(anim_name)

	for i in range(rects.size()):
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
		margin.size = Vector2(CANVAS_W - rw, CANVAS_H - rh)
		margin.position = Vector2(192.0 - (anchor_x - rx), FEET_BASELINE - rh)
		at.margin = margin

		frames.add_frame(anim_name, at, 1.0)

	frames.set_animation_speed(anim_name, RUN_FPS)
	frames.set_animation_loop(anim_name, true)
	return true
