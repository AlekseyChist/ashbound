extends "res://scripts/tools/combat_feedback_sandbox.gd"
## Изолированное превью раскрашенных (painted) боевых эффектов.
## Переиспользует combat_feedback_sandbox, подменяя только сессию.

func _create_defense_controller() -> Node:
	return preload("res://scripts/tools/painted_combat_session.gd").new()


func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("AshBound — Painted combat")
	print("ASHBOUND_PAINTED_COMBAT_READY")
