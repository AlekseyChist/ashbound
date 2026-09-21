extends RefCounted
# Courtyard save schema: capture / validate / apply for the first courtyard snapshot.
# Single typed Dictionary, exactly 10 keys. No gameplay side effects in capture/validate.

const PROGRESS_PATH := "res://scripts/characters/character_progress.gd"

const ROOT_KEYS := ["schema_version", "location", "quest", "progress", "inventory", "player", "camera", "quick", "map_available", "pocket_available", "world_items"]
const QUEST_KEYS := ["state", "dummy_hits", "reward_claimed"]
const PLAYER_KEYS := ["position", "facing"]
const CAMERA_KEYS := ["yaw", "pitch"]
const INVENTORY_ROOT_KEYS := ["schema_version", "items", "equipped", "gold", "storage", "worn_storage"]

const LOCATION := "first_courtyard"
const SCHEMA_VERSION := 2

const POS_MIN := Vector3(-17.0, -0.5, -17.0)
const POS_MAX := Vector3(17.0, 5.0, 15.0)
const PITCH_MIN := deg_to_rad(-28.0)
const PITCH_MAX := deg_to_rad(5.0)

func _new_quest() -> Dictionary:
	return {"state": 0, "dummy_hits": 0, "reward_claimed": false}

func _new_player() -> Dictionary:
	return {"position": Vector3.ZERO, "facing": Vector3.FORWARD}

func _new_camera() -> Dictionary:
	return {"yaw": 0.0, "pitch": 0.0}

func _empty_quick() -> Array[String]:
	var out: Array[String] = []
	for i in 10:
		out.append("")
	return out

# ---------------------------------------------------------------- capture ---
func fresh_start(level: Node, inventory: Node) -> Dictionary:
	var data := capture(level, inventory)

	var quest := _new_quest()
	data["quest"] = quest

	var progress := {
		"schema_version": 1,
		"learning_points": 0,
		"point_awards": {},
		"guard_practice_completed": false,
	}
	data["progress"] = progress

	var inv_data: Dictionary = {
		"schema_version": int(data["inventory"]["schema_version"]),
		"items": [],
		"equipped": {},
		"gold": 0,
		"storage": {"placements": {}, "cells": {}},
	}
	for key in data["inventory"]["equipped"]:
		inv_data["equipped"][key] = null
	data["inventory"] = inv_data

	var player := {
		"position": level._player_spawn,
		"facing": Vector3.FORWARD,
	}
	data["player"] = player

	var camera := {
		"yaw": 0.0,
		"pitch": deg_to_rad(-12.0),
	}
	data["camera"] = camera

	data["quick"] = _empty_quick()
	data["world_items"] = []
	data["map_available"] = true
	data["pocket_available"] = true

	return data

func capture(level: Node, inventory: Node) -> Dictionary:
	var player := level.get_node("Actors/Player")
	var camera := level.get_node("CameraRig")
	var panel := level.get_node("InventoryMenu/RootControl/Overlay/Window")

	var quest := _new_quest()
	quest["state"] = int(level.state)
	quest["dummy_hits"] = int(level.dummy_hits)
	quest["reward_claimed"] = bool(level.reward_claimed)

	var player_data := _new_player()
	player_data["position"] = Vector3(player.global_position)
	player_data["facing"] = Vector3(player.facing_direction)

	var camera_data := _new_camera()
	camera_data["yaw"] = float(camera._yaw)
	camera_data["pitch"] = float(camera._pitch)

	var inv_data: Dictionary = inventory.get_save_data()

	var quick: Array[String] = []
	for id in panel._quick_bindings:
		# Normalize stale references only in the returned copy.
		if not _is_bindable_id(str(id), inv_data, inventory):
			id = ""
		quick.append(str(id))

	var map_stand := level.get_node("Interactions/MapStand")
	var map_available := bool(map_stand.available_on_crate)

	var data := {
		"schema_version": SCHEMA_VERSION,
		"location": LOCATION,
		"quest": quest,
		"progress": player.get_node("Progression").get_save_data(),
		"inventory": inv_data,
		"player": player_data,
		"camera": camera_data,
		"quick": quick,
		"map_available": map_available,
		"pocket_available": bool(level.get_node("Actors/Player/PocketAccess").available),
		"world_items": level.get_node("WorldItems").get_records() if level.has_node("WorldItems") else [],
	}
	return data.duplicate(true)


