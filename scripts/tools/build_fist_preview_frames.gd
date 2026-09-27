extends SceneTree
## Offline builder for the COMBAT-01 fist-preview comparison sandbox.
## Builds four SpriteFrames (novice/trained x bare/pack) from the existing
## traveler frames plus six 2x2 novice pose atlases. No source mutation.
## All pixel measurements are done on ORIGINAL PNG files loaded from disk,
## never on compressed get_image() output of imported textures.

const SRC_DIR := "res://assets/characters/courtyard/"
const OUT_DIR := "res://assets/characters/courtyard/fist-preview/"
const NOVICE_SRC := SRC_DIR + "traveler_frames.tres"
const PACK_SRC := SRC_DIR + "traveler_backpack_frames.tres"

const VIEWS: Array[String] = ["front", "back", "side"]
const PHASES: Array[String] = ["windup", "contact", "follow_through", "recovery"]
const ATTACK_ACTIONS: Array[String] = ["attack_front", "attack_back", "attack_side"]
const IDLE_ACTIONS: Array[String] = ["idle_front", "idle_back", "idle_side"]

const ALPHA_THRESHOLD := 0.2
const FOOT_BAND_FRACTION := 0.125 # bottom 12.5% of silhouette height
const ATLAS_PX := 1254 # actual novice PNG size (627x627 cells)
const CELL_PAD := 2 # small padding inside cell, never below the sole


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: Array[String] = []
	_build(errors)
	if not errors.is_empty():
		for e in errors:
			push_error("FIST_PREVIEW: " + e)
		printerr("ASHBOUND_FIST_PREVIEW_FRAMES_FAILED")
		quit(1)
	else:
		print("ASHBOUND_FIST_PREVIEW_FRAMES_READY")
		quit(0)


func _build(errors: Array[String]) -> void:
	var novice_src: SpriteFrames = _load_frames(NOVICE_SRC, errors)
	var pack_src: SpriteFrames = _load_frames(PACK_SRC, errors)
	if novice_src == null or pack_src == null:
		return

	# Load the six novice pose atlases (2x2 grids of phase poses).
	var pngs := {} # "novice-<view>" / "novice-<view>-pack" -> Texture2D
	for view in VIEWS:
		for pack in [false, true]:
			var suffix := "-pack" if pack else ""
			var rel := OUT_DIR + "novice-" + view + suffix + ".png"
			var tex: Texture2D = load(rel)
			if tex == null:
				errors.push_back("missing novice atlas: " + rel)
				continue
			pngs["novice-" + view + suffix] = tex

	# Per-view cell records: phase -> {tex, region, bbox}.
	var novice_cells := {} # view -> Dictionary(phase -> cell)
	var pack_cells := {}
	for view in VIEWS:
		novice_cells[view] = _grid_cells(pngs.get("novice-" + view), view, "novice", errors)
		pack_cells[view] = _grid_cells(pngs.get("novice-" + view + "-pack"), view, "novice-pack", errors)

	# Calibrate per-view scale from the BARE recovery pose vs source idle.
	var meta := {} # view -> {pixel_size_attack, baseline_offset_pixels_attack}
	for view in VIEWS:
		meta[view] = _calibrate_scale(novice_src, novice_cells.get(view, {}), view, errors)

	# Validate all clips and cells BEFORE mutating any output resource.
	if not _validate_sources(novice_src, pack_src, novice_cells, pack_cells, meta, errors):
		return

	# Build all four output resources BEFORE saving anything.
	var out_novice := _build_bare(novice_src, novice_cells, meta, "novice", false, errors)
	var out_trained: Resource = null
	var out_nov_pack: Resource = null
	var out_trn_pack: Resource = null
	if errors.is_empty():
		out_trained = _build_trained(novice_src, "trained", false, errors)
	if errors.is_empty():
		out_nov_pack = _build_bare(pack_src, pack_cells, meta, "novice-pack", true, errors)
	if errors.is_empty():
		out_trn_pack = _build_trained(pack_src, "trained-pack", true, errors)

	if errors.is_empty():
		for res in [out_novice, out_trained, out_nov_pack, out_trn_pack]:
			if res == null:
				errors.push_back("output resource failed to build")
				break

	var outputs := {
		out_novice: OUT_DIR + "novice_frames.tres",
		out_trained: OUT_DIR + "trained_frames.tres",
		out_nov_pack: OUT_DIR + "novice_pack_frames.tres",
		out_trn_pack: OUT_DIR + "trained_pack_frames.tres",
	}
	if errors.is_empty():
		var out_dir := ProjectSettings.globalize_path(OUT_DIR)
		if not DirAccess.dir_exists_absolute(out_dir):
			DirAccess.make_dir_recursive_absolute(out_dir)
		for res in outputs.keys():
			var path: String = outputs[res]
			var err: int = ResourceSaver.save(res, ProjectSettings.globalize_path(path))
			if err != OK:
				errors.push_back("failed to save %s (err=%d)" % [path, err])


