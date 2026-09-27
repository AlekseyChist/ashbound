extends SceneTree
## Independent acceptance tests for inventory selection and transfer UI.

var inv: Node
var loc: Node
var panel: Control
var rows: ItemList
var target: OptionButton
var move_button: Button
var failures: Array[String] = []
var groups := 0
var settings_path: String

func _initialize() -> void:
	_run.call_deferred()
	_watchdog.call_deferred()

func _watchdog() -> void:
	await create_timer(30.0).timeout
	printerr("ASHBOUND_INVENTORY_TRANSFER_TIMEOUT")
	quit(1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("TRANSFER_FAIL: " + message)

func settle() -> void:
	for i in 4:
		await process_frame

func owned(item_id: String, index: int = 0) -> Dictionary:
	var matches: Array = []
	for item in inv.items:
		if item.id == item_id:
			matches.append(item)
	return matches[index].duplicate(true) if index < matches.size() else {}

func row_identity(index: int) -> String:
	var metadata: Variant = rows.get_item_metadata(index)
	if metadata is Dictionary:
		return str(metadata.get("instance_id", ""))
	return str(metadata)

func select_item(instance_id: String) -> void:
	for i in rows.item_count:
		if row_identity(i) == instance_id:
			rows.select(i)
			rows.item_selected.emit(i)
			return
	check(false, "select real identity " + instance_id)

func destination_index(id: String) -> int:
	for i in target.item_count:
		if str(target.get_item_metadata(i)) == id:
			return i
	return -1

func choose_destination(id: String) -> void:
	var i := destination_index(id)
	check(i >= 0, "destination exists " + id)
	if i >= 0:
		target.select(i)
		target.item_selected.emit(i)

func selected_id() -> String:
	var selection := rows.get_selected_items()
	return row_identity(selection[0]) if not selection.is_empty() else ""

func belongings() -> Dictionary:
	var snapshot: Dictionary = inv.get_save_data()
	snapshot.erase("storage")
	return snapshot

func touch(button: Button, pressed: bool, position: Vector2, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 2
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	button.gui_input.emit(event)

func _run() -> void:
	inv = root.get_node("Inventory")
	loc = root.get_node("Localization")
	settings_path = "res://.tools/transfer-qa-%d.cfg" % OS.get_process_id()
	loc.load_preferences(settings_path, "en_US")
	panel = load("res://scenes/courtyard/courtyard_inventory_panel.tscn").instantiate()
	root.add_child(panel)
	await settle()
	for id in ["Items", "ItemDetails", "TransferTarget", "TransferButton", "TransferRow", "TransferError"]:
		if panel.get_node_or_null("%" + id) == null:
			printerr("TRANSFER_FAIL: missing required control " + id)
			quit(1)
			return
	rows = panel.get_node("%Items")
	check(rows.select_mode == ItemList.SELECT_SINGLE, "one item at a time on mouse, touch and keyboard")
	target = panel.get_node("%TransferTarget")
	move_button = panel.get_node("%TransferButton")
	panel.open_panel()
	check(inv.items.is_empty() and inv.gold == 0, "UI grants no free belongings")
	check(selected_id().is_empty() and not panel.get_node("%TransferRow").visible, "empty UI offers no fictional container")
	check(panel.get_node("%ItemDetails").text == "Select an item to inspect it.", "empty details localized")
	groups += 1

	var profile := [{"id":"qa_pocket", "kind":"pocket", "capacity":2}, {"id":"qa_bag", "kind":"pocket", "capacity":1}, {"id":"qa_pouch", "kind":"wallet", "capacity":2}]
	check(inv.configure_storage(profile), "configure physical QA clothing and bag")
	check(inv.add_item("bread", 3) and inv.add_item("rusty_sword", 2) and inv.add_item("health_potion"), "seed canonical fixture")
	inv.add_gold(17)
	await settle()
	var bread := owned("bread")
	var sword := owned("rusty_sword")
	var other_sword := owned("rusty_sword", 1)
	check(bread.instance_id != sword.instance_id and sword.instance_id != other_sword.instance_id, "unique identities")
	var before: Dictionary = inv.get_save_data()
	select_item(bread.instance_id)
	rows.item_activated.emit(rows.get_selected_items()[0])
	await settle()
	check(inv.get_save_data() == before, "selection and activation never use/equip or move")
	check(panel.get_node("%ItemDetails").text.contains("Bread × 3") and panel.get_node("%ItemDetails").text.contains("Clothing pocket"), "details match canonical quantity/location")
	check(not panel.get_node("%TransferError").visible, "ordinary selection is not shown as failure")
	var full_index := destination_index("qa_bag")
	check(full_index >= 0 and target.is_item_disabled(full_index), "full destination disabled")
	check(destination_index("qa_pocket") == -1, "current source is not a move destination")
	groups += 1

	var unchanged := belongings()
	choose_destination("qa_pouch")
	check(not move_button.disabled, "valid action enabled")
	move_button.pressed.emit()
	await settle()
	check(inv.get_item_storage(bread.instance_id) == "qa_pouch", "whole bread stack moved")
	check(belongings() == unchanged, "move preserves every item, count, equipment and coin")
	check(selected_id() == bread.instance_id, "moved stack remains selected")
	check(panel.get_node("%ItemDetails").text.contains("Wallet") and not panel.get_node("%TransferError").visible, "success updates detail location without error")
	check(inv.add_item("bread", 1), "grow existing selected stack")
	await settle()
	check(panel.get_node("%ItemDetails").text.contains("Bread × 4"), "selected quantity refreshes from canonical data")
	check(inv.remove_item("bread", 1), "restore stack quantity")
	await settle()
	check(inv.get_item_storage(sword.instance_id) == "qa_pocket" and inv.get_item_storage(other_sword.instance_id) == "qa_bag", "unrelated identical swords unchanged")
	groups += 1

	choose_destination("qa_pocket")
	check(inv.add_item("iron_sword"), "fill selected destination before UI processes dirty signal")
	before = inv.get_save_data()
	move_button.pressed.emit()
	check(inv.get_save_data() == before, "stale enabled action cannot overflow or partially move")
	await settle()
	check(inv.get_item_storage(bread.instance_id) == "qa_pouch", "race failure retains source")
	check(panel.get_node("%TransferError").visible, "rejected move has visible failure feedback")
	groups += 1

	profile[0].capacity = 3
	profile[1].capacity = 3
	check(inv.configure_storage(profile), "allow two free targets")
	await settle()
	choose_destination("qa_bag")
	before = inv.get_save_data()
	var reversed: Dictionary = before.duplicate(true)
	reversed.items.reverse()
	check(inv.load_save_data(reversed), "reorder rows through valid snapshot")
	check(inv.configure_storage([profile[2], profile[0], profile[1]]), "reorder target definitions")
	loc.set_language("ru")
	await settle()
	check(selected_id() == bread.instance_id, "identity survives row order and translation")
	check(str(target.get_item_metadata(target.selected)) == "qa_bag", "target identity survives option reorder")
	check(panel.get_node("%ItemDetails").text.contains("Хлеб × 3"), "selected details translate")
	unchanged = belongings()
	move_button.pressed.emit()
	await settle()
	check(inv.get_item_storage(bread.instance_id) == "qa_bag", "reordered action moves requested identity to requested target")
	check(belongings() == unchanged, "translated action preserves canonical data")
	groups += 1

	choose_destination("qa_pocket")
	check(inv.remove_item("bread", 3), "remove selected stack before queued action")
	before = inv.get_save_data()
	move_button.pressed.emit()
	await settle()
	check(inv.get_save_data() == before, "removed selection cannot act on replacement row")
	check(selected_id().is_empty() and not panel.get_node("%TransferRow").visible, "removed identity clears selection/actions")
	groups += 1

	select_item(sword.instance_id)
	before = inv.get_save_data()
	check(inv.equip_item(sword), "external equipment change")
	await settle()
	check(selected_id() == sword.instance_id, "selection follows same item into equipped owner")
	check(not panel.get_node("%TransferRow").visible, "equipped item cannot be transferred as carried")
	check(panel.get_node("%ItemDetails").text.contains("Надето"), "equipped detail localized")
	before = inv.get_save_data()
	move_button.pressed.emit()
	check(inv.get_save_data() == before, "forged activation cannot transfer equipped item")
	check(inv.unequip_slot("weapon"), "return equipped item to carried ownership")
	await settle()
	groups += 1

	select_item(other_sword.instance_id)
	choose_destination("qa_pocket")
	before = inv.get_save_data()
	panel.close_panel()
	move_button.pressed.emit()
	check(inv.get_save_data() == before, "hidden panel cannot mutate inventory")
	panel.open_panel()
	await settle()
	check(selected_id().is_empty(), "reopen starts with explicit unselected state")
	check(not panel.get_node("%TransferError").visible, "reopen clears stale errors")
	groups += 1

	select_item(other_sword.instance_id)
	# Unequipping above legitimately filled the first available pouch.
	# This touch acceptance case must target the still-free clothing pocket.
	choose_destination("qa_pocket")
	check(not move_button.disabled, "touch fixture destination has free space")
	before = inv.get_save_data()
	var middle := move_button.size * 0.5
	touch(move_button, true, middle)
	touch(move_button, false, middle, true)
	check(inv.get_save_data() == before, "canceled touch cannot move")
	touch(move_button, true, middle)
	var drag := InputEventScreenDrag.new()
	drag.index = 2
	drag.position = Vector2(-50, -50)
	move_button.gui_input.emit(drag)
	touch(move_button, false, middle)
	check(inv.get_save_data() == before, "drag out then release cannot activate")
	touch(move_button, true, middle)
	touch(move_button, false, middle)
	await settle()
	if inv.get_item_storage(other_sword.instance_id) != "qa_pocket":
		printerr("TRANSFER_TOUCH_DIAGNOSTIC ", {"button_size":move_button.size, "press_position":middle, "disabled":move_button.disabled, "selection":selected_id(), "target":target.get_item_metadata(target.selected) if target.selected >= 0 else null, "storage":inv.get_item_storage(other_sword.instance_id), "error_visible":panel.get_node("%TransferError").visible})
	check(inv.get_item_storage(other_sword.instance_id) == "qa_pocket", "one deliberate touch transfers correct unique sword")
	var after_touch: Dictionary = inv.get_save_data()
	for pressed in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = middle
		mouse.pressed = pressed
		move_button.gui_input.emit(mouse)
	await settle()
	check(inv.get_save_data() == after_touch, "emulated duplicate cannot move back into newly selected destination")
	# A second finger may change selection while the transfer finger is held.
	# Release must not act on the new item the player did not press for.
	choose_destination("qa_bag")
	before = inv.get_save_data()
	touch(move_button, true, middle)
	select_item(sword.instance_id)
	choose_destination("qa_bag")
	touch(move_button, false, middle)
	await settle()
	check(inv.get_save_data() == before, "selection changed during held touch cancels action")
	touch(move_button, true, middle)
	choose_destination("qa_pocket")
	touch(move_button, false, middle)
	await settle()
	check(inv.get_save_data() == before, "destination changed during held touch cancels action")
	groups += 1

	panel.close_panel()
	check(inv.configure_storage(profile), "restore container order")
	var unknown := {"id":"future_item", "instance_id":"qa_unknown", "quantity":1, "name":"SECRET_RAW_NAME"}
	inv.items.append(unknown)
	inv.item_added.emit(unknown)
	panel.open_panel()
	await settle()
	select_item("qa_unknown")
	check(panel.get_node("%ItemDetails").text.contains("Неизвестный предмет"), "unknown item has safe fallback")
	check(not panel.get_node("%ItemDetails").text.contains("future_item") and not panel.get_node("%ItemDetails").text.contains("SECRET_RAW_NAME"), "details never leak internal identity/raw text")
	inv.items.erase(unknown)
	inv.item_removed.emit("future_item")
	await settle()
	groups += 1

	panel.queue_free()
	await settle()
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if failures.is_empty() and groups == 10:
		print("ASHBOUND_INVENTORY_TRANSFER_OK groups=10")
		quit(0)
	else:
		printerr("ASHBOUND_INVENTORY_TRANSFER_FAILED groups=%d failures=%d" % [groups, failures.size()])
		quit(1)
