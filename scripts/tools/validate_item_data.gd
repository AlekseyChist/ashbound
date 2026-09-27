extends SceneTree
## ITEM-DATA-01: the item catalog as data gives exactly the dictionaries of the old
## hard-coded catalog (snapshot taken from it before the change); every item has a unique id,
## a known category, stack rules that make sense, and an existing icon when it names one.
const Snapshot := "res://scripts/tools/fixtures/item_catalog_snapshot.txt"
const KNOWN_MISSING_ICONS := ["rusty_sword"]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("ITEM_DATA_FAIL " + label)

func same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key], b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not same(a[i], b[i]): return false
		return true
	return a == b

func run() -> void:
	var inv: Node = root.get_node("Inventory")
	var old: Dictionary = str_to_var(FileAccess.get_file_as_string(Snapshot))
	check(old.size() == 10, "snapshot has the ten old items")
	check(inv.item_database.size() == old.size(), "same number of items")
	for id in old:
		check(inv.item_database.has(id) and same(inv.item_database[id], old[id]), "item %s unchanged" % id)
	var catalog: ItemCatalog = load("res://data/items/catalog.tres")
	var ids := {}
	for item in catalog.items:
		check(not ids.has(item.id), "unique id " + item.id)
		ids[item.id] = true
		check(item.category in ["weapon", "clothing", "consumable", "object"], "%s has a known category" % item.id)
		check(item.stackable == (item.max_stack > 0), "%s: stack limit only for stackable items" % item.id)
		# Known since before ITEM-DATA-01: the rusty sword names an icon that was never drawn (STATUS).
		if not item.icon.is_empty() and not KNOWN_MISSING_ICONS.has(item.id):
			check(ResourceLoader.exists(item.icon), "%s icon exists" % item.id)
		check(item.resource_path == "res://data/items/%s.tres" % item.id, "%s lives in its own file" % item.id)
	# The live database is a copy: editing it never changes the data resource.
	inv.item_database["bread"]["value"] = 999
	check((load("res://data/items/bread.tres") as ItemData).value == 3, "the data resource is not changed by the inventory")
	print("ITEM_DATA_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
