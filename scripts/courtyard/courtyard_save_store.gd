extends RefCounted

const FORMAT_NAME: String = "ASHBOUND_COURTYARD"
const FORMAT_VERSION: int = 1
const MAX_BYTES: int = 2 * 1024 * 1024
const MAX_SEQUENCE: int = 9223372036854775807
var MAGIC: PackedByteArray = PackedByteArray([65, 66, 67, 83, 65, 86, 69, 49]) # "ABCSAVE1"
const MIN_FILE_SIZE: int = 44

var directory: String = "user://courtyard-save-v1"
## The world save (WORLD-SAVE-01) reuses this store with its own format name and folder.
var format_name: String = FORMAT_NAME
var sequence: int = 0
var active_slot: int = -1
var blocked: bool = false
var last_error: String = ""


func load_latest(validator: Callable) -> Dictionary:
	sequence = 0
	active_slot = -1
	blocked = false
	last_error = ""
	var best: Dictionary = {}
	var best_seq: int = 0
	var has_final: bool = false
	var has_valid: bool = false
	var any_invalid: bool = false
	for slot in [0, 1]:
		var info: Dictionary = _read_slot(slot)
		if not info.get("exists", false):
			continue
		has_final = true
		if info.get("valid", false) and validator.call(info["payload"]):
			has_valid = true
			var seq: int = int(info["sequence"])
			if seq > best_seq:
				best_seq = seq
				best = info
		else:
			any_invalid = true
	if not has_final:
		return {"status": "empty", "payload": {}}
	if not has_valid:
		blocked = true
		last_error = "no valid slot"
		return {"status": "invalid", "payload": {}}
	var status: String = "loaded"
	if any_invalid:
		status = "recovered"
	active_slot = int(best["slot"])
	sequence = best_seq
	return {"status": status, "payload": best["payload"]}


func commit(payload: Dictionary, validator: Callable) -> bool:
	if blocked:
		last_error = "blocked"
		return false
	if not validator.call(payload):
		last_error = "validator rejected payload"
		return false
	if sequence == MAX_SEQUENCE:
		last_error = "sequence overflow"
		return false
	var greatest_seq: int = 0
	for i in range(2):
		var info: Dictionary = _read_slot(i)
		if info.get("valid", false) and validator.call(info.get("payload", {})):
			greatest_seq = max(greatest_seq, int(info.get("sequence", 0)))
	if greatest_seq != sequence:
		blocked = true
		last_error = "save_changed_by_another_process"
		return false
	var next_seq: int = sequence + 1
	var slot: int = 1 if active_slot == 0 else 0
	var payload_bytes: PackedByteArray = var_to_bytes(payload)
	if payload_bytes.size() > MAX_BYTES:
		last_error = "payload too large"
		return false
	var digest: PackedByteArray = _sha256(payload_bytes)
	var envelope: Dictionary = {
		"format": format_name,
		"version": FORMAT_VERSION,
		"sequence": next_seq,
		"payload": payload_bytes,
		"digest": digest,
	}
	var envelope_bytes: PackedByteArray = var_to_bytes(envelope)
	if envelope_bytes.size() > MAX_BYTES:
		last_error = "envelope too large"
		return false
	var framed: PackedByteArray = _build_framed(envelope_bytes)
	var dir_abs: String = ProjectSettings.globalize_path(directory)
	if not DirAccess.dir_exists_absolute(dir_abs):
		var err: int = DirAccess.make_dir_recursive_absolute(dir_abs)
		if err != OK:
			last_error = "cannot create directory"
			return false
	var tmp_path: String = "%s/slot%d.sav.tmp" % [directory, slot]
	var final_path: String = "%s/slot%d.sav" % [directory, slot]
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		last_error = "cannot open temp for write"
		return false
	file.store_buffer(framed)
	file.flush()
	if file.get_error() != OK:
		file.close()
		last_error = "temp write failed"
		return false
	file.close()
	var check: Dictionary = _read_slot_raw(tmp_path, next_seq, payload)
	if not check.get("valid", false):
		last_error = "temp validation failed"
		return false
	if not validator.call(check["payload"]):
		last_error = "temp semantic validation failed"
		return false
	var tmp_abs: String = ProjectSettings.globalize_path(tmp_path)
	var final_abs: String = ProjectSettings.globalize_path(final_path)
	if FileAccess.file_exists(final_path):
		if DirAccess.remove_absolute(final_abs) != OK:
			last_error = "cannot remove old final"
			return false
	if DirAccess.rename_absolute(tmp_abs, final_abs) != OK:
		last_error = "rename failed"
		return false
	var final_check: Dictionary = _read_slot_raw(final_path, next_seq, payload)
	if not final_check.get("valid", false):
		last_error = "final validation failed"
		return false
	if not validator.call(final_check["payload"]):
		last_error = "final semantic validation failed"
		return false
	active_slot = slot
	sequence = next_seq
	last_error = ""
	return true


