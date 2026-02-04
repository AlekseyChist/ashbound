## DialogueSystem - Система диалогов в стиле Gothic
## Ветвящиеся диалоги с условиями, репутацией, выборами
extends Node

signal dialogue_started(npc_name: String)
signal dialogue_ended
signal line_displayed(speaker: String, text: String)
signal choices_presented(choices: Array)
signal choice_made(choice_index: int)

# Текущий диалог
var current_dialogue: Dictionary = {}
var current_node_id: String = ""
var current_npc: Node = null
var is_in_dialogue: bool = false


func _ready() -> void:
	print("[ASHBOUND] DialogueSystem инициализирован")


# Начать диалог с NPC
func start_dialogue(npc: Node, dialogue_data: Dictionary) -> void:
	if is_in_dialogue:
		return

	current_npc = npc
	current_dialogue = dialogue_data
	is_in_dialogue = true

	# Переключаем состояние игры
	GameManager.change_state(GameManager.GameState.DIALOGUE)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var npc_name = dialogue_data.get("npc_name", "Незнакомец")
	dialogue_started.emit(npc_name)

	# Начинаем с начального узла
	_goto_node(dialogue_data.get("start_node", "start"))


func _goto_node(node_id: String) -> void:
	current_node_id = node_id

	if not current_dialogue.has("nodes"):
		end_dialogue()
		return

	var nodes = current_dialogue["nodes"]
	if not nodes.has(node_id):
		end_dialogue()
		return

	var node = nodes[node_id]

	# Проверяем условия узла
	if node.has("condition") and not _check_condition(node["condition"]):
		# Если условие не выполнено, идём на fallback или заканчиваем
		if node.has("fallback"):
			_goto_node(node["fallback"])
		else:
			end_dialogue()
		return

	# Отображаем текст
	var speaker = node.get("speaker", current_dialogue.get("npc_name", ""))
	var text = node.get("text", "")

	# Подстановка переменных в текст
	text = _process_text(text)

	line_displayed.emit(speaker, text)

	# Выполняем действия узла
	if node.has("actions"):
		_execute_actions(node["actions"])

	# Показываем варианты ответа или продолжаем
	if node.has("choices"):
		var available_choices = _filter_choices(node["choices"])
		if available_choices.is_empty():
			# Нет доступных выборов - заканчиваем
			if node.has("next"):
				# Автопереход через несколько секунд или по клику
				pass
			else:
				end_dialogue()
		else:
			choices_presented.emit(available_choices)
	elif node.has("next"):
		# Автоматический переход (для монологов)
		# UI должен вызвать continue_dialogue()
		pass
	else:
		# Конец ветки
		pass


# Продолжить диалог (для узлов без выбора)
func continue_dialogue() -> void:
	if not is_in_dialogue:
		return

	var nodes = current_dialogue.get("nodes", {})
	var current_node = nodes.get(current_node_id, {})

	if current_node.has("next"):
		_goto_node(current_node["next"])
	else:
		end_dialogue()


# Выбор варианта ответа
func select_choice(choice_index: int) -> void:
	if not is_in_dialogue:
		return

	var nodes = current_dialogue.get("nodes", {})
	var current_node = nodes.get(current_node_id, {})
	var choices = current_node.get("choices", [])

	var available_choices = _filter_choices(choices)

	if choice_index < 0 or choice_index >= available_choices.size():
		return

	var choice = available_choices[choice_index]
	choice_made.emit(choice_index)

	# Выполняем действия выбора
	if choice.has("actions"):
		_execute_actions(choice["actions"])

	# Переходим к следующему узлу
	if choice.has("next"):
		_goto_node(choice["next"])
	else:
		end_dialogue()


func _filter_choices(choices: Array) -> Array:
	var available = []
	for choice in choices:
		if choice.has("condition"):
			if _check_condition(choice["condition"]):
				available.append(choice)
		else:
			available.append(choice)
	return available


func _check_condition(condition: Dictionary) -> bool:
	var type = condition.get("type", "")

	match type:
		"reputation":
			var faction = condition.get("faction", "")
			var min_rep = condition.get("min", -100)
			var max_rep = condition.get("max", 100)
			var rep = FactionManager.get_reputation(faction)
			return rep >= min_rep and rep <= max_rep

		"quest_active":
			return QuestManager.is_quest_active(condition.get("quest_id", ""))

		"quest_completed":
			return QuestManager.is_quest_completed(condition.get("quest_id", ""))

		"objective_completed":
			return QuestManager.is_objective_completed(
				condition.get("quest_id", ""),
				condition.get("objective_id", "")
			)

		"player_faction":
			return FactionManager.player_faction == condition.get("faction", "")

		"player_level":
			var min_level = condition.get("min", 1)
			return GameManager.player.level >= min_level

		"flag":
			# Простые флаги для особых условий
			var flag_name = condition.get("name", "")
			if flag_name == "discovered_ancient_threat":
				return GameManager.has_discovered_ancient_threat
			return false

		"time":
			var period = condition.get("period", "")
			return GameManager.get_time_period() == period

	return true


