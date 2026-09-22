extends "res://scripts/tools/combat_feedback_player.gd"
## Игрок изолированного превью уворота: базовое поведение (движение, атака,
## ввод, hitstop) полностью унаследовано; добавлен только физический короткий
## уворот без неуязвимости.

const DODGE_DURATION := 0.20
const DODGE_DISTANCE := 1.35
const DODGE_COOLDOWN := 0.60

var _dodge_active: bool = false
var _dodge_direction: Vector3 = Vector3.ZERO
var _dodge_elapsed: float = 0.0
var _dodge_cooldown: float = 0.0


func request_dodge() -> bool:
	if not input_enabled:
		return false
	if not is_attack_allowed():
		return false
	if not is_on_floor():
		return false
	if _dodge_active:
		return false
	if _dodge_cooldown > 0.0:
		return false
	if _attack_active or _cooldown > 0.0:
		return false
	if feedback_stop_remaining() > 0.0:
		return false
	if defense_controller != null and is_instance_valid(defense_controller):
		var snapshot: Dictionary = defense_controller.snapshot()
		if snapshot.get("guarding", false) or defense_controller.get_visual_action() == &"hit":
			return false

	var dir := _dodge_input_direction()
	if not dir.is_finite() or dir.length_squared() <= 0.01:
		return false
	dir = dir.normalized()

	velocity.x = 0.0
	velocity.z = 0.0
	_dodge_active = true
	_dodge_direction = dir
	_dodge_elapsed = 0.0
	_dodge_cooldown = DODGE_COOLDOWN
	print("ASHBOUND_DODGE_STARTED ", dir)
	return true


func is_dodging() -> bool:
	return _dodge_active


func dodge_cooldown_remaining() -> float:
	return _dodge_cooldown


func cancel_dodge() -> void:
	if not _dodge_active:
		return
	_dodge_active = false
	_dodge_elapsed = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


func is_running() -> bool:
	if _dodge_active:
		return false
	return super.is_running()


func request_attack() -> void:
	if _dodge_active:
		return
	super.request_attack()


func request_interaction() -> void:
	if _dodge_active:
		return
	super.request_interaction()


func begin_feedback_stop(seconds: float, action: StringName) -> void:
	if is_finite(seconds) and seconds > 0.0 and _dodge_active:
		cancel_dodge()
	super.begin_feedback_stop(seconds, action)


func clear_movement_input() -> void:
	if _dodge_active:
		cancel_dodge()
	super.clear_movement_input()


func stop_input() -> void:
	if _dodge_active:
		cancel_dodge()
	super.stop_input()
	_dodge_cooldown = 0.0


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var stop_remaining := feedback_stop_remaining()
	var unfrozen: float = maxf(0.0, delta - minf(stop_remaining, delta))
	if _dodge_cooldown > 0.0 and unfrozen > 0.0:
		_dodge_cooldown = maxf(0.0, _dodge_cooldown - unfrozen)
	if not is_attack_allowed():
		cancel_dodge()
		super._physics_process(delta)
		return
	if _dodge_active:
		if stop_remaining >= delta:
			_update_visual()
			return
		if unfrozen > 0.0:
			_step_dodge(unfrozen)
		_update_visual()
		return
	super._physics_process(delta)


func _step_dodge(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var elapsed_before := _dodge_elapsed
	_dodge_elapsed = minf(_dodge_elapsed + delta, DODGE_DURATION)
	var ease_before: float = 1.0 - pow(1.0 - clampf(elapsed_before / DODGE_DURATION, 0.0, 1.0), 2.0)
	var ease_after: float = 1.0 - pow(1.0 - clampf(_dodge_elapsed / DODGE_DURATION, 0.0, 1.0), 2.0)
	var step: float = DODGE_DISTANCE * (ease_after - ease_before)

	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y -= gravity * delta

	var horizontal := Vector3(0.0, 0.0, 0.0)
	horizontal.x = _dodge_direction.x * step
	horizontal.z = _dodge_direction.z * step
	if horizontal.length_squared() > 0.0:
		var hit := move_and_collide(horizontal)
		if hit != null:
			_dodge_active = false

	var vertical := Vector3(0.0, velocity.y * delta, 0.0)
	if vertical.length_squared() > 0.0:
		var vhit := move_and_collide(vertical)
		if vhit != null and vhit.get_normal().y > 0.5:
			velocity.y = 0.0

	if _dodge_elapsed >= DODGE_DURATION - 1e-8:
		_dodge_active = false


func _dodge_input_direction() -> Vector3:
	var input_dir := Vector2.ZERO
	if input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		input_dir += _touch_move
		input_dir = input_dir.limit_length(1.0)

	var world_dir := Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var right := cam.global_basis.x
		right.y = 0.0
		right = right.normalized()
		var back := cam.global_basis.z
		back.y = 0.0
		back = back.normalized()
		world_dir = right * input_dir.x + back * input_dir.y
	else:
		world_dir = Vector3(input_dir.x, 0.0, input_dir.y)

	if not world_dir.is_finite():
		return Vector3.ZERO
	if world_dir.length_squared() <= 0.01:
		var facing := facing_direction
		facing.y = 0.0
		if not facing.is_finite() or facing.length_squared() <= 0.01:
			return Vector3.ZERO
		world_dir = -facing.normalized()
	return world_dir


func _update_visual() -> void:
	if _dodge_active:
		var visual := $Visual as CourtyardCharacterVisual
		if visual != null:
			visual.update_visual(&"walk", facing_direction, walk_pose_fps, run_pose_fps)
		return
	super._update_visual()
