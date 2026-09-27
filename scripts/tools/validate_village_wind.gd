extends "res://scripts/tools/validate_village_surfaces.gd"

func run_checks() -> void:
	validation_version="0.23.4"
	validation_output="user://wind-qa"
	await super.run_checks()

func state_checks() -> void:
	super.state_checks()
	for batch in world.dressing.foliage_batches:
		var tree: bool="pine" in batch.name or "spruce" in batch.name
		check(batch.extra_cull_margin >= (2.0 if tree else .6),"wind bounds "+batch.name)
	check(world.dressing.household!=null,"household dressing retained")

func probe_mesh(anchored: bool) -> ArrayMesh:
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	var colors:=PackedColorArray();var indices:=PackedInt32Array()
	for row in range(5):
		for x in [-.14,.14]:
			vertices.append(Vector3(x,row*.5,0));normals.append(Vector3(0,0,1))
			colors.append(Color(1,1,1,0 if anchored else row*.25))
	for row in range(4):
		var i:=row*2
		indices.append_array(PackedInt32Array([i,i+1,i+2,i+1,i+3,i+2]))
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func probe_image(view: SubViewport, material: ShaderMaterial, strength: float, time: float) -> Image:
	material.set_shader_parameter("wind_strength",strength)
	material.set_shader_parameter("effect_time",time)
	await get_tree().process_frame;await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func tip_center(picture: Image) -> float:
	var total:=0.0;var mass:=0.0
	for y in range(85,100):
		for x in range(picture.get_width()):
			var light:=picture.get_pixel(x,y).get_luminance()
			if light>.1:total+=x*light;mass+=light
	check(mass>1.0,"rendered probe tip visible")
	return total/maxf(mass,.001)

func shader_render_checks() -> void:
	var view:=SubViewport.new();view.size=Vector2i(256,256);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=1.0
	view.add_child(env)
	var camera:=Camera3D.new();view.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6.0
	camera.position=Vector3(0,1,7);camera.look_at(Vector3(0,1,0));camera.make_current()
	var mesh:=MeshInstance3D.new();mesh.mesh=probe_mesh(false);mesh.extra_cull_margin=2.0
	var material:=ShaderMaterial.new();material.shader=preload("res://assets/shaders/village_foliage.gdshader")
	material.set_shader_parameter("wind_direction",Vector2(1,0));material.set_shader_parameter("amplitude",.55)
	mesh.material_override=material;view.add_child(mesh);await settle(.2)
	var zero_a: Image=await probe_image(view,material,0,0)
	var zero_b: Image=await probe_image(view,material,0,6)
	check(zero_a.get_data()==zero_b.get_data(),"zero wind renders static")
	mesh.mesh=probe_mesh(true)
	var root_a: Image=await probe_image(view,material,1,0)
	var root_b: Image=await probe_image(view,material,1,6)
	check(root_a.get_data()==root_b.get_data(),"zero painted weights remain anchored")
	mesh.mesh=probe_mesh(false)
	for tree in [true,false]:
		material.set_shader_parameter("painted_weight",tree)
		material.set_shader_parameter("amplitude",.55 if tree else .16)
		var ranges:=[]
		for strength in [.15,.95]:
			var positions:=PackedFloat32Array()
			for i in range(12):
				var picture: Image=await probe_image(view,material,strength,i*.7)
				positions.append(tip_center(picture))
			positions.sort();ranges.append(positions[-1]-positions[0])
		check(ranges[1]>ranges[0]*3.0 and ranges[1]>3.0,"strong wind visibly exceeds clear "+str(tree))
		metrics["wind_tree" if tree else "wind_understory"]={"clear_tip_range_px":ranges[0],"strong_tip_range_px":ranges[1]}
	var repeat_a: Image=await probe_image(view,material,.95,2.1)
	await probe_image(view,material,.95,8.4)
	var repeat_b: Image=await probe_image(view,material,.95,2.1)
	check(repeat_a.get_data()==repeat_b.get_data(),"same effect time reproduces rendered phase")
	view.queue_free();await get_tree().process_frame
	print("VILLAGE_WIND_RENDER_COMPLETE ",JSON.stringify(metrics))

func look_comparison() -> void:
	await shader_render_checks()
	var camera:=Camera3D.new();world.add_child(camera)
	camera.position=Vector3(-6,4.5,13);camera.look_at(Vector3(-18,3,0));camera.make_current()
	world.hud.hide();atmosphere.force_pause=true
	for preset in [["clear",0],["wind",2]]:
		atmosphere.set_hour(14);atmosphere.set_weather(preset[1],true,true)
		for phase in range(8):
			atmosphere.effect_time=phase*.7;atmosphere.apply_look()
			await settle(.08);await shot(preset[0]+"-"+str(phase))
	camera.queue_free();world.hud.show();world.camera_rig.get_camera().make_current()
	world.select_building(0);atmosphere.set_hour(14);atmosphere.set_weather(2,true,true)
	atmosphere.apply_look();await settle(.3);await shot("game-wind")
