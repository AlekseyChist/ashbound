class_name ItemData
extends Resource
## ITEM-DATA-01 (review 2.4): one item of the catalog as data. The inventory still works with
## Dictionaries; `to_dict()` gives exactly the dictionary the old hard-coded catalog had
## (a key is present only when it is set, as before).

enum Type { WEAPON, ARMOR, CONSUMABLE, QUEST, MISC, MAGIC }

@export var id: String
@export var type: Type = Type.MISC
## Display name/description (Russian source text, as in the old catalog).
@export var name: String
@export_multiline var description: String
@export var value := 0
@export var stackable := false
## Stack limit; 0 = not set (non-stackable items).
@export var max_stack := 0
## Equipment slot ("weapon", "armor"); empty = cannot be equipped.
@export var slot: String
@export var icon: String
@export var stats: Dictionary = {}
@export var effect: Dictionary = {}
@export var faction_requirement: String
@export var quest_id: String
@export var quest_locked := false
@export var category: String
@export var subtype: String
@export var tags: Array = []

func to_dict() -> Dictionary:
	var item := {
		"id": id,
		"type": int(type),
		"name": name,
		"description": description,
		"value": value,
		"stackable": stackable,
		"category": category,
		"subtype": subtype,
		"tags": tags.duplicate(),
	}
	if max_stack > 0: item["max_stack"] = max_stack
	if not slot.is_empty(): item["slot"] = slot
	if not icon.is_empty(): item["icon"] = icon
	if not stats.is_empty(): item["stats"] = stats.duplicate(true)
	if not effect.is_empty(): item["effect"] = effect.duplicate(true)
	if not faction_requirement.is_empty(): item["faction_requirement"] = faction_requirement
	if not quest_id.is_empty(): item["quest_id"] = quest_id
	if quest_locked: item["quest_locked"] = true
	return item
