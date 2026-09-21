class_name ItemRules
extends RefCounted
## Data-driven item behavior rules.
## All APIs receive canonical catalog templates (never caller-provided capabilities).

const TYPE_WEAPON := 0
const TYPE_ARMOR := 1
const TYPE_CONSUMABLE := 2
const TYPE_QUEST := 3
const TYPE_MISC := 4
const TYPE_MAGIC := 5


static func describe(template: Dictionary) -> Dictionary:
	if template.is_empty():
		return {}
	var category := _category(template)
	if category == "":
		return {}
	var subtype := _subtype(template, category)
	var quest_locked := _quest_locked(template)
	var tags := _tags(template, category)
	var quick_bindable := _quick_eligible(category, subtype)
	return {
		"category": category,
		"subtype": subtype,
		"tags": tags,
		"quest_locked": quest_locked,
		"movable": true,
		"droppable": not quest_locked,
		"quick_bindable": quick_bindable,
		"equipment_slot": _equipment_slot(template, category),
		"quick_action": _quick_action(category, subtype),
	}


static func can_equip(template: Dictionary, slot: String) -> bool:
	var d := describe(template)
	if d.is_empty():
		return false
	if d["equipment_slot"] != slot or slot == "":
		return false
	match slot:
		"weapon":
			return _legacy_type(template) == TYPE_WEAPON
		"armor":
			return _legacy_type(template) == TYPE_ARMOR
		"backpack", "pouch":
			return _legacy_type(template) == TYPE_MISC
		_:
			return false
	return false


static func can_quick(template: Dictionary) -> bool:
	var d := describe(template)
	if d.is_empty():
		return false
	return bool(d["quick_bindable"])


static func can_drop(template: Dictionary) -> bool:
	var d := describe(template)
	if d.is_empty():
		return false
	return bool(d["droppable"])


static func has_tag(template: Dictionary, tag: String) -> bool:
	var d := describe(template)
	if d.is_empty():
		return false
	return (d["tags"] as Array).has(tag)


# --- internals -----------------------------------------------------------

static func _category(t: Dictionary) -> String:
	var c := str(t.get("category", "")).strip_edges().to_lower()
	if c != "":
		return c
	var id := str(t.get("id", "")).strip_edges().to_lower()
	match id:
		"courtyard_sketch":
			return "object"
		"traveler_backpack":
			return "equipment"
		"belt_pouch":
			return "equipment"
		_:
			pass
	var legacy := _legacy_type(t)
	match legacy:
		TYPE_WEAPON:
			return "weapon"
		TYPE_ARMOR:
			return "clothing"
		TYPE_CONSUMABLE:
			return "consumable"
		TYPE_QUEST:
			return "object"
		TYPE_MAGIC:
			return "magic"
		TYPE_MISC:
			return "object"
		_:
			return ""
	return ""


static func _subtype(t: Dictionary, category: String) -> String:
	var s := str(t.get("subtype", "")).strip_edges().to_lower()
	if s != "":
		return s
	var id := str(t.get("id", "")).strip_edges().to_lower()
	match id:
		"courtyard_sketch":
			return "map"
		"traveler_backpack":
			return "backpack"
		"belt_pouch":
			return "pouch"
		_:
			pass
	match category:
		"weapon":
			if id.begins_with("sword"):
				return "sword"
			return "weapon"
		"clothing":
			return "armor_set"
		"consumable":
			if id == "bread":
				return "food"
			return "potion"
		"object":
			match _legacy_type(t):
				TYPE_QUEST:
					return "quest_object"
				_:
					return "misc"
		"magic":
			if id.begins_with("rune"):
				return "rune"
			return "scroll"
		_:
			return ""
	return ""


static func _tags(t: Dictionary, category: String) -> Array[String]:
	var out: Array[String] = []
	if category == "magic":
		out.append("magic")
	for v in t.get("tags", []):
		var tag := str(v).strip_edges()
		if tag != "" and not out.has(tag):
			out.append(tag)
	return out


static func _quest_locked(t: Dictionary) -> bool:
	if _legacy_type(t) == TYPE_QUEST:
		return true
	return bool(t.get("quest_locked", false))


static func _quick_eligible(category: String, subtype: String) -> bool:
	match category:
		"weapon":
			return true
		"consumable":
			return true
		"object":
			return subtype == "map"
		"magic":
			return subtype == "scroll" or subtype == "rune"
		_:
			return false


static func _quick_action(category: String, subtype: String) -> String:
	if not _quick_eligible(category, subtype):
		return ""
	match category:
		"weapon":
			return "equip_weapon"
		"consumable":
			return "consume"
		"object":
			return "open_map"
		"magic":
			return "cast"
		_:
			return ""


static func _equipment_slot(t: Dictionary, category: String) -> String:
	match category:
		"weapon":
			if _legacy_type(t) == TYPE_WEAPON:
				return "weapon"
			return ""
		"clothing":
			if _legacy_type(t) == TYPE_ARMOR:
				return "armor"
			return ""
		"equipment":
			match _subtype(t, category):
				"backpack":
					return "backpack" if _legacy_type(t) == TYPE_MISC else ""
				"pouch":
					return "pouch" if _legacy_type(t) == TYPE_MISC else ""
				_:
					return ""
		_:
			return ""


static func _legacy_type(t: Dictionary) -> int:
	var v = t.get("type", null)
	if v is int:
		return int(v)
	if v is float:
		return int(v)
	return -1
