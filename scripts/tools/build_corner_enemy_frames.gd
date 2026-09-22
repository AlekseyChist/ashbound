extends SceneTree
## Offline builder: extracts 18 connected silhouettes per source sheet and packs
## them into a 3x6 (512px cells) atlas + SpriteFrames .tres for wolf/guard.
##
## Usage (run by Codex, not this script itself):
##   godot --headless -s scripts/tools/build_corner_enemy_frames.gd
##
## Phases:
##   1) pack-only (default): load ORIGINAL png files, validate, write atlas PNGs.
##   2) After the engine imports the new atlases, run again with --with-frames
##      to (re)write the .tres SpriteFrames resources referencing the imported
##      Texture2D at res://...-atlas.png.
##
## Build marker on success: ASHBOUND_CORNER_ENEMY_FRAMES_OK sheets=2 poses=36

const ALPHA_CUTOFF := 0.12          # source alpha below this is invisible under game alpha-scissor 0.25
const MIN_COMPONENT_PIXELS := 1800 # discard tiny disconnected specks
const EXPECTED_POSES := 18
const CELL_SIZE := 512
const COLS := 3
const ROWS := 6
const ATLAS_W := COLS * CELL_SIZE   # 1536
const ATLAS_H := ROWS * CELL_SIZE   # 3072
const GROUND_Y := 492               # lowest pixel row inside a cell
const ANCHOR_X := 256               # foot anchor x inside a cell
const MAX_COMPONENT_DIM := 480      # reject oversized components
const ATTACK_AIR_GAP := 12          # extra px above ground for wolf attack row (row 4)
const BASELINE_OFFSET_PIXELS := 236.0  # 492 - 256

const ROW_NAMES := ["idle", "walkA", "walkB", "windup", "attack", "hit"]
const VIEWS := ["front", "back", "side"]
const VIEW_HEIGHTS := { "guard": 1.85, "wolf": 1.0 }

var _errors: PackedStringArray = []


func _init() -> void:
	var with_frames := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--with-frames":
			with_frames = true
		else:
			printerr("BUILD FAILED:")
			printerr("  - unknown argument: %s" % arg)
			quit(1)
			return
	var ok := _build(with_frames)
	if not ok:
		printerr("BUILD FAILED:")
		for e in _errors:
			printerr("  - " + e)
		quit(1)
	else:
		if with_frames:
			print("ASHBOUND_CORNER_ENEMY_FRAMES_OK sheets=2 poses=36")
		else:
			print("PACK_OK sheets=2 poses=36")
		quit(0)


