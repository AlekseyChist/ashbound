## Регрессионный тест: владение предметами по instance_id (equip_item/use_item).
extends SceneTree

var inv: Node = null
var gm: Node = null
var fm: Node = null
var failures: Array = []
var done: bool = false

# Наблюдатели: снапшоты состояния в момент сигнала
var eq_events: Array = []
var uneq_events: Array = []
var removed_events: Array = []
var added_events: Array = []

class TestPlayer extends Node3D:
	var strength: int = 10
	var dexterity: int = 10
	var base_damage: int = 15
	var defense: int = 2
	var current_stamina: float = 0.0
	var max_stamina: float = 100.0
	var current_health: int = 0
	var heal_calls: Array = []

	func heal(amount: int) -> void:
		heal_calls.append(amount)
		current_health += amount


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if is_instance_valid(inv):
		return
	inv = root.get_node("Inventory")
	gm = root.get_node("GameManager")
	fm = root.get_node("FactionManager")
	if inv == null or gm == null or fm == null:
		failures.append("autoloads missing")
		_finish()
		return
	inv.item_added.connect(_on_item_added)
	inv.item_removed.connect(_on_item_removed)
	inv.item_equipped.connect(_on_item_equipped)
	inv.item_unequipped.connect(_on_item_unequipped)

	var player: Node3D = TestPlayer.new()
	gm.player = player

	_test1_unowned_equip_rejected(player)
	_test2_forged_copy_cannot_override(player)
	_test3_swap_capacity_and_repeat(player)
	_test4_faction_requirement_enforced(player)
	_test5_unequip_full_bag_then_free(player)
	_test6_unowned_use_rejected(player)
	_test7_potion_single_use(player)
	_test8_stack_order_consumption(player)
	_test9_forged_use_fields_ignored(player)
	_test10_no_player_use_rejected(player)
	_test11_type_mismatch_rejected(player)
	_test12_missing_instance_id_rejected(player)

	gm.player = null
	player.free()
	_finish()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


# --- Наблюдатели сигналов (снапшоты в момент сигнала) ---

func _on_item_added(item: Dictionary) -> void:
	added_events.append({"item": item.duplicate(true), "items": inv.items.duplicate(true)})


func _on_item_removed(item_id: String) -> void:
	removed_events.append({"id": item_id, "items": inv.items.duplicate(true)})


func _on_item_equipped(item: Dictionary, slot: String) -> void:
	eq_events.append({
		"item": item.duplicate(true),
		"slot": slot,
		"items": inv.items.duplicate(true),
		"equipped": inv.equipped.duplicate(true),
	})


func _on_item_unequipped(slot: String) -> void:
	uneq_events.append({"slot": slot, "items": inv.items.duplicate(true)})


# --- Утилиты ---

func _reset(player: Node3D) -> void:
	inv.items.clear()
	for k in inv.equipped.keys():
		inv.equipped[k] = null
	inv.max_capacity = 50
	eq_events.clear()
	uneq_events.clear()
	removed_events.clear()
	added_events.clear()
	player.strength = 10
	player.dexterity = 10
	player.base_damage = 15
	player.defense = 2
	player.current_stamina = 0.0
	player.max_stamina = 100.0
	player.current_health = 0
	player.heal_calls.clear()


func _carried(id: String) -> Dictionary:
	for it in inv.items:
		if it.get("instance_id", "") == id:
			return it
	return {}


# --- Тесты ---

func _test1_unowned_equip_rejected(player: Node3D) -> void:
	_reset(player)
	var full: Dictionary = inv.item_database["iron_sword"].duplicate(true)
	full["instance_id"] = "ghost_1"
	var ok: bool = inv.equip_item(full)
	_check(ok == false, "T1: equip unowned should fail")
	_check(inv.items.is_empty(), "T1: items changed")
	_check(inv.equipped["weapon"] == null, "T1: weapon slot mutated")
	_check(eq_events.is_empty(), "T1: equipped event fired")


