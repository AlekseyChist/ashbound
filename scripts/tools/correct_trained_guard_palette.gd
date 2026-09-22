extends SceneTree
## Offline tool: precise gamma color correction of the TRAINED guard only.
## Usage (editor headless):
##   godot --headless -s res://scripts/tools/correct_trained_guard_palette.gd \
##     [--manifest=res://art/characters/fist-defense-palette-v1/palette.json] \
##     [--out-dir=res://.tools/guard-palette/export/]
##
## Reads a schema-1 palette manifest, validates inputs (SHA256, RGBA8 1254x1254),
## applies gamma correction to the first 627 rows of base and paint identically,
## then composes the trained pack. Outputs only trained.png and trained-pack.png.

const DEFAULT_MANIFEST := "res://art/characters/fist-defense-palette-v1/palette.json"
const DEFAULT_OUT_DIR := "res://.tools/guard-palette/export/"
const EXPECTED_WIDTH := 1254
const EXPECTED_HEIGHT := 1254
const GUARD_ROWS := 627
const LUM_R := 0.2126
const LUM_G := 0.7152
const LUM_B := 0.0722

var _manifest_path: String = DEFAULT_MANIFEST
var _out_dir: String = DEFAULT_OUT_DIR


func _init() -> void:
	if not _parse_args():
		return
	call_deferred("_run")


func _parse_args() -> bool:
	var args: Array = OS.get_cmdline_user_args()
	for arg in args:
		var s: String = str(arg)
		if s.begins_with("--manifest="):
			_manifest_path = s.substr("--manifest=".length())
		elif s.begins_with("--out-dir="):
			_out_dir = s.substr("--out-dir=".length())
		else:
			_fail("unknown argument: %s" % s)
			return false
	return true


func _fail(reason: String) -> void:
	printerr("ASHBOUND_GUARD_PALETTE_FAIL " + reason)
	quit(1)


