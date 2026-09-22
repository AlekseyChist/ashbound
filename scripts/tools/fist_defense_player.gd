extends "res://scripts/courtyard/courtyard_player.gd"
## Игрок для изолированного превью защиты: базовое поведение без изменений,
## только атака блокируется, пока активен блок (guarding) у контроллера.

var defense_controller: Node = null


func request_attack() -> void:
	if defense_controller != null and defense_controller.snapshot().get("guarding", false):
		return
	super.request_attack()
