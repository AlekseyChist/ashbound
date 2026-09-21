extends PanelContainer
## Touch-first inventory panel for the courtyard.
## Nearly fullscreen, illustrated grid, real touch drag & drop.
## Four equipment slots: armor (complete outfit), weapon, backpack, pouch.

const GestureScript = preload("res://scripts/courtyard/inventory_touch_gesture.gd")
const MenuSections = preload("res://scripts/courtyard/courtyard_menu_sections.gd")

var _gesture_handler: RefCounted = null
var _sections: RefCounted = null

signal close_requested()

const ATLAS_PATH := preload("res://assets/ui/inventory/items-v1.png")
const POCKET_TEX := preload("res://assets/ui/inventory/pocket-v1.png")
const BACKPACK_TEX := preload("res://assets/ui/inventory/backpack-v1.png")
const POUCH_TEX := preload("res://assets/ui/inventory/pouch-v1.png")
const MAP_TEX := preload("res://assets/ui/maps/courtyard-sketch-v1.png")
const TRAVELER_FRAMES := preload("res://assets/characters/courtyard/traveler_frames.tres")

const ITEM_IDS := [
	"rusty_sword", "iron_sword", "cultist_blade",
	"leather_armor", "chain_mail", "bread",
	"health_potion", "stamina_potion", "sacred_ash",
]

const QUICK_SLOT_COUNT := 10
const TOUCH_HOLD_TIME := 0.25
const MOUSE_DRAG_THRESHOLD := 12.0
const SCROLL_CANCEL_PX := 16.0
const GHOST_OFFSET := Vector2(0, -160)
const MAX_VISIBLE_CELLS := 100

# Colors
const COLOR_PANEL := Color(0.13, 0.12, 0.11, 1.0)
const COLOR_PANEL_DARK := Color(0.09, 0.085, 0.08, 1.0)
const COLOR_BRONZE := Color(0.62, 0.47, 0.22, 1.0)
const COLOR_BRONZE_DIM := Color(0.38, 0.30, 0.15, 1.0)
const COLOR_GOLD := Color(0.92, 0.78, 0.35, 1.0)
const COLOR_GREEN := Color(0.45, 0.72, 0.45, 1.0)
const COLOR_MUTED := Color(0.55, 0.53, 0.5, 1.0)
const COLOR_TEXT := Color(0.88, 0.85, 0.78, 1.0)

var _inventory: Node = null
var _localization: Node = null
var _atlas_texture: Texture2D = null
var _traveler_frames: SpriteFrames = null

# UI refs
var _title: Label
var _coins: Label
var _close_button: Button
var _character_preview: TextureRect
var _armor_label: Label
var _armor_slot: Button
var _weapon_label: Label
var _weapon_slot: Button
var _backpack_label: Label
var _backpack_slot: Button
var _pouch_label: Label
var _pouch_slot: Button
var _storage_tabs: HBoxContainer
var _item_scroll: ScrollContainer
var _item_grid: GridContainer
var _item_details: Label
var _empty_label: Label
var _quick_label: Label
var _quick_slots: HBoxContainer
var _hint: Label
var _language_choice: OptionButton
var _settings_error: Label
var _drop_button: Button

# State
var _selected_item_id: String = ""
var _current_container: String = ""
var _quick_bindings: Array[String] = []
var _tab_buttons: Dictionary = {}  # container id -> Button
var _cell_nodes: Array[Control] = []
var _quick_cells: Array[Button] = []

# Drag state
enum DragMode { NONE, PENDING, ACTIVE }
var _drag_mode: int = DragMode.NONE
var _drag_source: Dictionary = {}  # {kind: "item"/"equip"/"worn", id, slot, container}
var _press_target_id: String = ""
var _press_position: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _active_pointers: Dictionary = {}  # pointer_id -> true
var _gesture_cancelled := false
var _ghost: TextureRect
var _highlighted_targets: Array[Control] = []

