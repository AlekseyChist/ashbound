extends SceneTree
## Independent storage contract: identity, capacity, transactions and untrusted snapshots.
var failures: Array[String] = []
var groups := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		printerr("STORAGE_LAYOUT_FAIL: " + label)

func entry(id: String) -> Dictionary:
	return {"instance_id": id, "id": "bread", "quantity": 20}

func definitions() -> Array:
	return [{"id": "coat", "kind": "pocket", "capacity": 2}, {"id": "bag", "kind": "backpack", "capacity": 2}]

func state(layout: RefCounted) -> Dictionary:
	return {"containers": layout.get_containers(), "save": layout.get_save_data()}

func _run() -> void:
	var script: Script = load("res://scripts/systems/inventory_storage_layout.gd")
	if script == null or not script.can_instantiate():
		printerr("STORAGE_LAYOUT_FAIL: component cannot instantiate")
		quit(1)
		return
	var layout: RefCounted = script.new()
	var carried: Array = [entry("a"), entry("b"), entry("c")]
	var original_items := carried.duplicate(true)
	var config := definitions()
	check(layout.configure(config, carried), "configure with carried stacks")
	check(layout.get_capacity() == 4, "sum of real capacities")
	check(layout.get_container_id("a") == "coat" and layout.get_container_id("b") == "coat" and layout.get_container_id("c") == "bag", "deterministic initial allocation")
	check(layout.get_containers()[0]["used"] == 2 and layout.get_containers()[1]["used"] == 1, "stack occupies one slot")
	check(carried == original_items, "canonical items are never modified")
	config[0]["capacity"] = 900
	check(layout.get_capacity() == 4, "configuration input is isolated")
	groups += 1

	var before := state(layout)
	for bad_capacity in [-1, 0, 1000001, 2.0, true, "2", null]:
		var bad := definitions()
		bad[0]["capacity"] = bad_capacity
		check(not layout.configure(bad, carried) and state(layout) == before, "invalid capacity is atomic: " + str(bad_capacity))
	for bad in [[], [{"id": "coat", "kind": "pocket", "capacity": 1}], [{"id": "coat", "kind": "pocket", "capacity": 2}, {"id": "coat", "kind": "backpack", "capacity": 2}], [{"id": "", "kind": "pocket", "capacity": 3}], [{"id": "x", "kind": "magic", "capacity": 3}], [{"id": "coat", "kind": "pocket", "capacity": 1000000}, {"id": "bag", "kind": "backpack", "capacity": 1}]]:
		check(not layout.configure(bad, carried) and state(layout) == before, "invalid/occupied container edit leaves state")
	groups += 1

	check(layout.move("a", "bag", carried), "move whole stack into last bag slot")
	check(layout.get_container_id("a") == "bag" and layout.get_container_id("b") == "coat", "move preserves unrelated locations")
	before = state(layout)
	check(layout.move("a", "bag", carried) and state(layout) == before, "same location is idempotent")
	check(not layout.move("b", "bag", carried) and state(layout) == before, "full destination rejects atomically")
	check(not layout.move("missing", "coat", carried) and state(layout) == before, "stale instance rejected")
	check(not layout.move("b", "missing", carried) and state(layout) == before, "missing destination rejected")
	check(not layout.configure([definitions()[0]], carried) and state(layout) == before, "cannot silently drop occupied backpack")
	groups += 1

	carried.erase(carried[2]) # c was consumed/sold; a stays in backpack.
	check(layout.reconcile(carried), "removed item frees its slot")
	check(layout.get_container_id("c") == "" and layout.get_container_id("a") == "bag", "no reassignment of remaining items")
	carried.append(entry("d"))
	check(layout.reconcile(carried) and layout.get_container_id("d") == "coat", "new item fills first actual vacancy")
	carried.append(entry("e"))
	check(layout.reconcile(carried) and layout.get_container_id("e") == "bag", "new item fills second storage")
	before = state(layout)
	check(not layout.reconcile(carried + [entry("overflow")]) and state(layout) == before, "over-capacity batch rolls back")
	groups += 1

	for invalid in [[entry("a"), entry("a")], [{}], [{"instance_id": 1}], [{"instance_id": ""}], [null], ["item"]]:
		check(not layout.reconcile(invalid) and state(layout) == before, "invalid carried identity rejected")
		check(not layout.configure(definitions(), invalid) and state(layout) == before, "invalid identity does not reconfigure")
	# A failed operation must not commit the removal of a stale assignment either.
	check(not layout.move("unknown", "coat", [entry("a")]) and state(layout) == before, "failed move does not commit reconciliation")
	groups += 1

	var reordered := [definitions()[1], definitions()[0]]
	check(layout.configure(reordered, carried), "reordering definitions permitted")
	check(layout.get_container_id("a") == "bag" and layout.get_container_id("d") == "coat", "definition order cannot move belongings")
	var snapshot: Dictionary = layout.get_save_data()
	var fresh: RefCounted = script.new()
	check(fresh.configure(definitions(), []), "fresh storage config")
	check(fresh.load_placements(snapshot, carried), "restore exact assignments")
	check(fresh.get_container_id("a") == "bag" and fresh.get_container_id("d") == "coat", "restored locations not repacked")
	groups += 1

	var saved_copy := snapshot.duplicate(true)
	snapshot["placements"]["a"] = "coat"
	check(fresh.get_container_id("a") == "bag" and layout.get_container_id("a") == "bag", "snapshot cannot mutate either layout")
	var exposed: Array = fresh.get_containers()
	exposed[0]["capacity"] = 100
	check(fresh.get_capacity() == 4, "query copy cannot increase capacity")
	before = state(fresh)
	var corrupt: Array = [{}, {"placements": []}, {"placements": {}}, {"placements": {"a": "bag", "b": "coat", "d": "coat", "e": "unknown"}}, {"placements": {"a": "coat", "b": "coat", "d": "coat", "e": "bag"}}]
	var missing := saved_copy.duplicate(true)
	missing["placements"].erase("a")
	corrupt.append(missing)
	var extra := saved_copy.duplicate(true)
	extra["placements"]["ghost"] = "bag"
	corrupt.append(extra)
	for broken in corrupt:
		check(not fresh.load_placements(broken, carried) and state(fresh) == before, "corrupt placements leave live state intact")
	groups += 1

	check(layout.reconcile([]), "removing all carried items empties occupancy")
	check(layout.configure([], []) and layout.get_capacity() == 0, "empty containers may be removed")
	check(not layout.reconcile([entry("a")]), "no invisible storage without containers")
	check(layout.load_placements({"placements": {}}, []), "empty round trip")
	check(layout.get_container_id("a") == "", "cleared storage has no old ownership")
	groups += 1

	if failures.is_empty() and groups == 8:
		print("ASHBOUND_STORAGE_LAYOUT_OK groups=8")
		quit(0)
	else:
		printerr("ASHBOUND_STORAGE_LAYOUT_FAILED groups=%d failures=%d" % [groups, failures.size()])
		quit(1)
