## Player - Главный герой ASHBOUND (Безымянный бродяга)
## Управление в стиле Gothic: WASD + мышь, боевая система
class_name Player
extends CharacterBase

signal interaction_available(target: Node)
signal interaction_unavailable
signal experience_gained(amount: int)
signal level_up(new_level: int)

@export_group("Камера")
@export var mouse_sensitivity: float = 0.002
@export var camera_distance: float = 3.5
@export var camera_height: float = 1.8
@export var min_pitch: float = -60.0
@export var max_pitch: float = 60.0

@export_group("Взаимодействие")
@export var interaction_range: float = 2.5

# Прогресс персонажа
var level: int = 1
var experience: int = 0
var experience_to_next: int = 100

# Атрибуты (растут с уровнем)
var strength: int = 10      # Урон в ближнем бою
var dexterity: int = 10     # Скорость атаки, уклонение
var intelligence: int = 10  # Сила магии, мана
var endurance: int = 10     # Здоровье, стамина

# Компоненты
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var interaction_ray: RayCast3D = $InteractionRay
@onready var attack_area: Area3D = $AttackArea

# Текущая цель взаимодействия
var current_interaction_target: Node = null

# Режим боя (как в Gothic)
var combat_mode: bool = false


func _ready() -> void:
	super._ready()

	# Регистрируем игрока в GameManager
	GameManager.player = self

	# Захват мыши
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Настраиваем начальные характеристики
	_calculate_derived_stats()

	print("[ASHBOUND] Безымянный пробудился...")


func _calculate_derived_stats() -> void:
	# Производные характеристики от атрибутов
	max_health = 50 + endurance * 5
	max_stamina = 50.0 + float(endurance) * 3.0
	base_damage = 5 + strength
	defense = dexterity / 5

	current_health = max_health
	current_stamina = max_stamina


func _input(event: InputEvent) -> void:
	# Вращение камеры мышью
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative)

	# Переключение режима мыши (Escape)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			GameManager.pause_game()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			GameManager.resume_game()


func _rotate_camera(mouse_delta: Vector2) -> void:
	# Горизонтальный поворот - вращаем персонажа
	rotate_y(-mouse_delta.x * mouse_sensitivity)

	# Вертикальный поворот - только камера
	camera_pivot.rotate_x(-mouse_delta.y * mouse_sensitivity)
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x,
		deg_to_rad(min_pitch),
		deg_to_rad(max_pitch)
	)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	super._physics_process(delta)

	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	_handle_movement(delta)
	_handle_actions()
	_check_interaction()


func _handle_movement(delta: float) -> void:
	# Получаем направление от ввода
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Преобразуем в мировые координаты относительно камеры
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Бег (Shift)
	is_running = Input.is_action_pressed("run") and direction != Vector3.ZERO

	# Присед (Ctrl)
	is_crouching = Input.is_action_pressed("crouch")

	# Прыжок (Space)
	if Input.is_action_just_pressed("jump"):
		jump()

	# Применяем движение
	move_toward_direction(direction, delta)


func _handle_actions() -> void:
	# Атака (ЛКМ)
	if Input.is_action_just_pressed("attack"):
		attack()

	# Блок (ПКМ)
	if Input.is_action_just_pressed("block"):
		start_blocking()
	if Input.is_action_just_released("block"):
		stop_blocking()

	# Взаимодействие (E)
	if Input.is_action_just_pressed("interact"):
		_interact()

	# Инвентарь (I или Tab)
	if Input.is_action_just_pressed("inventory"):
		_toggle_inventory()

	# Журнал квестов (J)
	if Input.is_action_just_pressed("journal"):
		_toggle_journal()


func _check_interaction() -> void:
	if not interaction_ray:
		return

	interaction_ray.force_raycast_update()

	if interaction_ray.is_colliding():
		var collider = interaction_ray.get_collider()

		# Проверяем, можно ли взаимодействовать
		if collider.has_method("can_interact") and collider.can_interact(self):
			if current_interaction_target != collider:
				current_interaction_target = collider
				interaction_available.emit(collider)
		else:
			_clear_interaction_target()
	else:
		_clear_interaction_target()


func _clear_interaction_target() -> void:
	if current_interaction_target != null:
		current_interaction_target = null
		interaction_unavailable.emit()


func _interact() -> void:
	if current_interaction_target and current_interaction_target.has_method("interact"):
		current_interaction_target.interact(self)


func _toggle_inventory() -> void:
	if GameManager.current_state == GameManager.GameState.INVENTORY:
		GameManager.change_state(GameManager.GameState.PLAYING)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		GameManager.change_state(GameManager.GameState.INVENTORY)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _toggle_journal() -> void:
	# TODO: Открыть журнал квестов
	pass


# === АТАКА ===

func _perform_attack() -> void:
	if not attack_area:
		return

	# Получаем всех врагов в зоне атаки
	var targets = attack_area.get_overlapping_bodies()

	for target in targets:
		if target == self:
			continue

		if target.has_method("take_damage"):
			var damage = base_damage

			# Крит при высокой ловкости
			if randf() < dexterity * 0.01:
				damage *= 2

			target.take_damage(damage, self)


# === ПРОГРЕСС ===

func add_experience(amount: int) -> void:
	experience += amount
	experience_gained.emit(amount)

	while experience >= experience_to_next:
		_level_up()


func _level_up() -> void:
	experience -= experience_to_next
	level += 1
	experience_to_next = int(experience_to_next * 1.5)

	# Бонусы за уровень
	strength += 1
	dexterity += 1
	endurance += 1

	_calculate_derived_stats()
	heal(max_health)  # Полное восстановление при левелапе

	level_up.emit(level)
	print("[ASHBOUND] Уровень повышен до %d!" % level)


# === СМЕРТЬ ===

func _on_death() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# TODO: Экран смерти, перезагрузка
	print("[ASHBOUND] Безымянный пал...")
