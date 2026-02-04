## FactionManager - Система фракций ASHBOUND
## Управляет репутацией, отношениями между фракциями и реакцией NPC
extends Node

signal reputation_changed(faction_id: String, old_value: int, new_value: int)
signal faction_status_changed(faction_id: String, new_status: String)
signal player_joined_faction(faction_id: String)
signal player_left_faction(faction_id: String)

# Идентификаторы фракций
const FACTION_ASHEN_ORDER = "ashen_order"      # Орден Пепельного Пламени
const FACTION_MAGE_CONCLAVE = "mage_conclave"  # Конклав Чародеев
const FACTION_COUNCIL = "council"              # Совет Наместников
const FACTION_OUTCASTS = "outcasts"            # Изгнанники
const FACTION_ANCIENT = "ancient"              # Древняя Раса (скрытая)

# Пороги репутации
const REP_HOSTILE = -50      # Атакуют при виде
const REP_UNFRIENDLY = -25   # Не разговаривают, могут напасть
const REP_NEUTRAL = 0        # Нейтральны
const REP_FRIENDLY = 25      # Доброжелательны, дают квесты
const REP_TRUSTED = 50       # Доверяют, доступ к секретам
const REP_MEMBER = 75        # Можно вступить в фракцию
const REP_CHAMPION = 100     # Герой фракции

# Данные о фракциях
var factions: Dictionary = {}

# Репутация игрока с каждой фракцией (-100 до 100)
var player_reputation: Dictionary = {}

# Текущая фракция игрока (можно быть только в одной)
var player_faction: String = ""


func _ready() -> void:
	_init_factions()
	print("[ASHBOUND] FactionManager инициализирован")


func _init_factions() -> void:
	# Орден Пепельного Пламени
	factions[FACTION_ASHEN_ORDER] = {
		"name": "Орден Пепельного Пламени",
		"description": "Фанатичный культ, верящий в очищение огнём",
		"leader": "Пророк Пепла",
		"location": "Руины древнего собора",
		"color": Color(0.9, 0.3, 0.1),  # Огненно-оранжевый
		"enemies": [FACTION_MAGE_CONCLAVE],
		"rivals": [FACTION_COUNCIL],
		"ideology": "theocracy",
	}

	# Конклав Чародеев
	factions[FACTION_MAGE_CONCLAVE] = {
		"name": "Конклав Чародеев",
		"description": "Осколки старого круга магов",
		"leader": "Архимаг Верен",
		"location": "Башня Академии",
		"color": Color(0.3, 0.3, 0.9),  # Магический синий
		"enemies": [FACTION_ASHEN_ORDER],
		"rivals": [FACTION_COUNCIL],
		"ideology": "knowledge",
	}

	# Совет Наместников
	factions[FACTION_COUNCIL] = {
		"name": "Совет Наместников",
		"description": "Бывшие дворяне и генералы",
		"leader": "Лорд-Протектор Мальрик",
		"location": "Город-крепость Халленхольд",
		"color": Color(0.8, 0.7, 0.2),  # Золотой
		"enemies": [],
		"rivals": [FACTION_ASHEN_ORDER, FACTION_MAGE_CONCLAVE, FACTION_OUTCASTS],
		"ideology": "order",
	}

	# Изгнанники
	factions[FACTION_OUTCASTS] = {
		"name": "Изгнанники",
		"description": "Простой народ, выживающий как может",
		"leader": "Нет единого лидера",
		"location": "Разбросаны по миру",
		"color": Color(0.5, 0.4, 0.3),  # Земляной коричневый
		"enemies": [],
		"rivals": [FACTION_COUNCIL],
		"ideology": "freedom",
	}

	# Древняя Раса (скрытая фракция)
	factions[FACTION_ANCIENT] = {
		"name": "???",
		"description": "Неизвестно",
		"leader": "???",
		"location": "Глубины",
		"color": Color(0.2, 0.0, 0.3),  # Тёмно-фиолетовый
		"enemies": [FACTION_ASHEN_ORDER, FACTION_MAGE_CONCLAVE, FACTION_COUNCIL, FACTION_OUTCASTS],
		"rivals": [],
		"ideology": "extinction",
		"hidden": true,
	}

	# Начальная репутация
	for faction_id in factions.keys():
		if faction_id == FACTION_ANCIENT:
			player_reputation[faction_id] = REP_HOSTILE  # Древние враждебны изначально
		else:
			player_reputation[faction_id] = REP_NEUTRAL


