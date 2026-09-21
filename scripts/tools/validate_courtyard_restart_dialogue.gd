extends "res://scripts/tools/validate_touch_inventory.gd"
## Owner regressions: dismiss a conversation, then fully restart a dirty courtyard.
var level:Node
var hud:Node
var player:Node3D
var worlds:Node
var schema:RefCounted
var observed_resets:=0

func key(code:Key) -> void:
	for down in [true,false]:
		var e:=InputEventKey.new()
		e.physical_keycode=code
		e.keycode=code
		e.pressed=down
		root.push_input(e,true)
	await settle()

func open_host_message() -> void:
	player.global_position=level.get_node("Actors/Innkeeper").global_position+Vector3(0,0,1.5)
	level._on_point_interacted(level.get_node("Actors/Innkeeper"))
	check(hud._message_visible,"host message fixture visible")

func observe_reset() -> void:
	observed_resets+=1
	level._on_restart_pressed()
	check(worlds.get_records().is_empty() and worlds.get_points().is_empty(),"observer sees no dropped copy")
	check(level.get_node("Interactions/MapStand").available_on_crate,"observer sees original map restored")
	check(inv.items.is_empty() and inv.gold==0 and level.state==0,"observer sees complete new start")
	check(schema.validate(schema.capture(level,inv),inv),"observer sees valid reset snapshot")

func run() -> void:
	root.size=Vector2i(1920,1080)
	inv=root.get_node("Inventory")
	loc=root.get_node("Localization")
	loc.load_preferences("res://.tools/restart-dialogue-language.cfg","en_US")
	level=load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	level.get_node("HUD").force_touch_controls=true
	root.add_child(level)
	await settle()
	player=level.get_node("Actors/Player")
	hud=level.get_node("HUD")
	worlds=level.get_node("WorldItems")
	panel=level.get_node("InventoryMenu/RootControl/Overlay/Window")
	schema=load("res://scripts/courtyard/courtyard_save_schema.gd").new()
	var baseline:Dictionary=schema.capture(level,inv)
	open_host_message()
	var quest_before:int=level.state
	await key(KEY_E)
	check(not hud._message_visible and level.state==quest_before and not level._pending_interact,"E dismisses without replaying interaction")
	open_host_message()
	await key(KEY_ESCAPE)
	check(not hud._message_visible,"Escape dismisses dialogue")
	# Headless DisplayServer cannot capture the mouse. This case must also run
	# with -Render, where real capture and its event routing are available.
	if DisplayServer.get_name()!="headless":
		open_host_message()
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"graphical fixture captures mouse")
		for down in [true,false]:
			var click:=InputEventMouseButton.new()
			click.device=0
			click.button_index=MOUSE_BUTTON_LEFT
			click.pressed=down
			click.position=Vector2(900,500)
			root.push_input(click,true)
		await settle()
		check(not hud._message_visible and not player.is_attacking(),"captured LMB dismisses without attack")
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	player.stop_input()
	open_host_message()
	await tap(hud._message_panel.get_global_rect().get_center())
	check(not hud._message_visible,"touch panel dismisses")
	open_host_message()
	await tap(hud._btn_interact.get_global_rect().get_center())
	check(not hud._message_visible and not level._pending_interact,"touch action dismisses without repeat")
	open_host_message()
	player.global_position=Vector3(5,0,7)
	for i in 3:await physics_frame
	check(not hud._message_visible,"walking away dismisses conversation")
	await capture("dialogue-dismissed")
	groups+=1

	check(schema.apply(level,inv,baseline),"restore initial fixture")
	check(inv.add_item("traveler_backpack"),"backpack fixture")
	check(inv.equip_storage_item(item("traveler_backpack")),"wear backpack")
	for id in ["courtyard_sketch","bread","rusty_sword","sacred_ash"]:
		check(inv.add_item(id),"dirty inventory "+id)
	check(inv.equip_item(item("rusty_sword")),"equip sword")
	var map:Dictionary=item("courtyard_sketch").duplicate(true)
	level.get_node("Interactions/MapStand").available_on_crate=false
	panel._quick_bindings[0]=item("bread").instance_id
	check(worlds.drop_item(map),"dirty world contains map")
	var progress:Node=player.get_node("Progression")
	check(progress.award_learning_points("restart_test",3),"dirty progression")
	progress.complete_guard_practice()
	inv.add_gold(52)
	level.state=6
	level.dummy_hits=3
	level.reward_claimed=true
	player.global_position=Vector3(5,0,7)
	level._pending_interact=true
	player.request_attack()
	hud.show_message("COURTYARD_NAME_WATCHMAN","COURTYARD_DIALOGUE_GUARD_OTHER")
	var persistence:Node=load("res://scripts/courtyard/courtyard_persistence.gd").new()
	persistence.name="Persistence"
	level.add_child(persistence)
	var directory:String="res://.tools/restart-dialogue-save-"+str(Time.get_ticks_usec())
	check(persistence.initialize(level,directory)=="empty","isolated persistence starts")
	inv.inventory_restored.connect(observe_reset)
	await tap(hud._btn_restart.get_global_rect().get_center())
	inv.inventory_restored.disconnect(observe_reset)
	check(observed_resets==1,"one inventory reset notification")
	check(inv.items.is_empty() and inv.gold==0,"new start clears inventory and money")
	check(inv.get_worn_storage("backpack").is_empty() and inv.get_equipped("weapon").is_empty(),"new start clears all worn equipment")
	check(worlds.get_records().is_empty() and worlds.get_points().is_empty(),"new start clears dropped records and sprites")
	check(level.get_node("Interactions/MapStand").available_on_crate and not inv.has_item("courtyard_sketch"),"map returns exclusively to crate")
	check(panel._quick_bindings.all(func(id):return id==""),"new start clears all quick references")
	check(progress.get_save_data()==baseline.progress,"new start clears training and award history")
	check(level.state==0 and level.dummy_hits==0 and not level.reward_claimed,"new start clears lesson state")
	check(player.global_position.distance_to(level._player_spawn)<0.2 and not player.is_attacking(),"new start resets position and pending attack")
	check(not hud._message_visible and not level._pending_interact,"new start closes dialogue and pending action")
	check(persistence.flush_now(),"new start is saveable")
	var store:RefCounted=load("res://scripts/courtyard/courtyard_save_store.gd").new()
	store.directory=directory
	var result:Dictionary=store.load_latest(func(data):return schema.validate(data,inv))
	check(result.status=="loaded" and result.payload.world_items.is_empty() and result.payload.inventory.items.is_empty() and result.payload.map_available,"disk reload cannot resurrect discarded map")
	check(schema.apply(level,inv,result.payload),"restart checkpoint reloads")
	await tap(hud._btn_restart.get_global_rect().get_center())
	check(worlds.get_records().is_empty() and inv.items.is_empty() and level.get_node("Interactions/MapStand").available_on_crate,"repeat restart does not duplicate map")
	await capture("restart-clean")
	groups+=1
	persistence.enabled=false
	level.queue_free()
	await process_frame
	if failures.is_empty() and groups==2:
		print("ASHBOUND_COURTYARD_RESTART_DIALOGUE_OK groups=2")
		quit(0)
	else:
		printerr("ASHBOUND_COURTYARD_RESTART_DIALOGUE_FAILED groups=%d failures=%d"%[groups,failures.size()])
		quit(1)
