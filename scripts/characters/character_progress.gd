extends Node

signal changed()

const MAX_POINTS: int = 2147483647
const _MAX_AWARD_SOURCES: int = 1024
var _source_id_regex: RegEx = RegEx.new()


func _init() -> void:
	_source_id_regex.compile("^[a-z][a-z0-9_]{0,63}$")


var _learning_points: int = 0
var _point_awards: Dictionary = {}
var _guard_practice_completed: bool = false


func get_character_data() -> Dictionary:
	return {
		"learning_points": _learning_points,
		"unarmed_mastery": "novice",
		"guard_practice_completed": _guard_practice_completed,
	}


func award_learning_points(source_id: String, amount: int) -> bool:
	if not _is_valid_source_id(source_id):
		return false
	if amount <= 0 or amount > MAX_POINTS:
		return false
	if _point_awards.has(source_id):
		return false
	if _point_awards.size() >= _MAX_AWARD_SOURCES:
		return false
	var new_total: int = _learning_points + amount
	if new_total < 0 or new_total > MAX_POINTS:
		return false
	_point_awards[source_id] = amount
	_learning_points = new_total
	changed.emit()
	return true


func complete_guard_practice() -> bool:
	if _guard_practice_completed:
		return false
	_guard_practice_completed = true
	changed.emit()
	return true


func reset_guard_practice() -> void:
	if not _guard_practice_completed:
		return
	_guard_practice_completed = false
	changed.emit()


func get_save_data() -> Dictionary:
	var awards_copy: Dictionary = {}
	for key in _point_awards.keys():
		awards_copy[key] = int(_point_awards[key])
	return {
		"schema_version": 1,
		"learning_points": _learning_points,
		"point_awards": awards_copy,
		"guard_practice_completed": _guard_practice_completed,
	}


func load_save_data(data: Dictionary) -> bool:
	if not data.has("schema_version") or not data.has("learning_points") \
			or not data.has("point_awards") or not data.has("guard_practice_completed"):
		return false
	if data.size() != 4:
		return false

	var schema_version: Variant = data["schema_version"]
	if not _is_whole_number(schema_version) or int(schema_version) != 1:
		return false

	var learning_points: Variant = data["learning_points"]
	if not _is_whole_number(learning_points):
		return false
	var points_value: int = int(learning_points)
	if points_value < 0 or points_value > MAX_POINTS:
		return false

	var raw_awards: Variant = data["point_awards"]
	if not (raw_awards is Dictionary):
		return false
	var awards: Dictionary = raw_awards
	if awards.size() > _MAX_AWARD_SOURCES:
		return false

	var parsed_awards: Dictionary = {}
	var total: int = 0
	for key in awards.keys():
		if not (key is String):
			return false
		var source_id: String = key
		if not _is_valid_source_id(source_id):
			return false
		var value: Variant = awards[key]
		if not _is_whole_number(value):
			return false
		var award_value: int = int(value)
		if award_value <= 0 or award_value > MAX_POINTS:
			return false
		if total > MAX_POINTS - award_value:
			return false
		total += award_value
		parsed_awards[source_id] = award_value

	if total != points_value:
		return false

	var guard_flag: Variant = data["guard_practice_completed"]
	if not (guard_flag is bool):
		return false

	var new_points: int = points_value
	var new_guard: bool = bool(guard_flag)
	var data_changed := parsed_awards != _point_awards \
			or new_points != _learning_points \
			or new_guard != _guard_practice_completed

	_learning_points = new_points
	_point_awards = parsed_awards
	_guard_practice_completed = new_guard

	if data_changed:
		changed.emit()
	return true


func _is_valid_source_id(source_id: String) -> bool:
	var match := _source_id_regex.search(source_id)
	return match != null and match.get_start() == 0 and match.get_end() == source_id.length()


func _is_whole_number(value: Variant) -> bool:
	var type := typeof(value)
	if type == TYPE_INT:
		var i: int = value
		return i >= 0 and i <= MAX_POINTS
	if type != TYPE_FLOAT:
		return false
	var f: float = value
	return is_finite(f) and f == floorf(f) and f >= 0.0 and f <= float(MAX_POINTS)
