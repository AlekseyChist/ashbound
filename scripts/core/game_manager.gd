## GameManager - Главный контроллер игры ASHBOUND
## Автозагрузчик (Singleton) - доступен как GameManager из любого скрипта
extends Node

# Сигналы для событий игры
signal game_started
signal game_paused(is_paused: bool)
signal game_saved
signal game_loaded
signal time_of_day_changed(hour: int)

# Состояния игры
enum GameState { MAIN_MENU, PLAYING, PAUSED, DIALOGUE, INVENTORY, CUTSCENE }

# Текущее состояние
var current_state: GameState = GameState.MAIN_MENU
var previous_state: GameState = GameState.MAIN_MENU

# Игровое время (Gothic-style day/night cycle)
var game_time: float = 8.0  # Начинаем в 8 утра
var time_scale: float = 60.0  # 1 реальная секунда = 1 игровая минута
var current_day: int = 1

# Ссылка на игрока
var player: Node3D = null

# Флаги прогресса
var has_discovered_ancient_threat: bool = false
var main_quest_stage: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Работает даже на паузе
	print("[ASHBOUND] GameManager инициализирован")


func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		_update_game_time(delta)


func _update_game_time(delta: float) -> void:
	game_time += delta * time_scale / 3600.0  # Конвертируем в часы

	if game_time >= 24.0:
		game_time -= 24.0
		current_day += 1

	# Оповещаем о смене времени суток каждый час
	var current_hour = int(game_time)
	if current_hour != int(game_time - delta * time_scale / 3600.0):
		time_of_day_changed.emit(current_hour)


# Управление состоянием игры
func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return

	previous_state = current_state
	current_state = new_state

	match new_state:
		GameState.PAUSED:
			get_tree().paused = true
			game_paused.emit(true)
		GameState.PLAYING:
			get_tree().paused = false
			game_paused.emit(false)
		GameState.DIALOGUE, GameState.INVENTORY:
			get_tree().paused = true


func start_new_game() -> void:
	current_state = GameState.PLAYING
	game_time = 8.0
	current_day = 1
	has_discovered_ancient_threat = false
	main_quest_stage = 0
	game_started.emit()
	print("[ASHBOUND] Новая игра началась")


func pause_game() -> void:
	if current_state == GameState.PLAYING:
		change_state(GameState.PAUSED)


func resume_game() -> void:
	if current_state == GameState.PAUSED:
		change_state(GameState.PLAYING)


func toggle_pause() -> void:
	if current_state == GameState.PLAYING:
		pause_game()
	elif current_state == GameState.PAUSED:
		resume_game()


# Время суток для освещения и NPC расписания
func get_time_period() -> String:
	if game_time >= 6.0 and game_time < 12.0:
		return "morning"
	elif game_time >= 12.0 and game_time < 18.0:
		return "afternoon"
	elif game_time >= 18.0 and game_time < 22.0:
		return "evening"
	else:
		return "night"


func is_night() -> bool:
	return game_time >= 22.0 or game_time < 6.0


# Сохранение/Загрузка
func save_game(slot: int = 0) -> void:
	var save_data = {
		"game_time": game_time,
		"current_day": current_day,
		"main_quest_stage": main_quest_stage,
		"has_discovered_ancient_threat": has_discovered_ancient_threat,
		"player_position": player.global_position if player else Vector3.ZERO,
	}

	var save_path = "user://save_%d.json" % slot
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()
		game_saved.emit()
		print("[ASHBOUND] Игра сохранена в слот %d" % slot)


func load_game(slot: int = 0) -> bool:
	var save_path = "user://save_%d.json" % slot
	if not FileAccess.file_exists(save_path):
		print("[ASHBOUND] Файл сохранения не найден")
		return false

	var file = FileAccess.open(save_path, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		file.close()

		if error == OK:
			var save_data = json.data
			game_time = save_data.get("game_time", 8.0)
			current_day = save_data.get("current_day", 1)
			main_quest_stage = save_data.get("main_quest_stage", 0)
			has_discovered_ancient_threat = save_data.get("has_discovered_ancient_threat", false)

			game_loaded.emit()
			print("[ASHBOUND] Игра загружена из слота %d" % slot)
			return true

	return false
