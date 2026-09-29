extends SceneTree
## ITEM-DATA-02A: definition/instance isolation and legacy records, independent of UI.
const SNAPSHOT := "res://scripts/tools/fixtures/item_catalog_snapshot.txt"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("ITEM_DEFINITIONS_FAIL ", label)

func inventory() -> Node:
	# Use the initialized autoload's script: preloading it from --script would
	# compile its FactionManager dependency before autoload names are registered.
	var inv: Node = root.get_node("Inventory").get_script().new()
	inv._init_item_database()
	return inv

func run() -> void:
	var a := inventory()
	var b := inventory()
	root.get_node("GameManager").player = null
	var old: Dictionary = str_to_var(FileAccess.get_file_as_string(SNAPSHOT))
	check(a.item_database.size() == 10, "all ten definitions loaded")
	check(a.item_database.iron_sword is ItemData, "live definitions are ItemData")
	check(not is_same(a.item_database.iron_sword, b.item_database.iron_sword), "inventories have separate definitions")
	check(a.add_item("iron_sword", 2), "two independent swords created")
	var first: Dictionary = a.items[0]
	var second: Dictionary = a.items[1]
	check(first.instance_id != second.instance_id, "two instance IDs")
	var original := first.duplicate(true)
	original.erase("instance_id")
	original.erase("quantity")
	check(original == old.iron_sword, "new instance exactly matches the pre-refactor snapshot")
	first.stats.damage = 999
	first.tags.append("qa_changed_instance")
	check(second.stats.damage == 15 and second.tags.is_empty(), "changing one instance leaves its sibling intact")
	check(a.item_database.iron_sword.stats.damage == 15 and a.item_database.iron_sword.tags.is_empty(), "instance does not edit its live definition")
	a.item_database.iron_sword.stats.damage = 42
	a.item_database.iron_sword.tags.append("qa_live_definition")
	check(second.stats.damage == 15 and second.tags.is_empty(), "definition change is not retroactive")
	check(b.item_database.iron_sword.stats.damage == 15 and b.item_database.iron_sword.tags.is_empty(), "definition change does not leak to another inventory")
	var disk: ItemData = load("res://data/items/iron_sword.tres")
	check(disk.stats.damage == 15 and disk.tags.is_empty(), "resource loader cache is not mutated")
	check(a.add_item("iron_sword") and a.items[2].stats.damage == 42 and a.items[2].tags == ["qa_live_definition"], "new instance uses current typed definition")
	check(b.add_item("bread", 21), "food splits into two stacks")
	var food: Dictionary = b.items[0]
	var spare: Dictionary = b.items[1]
	check(food.quantity == 20 and spare.quantity == 1, "old stack limit retained")
	food.effect.heal = 999
	check(spare.effect.heal == 10 and b.item_database.bread.effect.heal == 10, "effect dictionary is independent per stack")
	b.gold = 50
	check(b.buy_item("iron_sword", 50) and b.gold == 0, "purchase uses typed definition and exact payment")
	var bought: Dictionary = b.items[2]
	check(bought.stats.damage == 15 and bought.quantity == 1, "purchase creates the old record shape")
	b.gold = 10
	var before: Dictionary = b.get_save_data()
	check(not b.buy_item("unknown_definition", 1) and b.describe_item_id("unknown_definition").is_empty(), "unknown ID is rejected")
	check(b.get_save_data() == before, "rejected lookup does not change inventory")
	# Author a schema-1 save from the OLD snapshot, not from the new implementation.
	var saved_sword: Dictionary = old.iron_sword.duplicate(true)
	saved_sword.instance_id = "legacy-worn-sword"
	saved_sword.quantity = 1
	var saved_food: Dictionary = old.bread.duplicate(true)
	saved_food.instance_id = "legacy-food"
	saved_food.quantity = 3
	var legacy := {"schema_version": 1, "gold": 7, "items": [saved_food], "equipped": {"weapon": saved_sword, "armor": null, "helmet": null, "ring": null, "amulet": null}}
	check(b.load_save_data(legacy), "schema-1 save from old definitions loads")
	check(b.items == [saved_food] and b.equipped.weapon == saved_sword and b.gold == 7, "old values, quantities, IDs and equipment retained")
	check(b.get_save_data().schema_version == 1, "save version unchanged")
	var carried: Dictionary = b.items[0]
	carried.effect.heal = 25
	check(saved_food.effect.heal == 10 and b.item_database.bread.effect.heal == 10, "loaded record does not alias input or definition")
	var c := inventory()
	check(c.load_save_data(b.get_save_data()) and c.items[0].effect.heal == 25, "valid per-instance changes survive roundtrip")
	a.free()
	b.free()
	c.free()
	print("ITEM_DEFINITIONS_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
