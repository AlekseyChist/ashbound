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
			# The map is read when it is carried on the hero: main inventory or wallet.
			if (kind == "pocket" or kind == "wallet") and pocket.has_access():
				return item.duplicate(true)
	return {}
