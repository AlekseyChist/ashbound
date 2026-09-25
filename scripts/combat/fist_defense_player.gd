extends "res://scripts/courtyard/courtyard_player.gd"
## Игрок для изолированного превью защиты: базовое поведение без изменений,
## только атака блокируется, пока активен блок (guarding) у контроллера.

var defense_controller: Node = null


func request_attack() -> void:
	if defense_controller != null and defense_controller.snapshot().get("guarding", false):
		return
	super.request_attack()


func _update_visual() -> void:
	if is_attacking():
		super._update_visual()
		return
	var action := &""
	if is_instance_valid(defense_controller) and defense_controller.has_method("get_visual_action"):
		action = defense_controller.get_visual_action()
	if action == &"hit":
		var visual := $Visual as CourtyardCharacterVisual
		if visual != null:
			visual.update_visual(&"hit", facing_direction, walk_pose_fps, run_pose_fps)
		return
	if action == &"guard":
		var hvel := Vector2(velocity.x, velocity.z)
		if absf(hvel.x) < 0.01 and absf(hvel.y) < 0.01:
			var visual := $Visual as CourtyardCharacterVisual
			if visual != null:
				visual.update_visual(&"guard", facing_direction, walk_pose_fps, run_pose_fps)
			return
	super._update_visual()