func _ready() -> void:
	_inventory = get_node_or_null("/root/Inventory")
	_localization = get_node_or_null("/root/Localization")
	_atlas_texture = ATLAS_PATH
	_traveler_frames = TRAVELER_FRAMES
	_quick_bindings.resize(QUICK_SLOT_COUNT)
	for i in QUICK_SLOT_COUNT:
		_quick_bindings[i] = ""

	_title = $Margin/RootVBox/Header/Title
	_coins = $Margin/RootVBox/Header/Coins
	_close_button = $Margin/RootVBox/Header/CloseButton
	_character_preview = $Margin/RootVBox/Body/Left/CharacterPreview
	_armor_label = $Margin/RootVBox/Body/Left/EquipmentGrid/ArmorColumn/ArmorLabel
	_armor_slot = $Margin/RootVBox/Body/Left/EquipmentGrid/ArmorColumn/ArmorSlot
	_weapon_label = $Margin/RootVBox/Body/Left/EquipmentGrid/WeaponColumn/WeaponLabel
	_weapon_slot = $Margin/RootVBox/Body/Left/EquipmentGrid/WeaponColumn/WeaponSlot
	_backpack_label = $Margin/RootVBox/Body/Left/EquipmentGrid/BackpackColumn/BackpackLabel
	_backpack_slot = $Margin/RootVBox/Body/Left/EquipmentGrid/BackpackColumn/BackpackSlot
	_pouch_label = $Margin/RootVBox/Body/Left/EquipmentGrid/PouchColumn/PouchLabel
	_pouch_slot = $Margin/RootVBox/Body/Left/EquipmentGrid/PouchColumn/PouchSlot
	_storage_tabs = $Margin/RootVBox/Body/Right/StorageTabs
	_item_scroll = $Margin/RootVBox/Body/Right/ItemScroll
	_item_grid = $Margin/RootVBox/Body/Right/ItemScroll/ItemGrid
	_item_details = $Margin/RootVBox/Body/Right/ItemDetails
	_empty_label = $Margin/RootVBox/Body/Right/Empty
	_quick_label = $Margin/RootVBox/QuickLabel
	_quick_slots = $Margin/RootVBox/QuickSlots
	_hint = $Margin/RootVBox/Footer/Hint
	_language_choice = $Margin/RootVBox/Footer/LanguageChoice
	_settings_error = %SettingsError

	_apply_styles()
	_setup_character_preview()
	_setup_equipment_slots()
	_setup_quick_slots()
	_setup_language_choice()
	_setup_drop_action()
	_refresh_labels()

	if _inventory:
		_inventory.item_added.connect(_on_item_changed)
		_inventory.item_removed.connect(_on_item_changed)
		_inventory.item_equipped.connect(_on_item_changed)
		_inventory.item_unequipped.connect(_on_item_changed)
		_inventory.gold_changed.connect(_on_gold_changed)
		_inventory.inventory_restored.connect(_on_inventory_restored)
		_inventory.storage_changed.connect(_on_storage_changed)

	if _localization and _localization.has_signal("language_changed"):
		_localization.language_changed.connect(_on_language_changed)

	# Ghost for drag preview.
	_ghost = TextureRect.new()
	_ghost.z_index = 100
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ghost.visible = false
	add_child(_ghost)

	_gesture_handler = GestureScript.new(self)
	_ghost.set_as_top_level(true)
	_ghost.size = Vector2(140, 140)
	_sections = MenuSections.new(self)
	refresh_contents()
	visible = false


func open_panel() -> void:
	_reset_gesture()
	_selected_item_id = ""
	_settings_error.visible = false
	if _sections:
		_sections.select_section("items")
	refresh_contents()
	visible = true


func close_panel() -> void:
	_reset_gesture()
	_selected_item_id = ""
	visible = false


func refresh_contents() -> void:
	_refresh_labels()
	_rebuild_tabs()
	_rebuild_grid()
	_rebuild_equipment()
	_rebuild_quick_slots()
	_update_details()


# ---------------------------------------------------------------------------
# Styling
# ---------------------------------------------------------------------------

