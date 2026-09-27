extends SceneTree
## Offline builder for traveler backpack base-layer atlases.
## Reads a frozen manifest, validates hashes/sizes/masks, composes
## replace_rgba_binary_mask outputs into a scratch .tools directory only.

const DEFAULT_MANIFEST_PATH := "res://art/characters/traveler-base-v1/manifest.json"
const DEFAULT_OUTPUT_DIR := "res://.tools/character-base/export"
const EXPECTED_SHEET_COUNT := 7
const EXPECTED_POSE_COUNT := 84
const EXPECTED_SOURCE_COUNT := 2
const EXPECTED_SIZE_X := 1254
const EXPECTED_SIZE_Y := 1254
const HEAD_TOP_FRACTION := 0.12
const LOWER_BODY_START_FRACTION := 0.55


func _initialize() -> void:
	# Defer so the SceneTree is fully constructed before we run.
	call_deferred("_run")


func _run() -> void:
	var manifest_path := DEFAULT_MANIFEST_PATH
	var output_dir := DEFAULT_OUTPUT_DIR
	var args := OS.get_cmdline_user_args()
	var parsed_args: Dictionary = _parse_args(args)
	if parsed_args.is_empty():
		_fail("invalid command line arguments: %s" % str(args))
		return
	manifest_path = str(parsed_args["manifest"])
	output_dir = str(parsed_args["output_dir"])
	if not _is_valid_res_path(manifest_path):
		_fail("manifest path must be a res:// project path without traversal: %s" % manifest_path)
		return
	if not _is_valid_output_dir(output_dir):
		_fail("output dir must be below res://.tools/ and contain no traversal: %s" % output_dir)
		return

	var manifest: Variant = _load_manifest(manifest_path)
	if manifest == null:
		_fail("manifest missing or unreadable: %s" % manifest_path)
		return
	if not _validate_manifest_structure(manifest):
		_fail("manifest structure invalid: %s" % manifest_path)
		return

	var source_resources: Array = manifest["source_resources"]
	for i in source_resources.size():
		var entry: Dictionary = source_resources[i]
		var res_path: String = entry["path"]
		if not _is_project_relative_no_traversal(res_path):
			_fail("source resource path invalid or has traversal: %s" % res_path)
			return
		if not res_path.begins_with("assets/characters/courtyard/"):
			_fail("source resource must be under assets/characters/courtyard/: %s" % res_path)
			return
		var expected_sha: String = entry["sha256"]
		if not _validate_sha256(expected_sha, "source_resources[%d].sha256" % i):
			_fail("source_resources[%d].sha256 is not 64 hex chars" % i)
			return
		var actual_sha := _hash_source_resource_text(res_path)
		if actual_sha == "":
			_fail("source resource missing or unreadable: %s" % res_path)
			return
		if actual_sha != expected_sha:
			_fail("source resource hash mismatch for %s (expected %s, got %s)" % [res_path, expected_sha, actual_sha])
			return

	var sheets: Array = manifest["sheets"]
	var seen_sheet_ids := {}
	var all_region_ids := {}
	var total_regions := 0
	var built_images: Array = []
	for s in sheets.size():
		var sheet: Dictionary = sheets[s]
		var sheet_id: String = str(sheet.get("id", "<missing>"))
		if seen_sheet_ids.has(sheet_id):
			_fail("duplicate sheet id '%s'" % sheet_id)
			return
		seen_sheet_ids[sheet_id] = true
		if not _validate_sheet_structure(sheet, sheet_id):
			_fail("sheet '%s' has invalid structure" % sheet_id)
			return

		var base_path: String = sheet["base_path"]
		if not _is_project_relative_no_traversal(base_path):
			_fail("sheet '%s' base_path invalid or has traversal: %s" % [sheet_id, base_path])
			return
		if not base_path.begins_with("assets/characters/courtyard/"):
			_fail("sheet '%s' base_path must be under assets/characters/courtyard/: %s" % [sheet_id, base_path])
			return
		var base_sha_expected: String = sheet["base_sha256"]
		if not _validate_sha256(base_sha_expected, "sheet '%s'.base_sha256" % sheet_id):
			_fail("sheet '%s' base_sha256 is not 64 hex chars" % sheet_id)
			return
		var base_sha_actual := FileAccess.get_sha256(ProjectSettings.globalize_path("res://" + base_path))
		if base_sha_actual == "":
			_fail("sheet '%s' base PNG missing or unreadable: %s" % [sheet_id, base_path])
			return
		if base_sha_actual != base_sha_expected:
			_fail("sheet '%s' base hash mismatch for %s (expected %s, got %s)" % [sheet_id, base_path, base_sha_expected, base_sha_actual])
			return

		var paint_path: String = sheet["paint_path"]
		var mask_path: String = sheet["mask_path"]
		if not _is_project_relative_no_traversal(paint_path):
			_fail("sheet '%s' paint_path invalid or has traversal: %s" % [sheet_id, paint_path])
			return
		if not paint_path.begins_with("art/characters/traveler-base-v1/layers/"):
			_fail("sheet '%s' paint_path must be under art/characters/traveler-base-v1/layers/: %s" % [sheet_id, paint_path])
			return
		if not _is_project_relative_no_traversal(mask_path):
			_fail("sheet '%s' mask_path invalid or has traversal: %s" % [sheet_id, mask_path])
			return
		if not mask_path.begins_with("art/characters/traveler-base-v1/layers/"):
			_fail("sheet '%s' mask_path must be under art/characters/traveler-base-v1/layers/: %s" % [sheet_id, mask_path])
			return

		var base_img := _load_rgba8(base_path, "sheet '%s' base" % sheet_id)
		if base_img == null:
			_fail("sheet '%s' base image failed to load: %s" % [sheet_id, base_path])
			return
		var paint_img := _load_rgba8(paint_path, "sheet '%s' paint" % sheet_id)
		if paint_img == null:
			_fail("sheet '%s' paint image failed to load: %s" % [sheet_id, paint_path])
			return
		var mask_img := _load_rgba8(mask_path, "sheet '%s' mask" % sheet_id)
		if mask_img == null:
			_fail("sheet '%s' mask image failed to load: %s" % [sheet_id, mask_path])
			return

		if base_img.get_width() != EXPECTED_SIZE_X or base_img.get_height() != EXPECTED_SIZE_Y:
			_fail("sheet '%s' base size must be %dx%d, got %dx%d" % [sheet_id, EXPECTED_SIZE_X, EXPECTED_SIZE_Y, base_img.get_width(), base_img.get_height()])
			return
		if paint_img.get_width() != EXPECTED_SIZE_X or paint_img.get_height() != EXPECTED_SIZE_Y:
			_fail("sheet '%s' paint size must be %dx%d, got %dx%d" % [sheet_id, EXPECTED_SIZE_X, EXPECTED_SIZE_Y, paint_img.get_width(), paint_img.get_height()])
			return
		if mask_img.get_width() != EXPECTED_SIZE_X or mask_img.get_height() != EXPECTED_SIZE_Y:
			_fail("sheet '%s' mask size must be %dx%d, got %dx%d" % [sheet_id, EXPECTED_SIZE_X, EXPECTED_SIZE_Y, mask_img.get_width(), mask_img.get_height()])
			return

		if not _validate_binary_mask(mask_img, sheet_id):
			_fail("sheet '%s' mask is not opaque binary grayscale (RGB 0/255, alpha 255)" % sheet_id)
			return

		var regions: Array = sheet["regions"]
		var seen_rects := {}
		for r in regions.size():
			var region: Dictionary = regions[r]
			var region_id: String = str(region.get("id", "<missing>"))
			if all_region_ids.has(region_id):
				_fail("duplicate region id '%s' (sheet '%s')" % [region_id, sheet_id])
				return
			all_region_ids[region_id] = true

			var rect_arr: Array = region["rect"]
			var margin_arr: Array = region["margin"]
			if not _is_int_array(rect_arr, 4):
				_fail("region '%s' rect must be an integer array of length 4" % region_id)
				return
			if not _is_finite_number_array(margin_arr, 4):
				_fail("region '%s' margin must be a finite numeric array of length 4" % region_id)
				return
			var rx := int(rect_arr[0])
			var ry := int(rect_arr[1])
			var rw := int(rect_arr[2])
			var rh := int(rect_arr[3])
			if rw <= 0 or rh <= 0:
				_fail("region '%s' has non-positive size %dx%d" % [region_id, rw, rh])
				return
			if rx < 0 or ry < 0 or rx + rw > EXPECTED_SIZE_X or ry + rh > EXPECTED_SIZE_Y:
				_fail("region '%s' rect [%d,%d,%d,%d] is out of bounds" % [region_id, rx, ry, rw, rh])
				return
			var key := "%s|%d|%d|%d|%d" % [sheet_id, rx, ry, rw, rh]
			if seen_rects.has(key):
				_fail("duplicate rectangle on sheet '%s' for region '%s'" % [sheet_id, region_id])
				return
			seen_rects[key] = true
		total_regions += regions.size()

		var out_img := _compose_sheet(base_img, paint_img, mask_img, regions, sheet_id)
		if out_img == null:
			_fail("sheet '%s' composition failed" % sheet_id)
			return
		built_images.append(out_img)

	if total_regions != EXPECTED_POSE_COUNT:
		_fail("total region count is %d, expected %d" % [total_regions, EXPECTED_POSE_COUNT])
		return

	# All validation and construction succeeded; now write outputs.
	# Validate every output basename and uniqueness BEFORE creating any directory or file.
	var seen_output_names := {}
	for s in sheets.size():
		var sheet: Dictionary = sheets[s]
		var out_name: String = str(sheet["output_name"])
		if not _is_simple_png_basename(out_name):
			_fail("sheet '%s' output_name is not a simple .png basename: %s" % [str(sheet.get("id", "")), out_name])
			return
		var out_key := out_name.to_lower()
		if seen_output_names.has(out_key):
			_fail("duplicate output_name '%s' (sheet '%s')" % [out_name, str(sheet.get("id", ""))])
			return
		seen_output_names[out_key] = true

	var out_dir_abs := ProjectSettings.globalize_path(output_dir)
	if not DirAccess.dir_exists_absolute(out_dir_abs):
		var err := DirAccess.make_dir_recursive_absolute(out_dir_abs)
		if err != OK:
			_fail("could not create output directory %s (error %d)" % [output_dir, err])
			return

	for s in built_images.size():
		var sheet: Dictionary = sheets[s]
		var out_name: String = str(sheet["output_name"])
		var out_path := output_dir.path_join(out_name)
		var img: Image = built_images[s]
		var save_err := img.save_png(ProjectSettings.globalize_path(out_path))
		if save_err != OK:
			_fail("failed to save %s (error %d)" % [out_path, save_err])
			return

	print("ASHBOUND_CHARACTER_BASE_BUILD_OK sheets=%d poses=%d" % [EXPECTED_SHEET_COUNT, EXPECTED_POSE_COUNT])
	quit(0)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result := {"manifest": DEFAULT_MANIFEST_PATH, "output_dir": DEFAULT_OUTPUT_DIR}
	var i := 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--manifest":
			if i + 1 >= args.size():
				return {}
			i += 1
			result["manifest"] = args[i]
		elif arg == "--output-dir":
			if i + 1 >= args.size():
				return {}
			i += 1
			result["output_dir"] = args[i]
		else:
			return {}
		i += 1
	return result


