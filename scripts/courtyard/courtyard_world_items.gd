extends Node3D
## Мировые предметы двора: хранение, сброс и подбор канонических стеков.
## Не создаёт предметы, не меняет статы/лечение игрока, не имеет коллизий.

const MAX_DROPS: int = 128
const DROPPED_ITEM_SCRIPT: GDScript = preload("res://scripts/courtyard/courtyard_dropped_item.gd")
const ICON_MAP: String = "res://assets/ui/maps/courtyard-sketch-v1.png"
const ICON_BACKPACK: String = "res://assets/ui/inventory/backpack-v1.png"
const ICON_POUCH: String = "res://assets/ui/inventory/pouch-v1.png"
const ICON_ATLAS: String = "res://assets/ui/inventory/items-v1.png"
const ATLAS_ORDER: Array[String] = [
	"rusty_sword", "iron_sword", "cultist_blade",
	"leather_armor", "chain_mail", "bread",
	"health_potion", "stamina_potion", "sacred_ash",
]

signal changed()

var _busy: bool = false
var _records: Array[Dictionary] = []
var _points: Array[Node3D] = []
var _level: Node = null
var _inventory: Node = null


func setup(level: Node, inventory: Node) -> void:
	_level = level
	_inventory = inventory


func get_records() -> Array:
	var out: Array = []
	for record in _records:
		out.append(_deep_copy_value(record))
	return out


func get_points() -> Array:
	var out: Array = []
	for point in _points:
		if is_instance_valid(point):
			out.append(point)
	return out


static func texture_for_item(item_id: String) -> Texture2D:
	match item_id:
		"courtyard_sketch":
			return load(ICON_MAP)
		"traveler_backpack":
			return load(ICON_BACKPACK)
		"belt_pouch":
			return load(ICON_POUCH)
	var atlas_index: int = ATLAS_ORDER.find(item_id)
	if atlas_index < 0:
		return null
	var atlas: Texture2D = load(ICON_ATLAS)
	if atlas == null:
		return null
	var region_size: Vector2 = atlas.get_size() / 3.0
	var col: int = atlas_index % 3
	var row: int = floori(atlas_index / 3.0)
	var atlas_texture: AtlasTexture = AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = Rect2(Vector2(col, row) * region_size, region_size)
	atlas_texture.filter_clip = true
	return atlas_texture


func validate_records(records: Variant, inventory_snapshot: Dictionary) -> bool:
	if not (records is Array):
		return false
	var record_array: Array = records
	if record_array.size() > MAX_DROPS:
		return false
	var seen_ids: Dictionary = {}
	for item in _iter_inventory_items(inventory_snapshot):
		var value: Variant = item.get("instance_id")
		if not (value is String) or value == "" or seen_ids.has(value):
			return false
		seen_ids[value] = true
	for record in record_array:
		if not _is_exact_record(record, seen_ids):
			return false
	return true


func restore_records(records: Array) -> void:
	_records.clear()
	_points.clear()
	for node in get_children():
		remove_child(node)
		node.queue_free()
	for record in records:
		var copy: Dictionary = _deep_copy_value(record)
		_records.append(copy)
		_spawn_point(copy, true)


func drop_item(handle: Dictionary) -> bool:
	if _busy or _level == null or _inventory == null:
		return false
	if not (handle is Dictionary):
		return false
	var instance_id: String = str(handle.get("instance_id", ""))
	if instance_id == "":
		return false
	var owned: Variant = _inventory.resolve_owned_item({"instance_id": instance_id})
	if not (owned is Dictionary) or owned.is_empty():
		return false
	var rules: Variant = _inventory.get_item_rules(owned)
	if not (rules is Dictionary):
		return false
	if bool(rules.get("droppable", false)) == false:
		return false
	if bool(rules.get("quest_locked", false)):
		return false
	var storage: Variant = _inventory.get_item_storage(instance_id)
	if not (storage is String) or str(storage) == "":
		return false
	var texture: Variant = texture_for_item(str(owned.get("id", "")))
	if texture == null:
		return false
	if _records.size() >= MAX_DROPS:
		return false
	var player: Node3D = _level.get_node_or_null("Actors/Player") as Node3D
	if player == null:
		return false
	var candidate_inventory: Dictionary = _inventory.get_save_data().duplicate(true)
	if not (candidate_inventory is Dictionary) or candidate_inventory.is_empty():
		return false
	if not _remove_carried_record(candidate_inventory, owned):
		return false
	var candidate_records: Array[Dictionary] = []
	for record in _records:
		candidate_records.append(_deep_copy_value(record))
	candidate_records.append({"item": owned.duplicate(true), "position": _resolve_drop_position(player.global_position)})
	return _commit_state(candidate_inventory, candidate_records)


