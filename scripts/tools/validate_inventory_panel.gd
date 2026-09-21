extends SceneTree

var inv: Node
var loc: Node
var panel: Control
var failures: Array[String] = []
var groups := 0
var settings_path: String
var original: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("PANEL_FAIL: " + message)

func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame

func _rows() -> PackedStringArray:
	var result := PackedStringArray()
	var list: ItemList = panel.get_node("%Items")
	for i in list.item_count:
		result.append(list.get_item_text(i))
	return result

func _select_language(index: int) -> void:
	var choice: OptionButton = panel.get_node("%LanguageChoice")
	choice.select(index)
	choice.item_selected.emit(index)
	await _frames()

func _run() -> void:
	inv = root.get_node("Inventory")
	loc = root.get_node("Localization")
	original = inv.get_save_data()
	settings_path = "res://.tools/inventory-panel-qa-%d.cfg" % OS.get_process_id()
	loc.load_preferences(settings_path, "en_US")
	panel = load("res://scenes/courtyard/courtyard_inventory_panel.tscn").instantiate()
	root.add_child(panel)
	await _frames()
	_check(not panel.visible, "panel initially hidden")
	panel.open_panel()
	await _frames()
	_check(panel.visible and _rows().is_empty(), "real empty inventory")
	_check(panel.get_node("%Empty").visible, "empty label visible")
	_check(panel.get_node("%Coins").text == "Coins: 0", "honest initial gold")
	_check(not FileAccess.file_exists(settings_path), "opening does not write language preferences")
	_check(inv.get_save_data() == original, "opening adds no free items")
	groups += 1

	_check(inv.add_item("bread", 3), "fixture bread")
	_check(inv.add_item("health_potion", 2), "fixture potion")
	_check(inv.add_item("rusty_sword", 1), "fixture sword")
	inv.add_gold(17)
	await _frames()
	_check(_rows().has("Bread × 3") and _rows().has("Health potion × 2"), "localized names and stack quantities")
	_check(_rows().has("Rusty sword × 1"), "unique item row")
	_check(not panel.get_node("%Empty").visible, "not empty with actual items")
	_check(panel.get_node("%Coins").text == "Coins: 17", "gold signal refresh")
	groups += 1

	var before: Dictionary = inv.get_save_data()
	await _select_language(2)
	_check(loc.get_preference() == "ru" and loc.get_language() == "ru", "selector persists Russian")
	_check(FileAccess.file_exists(settings_path), "explicit language choice saved")
	_check(_rows().has("Хлеб × 3") and _rows().has("Зелье здоровья × 2"), "open rows refresh to Russian")
	_check(panel.get_node("%Title").text == "При себе", "Russian title")
	_check(panel.get_node("%Source").text == "Карман одежды", "actual pocket source")
	_check(inv.get_save_data() == before, "translation preserves owned item data")
	groups += 1

	var sword: Dictionary = {}
	for item in inv.items:
		if item.id == "rusty_sword":
			sword = item.duplicate(true)
	_check(inv.equip_item(sword), "fixture equipment")
	await _frames()
	_check(_rows().has("Ржавый меч · надето"), "equipment row reflects actual equipped owner")
	_check(not _rows().has("Ржавый меч × 1"), "equipped item not duplicated")
	before = inv.get_save_data()
	var list: ItemList = panel.get_node("%Items")
	list.select(0)
	list.item_selected.emit(0)
	await _frames()
	_check(inv.get_save_data() == before, "read-only selection does not consume/equip")
	groups += 1

	_check(inv.add_item("bread", 1), "fixture extra bread")
	await _frames()
	_check(_rows().has("Хлеб × 4"), "live quantity refresh")
	_check(inv.remove_item("health_potion", 2), "fixture remove potion")
	await _frames()
	_check(not _rows().has("Зелье здоровья × 2"), "removed item disappears")
	groups += 1

	var unknown := {"id":"future_relic", "instance_id":"qa_unknown", "name":"Скрытое русское имя", "quantity":1}
	inv.items.append(unknown)
	inv.item_added.emit(unknown)
	await _frames()
	_check(_rows().has("Неизвестный предмет × 1"), "unknown ID has safe localized label")
	_check(not str(_rows()).contains("future_relic") and not str(_rows()).contains("Скрытое русское имя"), "internal ID/name not leaked")
	inv.items.erase(unknown)
	groups += 1

	loc.load_preferences("res://.tools", "en_US")
	await _select_language(2)
	_check(loc.get_preference() == "auto" and loc.get_language() == "en", "failed write preserves real preference")
	_check(panel.get_node("%LanguageChoice").selected == 0, "selector rolls back after write failure")
	_check(panel.get_node("%SettingsError").visible, "settings error is visible")
	_check(panel.get_node("%SettingsError").text == "Could not save the language preference.", "settings error translated")
	loc.load_preferences(settings_path, "en_US")
	await _select_language(1)
	_check(not panel.get_node("%SettingsError").visible, "successful choice clears error")
	groups += 1

	before = inv.get_save_data()
	for i in 10:
		panel.close_panel()
		panel.open_panel()
	await _frames()
	_check(inv.get_save_data() == before, "reopening has no item/gold effects")
	_check(inv.load_save_data(original), "restore initial inventory")
	await _frames()
	_check(_rows().is_empty() and panel.get_node("%Empty").visible, "snapshot restoration refreshes open panel")
	panel.close_panel()
	_check(not panel.visible, "close hides panel")
	groups += 1
	_check(groups == 8, "all eight groups complete")
	panel.queue_free()
	await process_frame
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if failures.is_empty():
		print("ASHBOUND_INVENTORY_PANEL_OK groups=8")
		quit(0)
	else:
		printerr("ASHBOUND_INVENTORY_PANEL_FAILED groups=%d failures=%d" % [groups, failures.size()])
		quit(1)