func _is_valid_res_path(p: String) -> bool:
	if p.is_empty() or not p.begins_with("res://"):
		return false
	if p.contains("\\") or p.contains(".."):
		return false
	var after_prefix := p.substr(6)
	if after_prefix.contains(":"):
		return false
	return true


func _is_valid_output_dir(p: String) -> bool:
	if not _is_valid_res_path(p):
		return false
	var normalized := p.trim_suffix("/")
	if normalized != "res://.tools" and not normalized.begins_with("res://.tools/"):
		return false
	return true


func _is_project_relative_no_traversal(p: String) -> bool:
	if p.is_empty() or p.contains("\\") or p.contains("..") or p.contains(":"):
		return false
	if p.begins_with("/") or p.begins_with("res://") or p.begins_with("user://"):
		return false
	return true


func _is_simple_png_basename(p: String) -> bool:
	if p.is_empty() or not p.ends_with(".png"):
		return false
	if p.contains("/") or p.contains("\\") or p.contains(".."):
		return false
	var stem := p.trim_suffix(".png")
	if stem.is_empty() or stem.contains(".") or stem.contains(":"):
		return false
	for c in stem.length():
		var ch := stem[c]
		if not (ch >= "a" and ch <= "z") and not (ch >= "A" and ch <= "Z") \
				and not (ch >= "0" and ch <= "9") and ch != "-" and ch != "_":
			return false
	return true


