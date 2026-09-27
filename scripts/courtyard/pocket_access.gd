extends Node
## CourtyardPocketAccess — компонент доступа к карману стартового гардероба.
## Принадлежит фиксированному стартовому наряду; не содержит копий предметов
## и не генерирует лут по умолчанию.

signal availability_changed()

@export var storage_id: StringName = &"traveler_clothing_pocket":
	set(value):
		if storage_id == value:
			return
		storage_id = value
		availability_changed.emit()

@export var available: bool = true:
	set(value):
		if available == value:
			return
		available = value
		availability_changed.emit()

## Main inventory size at the start (D-057, owner's choice 25 Sep: 12 cells).
## Growth with level and strength comes later (INV-03B).
@export_range(1, 1000000) var slot_capacity: int = 12

## Wallet section (D-057, owner's choice 25 Sep: 4 cells). Protection from arrest
## and looting is planned with JUSTICE-01/LOOT-01; for now it is a separate section.
@export var wallet_id: StringName = &"traveler_wallet"
@export_range(1, 1000000) var wallet_capacity: int = 4


func _ready() -> void:
	_configure_pocket_if_needed()


func has_access() -> bool:
	if not is_inside_tree():
		return false
	if not available:
		return false
	if storage_id == &"":
		return false
	return _inventory_has_pocket()


func _configure_pocket_if_needed() -> void:
	if Inventory.is_storage_configured():
		return
	if not available:
		return
	var id := str(storage_id)
	if id.is_empty():
		return
	var definitions: Array = [
		{"id": id, "kind": "pocket", "capacity": slot_capacity},
	]
	if wallet_id != &"" and str(wallet_id) != id:
		definitions.append({"id": str(wallet_id), "kind": "wallet", "capacity": wallet_capacity})
	Inventory.configure_storage(definitions)


func _inventory_has_pocket() -> bool:
	var containers: Variant = Inventory.get_storage_containers()
	if typeof(containers) != TYPE_ARRAY:
		return false
	for entry in containers:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var container: Dictionary = entry
		if str(container.get("id", "")) == str(storage_id) \
				and str(container.get("kind", "")) == "pocket":
			return true
	return false