func _execute_actions(actions: Array) -> void:
	for action in actions:
		var type = action.get("type", "")

		match type:
			"reputation":
				var faction = action.get("faction", "")
				var amount = action.get("amount", 0)
				FactionManager.change_reputation(faction, amount)

			"start_quest":
				QuestManager.start_quest(action.get("quest_id", ""))

			"complete_objective":
				QuestManager.update_objective(
					action.get("quest_id", ""),
					action.get("objective_id", ""),
					true
				)

			"give_item":
				# TODO: Inventory system
				pass

			"give_gold":
				# TODO: Inventory system
				pass

			"give_experience":
				if GameManager.player:
					GameManager.player.add_experience(action.get("amount", 0))

			"set_flag":
				var flag_name = action.get("name", "")
				if flag_name == "discovered_ancient_threat":
					GameManager.has_discovered_ancient_threat = true

			"trigger_event":
				# Для кат-сцен, боёв и т.д.
				pass


func _process_text(text: String) -> String:
	# Подстановка переменных
	text = text.replace("{player_name}", "Безымянный")

	if GameManager.player:
		text = text.replace("{player_level}", str(GameManager.player.level))

	text = text.replace("{time_period}", GameManager.get_time_period())
	text = text.replace("{day}", str(GameManager.current_day))

	return text


func end_dialogue() -> void:
	is_in_dialogue = false
	current_dialogue = {}
	current_node_id = ""
	current_npc = null

	GameManager.change_state(GameManager.GameState.PLAYING)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	dialogue_ended.emit()


# === СОЗДАНИЕ ДИАЛОГОВ ===
# Пример структуры диалога:

static func create_example_dialogue() -> Dictionary:
	return {
		"npc_name": "Старый выживший",
		"start_node": "greeting",
		"nodes": {
			"greeting": {
				"speaker": "Старый выживший",
				"text": "Хм? Ещё один бродяга? Удивительно, что ты добрался сюда живым.",
				"choices": [
					{
						"text": "Где я? Что здесь произошло?",
						"next": "explain_world"
					},
					{
						"text": "Мне нужно оружие.",
						"next": "about_weapon"
					},
					{
						"text": "[Уйти]",
						"next": "end"
					}
				]
			},
			"explain_world": {
				"speaker": "Старый выживший",
				"text": "Ты в руинах того, что когда-то было королевством. Война, магия, фанатики... всё это превратило мир в пепел. Теперь здесь правят три силы: культисты, маги и так называемый Совет. А простой люд, вроде меня... выживает как может.",
				"actions": [
					{"type": "complete_objective", "quest_id": "prologue_survival", "objective_id": "talk_survivor"}
				],
				"choices": [
					{
						"text": "Расскажи больше о фракциях.",
						"next": "about_factions"
					},
					{
						"text": "Где найти укрытие?",
						"next": "about_shelter"
					}
				]
			},
			"about_factions": {
				"speaker": "Старый выживший",
				"text": "Орден Пепельного Пламени – фанатики, верящие в очищение огнём. Конклав магов – гордецы, запершиеся в своей башне. Совет Наместников – жадные лорды, выжимающие последние соки из народа. Выбирай союзников осторожно... или не выбирай вовсе.",
				"actions": [
					{"type": "start_quest", "quest_id": "choose_path"}
				],
				"next": "greeting"
			},
			"about_weapon": {
				"speaker": "Старый выживший",
				"text": "Оружие? Хех, в развалинах к востоку можно найти ржавый меч. Если повезёт.",
				"next": "greeting"
			},
			"about_shelter": {
				"speaker": "Старый выживший",
				"text": "За холмом есть старая мельница. Крыша дырявая, но от дождя укроет.",
				"actions": [
					{"type": "complete_objective", "quest_id": "prologue_survival", "objective_id": "find_shelter"}
				],
				"next": "greeting"
			},
			"end": {
				"speaker": "",
				"text": "",
			}
		}
	}
