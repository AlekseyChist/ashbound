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


func has_access() -> bool:
	if not is_inside_tree():
		return false
	if not available:
		return false
	if storage_id == &"":
		return false
	return true
