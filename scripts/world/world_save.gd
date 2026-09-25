extends Node
## WORLD-SAVE-01: autosave of the world scene — carried things and wallet, where the hero
## stands and faces, and the hero's progress. Same crash-safe two-slot store as the courtyard
## save (own format name and folder). The lesson keeps its own file (village_lesson.gd) and
## time/weather/settings keep theirs until the campaign save joins them.
## A missing save starts fresh; a damaged one is not applied (the store keeps the last good slot).
const StoreScript = preload("res://scripts/courtyard/courtyard_save_store.gd")
const FORMAT := "ASHBOUND_WORLD"
const DIRECTORY := "user://world-save-v1"
const AUTOSAVE_INTERVAL := 2.0
const VERSION := 1

var world: Node3D
var inventory: Node
var store: RefCounted
var load_status := ""
var save_count := 0
var enabled := false
var _last_snapshot := PackedByteArray()
var _elapsed := 0.0
var _busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func initialize(scene: Node3D, directory: String = DIRECTORY) -> String:
	world = scene
	inventory = get_node("/root/Inventory")
	store = StoreScript.new()
	store.format_name = FORMAT
	store.directory = directory
	_busy = true
	var result: Dictionary = store.load_latest(validate)
	load_status = str(result.get("status", "invalid"))
	if load_status == "loaded" or load_status == "recovered":
		if not apply(result.get("payload", {})):
			store.blocked = true
			load_status = "invalid"
	_busy = false
	enabled = true
	for signal_name in ["item_added", "item_removed", "inventory_restored", "storage_changed", "gold_changed", "item_equipped", "item_unequipped"]:
		if inventory.has_signal(signal_name):
			inventory.connect(signal_name, queue_save)
	var progression: Node = world.player.get_node_or_null("Progression")
	if progression != null and progression.has_signal("changed"):
		progression.changed.connect(queue_save)
	if load_status == "empty":
		flush_now()
	else:
		_last_snapshot = var_to_bytes(capture())
	print("WORLD_SAVE_READY status=", load_status, " sequence=", store.sequence)
	return load_status

func capture() -> Dictionary:
	var player: CharacterBody3D = world.player
	var progression: Node = player.get_node_or_null("Progression")
	return {
		"version": VERSION,
		"hero": {
			"position": [player.global_position.x, player.global_position.y, player.global_position.z],
			"facing": [player.facing_direction.x, player.facing_direction.z],
		},
		"inventory": inventory.get_save_data(),
		"progression": progression.get_save_data() if progression != null else {},
	}

func validate(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != VERSION: return false
	var hero: Variant = data.get("hero")
	if not hero is Dictionary: return false
	var position: Variant = hero.get("position")
	var facing: Variant = hero.get("facing")
	if not (position is Array and position.size() == 3 and facing is Array and facing.size() == 2): return false
	for value in position + facing:
		if not (value is float or value is int) or not is_finite(float(value)): return false
	if not data.get("inventory") is Dictionary or data.inventory.is_empty(): return false
	if inventory._validate_save_data(data.inventory).is_empty(): return false
	return data.get("progression") is Dictionary

## Put the saved state into the world. The hero goes back only onto real ground inside the map.
func apply(data: Variant) -> bool:
	if not data is Dictionary or not validate(data):
		return false
	if not inventory.load_save_data(data.inventory):
		return false
	var progression: Node = world.player.get_node_or_null("Progression")
	if progression != null and not data.progression.is_empty():
		progression.load_save_data(data.progression)
	var p: Array = data.hero.position
	var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
	if at.y > world.fall_limit() + 2.0:
		world.player.velocity = Vector3.ZERO
		world.player.global_position = at + Vector3.UP * .1
		var f: Array = data.hero.facing
		var facing := Vector3(float(f[0]), 0, float(f[1]))
		if facing.length() > .01:
			world.player.facing_direction = facing.normalized()
		world.camera_rig.snap_to_target()
	return true

func queue_save(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	if enabled and not _busy:
		flush_now.call_deferred()

func flush_now() -> bool:
	if not enabled or _busy or store == null or store.blocked or not world.is_inside_tree():
		return false
	_busy = true
	var snapshot := capture()
	var ok := validate(snapshot)
	var bytes := var_to_bytes(snapshot)
	if ok and bytes != _last_snapshot:
		ok = store.commit(snapshot, validate)
		if ok:
			_last_snapshot = bytes
			save_count += 1
	_busy = false
	return ok

func _process(delta: float) -> void:
	if not enabled:
		return
	_elapsed += delta
	if _elapsed >= AUTOSAVE_INTERVAL:
		_elapsed = 0.0
		flush_now()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		flush_now()
