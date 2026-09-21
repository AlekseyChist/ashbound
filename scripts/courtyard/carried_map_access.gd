extends RefCounted

const ITEM_ID := "courtyard_sketch"


static func find_carried_map(inventory: Node, pocket: Node) -> Dictionary:
	if not is_instance_valid(inventory) or not is_instance_valid(pocket):
		return {}
	if not pocket.is_inside_tree():
		return {}
	if not pocket.has_method("has_access"):
		return {}
	if not inventory.is_storage_configured():
		return {}

	var items: Array = inventory.get_save_data().items
	var containers: Array = inventory.get_storage_containers()

	var worn_backpack: Dictionary = _worn_item(inventory, "backpack")
	var worn_pouch: Dictionary = _worn_item(inventory, "pouch")

	for item in items:
		if not (item is Dictionary):
			continue
		if str(item.get("id", "")) != ITEM_ID:
			continue
		if int(item.get("quantity", 0)) <= 0:
			continue
		var instance_id: String = str(item.get("instance_id", ""))
		if instance_id.is_empty():
			continue

		var storage_id: String = inventory.get_item_storage(instance_id)
		for container in containers:
			if not (container is Dictionary):
				continue
			if str(container.get("id", "")) != storage_id:
				continue
			var kind: String = str(container.get("kind", ""))
			if kind == "pocket":
				if str(container.get("id", "")) == str(pocket.storage_id) and pocket.has_access():
					return item.duplicate(true)
			elif kind == "backpack" or kind == "pouch":
				var worn: Dictionary = worn_backpack if kind == "backpack" else worn_pouch
				if not worn.is_empty() and str(worn.get("instance_id", "")) != "":
					if str(container.get("id", "")) == "worn_storage:" + str(worn.get("instance_id", "")):
						return item.duplicate(true)
	return {}


static func _worn_item(inventory: Node, kind: String) -> Dictionary:
	var worn: Variant = inventory.get_worn_storage(kind)
	if worn is Dictionary and not worn.is_empty():
		return worn
	return {}
