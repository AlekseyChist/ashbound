extends "res://scripts/combat/fist_defense_toolbar.gd"


func _build_ui() -> void:
	super._build_ui()
	# Автоматические атаки врагов — кнопка замаха не нужна.
	_swing_btn.hide()
	# Ряд теперь содержит только кнопку сброса: центрируем её.
	var row := _reset_btn.get_parent() as Control
	row.offset_left = -130
	row.offset_right = 130


func _inside_own_control(pos: Vector2) -> bool:
	# Скрытая кнопка замаха не должна перехватывать невидимый прямоугольник.
	if _inside_button(_reset_btn, pos):
		return true
	if _inside_button(_guard_btn, pos):
		return true
	return false


func _inside_button(control: Control, global_pos: Vector2) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	if not control.is_visible_in_tree():
		return false
	var rect := (control as Control).get_global_rect()
	return rect.has_point(global_pos)


func _request_swing() -> void:
	# F5 не вызывает ручной атаки врага.
	pass


func _update_hint() -> void:
	if _hint_label == null:
		return
	var is_touch := OS.has_feature("android")
	var base_key := "ENEMY_HINT_TOUCH" if is_touch else "ENEMY_HINT_PC"
	var base := Localization.text(base_key)
	var level_key := "DEFENSE_NOVICE_HINT" if _is_novice() else "DEFENSE_TRAINED_HINT"
	_hint_label.text = base + "\n" + Localization.text(level_key)
