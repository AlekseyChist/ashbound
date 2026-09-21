class_name InventoryStorageLayout
extends RefCounted
## Reusable physical inventory storage layout.
## Tracks assignment of carried instance ids to stable container slots and exact cells.
## Does not own or copy items; canonical data stays in Inventory.items.

const _MAX_TOTAL_CAPACITY := 1000000
const _VALID_KINDS: Array = ["pocket", "pouch", "backpack"]

var _definitions: Array = []
var _assignments: Dictionary = {}
var _cells: Dictionary = {}


func configure(definitions: Variant, carried: Variant) -> bool:
	var parsed: Variant = _parse_definitions(definitions)
	if parsed == null:
		return false
	var planned: Variant = _plan_assignments(parsed, carried, _assignments)
	if planned == null:
		return false
	var cells: Variant = _plan_cells(parsed, carried, planned, _cells)
	if cells == null:
		return false
	_definitions = parsed
	_assignments = planned
	_cells = cells
	return true


func reconcile(carried: Variant) -> bool:
	var planned: Variant = _plan_assignments(_definitions, carried, _assignments)
	if planned == null:
		return false
	var cells: Variant = _plan_cells(_definitions, carried, planned, _cells)
	if cells == null:
		return false
	_assignments = planned
	_cells = cells
	return true


func move(instance_id: String, destination_id: String, carried: Variant, cell_index: int = -1) -> bool:
	if cell_index < -1:
		return false
	if not _is_valid_carried(carried):
		return false
	var by_id := _definitions_by_id()
	if not by_id.has(destination_id):
		return false
	var planned: Variant = _plan_assignments(_definitions, carried, _assignments)
	if planned == null or not planned.has(instance_id):
		return false
	var cells: Variant = _plan_cells(_definitions, carried, planned, _cells)
	if cells == null:
		return false
	var source_container := str(planned[instance_id])
	var source_index := int(cells.get(instance_id, -1))
	if cell_index >= 0:
		var capacity := int(by_id[destination_id]["capacity"])
		if cell_index >= capacity:
			return false
		var occupant := ""
		for key in planned.keys():
			if str(planned[key]) == destination_id and int(cells.get(key, -1)) == cell_index:
				occupant = str(key)
				break
		if occupant != "":
			planned[occupant] = source_container
			cells[occupant] = source_index
		planned[instance_id] = destination_id
		cells[instance_id] = cell_index
	else:
		if source_container == destination_id:
			_assignments = planned
			_cells = cells
			return true
		var target_used := 0
		for key in planned.keys():
			if str(planned[key]) == destination_id:
				target_used += 1
		if target_used >= int(by_id[destination_id]["capacity"]):
			return false
		var free_index := -1
		for index in range(int(by_id[destination_id]["capacity"])):
			var occupied := false
			for key in planned.keys():
				if str(key) == instance_id:
					continue
				if str(planned[key]) == destination_id and int(cells.get(key, -1)) == index:
					occupied = true
					break
			if not occupied:
				free_index = index
				break
		if free_index < 0:
			return false
		planned[instance_id] = destination_id
		cells[instance_id] = free_index
	_assignments = planned
	_cells = cells
	return true


func get_capacity() -> int:
	var total := 0
	for def in _definitions:
		total += int(def["capacity"])
	return total


func get_containers() -> Array:
	var result: Array = []
	for def in _definitions:
		var used := 0
		for key in _assignments.keys():
			if _assignments[key] == def["id"]:
				used += 1
		result.append({
			"id": def["id"],
			"kind": def["kind"],
			"capacity": int(def["capacity"]),
			"used": used,
		})
	return result


func get_container_id(instance_id: String) -> String:
	if _assignments.has(instance_id):
		return str(_assignments[instance_id])
	return ""


func get_cell_index(instance_id: String) -> int:
	if _cells.has(instance_id):
		return int(_cells[instance_id])
	return -1


func get_save_data() -> Dictionary:
	var placements: Dictionary = {}
	for key in _assignments.keys():
		placements[str(key)] = str(_assignments[key])
	var cells: Dictionary = {}
	for key in _cells.keys():
		cells[str(key)] = int(_cells[key])
	return {"placements": placements, "cells": cells}


func load_placements(data: Variant, carried: Variant) -> bool:
	if not data is Dictionary:
		return false
	var raw: Variant = (data as Dictionary).get("placements", null)
	if not raw is Dictionary:
		return false
	var placements: Dictionary = raw
	if not _is_valid_carried(carried):
		return false
	var carried_ids: Array = []
	for entry in carried:
		carried_ids.append(str((entry as Dictionary).get("instance_id", "")))
	if carried_ids.size() != placements.size():
		return false
	var by_id: Dictionary = _definitions_by_id()
	var usage: Dictionary = {}
	for key in placements.keys():
		if not key is String:
			return false
		var dest: Variant = placements[key]
		if not dest is String:
			return false
		if not by_id.has(dest):
			return false
		usage[dest] = int(usage.get(dest, 0)) + 1
	for id in carried_ids:
		if not placements.has(id):
			return false
	for key in usage.keys():
		if int(usage[key]) > int(by_id[key]["capacity"]):
			return false
	var next: Dictionary = {}
	for id in carried_ids:
		next[id] = str(placements[id])
	var raw_cells: Variant = (data as Dictionary).get("cells", null)
	var cells: Variant = _plan_cells(_definitions, carried, next, {})
	if cells == null:
		return false
	if data.has("cells"):
		if not raw_cells is Dictionary:
			return false
		var saved_cells: Dictionary = raw_cells
		if saved_cells.size() != carried_ids.size():
			return false
		var occupancy: Dictionary = {}
		for id in carried_ids:
			if not saved_cells.has(id):
				return false
			var cell: Variant = saved_cells[id]
			if not cell is int:
				return false
			var container_id: String = next[id]
			var capacity: int = int(by_id[container_id]["capacity"])
			if int(cell) < 0 or int(cell) >= capacity:
				return false
			var key: String = container_id + ":" + str(int(cell))
			if occupancy.has(key):
				return false
			occupancy[key] = true
		cells = saved_cells.duplicate(true)
	_assignments = next
	_cells = cells
	return true


