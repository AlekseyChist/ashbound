extends "res://scripts/tools/guard_phases_sandbox.gd"
## Изолированное превью combat-dodge: подменяет сессию, игрока и тулбар.


func _create_preview_player_script() -> GDScript:
	return preload("res://scripts/combat/combat_dodge_player.gd")


func _create_defense_controller() -> Node:
	return preload("res://scripts/tools/combat_dodge_session.gd").new()


func _create_defense_toolbar() -> Node:
	return preload("res://scripts/tools/combat_dodge_toolbar.gd").new()


func _create_preview_toolbar() -> CanvasLayer:
	return preload("res://scripts/tools/combat_tools_toolbar.gd").new()


func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("AshBound — Combat Dodge")
	print("ASHBOUND_COMBAT_DODGE_READY")
