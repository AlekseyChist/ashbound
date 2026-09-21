class_name CourtyardInventoryPanel
extends PanelContainer
## Courtyard inventory panel: single-selection view with whole-stack transfer.
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
var _transfer_touch_index := -1
var _transfer_pressed_instance_id := ""
var _transfer_pressed_target_id := ""
var _list_touch_index := -1
var _list_pressed_row := -1
var _list_touch_start := Vector2.ZERO
var _list_last_drag_position := Vector2.ZERO
var _list_scroll_active := false
var _selected_instance_id := ""
var _selected_is_equipped := false
var _selected_slot := ""
var _selected_container_id := ""
var _selected_quantity := 1
var _selected_name_key := ""
var _transfer_target_id := ""
var _transfer_failed := false

@onready var _title: Label = %Title
@onready var _close_button: Button = %CloseButton
@onready var _source: Label = %Source
@onready var _empty: Label = %Empty
@onready var _items: ItemList = %Items
@onready var _coins: Label = %Coins
@onready var _language_label: Label = %LanguageLabel
@onready var _language_choice: OptionButton = %LanguageChoice
@onready var _settings_error: Label = %SettingsError
@onready var _item_details: Label = %ItemDetails
@onready var _transfer_row: HBoxContainer = %TransferRow
@onready var _transfer_target: OptionButton = %TransferTarget
@onready var _transfer_button: Button = %TransferButton
@onready var _transfer_error: Label = %TransferError


func _ready() -> void:
	_apply_style()
	_connect_signals()
	_populate_language_choices()
	refresh_contents()
	visible = false


func open_panel() -> void:
	_clear_selection()
	_transfer_target_id = ""
	_transfer_failed = false
	_refresh_transfer_error()
	refresh_contents()
	visible = true


func close_panel() -> void:
	_close_touch_index = -1
	_transfer_touch_index = -1
	_transfer_pressed_instance_id = ""
	_transfer_pressed_target_id = ""
	_list_touch_index = -1
	_list_pressed_row = -1
	_list_last_drag_position = Vector2.ZERO
	_list_scroll_active = false
	_clear_selection()
	_transfer_target_id = ""
	_transfer_failed = false
	_refresh_transfer_error()
	visible = false


func refresh_contents() -> void:
	if not is_inside_tree():
		return
	_title.text = Localization.text("INV_TITLE")
	_close_button.text = Localization.text("UI_CLOSE")
	_refresh_source_label()
	_empty.text = Localization.text("INV_EMPTY")
	_language_label.text = Localization.text("UI_LANGUAGE")
	if _settings_error.visible:
		_settings_error.text = Localization.text("INV_SETTINGS_FAILURE")
	_refresh_language_choices()
	_rebuild_items()
	_refresh_details()
	_refresh_transfer_row()
	_refresh_transfer_error()


func _process(_delta: float) -> void:
	if not visible or not _dirty:
		return
	_dirty = false
	refresh_contents()


func _connect_signals() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_close_button.gui_input.connect(_on_close_button_gui_input)
	_language_choice.item_selected.connect(_on_language_selected)
	_items.item_selected.connect(_on_item_selected)
	_items.gui_input.connect(_on_items_gui_input)
	_transfer_target.item_selected.connect(_on_transfer_target_selected)
	_transfer_button.pressed.connect(_on_transfer_pressed)
	_transfer_button.gui_input.connect(_on_transfer_button_gui_input)
	Localization.language_changed.connect(_on_language_changed)
	Inventory.item_added.connect(_on_inventory_dirty)
	Inventory.item_removed.connect(_on_inventory_dirty)
	Inventory.item_equipped.connect(_on_inventory_dirty)
	Inventory.item_unequipped.connect(_on_inventory_dirty)
	Inventory.gold_changed.connect(_on_inventory_dirty)
	Inventory.inventory_restored.connect(_on_inventory_dirty)
	if Inventory.has_signal("storage_changed"):
		Inventory.storage_changed.connect(_on_inventory_dirty)


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

	var containers := _get_storage_containers()
	var multi_container := containers.size() > 1
	_items.clear()
	var row_count := 0
	for entry in items:
		var item: Dictionary = entry
		var line := _format_item_row(item, multi_container)
		if line.is_empty():
			continue
		var instance_id := str(item.get("instance_id", ""))
		var quantity := _item_quantity(item)
		var name_key := _item_name_key(item)
		var container_id := ""
		if not instance_id.is_empty():
			container_id = str(Inventory.get_item_storage(instance_id))
		_items.add_item(line)
		_items.set_item_metadata(row_count, {
			"instance_id": instance_id,
			"equipped": false,
			"slot": "",
			"quantity": quantity,
			"name_key": name_key,
			"container_id": container_id,
		})
		row_count += 1
	var slot_keys: Array = equipped.keys()
	slot_keys.sort()
	for slot in slot_keys:
		var slot_item: Variant = equipped[slot]
		if typeof(slot_item) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = slot_item
		var line := _format_equipped_row(item)
		if line.is_empty():
			continue
		var instance_id := str(item.get("instance_id", ""))
		_items.add_item(line)
		_items.set_item_metadata(row_count, {
			"instance_id": instance_id,
			"equipped": true,
			"slot": str(slot),
			"quantity": _item_quantity(item),
			"name_key": _item_name_key(item),
			"container_id": "",
		})
		row_count += 1

	_empty.visible = row_count == 0
	_coins.text = Localization.text("INV_GOLD", {"amount": str(gold)})
	_reconcile_selection(items, equipped)