# Изменение репутации
func change_reputation(faction_id: String, amount: int) -> void:
	if not factions.has(faction_id):
		return

	var old_value = player_reputation[faction_id]
	player_reputation[faction_id] = clampi(old_value + amount, -100, 100)
	var new_value = player_reputation[faction_id]

	if old_value != new_value:
		reputation_changed.emit(faction_id, old_value, new_value)

		# Проверяем изменение статуса
		var old_status = _get_status_for_rep(old_value)
		var new_status = _get_status_for_rep(new_value)
		if old_status != new_status:
			faction_status_changed.emit(faction_id, new_status)

		# Влияние на враждебные фракции (убийство врагов = репутация)
		var faction_data = factions[faction_id]
		for enemy_id in faction_data.get("enemies", []):
			# Если репутация с фракцией растёт, с её врагами падает
			if amount > 0:
				change_reputation(enemy_id, -amount / 2)


func _get_status_for_rep(rep: int) -> String:
	if rep <= REP_HOSTILE:
		return "hostile"
	elif rep <= REP_UNFRIENDLY:
		return "unfriendly"
	elif rep < REP_FRIENDLY:
		return "neutral"
	elif rep < REP_TRUSTED:
		return "friendly"
	elif rep < REP_MEMBER:
		return "trusted"
	else:
		return "champion"


# Получить репутацию
func get_reputation(faction_id: String) -> int:
	return player_reputation.get(faction_id, 0)


# Получить статус отношений
func get_status(faction_id: String) -> String:
	return _get_status_for_rep(get_reputation(faction_id))


# Проверки отношений
func is_hostile(faction_id: String) -> bool:
	return get_reputation(faction_id) <= REP_HOSTILE


func is_friendly(faction_id: String) -> bool:
	return get_reputation(faction_id) >= REP_FRIENDLY


func can_join(faction_id: String) -> bool:
	if player_faction != "":
		return false  # Уже в фракции
	return get_reputation(faction_id) >= REP_MEMBER


# Вступление в фракцию
func join_faction(faction_id: String) -> bool:
	if not can_join(faction_id):
		return false

	# Выход из текущей фракции
	if player_faction != "":
		leave_faction()

	player_faction = faction_id
	player_joined_faction.emit(faction_id)

	# Враги фракции становятся врагами игрока
	var faction_data = factions[faction_id]
	for enemy_id in faction_data.get("enemies", []):
		change_reputation(enemy_id, -30)

	print("[ASHBOUND] Игрок вступил в: %s" % factions[faction_id]["name"])
	return true


func leave_faction() -> void:
	if player_faction == "":
		return

	var old_faction = player_faction
	player_faction = ""

	# Репутация падает при выходе
	change_reputation(old_faction, -40)

	player_left_faction.emit(old_faction)
	print("[ASHBOUND] Игрок покинул: %s" % factions[old_faction]["name"])


# Получить данные о фракции
func get_faction_data(faction_id: String) -> Dictionary:
	return factions.get(faction_id, {})


func get_faction_name(faction_id: String) -> String:
	var data = get_faction_data(faction_id)
	if data.get("hidden", false) and not GameManager.has_discovered_ancient_threat:
		return "???"
	return data.get("name", "Неизвестно")


# Отношения между фракциями
func get_faction_relation(faction_a: String, faction_b: String) -> String:
	if faction_a == faction_b:
		return "same"

	var data_a = factions.get(faction_a, {})

	if faction_b in data_a.get("enemies", []):
		return "enemy"
	elif faction_b in data_a.get("rivals", []):
		return "rival"
	else:
		return "neutral"
