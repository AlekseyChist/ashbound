extends "res://scripts/tools/guard_phases_session.gd"
## Сессия combat-dodge: guard-фазы + уклонение игрока.
## Отклоняет новый guard, пока игрок в dodge; отменяет dodge при cancel_trial.


func set_guard(pressed: bool) -> bool:
	# Свежий guard (pressed=true) запрещён во время активного dodge игрока.
	if pressed:
		var player := _dodge_player()
		if player != null and is_instance_valid(player) and player.is_dodging():
			return false
	return super.set_guard(pressed)


func cancel_trial() -> void:
	# Снимаем dodge немедленно, затем базовый reset (stop_input сбрасывает кулдаун).
	var player := _dodge_player()
	if player != null and is_instance_valid(player) and player.has_method("cancel_dodge"):
		player.cancel_dodge()
	super.cancel_trial()


func _dodge_player() -> Node:
	return player