func _validate_sha256(value: String, _label: String) -> bool:
	if value.length() != 64:
		return false
	for c in value.length():
		var ch := value[c]
		var ok := (ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "f") or (ch >= "A" and ch <= "F")
		if not ok:
			return false
	return true


func _load_manifest(path: String) -> Variant:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed


func _validate_manifest_structure(manifest: Dictionary) -> bool:
	if manifest.get("schema", null) == null or not _is_exact_int(manifest["schema"], 1):
		return false
	if str(manifest.get("composition", "")) != "replace_rgba_binary_mask":
		return false
	if not manifest.has("pose_count") or not _is_exact_int(manifest["pose_count"], EXPECTED_POSE_COUNT):
		return false
	if not manifest.has("base_id") or typeof(manifest["base_id"]) != TYPE_STRING:
		return false
	var sources: Variant = manifest.get("source_resources", null)
	if typeof(sources) != TYPE_ARRAY or (sources as Array).size() != EXPECTED_SOURCE_COUNT:
		return false
	for i in (sources as Array).size():
		var entry: Variant = (sources as Array)[i]
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var d: Dictionary = entry
		if not d.has("path") or typeof(d["path"]) != TYPE_STRING:
			return false
		if not d.has("sha256") or typeof(d["sha256"]) != TYPE_STRING:
			return false
	var sheets: Variant = manifest.get("sheets", null)
	if typeof(sheets) != TYPE_ARRAY or (sheets as Array).size() != EXPECTED_SHEET_COUNT:
		return false
	for i in (sheets as Array).size():
		var sh: Variant = (sheets as Array)[i]
		if typeof(sh) != TYPE_DICTIONARY:
			return false
		var sd: Dictionary = sh
		for key in ["id", "base_path", "base_sha256", "paint_path", "mask_path", "output_name"]:
			if not sd.has(key) or typeof(sd[key]) != TYPE_STRING:
				return false
		if not sd.has("size") or typeof(sd["size"]) != TYPE_ARRAY:
			return false
		var size_arr: Array = sd["size"]
		if not _is_int_array(size_arr, 2) or int(size_arr[0]) != EXPECTED_SIZE_X or int(size_arr[1]) != EXPECTED_SIZE_Y:
			return false
		if not sd.has("regions") or typeof(sd["regions"]) != TYPE_ARRAY:
			return false
		var regions: Array = sd["regions"]
		for r in regions.size():
			var reg: Variant = regions[r]
			if typeof(reg) != TYPE_DICTIONARY:
				return false
			var rd: Dictionary = reg
			if not rd.has("id") or typeof(rd["id"]) != TYPE_STRING:
				return false
			for key in ["rect", "margin"]:
				if not rd.has(key) or typeof(rd[key]) != TYPE_ARRAY:
					return false
				var arr: Array = rd[key]
				if arr.size() != 4:
					return false
				for v in arr:
					if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
						return false
					if not is_finite(float(v)):
						return false
				if key == "rect":
					for v in arr:
						if float(v) != floorf(float(v)):
							return false
	return true


