extends SceneTree
# AshBound: frozen-base + working-paint mask composition for fist defense equipment.
# Lossless copy of authored region rects from paint sheets onto immutable base sheets.

const MANIFEST_PATH := "res://art/characters/fist-defense-v1/equipment.json"
const DEFAULT_OUT_DIR := "res://.tools/defense-equipment/export/"
const ALLOWED_IDS: Array[String] = ["novice", "trained"]

var _errors: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var manifest_path := MANIFEST_PATH
	var out_dir := DEFAULT_OUT_DIR
	for a in args:
		if a.begins_with("--manifest="):
			manifest_path = a.substr(11)
		elif a.begins_with("--out-dir="):
			out_dir = a.substr(10)
		else:
			_record("unknown flag: %s" % a)
	if _errors.size() > 0:
		return
	if not _is_tools_path(out_dir):
		_record("out-dir must stay inside .tools: %s" % out_dir)
		return
	var manifest = _load_manifest(manifest_path)
	if manifest == null:
		return
	var sheets = manifest.get("sheets")
	if typeof(sheets) != TYPE_ARRAY or (sheets as Array).size() != 2:
		_record("manifest.sheets must be an array of exactly 2 entries")
		return
	var seen := {}
	var jobs: Array[Dictionary] = []
	for s in sheets:
		var job = _validate_sheet(s, seen)
		if job == null:
			return
		jobs.append(job)
	# Preflight: load and hash-check every source before any save.
	for j in jobs:
		var base_img := _load_image(j["base"], j["base_sha256"])
		if base_img == null:
			return
		var paint_img := _load_image(j["paint"], j["paint_sha256"])
		if paint_img == null:
			return
		j["base_img"] = base_img
		j["paint_img"] = paint_img
	var dir := out_dir
	if not dir.ends_with("/"):
		dir += "/"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	for j in jobs:
		var out_img: Image = (j["base_img"] as Image).duplicate()
		for r in j["regions"]:
			var rect := Rect2i(r[0], r[1], r[2], r[3])
			out_img.blit_rect(j["paint_img"], rect, rect.position)
		var path := dir + String(j["id"]) + "-pack.png"
		if out_img.save_png(path) != OK:
			_record("failed to save %s" % path)
			return
		print("saved %s" % path)
	print("ASHBOUND_DEFENSE_EQUIPMENT_OK sheets=2")
	quit(0)

func _record(msg: String) -> void:
	_errors.append(msg)
	printerr("ASHBOUND_DEFENSE_EQUIPMENT_FAIL " + msg)
	quit(1)


func _load_manifest(p: String) -> Variant:
	if not p.begins_with("res://"):
		_record("manifest must be a res:// project path: %s" % p)
		return null
	if not _is_project_asset_path(p.trim_prefix("res://")):
		_record("manifest path is outside allowed project assets: %s" % p)
		return null
	if not FileAccess.file_exists(p):
		_record("manifest not found: %s" % p)
		return null
	var t := JSON.new()
	if t.parse(FileAccess.get_file_as_string(p)) != OK:
		_record("manifest is not valid JSON")
		return null
	var d = t.data
	if typeof(d) != TYPE_DICTIONARY or (d as Dictionary).get("schema") != 1:
		_record("manifest must be a schema1 object")
		return null
	return d


func _validate_sheet(s, seen: Dictionary) -> Variant:
	if typeof(s) != TYPE_DICTIONARY:
		_record("sheet entry is not an object")
		return null
	var id = s.get("id")
	if typeof(id) != TYPE_STRING or not ALLOWED_IDS.has(id):
		_record("sheet.id must be novice or trained, got: %s" % str(id))
		return null
	if seen.has(id):
		_record("duplicate sheet id: %s" % id)
		return null
	seen[id] = true
	var base = s.get("base")
	var paint = s.get("paint")
	if typeof(base) != TYPE_STRING or typeof(paint) != TYPE_STRING:
		_record("sheet %s: base/paint must be strings" % id)
		return null
	if not _is_project_asset_path(base):
		_record("sheet %s: bad base path: %s" % [id, str(base)])
		return null
	if not _is_project_asset_path(paint):
		_record("sheet %s: bad paint path: %s" % [id, str(paint)])
		return null
	var bsha = s.get("base_sha256")
	var psha = s.get("paint_sha256")
	if not _is_sha256(bsha):
		_record("sheet %s: base_sha256 must be 64 hex chars" % id)
		return null
	if not _is_sha256(psha):
		_record("sheet %s: paint_sha256 must be 64 hex chars" % id)
		return null
	var regions_raw = s.get("regions")
	if typeof(regions_raw) != TYPE_ARRAY or (regions_raw as Array).size() == 0:
		_record("sheet %s: regions must be a non-empty array" % id)
		return null
	var regions: Array[Array] = []
	for r in regions_raw:
		var region = _validate_region(r, id)
		if region == null:
			return null
		regions.append(region)
	return {"id": id, "base": base, "paint": paint, "base_sha256": bsha, "paint_sha256": psha, "regions": regions}

func _validate_region(r, sheet_id: String) -> Variant:
	if typeof(r) != TYPE_ARRAY or (r as Array).size() != 4:
		_record("sheet %s: region must be [x,y,w,h]" % sheet_id)
		return null
	var out: Array[int] = []
	for v in r:
		var n = _as_int(v)
		if n == null:
			_record("sheet %s: region values must be non-negative whole numbers" % sheet_id)
			return null
		out.append(n)
	if out[2] <= 0 or out[3] <= 0:
		_record("sheet %s: region w/h must be positive" % sheet_id)
		return null
	if out[0] + out[2] > 1254 or out[1] + out[3] > 1254:
		_record("sheet %s: region exceeds 1254x1254 sheet" % sheet_id)
		return null
	return out

func _as_int(v) -> Variant:
	if typeof(v) == TYPE_INT:
		var i := int(v)
		if i < 0:
			return null
		return i
	if typeof(v) == TYPE_FLOAT:
		var f := float(v)
		if not is_finite(f) or f < 0.0 or f != floorf(f):
			return null
		return int(f)
	return null


func _is_sha256(v) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s := String(v)
	if s.length() != 64:
		return false
	for c in s:
		var ok := (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
		if not ok:
			return false
	return true

func _is_project_asset_path(p) -> bool:
	if typeof(p) != TYPE_STRING:
		return false
	var s := String(p)
	if s.contains("\\"):
		return false
	if s.begins_with("/") or s.begins_with("~") or s.length() >= 2 and s[1] == ":":
		return false
	for part in s.split("/"):
		if part == "..":
			return false
	return s.begins_with("assets/") or s.begins_with("art/") or s.begins_with(".tools/")

func _load_image(path: String, expected_sha: String) -> Image:
	var res := "res://" + path
	if not FileAccess.file_exists(res):
		_record("source image not found: %s" % path)
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(res))
	if img == null:
		_record("failed to load image: %s" % path)
		return null
	if img.get_width() != 1254 or img.get_height() != 1254:
		_record("image must be 1254x1254: %s" % path)
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		_record("image must be RGBA8: %s" % path)
		return null
	var actual := FileAccess.get_sha256(res).to_lower()
	if actual != expected_sha.to_lower():
		_record("sha256 mismatch for %s (expected %s, got %s)" % [path, expected_sha, actual])
		return null
	return img

func _is_tools_path(p: String) -> bool:
	var norm := p.replace("\\", "/")
	if not norm.begins_with("res://.tools/"):
		return false
	for part in norm.split("/"):
		if part == "..":
			return false
	return true
