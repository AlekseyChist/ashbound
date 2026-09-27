extends "res://scripts/courtyard/courtyard_level.gd"

## Инструментальная обёртка над courtyard_level для проверки угловых врагов.
## Не трогает основной campaign-код: переопределяются только нужные хуки.

var enemy_session: Node = null


func _eligible_attack_target() -> Node3D:
	if is_instance_valid(enemy_session):
		return enemy_session.eligible_target()
	return null


func _on_strike_requested() -> void:
	# super НЕ вызывается: campaign dummy / quest hits здесь не используются.
	if is_instance_valid(enemy_session):
		enemy_session.hero_strike()


func _set_focus_prompt() -> void:
	var text: String = ""
	if _current_attack_target != null:
		var kind := String(_current_attack_target.get("kind"))
		var name_key := "ENEMY_GUARD" if kind == "guard" else "ENEMY_WOLF"
		var target_name: String = Localization.text(name_key)
		var is_touch: bool = OS.has_feature("android") or _hud.force_touch_controls
		var focus_key := "COURTYARD_FOCUS_ATTACK_TOUCH" if is_touch else "COURTYARD_FOCUS_ATTACK_DESKTOP"
		text = Localization.text(focus_key, {"name": target_name})
	_hud.set_prompt(text)
	_last_focus_prompt = text
