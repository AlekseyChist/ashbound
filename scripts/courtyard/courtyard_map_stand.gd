extends "res://scripts/courtyard/interaction_point.gd"

## CourtyardMapStand — prototype interaction: take ONE physical sketch from
## CrateA and put it back. NOT a free automatic grant, NOT a canon story reward.

const CarriedMapAccess := preload("res://scripts/courtyard/carried_map_access.gd")

const ITEM_ID: StringName = &"courtyard_sketch"
const MIN_SUCCESS_INTERVAL_MS: int = 350

## Public state: is the sheet physically on the crate?
var available_on_crate: bool = true
## Reentrance guard while a transfer is in progress.
var _busy: bool = false
## Real-time (ms) of the last successful transfer (anti-spam, not anti-retry).
var _last_success_msec: int = -1000


func _ready() -> void:
	super._ready()
	# Avoid a duplicate sheet when the scene is instantiated with a carried
	# snapshot (player already holds the prototype sketch).
	if Inventory.has_item(ITEM_ID):
		available_on_crate = false
	interacted.connect(_on_interacted)
	Inventory.item_added.connect(_refresh_appearance)
	Inventory.item_removed.connect(_refresh_appearance)
	Inventory.inventory_restored.connect(_refresh_appearance)
	Inventory.storage_changed.connect(_refresh_appearance)
	_refresh_appearance()


func get_prompt() -> String:
	if available_on_crate:
		return Localization.text("COURTYARD_ACTION_TAKE_MAP")
	var pocket := _get_pocket()
	if Inventory.get_item_count(ITEM_ID) == 1 and not CarriedMapAccess.find_carried_map(Inventory, pocket).is_empty():
		return Localization.text("COURTYARD_ACTION_RETURN_MAP")
	return Localization.text("COURTYARD_ACTION_MAP_ABSENT")


## Attempt to take or return the prototype sketch. Returns true on success.
func try_transfer() -> bool:
	if _busy:
		return false
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_success_msec < MIN_SUCCESS_INTERVAL_MS:
		return false
	var level := get_parent().get_parent()
	if level == null:
		return false
	var player: Node = level.get_node("Actors/Player")
	if player == null or not player.input_enabled or player.is_attacking():
		return false
	var from: Vector2 = Vector2(global_position.x, global_position.z)
	var to: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	if from.distance_to(to) > level.interact_radius:
		return false
	if not level._has_line_of_sight(global_position, player.global_position):
		return false
	var pocket := _get_pocket()
	if pocket == null:
		return false

	_busy = true
	var ok := false
	if available_on_crate:
		if pocket.has_access() and not Inventory.has_item(ITEM_ID):
			if Inventory.add_item(ITEM_ID):
				available_on_crate = false
				ok = true
			else:
				level.get_node("HUD").show_message("ITEM_COURTYARD_SKETCH_NAME", "COURTYARD_MAP_FULL")
	else:
		var carried := CarriedMapAccess.find_carried_map(Inventory, pocket)
		if Inventory.get_item_count(ITEM_ID) == 1 and not carried.is_empty():
			if Inventory.remove_item(ITEM_ID):
				available_on_crate = true
				ok = true

	if ok:
		_last_success_msec = now_ms
	_busy = false
	_refresh_appearance()
	return ok


func _on_interacted(point: Node) -> void:
	if point == self:
		try_transfer()


func _refresh_appearance(_unused: Variant = null) -> void:
	var paper := get_node("Paper")
	paper.visible = available_on_crate


func _get_pocket() -> Node:
	var level := get_parent().get_parent()
	if level == null:
		return null
	var player: Node = level.get_node("Actors/Player")
	if player == null:
		return null
	return player.get_node("PocketAccess")