func _apply_styles() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.set_border_color(COLOR_BRONZE)
	panel_style.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", panel_style)

	var dark_style := StyleBoxFlat.new()
	dark_style.bg_color = COLOR_PANEL_DARK
	dark_style.border_width_left = 2
	dark_style.border_width_top = 2
	dark_style.border_width_right = 2
	dark_style.border_width_bottom = 2
	dark_style.set_border_color(COLOR_BRONZE_DIM)
	dark_style.set_corner_radius_all(6)

	for label in [_title, _coins, _armor_label, _weapon_label, _backpack_label, _pouch_label, _item_details, _empty_label, _quick_label, _hint]:
		if label:
			label.add_theme_color_override("font_color", COLOR_TEXT)

	_close_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_button.add_theme_stylebox_override("normal", dark_style)
	_close_button.add_theme_stylebox_override("hover", dark_style)
	_close_button.add_theme_stylebox_override("pressed", dark_style)
	_close_button.add_theme_color_override("font_color", COLOR_TEXT)

	for slot in [_armor_slot, _weapon_slot, _backpack_slot, _pouch_slot]:
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("normal", dark_style)
		slot.add_theme_stylebox_override("hover", dark_style)
		slot.add_theme_stylebox_override("pressed", dark_style)
		slot.add_theme_color_override("font_color", COLOR_TEXT)