func _load_frames(path: String, errors: Array[String]) -> SpriteFrames:
	var res := load(path)
	if res == null or not (res is SpriteFrames):
		errors.push_back("missing or invalid source: " + path)
		return null
	return res as SpriteFrames


## Load the ORIGINAL PNG from disk for pixel-accurate offline measurement.
func _load_png(res_path: String, errors: Array[String], label: String) -> Image:
	if res_path.is_empty():
		errors.push_back("%s: empty png path" % label)
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	if img == null:
		errors.push_back("%s: cannot load original png: %s" % [label, res_path])
		return null
	if img.detect_alpha() == Image.ALPHA_NONE:
		errors.push_back("%s: png has no alpha channel: %s" % [label, res_path])
		return null
	return img


## Validate a NEW 2x2 novice atlas PNG: square 1254x1254 (627x627 cells).
func _validate_new_atlas(img: Image, label: String, errors: Array[String]) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	if w != h or w <= 0 or h <= 0:
		errors.push_back("%s: atlas must be square and positive, got %dx%d" % [label, w, h])
		return false
	if w % 2 != 0 or h % 2 != 0:
		errors.push_back("%s: total atlas dimension must be even, got %dx%d" % [label, w, h])
		return false
	if w != ATLAS_PX:
		errors.push_back("%s: expected %d x %d atlas, got %dx%d" % [label, ATLAS_PX, ATLAS_PX, w, h])
		return false
	return true


func _grid_cells(tex: Texture2D, view: String, label: String, errors: Array[String]) -> Dictionary:
	var cells := {}
	if tex == null:
		errors.push_back("%s %s: atlas texture missing" % [label, view])
		return cells
	var png_path: String = tex.resource_path
	var img := _load_png(png_path, errors, "%s %s" % [label, view])
	if img == null:
		return cells
	if not _validate_new_atlas(img, "%s %s" % [label, view], errors):
		return cells
	var cell := img.get_width() / 2
	for i in 4:
		var phase: String = PHASES[i]
		var col := i % 2
		var row := i / 2
		var region := Rect2i(col * cell, row * cell, cell, cell)
		var bbox := _alpha_bbox(img, region)
		if bbox.size.x <= 0 or bbox.size.y <= 0:
			errors.push_back("%s %s/%s: empty pose cell" % [label, view, phase])
			continue
		if _bbox_touches_cell_border(bbox, region):
			errors.push_back("%s %s/%s: alpha touches cell border (clipped grid)" % [label, view, phase])
			continue
		cells[phase] = {"tex": tex, "region": region, "bbox": bbox}
	return cells


func _bbox_touches_cell_border(bbox: Rect2i, region: Rect2i) -> bool:
	if bbox.position.x <= region.position.x or bbox.position.y <= region.position.y:
		return true
	if bbox.end.x >= region.end.x or bbox.end.y >= region.end.y:
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


func _calibrate_scale(src: SpriteFrames, cells: Dictionary, view: String, errors: Array[String]) -> Dictionary:
	var idle_action := "idle_" + view
	if not src.has_animation(idle_action):
		errors.push_back("source lacks clip: " + idle_action)
		return {}
	var frame0: Texture2D = src.get_frame_texture(idle_action, 0)
	if frame0 == null or not (frame0 is AtlasTexture):
		errors.push_back("idle_%s frame0 is not an AtlasTexture" % view)
		return {}
	var idle_atlas: AtlasTexture = frame0 as AtlasTexture
	if idle_atlas.atlas == null:
		errors.push_back("idle_%s atlas texture missing" % view)
		return {}
	# Measure on the ORIGINAL PNG of the idle atlas, not the compressed image.
	var idle_img := _load_png(idle_atlas.atlas.resource_path, errors, "idle_%s atlas" % view)
	if idle_img == null:
		return {}
	var idle_bbox := _alpha_bbox(idle_img, idle_atlas.region)
	if idle_bbox.size.y <= 0:
		errors.push_back("idle_%s frame0 has no alpha" % view)
		return {}
	var src_px_size: float = _meta_float(src, "pixel_size_" + view, 1.0)
	if not (src_px_size > 0.0 and is_finite(src_px_size)):
		errors.push_back("idle_%s source pixel_size invalid: %f" % [view, src_px_size])
		return {}
	var ref_world_h := float(idle_bbox.size.y) * src_px_size

	var rec_cell: Dictionary = cells.get("recovery", {})
	var rec_tex: Texture2D = rec_cell.get("tex")
	var rec_region: Rect2i = rec_cell.get("region", Rect2i())
	if rec_tex == null or rec_region.size.x <= 0:
		errors.push_back("novice %s recovery cell missing" % view)
		return {}
	var rec_img := _load_png(rec_tex.resource_path, errors, "novice %s atlas" % view)
	if rec_img == null:
		return {}
	var rec_bbox := _alpha_bbox(rec_img, rec_region)
	if rec_bbox.size.y <= 0:
		errors.push_back("novice %s recovery pose empty" % view)
		return {}
	var new_px_size := ref_world_h / float(rec_bbox.size.y)
	if not (new_px_size > 0.0 and is_finite(new_px_size)):
		errors.push_back("novice %s calibrated scale invalid: %f" % [view, new_px_size])
		return {}
	return {"pixel_size_attack": new_px_size, "baseline_offset_pixels_attack": float(rec_region.size.y) / 2.0}