func _validate_sheet_structure(sheet: Dictionary, sheet_id: String) -> bool:
	var size_arr: Array = sheet["size"]
	if not _is_int_array(size_arr, 2) or int(size_arr[0]) != EXPECTED_SIZE_X or int(size_arr[1]) != EXPECTED_SIZE_Y:
		push_warning("sheet '%s' size mismatch with expected %dx%d" % [sheet_id, EXPECTED_SIZE_X, EXPECTED_SIZE_Y])
		return false
	return true


func _is_int_array(arr: Array, count: int) -> bool:
	if arr.size() != count:
		return false
	for v in arr:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return false
		var f := float(v)
		if not is_finite(f):
			return false
		if f != floorf(f):
			return false
	return true


func _is_finite_number_array(arr: Array, count: int) -> bool:
	if arr.size() != count:
		return false
	for v in arr:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return false
		if not is_finite(float(v)):
			return false
	return true


func _is_exact_int(value: Variant, expected: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) == expected
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		return is_finite(f) and f == floorf(f) and int(f) == expected
	return false


func _hash_source_resource_text(res_path: String) -> String:
	var abs_path := ProjectSettings.globalize_path("res://" + res_path)
	if not FileAccess.file_exists(abs_path):
		return ""
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	text = text.replace("\r\n", "\n")
	return text.sha256_text()


