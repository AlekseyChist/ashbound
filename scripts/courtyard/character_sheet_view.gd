extends RefCounted
## MENU-02B: read-only character sheet page (inserted after QuestPage).

var page: HBoxContainer:
	get:
		return _page

var _panel: Control
var _progress: Node = null
var _page: HBoxContainer
var _title_label: Label
var _points_label: Label
var _skills_title_label: Label
var _unarmed_label: Label
var _guard_label: Label
var _hint_label: Label


func _init(panel: Control) -> void:
	_panel = panel
	_build_page()
	var profile := _find_profile()
	if profile != null:
		_progress = profile
		profile.changed.connect(_on_progress_changed)
	refresh()


func has_profile() -> bool:
	if not is_instance_valid(_progress):
		return false
	return _progress.has_method("get_character_data") and _progress.has_signal("changed")


func refresh() -> void:
	if _panel == null or _page == null:
		return
	var data: Variant = null
	if is_instance_valid(_progress):
		data = _progress.get_character_data()
	if typeof(data) != TYPE_DICTIONARY:
		_title_label.text = ""
		_points_label.text = ""
		_skills_title_label.text = ""
		_unarmed_label.text = ""
		_guard_label.text = ""
		_hint_label.text = ""
		return
	var dict_data: Dictionary = data
	_localize(dict_data)
	var unarmed_mastery: String = str(dict_data.get("unarmed_mastery", ""))
	var guard_done: bool = bool(dict_data.get("guard_practice_completed", false))
	if unarmed_mastery == "novice":
		_unarmed_label.text = _text("MENU_CHARACTER_UNARMED_NOVICE")
	else:
		_unarmed_label.text = ""
	if guard_done:
		_guard_label.text = _text("MENU_CHARACTER_PRACTICE_DONE")
	else:
		_guard_label.text = _text("MENU_CHARACTER_PRACTICE_PENDING")


func _on_progress_changed() -> void:
	refresh()


func _build_page() -> void:
	var root_vbox: Node = _panel.get_node("Margin/RootVBox")
	_page = HBoxContainer.new()
	_page.name = "CharacterPage"
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 40)
	_page.visible = false

	var portrait_script: GDScript = preload("res://scripts/courtyard/inventory_character_preview.gd")
	var portrait: TextureRect = portrait_script.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(600, 500)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(portrait)

	var details: VBoxContainer = VBoxContainer.new()
	details.name = "Details"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 24)
	_page.add_child(details)

	_title_label = _make_label(42, "MENU_SECTION_CHARACTER")
	_title_label.name = "CharacterTitle"
	details.add_child(_title_label)
	_points_label = _make_label(38, "")
	_points_label.name = "LearningPoints"
	details.add_child(_points_label)
	_skills_title_label = _make_label(36, "MENU_CHARACTER_SKILLS")
	_skills_title_label.name = "SkillsTitle"
	details.add_child(_skills_title_label)
	_unarmed_label = _make_label(34, "")
	_unarmed_label.name = "Unarmed"
	details.add_child(_unarmed_label)
	_guard_label = _make_label(30, "")
	_guard_label.name = "GuardPractice"
	details.add_child(_guard_label)
	_hint_label = _make_label(30, "MENU_CHARACTER_TEACHER_HINT")
	_hint_label.name = "TeacherHint"
	details.add_child(_hint_label)

	var quest_page: Node = root_vbox.get_node_or_null("QuestPage")
	if quest_page != null:
		root_vbox.add_child(_page)
		root_vbox.move_child(_page, quest_page.get_index() + 1)
	else:
		root_vbox.add_child(_page)


func _make_label(font_size: int, key: String) -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.88, 0.85, 0.77))
	if key != "":
		label.text = _text(key)
	return label


func _localize(data: Dictionary) -> void:
	_title_label.text = _text("MENU_SECTION_CHARACTER")
	var points: int = int(data["learning_points"])
	_points_label.text = _text("MENU_CHARACTER_POINTS", {"count": points})
	_skills_title_label.text = _text("MENU_CHARACTER_SKILLS")
	_hint_label.text = _text("MENU_CHARACTER_TEACHER_HINT")


func _find_profile() -> Node:
	var node: Node = _panel
	while node != null:
		var candidate: Node = node.get_node_or_null("Actors/Player/Progression")
		if candidate != null and is_instance_valid(candidate) \
				and candidate.has_method("get_character_data") \
				and candidate.has_signal("changed"):
			return candidate
		node = node.get_parent()
	return null


func _text(key: String, params: Variant = {}) -> String:
	if not is_instance_valid(_panel):
		return ""
	var result: Variant = _panel._text(key, params)
	if typeof(result) == TYPE_STRING:
		return str(result)
	return ""
