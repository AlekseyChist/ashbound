extends SceneTree
## Independent end-to-end native input checks for the mobile inventory.
var failures: Array[String] = []
var groups := 0
var inv: Node
var panel: Control
var loc: Node

func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("TOUCH_INVENTORY_FAIL: " + why)
func settle() -> void:
	await create_timer(0.12).timeout
func send_touch(pos: Vector2, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.index = index
	e.pressed = pressed
	e.canceled = canceled
	root.push_input(e, true)
func send_motion(pos: Vector2, relative: Vector2, index: int = 0) -> void:
	var e := InputEventScreenDrag.new()
	e.position = pos
	e.relative = relative
	e.index = index
	root.push_input(e, true)
func tap(pos: Vector2) -> void:
	send_touch(pos,true)
	send_touch(pos,false)
	await settle()
func carry(from: Vector2, to: Vector2, cancel_release: bool = false) -> void:
	send_touch(from,true)
	await create_timer(0.30).timeout
	send_motion(from+Vector2(10,0),Vector2(10,0))
	await process_frame
	check(panel.get("_ghost").visible and panel.get("_ghost").texture != null,"held item has illustrated drag preview")
	send_motion(to,to-from-Vector2(10,0))
	await process_frame
	send_touch(to,false,0,cancel_release)
	await settle()
func item(id: String) -> Dictionary:
	for d: Dictionary in inv.items:
		if d.id == id: return d
	return {}
func cell_pos(iid: String) -> Vector2:
	for c: Control in panel.get("_cell_nodes"):
		if c.get_meta("item_id","") == iid:
			return c.get_global_rect().get_center()
	check(false,"visible cell for "+iid)
	return Vector2(-500,-500)
func center(name: String) -> Vector2:
	return panel.get_node("%"+name).get_global_rect().get_center()
func tab_pos(id: String) -> Vector2:
	var tabs: Dictionary = panel.get("_tab_buttons")
	if not tabs.has(id):
		check(false,"active tab for "+id)
		return Vector2(-500,-500)
	return tabs[id].get_global_rect().get_center()
func snap() -> String:
	return JSON.stringify(inv.get_save_data())
func layout(language: String) -> void:
	var area: Rect2 = panel.get_global_rect()
	check(root.get_visible_rect().grow(1).encloses(area),language+" panel fits")
	check(area.size.x >= root.get_visible_rect().size.x*0.9,language+" uses phone width")
	for key in ["CloseButton","ArmorSlot","WeaponSlot","BackpackSlot","PouchSlot","LanguageChoice","QuickSlots","ItemDetails"]:
		var c: Control = panel.get_node("%"+key)
		check(area.grow(1).encloses(c.get_global_rect()),language+" inside "+key)
	for c: Control in panel.get("_quick_cells"):
		check(c.size.x >= 100 and c.size.y >= 100,"quick target touch size")
		check(not c.text.is_empty(),"quick key visible")
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.tools/touch-"+name+".png")==OK,"capture")
func run() -> void:
	root.size = Vector2i(1920,1080)
	await process_frame
	inv = root.get_node("Inventory")
	loc = root.get_node("Localization")
	loc.load_preferences("res://.tools/touch-qa-language.cfg","en_US")
	check(inv.configure_storage([{"id":"traveler_clothing_pocket","kind":"pocket","capacity":6}]),"starter pocket")
	panel = load("res://scenes/courtyard/touch_inventory_panel.tscn").instantiate()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left=48
	panel.offset_top=27
	panel.offset_right=-48
	panel.offset_bottom=-27
	check(not panel.visible,"ready does not open")
	panel.open_panel()
	await settle()
	check(panel.get("_tab_buttons").size()==1,"only starter pocket active")
	check(not panel.get_node("%CharacterPreview").get_node("BackpackPreview").visible,"portrait does not invent backpack")
	check(panel.get_node("%StorageTabs").get_child_count()==3,"missing bags still pictured")
	for language in ["en","ru"]:
		loc.load_preferences("res://.tools/touch-qa-language.cfg",language)
		await settle()
		check(panel.get_node("%Title").text==loc.text("INV_TITLE"),"title updates to "+language)
		check(panel.get_node("%LanguageChoice").get_item_text(0)==loc.text("UI_LANGUAGE_AUTO"),"language chooser updates to "+language)
		layout(language)
		await capture("empty-"+language)
	groups+=1
	for id in ["bread","rusty_sword","leather_armor","traveler_backpack","belt_pouch","health_potion"]:
		check(inv.add_item(id),"seed "+id)
	await settle()
	var bread: Dictionary = item("bread").duplicate(true)
	var bag: Dictionary = item("traveler_backpack").duplicate(true)
	var pouch: Dictionary = item("belt_pouch").duplicate(true)
	var sword: Dictionary = item("rusty_sword").duplicate(true)
	var armor: Dictionary = item("leather_armor").duplicate(true)
	await carry(cell_pos(bag.instance_id),center("BackpackSlot"))
	check(inv.get_worn_storage("backpack").get("instance_id","")==bag.instance_id,"touch equip backpack")
	check(panel.get_node("%CharacterPreview").get_node("BackpackPreview").visible,"portrait shows worn backpack straps")
	var bag_id := "worn_storage:"+str(bag.instance_id)
	check(panel.get("_tab_buttons").has(bag_id),"backpack tab becomes active")
	await carry(cell_pos(pouch.instance_id),center("PouchSlot"))
	check(inv.get_worn_storage("pouch").get("instance_id","")==pouch.instance_id,"touch equip pouch")
	groups+=1
	await carry(cell_pos(bread.instance_id),tab_pos(bag_id))
	check(inv.get_item_storage(bread.instance_id)==bag_id,"touch drag onto tab preserves colon ID")
	var before:=snap()
	await carry(center("BackpackSlot"),center("ItemScroll"))
	check(snap()==before,"occupied bag remains equipped")
	groups+=1
	await carry(cell_pos(armor.instance_id),center("ArmorSlot"))
	check(inv.get_equipped("armor").get("instance_id","")==armor.instance_id,"equip complete armor set")
	await carry(cell_pos(sword.instance_id),center("WeaponSlot"))
	check(inv.get_equipped("weapon").get("instance_id","")==sword.instance_id,"equip weapon separately")
	await carry(center("WeaponSlot"),center("ItemScroll"))
	check(inv.get_equipped("weapon").is_empty(),"drag weapon back to storage")
	check(inv.get_item_storage(sword.instance_id)=="traveler_clothing_pocket","unequip destination")
	groups+=1
	await tap(tab_pos(bag_id))
	check(panel.get("_current_container")==bag_id,"tap bag tab full ID")
	var quick: Array = panel.get("_quick_cells")
	await carry(cell_pos(bread.instance_id),quick[2].get_global_rect().get_center())
	check(panel.get("_quick_bindings")[2]==bread.instance_id,"touch quick binding")
	check(inv.get_item_count("bread")==1,"binding does not consume")
	await capture("equipped-ru")
	panel.close_panel()
	panel.open_panel()
	await settle()
	check(panel.get("_quick_bindings")[2]==bread.instance_id,"bindings survive menu reopen")
	groups+=1
	await tap(tab_pos(bag_id))
	before=snap()
	await carry(cell_pos(bread.instance_id),tab_pos("traveler_clothing_pocket"),true)
	check(snap()==before,"canceled touch has no action")
	var start: Vector2 = cell_pos(bread.instance_id)
	send_touch(start,true)
	await create_timer(0.30).timeout
	send_motion(start+Vector2(15,0),Vector2(15,0))
	send_touch(start+Vector2(30,0),true,1)
	send_motion(tab_pos("traveler_clothing_pocket"),Vector2(-200,0))
	send_touch(tab_pos("traveler_clothing_pocket"),false)
	send_touch(tab_pos("traveler_clothing_pocket"),false,1)
	await settle()
	check(snap()==before,"second finger cancels drag")
	check(not panel.get("_ghost").visible,"cancel hides ghost")
	groups+=1
	start=cell_pos(bread.instance_id)
	send_touch(start,true)
	await create_timer(0.30).timeout
	send_motion(start+Vector2(15,0),Vector2(15,0))
	check(inv.move_item_to_storage({"instance_id":bread.instance_id},"traveler_clothing_pocket"),"external transfer")
	before=snap()
	send_touch(tab_pos(bag_id),false)
	await settle()
	check(snap()==before,"source relocation cancels stale drag")
	groups+=1
	# Real mouse uses a distinct device id; an emulated duplicate must be ignored.
	await tap(tab_pos("traveler_clothing_pocket"))
	var from: Vector2 = cell_pos(bread.instance_id)
	var to: Vector2 = tab_pos(bag_id)
	var mb:=InputEventMouseButton.new()
	mb.device=InputEvent.DEVICE_ID_MOUSE
	mb.button_index=MOUSE_BUTTON_LEFT
	mb.pressed=true
	mb.position=from
	root.push_input(mb,true)
	var mm:=InputEventMouseMotion.new()
	mm.device=InputEvent.DEVICE_ID_MOUSE
	mm.position=to
	mm.relative=to-from
	root.push_input(mm,true)
	mb=mb.duplicate()
	mb.pressed=false
	mb.position=to
	root.push_input(mb,true)
	await settle()
	check(inv.get_item_storage(bread.instance_id)==bag_id,"real mouse drag")
	before=snap()
	mb.device=InputEvent.DEVICE_ID_EMULATION
	mb.pressed=true
	root.push_input(mb,true)
	mb=mb.duplicate()
	mb.pressed=false
	root.push_input(mb,true)
	check(snap()==before,"emulated duplicate has no mutation")
	groups+=1
	var close_count := [0]
	panel.close_requested.connect(func(): close_count[0]+=1)
	await tap(center("CloseButton"))
	check(close_count[0]==1,"touch close emits exactly once")
	panel.close_panel()
	before=snap()
	await tap(center("BackpackSlot"))
	check(snap()==before,"hidden panel ignores input")
	groups+=1
	print("ASHBOUND_TOUCH_INVENTORY_GROUPS=",groups)
	panel.queue_free()
	await process_frame
	if failures.is_empty() and groups==9:
		print("ASHBOUND_TOUCH_INVENTORY_OK")
		quit(0)
	else: quit(1)
