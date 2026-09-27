class_name QuestTracker
extends RefCounted
## Runtime state of one QuestData: current stage, counters and flags.
## The level shows lines and runs effects; the tracker only decides and remembers.

var quest: QuestData
var stage_index := 0
var counters: Dictionary = {}
var flags: Dictionary = {}

func _init(data: QuestData) -> void:
	quest = data
	reset()

func reset() -> void:
	stage_index = 0
	counters.clear()
	flags.clear()
	for stage in quest.stages:
		if stage.counter != &"":
			counters[stage.counter] = 0
	for flag in quest.flags:
		flags[flag] = false

func current_stage() -> QuestStageData:
	return quest.stages[clampi(stage_index, 0, quest.stages.size() - 1)]

func line_for(speaker: StringName) -> DialogueLineData:
	return quest.line_for(speaker, current_stage().id, flags)

## Remember what the line changes. Returns true when the stage changed.
func apply_line(line: DialogueLineData) -> bool:
	if line.set_flag != &"":
		flags[line.set_flag] = true
	return go_to(line.next_stage)

func go_to(stage_id: StringName) -> bool:
	if stage_id == &"":
		return false
	var index := quest.stage_index(stage_id)
	if index < 0 or index == stage_index:
		return false
	stage_index = index
	return true

## True when the current stage counts this counter (e.g. the dummy during practice).
func counts(counter: StringName) -> bool:
	return current_stage().counter == counter

## Count one; returns true when the total is reached.
func add_count(counter: StringName) -> bool:
	var stage := current_stage()
	if stage.counter != counter:
		return false
	counters[counter] = mini(int(counters.get(counter, 0)) + 1, stage.counter_total)
	return int(counters[counter]) >= stage.counter_total

func finish_counter() -> bool:
	return go_to(current_stage().counter_next_stage)

func journal_entry() -> Dictionary:
	var stage := current_stage()
	var params := {}
	if stage.counter != &"":
		params[stage.counter_param] = int(counters.get(stage.counter, 0))
		params["total"] = stage.counter_total
	return {
		"id": String(quest.id),
		"title_key": quest.title_key,
		"objective_key": stage.objective_key,
		"params": params,
		"completed": stage.completed,
	}