func _plan_cells(definitions: Variant, carried: Variant, planned: Dictionary, previous: Dictionary) -> Variant:
	if not definitions is Array or not planned is Dictionary:
		return null
	var by_id: Dictionary = {}
	for def in definitions:
		by_id[def["id"]] = def
	var result: Dictionary = {}
	var occupied: Dictionary = {}
	for dest in by_id.keys():
		occupied[dest] = {}
	var carried_ids: Dictionary = {}
	for entry in carried:
		var id := str((entry as Dictionary).get("instance_id", ""))
		if not planned.has(id):
			return null
		var dest := str(planned[id])
		if not by_id.has(dest):
			return null
		carried_ids[id] = true
	# Pass 1: reserve surviving in-bounds previous cells.
	for id in carried_ids.keys():
		var dest := str(planned[id])
		var capacity := int(by_id[dest]["capacity"])
		if _assignments.has(id) and _assignments[id] == planned[id]:
			var prev_cell: Variant = previous.get(id, null)
			if _is_strict_int(prev_cell):
				var idx := int(prev_cell)
				if idx >= 0 and idx < capacity and not occupied[dest].has(idx):
					result[id] = idx
					occupied[dest][idx] = true
	# Pass 2: assign first free cell for every unassigned carried id.
	for id in carried_ids.keys():
		if result.has(id):
			continue
		var dest := str(planned[id])
		var capacity := int(by_id[dest]["capacity"])
		var free := -1
		for idx in range(capacity):
			if not occupied[dest].has(idx):
				free = idx
				break
		if free < 0:
			return null
		result[id] = free
		occupied[dest][free] = true
	return result












func _parse_definitions(definitions: Variant) -> Variant:
	if not definitions is Array:
		return null
	var result: Array = []
	var seen: Dictionary = {}
	var total := 0
	for entry in definitions:
		if not entry is Dictionary:
			return null
		var id: Variant = (entry as Dictionary).get("id", null)
		var kind: Variant = (entry as Dictionary).get("kind", null)
		var capacity: Variant = (entry as Dictionary).get("capacity", null)
		if not id is String or (id as String).is_empty():
			return null
		if not kind is String or not _VALID_KINDS.has(kind):
			return null
		if not _is_strict_int(capacity):
			return null
		var cap := int(capacity)
		if cap < 1 or cap > _MAX_TOTAL_CAPACITY:
			return null
		if seen.has(id):
			return null
		seen[id] = true
		total += cap
		if total > _MAX_TOTAL_CAPACITY:
			return null
		result.append({"id": id, "kind": kind, "capacity": cap})
	return result


func _plan_assignments(definitions: Variant, carried: Variant, previous: Dictionary) -> Variant:
	if not definitions is Array:
		return null
	if not _is_valid_carried(carried):
		return null
	var by_id: Dictionary = {}
	for def in definitions:
		by_id[def["id"]] = def
	var usage: Dictionary = {}
	var planned: Dictionary = {}
	for entry in carried:
		var id := str((entry as Dictionary).get("instance_id", ""))
		if previous.has(id):
			var prev_dest: Variant = previous[id]
			if not prev_dest is String or (prev_dest as String).is_empty():
				continue
			if not by_id.has(prev_dest):
				return null
			planned[id] = prev_dest
			usage[prev_dest] = int(usage.get(prev_dest, 0)) + 1
	for def in definitions:
		if int(usage.get(def["id"], 0)) > int(def["capacity"]):
			return null
	for entry in carried:
		var id := str((entry as Dictionary).get("instance_id", ""))
		if planned.has(id):
			continue
		var placed := false
		for def in definitions:
			var used := int(usage.get(def["id"], 0))
			if used < int(def["capacity"]):
				planned[id] = def["id"]
				usage[def["id"]] = used + 1
				placed = true
				break
		if not placed:
			return null
	return planned


func _is_valid_carried(carried: Variant) -> bool:
	if not carried is Array:
		return false
	var seen: Dictionary = {}
	for entry in carried:
		if not entry is Dictionary:
			return false
		var id: Variant = (entry as Dictionary).get("instance_id", null)
		if not id is String or (id as String).is_empty():
			return false
		if seen.has(id):
			return false
		seen[id] = true
	return true


func _definitions_by_id() -> Dictionary:
	var result: Dictionary = {}
	for def in _definitions:
		result[def["id"]] = def
	return result


func _is_strict_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT
