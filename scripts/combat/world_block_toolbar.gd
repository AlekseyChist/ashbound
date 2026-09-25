extends "res://scripts/combat/corner_enemy_toolbar.gd"
## COMBAT-WORLD-01B: only the Block button of the sandbox toolbar (same pointer ownership,
## hold = block, the cue lights up in the perfect window). No reset button, no sandbox hints.

func _build_ui() -> void:
	super._build_ui()
	_reset_btn.hide()
	_reset_btn.get_parent().hide()
	if _hint_panel != null:
		_hint_panel.hide()
	if _hint_label != null:
		_hint_label.hide()


func _inside_own_control(pos: Vector2) -> bool:
	return _inside_button(_guard_btn, pos)


func _request_reset() -> void:
	pass


func _update_hint() -> void:
	pass