func try_pickup(instance_id: String) -> bool:
	if _busy or _level == null or _inventory == null:
		return false
	var player: Node3D = _level.get_node_or_null("Actors/Player") as Node3D
	if player == null:
		return false
	if not bool(player.get("input_enabled")):
		return false
	if bool(player.call("is_attacking")):
		return false
	var drop_index: int = -1
	var drop_position: Vector3 = Vector3.ZERO
	for i in _records.size():
		var record: Dictionary = _records[i]
		var item: Dictionary = record.get("item", {}) as Dictionary
		if str(item.get("instance_id", "")) == instance_id:
			drop_index = i
			drop_position = record.get("position", Vector3.ZERO) as Vector3
			break
	if drop_index < 0:
		return false
	var player_pos: Vector3 = player.global_position
	var planar_distance: float = Vector2(player_pos.x, player_pos.z).distance_to(Vector2(drop_position.x, drop_position.z))
	if planar_distance > float(_level.get("interact_radius")):
		return false
	if not bool(_level.call("_has_line_of_sight", player_pos, drop_position)):
		return false
	var item: Dictionary = _deep_copy_value((_records[drop_index].get("item", {}) as Dictionary))
	var candidate_records: Array[Dictionary] = []
	for i in _records.size():
		if i != drop_index:
			candidate_records.append(_deep_copy_value(_records[i]))
	var cell: Dictionary = _find_free_cell(item)
	if cell.is_empty():
		var hud: Node = _level.get_node_or_null("HUD")
		if hud != null and hud.has_method("show_message"):
			hud.call("show_message", "INV_DROP_ITEM", "DROP_STORAGE_FULL")
		return false
	var candidate_inventory: Dictionary = _inventory.get_save_data().duplicate(true)
	if not _add_carried_record(candidate_inventory, item, cell):
		return false
	return _commit_state(candidate_inventory, candidate_records)


func _resolve_drop_position(player_pos: Vector3) -> Vector3:
	var offset: Vector2 = Vector2(randf_range(-0.45, 0.45), randf_range(-0.45, 0.45))
	var pos: Vector3 = player_pos + Vector3(offset.x, 0.0, offset.y)
	pos.x = clampf(pos.x, -16.5, 16.5)
	pos.z = clampf(pos.z, -16.5, 14.5)
	pos.y = 0.12
	return pos


func _find_free_cell(item: Dictionary) -> Dictionary:
	if int(_inventory.items.size()) >= int(_inventory.max_capacity):
		return {}
	var containers: Array = _inventory.get_storage_containers()
	for container in containers:
		var cid: String = str(container.get("id", ""))
		var capacity: int = int(container.get("capacity", 0))
		for idx in range(capacity):
			var occupied: bool = false
			for entry in _inventory.items:
				var iid: String = str(entry.get('instance_id', ''))
				if str(_inventory.get_item_storage(iid)) == cid and int(_inventory.get_item_cell(iid)) == idx:
					occupied = true
					break
			if not occupied:
				return {"container": cid, "index": idx}
	return {}






func _remove_carried_record(save_data: Dictionary, item: Dictionary) -> bool:
	var iid: String = str(item.get("instance_id", ""))
	var items: Array = save_data.get("items", []) as Array
	var found_index: int = -1
	for i in range(items.size()):
		var candidate: Dictionary = items[i] as Dictionary
		if str(candidate.get("instance_id", "")) == iid:
			if found_index != -1:
				return false
			found_index = i
	if found_index == -1:
		return false
	items.remove_at(found_index)
	var storage: Dictionary = save_data.get("storage", {}) as Dictionary
	var placements: Dictionary = storage.get("placements", {}) as Dictionary
	placements.erase(iid)
	var cells: Dictionary = storage.get("cells", {}) as Dictionary
	cells.erase(iid)
	return true


func _add_carried_record(save_data: Dictionary, item: Dictionary, cell: Dictionary) -> bool:
	if not cell.has("container") or not cell.has("index"):
		return false
	var items: Array = save_data.get("items", []) as Array
	items.append(_deep_copy_value(item))
	var storage: Dictionary = save_data.get("storage", {}) as Dictionary
	var placements: Dictionary = storage.get("placements", {}) as Dictionary
	placements[str(item.get("instance_id", ""))] = str(cell.get("container", ""))
	var cells: Dictionary = storage.get("cells", {}) as Dictionary
	cells[str(item.get("instance_id", ""))] = int(cell.get("index", 0))
	return true




