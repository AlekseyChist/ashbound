class_name CourtyardInteractionPoint
extends Node3D
## Точка взаимодействия двора. Маркеры/лейблы подключаются сценой.
## display_name и prompt хранят КЛЮЧИ локализации; переведённые значения
## выдаются через get_display_name()/get_prompt().

@export var interaction_id: StringName = &"innkeeper"
@export var display_name: String = "COURTYARD_NAME_INNKEEPER"
@export var prompt: String = "COURTYARD_ACTION_TALK"

signal interacted(point: CourtyardInteractionPoint)


func _ready() -> void:
	Localization.language_changed.connect(_on_language_changed)
	_refresh_labels()


func get_display_name() -> String:
	return Localization.text(display_name)


func get_prompt() -> String:
	return Localization.text(prompt)


func _refresh_labels() -> void:
	var name_label: Label3D = get_node_or_null("NameLabel")
	if name_label != null:
		name_label.text = get_display_name()
	var label: Label3D = get_node_or_null("Label3D")
	if label != null:
		label.text = get_display_name()


func _on_language_changed(_language: String) -> void:
	if not is_node_ready():
		return
	_refresh_labels()


func interact() -> void:
	interacted.emit(self)