func _is_bindable_id(id: String, inventory_data: Dictionary, inventory: Node) -> bool:
	if id == "":
		return true
	var items = inventory_data.get("items", [])
	if items is Array:
		for entry in items:
			if not (entry is Dictionary):
				continue
			if str(entry.get("instance_id", "")) == id and inventory.describe_item_id(entry.id).quick_bindable:
				return true
	var equipped = inventory_data.get("equipped", {})
	if equipped is Dictionary:
		for value in equipped.values():
			if not (value is Dictionary):
				continue
			if str(value.get("instance_id", "")) == id and inventory.describe_item_id(value.id).quick_bindable:
				return true
	return false


# --------------------------------------------------------------- validate ---
func validate(data: Dictionary, inventory: Node) -> bool:
	var expected := ROOT_KEYS.duplicate()
	var schema_version = data.get("schema_version", null)
	if not (schema_version is int) or schema_version < 1 or schema_version > 2:
		return false
	if schema_version == 1:
		expected.erase("world_items")
	if not _is_exact_keys(data, expected):
		return false
	var location = data["location"]
	if not (location is String) or location != LOCATION:
		return false

	var quest = data["quest"]
	if not (quest is Dictionary) or not _is_exact_keys(quest, QUEST_KEYS):
		return false
	var state_raw = quest["state"]
	var hits_raw = quest["dummy_hits"]
	var claimed_raw = quest["reward_claimed"]
	if not (state_raw is int) or not (hits_raw is int) or not (claimed_raw is bool):
		return false
	var state: int = state_raw
	var hits: int = hits_raw
	var claimed: bool = claimed_raw
	if state < 0 or state > 6:
		return false
	if hits < 0 or hits > 3:
		return false
	if state < 4 and hits != 0:
		return false
	if state == 4 and (hits < 0 or hits > 2):
		return false
	if (state == 5 or state == 6) and hits != 3:
		return false
	if claimed != (state >= 3):
		return false

	var player = data["player"]
	if not (player is Dictionary) or not _is_exact_keys(player, PLAYER_KEYS):
		return false
	var pos_raw = player["position"]
	var facing_raw = player["facing"]
	if not (pos_raw is Vector3) or not (facing_raw is Vector3):
		return false
	var pos: Vector3 = pos_raw
	var facing: Vector3 = facing_raw
	if not _finite(pos) or not _finite(facing):
		return false
	if pos.x < POS_MIN.x or pos.x > POS_MAX.x:
		return false
	if pos.y < POS_MIN.y or pos.y > POS_MAX.y:
		return false
	if pos.z < POS_MIN.z or pos.z > POS_MAX.z:
		return false
	if absf(facing.y) > 0.001:
		return false
	if absf(facing.length() - 1.0) > 0.001:
		return false

	var camera = data["camera"]
	if not (camera is Dictionary) or not _is_exact_keys(camera, CAMERA_KEYS):
		return false
	var yaw_raw = camera["yaw"]
	var pitch_raw = camera["pitch"]
	if not (yaw_raw is float) or not (pitch_raw is float):
		return false
	var yaw: float = yaw_raw
	var pitch: float = pitch_raw
	if not is_finite(yaw) or not is_finite(pitch):
		return false
	if yaw < -PI or yaw > PI:
		return false
	if pitch < PITCH_MIN or pitch > PITCH_MAX:
		return false

	var map_available_raw = data["map_available"]
	var pocket_available_raw = data["pocket_available"]
	if not (map_available_raw is bool) or not (pocket_available_raw is bool):
		return false
	var map_available: bool = map_available_raw
	var pocket_available: bool = pocket_available_raw

	var inv_data = data["inventory"]
	if not (inv_data is Dictionary):
		return false
	if not _is_subset_keys(inv_data, INVENTORY_ROOT_KEYS):
		return false
	if not inv_data.has("storage"):
		return false
	var validated_inv_raw = inventory._validate_save_data(inv_data)
	if not (validated_inv_raw is Dictionary):
		return false
	var validated_inv: Dictionary = validated_inv_raw
	if validated_inv.is_empty():
		return false

	var quick = data["quick"]
	if not (quick is Array) or quick.size() != 10:
		return false
	for id in quick:
		if not (id is String):
			return false
		if id != "" and not _is_bindable_id(id, inv_data, inventory):
			return false

	var progress = data["progress"]
	if not (progress is Dictionary):
		return false
	var guard_raw = progress.get("guard_practice_completed", false)
	if not (guard_raw is bool):
		return false
	var guard: bool = guard_raw
	if guard != (state == 6):
		return false
	if not _validate_progress_detached(progress):
		return false

	var world_items_raw = data.get("world_items", [])
	if not (world_items_raw is Array):
		return false
	var world_items: Array = world_items_raw
	var world_manager: Node3D = load("res://scripts/courtyard/courtyard_world_items.gd").new()
	world_manager.setup(null, inventory)
	var world_ok: bool = world_manager.validate_records(world_items, inv_data)
	world_manager.free()
	if not world_ok:
		return false
	var map_count := _count_map_items(inv_data)
	for record in world_items:
		if not (record is Dictionary):
			return false
		var ground_item: Dictionary = record["item"]
		if ground_item["id"] == "courtyard_sketch":
			map_count += int(ground_item["quantity"])
	if map_count < 0 or map_count > 1:
		return false
	if map_available != (map_count == 0):
		return false
	return true


