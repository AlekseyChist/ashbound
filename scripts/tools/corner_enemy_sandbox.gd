extends "res://scripts/tools/fist_technique_sandbox.gd"
## Corner-enemies combat probe. Reuses the fist sandbox scene, but swaps in
## corner-enemy level/session/toolbar scripts via factory overrides.

func _create_level() -> Node:
	var node: Node = preload("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	node.set_script(preload("res://scripts/tools/corner_enemy_level.gd"))
	return node

func _create_preview_toolbar() -> CanvasLayer:
	return preload("res://scripts/tools/corner_enemy_preview_toolbar.gd").new()

func _create_defense_controller() -> Node:
	return preload("res://scripts/combat/corner_enemy_session.gd").new()

func _create_defense_toolbar() -> Node:
	return preload("res://scripts/combat/corner_enemy_toolbar.gd").new()

func _ready() -> void:
	super._ready()
	if level == null or defense == null:
		return
	level.enemy_session = defense
	var dummy: Node = level.get_node_or_null("Environment/Props/Dummy")
	if dummy != null:
		dummy.get_parent().remove_child(dummy)
		dummy.queue_free()
	set_technique("trained")
	defense.reset_trial()
	DisplayServer.window_set_title("AshBound — Corner enemies")
	print("ASHBOUND_CORNER_ENEMIES_READY")
