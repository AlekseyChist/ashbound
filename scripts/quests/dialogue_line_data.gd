class_name DialogueLineData
extends Resource
## One reply of a speaker; the quest uses the first line whose conditions match.

## Interaction id of the speaker or object (innkeeper, woodpile, watchman...).
@export var speaker: StringName
## Stages where the line applies; empty = any stage.
@export var stages: Array[StringName] = []
@export var requires_flag: StringName
@export var forbids_flag: StringName
## Localization keys: speaker name ("" for objects) and the line itself.
@export var name_key: String
@export var line_key: String
## Level actions run before the line is shown (e.g. hide_woodpile_label).
@export var effects: Array[StringName] = []
@export var set_flag: StringName
@export var next_stage: StringName