func _run() -> void:
	if not _is_safe_res_path(_manifest_path):
		_fail("manifest path is not a safe res:// project path")
		return
	if not _is_safe_out_dir(_out_dir):
		_fail("output dir must be inside res://.tools/ without traversal or backslashes")
		return

	var manifest: Variant = _load_manifest(_manifest_path)
	if manifest == null:
		return
	if typeof(manifest) != TYPE_DICTIONARY:
		_fail("manifest root must be a dictionary")
		return

	var schema: Variant = manifest.get("schema", null)
	if not _is_finite_integral(schema, 1):
		_fail("manifest schema must be integer 1")
		return

	var gamma: Variant = manifest.get("gamma", null)
	if typeof(gamma) == TYPE_BOOL or typeof(gamma) == TYPE_STRING:
		_fail("gamma must be a number, not boolean/string")
		return
	if typeof(gamma) != TYPE_FLOAT and typeof(gamma) != TYPE_INT:
		_fail("gamma missing or not numeric")
		return
	var gamma_f: float = float(gamma)
	if not is_finite(gamma_f) or gamma_f < 1.0 or gamma_f > 1.3:
		_fail("gamma must be finite in range 1..1.3")
		return

	var width_v: Variant = manifest.get("width", null)
	var height_v: Variant = manifest.get("height", null)
	if not _is_finite_integral(width_v, EXPECTED_WIDTH):
		_fail("manifest width must be integer %d" % EXPECTED_WIDTH)
		return
	if not _is_finite_integral(height_v, EXPECTED_HEIGHT):
		_fail("manifest height must be integer %d" % EXPECTED_HEIGHT)
		return

	var guard_rows_v: Variant = manifest.get("guard_rows", null)
	if not _is_finite_integral(guard_rows_v, GUARD_ROWS):
		_fail("manifest guard_rows must be integer %d" % GUARD_ROWS)
		return

	var base_path: String = _require_string_field(manifest, "base")
	if base_path == "":
		return
	var paint_path: String = _require_string_field(manifest, "paint")
	if paint_path == "":
		return
	var base_sha: String = _require_string_field(manifest, "base_sha256")
	if base_sha == "":
		return
	var paint_sha: String = _require_string_field(manifest, "paint_sha256")
	if paint_sha == "":
		return

	if not _is_relative_project_path(base_path):
		_fail("base path must be a relative project path (no res://, no traversal)")
		return
	if not _is_relative_project_path(paint_path):
		_fail("paint path must be a relative project path (no res://, no traversal)")
		return

	var regions: Variant = _load_regions(manifest)
	if regions == null:
		return

	# Validate and load all inputs before creating/writing any outputs.
	var base_img: Image = _load_validated_image("res://" + base_path, base_sha)
	if base_img == null:
		return
	var paint_img: Image = _load_validated_image("res://" + paint_path, paint_sha)
	if paint_img == null:
		return

	# Correct base and working paint identically.
	var corrected_base: Image = _correct_image(base_img, gamma_f)
	var corrected_paint: Image = _correct_image(paint_img, gamma_f)

	# Compose whole trained-pack image: copy corrected paint in manifest regions over corrected base.
	var pack: Image = corrected_base.duplicate()
	for region in regions:
		var r: Array = region
		var rx: int = int(r[0])
		var ry: int = int(r[1])
		var rw: int = int(r[2])
		var rh: int = int(r[3])
		var src_rect := Rect2i(rx, ry, rw, rh)
		pack.blit_rect(corrected_paint, src_rect, Vector2i(rx, ry))

	# Ensure output directory exists.
	var out_dir_abs: String = _out_dir
	if not out_dir_abs.ends_with("/"):
		out_dir_abs += "/"
	var dir_path: String = out_dir_abs.left(out_dir_abs.length() - 1)
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		var err: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		if err != OK:
			_fail("cannot create output directory: %s" % dir_path)
			return

	var base_out: String = out_dir_abs + "trained.png"
	var pack_out: String = out_dir_abs + "trained-pack.png"

	var save_err1: int = corrected_base.save_png(base_out)
	if save_err1 != OK:
		_fail("failed to save %s (error %d)" % [base_out, save_err1])
		return
	var save_err2: int = pack.save_png(pack_out)
	if save_err2 != OK:
		_fail("failed to save %s (error %d)" % [pack_out, save_err2])
		return

	print("ASHBOUND_GUARD_PALETTE_OK sheets=2 gamma=" + str(gamma_f))
	quit(0)