func _test2_forged_copy_cannot_override(player: Node3D) -> void:
	_reset(player)
	inv.add_item("rusty_sword", 1)
	var real: Dictionary = _carried(_only_id())
	if real.is_empty():
		failures.append("T2: setup failed")
		return
	var forged: Dictionary = real.duplicate(true)
	forged["stats"] = {"damage": 999}
	forged["name"] = "Forged"
	forged["slot"] = "armor"
	forged["faction_requirement"] = fm.FACTION_ASHEN_ORDER
	var ok: bool = inv.equip_item(forged)
	_check(ok == true, "T2: equip forged copy should succeed")
	var w: Variant = inv.equipped["weapon"]
	_check(w is Dictionary and is_same(w, real), "T2: wrong weapon instance (identity)")
	if ok and w is Dictionary:
		_check(int(w.get("stats", {}).get("damage", 0)) == 8, "T2: damage not canonical 8 (got %s)" % str(w.get("stats", {}).get("damage")))
		_check(player.base_damage == 23, "T2: base_damage not 15+8=23 (got %d)" % player.base_damage)
	_check(inv.equipped["armor"] == null, "T2: armor slot mutated")
	_check(eq_events.size() == 1, "T2: expected 1 equipped event")


func _only_id() -> String:
	for it in inv.items:
		return str(it.get("instance_id", ""))
	return ""


func _test3_swap_capacity_and_repeat(player: Node3D) -> void:
	_reset(player)
	inv.max_capacity = 1
	inv.add_item("rusty_sword", 1)
	var old: Dictionary = _carried(_only_id())
	if old.is_empty():
		failures.append("T3: setup failed")
		return
	var ok_old: bool = inv.equip_item(old)
	_check(ok_old, "T3: equip old failed")
	inv.add_item("iron_sword", 1)
	var new: Dictionary = _carried(_only_id())
	if new.is_empty():
		failures.append("T3: setup new failed")
		return
	var ok_new: bool = inv.equip_item(new)
	_check(ok_new, "T3: equip new should succeed")
	var w: Variant = inv.equipped["weapon"]
	_check(w is Dictionary and is_same(w, new), "T3: weapon not new instance (identity)")
	_check(inv.items.size() == 1, "T3: bag count != 1 (got %d)" % inv.items.size())
	if inv.items.size() == 1:
		var b: Variant = inv.items[0]
		_check(b is Dictionary and is_same(b, old), "T3: bag not old instance (identity)")
	_check(eq_events.size() >= 1, "T3: no equipped event")
	if eq_events.size() > 0:
		var ev: Dictionary = eq_events[eq_events.size() - 1]
		_check(ev.get("items", []).size() == 1, "T3: event snapshot bag wrong size")
	var events_before_repeat: int = eq_events.size()
	var snapshot_before_repeat: Array = inv.items.duplicate(true)
	var again: bool = inv.equip_item(new)
	_check(again == false, "T3: repeat equip should fail (stale handle)")
	_check(inv.items.size() == 1, "T3: items changed after repeat")
	_check(eq_events.size() == events_before_repeat, "T3: new equipped event on repeat (got %d, expected %d)" % [eq_events.size(), events_before_repeat])
	_check(inv.items.duplicate(true) == snapshot_before_repeat, "T3: snapshot changed after repeat equip")


func _test4_faction_requirement_enforced(player: Node3D) -> void:
	_reset(player)
	fm.player_faction = ""
	inv.add_item("cultist_blade", 1)
	var real: Dictionary = _carried(_only_id())
	if real.is_empty():
		failures.append("T4: setup failed")
		return
	var copy: Dictionary = real.duplicate(true)
	copy.erase("faction_requirement")
	var ok: bool = inv.equip_item(copy)
	_check(ok == false, "T4: faction requirement must be enforced from canonical item")
	_check(inv.items.size() == 1, "T4: items changed")
	_check(inv.equipped["weapon"] == null, "T4: weapon mutated")
	_check(eq_events.is_empty(), "T4: event fired")


