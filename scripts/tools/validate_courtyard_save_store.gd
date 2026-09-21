extends SceneTree
## Codex QA: crash-resistant persistence, exact integer roundtrip and fallback.
const Store = preload("res://scripts/courtyard/courtyard_save_store.gd")
var failures: Array[String] = []
var groups := 0
var directory := "res://.tools/save-store-qa-" + str(Time.get_ticks_usec())

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("SAVE_STORE_FAIL: " + message)

func valid(data: Dictionary) -> bool:
	return data.size() == 2 and data.get("gold") is int and data.gold >= 0 and data.get("marker") is String

func fresh() -> RefCounted:
	var result = Store.new()
	result.directory = directory
	return result

func put(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	check(f != null, "fixture write " + path)
	if f: f.store_buffer(bytes)

func bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)

func frame(envelope: Dictionary) -> PackedByteArray:
	var data := var_to_bytes(envelope)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	return "ABCSAVE1".to_ascii_buffer() + hashing.finish() + data

func _run() -> void:
	var store = fresh()
	check(store.load_latest(valid).status == "empty" and not store.blocked, "empty directory")
	var first := {"gold": 9223372036854775807, "marker":"first"}
	check(store.commit(first, valid), "first commit")
	check(store.sequence == 1, "sequence one")
	var first_path: String = directory.path_join("slot%d.sav" % store.active_slot)
	var first_bytes := bytes(first_path)
	var reader = fresh()
	check(reader.load_latest(valid).payload == first, "exact int64 process-style read")
	check(first.gold == 9223372036854775807, "source untouched")
	groups += 1

	var second := {"gold":17,"marker":"second"}
	check(store.commit(second, valid), "second commit")
	var second_path: String = directory.path_join("slot%d.sav" % store.active_slot)
	check(second_path != first_path and bytes(first_path) == first_bytes, "previous valid copy preserved")
	reader = fresh()
	check(reader.load_latest(valid).payload == second and reader.sequence == 2, "newest chosen")
	var second_bytes := bytes(second_path)
	put(directory.path_join("slot0.sav.tmp"), PackedByteArray([99,88,77]))
	reader = fresh()
	check(reader.load_latest(valid).payload == second, "interrupted temporary file ignored")
	groups += 1

	put(second_path, second_bytes.slice(0,second_bytes.size()/2))
	reader = fresh()
	var fallback: Dictionary = reader.load_latest(valid)
	check(fallback.status == "recovered" and fallback.payload == first and not reader.blocked, "truncated newest falls back")
	check(reader.commit({"gold":19,"marker":"recovery"}, valid), "recovery can continue")
	check(bytes(first_path) == first_bytes, "recovery keeps valid predecessor")
	groups += 1

	put(second_path, second_bytes)
	var envelope: Dictionary = bytes_to_var(second_bytes.slice(40))
	envelope.digest[0] = (envelope.digest[0] + 1) % 256
	put(second_path, frame(envelope))
	reader = fresh()
	check(reader.load_latest(valid).payload == first, "digest corruption falls back")
	put(second_path, second_bytes)
	envelope = bytes_to_var(second_bytes.slice(40))
	envelope.version = 999
	put(second_path, frame(envelope))
	reader = fresh()
	check(reader.load_latest(valid).payload == first, "unknown format falls back")
	groups += 1

	put(second_path, second_bytes)
	reader = fresh()
	var only_first := func(data: Dictionary) -> bool: return valid(data) and data.marker == "first"
	check(reader.load_latest(only_first).payload == first, "semantic-invalid newest falls back")
	var before := bytes(second_path)
	check(not reader.commit({"gold":-1,"marker":"bad"}, valid), "invalid commit refused")
	check(bytes(second_path) == before and bytes(first_path) == first_bytes, "refused commit preserves both files")
	groups += 1

	put(first_path, PackedByteArray([1,2,3]))
	put(second_path, PackedByteArray([4,5,6]))
	reader = fresh()
	check(reader.load_latest(valid).status == "invalid" and reader.blocked, "all corrupt blocks writes")
	check(not reader.commit(first, valid), "never overwrite both invalid saves")
	check(bytes(first_path) == PackedByteArray([1,2,3]) and bytes(second_path) == PackedByteArray([4,5,6]), "corrupt evidence preserved")
	groups += 1

	put(first_path, first_bytes)
	put(second_path, second_bytes)
	reader = fresh()
	reader.load_latest(valid)
	reader.sequence = 9223372036854775807
	check(not reader.commit(first, valid), "sequence overflow refused")
	check(bytes(first_path) == first_bytes and bytes(second_path) == second_bytes, "overflow preserves data")
	groups += 1

	var stale_reader = fresh()
	stale_reader.load_latest(valid)
	var writer = fresh()
	writer.load_latest(valid)
	check(writer.commit({"gold":21,"marker":"newer_process"},valid),"new process checkpoint")
	check(not stale_reader.commit(first,valid) and stale_reader.blocked,"stale process cannot roll back newer checkpoint")
	var newest = fresh()
	check(newest.load_latest(valid).payload.marker=="newer_process","newer checkpoint survives stale writer")
	groups += 1

	# A directory at the pending-file path simulates a write failure, without
	# changing permissions on any owner file or touching the user's save.
	var failed_dir := directory + "-unwritable"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(failed_dir.path_join("slot0.sav.tmp")))
	reader = Store.new()
	reader.directory = failed_dir
	check(not reader.commit(first, valid), "I/O failure returned")
	check(reader.sequence == 0 and reader.active_slot == -1, "failed write is not committed")
	groups += 1

	check(groups == 9,"all nine groups completed")
	if failures.is_empty(): print("ASHBOUND_COURTYARD_SAVE_STORE_OK groups=",groups)
	quit(0 if failures.is_empty() else 1)