func _make_cell_style(selected: bool, valid: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_DARK if not selected else Color(0.16, 0.15, 0.12, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	if valid:
		style.set_border_color(COLOR_GREEN)
	elif selected:
		style.set_border_color(COLOR_GOLD)
	else:
		style.set_border_color(COLOR_BRONZE_DIM)
	style.set_corner_radius_all(6)
	return style


# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

func _setup_character_preview() -> void:
	if _traveler_frames and _traveler_frames.has_method("get_frame_texture"):
		var tex: Texture2D = _traveler_frames.get_frame_texture("idle_front", 0)
		if tex:
			_character_preview.texture = tex


func _setup_equipment_slots() -> void:
	_armor_slot.pressed.connect(_on_armor_slot_tapped)
	_weapon_slot.pressed.connect(_on_weapon_slot_tapped)
	_backpack_slot.pressed.connect(_on_backpack_slot_tapped)
	_pouch_slot.pressed.connect(_on_pouch_slot_tapped)


func _setup_quick_slots() -> void:
	for i in QUICK_SLOT_COUNT:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(min(140, 110), 110)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 70)
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_theme_font_size_override("font_size", 28)
		btn.add_theme_color_override("font_color", COLOR_TEXT)
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_PANEL_DARK
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.set_border_color(COLOR_BRONZE_DIM)
		style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.pressed.connect(_on_quick_slot_tapped.bind(i))
		_quick_slots.add_child(btn)
		_quick_cells.append(btn)


func _setup_language_choice() -> void:
	_language_choice.clear()
	_language_choice.add_item(_text("UI_LANGUAGE_AUTO"), 0)
	_language_choice.add_item(_text("LOC_LANGUAGE_ENGLISH"), 1)
	_language_choice.add_item(_text("LOC_LANGUAGE_RUSSIAN"), 2)
	if _localization and _localization.has_method("get_preference"):
		var pref: String = _localization.get_preference()
		match pref:
			"en": _language_choice.select(1)
			"ru": _language_choice.select(2)
			_: _language_choice.select(0)
	if not _language_choice.item_selected.is_connected(_on_language_selected):
		_language_choice.item_selected.connect(_on_language_selected)


func _on_language_selected(index: int) -> void:
	if not _localization or not _localization.has_method("set_language"):
		return
	var code := ""
	match index:
		1: code = "en"
		2: code = "ru"
		_: code = "auto"
	var result: Error = _localization.set_language(code)
	if result != OK:
		_settings_error.text = _text("INV_SETTINGS_FAILURE")
		_settings_error.visible = true
	else:
		_settings_error.visible = false


# ---------------------------------------------------------------------------
# Labels / localization
# ---------------------------------------------------------------------------

func _text(key: String, params: Dictionary = {}) -> String:
	if _localization and _localization.has_method("text"):
		return _localization.text(key, params)
	return key


func _setup_drop_action() -> void:
	_drop_button = Button.new()
	_drop_button.name = "DropItem"
	_drop_button.custom_minimum_size = Vector2(190, 90)
	_drop_button.add_theme_font_size_override("font_size", 30)
	_drop_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_button.focus_mode = Control.FOCUS_NONE

	var normal_style := _make_cell_style(false, false)
	normal_style.set_border_color(COLOR_BRONZE)
	normal_style.bg_color = COLOR_PANEL_DARK
	normal_style.content_margin_left = 16.0
	normal_style.content_margin_right = 16.0
	normal_style.content_margin_top = 8.0
	normal_style.content_margin_bottom = 8.0

	var hover_style := _make_cell_style(true, false)
	hover_style.content_margin_left = 16.0
	hover_style.content_margin_right = 16.0
	hover_style.content_margin_top = 8.0
	hover_style.content_margin_bottom = 8.0

	var pressed_style := _make_cell_style(true, false)
	pressed_style.content_margin_left = 16.0
	pressed_style.content_margin_right = 16.0
	pressed_style.content_margin_top = 8.0
	pressed_style.content_margin_bottom = 8.0

	var disabled_style := _make_cell_style(false, false)
	disabled_style.set_border_color(COLOR_BRONZE_DIM)
	disabled_style.bg_color = COLOR_PANEL_DARK
	disabled_style.content_margin_left = 16.0
	disabled_style.content_margin_right = 16.0
	disabled_style.content_margin_top = 8.0
	disabled_style.content_margin_bottom = 8.0

	_drop_button.add_theme_stylebox_override("normal", normal_style)
	_drop_button.add_theme_stylebox_override("hover", hover_style)
	_drop_button.add_theme_stylebox_override("pressed", pressed_style)
	_drop_button.add_theme_stylebox_override("disabled", disabled_style)
	_drop_button.add_theme_color_override("font_color", COLOR_TEXT)
	_drop_button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	_drop_button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	_drop_button.add_theme_color_override("font_disabled_color", COLOR_MUTED)

	var footer: Node = $Margin/RootVBox/Footer
	var lang_index := footer.get_node_or_null("LanguageChoice").get_index()
	footer.add_child(_drop_button)
	footer.move_child(_drop_button, lang_index)


func _world_items() -> Node:
	var node: Node = self
	while node != null:
		var manager := node.get_node_or_null("WorldItems")
		if manager:
			return manager
		node = node.get_parent()
	return null

func can_drop_instance(iid: String) -> bool:
	if iid.is_empty():
		return false
	if not _inventory or not _inventory.has_method("get_item_rules"):
		return false
	var rules:Dictionary = _inventory.get_item_rules({"instance_id": iid})
	if not (rules is Dictionary):
		return false
	if not rules.get("droppable", false):
		return false
	var storage:String = _inventory.get_item_storage(iid)
	if not (storage is String) or storage == "":
		return false
	if _world_items() == null:
		return false
	return true


func drop_instance(iid: String) -> bool:
	var manager := _world_items()
	if iid.is_empty() or manager == null or not can_drop_instance(iid):
		_flash_error()
		return false
	var result: bool = manager.drop_item({"instance_id": iid})
	if not result:
		_flash_error()
	else:
		_selected_item_id = ""
		refresh_contents()
	return result


func _refresh_drop_action() -> void:
	if _drop_button == null:
		return
	_drop_button.text = _text("INV_DROP_ITEM")
	_drop_button.disabled = not can_drop_instance(_selected_item_id)
	_drop_button.tooltip_text = ""
	if not _selected_item_id.is_empty():
		var rules:Dictionary = _inventory.get_item_rules({ "instance_id": _selected_item_id })
		if bool(rules.get("quest_locked", false)):
			_drop_button.tooltip_text = _text("INV_DROP_QUEST_LOCKED")
		elif not rules.is_empty() and _inventory.get_item_storage(_selected_item_id) == "":
			_drop_button.tooltip_text = _text("INV_DROP_UNEQUIP_FIRST")


func _refresh_labels() -> void:
	if _drop_button != null:
		_refresh_drop_action()
	_title.text = _text("INV_TITLE")
	_coins.text = _text("INV_GOLD", {"amount": str(_get_gold())})
	_close_button.text = _text("UI_CLOSE")
	_armor_label.text = _text("TOUCH_ARMOR_SET")
	_weapon_label.text = _text("TOUCH_WEAPON")
	_backpack_label.text = _text("TOUCH_BACKPACK")
	_pouch_label.text = _text("TOUCH_POUCH")
	_quick_label.text = _text("TOUCH_QUICK_LABEL")
	_hint.text = _text("TOUCH_DRAG_HINT")
	_empty_label.text = _text("INV_EMPTY")
	if _sections:
		_sections.refresh()


func _on_language_changed(_language: String) -> void:
	_reset_gesture()
	_setup_language_choice()
	refresh_contents()


# ---------------------------------------------------------------------------
# Inventory data access
# ---------------------------------------------------------------------------

func _get_gold() -> int:
	if not _inventory or not _inventory.has_method("get_save_data"):
		return 0
	var data: Dictionary = _inventory.get_save_data()
	return int(data.get("gold", 0))


func _get_equipped() -> Dictionary:
	if not _inventory or not _inventory.has_method("get_save_data"):
		return {}
	var data: Dictionary = _inventory.get_save_data()
	var eq: Dictionary = data.get("equipped", {})
	return eq if eq is Dictionary else {}


func _get_containers() -> Array:
	if not _inventory or not _inventory.has_method("get_storage_containers"):
		return []
	var c: Array = _inventory.get_storage_containers()
	return c if c is Array else []


func _get_items_in_container(container_id: String) -> Array:
	var result: Array = []
	if not _inventory or not _inventory.has_method("get_save_data"):
		return result
	var data: Dictionary = _inventory.get_save_data()
	for item in data.get("items", []):
		if not (item is Dictionary):
			continue
		var iid: String = str(item.get("instance_id", ""))
		if _inventory.get_item_storage(iid) == container_id:
			result.append(item)
	return result


func _get_worn_kind(kind: String) -> Dictionary:
	if not _inventory or not _inventory.has_method("get_worn_storage"):
		return {}
	var d: Dictionary = _inventory.get_worn_storage(kind)
	return d if d is Dictionary else {}


# ---------------------------------------------------------------------------
# Storage tabs
# ---------------------------------------------------------------------------

func _rebuild_tabs() -> void:
	for child in _storage_tabs.get_children():
		_storage_tabs.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()

	var containers := _get_containers()
	var seen_kinds := {}
	var default_id := ""

	for c in containers:
		if not (c is Dictionary):
			continue
		var id: String = str(c.get("id", ""))
		var kind: String = str(c.get("kind", ""))
		if id.is_empty():
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 140)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 90)
		btn.add_theme_font_size_override("font_size", 28)
		btn.add_theme_color_override("font_color", COLOR_TEXT)
		var tex := _container_texture(kind)
		if tex:
			btn.icon = tex
		btn.text = _container_label(id, kind, seen_kinds)
		seen_kinds[kind] = int(seen_kinds.get(kind, 0)) + 1
		btn.pressed.connect(_on_tab_tapped.bind(id))
		_storage_tabs.add_child(btn)
		_tab_buttons[id] = btn
		if default_id.is_empty() and kind == "pocket":
			default_id = id

	var known_kinds := ["pocket", "backpack", "pouch"]
	for kind in known_kinds:
		if not seen_kinds.has(kind):
			var ph := Button.new()
			ph.disabled = true
			ph.custom_minimum_size = Vector2(0, 140)
			ph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ph.expand_icon = true
			ph.add_theme_constant_override("icon_max_width", 90)
			ph.add_theme_font_size_override("font_size", 28)
			ph.add_theme_color_override("font_color", COLOR_TEXT)
			var tex := _container_texture(kind)
			if tex:
				ph.icon = tex
			ph.text = _container_label("", kind, {}) + "\n" + _text("TOUCH_NOT_WORN")
			ph.modulate = Color(0.5, 0.5, 0.5, 1.0)
			_storage_tabs.add_child(ph)

	if default_id.is_empty():
		for c in containers:
			if c is Dictionary and str(c.get("id", "")) != "":
				default_id = str(c.get("id", ""))
				break

	if _current_container.is_empty() or not _tab_buttons.has(_current_container):
		_current_container = default_id

	for id in _tab_buttons:
		var btn: Button = _tab_buttons[id]
		var style := _make_cell_style(id == _current_container, false)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)


