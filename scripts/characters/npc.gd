## NPC - Неигровой персонаж ASHBOUND
## Базовый класс для всех NPC: торговцы, квестодатели, враги
class_name NPC
extends CharacterBase

signal started_talking
signal stopped_talking

@export_group("NPC Данные")
@export var npc_name: String = "Незнакомец"
@export var npc_id: String = ""  # Уникальный ID для сохранений
@export var faction: String = ""  # ID фракции
@export var level: int = 1  # Уровень NPC (влияет на опыт за убийство)

@export_group("Поведение")
@export var is_hostile: bool = false
@export var is_merchant: bool = false
@export var can_talk: bool = true
@export var patrol_points: Array[Node3D] = []

@export_group("Диалог")
@export var dialogue_resource: Resource = null  # DialogueResource

# Состояния ИИ
enum AIState { IDLE, PATROL, CHASE, ATTACK, FLEE, TALK, DEAD }
var current_ai_state: AIState = AIState.IDLE

# Навигация
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# Восприятие
var detection_range: float = 15.0
var attack_range: float = 2.0
var current_target: Node3D = null

# Патруль
var current_patrol_index: int = 0
var patrol_wait_time: float = 3.0
var patrol_timer: float = 0.0

# Диалог
var dialogue_data: Dictionary = {}


func _ready() -> void:
	super._ready()

	# Определяем враждебность по фракции
	if faction != "":
		is_hostile = FactionManager.is_hostile(faction)

	# Загружаем диалог
	if dialogue_resource:
		# TODO: Загрузка из ресурса
		pass


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	super._physics_process(delta)

	match current_ai_state:
		AIState.IDLE:
			_process_idle(delta)
		AIState.PATROL:
			_process_patrol(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.ATTACK:
			_process_attack(delta)
		AIState.FLEE:
			_process_flee(delta)
		AIState.TALK:
			_process_talk(delta)


func _process_idle(delta: float) -> void:
	# Проверяем видимость игрока
	var player = GameManager.player
	if player and is_hostile:
		var distance = global_position.distance_to(player.global_position)
		if distance < detection_range and _can_see_target(player):
			current_target = player
			_change_state(AIState.CHASE)
			return

	# Начинаем патруль если есть точки
	if patrol_points.size() > 0:
		patrol_timer += delta
		if patrol_timer >= patrol_wait_time:
			patrol_timer = 0.0
			_change_state(AIState.PATROL)


func _process_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		_change_state(AIState.IDLE)
		return

	# Проверяем врагов
	var player = GameManager.player
	if player and is_hostile:
		var distance = global_position.distance_to(player.global_position)
		if distance < detection_range and _can_see_target(player):
			current_target = player
			_change_state(AIState.CHASE)
			return

	# Двигаемся к точке патруля
	var target_point = patrol_points[current_patrol_index]
	nav_agent.target_position = target_point.global_position

	if nav_agent.is_navigation_finished():
		current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
		_change_state(AIState.IDLE)
		return

	var next_pos = nav_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	direction.y = 0

	move_toward_direction(direction, delta)
	_look_at_direction(direction)


func _process_chase(delta: float) -> void:
	if not current_target or not is_instance_valid(current_target):
		current_target = null
		_change_state(AIState.IDLE)
		return

	var distance = global_position.distance_to(current_target.global_position)

	# Проверяем дистанцию атаки
	if distance <= attack_range:
		_change_state(AIState.ATTACK)
		return

	# Потеряли цель
	if distance > detection_range * 1.5:
		current_target = null
		_change_state(AIState.IDLE)
		return

	# Преследуем
	nav_agent.target_position = current_target.global_position

	if not nav_agent.is_navigation_finished():
		var next_pos = nav_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		direction.y = 0

		is_running = true
		move_toward_direction(direction, delta)
		_look_at_direction(direction)


func _process_attack(delta: float) -> void:
	if not current_target or not is_instance_valid(current_target):
		current_target = null
		_change_state(AIState.IDLE)
		return

	var distance = global_position.distance_to(current_target.global_position)

	# Цель убежала
	if distance > attack_range * 1.5:
		_change_state(AIState.CHASE)
		return

	# Поворачиваемся к цели
	var direction = (current_target.global_position - global_position).normalized()
	direction.y = 0
	_look_at_direction(direction)

	# Атакуем
	attack()


func _process_flee(delta: float) -> void:
	if not current_target:
		_change_state(AIState.IDLE)
		return

	# Бежим в противоположную сторону
	var flee_direction = (global_position - current_target.global_position).normalized()
	flee_direction.y = 0

	is_running = true
	move_toward_direction(flee_direction, delta)

	# Проверяем дистанцию
	var distance = global_position.distance_to(current_target.global_position)
	if distance > detection_range * 2:
		current_target = null
		_change_state(AIState.IDLE)


func _process_talk(delta: float) -> void:
	# Поворачиваемся к игроку во время разговора
	var player = GameManager.player
	if player:
		var direction = (player.global_position - global_position).normalized()
		direction.y = 0
		_look_at_direction(direction)


func _can_see_target(target: Node3D) -> bool:
	# Простая проверка линии видимости
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.5,
		target.global_position + Vector3.UP * 1.5
	)
	query.exclude = [self]

	var result = space_state.intersect_ray(query)

	if result.is_empty():
		return true

	return result.collider == target


