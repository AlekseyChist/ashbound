extends "res://scripts/tools/corner_enemy_sandbox.gd"
## Combat feedback preview. Reuses the corner-enemy sandbox, but swaps in the
## combat-feedback player/session scripts via factory overrides.

func _create_preview_player_script() -> GDScript:
	return preload("res://scripts/combat/combat_feedback_player.gd")

func _create_defense_controller() -> Node:
	return preload("res://scripts/combat/combat_feedback_session.gd").new()

func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("AshBound — Combat feedback")
	print("ASHBOUND_COMBAT_FEEDBACK_READY")
