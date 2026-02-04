## CharacterBase - Базовый класс для всех персонажей ASHBOUND
## Наследуется игроком, NPC, врагами
class_name CharacterBase
extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)
signal died
signal damage_taken(amount: int, attacker: Node)

# Экспорт для настройки в редакторе
@export_group("Характеристики")
@export var max_health: int = 100
@export var max_stamina: float = 100.0
@export var stamina_regen: float = 15.0  # В секунду

@export_group("Движение")
@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var crouch_speed: float = 1.5
@export var jump_force: float = 5.0
@export var gravity_multiplier: float = 1.0

@export_group("Бой")
@export var base_damage: int = 10
@export var attack_speed: float = 1.0
@export var defense: int = 0

# Текущие значения
var current_health: int
var current_stamina: float
var is_alive: bool = true

# Состояния
var is_running: bool = false
var is_crouching: bool = false
var is_blocking: bool = false
var is_attacking: bool = false
var can_attack: bool = true

# Физика
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Компоненты (назначаются в _ready дочерних классов)
var animation_player: AnimationPlayer
var mesh_instance: Node3D


func _ready() -> void:
	current_health = max_health
	current_stamina = max_stamina
	_setup_components()


func _setup_components() -> void:
	# Переопределяется в дочерних классах
	pass


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	_apply_gravity(delta)
	_regenerate_stamina(delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta


func _regenerate_stamina(delta: float) -> void:
	if not is_running and not is_attacking:
		current_stamina = minf(current_stamina + stamina_regen * delta, max_stamina)
		stamina_changed.emit(current_stamina, max_stamina)


# === ЗДОРОВЬЕ ===

func take_damage(amount: int, attacker: Node = null) -> void:
	if not is_alive:
		return

	# Применяем защиту
	var actual_damage = maxi(amount - defense, 1)

	# Блокирование снижает урон
	if is_blocking:
		actual_damage = int(actual_damage * 0.3)
		use_stamina(10.0)  # Блок тратит стамину

	current_health -= actual_damage
	health_changed.emit(current_health, max_health)
	damage_taken.emit(actual_damage, attacker)

	if current_health <= 0:
		die()


func heal(amount: int) -> void:
	if not is_alive:
		return

	current_health = mini(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)


func die() -> void:
	is_alive = false
	died.emit()
	_on_death()


func _on_death() -> void:
	# Переопределяется в дочерних классах
	pass


# === СТАМИНА ===

func use_stamina(amount: float) -> bool:
	if current_stamina < amount:
		return false

	current_stamina -= amount
	stamina_changed.emit(current_stamina, max_stamina)
	return true


func has_stamina(amount: float) -> bool:
	return current_stamina >= amount


# === ДВИЖЕНИЕ ===

func get_movement_speed() -> float:
	if is_crouching:
		return crouch_speed
	elif is_running and has_stamina(0.1):
		return run_speed
	else:
		return walk_speed


func move_toward_direction(direction: Vector3, delta: float) -> void:
	var speed = get_movement_speed()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

		# Бег тратит стамину
		if is_running:
			use_stamina(10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()


func jump() -> void:
	if is_on_floor() and use_stamina(15.0):
		velocity.y = jump_force


# === БОЙ ===

func attack() -> void:
	if not can_attack or is_attacking:
		return

	if not use_stamina(20.0):
		return

	is_attacking = true
	can_attack = false
	_perform_attack()

	# Кулдаун атаки
	await get_tree().create_timer(1.0 / attack_speed).timeout
	is_attacking = false
	can_attack = true


func _perform_attack() -> void:
	# Переопределяется в дочерних классах
	pass


func start_blocking() -> void:
	is_blocking = true


func stop_blocking() -> void:
	is_blocking = false


# === УТИЛИТЫ ===

func get_health_percent() -> float:
	return float(current_health) / float(max_health)


func get_stamina_percent() -> float:
	return current_stamina / max_stamina


func is_low_health() -> bool:
	return get_health_percent() < 0.25