func _test5_unequip_full_bag_then_free(player: Node3D) -> void:
	_reset(player)
	inv.max_capacity = 1
	inv.add_item("rusty_sword", 1)
	var sword: Dictionary = _carried(_only_id())
	if sword.is_empty():
		failures.append("T5: setup failed")
		return
	_check(inv.equip_item(sword), "T5: equip failed")
	inv.add_item("bread", 1)
	var ok_full: bool = inv.unequip_slot("weapon")
	_check(ok_full == false, "T5: unequip into full bag should fail")
	_check(inv.equipped["weapon"] is Dictionary, "T5: equipped lost on failure")
	_check(inv.items.size() == 1, "T5: bag changed on failure")
	inv.remove_item("bread", 1)
	var ok_free: bool = inv.unequip_slot("weapon")
	_check(ok_free, "T5: unequip after freeing slot should succeed")
	_check(inv.items.size() == 1, "T5: bag count wrong after unequip")
	if inv.items.size() == 1:
		var b: Variant = inv.items[0]
		_check(b is Dictionary and is_same(b, sword), "T5: exact reference lost (identity)")


func _test6_unowned_use_rejected(player: Node3D) -> void:
	_reset(player)
	var full: Dictionary = inv.item_database["health_potion"].duplicate(true)
	full["instance_id"] = "ghost_p"
	var ok: bool = inv.use_item(full)
	_check(ok == false, "T6: use unowned should fail")
	_check(player.heal_calls.is_empty(), "T6: heal called")
	_check(removed_events.is_empty(), "T6: removal signal fired")
	_check(inv.items.is_empty(), "T6: items changed")


func _test7_potion_single_use(player: Node3D) -> void:
	_reset(player)
	inv.add_item("health_potion", 1)
	var real: Dictionary = _carried(_only_id())
	if real.is_empty():
		failures.append("T7: setup failed")
		return
	var ok: bool = inv.use_item(real)
	_check(ok, "T7: use should succeed")
	_check(player.heal_calls == [50], "T7: heal not exactly 50 once (got %s)" % str(player.heal_calls))
	_check(removed_events.size() == 1, "T7: removal count != 1")
	var again: bool = inv.use_item(real)
	_check(again == false, "T7: stale dict reuse should fail")
	_check(player.heal_calls.size() == 1, "T7: extra heal")
	_check(removed_events.size() == 1, "T7: extra removal signal")


func _test8_stack_order_consumption(player: Node3D) -> void:
	_reset(player)
	var a: Dictionary = inv.item_database["bread"].duplicate(true)
	a["quantity"] = 2
	a["instance_id"] = "t8_a"
	var b: Dictionary = inv.item_database["bread"].duplicate(true)
	b["quantity"] = 3
	b["instance_id"] = "t8_b"
	inv.items.append(a)
	inv.items.append(b)
	var ok: bool = inv.use_item(a)
	_check(ok, "T8: use A should succeed")
	_check(int(a.get("quantity", 0)) == 1, "T8: A quantity != 1 (got %s)" % str(a.get("quantity")))
	_check(int(b.get("quantity", 0)) == 3, "T8: B quantity changed (got %s)" % str(b.get("quantity")))
	_check(player.heal_calls == [10], "T8: heal wrong (got %s)" % str(player.heal_calls))
	if inv.items.size() >= 2:
		var i0: Variant = inv.items[0]
		var i1: Variant = inv.items[1]
		_check(i0 is Dictionary and is_same(i0, a), "T8: items[0] not A (identity)")
		_check(i1 is Dictionary and is_same(i1, b), "T8: items[1] not B (identity)")
		if i0 is Dictionary:
			_check(str(i0.get("instance_id", "")) == "t8_a", "T8: A instance_id lost (got %s)" % str(i0.get("instance_id")))
		if i1 is Dictionary:
			_check(str(i1.get("instance_id", "")) == "t8_b", "T8: B instance_id lost (got %s)" % str(i1.get("instance_id")))
	else:
		failures.append("T8: expected 2 items, got %d" % inv.items.size())
	_check(removed_events.size() == 1, "T8: removal count != 1")
	if removed_events.size() > 0:
		var ev_items: Array = removed_events[0].get("items", [])
		var total: int = 0
		for it in ev_items:
			total += int(it.get("quantity", 0))
		_check(total == 4, "T8: removal snapshot total != 4 (got %d)" % total)


