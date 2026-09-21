extends SceneTree
## Codex QA: separate OS processes share ONLY isolated save files.
const Persistence = preload("res://scripts/courtyard/courtyard_persistence.gd")
var failed := false
var path := ""
var phase := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-qa-path="): path=arg.trim_prefix("--save-qa-path=")
		if arg.begins_with("--save-qa-phase="): phase=arg.trim_prefix("--save-qa-phase=")
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	if not ok:
		failed=true
		printerr("SAVE_PROCESS_FAIL: "+why)

func find(inventory: Node,id: String)->Dictionary:
	for item in inventory.get_save_data().items:
		if item.id==id:return item
	return {}

func _run() -> void:
	if not path.begins_with("res://.tools/save-process-") or phase not in ["write","read"]:
		printerr("SAVE_PROCESS_FAIL: explicit isolated QA arguments required");quit(1);return
	var level:Node=load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	for i in 5:await physics_frame
	var player:Node3D=level.get_node("Actors/Player")
	player.set_physics_process(false)
	var inv:Node=root.get_node("Inventory")
	var panel:Control=level.get_node("InventoryMenu/RootControl/Overlay/Window")
	var progress:Node=player.get_node("Progression")
	var persistence:Node=Persistence.new();level.add_child(persistence)
	var status:String=persistence.initialize(level,path)
	if phase=="write":
		check(status=="empty","write starts in new slot")
		check(inv.add_item("traveler_backpack"),"bag fixture")
		check(inv.equip_storage_item(find(inv,"traveler_backpack")),"wear bag")
		check(inv.add_item("bread",3),"bread fixture")
		check(inv.move_item_to_storage(find(inv,"bread"),"worn_storage:"+str(inv.get_worn_storage("backpack").instance_id)),"bread placed in bag")
		check(inv.add_item("courtyard_sketch"),"map fixture")
		level.get_node("Interactions/MapStand").available_on_crate=false
		level._on_innkeeper_interact()
		check(progress.award_learning_points("process_save_qa",11),"award fixture")
		inv.add_gold(23)
		panel._quick_bindings[0]=str(find(inv,"bread").instance_id)
		player.global_position=Vector3(1,0,6)
		player.facing_direction=Vector3.RIGHT
		level.get_node("CameraRig")._yaw=0.7
		level.get_node("CameraRig")._pitch=-0.2
		check(persistence.flush_now(),"checkpoint committed before termination")
		if failed:quit(1);return
		print("ASHBOUND_SAVE_PROCESS_WRITER_READY")
		# Runner kills this exact process, never the user's editor or game.
		return
	check(status=="loaded","fresh process loads prior checkpoint")
	check(level.state==1 and not level.reward_claimed and level.dummy_hits==0,"accepted firewood quest retained")
	check(inv.get_item_count("bread")==3 and inv.gold==23,"items and money retained")
	check(not inv.get_worn_storage("backpack").is_empty(),"equipped backpack retained")
	check(inv.get_item_storage(str(find(inv,"bread").instance_id))=="worn_storage:"+str(inv.get_worn_storage("backpack").instance_id),"placement retained")
	check(inv.get_item_count("courtyard_sketch")==1 and not level.get_node("Interactions/MapStand").available_on_crate,"map source and item consistent")
	check(not level.get_node("Interactions/MapStand/Paper").visible,"source paper hidden")
	check(panel._quick_bindings[0]==str(find(inv,"bread").instance_id),"quick assignment refers to restored instance")
	check(progress.get_character_data().learning_points==11 and not progress.award_learning_points("process_save_qa",11),"award history survives process kill")
	check(player.global_position.is_equal_approx(Vector3(1,0,6)) and player.facing_direction==Vector3.RIGHT,"position and facing retained")
	check(is_equal_approx(level.get_node("CameraRig")._yaw,0.7),"camera retained")
	check(level.get_node("InventoryMenu").request_open(),"load does not block inventory")
	await create_timer(1.0).timeout
	check(level.get_node("InventoryMenu").get_menu_state()==2,"loaded inventory opens after gesture")
	panel._sections.select_section("quests")
	check(panel._sections.current_section=="quests" and level.get_journal_entry().objective_key=="COURTYARD_OBJECTIVE_FETCH_WOOD","accepted quest viewable")
	panel._sections.select_section("map")
	check(panel._sections.current_section=="map","map viewable")
	if not failed:print("ASHBOUND_COURTYARD_SAVE_PROCESS_OK")
	quit(1 if failed else 0)
