extends SceneTree
## Codex QA. Every candidate is checked against immutable expectations, not
## against a second copy of the gameplay implementation.
const Schema = preload("res://scripts/courtyard/courtyard_save_schema.gd")
const Persistence = preload("res://scripts/courtyard/courtyard_persistence.gd")
var failures: Array[String] = []
var groups := 0
var level: Node
var inventory: Node
var player: Node3D
var panel: Control
var schema: RefCounted
var progress: Node
var store_node: Node
var root_path := "res://.tools/courtyard-save-qa-" + str(Time.get_ticks_usec())
var observe_expected: Dictionary = {}
var observed := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("COURTYARD_SAVE_FAIL: " + why)

func settle(frames: int = 3) -> void:
	for i in frames: await physics_frame
	await process_frame
	await process_frame

func item(id: String) -> Dictionary:
	for entry in inventory.get_save_data().items:
		if entry.id == id: return entry
	return {}

func on_restored() -> void:
	observed += 1
	check(schema.capture(level,inventory) == observe_expected, "observers see entire coherent snapshot")
	check(not schema.apply(level,inventory,observe_expected), "reentrant apply rejected")

func _run() -> void:
	inventory = root.get_node("Inventory")
	schema = Schema.new()
	level = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await settle(6)
	player = level.get_node("Actors/Player")
	panel = level.get_node("InventoryMenu/RootControl/Overlay/Window")
	progress = player.get_node("Progression")
	check(level.get_node_or_null("Persistence") == null,"embedded QA level must not touch normal save")
	var empty: Dictionary = schema.capture(level,inventory)
	check(schema.validate(empty,inventory), "fresh courtyard validates")
	check(empty.progress.learning_points == 0 and empty.quest.state == 0 and empty.map_available and empty.inventory.items.is_empty(),"fresh start actual data")
	groups += 1

	# Real inventory APIs create/equip the fixture, no raw inventory field writes.
	check(inventory.add_item("traveler_backpack"),"backpack fixture")
	check(inventory.equip_storage_item(item("traveler_backpack")),"wear backpack")
	check(inventory.add_item("leather_armor") and inventory.equip_item(item("leather_armor")),"wear whole armor")
	check(inventory.add_item("rusty_sword") and inventory.equip_item(item("rusty_sword")),"equip sword")
	check(inventory.add_item("bread",3),"food fixture")
	check(inventory.move_item_to_storage(item("bread"),"worn_storage:"+str(inventory.get_worn_storage("backpack").instance_id)),"bread to worn bag")
	check(inventory.add_item("courtyard_sketch"),"map fixture")
	level.get_node("Interactions/MapStand").available_on_crate = false
	inventory.add_gold(9223372036854775807)
	check(progress.award_learning_points("save_qa_award",17),"award ledger fixture")
	level._on_innkeeper_interact()
	level._on_woodpile_interact()
	level._on_innkeeper_interact()
	level._on_watchman_interact()
	level.dummy_hits = 3
	level._apply_state(5)
	level._on_watchman_interact()
	panel._quick_bindings[0] = str(item("bread").instance_id)
	panel._quick_bindings[9] = str(inventory.get_equipped("weapon").instance_id)
	player.global_position = Vector3(2,0,4)
	player.facing_direction = Vector3.RIGHT
	level.get_node("CameraRig")._yaw = 0.8
	level.get_node("CameraRig")._pitch = -0.2
	var rich: Dictionary = schema.capture(level,inventory)
	check(schema.validate(rich,inventory),"complete equipped snapshot validates")
	check(rich.quest.state == 6 and rich.quest.reward_claimed and rich.progress.guard_practice_completed,"finished quest linked to practice")
	check(rich.inventory.gold == 9223372036854775807 and rich.quick[0] != "" and rich.quick[9] != "","int64 and bindings captured")
	groups += 1

	check(schema.apply(level,inventory,empty),"apply empty snapshot")
	check(inventory.get_worn_storage("backpack").is_empty() and inventory.get_item_count("bread") == 0,"old equipment and items cleared")
	check(schema.validate(rich,inventory),"incoming quick references validated against incoming items")
	observe_expected = rich
	inventory.inventory_restored.connect(on_restored)
	check(schema.apply(level,inventory,bytes_to_var(var_to_bytes(rich))),"typed full snapshot roundtrip")
	inventory.inventory_restored.disconnect(on_restored)
	check(observed == 1,"single coherent restoration event")
	check(schema.capture(level,inventory) == rich,"all fields restored exactly")
	check(not progress.award_learning_points("save_qa_award",17),"award cannot be repeated after load")
	check(not level.get_node("Interactions/MapStand/Paper").visible,"carried map not duplicated on crate")
	check(not level.get_node("Interactions/Woodpile/Label3D").visible,"collected wood presentation restored")
	check(not panel.get_node("Margin/RootVBox/Header/SectionTabs/MapTab").disabled,"restored map accessible")
	groups += 1

	var invalids: Array[Dictionary] = []
	for key in rich:
		var missing: Dictionary = rich.duplicate(true)
		missing.erase(key)
		invalids.append(missing)
	for value in [0,2,"1",1.0]:
		var wrong: Dictionary = rich.duplicate(true); wrong.schema_version=value; invalids.append(wrong)
	for pair in [["state","6"],["state",7],["state",-1],["dummy_hits",2],["reward_claimed",false]]:
		var wrong: Dictionary = rich.duplicate(true); wrong.quest[pair[0]]=pair[1]; invalids.append(wrong)
	var bad: Dictionary = rich.duplicate(true); bad.progress.guard_practice_completed=false; invalids.append(bad)
	bad=rich.duplicate(true); bad.map_available=true; invalids.append(bad)
	bad=rich.duplicate(true); bad.player.position=Vector3(NAN,0,0); invalids.append(bad)
	bad=rich.duplicate(true); bad.player.position=Vector3(100,0,0); invalids.append(bad)
	bad=rich.duplicate(true); bad.player.facing=Vector3.ZERO; invalids.append(bad)
	bad=rich.duplicate(true); bad.camera.pitch=1.0; invalids.append(bad)
	bad=rich.duplicate(true); bad.camera.yaw="0.8"; invalids.append(bad)
	bad=rich.duplicate(true); bad.quick[0]="missing_instance"; invalids.append(bad)
	bad=rich.duplicate(true); bad.quick[0]=str(item("courtyard_sketch").instance_id); invalids.append(bad)
	bad=rich.duplicate(true); bad.inventory.gold=-1; invalids.append(bad)
	bad=rich.duplicate(true); bad.inventory.storage={}; invalids.append(bad)
	for candidate in invalids:
		check(not schema.validate(candidate,inventory),"malformed snapshot rejected")
		check(not schema.apply(level,inventory,candidate),"invalid apply refused")
		check(schema.capture(level,inventory)==rich,"invalid apply is atomic")
	groups += 1

	# Partial practice is valid; neither another reward nor a completed lesson.
	var practice: Dictionary = rich.duplicate(true)
	practice.quest.state=4; practice.quest.dummy_hits=2; practice.progress.guard_practice_completed=false
	check(schema.apply(level,inventory,practice),"two training hits load")
	check(level.get_journal_entry().params.hits==2 and not progress.get_character_data().guard_practice_completed,"partial practice remains partial")
	var stale: Array[String] = panel._quick_bindings.duplicate()
	stale[3]="deleted_instance"; panel._quick_bindings=stale
	var normalized: Dictionary = schema.capture(level,inventory)
	check(normalized.quick[3]=="" and panel._quick_bindings[3]=="deleted_instance","capture normalizes copied bindings only")
	check(schema.apply(level,inventory,practice),"restore valid fixture")
	groups += 1

	store_node = Persistence.new(); store_node.name="SaveQACoordinator"; level.add_child(store_node)
	check(store_node.initialize(level,root_path)=="empty","isolated save starts empty")
	var previous_count: int = store_node.save_count
	check(store_node.flush_now() and store_node.save_count==previous_count,"unchanged snapshot does not write")
	level._apply_state(5); level.dummy_hits=3
	# Burst completes synchronously before queued save, like real signal mutations.
	level._on_watchman_interact()
	await settle(3)
	check(store_node.save_count==previous_count+1,"burst produces one complete deferred save")
	var saved: Dictionary = schema.capture(level,inventory)
	check(saved.quest.state==6,"saved finished state")
	store_node.enabled=false
	check(schema.apply(level,inventory,empty),"erase live fixture before file load")
	store_node.queue_free(); await settle()
	store_node=Persistence.new(); level.add_child(store_node)
	check(store_node.initialize(level,root_path)=="loaded","file load on new coordinator")
	check(inventory.get_save_data()==saved.inventory and progress.get_save_data()==saved.progress and level.state==6,"file restores all domains")
	var menu: Node = level.get_node("InventoryMenu")
	check(menu.request_open() and menu.get_menu_state()==1,"loaded game permits physical inventory gesture")
	await settle(55)
	check(menu.get_menu_state()==2 and panel.visible,"loaded menu actually opens")
	panel._sections.select_section("map")
	check(panel._sections.current_section=="map","loaded map page opens")
	panel._sections.select_section("quests")
	check(level.get_journal_entry().completed,"loaded completed quest remains viewable")
	var close_events: Array[bool] = []
	var reenter_close := func() -> void: close_events.append(schema.apply(level,inventory,empty))
	menu.closed.connect(reenter_close)
	check(schema.apply(level,inventory,saved),"restore closes active menu coherently")
	menu.closed.disconnect(reenter_close)
	check(close_events == [false] and level.state==6,"menu close callback cannot reenter snapshot application")
	groups += 1

	level.reset_lesson()
	await settle()
	check(level.state==0 and inventory.get_item_count("courtyard_sketch")==1 and not level.get_node("Interactions/MapStand").available_on_crate,"restart lesson keeps map source coherent")
	check(store_node.flush_now(),"reset checkpoint writes")
	check(player.input_enabled and level.get_node("InventoryMenu").get_menu_state()==0,"loaded/reset state releases controls")
	groups += 1

	player.global_position=Vector3(3,0,5)
	store_node.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var load_store = load("res://scripts/courtyard/courtyard_save_store.gd").new()
	load_store.directory=root_path
	var accepted := func(data:Dictionary)->bool:return schema.validate(data,inventory)
	check(load_store.load_latest(accepted).payload.player.position==Vector3(3,0,5),"background notification writes latest position immediately")
	groups += 1

	store_node.enabled=false
	store_node.queue_free(); await settle()
	var broken_path:=root_path+"-corrupt"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(broken_path))
	var broken_file:=FileAccess.open(broken_path.path_join("slot0.sav"),FileAccess.WRITE)
	broken_file.store_buffer(PackedByteArray([1,2,3])); broken_file.close()
	var before_bad:Dictionary=schema.capture(level,inventory)
	store_node=Persistence.new();level.add_child(store_node)
	check(store_node.initialize(level,broken_path)=="invalid","corrupt checkpoint reported")
	check(schema.capture(level,inventory)==before_bad and not store_node.flush_now(),"invalid load never replaces live state or overwrites files")
	check(FileAccess.get_file_as_bytes(broken_path.path_join("slot0.sav"))==PackedByteArray([1,2,3]),"invalid file retained")
	store_node.enabled=false
	groups += 1

	level.queue_free(); await settle()
	check(groups==9,"all nine integration groups completed")
	if failures.is_empty(): print("ASHBOUND_COURTYARD_SAVE_OK groups=",groups," invalids=",invalids.size())
	quit(0 if failures.is_empty() else 1)
