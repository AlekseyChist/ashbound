class_name QuestData
extends Resource
## A quest as data (review 2.2): ordered stages, dialogue lines and saved flags.
## Stage order is the saved stage index, so it must not be reordered once saves exist.

@export var id: StringName
@export var title_key: String
@export var stages: Array[QuestStageData] = []
@export var lines: Array[DialogueLineData] = []
@export var flags: Array[StringName] = []

func stage_index(stage_id: StringName) -> int:
	for i in range(stages.size()):
		if stages[i].id == stage_id:
			return i
	return -1

func line_for(speaker: StringName, stage_id: StringName, active_flags: Dictionary) -> DialogueLineData:
	for line in lines:
		if line.speaker != speaker:
			continue
		if not line.stages.is_empty() and not line.stages.has(stage_id):
			continue
		if line.requires_flag != &"" and not active_flags.get(line.requires_flag, false):
			continue
		if line.forbids_flag != &"" and active_flags.get(line.forbids_flag, false):
			continue
		return line
	return null
