extends SceneTree
## INV-03A (D-057): main inventory 12 + wallet 4, no wearable bags; saves made with bags migrate without loss.
var failures: Array[String] = []
var checks := 0
var inv: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures.append(why)
		printerr("NO_BACKPACK_FAIL: " + why)

func containers() -> Dictionary:
	var result := {}
	for c in inv.get_storage_containers(): result[c.id] = c
	return result

func reset() -> void:
	inv._storage_layout = null
	inv.items = []
	for slot in inv.equipped.keys(): inv.equipped[slot] = null
	inv.gold = 0
	check(inv.configure_storage([
		{"id": "traveler_clothing_pocket", "kind": "pocket", "capacity": 12},
		{"id": "traveler_wallet", "kind": "wallet", "capacity": 4},
	]), "main inventory 12 + wallet 4 configure")

func bag(id: String, iid: String) -> Dictionary:
	return {"id": id, "instance_id": iid, "type": 4, "value": 30 if id == "traveler_backpack" else 10,
		"stackable": false, "quantity": 1, "name": "legacy", "description": "", "icon": ""}

## A save as the old code wrote it: pocket 6 (one of them a spare pouch), backpack 8, pouch 2, both bags worn.
func legacy_save(real_items: int) -> Dictionary:
	reset()
	for i in range(real_items): check(inv.add_item("rusty_sword"), "seed item %d" % i)
	var data: Dictionary = inv.get_save_data()
	var placements := {}
	var cells := {}
	var index := 0
	var spare := bag("belt_pouch", "legacy-spare-pouch")
	var in_pocket := mini(real_items, 5)
	for item in data.items:
		var iid := str(item.instance_id)
		if index < in_pocket:
			placements[iid] = "traveler_clothing_pocket"; cells[iid] = index
		elif index < in_pocket + 8:
			placements[iid] = "worn_storage:legacy-backpack"; cells[iid] = index - in_pocket
		else:
			placements[iid] = "worn_storage:legacy-pouch"; cells[iid] = index - in_pocket - 8
		index += 1
	data.items.append(spare)
	placements[spare.instance_id] = "traveler_clothing_pocket"
	cells[spare.instance_id] = in_pocket
	data["storage"] = {"placements": placements, "cells": cells}
	data["worn_storage"] = {"backpack": bag("traveler_backpack", "legacy-backpack"), "pouch": bag("belt_pouch", "legacy-pouch")}
	return data

func check_loaded(label: String, expected_items: int, before_ids: Array) -> void:
	check(inv.items.size() == expected_items, label + ": every real item kept (%d)" % inv.items.size())
	var ids: Array = []
	for item in inv.items:
		check(not inv.LEGACY_BAG_IDS.has(str(item.id)), label + ": no bag item remains")
		ids.append(str(item.instance_id))
	ids.sort()
	check(ids == before_ids, label + ": same instance ids, nothing duplicated")
	var saved: Dictionary = inv.get_save_data()
	check(not saved.has("worn_storage"), label + ": new saves carry no worn storage")
	var taken := {}
	for iid in saved.storage.placements.keys():
		var key := str(saved.storage.placements[iid]) + ":" + str(saved.storage.cells[iid])
		check(not taken.has(key), label + ": one item per cell")
		taken[key] = true
		check(not str(saved.storage.placements[iid]).begins_with("worn_storage:"), label + ": no bag containers remain")

func run() -> void:
	inv = root.get_node("Inventory")
	check(not inv.item_database.has("traveler_backpack") and not inv.item_database.has("belt_pouch"), "bags are not game items any more")
	check(not inv.has_method("equip_storage_item") and not inv.has_method("get_worn_storage"), "wearable bag API is gone")
	check(inv.configure_storage([{"id": "x", "kind": "backpack", "capacity": 8}]) == false, "backpack container kind is rejected")

	reset()
	var c := containers()
	check(int(c.traveler_clothing_pocket.capacity) == 12 and int(c.traveler_wallet.capacity) == 4, "capacities 12 and 4")
	for i in range(16): check(inv.add_item("rusty_sword"), "item %d fits" % i)
	check(not inv.add_item("rusty_sword"), "the 17th item does not fit")
	c = containers()
	check(int(c.traveler_clothing_pocket.used) == 12 and int(c.traveler_wallet.used) == 4, "main inventory fills first, then wallet")

	reset()
	check(inv.add_item("rusty_sword"), "sword to equip")
	check(inv.equip_item(inv.items[0]), "equip sword")
	check(inv.unequip_to_storage("weapon", "traveler_wallet"), "unequip weapon straight into the wallet")
	check(inv.get_item_storage(str(inv.items[0].instance_id)) == "traveler_wallet", "weapon lies in the wallet")
	check(inv.equipped.weapon == null, "weapon slot is empty")

	for real in [15, 16]:
		var data := legacy_save(real)
		var before: Array = []
		for item in data.items:
			if not inv.LEGACY_BAG_IDS.has(str(item.id)): before.append(str(item.instance_id))
		before.sort()
		reset()
		check(inv.load_save_data(data), "legacy save with %d items and worn bags loads" % real)
		check_loaded("legacy %d" % real, real, before)
		c = containers()
		check(int(c.traveler_clothing_pocket.used) == 12, "legacy %d: main inventory full" % real)
		check(int(c.traveler_wallet.used) == real - 12, "legacy %d: rest in the wallet" % real)
		var again: Dictionary = inv.get_save_data()
		check(inv.load_save_data(again) and JSON.stringify(inv.get_save_data()) == JSON.stringify(again), "legacy %d: migrated save round-trips" % real)

	var schema: RefCounted = load("res://scripts/courtyard/courtyard_save_schema.gd").new()
	var with_drop := {"world_items": [{"item": bag("traveler_backpack", "dropped-bag")}, {"item": {"id": "bread"}}]}
	var stripped: Dictionary = schema._without_legacy_bags(with_drop, inv)
	check(stripped.world_items.size() == 1 and stripped.world_items[0].item.id == "bread", "a bag lying on the ground is dropped from old saves")
	check(with_drop.world_items.size() == 2, "the original save data is not modified")

	print("NO_BACKPACK_CHECKS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
