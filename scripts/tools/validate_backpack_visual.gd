extends SceneTree
## Actual Godot compositing review, with independent ownership/frame checks.
var failures: Array[String] = []
var visuals: Array[Node] = []
var inv: Node
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("BACKPACK_VISUAL_FAIL: "+why)
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
			visual.set("_current_action",StringName(action))
			var body:AnimatedSprite3D=visual.get_node("Body")
			var pocket:AnimatedSprite3D=visual.get_node("PocketPose")
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
			layer.call("refresh_visual")
			check(not layer.get_node("Pack").visible,"no free visible backpack")
			visuals.append(visual)
	check(inv.add_item("traveler_backpack"),"obtain bag fixture")
	var bag:Dictionary=inv.items[0].duplicate(true)
	check(inv.equip_storage_item({"instance_id":bag.instance_id}),"wear fixture bag")
	for visual in visuals:
		var source:AnimatedSprite3D=visual.get_node("Body")
		if not source.visible: source=visual.get_node("PocketPose")
		var layer:Node=visual.get_node("BackpackLayer")
		var pack:Sprite3D=layer.get_node("Pack")
		var view:String=str(visual.get_visual_direction())
		for frame in source.sprite_frames.get_frame_count(source.animation):
			source.frame=frame
			var original_size:float=source.pixel_size
			layer.call("refresh_visual")
			check(pack.visible,"worn visible "+str(source.animation))
			check(pack.texture is AtlasTexture,"accessory atlas")
			check(pack.flip_h==(view=="left"),"accessory left mirror")
			check(pack.billboard==BaseMaterial3D.BILLBOARD_FIXED_Y and not pack.no_depth_test,"billboard and world occlusion")
			check(source.frame==frame and source.pixel_size==original_size,"does not change actor frame or size")
			var cell:int=0 if view=="front" else (1 if view=="back" else 2)
			check(is_equal_approx(pack.texture.region.position.x,float(cell*724)),"correct art view")
			source.frame=mini(1,source.sprite_frames.get_frame_count(source.animation)-1)
		layer.call("refresh_visual")
	await create_timer(0.2).timeout
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		check(sheet.get_texture().get_image().save_png("res://.tools/backpack-visual-review.png")==OK,"render contact sheet")
	check(inv.unequip_storage_item("backpack","traveler_clothing_pocket"),"remove empty bag")
	check(inv.add_item("belt_pouch"),"obtain pouch")
	for entry:Dictionary in inv.items:
		if entry.id=="belt_pouch": check(inv.equip_storage_item({"instance_id":entry.instance_id}),"wear pouch")
	for visual in visuals:
		visual.get_node("BackpackLayer").call("refresh_visual")
		check(not visual.get_node("BackpackLayer/Pack").visible,"pouch alone has no backpack graphic")
	print("ASHBOUND_BACKPACK_VISUAL_CASES=",visuals.size())
	sheet.queue_free()
	await process_frame
	if failures.is_empty() and visuals.size()==20:
		print("ASHBOUND_BACKPACK_VISUAL_OK")
		quit(0)
	else: quit(1)
