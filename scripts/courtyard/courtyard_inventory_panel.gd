class_name CourtyardInventoryPanel
extends PanelContainer
## Courtyard inventory panel: read-only view of the pocket inventory.
## Layout is owned by the scene; this script only fills text and styles.

signal close_requested()

const NAME_KEYS := {
	"rusty_sword": "ITEM_RUSTY_SWORD_NAME",
	"iron_sword": "ITEM_IRON_SWORD_NAME",
	"cultist_blade": "ITEM_CULTIST_BLADE_NAME",
	"leather_armor": "ITEM_LEATHER_ARMOR_NAME",
	"chain_mail": "ITEM_CHAIN_MAIL_NAME",
	"health_potion": "ITEM_HEALTH_POTION_NAME",
	"stamina_potion": "ITEM_STAMINA_POTION_NAME",
	"bread": "ITEM_BREAD_NAME",
	"sacred_ash": "ITEM_SACRED_ASH_NAME",
}

const LANGUAGES: Array[String] = ["auto", "en", "ru"]
const LANGUAGE_LABEL_KEYS := {
	"auto": "UI_LANGUAGE_AUTO",
	"en": "LOC_LANGUAGE_ENGLISH",
	"ru": "LOC_LANGUAGE_RUSSIAN",
}

var _dirty := true
var _suppress_language_selection := false
var _close_touch_index := -1

@onready var _title: Label = %Title
@onready var _close_button: Button = %CloseButton
@onready var _source: Label = %Source
@onready var _empty: Label = %Empty
@onready var _items: ItemList = %Items
@onready var _coins: Label = %Coins
@onready var _language_label: Label = %LanguageLabel
@onready var _language_choice: OptionButton = %LanguageChoice
@onready var _settings_error: Label = %SettingsError


func _ready() -> void:
	_apply_style()
	_connect_signals()
	_populate_language_choices()
	refresh_contents()
	visible = false


func open_panel() -> void:
	refresh_contents()
	visible = true


func close_panel() -> void:
	_close_touch_index = -1
	visible = false


func refresh_contents() -> void:
	if not is_inside_tree():
		return
	_title.text = Localization.text("INV_TITLE")
	_close_button.text = Localization.text("UI_CLOSE")
	_source.text = Localization.text("INV_SOURCE_POCKET")
	_empty.text = Localization.text("INV_EMPTY")
	_language_label.text = Localization.text("UI_LANGUAGE")
	if _settings_error.visible:
		_settings_error.text = Localization.text("INV_SETTINGS_FAILURE")
	_refresh_language_choices()
	_rebuild_items()


func _process(_delta: float) -> void:
	if not visible or not _dirty:
		return
	_dirty = false
	refresh_contents()


func _connect_signals() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_close_button.gui_input.connect(_on_close_button_gui_input)
	_language_choice.item_selected.connect(_on_language_selected)
	_items.item_activated.connect(_on_item_activated)
	Localization.language_changed.connect(_on_language_changed)
	Inventory.item_added.connect(_on_inventory_dirty)
	Inventory.item_removed.connect(_on_inventory_dirty)
	Inventory.item_equipped.connect(_on_inventory_dirty)
	Inventory.item_unequipped.connect(_on_inventory_dirty)
	Inventory.gold_changed.connect(_on_inventory_dirty)
	Inventory.inventory_restored.connect(_on_inventory_dirty)


func _rebuild_items() -> void:
	var save_data: Variant = Inventory.get_save_data()
	var items: Array = []
	var equipped: Dictionary = {}
	var gold := 0
	if typeof(save_data) == TYPE_DICTIONARY:
		var data: Dictionary = save_data
		var raw_items: Variant = data.get("items", [])
		if typeof(raw_items) == TYPE_ARRAY:
			for entry in raw_items:
				if typeof(entry) == TYPE_DICTIONARY:
					items.append(entry)
		var raw_equipped: Variant = data.get("equipped", {})
		if typeof(raw_equipped) == TYPE_DICTIONARY:
			equipped = raw_equipped
		var raw_gold: Variant = data.get("gold", 0)
		if typeof(raw_gold) == TYPE_INT:
			gold = raw_gold

	_items.clear()
	var row_count := 0
	for entry in items:
		var item: Dictionary = entry
		var line := _format_item_row(item)
		if line.is_empty():
			continue
		_items.add_item(line)
		row_count += 1
	var slot_keys: Array = equipped.keys()
	slot_keys.sort()
	for slot in slot_keys:
		var slot_item: Variant = equipped[slot]
		if typeof(slot_item) != TYPE_DICTIONARY:
			continue
		var line := _format_equipped_row(slot_item)
		if line.is_empty():
			continue
		_items.add_item(line)
		row_count += 1

	_empty.visible = row_count == 0
	_coins.text = Localization.text("INV_GOLD", {"amount": str(gold)})


func _format_item_row(item: Dictionary) -> String:
	var name := _translate_item_name(item)
	if name.is_empty():
		return ""
	var quantity: Variant = item.get("quantity", 1)
	var count := 1
	if typeof(quantity) == TYPE_INT:
		count = quantity
	return Localization.text("INV_ROW", {"name": name, "count": str(count)})


