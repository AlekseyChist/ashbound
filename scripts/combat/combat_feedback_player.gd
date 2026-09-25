extends "res://scripts/combat/fist_defense_player.gd"
## Игрок изолированного превью боевой обратной связи: базовое поведение
## (движение, атака, ввод) полностью унаследовано; добавлен только локальный
## hitstop-час, замораживающий движение/атаку/кулдаун игрока на короткое время.

const STOP_ATTACK_FRAME := 1
const STOP_HIT_FRAME := 0

var _feedback_stop_remaining: float = 0.0
var _feedback_stop_action: StringName = &""
var _stop_body_paused: bool = false


func begin_feedback_stop(seconds: float, action: StringName) -> void:
	if not is_finite(seconds) or seconds < 0.0:
		return
	_feedback_stop_remaining = maxf(_feedback_stop_remaining, seconds)
	_feedback_stop_action = action
	_update_visual()


func clear_feedback_stop() -> void:
	_feedback_stop_remaining = 0.0
	_feedback_stop_action = &""
	_resume_body_after_stop()
	if is_inside_tree():
		super._update_visual()


func feedback_stop_remaining() -> float:
	return _feedback_stop_remaining


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	if not is_attack_allowed():
		clear_feedback_stop()
		super._physics_process(delta)
		return
	if _feedback_stop_remaining > 0.0:
		var frozen: float = minf(_feedback_stop_remaining, delta)
		_feedback_stop_remaining -= frozen
		if _feedback_stop_remaining > 0.0:
			_update_visual()
		else:
			_resume_body_after_stop()
			super._update_visual()
		var leftover: float = delta - frozen
		if leftover > 0.0:
			super._physics_process(leftover)
		return
	super._physics_process(delta)


func _update_visual() -> void:
	if _feedback_stop_remaining <= 0.0:
		super._update_visual()
		return
	var visual := $Visual as CourtyardCharacterVisual
	if visual == null:
		return
	var action := _feedback_stop_action
	if action == &"":
		action = &"idle"
	visual.update_visual(action, facing_direction, walk_pose_fps, run_pose_fps)
	var body := visual.get_node_or_null("Body") as AnimatedSprite3D
	if body != null:
		var frame_count: int = body.sprite_frames.get_frame_count(body.animation)
		var frame: int = STOP_ATTACK_FRAME if action == &"attack" else STOP_HIT_FRAME
		body.set_frame_and_progress(clampi(frame, 0, maxi(frame_count - 1, 0)), 0.0)
		body.pause()
		_stop_body_paused = true


func _resume_body_after_stop() -> void:
	if not _stop_body_paused:
		return
	_stop_body_paused = false
	var visual := $Visual as CourtyardCharacterVisual
	if visual == null:
		return
	var body := visual.get_node_or_null("Body") as AnimatedSprite3D
	if body != null:
		body.play()