func _look_at_direction(direction: Vector3) -> void:
	if direction.length() > 0.1:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, 0.1)


func _change_state(new_state: AIState) -> void:
	current_ai_state = new_state
	is_running = false


# === ВЗАИМОДЕЙСТВИЕ ===

func can_interact(interactor: Node) -> bool:
	if not is_alive:
		return false

	if is_hostile and FactionManager.is_hostile(faction):
		return false

	return can_talk


func interact(interactor: Node) -> void:
	if not can_interact(interactor):
		return

	_change_state(AIState.TALK)
	started_talking.emit()

	# Начинаем диалог
	if dialogue_data.is_empty():
		# Используем пример диалога для тестового NPC
		if npc_id == "test_survivor":
			dialogue_data = DialogueSystem.create_example_dialogue()
		else:
			dialogue_data = _get_default_dialogue()

	DialogueSystem.start_dialogue(self, dialogue_data)

	# Ждём окончания диалога
	await DialogueSystem.dialogue_ended

	stopped_talking.emit()
	_change_state(AIState.IDLE)


func get_interaction_text() -> String:
	if is_merchant:
		return "Торговать с %s" % npc_name
	else:
		return "Поговорить с %s" % npc_name


func _get_default_dialogue() -> Dictionary:
	# Диалог по умолчанию зависит от фракции
	var greeting = "..."

	match FactionManager.get_status(faction):
		"hostile":
			greeting = "Убирайся, пока цел!"
		"unfriendly":
			greeting = "Чего тебе?"
		"neutral":
			greeting = "Хм?"
		"friendly":
			greeting = "А, это ты. Чем могу помочь?"
		"trusted":
			greeting = "Друг! Рад тебя видеть."

	return {
		"npc_name": npc_name,
		"start_node": "greeting",
		"nodes": {
			"greeting": {
				"speaker": npc_name,
				"text": greeting,
				"choices": [
					{"text": "[Уйти]", "next": "end"}
				]
			},
			"end": {
				"speaker": "",
				"text": "",
			}
		}
	}


# === АТАКА ===

func _perform_attack() -> void:
	if not current_target or not current_target.has_method("take_damage"):
		return

	var damage = base_damage
	current_target.take_damage(damage, self)


# === СМЕРТЬ ===

func _on_death() -> void:
	current_ai_state = AIState.DEAD

	# Даём опыт игроку
	if GameManager.player:
		var exp_reward = 20 + level * 10
		GameManager.player.add_experience(exp_reward)

	# Репутация за убийство члена фракции
	if faction != "":
		FactionManager.change_reputation(faction, -10)

	# Дроп лута
	_drop_loot()

	# Анимация смерти, затем удаление
	# TODO: Анимация
	queue_free()


func _drop_loot() -> void:
	# TODO: Система дропа предметов
	pass


# === ТОРГОВЛЯ ===

func get_merchant_items() -> Array:
	if not is_merchant:
		return []

	# TODO: Загружать из ресурса
	return []
