extends Node

const SAVE_STORE_PATH := "res://scripts/courtyard/courtyard_save_store.gd"
const SAVE_SCHEMA_PATH := "res://scripts/courtyard/courtyard_save_schema.gd"

const AUTOSAVE_INTERVAL: float = 2.0

var enabled: bool = false
var load_status: String = "not_started"
var last_error: String = ""
var save_count: int = 0

var _level: Node = null
var _inventory: Node = null
var _store: RefCounted = null
var _schema: RefCounted = null
var _busy: bool = false
var _elapsed: float = 0.0
var _last_snapshot: PackedByteArray = PackedByteArray()
var _queued: bool = false
var _warning_shown: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func initialize(level: Node, directory_override: String = "") -> String:
	if enabled or _store != null:
		return load_status
	_level = level
	_store = load(SAVE_STORE_PATH).new()
	_schema = load(SAVE_SCHEMA_PATH).new()
	if directory_override != "":
		_store.directory = directory_override
	_inventory = get_node("/root/Inventory")
	_busy = true
	var result: Dictionary = _store.load_latest(_validate)
	load_status = str(result.get("status", "invalid"))
	if load_status == "loaded" or load_status == "recovered":
		var payload: Variant = result.get("payload", null)
		if not _schema.apply(_level, _inventory, payload):
			_store.blocked = true
			load_status = "invalid"
			last_error = "snapshot_apply_failed"
	elif load_status == "empty":
		pass
	else:
		if last_error == "":
			last_error = str(result.get("error", ""))
	_busy = false
	enabled = true
	_connect_inventory_signals()
	_connect_progression_signals()
	if load_status == "empty":
		flush_now()
	elif load_status == "loaded" or load_status == "recovered":
		_last_snapshot = _capture_bytes()
	_show_status_message()
	print("ASHBOUND_SAVE_READY status=", load_status, " sequence=", _store.sequence)
	return load_status


func queue_save(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	if not enabled or _busy or _store == null or _store.blocked:
		return
	if _queued:
		return
	_queued = true
	call_deferred("_flush_deferred")


func flush_now() -> bool:
	if not enabled or _level == null or not is_instance_valid(_level) or not _level.is_inside_tree():
		return false
	if _busy or _store == null or _store.blocked:
		return false
	_busy = true
	var snapshot: Dictionary = _schema.capture(_level, _inventory)
	if not _validate(snapshot):
		last_error = "snapshot_validation_failed"
		_busy = false
		return false
	var bytes := var_to_bytes(snapshot)
	if bytes == _last_snapshot:
		_busy = false
		return true
	var ok: bool = _store.commit(snapshot, _validate)
	if ok:
		_last_snapshot = bytes
		save_count += 1
		_warning_shown = false
	else:
		last_error = str(_store.last_error)
		_show_write_failure()
	_busy = false
	return ok


func _process(delta: float) -> void:
	if not enabled or _busy:
		return
	_elapsed += delta
	if _elapsed >= AUTOSAVE_INTERVAL:
		_elapsed = 0.0
		flush_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if enabled and not _busy:
			flush_now()


func _exit_tree() -> void:
	if not enabled or _store == null or _store.blocked:
		return
	if _level == null or not is_instance_valid(_level):
		return
	if _inventory == null or not is_instance_valid(_inventory):
		return
	flush_now()


func _flush_deferred() -> void:
	_queued = false
	flush_now()


func _connect_inventory_signals() -> void:
	if _inventory == null:
		return
	var required: Array[StringName] = ["item_added", "item_removed", "inventory_restored", "storage_changed", "gold_changed"]
	for signal_name in required:
		if _inventory.has_signal(signal_name):
			_inventory.connect(signal_name, queue_save)
	for optional_name in ["item_equipped", "item_unequipped"]:
		if _inventory.has_signal(optional_name):
			_inventory.connect(optional_name, queue_save)


func _connect_progression_signals() -> void:
	var progression_path := NodePath("Actors/Player/Progression")
	var progression: Node = _level.get_node_or_null(progression_path)
	if progression != null and progression.has_signal("changed"):
		progression.connect("changed", queue_save)
	_level.journal_changed.connect(queue_save)


func _validate(data: Dictionary) -> bool:
	return _schema.validate(data, _inventory)


func _capture_bytes() -> PackedByteArray:
	if _level == null or not is_instance_valid(_level):
		return PackedByteArray()
	var snapshot: Dictionary = _schema.capture(_level, _inventory)
	return var_to_bytes(snapshot)


func _flush_baseline() -> void:
	flush_now()


func _show_status_message() -> void:
	if load_status == "invalid":
		_show_warning("SAVE_STATUS_TITLE", "SAVE_LOAD_FAILED")
	elif load_status == "recovered":
		_show_warning("SAVE_STATUS_TITLE", "SAVE_RECOVERED")


func _show_write_failure() -> void:
	_show_warning("SAVE_STATUS_TITLE", "SAVE_WRITE_FAILED")


func _show_warning(title_key: String, message_key: String) -> void:
	if _warning_shown:
		return
	_warning_shown = true
	var hud: Node = _level.get_node_or_null(NodePath("HUD"))
	if hud != null and hud.has_method("show_message"):
		hud.show_message(title_key, message_key)
