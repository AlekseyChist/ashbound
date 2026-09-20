class_name CourtyardInteractionPoint
extends Node3D
## Точка взаимодействия двора. Маркеры/лейблы подключаются сценой.

@export var interaction_id: StringName = &"innkeeper"
@export var display_name: String = "Хозяйка"
@export var prompt: String = "Поговорить"

signal interacted(point: CourtyardInteractionPoint)


func interact() -> void:
	interacted.emit(self)
