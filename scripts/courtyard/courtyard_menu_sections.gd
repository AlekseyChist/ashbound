extends RefCounted
# MENU-02A: read-only journal sections controller for the courtyard touch panel.

const COLOR_DARK := Color(0.10, 0.11, 0.12)
const COLOR_BRONZE := Color(0.56, 0.44, 0.25)
const COLOR_TEXT := Color(0.88, 0.85, 0.77)

var owner: Control
var current_section: String = "items"

var _journal_provider: Node = null
var _tabs: HBoxContainer = null
var _items_tab: Button = null
var _quests_tab: Button = null
var _quest_page: VBoxContainer = null
var _quest_title: Label = null
var _quest_status: Label = null
var _quest_objective: Label = null
var _body: HBoxContainer = null
var _quick_label: Label = null
var _quick_slots: HBoxContainer = null


func _init(owner_arg: Control) -> void:
	owner = owner_arg
	_build_ui()
	_find_journal_provider()


func select_section(id: String) -> void:
	if id != "items" and id != "quests":
		return
	current_section = id
	owner._reset_gesture()
	_apply_section_visibility()
	_refresh_tabs()
	refresh()


func refresh() -> void:
	_refresh_tabs()
	_refresh_quest_page()


func hit_test(pos: Vector2) -> Dictionary:
	for button: Button in [_items_tab, _quests_tab]:
		if is_instance_valid(button) and button.is_visible_in_tree():
			if button.get_global_rect().has_point(pos):
				return {"kind": "section", "id": _tab_id(button), "control": button}
	return {}


func _build_ui() -> void:
	var header: HBoxContainer = owner.get_node("Margin/RootVBox/Header")
	var footer: HBoxContainer = owner.get_node("Margin/RootVBox/Footer")
	footer.alignment = BoxContainer.ALIGNMENT_END
	_body = owner.get_node("Margin/RootVBox/Body")
	_quick_label = owner._quick_label
	_quick_slots = owner._quick_slots

	_tabs = HBoxContainer.new()
	_tabs.name = "SectionTabs"
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_constant_override("separation", 12)
	header.add_child(_tabs)
	header.move_child(_tabs, 0)

	_items_tab = _make_tab_button("ItemsTab", "MENU_SECTION_ITEMS")
	_quests_tab = _make_tab_button("QuestsTab", "MENU_SECTION_QUESTS")
	_tabs.add_child(_items_tab)
	_tabs.add_child(_quests_tab)

	var root_vbox: VBoxContainer = owner.get_node("Margin/RootVBox")
	_quest_page = VBoxContainer.new()
	_quest_page.name = "QuestPage"
	_quest_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_quest_page.add_theme_constant_override("separation", 24)
	root_vbox.add_child(_quest_page)
	var body_index: int = _body.get_index()
	root_vbox.move_child(_quest_page, body_index + 1)

	_quest_title = _make_label("QuestTitle", 46)
	_quest_status = _make_label("QuestStatus", 30)
	_quest_objective = _make_label("QuestObjective", 38)
	_quest_page.add_child(_quest_title)
	_quest_page.add_child(_quest_status)
	_quest_page.add_child(_quest_objective)

	_apply_section_visibility()
	_refresh_tabs()


func _make_tab_button(node_name: String, text_key: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(240.0, 100.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 34)
	button.text = owner._text(text_key)
	return button


func _make_label(node_name: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _find_journal_provider() -> void:
	var node: Node = owner.get_parent()
	while is_instance_valid(node):
		if node.has_method("get_journal_entry"):
			_journal_provider = node
			break
		node = node.get_parent()
	if is_instance_valid(_journal_provider) and _journal_provider.has_signal("journal_changed"):
		_journal_provider.connect("journal_changed", _on_journal_changed)


func _on_journal_changed() -> void:
	refresh()


func _apply_section_visibility() -> void:
	var is_items: bool = current_section == "items"
	owner._title.visible = false
	if is_instance_valid(_body):
		_body.visible = is_items
	if is_instance_valid(_quick_label):
		_quick_label.visible = is_items
	if is_instance_valid(_quick_slots):
		_quick_slots.visible = is_items
	if is_instance_valid(owner._hint):
		owner._hint.visible = is_items
	if is_instance_valid(_quest_page):
		_quest_page.visible = not is_items


func _refresh_tabs() -> void:
	_items_tab.text = owner._text("MENU_SECTION_ITEMS")
	_quests_tab.text = owner._text("MENU_SECTION_QUESTS")
	_style_tab(_items_tab, current_section == "items")
	_style_tab(_quests_tab, current_section == "quests")


func _style_tab(button: Button, active: bool) -> void:
	if not is_instance_valid(button):
		return
	var bg_color: Color = COLOR_BRONZE if active else COLOR_DARK
	var fg_color: Color = COLOR_TEXT if active else COLOR_BRONZE
	button.add_theme_color_override("font_color", fg_color)
	button.add_theme_color_override("font_pressed_color", fg_color)
	button.add_theme_color_override("font_hover_color", fg_color)
	button.add_theme_color_override("font_focus_color", fg_color)
	button.add_theme_color_override("font_disabled_color", fg_color)
	button.add_theme_stylebox_override("normal", _flat_style(bg_color, fg_color))
	button.add_theme_stylebox_override("hover", _flat_style(bg_color, fg_color))
	button.add_theme_stylebox_override("pressed", _flat_style(bg_color, fg_color))
	button.add_theme_stylebox_override("focus", _flat_style(bg_color, fg_color))


func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	return style


func _refresh_quest_page() -> void:
	if not is_instance_valid(_quest_page):
		return
	var entry: Dictionary = {}
	if is_instance_valid(_journal_provider):
		var raw_entry: Variant = _journal_provider.call("get_journal_entry")
		if typeof(raw_entry) == TYPE_DICTIONARY:
			entry = raw_entry
	if entry.is_empty():
		_set_label_text(_quest_title, "")
		_set_label_text(_quest_status, "")
		_set_label_text(_quest_objective, owner._text("MENU_QUEST_EMPTY"))
		return
	var title_key: String = str(entry.get("title_key", ""))
	var objective_key: String = str(entry.get("objective_key", ""))
	var params: Dictionary = entry.get("params", {})
	var completed: bool = bool(entry.get("completed", false))
	_set_label_text(_quest_title, owner._text(title_key, params) if title_key != "" else "")
	_set_label_text(_quest_status, owner._text("MENU_QUEST_COMPLETED" if completed else "MENU_QUEST_ACTIVE"))
	_set_label_text(_quest_objective, owner._text(objective_key, params) if objective_key != "" else owner._text("MENU_QUEST_EMPTY"))


func _set_label_text(label: Label, text: String) -> void:
	if is_instance_valid(label):
		label.text = text


func _tab_id(button: Button) -> String:
	return "items" if button == _items_tab else "quests"