func _meta_float(frames: SpriteFrames, key: String, default_val: float) -> float:
	var md: Variant = frames.get_meta(key, default_val)
	if md is float:
		return md
	if md is int:
		return float(md)
	return default_val


## Validate all source clips and cells before any set_frame mutation.
func _validate_sources(novice_src: SpriteFrames, pack_src: SpriteFrames, novice_cells: Dictionary, pack_cells: Dictionary, meta: Dictionary, errors: Array[String]) -> bool:
	for src in [novice_src, pack_src]:
		if src == null:
			errors.push_back("source frames missing")
			return false
		for action in ATTACK_ACTIONS:
			if not src.has_animation(action):
				errors.push_back("source lacks clip: " + action)
				return false
			if src.get_frame_count(action) != 4:
				errors.push_back("%s must have exactly 4 frames, has %d" % [action, src.get_frame_count(action)])
				return false
		for action in IDLE_ACTIONS:
			if not src.has_animation(action):
				errors.push_back("source lacks clip: " + action)
				return false
			if src.get_frame_count(action) <= 0:
				errors.push_back("%s must have >0 frames" % action)
				return false
	for view in VIEWS:
		var m: Dictionary = meta.get(view, {})
		if m.is_empty():
			errors.push_back("calibration missing for " + view)
			return false
		var px_size: float = m["pixel_size_attack"]
		if not (px_size > 0.0 and is_finite(px_size)):
			errors.push_back("calibrated scale invalid for %s: %f" % [view, px_size])
			return false
		for cells in [novice_cells.get(view, {}), pack_cells.get(view, {})]:
			for phase in PHASES:
				var cell: Dictionary = cells.get(phase, {})
				if cell.is_empty():
					errors.push_back("cell missing: %s/%s" % [view, phase])
					return false
	return true


func _make_canvas_texture(cell: Dictionary, px_size: float, errors: Array[String], label: String) -> AtlasTexture:
	var tex_in: Texture2D = cell["tex"]
	var region: Rect2i = cell["region"]
	var bbox: Rect2i = cell["bbox"]
	# Measure on the ORIGINAL PNG for the foot anchor.
	var img := _load_png(tex_in.resource_path, errors, label)
	if img == null:
		return null
	var anchor := _foot_anchor(img, region)

	# Crop to alpha bounds with small padding, clamped to cell edges.
	var pad_x := mini(CELL_PAD, maxi(0, (region.size.x - bbox.size.x) / 2))
	var pad_top := mini(CELL_PAD, maxi(0, (bbox.position.y - region.position.y)))
	var crop := Rect2i(bbox.position.x - pad_x, bbox.position.y - pad_top,
			bbox.size.x + pad_x * 2, bbox.size.y + pad_top)
	# Clamp crop to the source cell.
	crop.position.x = clampi(crop.position.x, region.position.x, region.end.x - 1)
	crop.position.y = clampi(crop.position.y, region.position.y, region.end.y - 1)
	crop.size.x = mini(crop.size.x, region.end.x - crop.position.x)
	crop.size.y = mini(crop.size.y, region.end.y - crop.position.y)
	if crop.size.x <= 0 or crop.size.y <= 0:
		errors.push_back("%s: crop empty after clamping" % label)
		return null

	var out := AtlasTexture.new()
	out.atlas = tex_in
	out.region = crop
	# Virtual canvas is derived from the cell size (627x627 for 1254 atlases).
	var canvas := Vector2(region.size)
	# margin is in pixels; virtual size = region.size + margin.size = canvas.
	var margin := Rect2(
			canvas.x / 2.0 - (anchor.x - float(crop.position.x)),
			canvas.y - (float(bbox.end.y) - float(crop.position.y)),
			canvas.x - crop.size.x,
			canvas.y - crop.size.y)
	if margin.position.x < 0.0 or margin.position.y < 0.0:
		errors.push_back("%s: negative margin position %s" % [label, str(margin.position)])
		return null
	var virtual := Vector2(crop.size) + margin.size
	if not is_equal_approx(virtual.x, canvas.x) or not is_equal_approx(virtual.y, canvas.y):
		errors.push_back("%s: canvas mismatch %s vs %s" % [label, str(virtual), str(canvas)])
		return null
	# Full crop+margin must fit the virtual canvas (check both axes explicitly).
	var end := margin.position + Vector2(crop.size)
	if end.x > canvas.x or end.y > canvas.y:
		errors.push_back("%s: crop+margin exceeds canvas %s" % [label, str(canvas)])
		return null
	out.margin = margin
	return out


