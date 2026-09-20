class_name CourtyardPlayer
extends CharacterBody3D
## Игрок первого двора: 2D-спрайт в 3D-пространстве.
## Знает только о своих дочерних узлах, шлёт сигналы на действия.

signal interact_requested()
signal strike_requested()

@export var move_speed: float = 4.2
@export var acceleration: float = 20.0
@export var gravity: float = 22.0
@export var walk_pose_fps: int = 15

var input_enabled: bool = true
var facing_direction: Vector3 = Vector3(0, 0, -1)

# Внутреннее состояние
var _touch_move: Vector2 = Vector2.ZERO
var _attack_active: bool = false
var _attack_time: float = 0.0
var _strike_sent: bool = false
var _cooldown: float = 0.0
var _current_action: StringName = &""
var _current_view: StringName = &"back"

const ATTACK_DURATION := 0.4
const STRIKE_TIME := 0.12
const COOLDOWN_TIME := 0.55
const ATTACK_SPEED_SCALE := 0.25
const VIEW_HYSTERESIS := 0.08


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if not input_enabled:
		return
	if event.is_action_pressed("interact"):
		request_interaction()
	elif event.is_action_pressed("attack"):
		# LMB-атака только при захваченной мыши; эмулированные клики Android игнорируем.
		var is_mouse := event is InputEventMouseButton
		if is_mouse and (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or OS.has_feature("android")):
			return
		request_attack()


func _physics_process(delta: float) -> void:
	# Гравитация накапливается только в воздухе; на полу — нулевая вертикаль.
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	# Ввод движения: клавиатура + тач-вектор (только при включённом вводе)
	var input_dir := Vector2.ZERO
	if input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		input_dir += _touch_move
		input_dir = input_dir.limit_length(1.0)

	# Мир: движение относительно горизонтального базиса текущей камеры.
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
		# Запасной вариант без камеры: X — вправо, Z — вглубь.
		world_dir = Vector3(input_dir.x, 0.0, input_dir.y)

	if world_dir.length_squared() > 0.01:
		facing_direction = world_dir.normalized()

	# Скорость во время атаки снижена
	var speed_scale := 1.0
	if _attack_active:
		speed_scale = ATTACK_SPEED_SCALE

	var target_velocity := world_dir * move_speed * speed_scale
	var accel := acceleration * delta
	if velocity.x != target_velocity.x or velocity.z != target_velocity.z:
		velocity.x = move_toward(velocity.x, target_velocity.x, accel)
		velocity.z = move_toward(velocity.z, target_velocity.z, accel)

	move_and_slide()

	# Таймеры атаки/кулдауна (кулдаун тикает независимо от атаки)
	if _attack_active:
		_attack_time += delta
		if not _strike_sent and _attack_time >= STRIKE_TIME:
			_strike_sent = true
			strike_requested.emit()
		if _attack_time >= ATTACK_DURATION:
			_attack_active = false
	if _cooldown > 0.0:
		_cooldown -= delta

	_update_animation(delta)


func set_move_input(value: Vector2) -> void:
	if not input_enabled:
		return
	_touch_move = value.limit_length(1.0)


func stop_input() -> void:
	_touch_move = Vector2.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	_attack_active = false
	_cooldown = 0.0


func request_interaction() -> void:
	if not input_enabled:
		return
	interact_requested.emit()


func request_attack() -> void:
	if not input_enabled:
		return
	# Не перезапускать и не накладывать атаки
	if _attack_active or _cooldown > 0.0:
		return
	_attack_active = true
	_attack_time = 0.0
	_strike_sent = false
	_cooldown = COOLDOWN_TIME


func get_visual_direction() -> StringName:
	return _current_view


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_move = Vector2.ZERO


# --- Анимация спрайта (idle/walk/attack x front/back/left/right) ---

func _update_animation(_delta: float) -> void:
	var body: AnimatedSprite3D = $Visual/Body
	if body == null or body.sprite_frames == null:
		return

	# Текущее действие (отдельно от имени клипа)
	var new_action := &"idle"
	var moving := false
	if _attack_active:
		new_action = &"attack"
	elif velocity.x != 0.0 or velocity.z != 0.0:
		new_action = &"walk"
		moving = true

	# Текущее направление относительно камеры (с гистерезисом)
	var new_view := _resolve_view()

	var action_changed := new_action != _current_action
	var view_changed := new_view != _current_view

	if action_changed or view_changed:
		# Сохраняем фазу, чтобы смена вида не сбрасывала walk/attack
		var old_frame := body.frame
		var old_progress: float = body.frame_progress
		var was_playing := body.is_playing()
		var old_paused := not was_playing

		_current_action = new_action
		_current_view = new_view
		var clip_name := StringName(new_action + "_" + new_view)
		if not body.sprite_frames.has_animation(clip_name):
			# Запасные алиасы, пока новые клипы импортируются
			if new_view == &"left" or new_view == &"right":
				clip_name = StringName(new_action + "_side")
			if not body.sprite_frames.has_animation(clip_name):
				clip_name = new_action
		body.animation = clip_name

		if action_changed:
			# Нормальная смена действия — старт с первого кадра
			body.frame = 0
			body.frame_progress = 0.0
			body.play()
		else:
			# Только смена вида — сохраняем фазу старого клипа
			var frame_count := body.sprite_frames.get_frame_count(clip_name)
			var clamped_frame: int = clampi(old_frame, 0, maxi(frame_count - 1, 0))
			body.set_frame_and_progress(clamped_frame, old_progress)
			if old_paused:
				body.pause()

	# Частота кадров: walk — walk_pose_fps, иначе 1.0
	var target_scale := float(walk_pose_fps) / 15.0 if moving else 1.0
	body.speed_scale = target_scale

	# Переворот спрайта: только для боковых видов (LEFT — flip_h)
	var flip := _current_view == &"left"
	if body.flip_h != flip:
		body.flip_h = flip

	_apply_sprite_scale(body)


func _resolve_view() -> StringName:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return _current_view

	# Вектор от игрока к камере (проекция на горизонталь)
	var to_camera := cam.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.0001:
		return _current_view
	var view_back := to_camera.normalized()

	var right := cam.global_basis.x
	right.y = 0.0
	right = right.normalized()

	var facing := facing_direction
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return _current_view
	facing = facing.normalized()

	var vertical := facing.dot(view_back)
	var horizontal := facing.dot(right)

	# Гистерезис вокруг диагонали: вертикаль — front/back, горизонталь — left/right
	if absf(vertical) > absf(horizontal) + VIEW_HYSTERESIS:
		return &"front" if vertical > 0.0 else &"back"
	elif absf(horizontal) > absf(vertical) + VIEW_HYSTERESIS:
		return &"right" if horizontal > 0.0 else &"left"
	else:
		return _current_view


func _apply_sprite_scale(body: AnimatedSprite3D) -> void:
	var frames := body.sprite_frames
	if frames == null:
		return

	var key := "pixel_size_side"
	match _current_view:
		&"back":
			key = "pixel_size_back"
		&"front":
			key = "pixel_size_front"

	var pixel_size: float = frames.get_meta(key, 0.006)
	if pixel_size <= 0.0:
		pixel_size = 0.006
	body.pixel_size = pixel_size
	body.position.y = float(frames.get_meta("baseline_offset_pixels", 150.0)) * pixel_size
