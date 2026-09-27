extends SceneTree
## Codex acceptance: category matrix and exact persistent cell ownership.
const Rules = preload("res://scripts/systems/item_rules.gd")
const Layout = preload("res://scripts/systems/inventory_storage_layout.gd")
var failures: Array[String] = []
var groups := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("ITEM_BEHAVIOR_FAIL: " + why)
func entry(id: String) -> Dictionary: return {"instance_id":id}
func _run() -> void:
	var inv: Node = root.get_node("Inventory")
	var expected := {
		"courtyard_sketch":["object","map","",true,true],
		"rusty_sword":["weapon","sword","weapon",true,true],
		"leather_armor":["clothing","armor_set","armor",false,true],
		"bread":["consumable","food","",true,true],
		"sacred_ash":["object","quest_object","",false,false]
	}
	for id: String in expected:
		var d: Dictionary = inv.describe_item_id(id)
		check(not d.is_empty(), "catalog classification " + id)
		if d.is_empty(): continue
		var e: Array = expected[id]
		check(d.category==e[0] and d.subtype==e[1] and d.equipment_slot==e[2] and d.quick_bindable==e[3] and d.droppable==e[4], "matrix " + id)
		for slot in ["weapon","armor","backpack","pouch"]: # bags were removed (D-057): nothing equips there
			check(Rules.can_equip(inv.item_database[id],slot)==(slot==e[2]), "reject incompatible " + id + " -> " + slot)
	var enchanted := {"id":"qa_sword","type":0,"slot":"weapon","category":"weapon","subtype":"sword","tags":["magic"],"quest_locked":true}
	check(Rules.has_tag(enchanted,"magic") and not Rules.can_drop(enchanted) and Rules.can_equip(enchanted,"weapon"),"orthogonal quest/magic/weapon")
	for subtype in ["scroll","rune"]:
		var magic := {"id":"qa_"+subtype,"type":5,"category":"magic","subtype":subtype}
		check(Rules.can_quick(magic) and Rules.has_tag(magic,"magic") and not Rules.can_equip(magic,"weapon"),"magic policy " + subtype)
	check(Rules.describe({}).is_empty() and Rules.describe({"id":"x","type":99}).is_empty(),"unknown invalid policy")
	groups += 1

	var layout = Layout.new()
	var defs := [{"id":"coat:a","kind":"pocket","capacity":6},{"id":"bag","kind":"wallet","capacity":2}]
	var carried := [entry("a"),entry("b"),entry("c")]
	check(layout.configure(defs,carried),"configure cells")
	check(layout.move("a","coat:a",carried,5) and layout.get_cell_index("a")==5,"move into distant empty cell")
	check(layout.move("b","coat:a",carried,5) and layout.get_cell_index("a")==1 and layout.get_cell_index("b")==5,"swap occupied cells")
	carried.erase(carried[0])
	check(layout.reconcile(carried) and layout.get_cell_index("b")==5 and layout.get_cell_index("c")==2,"removal preserves holes")
	carried.push_front(entry("new"))
	check(layout.reconcile(carried) and layout.get_cell_index("b")==5 and layout.get_cell_index("c")==2 and layout.get_cell_index("new")==0,"early new entry cannot steal existing cell")
	check(layout.move("b","bag",carried,1),"explicit cross-container cell")
	check(layout.move("c","bag",carried,0),"fill bag")
	var full: Dictionary = layout.get_save_data()
	check(not layout.move("new","bag",carried) and layout.get_save_data()==full,"legacy auto target full rejects atomically")
	check(layout.move("new","bag",carried,1),"swap across full containers")
	check(layout.get_container_id("b")=="coat:a" and layout.get_cell_index("b")==0 and layout.get_cell_index("new")==1,"displaced item enters original cell")
	var before: Dictionary = layout.get_save_data()
	for index in [-2,2,2147483647]:
		check(not layout.move("new","bag",carried,index) and layout.get_save_data()==before,"invalid target atomic " + str(index))
	check(not layout.move("missing","bag",carried,0) and layout.get_save_data()==before,"stale drag")
	groups += 1

	var fresh = Layout.new()
	check(fresh.configure(defs,[]) and fresh.load_placements(before,carried),"restore cells into empty runtime")
	check(fresh.get_save_data()==before,"exact cell roundtrip")
	var legacy: Dictionary = before.duplicate(true)
	legacy.erase("cells")
	check(fresh.load_placements(legacy,carried) and fresh.get_container_id("new")=="bag","old placements migrate")
	check(fresh.load_placements(before,carried),"restore original cells")
	for cells in [null,[],{}, {"b":0,"c":0,"new":0}, {"b":0,"c":0,"new":1,"ghost":0}, {"b":0,"c":0,"new":1.0}, {"b":0,"c":0,"new":2}]:
		var bad: Dictionary = before.duplicate(true)
		bad.cells = cells
		check(not fresh.load_placements(bad,carried) and fresh.get_save_data()==before,"malformed saved cells refused")
	groups += 1

	check(inv.configure_storage([{"id":"qa-pocket","kind":"pocket","capacity":6}]),"inventory fixture")
	check(inv.add_item("courtyard_sketch") and inv.add_item("sacred_ash") and inv.add_item("cultist_blade"),"canonical items")
	var map: Dictionary = inv.items[0].duplicate(true)
	map.type=1; map.slot="armor"; map.tags=["magic"]
	check(inv.can_assign_quick(map) and not inv.can_equip_in_slot(map,"armor"),"forged caller capabilities ignored")
	check(inv.move_item_to_cell(map,"qa-pocket",4) and inv.get_item_cell(map.instance_id)==4,"inventory cell API")
	check(inv.has_carried_tag("magic"),"carried enchanted weapon detected")
	var quest: Dictionary = inv.items[1].duplicate(true)
	inv.items[1].value=500
	var snapshot: Dictionary = inv.get_save_data()
	check(not inv.sell_item(quest) and inv.get_save_data()==snapshot,"valuable quest item cannot be sold")
	check(inv.remove_item("sacred_ash"),"explicit quest hand-in remains possible")
	check(inv.remove_item("cultist_blade") and not inv.has_carried_tag("magic"),"lost magic item not detected")
	check(inv.load_save_data(snapshot),"inventory cells reload")
	check(inv.get_item_cell(map.instance_id)==4,"chosen cell survives inventory load")
	groups += 1
	if failures.is_empty() and groups==4:
		print("ASHBOUND_ITEM_BEHAVIOR_OK groups=4")
		quit(0)
	else:
		printerr("ASHBOUND_ITEM_BEHAVIOR_FAILED groups=%d failures=%d" % [groups,failures.size()])
		quit(1)