func _build_bare(src: SpriteFrames, cells: Dictionary, meta: Dictionary, label: String, is_pack: bool, errors: Array[String]) -> Resource:
	var out := src.duplicate(true) as SpriteFrames
	if out == null:
		errors.push_back("cannot duplicate source for " + label)
		return null
	out.set_meta("fist_preview_technique", "novice")
	out.set_meta("fist_preview_backpack", is_pack)
	for view in VIEWS:
		var m: Dictionary = meta.get(view, {})
		if m.is_empty():
			errors.push_back("%s calibration missing for %s" % [label, view])
			return null
		var px_size: float = m["pixel_size_attack"]
		var baseline: float = m["baseline_offset_pixels_attack"]
		var action := "attack_" + view
		if not out.has_animation(action):
			errors.push_back("%s source lacks clip: %s" % [label, action])
			return null
		var view_cells: Dictionary = cells.get(view, {})
		for i in 4:
			var phase: String = PHASES[i]
			var cell: Dictionary = view_cells.get(phase, {})
			if cell.is_empty():
				errors.push_back("%s %s/%s cell missing" % [label, view, phase])
				return null
			var tex := _make_canvas_texture(cell, px_size, errors, "%s %s/%s" % [label, view, phase])
			if tex == null:
				return null
			out.set_frame(action, i, tex, src.get_frame_duration(action, i))
		out.set_meta("pixel_size_attack_" + view, px_size)
		out.set_meta("baseline_offset_pixels_attack", baseline)
	# Alias "attack" mirrors the side attack clip (speed/loop/count preserved).
	if not out.has_animation("attack"):
		errors.push_back("%s source lacks alias clip: attack" % label)
		return null
	if out.get_frame_count("attack") != 4:
		errors.push_back("%s alias attack must have exactly 4 frames, has %d" % [label, out.get_frame_count("attack")])
		return null
	for i in 4:
		var side_tex: Texture2D = out.get_frame_texture("attack_side", i)
		if side_tex == null:
			errors.push_back("%s attack_side frame %d missing for alias" % [label, i])
			return null
		out.set_frame("attack", i, side_tex, src.get_frame_duration("attack", i))
	return out


func _build_trained(src: SpriteFrames, label: String, is_pack: bool, errors: Array[String]) -> Resource:
	var out := src.duplicate(true) as SpriteFrames
	if out == null:
		errors.push_back("cannot duplicate source for " + label)
		return null
	out.set_meta("fist_preview_technique", "trained")
	out.set_meta("fist_preview_backpack", is_pack)
	for view in VIEWS:
		var idle_action := "idle_" + view
		var attack_action := "attack_" + view
		if not out.has_animation(idle_action) or not out.has_animation(attack_action):
			errors.push_back("%s source lacks clip for %s" % [label, view])
			return null
		var guard_tex: Texture2D = out.get_frame_texture(attack_action, 0)
		if guard_tex == null:
			errors.push_back("%s %s attack frame0 missing" % [label, view])
			return null
		var count := out.get_frame_count(idle_action)
		for i in count:
			out.set_frame(idle_action, i, guard_tex, src.get_frame_duration(idle_action, i))
	# Alias "idle" mirrors the side attack frame 0 (original durations kept).
	if not out.has_animation("idle"):
		errors.push_back("%s source lacks alias clip: idle" % label)
		return null
	var idle_count := out.get_frame_count("idle")
	if idle_count <= 0:
		errors.push_back("%s alias idle must have >0 frames, has %d" % [label, idle_count])
		return null
	var side_idle_tex: Texture2D = out.get_frame_texture("attack_side", 0)
	if side_idle_tex == null:
		errors.push_back("%s attack_side frame 0 missing for idle alias" % label)
		return null
	for i in idle_count:
		out.set_frame("idle", i, side_idle_tex, src.get_frame_duration("idle", i))
	return out
