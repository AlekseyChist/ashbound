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
var _current_anim: StringName = &""

const ATTACK_DURATION := 0.4
const STRIKE_TIME := 0.12
const COOLDOWN_TIME := 0.55
const ATTACK_SPEED_SCALE := 0.25


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if not input_enabled:
		return
	if event.is_action_pressed("interact"):
		request_interaction()
	elif event.is_action_pressed("attack"):
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

	# Мир: X — вправо, Z — вглубь (камера смотрит на север).
	# Input.get_vector отдаёт отрицательный Y для W/вверх, поэтому worldZ = +input_dir.y.
	var world_dir := Vector3(input_dir.x, 0.0, input_dir.y)
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_move = Vector2.ZERO


# --- Анимация спрайта (idle/walk/attack) ---

func _update_animation(_delta: float) -> void:
	var body: AnimatedSprite3D = $Visual/Body
	if body == null or body.sprite_frames == null:
		return

	var new_anim := &"idle"
	var moving := false
	if _attack_active:
		new_anim = &"attack"
	elif velocity.x != 0.0 or velocity.z != 0.0:
		new_anim = &"walk"
		moving = true

	# Переключение только при смене имени анимации
	if new_anim != _current_anim:
		_current_anim = new_anim
		if body.sprite_frames.has_animation(new_anim):
			body.animation = new_anim
			body.play()

	# Частота кадров: walk — walk_pose_fps, иначе 15
	var target_fps := float(walk_pose_fps) if moving else 15.0
	body.speed_scale = target_fps / 15.0

	# Переворот спрайта по знаку X в мировых координатах
	var flip := facing_direction.x < 0.0
	if body.flip_h != flip:
		body.flip_h = flip