func _container_label(id: String, kind: String, seen: Dictionary) -> String:
	var base := ""
	match kind:
		"pocket": base = _text("TOUCH_POCKET")
		"backpack": base = _text("TOUCH_BACKPACK")
		"pouch": base = _text("TOUCH_POUCH")
		_: base = _text("INV_UNKNOWN_ITEM")
	var count: int = 0
	if seen.has(kind):
		count = int(seen[kind])
	if count > 0:
		base += " %d" % (count + 1)
	if id == "":
		return base
	for container in _get_containers():
		if container.get("id", "") == id:
			var used: int = int(container.get("used", 0))
			var capacity: int = int(container.get("capacity", 0))
			return "%s\n%d/%d" % [base, used, capacity]
	return base


func _container_texture(kind: String) -> Texture2D:
	match kind:
		"pocket": return POCKET_TEX
		"backpack": return BACKPACK_TEX
		"pouch": return POUCH_TEX
		_: return null


func _on_tab_tapped(container_id: String) -> void:
	if not _tab_buttons.has(container_id):
		return
	_current_container = container_id
	_selected_item_id = ""
	_rebuild_tabs()
	_rebuild_grid()
	_update_details()


# ---------------------------------------------------------------------------
# Item grid
# ---------------------------------------------------------------------------