func _build(with_frames: bool) -> bool:
	var manifest_lines: PackedStringArray = []
	var jobs: Array = []
	for name in ["wolf", "guard"]:
		var src_path := "res://assets/characters/courtyard/enemy-preview/%s.png" % name
		var atlas_path := "res://assets/characters/courtyard/enemy-preview/%s-atlas.png" % name
		var frames_path := "res://assets/characters/courtyard/enemy-preview/%s_frames.tres" % name
		var src_file := ProjectSettings.globalize_path(src_path)
		if not FileAccess.file_exists(src_file):
			_errors.append("%s: source file missing: %s" % [name, src_file])
			continue

		var img := Image.load_from_file(src_file)
		if img == null or img.is_empty():
			_errors.append("%s: failed to load image from %s" % [name, src_file])
			continue
		if img.get_width() != 1254 or img.get_height() != 1254:
			_errors.append("%s: expected 1254x1254 source, got %dx%d" % [name, img.get_width(), img.get_height()])
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			_errors.append("%s: source is not RGBA8" % name)
			continue

		var hash_str := _file_sha256_hex(src_file)
		manifest_lines.append("source=%s sha256=%s alpha_cutoff=%.3f" % [src_path, hash_str, ALPHA_CUTOFF])

		# --- connected components (8-connected flood fill on alpha > cutoff) ---
		var w := img.get_width()
		var h := img.get_height()
		var labels := PackedInt32Array()
		labels.resize(w * h)
		labels.fill(-1)
		var stack: Array[int] = []
		var components: Array[Dictionary] = []
		var next_label := 0
		for y in h:
			for x in w:
				var idx := y * w + x
				if labels[idx] != -1:
					continue
				if img.get_pixelv(Vector2i(x, y)).a <= ALPHA_CUTOFF:
					continue
				# BFS/DFS flood fill
				labels[idx] = next_label
				stack.clear()
				stack.append(idx)
				var pixels: Array[int] = []
				var min_x := x
				var max_x := x
				var min_y := y
				var max_y := y
				while not stack.is_empty():
					var cur: int = stack.pop_back()
					pixels.append(cur)
					var cx: int = cur % w
					var cy: int = cur / w
					if cx < min_x: min_x = cx
					if cx > max_x: max_x = cx
					if cy < min_y: min_y = cy
					if cy > max_y: max_y = cy
					for dy in [-1, 0, 1]:
						for dx in [-1, 0, 1]:
							if dx == 0 and dy == 0:
								continue
							var nx: int = cx + dx
							var ny: int = cy + dy
							if nx < 0 or nx >= w or ny < 0 or ny >= h:
								continue
							var nidx: int = ny * w + nx
							if labels[nidx] != -1:
								continue
							if img.get_pixelv(Vector2i(nx, ny)).a <= ALPHA_CUTOFF:
								continue
							labels[nidx] = next_label
							stack.append(nidx)
				components.append({
					"label": next_label,
					"pixels": pixels,
					"min_x": min_x, "max_x": max_x,
					"min_y": min_y, "max_y": max_y,
				})
				next_label += 1

		# discard specks
		var big: Array[Dictionary] = []
		for c in components:
			if (c["pixels"] as Array[int]).size() >= MIN_COMPONENT_PIXELS:
				big.append(c)
		if big.size() != EXPECTED_POSES:
			_errors.append("%s: expected exactly %d large components, found %d" % [name, EXPECTED_POSES, big.size()])
			continue

		# assign columns by bbox horizontal center
		for c in big:
			var cx := (c["min_x"] as int + c["max_x"] as int) / 2.0
			if cx < 450.0:
				c["col"] = 0
			elif cx < 760.0:
				c["col"] = 1
			else:
				c["col"] = 2

		# sort each column by bbox top y, require exactly 6
		var columns: Array = [[], [], []]
		for c in big:
			(columns[c["col"] as int] as Array).append(c)
		var valid := true
		for ci in COLS:
			var col_arr: Array = columns[ci]
			if col_arr.size() != ROWS:
				_errors.append("%s: column %d has %d components, expected %d" % [name, ci, col_arr.size(), ROWS])
				valid = false
				break
			col_arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return (a["min_y"] as int) < (b["min_y"] as int))
		if not valid:
			continue

		# pixel_size calibrated from first idle component height (row 0 of each column)
		var view_height_m: float = VIEW_HEIGHTS[name] as float
		var pixel_sizes: Array = [0.0, 0.0, 0.0]
		for ci in COLS:
			var idle_c: Dictionary = columns[ci][0]
			var idle_h_px := (idle_c["max_y"] as int) - (idle_c["min_y"] as int) + 1
			if idle_h_px <= 0:
				_errors.append("%s: idle component height invalid in column %d" % [name, ci])
				valid = false
				break
			pixel_sizes[ci] = view_height_m / float(idle_h_px)
		if not valid:
			continue

		# --- preflight: check component dims before touching any output ---
		var atlas := Image.create_empty(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
		atlas.fill(Color(0, 0, 0, 0))
		var preflight_ok := true

		# --- pack into atlas (lossless copy of original pixels) ---
		for ci in COLS:
			for ri in ROWS:
				var c: Dictionary = columns[ci][ri]
				var min_x := c["min_x"] as int
				var min_y := c["min_y"] as int
				var max_x := c["max_x"] as int
				var max_y := c["max_y"] as int
				var cw := max_x - min_x + 1
				var ch := max_y - min_y + 1

				# ground anchor: center x of visible pixels in bottom 12.5% of component height
				var bottom_start := max_y - int(ceil(ch * 0.125)) + 1
				if bottom_start < min_y:
					bottom_start = min_y
				var xs: Array[int] = []
				for py in range(bottom_start, max_y + 1):
					for px in range(min_x, max_x + 1):
						if labels[py * w + px] == (c["label"] as int) and img.get_pixelv(Vector2i(px, py)).a > ALPHA_CUTOFF:
							xs.append(px)
				var anchor_local_x := cw / 2.0
				if name == "wolf":
					# long bite pose: paws far back, foot anchor overflows cell; use bbox center
					anchor_local_x = float(cw) / 2.0
				elif not xs.is_empty():
					# simple min/max center of the bottom band (documented as acceptable)
					var lo := xs[0]
					var hi := xs[0]
					for v in xs:
						if v < lo: lo = v
						if v > hi: hi = v
					anchor_local_x = float(lo + hi) / 2.0 - float(min_x)

				var dest_x := ci * CELL_SIZE
				var dest_y := ri * CELL_SIZE
				var ground_row := GROUND_Y
				if name == "wolf" and ri == 4: # attack row, all views
					ground_row = GROUND_Y - ATTACK_AIR_GAP
				var top_in_cell := ground_row - ch + 1
				var left_in_cell := int(round(ANCHOR_X - anchor_local_x))

				for py in range(min_y, max_y + 1):
					for px in range(min_x, max_x + 1):
						if labels[py * w + px] != (c["label"] as int):
							continue
						var col := img.get_pixelv(Vector2i(px, py))
						if col.a <= ALPHA_CUTOFF:
							continue
						var tx := dest_x + left_in_cell + (px - min_x)
						var ty := dest_y + top_in_cell + (py - min_y)
						# validate against this component's individual 512 cell, not the whole atlas
						if tx < dest_x or tx >= dest_x + CELL_SIZE or ty < dest_y or ty >= dest_y + CELL_SIZE:
							_errors.append("%s: component row=%d col=%d pixel out of cell bounds" % [name, ri, ci])
							preflight_ok = false
							continue
						atlas.set_pixelv(Vector2i(tx, ty), col)
		if not preflight_ok:
			continue
		for ci in COLS:
			for ri in ROWS:
				var c: Dictionary = columns[ci][ri]
				var cw := (c["max_x"] as int) - (c["min_x"] as int) + 1
				var ch := (c["max_y"] as int) - (c["min_y"] as int) + 1
				if cw > MAX_COMPONENT_DIM or ch > MAX_COMPONENT_DIM:
					_errors.append("%s: component row=%d col=%d size %dx%d exceeds %d" % [name, ri, ci, cw, ch, MAX_COMPONENT_DIM])
					preflight_ok = false
		if not preflight_ok:
			continue

		jobs.append({
			"atlas": atlas,
			"atlas_path": atlas_path,
			"frames_path": frames_path,
			"pixel_sizes": pixel_sizes,
			"name": name,
		})

	if not _errors.is_empty():
		return false

	for job in jobs:
		var jname: String = job["name"]
		var atlas: Image = job["atlas"]
		var atlas_path: String = job["atlas_path"]
		var frames_path: String = job["frames_path"]
		var pixel_sizes: Array = job["pixel_sizes"]

		var err := atlas.save_png(ProjectSettings.globalize_path(atlas_path))
		if err != OK:
			_errors.append("%s: failed to save atlas %s (err=%d)" % [jname, atlas_path, err])
			continue

		manifest_lines.append("atlas=%s pixel_size_front=%.6f pixel_size_back=%.6f pixel_size_side=%.6f baseline_offset_pixels=%.1f" % [
			atlas_path, pixel_sizes[0], pixel_sizes[1], pixel_sizes[2], BASELINE_OFFSET_PIXELS])

		if with_frames:
			if _save_frames(jname, atlas_path, frames_path, pixel_sizes):
				manifest_lines.append("frames=%s" % frames_path)

	if not _errors.is_empty():
		return false

	var manifest := "ASHBOUND_CORNER_ENEMY_FRAMES_OK sheets=2 poses=36\n"
	for line in manifest_lines:
		manifest += line + "\n"
	var mf := FileAccess.open(ProjectSettings.globalize_path("res://assets/characters/courtyard/enemy-preview/build-manifest.txt"), FileAccess.WRITE)
	if mf != null:
		mf.store_string(manifest)
		mf.close()

	return _errors.is_empty()


func _save_frames(name: String, atlas_path: String, frames_path: String, pixel_sizes: Array) -> bool:
	var texture := load(atlas_path) as Texture2D
	if texture == null:
		_errors.append("%s: cannot load imported atlas texture %s" % [name, atlas_path])
		return false
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.set_meta("pixel_size_front", pixel_sizes[0] as float)
	frames.set_meta("pixel_size_back", pixel_sizes[1] as float)
	frames.set_meta("pixel_size_side", pixel_sizes[2] as float)
	frames.set_meta("baseline_offset_pixels", BASELINE_OFFSET_PIXELS)
	for ci in COLS:
		var view: String = VIEWS[ci]
		for ri in ROWS:
			var row_name: String = ROW_NAMES[ri]
			if row_name == "walkB":
				continue # merged into walk via walkA entry
			var action: String = ("walk" if row_name == "walkA" else row_name) + "_" + view
			frames.add_animation(action)
			frames.set_animation_loop(action, row_name == "idle" or row_name.begins_with("walk"))
			frames.set_animation_speed(action, 6.0 if row_name.begins_with("walk") else 1.0)
			var frame_rows: Array[int] = []
			if row_name == "walkA":
				frame_rows = [1, 2]
			else:
				frame_rows = [ri]
			for fr in frame_rows:
				var at := AtlasTexture.new()
				at.atlas = texture
				at.region = Rect2(ci * CELL_SIZE, fr * CELL_SIZE, CELL_SIZE, CELL_SIZE)
				at.filter_clip = true
				frames.add_frame(action, at)
	var err := ResourceSaver.save(frames, frames_path)
	if err != OK:
		_errors.append("%s: failed to save frames %s (err=%d)" % [name, frames_path, err])
		return false
	return true

func _file_sha256_hex(path: String) -> String:
	return FileAccess.get_sha256(path)