func _reconcile_selection(_items_data: Array, _equipped: Dictionary) -> void:
	if _selected_instance_id.is_empty():
		return
	var row_index := -1
	for i in _items.item_count:
		var metadata: Variant = _items.get_item_metadata(i)
		if typeof(metadata) != TYPE_DICTIONARY:
			continue
		if str((metadata as Dictionary).get("instance_id", "")) == _selected_instance_id:
			row_index = i
			break
	if row_index < 0:
		_clear_selection()
		return
	# Re-select the exact rebuilt row and reload all current metadata.
	_select_row(row_index)


func _clear_selection() -> void:
	_selected_instance_id = ""
	_selected_is_equipped = false
	_selected_slot = ""
	_selected_container_id = ""
	_selected_quantity = 1
	_selected_name_key = ""
	_transfer_target_id = ""
	_transfer_failed = false
	_items.deselect_all()
	_refresh_details()
	_refresh_transfer_row()
	_refresh_transfer_error()


func _select_row(index: int) -> void:
	if index < 0 or index >= _items.item_count:
		return
	var metadata: Variant = _items.get_item_metadata(index)
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	var data: Dictionary = metadata
	var previous_identity := _selected_instance_id
	_items.deselect_all()
	_items.select(index)
	_selected_instance_id = str(data.get("instance_id", ""))
	_selected_is_equipped = bool(data.get("equipped", false))
	_selected_slot = str(data.get("slot", ""))
	_selected_container_id = str(data.get("container_id", ""))
	_selected_quantity = int(data.get("quantity", 1))
	_selected_name_key = str(data.get("name_key", ""))
	if _selected_instance_id != previous_identity:
		# A different item was selected: drop stale target/failure state.
		_transfer_target_id = ""
		_transfer_failed = false
	_refresh_details()
	_refresh_transfer_row()
	_refresh_transfer_error()


func _refresh_details() -> void:
	if _selected_instance_id.is_empty():
		_item_details.text = Localization.text("INV_SELECT_ITEM")
		return
	var name := _translate_name_key(_selected_name_key)
	var location := _selected_location_text()
	_item_details.text = Localization.text("INV_ITEM_DETAILS", {
		"name": name,
		"count": str(_selected_quantity),
		"location": location,
	})


func _selected_location_text() -> String:
	if _selected_is_equipped:
		return Localization.text("INV_LOCATION_EQUIPPED")
	var containers := _get_storage_containers()
	for container in containers:
		if str(container.get("id", "")) == _selected_container_id:
			var kind := str(container.get("kind", ""))
			var name_key := _storage_name_key(kind)
			if not name_key.is_empty():
				return Localization.text(name_key)
	return Localization.text("INV_LOCATION_CARRIED")


