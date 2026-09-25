class_name CourtyardPlayer
extends CharacterBody3D
## Игрок первого двора: 2D-спрайт в 3D-пространстве.
## Знает только о своих дочерних узлах, шлёт сигналы на действия.

signal interact_requested()
signal strike_requested()

@export var move_speed: float = 4.2
@export var run_speed: float = 6.4
@export var acceleration: float = 20.0
@export var gravity: float = 22.0
@export var walk_pose_fps: int = 15
@export var run_pose_fps: int = 15

var facing_direction: Vector3 = Vector3(0, 0, -1)

# Внутреннее состояние
var _touch_move: Vector2 = Vector2.ZERO
var _touch_run: bool = false
var _attack_active: bool = false
var _attack_time: float = 0.0
var _strike_sent: bool = false
var _cooldown: float = 0.0
# Отдельный учёт фокуса и паузы приложения: атака разрешена только когда
# оба состояния вернулись (и дерево сцены не в паузе).
var _app_focused: bool = true
var _app_paused: bool = false

const ATTACK_DURATION := 0.4
const STRIKE_TIME := 0.12
const COOLDOWN_TIME := 0.55
const ATTACK_SPEED_SCALE := 0.25


## Ввод игрока (клавиатура + сенсорный HUD). Выключение немедленно отменяет
## активную атаку и очищает ввод движения; кулдаун продолжает тикать.
var input_enabled: bool = true:
	set(value):
		if value == input_enabled:
			return
		input_enabled = value
		if not value:
			_cancel_attack()
			clear_movement_input()


func _unhandled_input(event: InputEvent) -> void:
	# Тач-события принадлежат HUD/камере — игрок их не обрабатывает.
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return
	if event.is_echo():
		return
	if not input_enabled:
		return
	if event.is_action_pressed("interact"):
		request_interaction()
	elif event.is_action_pressed("attack"):
		# На Android атака — только явный HUD-запрос request_attack().
		if OS.has_feature("android"):
			return
		# Эмулированные клики (тачскрин -> мышь) игнорируем на всех платформах.
		var is_mouse := event is InputEventMouseButton
		if is_mouse and event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		# LMB-атака только при захваченной мыши.
		if is_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		request_attack()


func _physics_process(delta: float) -> void:
	# Защита от повторного входа: если сигнал strike_requested вызвал
	# отмену атаки, состояние уже сброшено — не дублируем контакт.
	if _attack_active and not is_attack_allowed():
		_cancel_attack()

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

	# Бег: отдельный сенсорный запрос или удержание run (ПК), только при движении.
	# Во время атаки бег подавляется прежним масштабом скорости.
	var moving := world_dir.length_squared() > 0.01
	var wants_running := input_enabled and not _attack_active and moving \
		and (_touch_run or Input.is_action_pressed("run"))

	# Скорость во время атаки снижена
	var speed_scale := 1.0
	if _attack_active:
		speed_scale = ATTACK_SPEED_SCALE

	var base_speed := run_speed if wants_running else move_speed
	var target_velocity := world_dir * base_speed * speed_scale
	var accel := acceleration * delta
	if velocity.x != target_velocity.x or velocity.z != target_velocity.z:
		velocity.x = move_toward(velocity.x, target_velocity.x, accel)
		velocity.z = move_toward(velocity.z, target_velocity.z, accel)

	move_and_slide()

	# Таймеры атаки/кулдауна (кулдаун тикает независимо от атаки).
	# Контакт не шлём, если ввод заблокирован (отмена могла произойти
	# в этом же кадре до этого блока).
	if _attack_active:
		_attack_time += delta
		if not _strike_sent and _attack_time >= STRIKE_TIME and is_attack_allowed():
			_strike_sent = true
			strike_requested.emit()
		if _attack_time >= ATTACK_DURATION:
			_attack_active = false
	if _cooldown > 0.0:
		_cooldown -= delta

	_update_visual()


func set_move_input(value: Vector2) -> void:
	if not input_enabled:
		return
	_touch_move = value.limit_length(1.0)


## Сенсорный запрос бега (отдельно от клавиатуры; на ПК — удержание run).
## Сброс (false) разрешён даже при выключенном вводе; установка true — нет.
func set_run_input(value: bool) -> void:
	if not input_enabled and value:
		return
	_touch_run = value