func _rebuild_grid() -> void:
	for child in _item_grid.get_children():
		_item_grid.remove_child(child)
		child.queue_free()
	_cell_nodes.clear()

	var items := _get_items_in_container(_current_container)
	var capacity := 0
	for c in _get_containers():
		if c is Dictionary and str(c.get("id", "")) == _current_container:
			capacity = int(c.get("capacity", 0))
			break

	var count := mini(capacity, MAX_VISIBLE_CELLS)

	# Map instance_id -> item data, keyed by its configured storage cell.
	var by_cell := {}
	for item in items:
		if not (item is Dictionary):
			continue
		var iid: String = str(item.get("instance_id", ""))
		if iid == "":
			continue
		var cell_index := -1
		if _inventory != null and _inventory.has_method("get_item_cell"):
			cell_index = int(_inventory.get_item_cell(iid))
		if cell_index >= 0:
			by_cell[cell_index] = item

	for i in count:
		var cell := _make_item_cell(180.0)
		cell.set_meta("cell_index", i)
		var item: Dictionary = by_cell.get(i, {})
		if not item.is_empty():
			var iid: String = str(item.get("instance_id", ""))
			cell.set_meta("item_id", iid)
			cell.set_meta("item_data", item)
			_populate_cell(cell, item)
		else:
			cell.set_meta("item_id", "")
			cell.set_meta("item_data", {})
			_apply_cell_style(cell, false, false)
		_item_grid.add_child(cell)
		_cell_nodes.append(cell)

	_empty_label.visible = items.is_empty()


func _make_item_cell(size: float) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(180, 160)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _make_cell_style(false, false)
	if style != null:
		cell.add_theme_stylebox_override("panel", style)
	return cell


func _populate_cell(cell: Control, item: Dictionary) -> void:
	var iid: String = str(item.get("instance_id", ""))
	var id: String = str(item.get("id", ""))
	var qty: int = int(item.get("quantity", 1))

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(overlay)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = _item_texture(id)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 12.0
	icon.offset_top = 12.0
	icon.offset_right = -12.0
	icon.offset_bottom = -12.0
	overlay.add_child(icon)

	if qty > 1:
		var qty_label := Label.new()
		qty_label.text = str(qty)
		qty_label.add_theme_font_size_override("font_size", 28)
		qty_label.add_theme_color_override("font_color", COLOR_GOLD)
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		qty_label.offset_left = -60.0
		qty_label.offset_top = -42.0
		qty_label.offset_right = -10.0
		qty_label.offset_bottom = -6.0
		overlay.add_child(qty_label)

	_apply_cell_style(cell, iid == _selected_item_id, false)