func _refresh_transfer_row() -> void:
	var show_row := false
	var target_valid := false
	if not _selected_is_equipped and not _selected_instance_id.is_empty():
		var containers := _get_storage_containers()
		if containers.size() > 1:
			show_row = true
			_transfer_target.clear()
			for container in containers:
				var container_id := str(container.get("id", ""))
				if container_id == _selected_container_id:
					continue
				var capacity: Variant = container.get("capacity", 0)
				var used: Variant = container.get("used", 0)
				var cap := 0
				var use := 0
				if typeof(capacity) == TYPE_INT:
					cap = capacity
				if typeof(used) == TYPE_INT:
					use = used
				var label := Localization.text("INV_STORAGE_USAGE", {
					"name": _storage_kind_name(container),
					"used": str(use),
					"capacity": str(cap),
				})
				var index := _transfer_target.item_count
				_transfer_target.add_item(label)
				_transfer_target.set_item_metadata(index, container_id)
				_transfer_target.set_item_disabled(index, use >= cap)
			if _transfer_target.item_count > 0:
				var keep_index := -1
				for i in _transfer_target.item_count:
					var id := str(_transfer_target.get_item_metadata(i))
					if id == _transfer_target_id and not _transfer_target.is_item_disabled(i):
						keep_index = i
						break
				if keep_index < 0:
					for i in _transfer_target.item_count:
						if not _transfer_target.is_item_disabled(i):
							keep_index = i
							break
				if keep_index >= 0:
					_transfer_target.select(keep_index)
					_transfer_target_id = str(_transfer_target.get_item_metadata(keep_index))
					target_valid = true
				else:
					_transfer_target.select(-1)
					_transfer_target_id = ""
			else:
				_transfer_target_id = ""
	if show_row:
		_transfer_row.visible = true
		_transfer_button.text = Localization.text("INV_MOVE_ITEM")
		_transfer_button.disabled = not target_valid
		if target_valid:
			_transfer_target.tooltip_text = Localization.text("INV_TRANSFER_TO")
		else:
			_transfer_target.tooltip_text = ""
	else:
		_transfer_row.visible = false
		_transfer_button.disabled = true
		_transfer_target.tooltip_text = ""


func _refresh_transfer_error() -> void:
	if not visible or _selected_instance_id.is_empty() or not _transfer_failed:
		_transfer_error.text = ""
		_transfer_error.visible = false
		return
	_transfer_error.text = Localization.text("INV_TRANSFER_FAILED")
	_transfer_error.visible = true


func _storage_kind_name(container: Dictionary) -> String:
	var kind := str(container.get("kind", ""))
	var name_key := _storage_name_key(kind)
	if name_key.is_empty():
		return ""
	return Localization.text(name_key)


func _item_quantity(item: Dictionary) -> int:
	var quantity: Variant = item.get("quantity", 1)
	if typeof(quantity) == TYPE_INT:
		return quantity
	return 1


func _item_name_key(item: Dictionary) -> String:
	var raw_id: Variant = item.get("id", "")
	var item_id := str(raw_id)
	return str(NAME_KEYS.get(item_id, ""))


func _translate_name_key(name_key: String) -> String:
	if name_key.is_empty():
		return Localization.text("INV_UNKNOWN_ITEM")
	return Localization.text(name_key)


func _format_item_row(item: Dictionary, multi_container: bool) -> String:
	var name := _translate_item_name(item)
	if name.is_empty():
		return ""
	var count := _item_quantity(item)
	var base := Localization.text("INV_ROW", {"name": name, "count": str(count)})
	if not multi_container:
		return base
	var storage_name := _storage_name_for_item(item)
	if storage_name.is_empty():
		return base
	return Localization.text("INV_STORAGE_ITEM_ROW", {"item": base, "storage": storage_name})


func _refresh_source_label() -> void:
	var containers := _get_storage_containers()
	if containers.is_empty():
		# Legacy/unconfigured: keep the exact old source behavior.
		_source.text = Localization.text("INV_SOURCE_POCKET")
		return
	var lines: Array[String] = []
	for container in containers:
		lines.append(_format_container_line(container))
	_source.text = "\n".join(lines)


func _get_storage_containers() -> Array:
	var raw: Variant = Inventory.get_storage_containers()
	if typeof(raw) != TYPE_ARRAY:
		return []
	var result: Array = []
	for entry in raw:
		if typeof(entry) == TYPE_DICTIONARY:
			result.append(entry)
	return result


func _format_container_line(container: Dictionary) -> String:
	var kind := str(container.get("kind", ""))
	var name_key := _storage_name_key(kind)
	if name_key.is_empty():
		return ""
	var capacity: Variant = container.get("capacity", 0)
	var used: Variant = container.get("used", 0)
	var cap := 0
	var use := 0
	if typeof(capacity) == TYPE_INT:
		cap = capacity
	if typeof(used) == TYPE_INT:
		use = used
	return Localization.text("INV_STORAGE_USAGE", {
		"name": Localization.text(name_key),
		"used": str(use),
		"capacity": str(cap),
	})


func _storage_name_for_item(item: Dictionary) -> String:
	var instance_id := str(item.get("instance_id", ""))
	if instance_id.is_empty():
		return ""
	var container_id := Inventory.get_item_storage(instance_id)
	if container_id.is_empty():
		return ""
	for container in _get_storage_containers():
		if str(container.get("id", "")) == container_id:
			var kind := str(container.get("kind", ""))
			var name_key := _storage_name_key(kind)
			if not name_key.is_empty():
				return Localization.text(name_key)
	return ""


