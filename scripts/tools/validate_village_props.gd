extends "res://scripts/tools/validate_village_surfaces.gd"
const PropsCatalog = preload("res://scripts/world/village_props_catalog.gd")

func run_checks() -> void:
	validation_version = "0.23.3"
	validation_output = "user://props-qa"
	await super.run_checks()

func state_checks() -> void:
	super.state_checks()
	var props: Node3D = world.dressing.household
	check(props.items.size() == 14, "fourteen household props in existing yards")
	var independent := PropsCatalog.all()
	independent[0].at = Vector3(999,999,999)
	check(PropsCatalog.all()[0].at == Vector3(1.2,0,4.65), "catalog callers cannot mutate later builds")
	var solids := 0
	var triangles := 0
	for record in props.records:
		var item: Node3D = props.items[record.id]
		var box: AABB = props.bounds[record.id]
		check(box.size.x > .05 and box.size.y > .05 and box.size.z > .05, "nonempty visible model " + record.id)
		check(item.has_node("Solid") == record.solid, "only substantial props obstruct feet " + record.id)
		if record.solid: solids += 1
		if record.support.is_empty():
			check(absf(item.global_position.y-world.terrain.height_at(item.global_position.x,item.global_position.z))<.01, "grounded " + record.id)
		else:
			var support: Node3D = props.items[record.support]
			check(absf(item.global_position.y-support.global_position.y-props.bounds[record.support].size.y-.01)<.001, "rests on support " + record.id)
		for mesh: MeshInstance3D in item.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				triangles += mesh.mesh.surface_get_array_index_len(surface)/3
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				check(material != null and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "prop responds to accepted lighting " + record.id)
				if material != null:
					for slot in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_NORMAL,BaseMaterial3D.TEXTURE_ORM]:
						var tex: Texture2D = material.get_texture(slot)
						if tex != null: check(tex.get_width()<=1024 and tex.get_height()<=1024 and tex.get_image().has_mipmaps(),"bounded mipmapped prop texture " + record.id)
	check(solids==6,"six coarse solid obstacles, no small-item ankle collisions")
	check(triangles<30000,"total household triangle budget below 30K")
	check(absf(props.bounds.home_bench.size.x-2.166)<.02,"human-scale 2.17m bench")
	check(absf(props.bounds.work_table.size.y-.895)<.02,"work surface at waist height")
	check(absf(props.bounds.barn_cart.size.y-2.63)<.02,"cart canopy height 2.63m")
	for building in world.buildings:
		var entry: Vector3 = building.record.entry
		for step in range(1,8):
			var point: Vector3 = building.to_global(entry+Vector3(0,.6,step*.5))
			for record in props.records:
				if record.building != building.record.id or not record.solid: continue
				var item: Node3D=props.items[record.id]
				check(not props.bounds[record.id].grow(.4).has_point(item.to_local(point)),"clear entrance " + building.record.id+" / "+str(step)+" / "+record.id)
	print("VILLAGE_PROPS_CONTRACT_COMPLETE triangles=",triangles)

func look_comparison() -> void:
	# Regression route and weather remain inherited; these views inspect the new yard groups.
	var props: Node3D = world.dressing.household
	if not OS.get_cmdline_user_args().has("--look-only"):
		for id in ["home_bench","work_table","barn_cart"]:
			var item: Node3D=props.items[id]
			var box: AABB=props.bounds[id]
			var start: Vector3=item.to_global(Vector3(box.end.x+1.1,0,box.get_center().z))
			start.y=world.terrain.height_at(start.x,start.z)
			await place(start)
			var goal: Vector3=item.to_global(Vector3(box.get_center().x,0,box.get_center().z))
			check(not await drive(goal,1.8,true),"running cannot pass through " + id)
			check(item.to_local(world.player.global_position).x>box.end.x+.1,"capsule stops outside " + id)
	var camera:=Camera3D.new();world.add_child(camera);camera.make_current()
	world.hud.hide()
	for index in range(3):
		var building: Node3D=world.buildings[index]
		camera.global_position=building.to_global(Vector3(9,4.8,10) if index==1 else Vector3(-10,5.5,12))
		camera.look_at(building.to_global(Vector3(0,1.1,1)))
		await place(building.to_global(building.record.entry+Vector3(0,0,2.5)))
		world.player.facing_direction=-building.global_basis.z
		for preset in [["day",12.0,0],["night",23.0,0],["rain",15.0,4]]:
			atmosphere.set_hour(preset[1]);atmosphere.set_weather(preset[2],true,true);atmosphere.apply_look()
			await settle(.6);await shot(str(building.record.id)+"-props-"+str(preset[0]))
	camera.queue_free();world.hud.show();world.camera_rig.get_camera().make_current()
	world.select_building(0)
	atmosphere.set_hour(12);atmosphere.set_weather(0,true,true);atmosphere.apply_look()
	await settle(.5);await shot("game-day")