func _apply_cell_style(cell: Control, selected: bool, valid: bool) -> void:
	if cell is PanelContainer:
		cell.add_theme_stylebox_override("panel", _make_cell_style(selected, valid))


func _item_texture(id: String) -> Texture2D:
	if id == "traveler_backpack":
		return BACKPACK_TEX
	if id == "belt_pouch":
		return POUCH_TEX
	if id == "courtyard_sketch":
		return MAP_TEX
	if not _atlas_texture:
		return null
	var idx := ITEM_IDS.find(id)
	if idx < 0:
		return null
	var cell_size := float(_atlas_texture.get_width()) / 3.0
	var at := AtlasTexture.new()
	at.atlas = _atlas_texture
	var col := idx % 3
	var row := floori(idx / 3.0)
	at.region = Rect2(Vector2(col * cell_size, row * cell_size), Vector2(cell_size, cell_size))
	at.filter_clip = true
	return at


func _item_name(id: String) -> String:
	var key := "ITEM_%s_NAME" % id.to_upper()
	var text := _text(key)
	if text == key:
		return _text("INV_UNKNOWN_ITEM")
	return text


# ---------------------------------------------------------------------------
# Equipment slots
# ---------------------------------------------------------------------------

func _rebuild_equipment() -> void:
	var eq := _get_equipped()
	_populate_equip_slot(_armor_slot, "armor", eq.get("armor"))
	_populate_equip_slot(_weapon_slot, "weapon", eq.get("weapon"))
	_populate_worn_bag_slot(_backpack_slot, "backpack")
	_populate_worn_bag_slot(_pouch_slot, "pouch")


func _populate_equip_slot(slot: Button, slot_name: String, item) -> void:
	slot.set_meta("equip_slot", slot_name)
	if item is Dictionary and not item.is_empty():
		var id: String = str(item.get("id", ""))
		slot.icon = _item_texture(id)
		slot.modulate = Color.WHITE
	else:
		match slot_name:
			"armor":
				slot.icon = _item_texture("leather_armor")
			"weapon":
				slot.icon = _item_texture("rusty_sword")
			_:
				slot.icon = null
		slot.modulate = Color(1, 1, 1, 0.25)
	slot.text = ""


func _populate_worn_bag_slot(slot: Button, kind: String) -> void:
	slot.set_meta("equip_slot", "worn_" + kind)
	var worn := _get_worn_kind(kind)
	if not worn.is_empty():
		var id: String = str(worn.get("id", ""))
		slot.icon = _item_texture(id)
		slot.tooltip_text = _item_name(id)
		slot.modulate = Color.WHITE
	else:
		slot.icon = _container_texture(kind)
		slot.tooltip_text = ""
		slot.modulate = Color(1, 1, 1, 0.4)
	slot.text = ""


func _on_armor_slot_tapped() -> void:
	_try_unequip("armor")


func _on_weapon_slot_tapped() -> void:
	_try_unequip("weapon")


func _on_backpack_slot_tapped() -> void:
	_try_unequip_worn("backpack")


func _on_pouch_slot_tapped() -> void:
	_try_unequip_worn("pouch")


func _try_unequip(slot_name: String) -> void:
	if not _inventory or not _inventory.has_method("unequip_slot"):
		return
	var ok: bool = _inventory.unequip_slot(slot_name)
	if not ok:
		_flash_error()


func _try_unequip_worn(kind: String) -> void:
	if not _inventory or not _inventory.has_method("unequip_storage_item"):
		return
	var dest := _current_container
	if dest.is_empty():
		dest = _first_pocket_id()
	var ok: bool = _inventory.unequip_storage_item(kind, dest)
	if not ok:
		_flash_error()


func _first_pocket_id() -> String:
	for c in _get_containers():
		if c is Dictionary and str(c.get("kind", "")) == "pocket":
			return str(c.get("id", ""))
	return ""