func _load_rgba8(path: String, label: String) -> Image:
	var abs_path := ProjectSettings.globalize_path("res://" + path)
	if not FileAccess.file_exists(abs_path):
		push_warning("image file missing %s (%s)" % [path, label])
		return null
	var img := Image.new()
	var err := img.load(abs_path)
	if err != OK:
		push_warning("failed to load image %s (%s), error %d" % [path, label, err])
		return null
	if img.is_empty():
		push_warning("image is empty %s (%s)" % [path, label])
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _validate_binary_mask(mask_img: Image, sheet_id: String) -> bool:
	var data := mask_img.get_data()
	var w := mask_img.get_width()
	var h := mask_img.get_height()
	for y in h:
		for x in w:
			var idx := (y * w + x) * 4
			var r := data[idx]
			var g := data[idx + 1]
			var b := data[idx + 2]
			var a := data[idx + 3]
			if a != 255:
				push_warning("mask '%s' has non-opaque pixel at (%d,%d)" % [sheet_id, x, y])
				return false
			var is_white := (r == 255 and g == 255 and b == 255)
			var is_black := (r == 0 and g == 0 and b == 0)
			if not is_white and not is_black:
				push_warning("mask '%s' has non-binary pixel at (%d,%d): rgb(%d,%d,%d)" % [sheet_id, x, y, r, g, b])
				return false
	return true


func _compose_sheet(base_img: Image, paint_img: Image, mask_img: Image, regions: Array, sheet_id: String) -> Image:
	var w := EXPECTED_SIZE_X
	var h := EXPECTED_SIZE_Y
	var out_data := PackedByteArray()
	out_data.resize(w * h * 4)
	# Initialize to fully transparent.
	for i in out_data.size():
		out_data[i] = 0

	var base_data := base_img.get_data()
	var paint_data := paint_img.get_data()
	var mask_data := mask_img.get_data()

	# Copy all base rectangles into the output at their original coordinates.
	for r in regions.size():
		var region: Dictionary = regions[r]
		var rect_arr: Array = region["rect"]
		var rx := int(rect_arr[0])
		var ry := int(rect_arr[1])
		var rw := int(rect_arr[2])
		var rh := int(rect_arr[3])
		for y in rh:
			var src_row := (ry + y) * w + rx
			var dst_row := (ry + y) * w + rx
			for x in rw:
				var si := (src_row + x) * 4
				var di := (dst_row + x) * 4
				out_data[di] = base_data[si]
				out_data[di + 1] = base_data[si + 1]
				out_data[di + 2] = base_data[si + 2]
				out_data[di + 3] = base_data[si + 3]

	# Validate protected head/lower rows within each rectangle.
	for r in regions.size():
		var region: Dictionary = regions[r]
		var rect_arr: Array = region["rect"]
		var rx := int(rect_arr[0])
		var ry := int(rect_arr[1])
		var rw := int(rect_arr[2])
		var rh := int(rect_arr[3])
		var head_top_end := ry + int(float(rh) * HEAD_TOP_FRACTION)
		var lower_body_start := ry + int(float(rh) * LOWER_BODY_START_FRACTION)
		for y in rh:
			var abs_y := ry + y
			var in_head_top := abs_y >= ry and abs_y < head_top_end
			var in_lower_body := abs_y >= lower_body_start and abs_y < (ry + rh)
			if not (in_head_top or in_lower_body):
				continue
			for x in rw:
				var px := rx + x
				var pi := (abs_y * w + px) * 4
				var mr := mask_data[pi]
				var mg := mask_data[pi + 1]
				var mb := mask_data[pi + 2]
				if mr == 255 and mg == 255 and mb == 255:
					push_warning("sheet '%s' region '%s': white mask pixel in protected area at (%d,%d)" % [sheet_id, str(region.get("id", "")), px, abs_y])
					return null

	# Apply ALL white mask pixels across the whole atlas exactly once (RGBA replacement).
	for y in h:
		var row := y * w
		for x in w:
			var pi := (row + x) * 4
			var mr := mask_data[pi]
			var mg := mask_data[pi + 1]
			var mb := mask_data[pi + 2]
			if not (mr == 255 and mg == 255 and mb == 255):
				continue
			out_data[pi] = paint_data[pi]
			out_data[pi + 1] = paint_data[pi + 1]
			out_data[pi + 2] = paint_data[pi + 2]
			out_data[pi + 3] = paint_data[pi + 3]

	var out_img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out_data)
	if out_img == null:
		return null
	return out_img


func _fail(message: String) -> void:
	print("CHARACTER_BASE_BUILD_FAIL %s" % message)
	quit(1)
