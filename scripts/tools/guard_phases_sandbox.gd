extends "res://scripts/tools/painted_combat_sandbox.gd"
## Изолированное превью фаз атак guard-актёра.
## Переиспользует painted_combat_sandbox, подменяя только сессию.

func _create_defense_controller() -> Node:
	return preload("res://scripts/tools/guard_phases_session.gd").new()


func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("AshBound — Guard attack phases")
	print("ASHBOUND_GUARD_PHASES_READY")
