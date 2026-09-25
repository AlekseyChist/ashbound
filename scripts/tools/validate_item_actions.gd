extends "res://scripts/tools/validate_touch_inventory.gd"
## Codex end-to-end item rules through real touch gestures and world ownership.
const SaveSchema = preload("res://scripts/courtyard/courtyard_save_schema.gd")
var level: Node
var menu: Node
var drops: Node
var save_schema: RefCounted
var observer_calls := 0
var expected_world_id := ""
func observe_drop() -> void:
	observer_calls += 1
	var records: Array = drops.get_records()
	check(records.size()==1 and records[0].item.instance_id==expected_world_id,"drop observer sees world item")
	check(inv.resolve_owned_item({"instance_id":expected_world_id}).is_empty(),"drop observer sees no carried copy")
	check(not drops.drop_item({"instance_id":expected_world_id}),"reentrant drop rejected")
	check(not inv.remove_item("bread"),"reentrant inventory mutation rejected")
	check(not drops.drop_item(item("bread")),"reentrant second owned drop rejected")
	check(save_schema.validate(save_schema.capture(level,inv),inv),"observer coherent save")
func no_collisions(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D: return false
	for child in node.get_children():
		if not no_collisions(child): return false
	return true
func run() -> void:
	root.size = Vector2i(1920,1080)
	await process_frame
	inv=root.get_node("Inventory")
	loc=root.get_node("Localization")
	loc.load_preferences("res://.tools/item-actions-language.cfg","en_US")
	level=load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await create_timer(0.3).timeout
	menu=level.get_node("InventoryMenu")
	panel=menu.get_node("RootControl/Overlay/Window")
	drops=level.get_node("WorldItems")
	save_schema=SaveSchema.new()
	check(inv.add_item("courtyard_sketch") and inv.add_item("bread",3),"map and stack fixture")
	level.get_node("Interactions/MapStand").available_on_crate=false
	var map: Dictionary=item("courtyard_sketch").duplicate(true)
	var food: Dictionary=item("bread").duplicate(true)
	check(menu.request_open(),"physical opening starts")
	await create_timer(1.1).timeout
	check(menu.state==2 and panel.visible,"opened only after gesture")
	await carry(cell_pos(map.instance_id),panel._cell_nodes[4].get_global_rect().get_center())
	check(inv.get_item_cell(map.instance_id)==4,"touch move to empty cell")
	await carry(cell_pos(map.instance_id),cell_pos(food.instance_id))
	check(inv.get_item_cell(map.instance_id)==1 and inv.get_item_cell(food.instance_id)==4,"touch occupied swap")
	var before: Dictionary=inv.get_save_data()
	for slot in ["ArmorSlot","WeaponSlot"]:
		await carry(cell_pos(map.instance_id),center(slot))
		check(inv.get_save_data()==before,"map cannot equip as "+slot)
	await carry(cell_pos(map.instance_id),panel._cell_nodes[3].get_global_rect().get_center(),true)
	check(inv.get_save_data()==before,"canceled move does not mutate")
	await carry(cell_pos(map.instance_id),panel._quick_cells[0].get_global_rect().get_center())
	check(panel._quick_bindings[0]==map.instance_id,"map quick assignment by drag")
	check(inv.get_save_data()==before,"assignment is reference only")
	await tap(panel._quick_cells[0].get_global_rect().get_center())
	check(panel._sections.current_section=="map","touch quick slot opens carried map")
	panel._sections.select_section("items")
	await settle()
	groups+=1

	var owned_snapshot: Dictionary=save_schema.capture(level,inv)
	check(save_schema.validate(owned_snapshot,inv),"map quick save valid")
	menu.close_menu(false)
	await settle()
	var quick_key := InputEventKey.new()
	quick_key.physical_keycode=KEY_1
	quick_key.pressed=true
	root.push_input(quick_key,true)
	quick_key=quick_key.duplicate()
	quick_key.pressed=false
	root.push_input(quick_key,true)
	check(menu.state==1,"physical 1 key uses normal opening")
	check(menu.state==1 and not panel.visible,"quick request does not skip gesture")
	await create_timer(1.1).timeout
	check(panel._sections.current_section=="map","quick request reaches map after gesture")
	panel._sections.select_section("items")
	await settle()
	check(inv.add_item("sacred_ash"),"quest fixture")
	var quest: Dictionary=item("sacred_ash").duplicate(true)
	var protected_before: Dictionary=inv.get_save_data()
	check(not drops.drop_item(quest) and inv.get_save_data()==protected_before and drops.get_records().is_empty(),"quest item stays owned")
	check(not panel.can_drop_instance(quest.instance_id),"quest discard UI disabled")
	groups+=1

	# A drag can drop an unselected item; no accidental release outside the window.
	panel._selected_item_id=""
	panel.refresh_contents()
	await settle()
	expected_world_id=map.instance_id
	inv.inventory_restored.connect(observe_drop)
	await carry(cell_pos(map.instance_id),panel._drop_button.get_global_rect().get_center())
	inv.inventory_restored.disconnect(observe_drop)
	check(observer_calls==1,"one coherent ownership commit")
	check(drops.get_records().size()==1 and not inv.has_item("courtyard_sketch"),"map on ground instead of carried")
	check(panel._quick_bindings[0]=="" and not panel.activate_quick(0),"drop invalidates quick reference")
	check(not panel._sections._map_view.has_map(),"ground map cannot be opened")
	var points: Array=drops.get_points()
	check(points.size()==1 and no_collisions(drops),"visible pickup without any physics collision")
	if points.size()==1:
		var sprite: Sprite3D=points[0].get_node("Visual")
		check(sprite.texture!=null and sprite.billboard==BaseMaterial3D.BILLBOARD_FIXED_Y,"item faces camera")
		check(points[0].global_position.distance_to(level.get_node("Actors/Player").global_position)<1,"drop near feet")
	var ground: Dictionary=save_schema.capture(level,inv)
	check(save_schema.validate(ground,inv),"world ownership saves")
	menu.close_menu(false)
	await settle()
	await capture("item-ground")
	for pair in [["position",Vector3(NAN,0,0)],["position",Vector3(100,0,0)],["position","0,0,0"],["item",{}]]:
		var malformed:Dictionary=ground.duplicate(true)
		malformed.world_items[0][pair[0]]=pair[1]
		check(not save_schema.validate(malformed,inv),"malformed world field rejected: "+str(pair[0]))
	var quest_on_ground:Dictionary=ground.duplicate(true)
	quest_on_ground.world_items[0].item=quest.duplicate(true)
	check(not save_schema.validate(quest_on_ground,inv),"quest cannot be smuggled into ground snapshot")
	var ghost_quantity:Dictionary=ground.duplicate(true)
	ghost_quantity.world_items[0].item.quantity=0
	check(not save_schema.validate(ghost_quantity,inv),"zero ground quantity rejected")
	check(save_schema.apply(level,inv,owned_snapshot),"restore carried snapshot")
	check(drops.get_records().is_empty() and inv.has_item("courtyard_sketch"),"restore clears former world ownership")
	check(save_schema.apply(level,inv,ground),"restore dropped snapshot")
	check(not menu.request_quick(0),"dropped map hotkey refuses to open")
	check(not inv.has_item("courtyard_sketch") and drops.get_records()[0].item.instance_id==map.instance_id,"world ID restored exactly")
	var invalid: Dictionary=ground.duplicate(true)
	invalid.world_items.append(invalid.world_items[0].duplicate(true))
	check(not save_schema.apply(level,inv,invalid) and save_schema.capture(level,inv)==ground,"duplicate world record refused atomically")
	invalid=owned_snapshot.duplicate(true)
	invalid.world_items=ground.world_items.duplicate(true)
	check(not save_schema.validate(invalid,inv),"same instance cannot be carried and dropped")
	groups+=1

	# Full inventory must not remove ground item; pickup uses real physics reachability.
	for i in range(inv.get_effective_capacity()-inv.items.size()):
		check(inv.add_item("rusty_sword"),"fill pocket")
	var full: Dictionary=save_schema.capture(level,inv)
	await physics_frame
	check(not drops.try_pickup(map.instance_id) and save_schema.capture(level,inv)==full,"full pickup preserves item")
	check(inv.remove_item("rusty_sword"),"free a cell")
	await physics_frame
	check(drops.try_pickup(map.instance_id),"pickup once after space available")
	check(inv.resolve_owned_item({"instance_id":map.instance_id}).id=="courtyard_sketch" and drops.get_records().is_empty(),"pickup original ID")
	await physics_frame
	check(not drops.try_pickup(map.instance_id) and inv.get_item_count("courtyard_sketch")==1,"repeat pickup cannot duplicate")
	# Real queued Action/E route, rather than only direct manager API.
	check(drops.drop_item(map),"drop for interaction route")
	level._on_hud_interact()
	for i in 4: await physics_frame
	check(inv.has_item("courtyard_sketch") and drops.get_records().is_empty(),"queued gameplay action picks up ground item")
	var old: Dictionary=owned_snapshot.duplicate(true)
	old.schema_version=1
	old.erase("world_items")
	old.inventory.storage.erase("cells")
	check(save_schema.validate(old,inv) and save_schema.apply(level,inv,old),"0.11 save upgrades without losing map")
	check(inv.has_item("courtyard_sketch") and panel._quick_bindings[0]==map.instance_id,"old item and binding preserved")
	groups+=1

	# Both languages remain usable and the discard target fits the phone viewport.
	check(menu.request_open(),"reopen items")
	await create_timer(1.1).timeout
	for language in ["en","ru"]:
		loc.load_preferences("res://.tools/item-actions-language.cfg",language)
		await settle()
		check(panel.get_global_rect().grow(1).encloses(panel._drop_button.get_global_rect()),"discard fits "+language)
		check(panel._drop_button.size.x>=150 and panel._drop_button.size.y>=80,"finger-sized discard")
		check(panel._drop_button.text != "INV_DROP_ITEM","discard localized "+language)
		await capture("item-drop-disabled-"+language)
		await tap(cell_pos(map.instance_id))
		await capture("item-drop-selected-"+language)
		panel._selected_item_id=""
		panel.refresh_contents()
		await settle()
	await capture("item-actions")
	var drag_from:Vector2=cell_pos(map.instance_id)
	var drag_to:Vector2=panel._drop_button.get_global_rect().get_center()
	send_touch(drag_from,true)
	# The touch hold is measured in wall time, independent of rendered-frame deltas.
	var held_at:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-held_at<300:
		await process_frame
	send_motion(drag_from+Vector2(10,0),Vector2(10,0))
	await process_frame
	send_motion(drag_to,drag_to-drag_from-Vector2(10,0))
	await process_frame
	check(panel._ghost.visible,"discard hover displays carried preview")
	check(panel._gesture_handler._drop_target_valid(panel._gesture_handler._hit_test(drag_to)),"discard hover accepts carried map")
	await settle()
	await capture("item-drop-preview")
	send_touch(drag_to,false,0,true)
	await settle()
	check(inv.has_item("courtyard_sketch") and drops.get_records().is_empty(),"discard preview cancel preserves item")
	# S23 regression: selected-item button discard emits inventory changes before
	# selection clears. Refresh must tolerate the now-stale selected instance.
	await tap(cell_pos(map.instance_id))
	check(panel._selected_item_id==map.instance_id and not panel._drop_button.disabled,"selected discard enabled")
	await tap(panel._drop_button.get_global_rect().get_center())
	check(not inv.has_item("courtyard_sketch") and drops.get_records().size()==1,"button discards selected item once")
	check(panel._selected_item_id=="" and panel._drop_button.disabled,"selection and button coherent after discard")
	menu.close_menu(false)
	level._on_hud_interact()
	for i in 4:await physics_frame
	check(inv.has_item("courtyard_sketch") and drops.get_records().is_empty(),"button discard pickup")
	groups+=1
	level.queue_free()
	await process_frame
	if failures.is_empty() and groups==5:
		print("ASHBOUND_ITEM_ACTIONS_OK groups=5")
		quit(0)
	else:
		printerr("ASHBOUND_ITEM_ACTIONS_FAILED groups=%d failures=%d" % [groups,failures.size()])
		quit(1)