func _storage_name_key(kind: String) -> String:
	match kind:
		"pocket":
			return "INV_STORAGE_POCKET"
		"pouch":
			return "INV_STORAGE_POUCH"
		"backpack":
			return "INV_STORAGE_BACKPACK"
		_:
			return ""


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


func _on_item_selected(index: int) -> void:
	_select_row(index)


func _on_item_activated(_index: int) -> void:
	# Read-only list: activation must not mutate items.
	pass


func _on_transfer_target_selected(index: int) -> void:
	if index < 0 or index >= _transfer_target.item_count:
		return
	if _transfer_target.is_item_disabled(index):
		# Disabled (full) entry: never enable the button for it.
		_transfer_button.disabled = true
		return
	var metadata: Variant = _transfer_target.get_item_metadata(index)
	_transfer_target_id = str(metadata)
	_transfer_failed = false
	_refresh_transfer_error()
	_transfer_button.disabled = _transfer_target_id.is_empty()


func _on_transfer_pressed(instance_id: String = "", target_id: String = "") -> void:
	if not visible or _transfer_button.disabled:
		return
	if instance_id.is_empty():
		instance_id = _selected_instance_id
	if target_id.is_empty():
		target_id = _transfer_target_id
	if instance_id.is_empty() or target_id.is_empty():
		return
	# Revalidate canonical carried identity, current container and capacity.
	var save_data: Variant = Inventory.get_save_data()
	var still_carried := false
	if typeof(save_data) == TYPE_DICTIONARY:
		var raw_items: Variant = (save_data as Dictionary).get("items", [])
		if typeof(raw_items) == TYPE_ARRAY:
			for entry in raw_items:
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				if str((entry as Dictionary).get("instance_id", "")) == instance_id:
					still_carried = true
					break
	if not still_carried:
		_dirty = true
		return
	var current_container := str(Inventory.get_item_storage(instance_id))
	if current_container == target_id:
		_dirty = true
		return
	var moved := _attempt_transfer(instance_id, target_id)
	if moved:
		_transfer_failed = false
		_transfer_target_id = ""
		# Refresh immediately: source, target and item details.
		refresh_contents()
	else:
		_transfer_failed = true
		_refresh_transfer_error()


func _attempt_transfer(instance_id: String, target_id: String) -> bool:
	# Revalidate against fresh inventory state at activation time.
	var save_data: Variant = Inventory.get_save_data()
	if typeof(save_data) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = save_data
	var raw_items: Variant = data.get("items", [])
	var found := false
	if typeof(raw_items) == TYPE_ARRAY:
		for entry in raw_items:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var item: Dictionary = entry
			if str(item.get("instance_id", "")) == instance_id:
				found = true
				break
	if not found:
		return false
	var containers := _get_storage_containers()
	var target_found := false
	for container in containers:
		if str(container.get("id", "")) != target_id:
			continue
		target_found = true
		var capacity: Variant = container.get("capacity", 0)
		var used: Variant = container.get("used", 0)
		var cap := 0
		var use := 0
		if typeof(capacity) == TYPE_INT:
			cap = capacity
		if typeof(used) == TYPE_INT:
			use = used
		if use >= cap:
			return false
		break
	if not target_found:
		return false
	var current_container := str(Inventory.get_item_storage(instance_id))
	if current_container == target_id:
		return false
	var moved: Variant = Inventory.move_item_to_storage({"instance_id": instance_id}, target_id)
	return bool(moved)


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


func _on_items_gui_input(event: InputEvent) -> void:
	# Native touch selection and deliberate scrolling for the ItemList
	# (project mouse emulation is off). gui_input positions are LOCAL to the
	# ItemList. Track the initiating finger and pressed row; only select on a
	# valid release in the same row. Once the gesture travels >12px it becomes
	# a scroll: cancel the row-selection candidate, keep tracking the finger
	# and drive the vertical scrollbar from the drag delta. Canceled/release
	# ends the gesture. Never consume press/drag events that are not scrolled
	# so native ItemList behavior is preserved.
	var list_rect := Rect2(Vector2.ZERO, _items.size)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _list_touch_index < 0 and list_rect.has_point(touch.position):
				_list_touch_index = touch.index
				_list_touch_start = touch.position
				_list_last_drag_position = touch.position
				_list_scroll_active = false
				_list_pressed_row = _items.get_item_at_position(touch.position, true)
		elif touch.index == _list_touch_index:
			var row := _items.get_item_at_position(touch.position, true)
			var was_scrolling := _list_scroll_active
			var pressed_row := _list_pressed_row
			_list_touch_index = -1
			_list_pressed_row = -1
			_list_last_drag_position = Vector2.ZERO
			_list_scroll_active = false
			if not touch.canceled and not was_scrolling \
					and list_rect.has_point(touch.position) \
					and (touch.position - _list_touch_start).length() <= 12.0 \
					and row >= 0 and row == pressed_row:
				_items.select(row)
				_on_item_selected(row)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _list_touch_index:
			if not list_rect.has_point(drag.position):
				# Finger left the list: cancel selection and stop scrolling.
				_list_touch_index = -1
				_list_pressed_row = -1
				_list_last_drag_position = Vector2.ZERO
				_list_scroll_active = false
			elif (drag.position - _list_touch_start).length() > 12.0:
				# Gesture became a scroll: cancel only the row-selection
				# candidate so scrolling cannot select another row.
				if not _list_scroll_active:
					_list_pressed_row = -1
					_list_last_drag_position = drag.position
				_list_scroll_active = true
				var delta := drag.position - _list_last_drag_position
				_list_last_drag_position = drag.position
				_scroll_items_by_delta(delta.y)
				_items.accept_event()
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		# Ignore emulated mouse to avoid duplicate selection.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			_items.accept_event()