func _read_slot(slot: int) -> Dictionary:
	var path: String = "%s/slot%d.sav" % [directory, slot]
	var info: Dictionary = _read_slot_raw(path, -1, {})
	info["slot"] = slot
	return info


func _max_final_sequence() -> int:
	var max_seq: int = 0
	for slot in [0, 1]:
		var info: Dictionary = _read_slot(slot)
		if info.get("exists", false):
			max_seq = maxi(max_seq, int(info.get("sequence", 0)))
	return max_seq


func _build_framed(envelope_bytes: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = MAGIC.duplicate()
	out.append_array(_sha256(envelope_bytes))
	out.append_array(envelope_bytes)
	return out


func _read_slot_raw(path: String, expected_seq: int, expected_payload: Dictionary) -> Dictionary:
	var result: Dictionary = {"exists": false, "valid": false, "sequence": 0, "payload": {}}
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		last_error = "path is a directory: %s" % path
		result["exists"] = true
		return result
	if not FileAccess.file_exists(path):
		return result
	result["exists"] = true
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "cannot open %s" % path
		return result
	var length: int = file.get_length()
	file.close()
	if length < MIN_FILE_SIZE or length > MAX_BYTES:
		last_error = "bad size for %s" % path
		return result
	var buffer: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if buffer.size() != length:
		last_error = "short read for %s" % path
		return result
	if not _bytes_equal(buffer.slice(0, MAGIC.size()), MAGIC):
		last_error = "bad magic for %s" % path
		return result
	var stored_digest: PackedByteArray = buffer.slice(MAGIC.size(), MAGIC.size() + 32)
	var envelope_bytes: PackedByteArray = buffer.slice(MAGIC.size() + 32)
	if _sha256(envelope_bytes) != stored_digest:
		last_error = "framing digest mismatch for %s" % path
		return result
	var decoded: Variant = bytes_to_var(envelope_bytes)
	if typeof(decoded) != TYPE_DICTIONARY:
		last_error = "not a dictionary"
		return result
	var envelope: Dictionary = decoded
	if envelope.size() != 5:
		last_error = "envelope field count"
		return result
	if not _is_strict(envelope, "format", format_name):
		last_error = "bad format"
		return result
	if not _is_int_value(envelope, "version", FORMAT_VERSION):
		last_error = "bad version"
		return result
	var seq: Variant = envelope.get("sequence")
	if typeof(seq) != TYPE_INT or int(seq) <= 0:
		last_error = "bad sequence"
		return result
	var payload_bytes: Variant = envelope.get("payload")
	if typeof(payload_bytes) != TYPE_PACKED_BYTE_ARRAY:
		last_error = "bad payload type"
		return result
	var digest: Variant = envelope.get("digest")
	if typeof(digest) != TYPE_PACKED_BYTE_ARRAY or (digest as PackedByteArray).size() != 32:
		last_error = "bad digest"
		return result
	if _sha256(payload_bytes as PackedByteArray) != (digest as PackedByteArray):
		last_error = "digest mismatch"
		return result
	var payload: Variant = bytes_to_var(payload_bytes as PackedByteArray)
	if typeof(payload) != TYPE_DICTIONARY:
		last_error = "payload not dictionary"
		return result
	result["sequence"] = int(seq)
	result["payload"] = payload
	if expected_seq >= 0 and int(seq) != expected_seq:
		last_error = "unexpected sequence"
		return result
	if expected_seq >= 0 and (payload as Dictionary) != expected_payload:
		last_error = "unexpected payload"
		return result
	result["valid"] = true
	return result


func _bytes_equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _is_strict(envelope: Dictionary, key: String, value: String) -> bool:
	var v: Variant = envelope.get(key)
	return typeof(v) == TYPE_STRING and v == value


func _is_int_value(envelope: Dictionary, key: String, value: int) -> bool:
	var v: Variant = envelope.get(key)
	return typeof(v) == TYPE_INT and int(v) == value


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()