func _is_exact_record(record: Variant, seen_ids: Dictionary) -> bool:
	if not (record is Dictionary):
		return false
	var dict: Dictionary = record
	if dict.size() != 2 or not dict.has("item") or not dict.has("position"):
		return false
	var item: Variant = dict.get("item")
	var position: Variant = dict.get("position")
	if not (item is Dictionary) or not (position is Vector3):
		return false
	var pos: Vector3 = position
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return false
	if pos.x < -17.0 or pos.x > 17.0 or pos.y < -0.5 or pos.y > 5.0 or pos.z < -17.0 or pos.z > 15.0:
		return false
	var item_dict: Dictionary = item
	var validated: Variant = _inventory.call("_validate_save_item", item_dict, seen_ids)
	if not (validated is Dictionary):
		return false
	var validated_dict: Dictionary = validated
	if validated_dict.is_empty():
		return false
	var item_id: String = str(validated_dict.get("id", ""))
	if item_id == "":
		return false
	var rules: Variant = _inventory.call("describe_item_id", item_id)
	if not (rules is Dictionary):
		return false
	var rules_dict: Dictionary = rules
	if bool(rules_dict.get("droppable", false)) == false:
		return false
	if bool(rules_dict.get("quest_locked", false)):
		return false
	var texture: Texture2D = texture_for_item(item_id)
	if texture == null:
		return false
	return true


func _iter_inventory_items(save_data: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var raw_items: Variant = save_data.get("items", [])
	if raw_items is Array:
		for item in raw_items:
			if item is Dictionary:
				items.append(item)
	var equipped: Variant = save_data.get("equipped", {})
	if equipped is Dictionary:
		for slot in equipped:
			var item: Variant = equipped[slot]
			if item is Dictionary:
				items.append(item)
	var worn_storage: Variant = save_data.get("worn_storage", {})
	if worn_storage is Dictionary:
		for kind in worn_storage:
			var item: Variant = worn_storage[kind]
			if item is Dictionary:
				items.append(item)
	return items


func _rebuild_points() -> void:
	for node in get_children():
		remove_child(node)
		node.queue_free()
	_points.clear()
	for record in _records:
		_spawn_point(record, false)


func _spawn_point(record: Dictionary, silent: bool) -> void:
	var item: Dictionary = record.get("item", {}) as Dictionary
	var texture: Texture2D = texture_for_item(str(item.get("id", "")))
	if texture == null:
		return
	var point: Node3D = DROPPED_ITEM_SCRIPT.new()
	point.name = "Drop_" + str(item.get("instance_id", "unknown"))
	point.set("owner_manager", self)
	point.set("item", _deep_copy_value(item))
	point.position = record.get("position", Vector3.ZERO) as Vector3
	add_child(point)
	_points.append(point)
	if not silent:
		pass


func _commit_state(candidate_inventory: Dictionary, candidate_records: Array) -> bool:
	if _busy:
		return false
	if inventory_get_guard("_trade_guard") or inventory_get_guard("_storage_guard") or inventory_get_guard("_wearable_guard"):
		return false
	if inventory_validate(candidate_inventory).is_empty() or not validate_records(candidate_records, candidate_inventory):
		return false
	_busy = true
	var old_signals_blocked: bool = _inventory.is_blocking_signals()
	_inventory.set_block_signals(true)
	var ok: bool = _inventory.load_save_data(candidate_inventory)
	if not ok:
		_inventory.set_block_signals(old_signals_blocked)
		_busy = false
		return false
	if candidate_records.size() > 0:
		_records.assign(candidate_records.duplicate(true))
	else:
		_records.clear()
	_rebuild_points()
	_inventory.set_block_signals(old_signals_blocked)
	var old_wearable_guard: bool = inventory_get_guard("_wearable_guard")
	var old_storage_guard: bool = inventory_get_guard("_storage_guard")
	_inventory.set("_wearable_guard", true)
	_inventory.set("_storage_guard", true)
	if not old_signals_blocked:
		if _inventory.has_signal("inventory_restored"):
			_inventory.emit_signal("inventory_restored")
		if _inventory.has_signal("storage_changed"):
			_inventory.emit_signal("storage_changed")
	changed.emit()
	_inventory.set("_wearable_guard", old_wearable_guard)
	_inventory.set("_storage_guard", old_storage_guard)
	_busy = false
	return true

func inventory_get_guard(guard_name: String) -> bool:
	if _inventory == null:
		return false
	var value: Variant = _inventory.get(guard_name)
	return value is bool and value

func inventory_validate(candidate: Dictionary) -> Dictionary:
	if _inventory == null or not _inventory.has_method("_validate_save_data"):
		return {}
	var result: Dictionary = _inventory._validate_save_data(candidate)
	return result




func _deep_copy_value(value: Variant) -> Variant:
	if value is Dictionary:
		var dict: Dictionary = {}
		for key in (value as Dictionary).keys():
			dict[key] = _deep_copy_value((value as Dictionary)[key])
		return dict
	if value is Array:
		var array: Array = []
		for entry in value:
			array.append(_deep_copy_value(entry))
		return array
	return value
