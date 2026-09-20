extends SceneTree
## Headless tool: rebuilds ONLY the run_back / run_front / run_side clips in
## res://assets/characters/courtyard/traveler_frames.tres from the measured
## alpha regions of the run atlases. All other clips and metadata are preserved.
## Idempotent: safe to re-run.
## Run: godot --headless --script res://scripts/tools/build_courtyard_run_frames.gd

const FRAMES_PATH := "res://assets/characters/courtyard/traveler_frames.tres"
const RUN_BACK_FRONT_TEX_PATH := "res://assets/characters/courtyard/traveler-run-v1.png"
const RUN_SIDE_TEX_PATH := "res://assets/characters/courtyard/traveler-run-spaced-v2.png"

const CANVAS_W := 384.0
const CANVAS_H := 384.0
const FEET_BASELINE := 374.0
const RUN_FPS := 15.0

# Measured alpha bounding boxes: [x, y, width, height, anchorX].
# BACK + FRONT come from traveler-run-v1.png; SIDE (bottom two rows) from
# traveler-run-spaced-v2.png.
const RUN_BACK_RECTS: Array = [
	[93, 16, 139, 264, 162],
	[327, 17, 139, 263, 396],
	[562, 16, 138, 264, 630.5],
	[799, 17, 135, 260, 866],
	[99, 291, 140, 262, 168.5],
	[335, 291, 140, 262, 404.5],
	[563, 291, 140, 261, 632.5],
	[802, 292, 137, 258, 870],
]

const RUN_FRONT_RECTS: Array = [
	[94, 556, 146, 259, 166.5],
	[334, 560, 142, 259, 404.5],
	[565, 557, 143, 262, 636],
	[803, 558, 139, 257, 872],
	[90, 819, 143, 260, 161],
	[322, 821, 146, 259, 394.5],
	[559, 823, 144, 260, 630.5],
	[794, 823, 141, 256, 864],
]

const RUN_SIDE_RECTS: Array = [
	[54, 913, 176, 241, 141.5],
	[309, 913, 155, 238, 386],
	[538, 914, 175, 243, 625],
	[775, 913, 180, 244, 864.5],
	[49, 1205, 181, 244, 139],
	[299, 1203, 172, 241, 384.5],
	[529, 1204, 187, 245, 622],
	[774, 1203, 174, 246, 860.5],
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
	var frames := frames_res as SpriteFrames

	var back_front_tex: Texture2D = load(RUN_BACK_FRONT_TEX_PATH) as Texture2D
	if back_front_tex == null:
		push_error("Failed to load run back/front atlas: " + RUN_BACK_FRONT_TEX_PATH)
		return false

	var side_tex: Texture2D = load(RUN_SIDE_TEX_PATH) as Texture2D
	if side_tex == null:
		push_error("Failed to load run side atlas: " + RUN_SIDE_TEX_PATH)
		return false

	# Rebuild only the three run clips; everything else stays untouched.
	for anim_name in ["run_back", "run_front", "run_side"]:
		if frames.has_animation(anim_name):
			frames.remove_animation(anim_name)

	var back_ok := _add_run_clip(frames, "run_back", back_front_tex, RUN_BACK_RECTS)
	var front_ok := _add_run_clip(frames, "run_front", back_front_tex, RUN_FRONT_RECTS)
	var side_ok := _add_run_clip(frames, "run_side", side_tex, RUN_SIDE_RECTS)
	if not (back_ok and front_ok and side_ok):
		return false

	# Per-view run scale: 1.8 m tall against the measured frame heights.
	frames.set_meta(StringName("pixel_size_run_back"), 1.8 / 264.0)
	frames.set_meta(StringName("pixel_size_run_front"), 1.8 / 265.0)
	frames.set_meta(StringName("pixel_size_run_side"), 1.8 / 246.0)

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
