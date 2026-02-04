## DialogueUI - Интерфейс диалогов в стиле Gothic
## Отображает реплики NPC и варианты ответов игрока
class_name DialogueUI
extends CanvasLayer

@onready var dialogue_panel: PanelContainer = $DialoguePanel
@onready var speaker_label: Label = $DialoguePanel/MarginContainer/VBoxContainer/SpeakerLabel
@onready var text_label: RichTextLabel = $DialoguePanel/MarginContainer/VBoxContainer/TextLabel
@onready var choices_container: VBoxContainer = $DialoguePanel/MarginContainer/VBoxContainer/ChoicesContainer
@onready var continue_hint: Label = $DialoguePanel/MarginContainer/VBoxContainer/ContinueHint

var choice_buttons: Array[Button] = []
var can_continue: bool = false


func _ready() -> void:
	# Скрываем UI по умолчанию
	dialogue_panel.visible = false

	# Подключаемся к сигналам DialogueSystem
	DialogueSystem.dialogue_started.connect(_on_dialogue_started)
	DialogueSystem.dialogue_ended.connect(_on_dialogue_ended)
	DialogueSystem.line_displayed.connect(_on_line_displayed)
	DialogueSystem.choices_presented.connect(_on_choices_presented)


func _input(event: InputEvent) -> void:
	if not dialogue_panel.visible:
		return

	# Продолжить диалог по пробелу или ЛКМ
	if can_continue:
		if event.is_action_pressed("interact") or event.is_action_pressed("attack"):
			can_continue = false
			DialogueSystem.continue_dialogue()


func _on_dialogue_started(npc_name: String) -> void:
	dialogue_panel.visible = true
	_clear_choices()


func _on_dialogue_ended() -> void:
	dialogue_panel.visible = false
	_clear_choices()


func _on_line_displayed(speaker: String, text: String) -> void:
	speaker_label.text = speaker
	text_label.text = text

	# Скрываем подсказку, пока не появятся выборы
	continue_hint.visible = false
	can_continue = false


func _on_choices_presented(choices: Array) -> void:
	_clear_choices()

	if choices.is_empty():
		# Нет выборов - показываем подсказку для продолжения
		continue_hint.visible = true
		continue_hint.text = "[Пробел/E] Продолжить"
		can_continue = true
		return

	# Создаём кнопки для каждого выбора
	for i in range(choices.size()):
		var choice = choices[i]
		var button = Button.new()
		button.text = "%d. %s" % [i + 1, choice.get("text", "...")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_choice_selected.bind(i))

		# Стиль кнопки
		button.add_theme_font_size_override("font_size", 16)

		choices_container.add_child(button)
		choice_buttons.append(button)

	# Показываем подсказку
	continue_hint.visible = true
	continue_hint.text = "Выберите ответ"


func _on_choice_selected(index: int) -> void:
	DialogueSystem.select_choice(index)
	_clear_choices()


func _clear_choices() -> void:
	for button in choice_buttons:
		button.queue_free()
	choice_buttons.clear()