func _validate_progress_detached(progress: Dictionary) -> bool:
	var script := load(PROGRESS_PATH) as Script
	if script == null:
		return false
	var instance = script.new()
	if instance == null:
		return false
	var ok := bool(instance.load_save_data(progress))
	instance.free()
	return ok

func _count_map_items(inv_data: Dictionary) -> int:
	var count := 0
	var items = inv_data.get("items", [])
	if items is Array:
		for entry in items:
			if not (entry is Dictionary):
				continue
			if str(entry.get("id", "")) == "courtyard_sketch":
				count += int(entry.get("quantity", 1))
	return count


func _is_exact_keys(d: Dictionary, keys: Array) -> bool:
	if d.size() != keys.size():
		return false
	for k in keys:
		if not d.has(k):
			return false
	return true

func _is_subset_keys(d: Dictionary, allowed: Array) -> bool:
	for k in d.keys():
		if not allowed.has(k):
			return false
	return true

func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

# ----------------------------------------------------------------- apply ---
var _applying: bool = false

func apply(level: Node, inventory: Node, data: Dictionary) -> bool:
	if _applying:
		return false
	if not validate(data, inventory):
		return false
	if data.get("world_items", []).size() > 0 and not level.has_node("WorldItems"):
		return false
	if inventory.get("_trade_guard") or inventory.get("_wearable_guard") or inventory.get("_storage_guard"):
		return false

	var player := level.get_node("Actors/Player")
	var progression := player.get_node("Progression")
	var pocket := player.get_node("PocketAccess")
	var camera := level.get_node("CameraRig")
	var panel := level.get_node("InventoryMenu/RootControl/Overlay/Window")
	var hud := level.get_node("HUD")
	var woodpile_label := level.get_node("Interactions/Woodpile/Label3D")
	var map_stand := level.get_node("Interactions/MapStand")
	var menu := level.get_node("InventoryMenu")

	_applying = true

	# Close menu only after validation.
	if menu.has_method("close_menu"):
		menu.close_menu(false)

	# Remember previous signal-block states, then block.
	var inv_blocked: bool = inventory.is_blocking_signals()
	var prog_blocked: bool = progression.is_blocking_signals()
	var pocket_blocked: bool = pocket.is_blocking_signals()
	inventory.set_block_signals(true)
	progression.set_block_signals(true)
	pocket.set_block_signals(true)

	var ok := false
	var quest: Dictionary = data["quest"]
	var player_data: Dictionary = data["player"]
	var camera_data: Dictionary = data["camera"]
	var quick: Array[String] = []
	for id in data["quick"]:
		quick.append(str(id))

	# Install all state before any notifications.
	level.state = int(quest["state"])
	level.dummy_hits = int(quest["dummy_hits"])
	level.reward_claimed = bool(quest["reward_claimed"])
	level._pending_interact = false
	level._current_target = null
	level._current_attack_target = null

	map_stand.available_on_crate = bool(data["map_available"])
	pocket.available = bool(data["pocket_available"])

	var prog_loaded: bool = progression.load_save_data(data["progress"])
	var inv_loaded: bool = inventory.load_save_data(data["inventory"])
	if not prog_loaded or not inv_loaded:
		inventory.set_block_signals(inv_blocked)
		progression.set_block_signals(prog_blocked)
		pocket.set_block_signals(pocket_blocked)
		_applying = false
		return false

	# Restore world items silently (no replay drop/pickup, no changed notifications).
	var world_items := level.get_node_or_null("WorldItems")
	if world_items != null and world_items.has_method("restore_records"):
		world_items.restore_records(data.get("world_items", []))

	# Player coherent state.
	if player.has_method("stop_input"):
		player.stop_input()
	player.velocity = Vector3.ZERO
	player.input_enabled = true
	player.global_position = Vector3(player_data["position"])
	player.facing_direction = Vector3(player_data["facing"])

	# Camera coherent state.
	if camera.has_method("stop_look"):
		camera.stop_look()
	camera._yaw = float(camera_data["yaw"])
	camera._pitch = float(camera_data["pitch"])
	if camera.has_method("_apply_rotation"):
		camera._apply_rotation()
	if camera.has_method("snap_to_target"):
		camera.snap_to_target()
	camera.input_enabled = true

	# HUD / focus / feedback.
	if hud.has_method("reset_controls"):
		hud.reset_controls()
	if hud.has_method("clear_message"):
		hud.clear_message()
	level._last_focus_prompt = ""
	if hud.has_method("set_prompt"):
		hud.set_prompt("")
	woodpile_label.visible = int(quest["state"]) < 2

	var focus := level.get_node("InteractionFocus")
	if focus != null and focus.has_method("clear_target"):
		focus.clear_target()
	var attack_focus := level.get_node("AttackFocus")
	if attack_focus != null and attack_focus.has_method("clear_target"):
		attack_focus.clear_target()

	# Quick bindings via clear/append, then refresh panel.
	panel._quick_bindings.clear()
	for id in quick:
		panel._quick_bindings.append(id)
	if panel.has_method("refresh_contents"):
		panel.refresh_contents()

	map_stand._refresh_appearance()

	# Emits after coherent world; level._refresh_objective emits journal_changed,
	# so it runs only after all state is installed.
	level._refresh_objective()

	ok = true

	# Restore block states, then emit coherent signals.
	inventory.set_block_signals(inv_blocked)
	progression.set_block_signals(prog_blocked)
	pocket.set_block_signals(pocket_blocked)

	if ok:
		var gold := int(data["inventory"].get("gold", 0))
		if inventory.has_signal("inventory_restored") and not inv_blocked:
			inventory.emit_signal("inventory_restored")
		if inventory.has_signal("gold_changed") and not inv_blocked:
			inventory.emit_signal("gold_changed", gold)
		if inventory.has_signal("storage_changed") and not inv_blocked:
			inventory.emit_signal("storage_changed")
		if progression.has_signal("changed") and not prog_blocked:
			progression.emit_signal("changed")
		if pocket.has_signal("availability_changed") and not pocket_blocked:
			pocket.emit_signal("availability_changed")

	_applying = false
	return ok


func _signal_blocked(node: Node) -> bool:
	return node != null and node.is_blocking_signals()


func _block_signals(node: Node, blocked: bool) -> void:
	if node == null:
		return
	node.set_block_signals(blocked)
