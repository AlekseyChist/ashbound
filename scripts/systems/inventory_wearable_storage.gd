# inventory_wearable_storage.gd
# Self-contained helper for wearable storage (backpack / pouch) equipment.
# Host Inventory autoload is passed as parameter `inv: Node` to all static funcs.

extends RefCounted

const InventoryStorageLayoutScript = preload("res://scripts/systems/inventory_storage_layout.gd")


static func kind_for_id(id: String) -> String:
	if id == "traveler_backpack":
		return "backpack"
	elif id == "belt_pouch":
		return "pouch"
	return ""


static func container_id(item: Dictionary) -> String:
	var iid: Variant = item.get("instance_id", "")
	if typeof(iid) == TYPE_STRING and (iid as String) != "":
		return "worn_storage:" + (iid as String)
	return ""


# Build the full definition list: current defs minus worn-prefixed ids,
# plus one entry per present worn container with trusted kind/capacity.
static func definitions(base: Array, worn: Dictionary) -> Array:
	var out: Array = []
	for i in base.size():
		var d: Variant = base[i]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var id: String = (d as Dictionary).get("id", "") as String
		if id.begins_with("worn_storage:"):
			continue
		out.append(d)
	for slot in worn.keys():
		var entry: Variant = worn[slot]
		if entry == null:
			continue
		var kind: String = slot as String
		var cap: int = 8 if kind == "backpack" else 2
		var iid: Variant = (entry as Dictionary).get("instance_id", "")
		out.append({
			"id": "worn_storage:" + str(iid),
			"kind": kind,
			"capacity": cap,
		})
	return out


# Validate a single saved worn entry. Returns {} on invalid.
static func _validate_worn_entry(inv: Node, entry: Variant, seen: Dictionary) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = entry as Dictionary
	var iid: Variant = d.get("instance_id", "")
	if typeof(iid) != TYPE_STRING or (iid as String) == "":
		return {}
	if seen.has(iid):
		return {}
	var result: Dictionary = inv._validate_save_item(entry, seen)
	if result.is_empty():
		return {}
	if kind_for_id(result.id) == "":
		return {}
	if result.get("type", -1) != 4: # MISC
		return {}
	if result.get("quantity", -1) != 1:
		return {}
	if result.get("stackable", true):
		return {}
	seen[iid] = true
	return result


# Parse raw saved worn_storage. Returns null on invalid, else {"backpack":..., "pouch":...}.
static func parse_saved(inv: Node, raw: Variant, seen: Dictionary) -> Variant:
	if raw == null:
		return {"backpack": null, "pouch": null}
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw as Dictionary
	if d.size() != 2 or not d.has("backpack") or not d.has("pouch"):
		return null
	var out: Dictionary = {}
	for slot in ["backpack", "pouch"]:
		var v: Variant = d[slot]
		if v == null:
			out[slot] = null
			continue
		var entry: Dictionary = _validate_worn_entry(inv, v, seen)
		if entry.is_empty():
			return null
		if kind_for_id(entry.id) != slot:
			return null
		out[slot] = entry
	return out


# Build a candidate layout. Returns null on failure.
static func plan_layout(inv: Node, new_items: Array, new_worn: Dictionary, preserve: bool = true) -> RefCounted:
	var current: Variant = inv.get("_storage_layout")
	if current == null or not (current is RefCounted):
		return null
	var base: Array = current.get_containers()
	var new_defs: Array = definitions(base, new_worn)
	var candidate: RefCounted = InventoryStorageLayoutScript.new()
	if preserve:
		if not candidate.configure(base, inv.get("items")):
			return null
		if not candidate.load_placements(current.get_save_data(), inv.get("items")):
			return null
		if not candidate.configure(new_defs, new_items):
			return null
	else:
		if not candidate.configure(new_defs, new_items):
			return null
	var cap: int = candidate.get_capacity()
	if new_items.size() > mini(int(inv.get("max_capacity")), int(cap)):
		return null
	return candidate


