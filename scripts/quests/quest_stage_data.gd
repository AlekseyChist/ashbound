class_name QuestStageData
extends Resource
## One stage of a quest: what the journal asks for, and an optional counter that moves it on.

@export var id: StringName
@export var objective_key: String
## Counter counted only in this stage (e.g. strikes on the dummy); empty = no counter.
@export var counter: StringName
@export var counter_total := 0
## Name of the objective text parameter that shows the count (the total is always "total").
@export var counter_param := "count"
## Stage reached when the counter hits its total.
@export var counter_next_stage: StringName
@export var completed := false
