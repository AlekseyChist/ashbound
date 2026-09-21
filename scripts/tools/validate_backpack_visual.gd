extends SceneTree
## Whole painted frames: actual ownership transitions and phase/pose regression.
const BARE = preload("res://assets/characters/courtyard/traveler_frames.tres")
const PACKED = preload("res://assets/characters/courtyard/traveler_backpack_frames.tres")
const BARE_POCKET = preload("res://assets/characters/courtyard/traveler_pocket_frames.tres")
const PACKED_POCKET = preload("res://assets/characters/courtyard/traveler_backpack_pocket_frames.tres")
var failures: Array[String] = []
var visuals: Array[Node] = []
var inv: Node
var transitions := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("BACKPACK_VISUAL_FAIL: "+why)
func state(sprite: AnimatedSprite3D) -> Array:
	return [sprite.animation,sprite.frame,sprite.frame_progress,sprite.is_playing(),sprite.speed_scale,sprite.flip_h,sprite.visible,sprite.position,sprite.pixel_size,sprite.autoplay]
func refresh_all() -> void:
	for visual in visuals: visual.get_node("BackpackLayer").refresh_visual()
func capture(sheet: SubViewport, name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	check(sheet.get_texture().get_image().save_png("res://.tools/backpack-"+name+".png")==OK,"render "+name)
func run() -> void:
	root.size=Vector2i(1280,1750)
	await process_frame
	inv=root.get_node("Inventory")
	var sheet:=SubViewport.new()
	sheet.size=Vector2i(1280,1750)
	sheet.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var grid:=GridContainer.new()
	grid.columns=4
	grid.add_theme_constant_override("h_separation",0)
	grid.add_theme_constant_override("v_separation",0)
	sheet.add_child(grid)
	for action in ["idle","walk","run","attack","pocket"]:
		for view in ["back","front","right","left"]:
			var column:=VBoxContainer.new()
			column.custom_minimum_size=Vector2(320,350)
			grid.add_child(column)
			var label:=Label.new()
			label.text=action+" / "+view
			label.add_theme_font_size_override("font_size",20)
			column.add_child(label)
			var container:=SubViewportContainer.new()
			container.custom_minimum_size=Vector2(320,320)
			column.add_child(container)
			var viewport:=SubViewport.new()
			viewport.size=Vector2i(320,320)
			viewport.own_world_3d=true
			viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			container.add_child(viewport)
			var env:=WorldEnvironment.new()
			env.environment=Environment.new()
			env.environment.background_mode=Environment.BG_COLOR
			env.environment.background_color=Color(0.11,0.12,0.14)
			viewport.add_child(env)
			var camera:=Camera3D.new()
			camera.projection=Camera3D.PROJECTION_ORTHOGONAL
			camera.size=2.1
			viewport.add_child(camera)
			camera.position=Vector3(0,0.92,4)
			camera.look_at(Vector3(0,0.92,0))
			var actor:Node=load("res://scenes/courtyard/courtyard_player.tscn").instantiate()
			viewport.add_child(actor)
			actor.set_physics_process(false)
			actor.set_process(false)
			var visual:Node=actor.get_node("Visual")
			visual.set("_current_view",StringName(view))
			visual.set("_current_action",StringName("idle" if action=="pocket" else action))
			var body:AnimatedSprite3D=visual.get_node("Body")
			var pocket:AnimatedSprite3D=visual.get_node("PocketPose")
			if action=="pocket":
				body.animation=StringName("idle_"+(view if view in ["front","back"] else "side"))
				body.pause()
				visual.call("_apply_sprite_scale",body)
			var source:AnimatedSprite3D=pocket if action=="pocket" else body
			body.visible=action!="pocket"
			pocket.visible=action=="pocket"
			var suffix:String=view if view in ["front","back"] else "side"
			source.animation=StringName(action+"_"+suffix)
			source.pause()
			source.frame=mini(1,source.sprite_frames.get_frame_count(source.animation)-1)
			source.flip_h=view=="left"
			if action=="pocket": visual.call("_apply_pocket_scale",source,StringName(view))
			else: visual.call("_apply_sprite_scale",source)
			var layer:Node=visual.get_node_or_null("BackpackLayer")
			check(layer!=null,"player includes backpack component")
			if layer==null: continue
			layer.set_process(false)
			layer.call("refresh_visual")
			check(layer.get_child_count()==0,"no accessory overlay nodes")
			check(body.sprite_frames==BARE and pocket.sprite_frames==BARE_POCKET,"no free visible backpack")
			visuals.append(visual)
	await capture(sheet,"bare-review")
	check(inv.add_item("traveler_backpack"),"obtain bag fixture")
	var bag:Dictionary=inv.items[0].duplicate(true)
	refresh_all()
	for visual in visuals: check(visual.get_node("Body").sprite_frames==BARE,"carried bag is not worn")
	for visual in visuals:
		var source:AnimatedSprite3D=visual.get_node("Body")
		if not source.visible: source=visual.get_node("PocketPose")
		var layer:Node=visual.get_node("BackpackLayer")
		var view:String=str(visual.get_visual_direction())
		for frame in source.sprite_frames.get_frame_count(source.animation):
			for playing in [false,true]:
				source.speed_scale=1.25
				if playing: source.play()
				else: source.pause()
				source.set_frame_and_progress(frame,0.37)
				var before := state(source)
				check(inv.equip_storage_item({"instance_id":bag.instance_id}),"wear bag")
				layer.refresh_visual()
				check(visual.get_node("Body").sprite_frames==PACKED and visual.get_node("PocketPose").sprite_frames==PACKED_POCKET,"both painted resources active")
				check(state(source)==before,"equip preserves pose/phase: "+str(source.animation)+" "+str(frame)+" "+str(playing))
				var game_snapshot: String=JSON.stringify(inv.get_save_data())
				layer.refresh_visual()
				check(state(source)==before and JSON.stringify(inv.get_save_data())==game_snapshot,"refresh idempotent, inventory unchanged")
				check(inv.unequip_storage_item("backpack","traveler_clothing_pocket"),"remove empty bag")
				layer.refresh_visual()
				check(visual.get_node("Body").sprite_frames==BARE and visual.get_node("PocketPose").sprite_frames==BARE_POCKET,"restore exact original resources")
				check(state(source)==before,"remove preserves pose/phase: "+str(source.animation))
				transitions += 2
			source.pause()
		source.frame=mini(1,source.sprite_frames.get_frame_count(source.animation)-1)
	check(inv.equip_storage_item({"instance_id":bag.instance_id}),"wear for render")
	refresh_all()
	await capture(sheet,"painted-review")
	var worn_save: Dictionary=inv.get_save_data()
	check(inv.unequip_storage_item("backpack","traveler_clothing_pocket"),"remove empty bag")
	refresh_all()
	check(inv.load_save_data(worn_save),"restore snapshot with backpack")
	refresh_all()
	for visual in visuals: check(visual.get_node("Body").sprite_frames==PACKED,"restored inventory restores appearance")
	# A newly instantiated player must also immediately restore the worn mode.
	var restored: Node=load("res://scenes/courtyard/courtyard_player.tscn").instantiate()
	sheet.add_child(restored)
	restored.set_physics_process(false)
	check(restored.get_node("Visual/Body").sprite_frames==PACKED,"initial worn snapshot applied")
	restored.queue_free()
	check(inv.unequip_storage_item("backpack","traveler_clothing_pocket"),"remove restored bag")
	check(inv.add_item("belt_pouch"),"obtain pouch")
	for entry:Dictionary in inv.items:
		if entry.id=="belt_pouch": check(inv.equip_storage_item({"instance_id":entry.instance_id}),"wear pouch")
	for visual in visuals:
		visual.get_node("BackpackLayer").call("refresh_visual")
		check(visual.get_node("Body").sprite_frames==BARE,"pouch alone has no backpack graphic")
	print("ASHBOUND_BACKPACK_VISUAL_CASES=",visuals.size())
	print("ASHBOUND_BACKPACK_TRANSITIONS=",transitions)
	sheet.queue_free()
	await process_frame
	if failures.is_empty() and visuals.size()==20 and transitions==448:
		print("ASHBOUND_BACKPACK_VISUAL_OK")
		quit(0)
	else: quit(1)