# Equip a carried backpack/pouch into its worn slot.
static func equip(inv: Node, handle: Dictionary) -> bool:
	if inv.get("_wearable_guard") or inv.get("_trade_guard") or inv.get("_storage_guard"):
		return false
	var current_layout: Variant = inv.get("_storage_layout")
	if current_layout == null or not (current_layout is RefCounted):
		return false
	if typeof(handle) != TYPE_DICTIONARY:
		return false
	var items: Array = inv.get("items") as Array
	var worn: Dictionary = inv.get("worn_storage") as Dictionary
	var iid: Variant = handle.get("instance_id", "")
	if typeof(iid) != TYPE_STRING or (iid as String) == "":
		return false
	# Scan all carried items; reject duplicate matches.
	var found_idx: int = -1
	for i in items.size():
		var it: Dictionary = items[i] as Dictionary
		if it.get("instance_id", "") == iid:
			if found_idx >= 0:
				return false
			found_idx = i
	if found_idx < 0:
		return false
	var item: Dictionary = items[found_idx] as Dictionary
	var kind: String = kind_for_id(item.get("id", "") as String)
	if kind == "":
		return false
	if item.get("type", -1) != 4 or item.get("quantity", -1) != 1 or item.get("stackable", true):
		return false
	var old_worn: Variant = worn.get(kind, null)
	if old_worn != null and typeof(old_worn) != TYPE_DICTIONARY:
		return false
	# Refuse if the old worn container still holds items.
	if old_worn != null:
		var old_iid: String = (old_worn as Dictionary).get("instance_id", "") as String
		var old_cid: String = "worn_storage:" + old_iid
		var containers: Array = inv.get_storage_containers()
		for i in containers.size():
			var c: Dictionary = containers[i] as Dictionary
			if c.get("id", "") == old_cid and (c.get("used", 0) as int) > 0:
				return false
	# Build next state.
	var next_items: Array = []
	for i in items.size():
		if i != found_idx:
			next_items.append(items[i])
	if old_worn != null:
		next_items.append(old_worn)
	var next_worn: Dictionary = {}
	for k in worn.keys():
		next_worn[k] = worn[k]
	next_worn[kind] = item
	var candidate: RefCounted = plan_layout(inv, next_items, next_worn, true)
	if candidate == null:
		return false
	# Commit.
	inv.set("_wearable_guard", true)
	inv.set("items", next_items)
	inv.set("worn_storage", next_worn)
	inv.set("_storage_layout", candidate)
	inv.emit_signal("storage_changed")
	if old_worn != null:
		inv.emit_signal("item_unequipped", kind)
	inv.emit_signal("item_equipped", item, kind)
	inv.set("_wearable_guard", false)
	return true


# Unequip a worn container back into another existing container.
static func unequip_equipment(inv: Node, slot: String, dest: String) -> bool:
	if slot != "weapon" and slot != "armor":
		return false
	if inv.get("_wearable_guard") or inv.get("_trade_guard") or inv.get("_storage_guard"):
		return false
	var layout = inv.get("_storage_layout")
	if layout == null:
		return false
	var equipped = inv.get("equipped")
	if not (equipped is Dictionary):
		return false
	var item = equipped.get(slot)
	if not (item is Dictionary):
		return false
	var containers = inv.get_storage_containers()
	var found := false
	for c in containers:
		if c.get("id") == dest:
			found = true
			if int(c.get("used", 0)) >= int(c.get("capacity", 0)):
				return false
			break
	if not found:
		return false
	var next_items: Array = inv.items.duplicate()
	next_items.append(item)
	var next_equipped: Dictionary = equipped.duplicate(true)
	next_equipped[slot] = null
	var candidate = plan_layout(inv, next_items, inv.worn_storage, true)
	if candidate == null:
		return false
	if not candidate.move(item.get("instance_id"), dest, next_items):
		return false
	inv._wearable_guard = true
	inv.items = next_items
	inv.equipped = next_equipped
	inv._storage_layout = candidate
	inv._apply_equipment_stats()
	inv.emit_signal("storage_changed")
	inv.emit_signal("item_unequipped", slot)
	inv._wearable_guard = false
	return true

static func unequip(inv: Node, kind: String, destination_id: String) -> bool:
	if inv.get("_wearable_guard") or inv.get("_trade_guard") or inv.get("_storage_guard"):
		return false
	var current_layout: Variant = inv.get("_storage_layout")
	if current_layout == null or not (current_layout is RefCounted):
		return false
	if kind != "backpack" and kind != "pouch":
		return false
	var worn: Dictionary = inv.get("worn_storage") as Dictionary
	var entry: Variant = worn.get(kind, null)
	if entry == null or typeof(entry) != TYPE_DICTIONARY:
		return false
	var iid: String = (entry as Dictionary).get("instance_id", "") as String
	var cid: String = "worn_storage:" + iid
	# Inspect containers: own must be empty, destination must exist, differ and have a free slot.
	var containers: Array = inv.get_storage_containers()
	var own_used: int = -1
	var dest_found: bool = false
	for i in containers.size():
		var c: Dictionary = containers[i] as Dictionary
		if c.get("id", "") == cid:
			own_used = c.get("used", 0) as int
		elif c.get("id", "") == destination_id:
			dest_found = true
			if (c.get("used", 0) as int) >= (c.get("capacity", 0) as int):
				return false
	if own_used != 0:
		return false
	if not dest_found:
		return false
	var items: Array = inv.get("items") as Array
	var next_items: Array = []
	for i in items.size():
		next_items.append(items[i])
	next_items.append(entry)
	var next_worn: Dictionary = {}
	for k in worn.keys():
		next_worn[k] = worn[k]
	next_worn[kind] = null
	var candidate: RefCounted = plan_layout(inv, next_items, next_worn, true)
	if candidate == null:
		return false
	if not candidate.move(iid, destination_id, next_items):
		return false
	inv.set("_wearable_guard", true)
	inv.set("items", next_items)
	inv.set("worn_storage", next_worn)
	inv.set("_storage_layout", candidate)
	inv.emit_signal("storage_changed")
	inv.emit_signal("item_unequipped", kind)
	inv.set("_wearable_guard", false)
	return true