func _scroll_items_by_delta(delta_y: float) -> void:
	# Move the ItemList vertical scrollbar opposite the finger delta, clamped
	# by the scrollbar range and page size.
	var scroll_bar := _items.get_v_scroll_bar()
	if scroll_bar == null or not scroll_bar.visible:
		return
	var max_value := float(scroll_bar.max_value)
	var min_value := float(scroll_bar.min_value)
	var page := float(scroll_bar.page)
	var new_value := float(scroll_bar.value) - delta_y
	new_value = clampf(new_value, min_value, max(0.0, max_value - page))
	scroll_bar.value = new_value


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


func _on_transfer_button_gui_input(event: InputEvent) -> void:
	var transfer_rect := Rect2(Vector2.ZERO, _transfer_button.size)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _transfer_touch_index < 0 and transfer_rect.has_point(touch.position):
				_transfer_touch_index = touch.index
				# Capture the exact press intent so a later selection/target
				# change by another finger cannot move the wrong item.
				if not _transfer_button.disabled:
					_transfer_pressed_instance_id = _selected_instance_id
					_transfer_pressed_target_id = _transfer_target_id
				else:
					_transfer_pressed_instance_id = ""
					_transfer_pressed_target_id = ""
		elif touch.index == _transfer_touch_index:
			_transfer_touch_index = -1
			var pressed_instance_id := _transfer_pressed_instance_id
			var pressed_target_id := _transfer_pressed_target_id
			_transfer_pressed_instance_id = ""
			_transfer_pressed_target_id = ""
			if not touch.canceled and transfer_rect.has_point(touch.position) \
					and not _transfer_button.disabled \
					and not pressed_instance_id.is_empty() \
					and not pressed_target_id.is_empty() \
					and pressed_instance_id == _selected_instance_id \
					and pressed_target_id == _transfer_target_id:
				_on_transfer_pressed(pressed_instance_id, pressed_target_id)
		_transfer_button.accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _transfer_touch_index and not transfer_rect.has_point(drag.position):
			_transfer_touch_index = -1
			_transfer_pressed_instance_id = ""
			_transfer_pressed_target_id = ""
		_transfer_button.accept_event()
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			if _transfer_touch_index >= 0 and not transfer_rect.has_point(event.position):
				_transfer_touch_index = -1
				_transfer_pressed_instance_id = ""
				_transfer_pressed_target_id = ""
			_transfer_button.accept_event()
	elif event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			_transfer_button.accept_event()


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
	_transfer_target.add_theme_stylebox_override("normal", choice_style)

	var transfer_style := StyleBoxFlat.new()
	transfer_style.bg_color = Color(0.2, 0.18, 0.15)
	transfer_style.border_color = Color(0.62, 0.52, 0.3, 0.85)
	transfer_style.set_border_width_all(1)
	transfer_style.set_corner_radius_all(10)
	var transfer_hover := transfer_style.duplicate() as StyleBoxFlat
	transfer_hover.bg_color = Color(0.26, 0.23, 0.19)
	_transfer_button.add_theme_stylebox_override("normal", transfer_style)
	_transfer_button.add_theme_stylebox_override("hover", transfer_hover)
	_transfer_button.add_theme_stylebox_override("pressed", transfer_hover)

	_title.add_theme_font_size_override("font_size", 32)
	_apply_theme_recursive(self, theme)


func _apply_theme_recursive(node: Node, theme: Theme) -> void:
	if node is Control:
		node.theme = theme
	for child in node.get_children():
		_apply_theme_recursive(child, theme)