func _format_equipped_row(slot_item: Dictionary) -> String:
	var name := _translate_item_name(slot_item)
	if name.is_empty():
		return ""
	return Localization.text("INV_EQUIPPED_ROW", {"name": name})


func _translate_item_name(item: Dictionary) -> String:
	var raw_id: Variant = item.get("id", "")
	var item_id := str(raw_id)
	var key: String = NAME_KEYS.get(item_id, "")
	if key.is_empty():
		return Localization.text("INV_UNKNOWN_ITEM")
	return Localization.text(key)


func _populate_language_choices() -> void:
	_suppress_language_selection = true
	_language_choice.clear()
	for lang in LANGUAGES:
		_language_choice.add_item(Localization.text(LANGUAGE_LABEL_KEYS[lang]))
	_suppress_language_selection = false
	_refresh_language_choices()


func _refresh_language_choices() -> void:
	_suppress_language_selection = true
	for i in LANGUAGES.size():
		_language_choice.set_item_text(i, Localization.text(LANGUAGE_LABEL_KEYS[LANGUAGES[i]]))
	var preference := Localization.get_preference()
	var index := LANGUAGES.find(preference)
	if index < 0:
		index = 0
	_language_choice.select(index)
	_suppress_language_selection = false


func _on_close_pressed() -> void:
	close_requested.emit()


func _on_item_activated(_index: int) -> void:
	# Read-only list: selection must not mutate items.
	pass


func _on_language_selected(index: int) -> void:
	if _suppress_language_selection:
		return
	if index < 0 or index >= LANGUAGES.size():
		return
	var preference := LANGUAGES[index]
	var error := Localization.set_language(preference)
	if error != OK:
		_settings_error.text = Localization.text("INV_SETTINGS_FAILURE")
		_settings_error.visible = true
		_refresh_language_choices()
	else:
		_settings_error.visible = false
		refresh_contents()


func _on_language_changed(_language: String) -> void:
	_dirty = true


func _on_inventory_dirty(_a: Variant = null, _b: Variant = null) -> void:
	_dirty = true


func _on_close_button_gui_input(event: InputEvent) -> void:
	var close_rect := Rect2(Vector2.ZERO, _close_button.size)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _close_touch_index < 0 and close_rect.has_point(touch.position):
				_close_touch_index = touch.index
		elif touch.index == _close_touch_index:
			_close_touch_index = -1
			if not touch.canceled and close_rect.has_point(touch.position):
				close_requested.emit()
		_close_button.accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _close_touch_index and not close_rect.has_point(drag.position):
			_close_touch_index = -1
		_close_button.accept_event()
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			if _close_touch_index >= 0 and not close_rect.has_point(event.position):
				_close_touch_index = -1
			_close_button.accept_event()
	elif event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			_close_button.accept_event()


func _apply_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.13, 0.12, 0.11)
	panel_style.border_color = Color(0.62, 0.52, 0.3, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	panel_style.content_margin_left = 24.0
	panel_style.content_margin_right = 24.0
	panel_style.content_margin_top = 20.0
	panel_style.content_margin_bottom = 20.0
	add_theme_stylebox_override("panel", panel_style)

	var theme := Theme.new()
	theme.default_font_size = 26
	theme.set_color("font_color", "Label", Color(0.93, 0.89, 0.8))
	theme.set_color("font_color", "Button", Color(0.93, 0.89, 0.8))
	theme.set_color("font_color", "OptionButton", Color(0.93, 0.89, 0.8))
	theme.set_color("font_color", "ItemList", Color(0.93, 0.89, 0.8))

	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.2, 0.18, 0.15)
	close_style.border_color = Color(0.62, 0.52, 0.3, 0.85)
	close_style.set_border_width_all(1)
	close_style.set_corner_radius_all(10)
	var close_hover := close_style.duplicate() as StyleBoxFlat
	close_hover.bg_color = Color(0.26, 0.23, 0.19)
	_close_button.add_theme_stylebox_override("normal", close_style)
	_close_button.add_theme_stylebox_override("hover", close_hover)
	_close_button.add_theme_stylebox_override("pressed", close_hover)

	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(0.1, 0.095, 0.085)
	list_style.border_color = Color(0.62, 0.52, 0.3, 0.4)
	list_style.set_border_width_all(1)
	list_style.set_corner_radius_all(8)
	_items.add_theme_stylebox_override("panel", list_style)

	var choice_style := StyleBoxFlat.new()
	choice_style.bg_color = Color(0.2, 0.18, 0.15)
	choice_style.border_color = Color(0.62, 0.52, 0.3, 0.85)
	choice_style.set_border_width_all(1)
	choice_style.set_corner_radius_all(10)
	_language_choice.add_theme_stylebox_override("normal", choice_style)

	_title.add_theme_font_size_override("font_size", 32)
	_apply_theme_recursive(self, theme)


func _apply_theme_recursive(node: Node, theme: Theme) -> void:
	if node is Control:
		node.theme = theme
	for child in node.get_children():
		_apply_theme_recursive(child, theme)