func _test9_forged_use_fields_ignored(player: Node3D) -> void:
	_reset(player)
	inv.add_item("bread", 1)
	var bread: Dictionary = _carried(_only_id())
	if bread.is_empty():
		failures.append("T9: setup failed")
		return
	inv.add_item("iron_sword", 1)
	var copy: Dictionary = bread.duplicate(true)
	copy["effect"] = {"heal": 999}
	copy["type"] = inv.ItemType.WEAPON
	copy["id"] = "iron_sword"
	var ok: bool = inv.use_item(copy)
	_check(ok, "T9: use should succeed via instance_id")
	_check(player.heal_calls == [10], "T9: heal not canonical 10 (got %s)" % str(player.heal_calls))
	_check(inv.get_item_count("bread") == 0, "T9: bread not consumed")
	_check(inv.get_item_count("iron_sword") == 1, "T9: sword lost")


func _test10_no_player_use_rejected(player: Node3D) -> void:
	_reset(player)
	inv.add_item("health_potion", 1)
	var real: Dictionary = _carried(_only_id())
	if real.is_empty():
		failures.append("T10: setup failed")
		return
	gm.player = null
	var ok: bool = inv.use_item(real)
	_check(ok == false, "T10: use without player should fail")
	_check(inv.get_item_count("health_potion") == 1, "T10: potion consumed")
	gm.player = player


func _test11_type_mismatch_rejected(player: Node3D) -> void:
	_reset(player)
	inv.add_item("rusty_sword", 1)
	var sword: Dictionary = _carried(_only_id())
	if sword.is_empty():
		failures.append("T11: setup failed")
		return
	inv.add_item("bread", 1)
	var bread: Dictionary = {}
	for it in inv.items:
		if str(it.get("id", "")) == "bread":
			bread = it
			break
	var ok_use: bool = inv.use_item(sword)
	_check(ok_use == false, "T11: use sword should fail")
	var ok_equip: bool = inv.equip_item(bread)
	_check(ok_equip == false, "T11: equip bread should fail")
	_check(inv.get_item_count("rusty_sword") == 1, "T11: sword lost")
	_check(inv.get_item_count("bread") == 1, "T11: bread lost")
	_check(inv.equipped["weapon"] == null, "T11: weapon mutated")


func _test12_missing_instance_id_rejected(player: Node3D) -> void:
	_reset(player)
	var potion: Dictionary = inv.item_database["health_potion"].duplicate(true)
	potion.erase("instance_id")
	var ok_use: bool = inv.use_item(potion)
	_check(ok_use == false, "T12: use without instance_id should fail")
	var sword: Dictionary = inv.item_database["iron_sword"].duplicate(true)
	sword.erase("instance_id")
	var ok_equip: bool = inv.equip_item(sword)
	_check(ok_equip == false, "T12: equip without instance_id should fail")
	_check(inv.items.is_empty(), "T12: items mutated")
	_check(inv.equipped["weapon"] == null, "T12: equipment mutated")


func _finish() -> void:
	if done:
		return
	done = true
	if failures.is_empty():
		print("ASHBOUND_INVENTORY_OWNERSHIP_OK")
		quit(0)
	else:
		for f in failures:
			print("[FAIL] ", f)
		print("ASHBOUND_INVENTORY_OWNERSHIP_FAILED: %d" % failures.size())
		quit(1)