## Идёт ли бег в данный момент: актуальный запрос движения (клавиатура + тач),
## реальная горизонтальная скорость, включённый ввод, отсутствие атаки и
## запрос бега. Замедление после отпускания движения бегом не считается.
func is_running() -> bool:
	if not input_enabled or _attack_active:
		return false
	var wants_running := _touch_run or (input_enabled and Input.is_action_pressed("run"))
	if not wants_running:
		return false
	var move_input := Vector2.ZERO
	if input_enabled:
		move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		move_input += _touch_move
		move_input = move_input.limit_length(1.0)
	if move_input.length_squared() <= 0.01:
		return false
	var real_velocity := get_real_velocity()
	return absf(real_velocity.x) > 0.01 or absf(real_velocity.z) > 0.01


## Активна ли атака в данный момент (для внешних систем, напр. инвентаря).
func is_attacking() -> bool:
	return _attack_active


## Очистить только ввод движения, не трогая состояние атаки и кулдаун.
func clear_movement_input() -> void:
	_touch_move = Vector2.ZERO
	_touch_run = false
	velocity.x = 0.0
	velocity.z = 0.0


func stop_input() -> void:
	_touch_move = Vector2.ZERO
	_touch_run = false
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
	# Атака запрещена без фокуса/приложения и при паузе дерева сцены.
	if not is_attack_allowed():
		return
	# Не перезапускать и не накладывать атаки
	if _attack_active or _cooldown > 0.0:
		return
	_attack_active = true
	_attack_time = 0.0
	_strike_sent = false
	_cooldown = COOLDOWN_TIME


## Разрешена ли атака прямо сейчас: включён ввод, есть фокус и приложение
## не в паузе, узел внутри дерева и способен обрабатываться (учёт
## process_mode и предков), дерево сцены (и предки) не на паузе.
func is_attack_allowed() -> bool:
	if not input_enabled or not _app_focused or _app_paused:
		return false
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null or tree.is_paused():
		return false
	return can_process()


## Немедленная отмена активной атаки (без сброса кулдауна): состояние
## атаки и ввод движения очищаются, визуальная атака снимается.
func _cancel_attack() -> void:
	if not _attack_active:
		return
	_attack_active = false
	_attack_time = 0.0
	_strike_sent = false
	clear_movement_input()
	if is_inside_tree() and is_node_ready():
		var visual := $Visual as CourtyardCharacterVisual
		if visual != null:
			visual.update_visual(&"idle", facing_direction, walk_pose_fps, run_pose_fps)


func get_visual_direction() -> StringName:
	var visual := $Visual as CourtyardCharacterVisual
	if visual == null:
		return &"back"
	return visual.get_visual_direction()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_app_focused = false
			# Потеря фокуса отменяет атаку и очищает ввод движения;
			# клавиатурный run сам перестаёт нажиматься.
			_cancel_attack()
			clear_movement_input()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_app_focused = true
		NOTIFICATION_APPLICATION_PAUSED:
			_app_paused = true
			_cancel_attack()
			clear_movement_input()
		NOTIFICATION_APPLICATION_RESUMED:
			_app_paused = false
		NOTIFICATION_PAUSED:
			# Реальная пауза дерева сцены: немедленная отмена без отложенного
			# контакта; при возврате атака не возрождается.
			_cancel_attack()
			clear_movement_input()


# --- Визуальная презентация (idle/walk/attack x front/back/left/right) ---

## Optional fight that asks for the whole-character poses (`get_visual_action()` -> &"guard" / &"hit"),
## as the courtyard defense preview does; the world combat sets it. Empty keeps the plain actions.
var visual_action_source: Object = null


func _update_visual() -> void:
	var visual := $Visual as CourtyardCharacterVisual
	if visual == null:
		return
	if not _attack_active and is_instance_valid(visual_action_source):
		var pose: StringName = visual_action_source.get_visual_action()
		# The hit pose shows during the recoil; the guard pose while standing (walking keeps the walk).
		if pose == &"hit" or (pose == &"guard" and velocity.x == 0.0 and velocity.z == 0.0):
			visual.update_visual(pose, facing_direction, walk_pose_fps, run_pose_fps)
			return

	# Текущее действие (отдельно от имени клипа).
	# Бег — только при фактическом горизонтальном движении (get_real_velocity
	# учитывает упор в стену; на первом кадре он равен нулю, что корректно).
	var new_action := &"idle"
	if _attack_active:
		new_action = &"attack"
	elif is_running():
		new_action = &"run"
	elif velocity.x != 0.0 or velocity.z != 0.0:
		new_action = &"walk"

	visual.update_visual(new_action, facing_direction, walk_pose_fps, run_pose_fps)