# ---------------------------------------------------------------------------
# Quick slots
# ---------------------------------------------------------------------------

func _rebuild_quick_slots() -> void:
	for i in QUICK_SLOT_COUNT:
		var btn: Button = _quick_cells[i]
		btn.text = str((i + 1) % 10)
		var iid := _quick_bindings[i]
		if iid.is_empty():
			btn.icon = null
			continue
		var item := _find_item_by_instance(iid)
		if item.is_empty() or not _inventory.can_assign_quick({"instance_id": iid}):
			_quick_bindings[i] = ""
			btn.icon = null
			continue
		var id: String = str(item.get("id", ""))
		btn.icon = _item_texture(id)


func _find_item_by_instance(instance_id: String) -> Dictionary:
	if not _inventory or not _inventory.has_method("get_save_data"):
		return {}
	var data: Dictionary = _inventory.get_save_data()
	for item in data.get("items", []):
		if item is Dictionary and str(item.get("instance_id", "")) == instance_id:
			return item
	var equipped: Dictionary = data.get("equipped", {})
	for item in equipped.values():
		if item is Dictionary and str(item.get("instance_id", "")) == instance_id:
			return item
	var worn_storage: Dictionary = data.get("worn_storage", {})
	for item in worn_storage.values():
		if item is Dictionary and str(item.get("instance_id", "")) == instance_id:
			return item
	return {}


func activate_quick(index: int) -> bool:
	if index < 0 or index >= QUICK_SLOT_COUNT:
		return false
	var iid := _quick_bindings[index]
	if iid.is_empty():
		return false
	var rules: Dictionary = _inventory.get_item_rules({"instance_id": iid})
	if str(rules.get("quick_action", "")) != "open_map" or not bool(rules.get("quick_bindable", false)):
		return false
	_sections.select_section("map")
	return _sections.current_section == "map"


func _on_quick_slot_tapped(index: int) -> void:
	if index < 0 or index >= QUICK_SLOT_COUNT:
		return
	var bound: String = _quick_bindings[index]
	if not _selected_item_id.is_empty() and _selected_item_id != bound:
		if _inventory.can_assign_quick({"instance_id": _selected_item_id}):
			_quick_bindings[index] = _selected_item_id
			_rebuild_quick_slots()
			return
	if not bound.is_empty():
		if activate_quick(index):
			return
		_selected_item_id = bound if _selected_item_id != bound else ""
		_rebuild_grid()
		_update_details()


# ---------------------------------------------------------------------------
# Details
# ---------------------------------------------------------------------------

func _update_details() -> void:
	_refresh_drop_action()
	if _selected_item_id.is_empty():
		_item_details.text = ""
		return
	var item := _find_item_by_instance(_selected_item_id)
	if item.is_empty():
		_item_details.text = _text("INV_UNKNOWN_ITEM")
		return
	var id: String = str(item.get("id", ""))
	var qty: int = int(item.get("quantity", 1))
	var text := _item_name(id)
	if qty > 1:
		text += " x%d" % qty
	_item_details.text = text


# ---------------------------------------------------------------------------
# Input handling (global, viewport coordinates)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _gesture_handler and _gesture_handler.handle(event):
		get_viewport().set_input_as_handled()

func _reset_gesture() -> void:
	if _gesture_handler:
		_gesture_handler.cancel()
	if _ghost:
		_ghost.visible = false

func _flash_error() -> void:
	_settings_error.text = _text("TOUCH_MOVE_FAILED")
	_settings_error.visible = true

func _on_item_changed(_arg = null, _slot = null) -> void:
	_reset_gesture()
	refresh_contents()


func _on_gold_changed(_amount) -> void:
	_coins.text = _text("INV_GOLD", {"amount": str(_get_gold())})


func _on_inventory_restored() -> void:
	_reset_gesture()
	refresh_contents()


func _on_storage_changed() -> void:
	_reset_gesture()
	_rebuild_tabs()
	_rebuild_grid()
	_rebuild_equipment()
	if _sections:
		_sections.refresh()