func _load_manifest(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_fail("manifest not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("cannot open manifest: %s" % path)
		return null
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_fail("manifest is not valid JSON")
		return null
	return parsed


func _require_string_field(dict: Dictionary, key: String) -> String:
	var v: Variant = dict.get(key, null)
	if typeof(v) != TYPE_STRING:
		_fail("manifest field '%s' must be a string" % key)
		return ""
	var s: String = str(v)
	if s.is_empty():
		_fail("manifest field '%s' must not be empty" % key)
		return ""
	return s


func _is_finite_integral(value: Variant, expected: int) -> bool:
	var t: int = typeof(value)
	if t == TYPE_BOOL or t == TYPE_STRING:
		return false
	if t != TYPE_INT and t != TYPE_FLOAT:
		return false
	var f: float = float(value)
	if not is_finite(f):
		return false
	if f != floorf(f):
		return false
	return int(f) == expected


func _load_regions(manifest: Dictionary) -> Variant:
	var regions_raw: Variant = manifest.get("regions", null)
	if typeof(regions_raw) != TYPE_ARRAY:
		_fail("manifest 'regions' must be an array")
		return null
	var raw_arr: Array = regions_raw
	if raw_arr.is_empty():
		_fail("manifest 'regions' must not be empty")
		return null
	var result: Array = []
	for i in raw_arr.size():
		var entry: Variant = raw_arr[i]
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 4:
			_fail("region %d must be an array of 4 integers [x,y,w,h]" % i)
			return null
		var arr: Array = entry
		var vals: Array = []
		for j in 4:
			var v: Variant = arr[j]
			if typeof(v) == TYPE_BOOL or typeof(v) == TYPE_STRING:
				_fail("region %d component %d must be an integer" % [i, j])
				return null
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				_fail("region %d component %d must be an integer" % [i, j])
				return null
			var fv: float = float(v)
			if not is_finite(fv):
				_fail("region %d component %d must be finite" % [i, j])
				return null
			if fv != floorf(fv):
				_fail("region %d component %d must be an integer (no fractions)" % [i, j])
				return null
			vals.append(int(fv))
		var x: int = vals[0]
		var y: int = vals[1]
		var w: int = vals[2]
		var h: int = vals[3]
		if w <= 0 or h <= 0:
			_fail("region %d must be nonempty (w>0, h>0)" % i)
			return null
		if x < 0 or y < 0 or x + w > EXPECTED_WIDTH or y + h > EXPECTED_HEIGHT:
			_fail("region %d is outside image bounds" % i)
			return null
		result.append(vals)
	return result


func _load_validated_image(path: String, expected_sha: String) -> Image:
	if not FileAccess.file_exists(path):
		_fail("input file not found: %s" % path)
		return null
	var actual_sha: String = FileAccess.get_sha256(path)
	if actual_sha != expected_sha:
		_fail("SHA256 mismatch for %s (expected %s, got %s)" % [path, expected_sha, actual_sha])
		return null
	var img := Image.load_from_file(path)
	if img == null:
		_fail("cannot load image: %s" % path)
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		_fail("image must be RGBA8: %s" % path)
		return null
	if img.get_width() != EXPECTED_WIDTH or img.get_height() != EXPECTED_HEIGHT:
		_fail("image must be %dx%d: %s" % [EXPECTED_WIDTH, EXPECTED_HEIGHT, path])
		return null
	return img


func _correct_image(img: Image, gamma: float) -> Image:
	var data := img.get_data()
	var out := PackedByteArray()
	out.resize(data.size())
	for i in data.size():
		out[i] = data[i]
	for y in GUARD_ROWS:
		var row_start: int = y * EXPECTED_WIDTH * 4
		for x in EXPECTED_WIDTH:
			var idx: int = row_start + x * 4
			var a: int = out[idx + 3]
			if a == 0:
				continue
			var r: float = float(out[idx])
			var g: float = float(out[idx + 1])
			var b: float = float(out[idx + 2])
			var lum: float = (r * LUM_R + g * LUM_G + b * LUM_B) / 255.0
			if lum <= 0.0:
				continue
			var new_lum: float = pow(lum, gamma)
			var ratio: float = new_lum / lum
			out[idx] = int(clampi(roundi(r * ratio), 0, 255))
			out[idx + 1] = int(clampi(roundi(g * ratio), 0, 255))
			out[idx + 2] = int(clampi(roundi(b * ratio), 0, 255))
	var result := Image.create_from_data(EXPECTED_WIDTH, EXPECTED_HEIGHT, false, Image.FORMAT_RGBA8, out)
	return result


func _is_relative_project_path(path: String) -> bool:
	if path.is_empty():
		return false
	if path.contains("\\"):
		return false
	if path.contains(":"):
		return false
	if path.begins_with("/"):
		return false
	if path.begins_with("res://"):
		return false
	if path.contains(".."):
		return false
	return true


func _is_safe_res_path(path: String) -> bool:
	if not path.begins_with("res://"):
		return false
	if path.contains("\\"):
		return false
	var rel: String = path.substr(6)
	if rel.is_empty():
		return false
	if rel.contains(".."):
		return false
	return true


func _is_safe_out_dir(path: String) -> bool:
	if not path.begins_with("res://.tools/"):
		return false
	if path.contains("\\"):
		return false
	var rel: String = path.substr(6)
	if rel.contains(".."):
		return false
	return true
