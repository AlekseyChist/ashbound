extends "res://scripts/tools/validate_village_surfaces.gd"
const HouseCatalog=preload("res://scripts/world/village_house_material_catalog.gd")

func run_checks() -> void:
	if get_script().resource_path.ends_with("validate_village_materials.gd"):
		validation_version="0.23.5"
		validation_output="user://material-qa"
	await super.run_checks()

func state_checks() -> void:
	super.state_checks()
	grain_checks()
	check(HouseCatalog.create("invalid")==null,"unknown house finish does not create a material")
	for kind in ["plaster","oak","stone"]:
		var a: StandardMaterial3D=HouseCatalog.create(kind)
		var b: StandardMaterial3D=HouseCatalog.create(kind)
		check(a!=b,"independent house material "+kind)
		check(a.albedo_texture==b.albedo_texture,"shared immutable map "+kind)
		for tex in [a.albedo_texture,a.normal_texture,a.roughness_texture]:
			check(tex!=null and tex.get_width()==1024 and tex.get_height()==1024,"exported house 1K "+kind)
			check(tex!=null and tex.get_image().has_mipmaps(),"house mipmaps "+kind)
		check(a.normal_enabled and a.normal_scale>0 and a.normal_texture.resource_path.contains("nor_gl"),"OpenGL relief "+kind)
		check(a.roughness_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_RED,"house roughness red channel "+kind)
		check(a.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"opaque house "+kind)
	var roof: ShaderMaterial=HouseCatalog.create("roof")
	check(roof.shader.resource_path.ends_with("village_house_roof.gdshader"),"existing shingle rows have continuous surface pattern")
	for key in ["albedo_map","normal_map","roughness_map"]:
		var map: Texture2D=roof.get_shader_parameter(key)
		check(map!=null and map.get_width()==1024 and map.get_image().has_mipmaps(),"exported roof map "+key)
	var finish: RefCounted=world.buildings[0].house_materials
	check(finish.originals.size()==33,"33 H01 architectural meshes finished")
	var materials: Dictionary={}
	for record in finish.originals:
		var original: Mesh=record.mesh
		var detail: Mesh=record.detailed
		check(original.get_surface_count()==detail.get_surface_count(),"same material surfaces "+record.node.name)
		var faces_a:=original.get_faces();var faces_b:=detail.get_faces()
		var same:=faces_a.size()==faces_b.size()
		if same:
			for i in range(faces_a.size()):
				if not faces_a[i].is_equal_approx(faces_b[i]):same=false;break
		check(same,"same triangles/collision outline "+record.node.name)
		for surface in range(detail.get_surface_count()):
			var arrays:=detail.surface_get_arrays(surface)
			var valid:=true
			for uv in arrays[Mesh.ARRAY_TEX_UV]:
				if not uv.is_finite():valid=false
			for t in arrays[Mesh.ARRAY_TANGENT]:
				if not is_finite(t):valid=false
			check(valid and arrays[Mesh.ARRAY_TANGENT].size()>0,"finite UV/tangent basis "+record.node.name)
			var material:=detail.surface_get_material(surface)
			materials[material.resource_name]=true
	check(materials.size()==4,"four shared finish materials")
	finish.set_enabled(false)
	check(finish.originals.all(func(r):return r.node.mesh==r.mesh),"original comparison uses original meshes")
	finish.set_enabled(true)
	check(finish.originals.all(func(r):return r.node.mesh==r.detailed),"comparison restores detailed house")
	var count: int=finish.originals.size();finish.apply(world.buildings[0].model,"H01")
	check(finish.originals.size()==count,"material application is idempotent")
	for building in world.buildings:
		if building.record.id!="H01":check(building.house_materials.originals.is_empty(),"unchanged finish "+building.record.id)
		for instance in building.model.find_children("*","MeshInstance3D",true,false):
			var extras: Dictionary=instance.get_meta("extras",{})
			if extras.get("part_role","")=="furniture":
				for surface in range(instance.mesh.get_surface_count()):
					check(not instance.mesh.surface_get_material(surface).resource_name.begins_with("H01_A"),"furniture finish retained "+building.record.id+"/"+instance.name)
	print("VILLAGE_MATERIALS_CONTRACT_COMPLETE")

func grain_checks() -> void:
	var mapper=preload("res://scripts/world/village_house_materials.gd").new()
	var beam:=BoxMesh.new();beam.size=Vector3(.2,2,.2)
	for angle in [0.0,PI/2,PI/4]:
		var arrays:=beam.surface_get_arrays(0)
		mapper.map_uv(arrays,Transform3D(Basis(Vector3.FORWARD,angle),Vector3.ZERO),"oak")
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		var aligned:=false
		for a in range(points.size()):
			for b in range(a+1,points.size()):
				if normals[a].z>.9 and normals[b].z>.9 and absf(points[a].y-points[b].y)>1.9 and is_equal_approx(points[a].x,points[b].x):
					aligned=absf(uv[a].y-uv[b].y)>3.2 and absf(uv[a].x-uv[b].x)<.05
		check(aligned,"grain follows vertical horizontal diagonal beam "+str(angle))

func look_comparison() -> void:
	var house: Node3D=world.buildings[0]
	var camera:=Camera3D.new();camera.fov=50;world.add_child(camera);camera.make_current()
	world.hud.hide();world.player.hide()
	for view in ["exterior","interior","roof"]:
		if view=="exterior":
			camera.global_position=house.to_global(Vector3(-9,5,12));camera.look_at(house.to_global(Vector3(0,2.7,0)))
		elif view=="interior":
			camera.global_position=house.to_global(Vector3(1.7,1.8,2.5));camera.look_at(house.to_global(Vector3(-1,1.4,-2)))
		else:
			camera.global_position=house.to_global(Vector3(-5.5,6.5,5));camera.look_at(house.to_global(Vector3(-1.7,4.9,0)))
		for preset in [["day",12.0,0],["night",23.0,0],["rain",15.0,4]]:
			if view=="roof" and preset[0]!="day":continue
			atmosphere.set_hour(preset[1]);atmosphere.set_weather(preset[2],true,true);atmosphere.apply_look()
			for enabled in [false,true]:
				house.house_materials.set_enabled(enabled)
				await settle(.35);await shot(view+"-"+str(preset[0])+"-"+("after" if enabled else "before"))
	house.house_materials.set_enabled(true)
	# Read the material while the viewpoint changes, not only in a still shot.
	atmosphere.set_hour(14);atmosphere.set_weather(0,true,true);atmosphere.apply_look()
	for i in range(8):
		var angle:=lerpf(-.85,.85,float(i)/7.0)
		camera.global_position=house.to_global(Vector3(sin(angle)*13,4,cos(angle)*13))
		camera.look_at(house.to_global(Vector3(0,2.8,0)))
		await settle(.15);await shot("orbit-"+str(i))
	camera.queue_free();world.player.show();world.hud.show();world.camera_rig.get_camera().make_current()
	world.select_building(0);atmosphere.set_hour(14);atmosphere.set_weather(0,true,true);atmosphere.apply_look()
	await settle(.5);await shot("game-house")
