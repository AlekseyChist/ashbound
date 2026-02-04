## QuestManager - Система квестов ASHBOUND
## Управляет квестами, целями, наградами и журналом
extends Node

signal quest_started(quest_id: String)
signal quest_updated(quest_id: String, objective_id: String)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)
signal objective_completed(quest_id: String, objective_id: String)

# Статусы квестов
enum QuestStatus { AVAILABLE, ACTIVE, COMPLETED, FAILED }

# Типы квестов
enum QuestType { MAIN, FACTION, SIDE, DISCOVERY }

# Активные и завершённые квесты
var active_quests: Dictionary = {}    # quest_id -> quest_data
var completed_quests: Array = []
var failed_quests: Array = []

# Все доступные квесты (загружаются из ресурсов)
var quest_database: Dictionary = {}


func _ready() -> void:
	_load_quest_database()
	print("[ASHBOUND] QuestManager инициализирован")


func _load_quest_database() -> void:
	# Начальные квесты для демонстрации
	# В будущем загружать из .tres ресурсов

	# Пролог - первый квест
	quest_database["prologue_survival"] = {
		"id": "prologue_survival",
		"title": "Выживание",
		"description": "Ты очнулся на окраине разрушенного мира. Найди укрытие и что-нибудь для защиты.",
		"type": QuestType.MAIN,
		"objectives": [
			{"id": "find_weapon", "text": "Найти оружие", "completed": false},
			{"id": "find_shelter", "text": "Найти укрытие", "completed": false},
			{"id": "talk_survivor", "text": "Поговорить с выжившим", "completed": false},
		],
		"rewards": {
			"experience": 100,
			"gold": 0,
		},
		"next_quests": ["choose_path"],
	}

	# Выбор пути
	quest_database["choose_path"] = {
		"id": "choose_path",
		"title": "Перекрёсток судьбы",
		"description": "Выживший рассказал о фракциях, борющихся за власть. Пора решить, к кому примкнуть... или остаться одиночкой.",
		"type": QuestType.MAIN,
		"objectives": [
			{"id": "visit_order", "text": "Посетить Орден Пепельного Пламени", "completed": false, "optional": true},
			{"id": "visit_mages", "text": "Посетить Конклав Чародеев", "completed": false, "optional": true},
			{"id": "visit_council", "text": "Посетить Совет Наместников", "completed": false, "optional": true},
			{"id": "visit_outcasts", "text": "Найти лагерь Изгнанников", "completed": false, "optional": true},
			{"id": "make_choice", "text": "Принять решение", "completed": false},
		],
		"rewards": {
			"experience": 200,
		},
		"next_quests": ["faction_initiation"],
	}

	# Пример фракционного квеста для Ордена
	quest_database["order_trial_fire"] = {
		"id": "order_trial_fire",
		"title": "Испытание Огнём",
		"description": "Чтобы доказать преданность Ордену Пепельного Пламени, ты должен пройти ритуал очищения.",
		"type": QuestType.FACTION,
		"faction": FactionManager.FACTION_ASHEN_ORDER,
		"objectives": [
			{"id": "collect_ashes", "text": "Собрать священный пепел (0/5)", "completed": false, "count": 0, "target": 5},
			{"id": "burn_heretic_books", "text": "Сжечь еретические книги в библиотеке магов", "completed": false},
			{"id": "return_prophet", "text": "Вернуться к Пророку Пепла", "completed": false},
		],
		"rewards": {
			"experience": 300,
			"reputation": {FactionManager.FACTION_ASHEN_ORDER: 20, FactionManager.FACTION_MAGE_CONCLAVE: -15},
		},
	}


# Начать квест
func start_quest(quest_id: String) -> bool:
	if not quest_database.has(quest_id):
		push_error("[ASHBOUND] Квест не найден: %s" % quest_id)
		return false

	if active_quests.has(quest_id):
		return false  # Уже активен

	if quest_id in completed_quests:
		return false  # Уже завершён

	var quest_data = quest_database[quest_id].duplicate(true)
	quest_data["status"] = QuestStatus.ACTIVE
	quest_data["started_day"] = GameManager.current_day

	active_quests[quest_id] = quest_data

	quest_started.emit(quest_id)
	print("[ASHBOUND] Квест начат: %s" % quest_data["title"])
	return true


# Обновить цель квеста
func update_objective(quest_id: String, objective_id: String, completed: bool = true, count_add: int = 0) -> void:
	if not active_quests.has(quest_id):
		return

	var quest = active_quests[quest_id]

	for objective in quest["objectives"]:
		if objective["id"] == objective_id:
			# Для целей со счётчиком
			if objective.has("target"):
				objective["count"] = objective.get("count", 0) + count_add
				if objective["count"] >= objective["target"]:
					objective["completed"] = true
					objective_completed.emit(quest_id, objective_id)
			elif completed:
				objective["completed"] = true
				objective_completed.emit(quest_id, objective_id)

			quest_updated.emit(quest_id, objective_id)
			break

	# Проверяем завершение квеста
	_check_quest_completion(quest_id)


func _check_quest_completion(quest_id: String) -> void:
	var quest = active_quests[quest_id]
	var all_required_complete = true

	for objective in quest["objectives"]:
		if not objective.get("optional", false) and not objective["completed"]:
			all_required_complete = false
			break

	if all_required_complete:
		complete_quest(quest_id)


# Завершить квест
func complete_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return

	var quest = active_quests[quest_id]
	quest["status"] = QuestStatus.COMPLETED

	# Выдаём награды
	var rewards = quest.get("rewards", {})

	if rewards.has("experience"):
		# TODO: PlayerStats.add_experience(rewards["experience"])
		pass

	if rewards.has("gold"):
		# TODO: Inventory.add_gold(rewards["gold"])
		pass

	if rewards.has("reputation"):
		for faction_id in rewards["reputation"]:
			FactionManager.change_reputation(faction_id, rewards["reputation"][faction_id])

	# Переносим в завершённые
	completed_quests.append(quest_id)
	active_quests.erase(quest_id)

	quest_completed.emit(quest_id)
	print("[ASHBOUND] Квест завершён: %s" % quest["title"])

	# Запускаем следующие квесты
	for next_quest in quest.get("next_quests", []):
		start_quest(next_quest)


# Провалить квест
func fail_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return

	var quest = active_quests[quest_id]
	quest["status"] = QuestStatus.FAILED

	failed_quests.append(quest_id)
	active_quests.erase(quest_id)

	quest_failed.emit(quest_id)
	print("[ASHBOUND] Квест провален: %s" % quest["title"])


# Получить данные квеста
func get_quest(quest_id: String) -> Dictionary:
	if active_quests.has(quest_id):
		return active_quests[quest_id]
	return quest_database.get(quest_id, {})


func is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)


func is_quest_completed(quest_id: String) -> bool:
	return quest_id in completed_quests


func is_objective_completed(quest_id: String, objective_id: String) -> bool:
	var quest = get_quest(quest_id)
	for objective in quest.get("objectives", []):
		if objective["id"] == objective_id:
			return objective.get("completed", false)
	return false


# Для UI журнала
func get_active_quests_by_type(type: QuestType) -> Array:
	var result = []
	for quest_id in active_quests:
		if active_quests[quest_id]["type"] == type:
			result.append(active_quests[quest_id])
	return result


func get_all_active_quests() -> Array:
	return active_quests.values()
