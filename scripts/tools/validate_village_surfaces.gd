extends "res://scripts/tools/validate_village_atmosphere.gd"
const Catalog=preload("res://scripts/world/village_surface_catalog.gd")
func _ready() -> void:
	validation_version="0.23.2"
	validation_output="user://surface-qa"
	super._ready()

func state_checks() -> void:
	super.state_checks()
	Catalog.apply_to(null)
	var mat: ShaderMaterial=world.terrain.material
	for key in ["grass_albedo","grass_normal","grass_roughness","path_albedo","path_normal","path_roughness"]:
		var tex: Texture2D=mat.get_shader_parameter(key)
		check(tex!=null and tex.get_width()==1024 and tex.get_height()==1024,"exported 1K map "+key)
		check(tex!=null and tex.get_image().has_mipmaps(),"mipmapped "+key)
	check(is_equal_approx(float(mat.get_shader_parameter("grass_meters")),1.4),"grass physical scale")
	check(is_equal_approx(float(mat.get_shader_parameter("path_meters")),3.2),"soil physical scale")
	check(world.terrain.color_at(-11.75,7.5).a>.99,"street material at known route centre")
	check(world.terrain.color_at(.25,-2).a>.99,"well apron soil material")
	check(world.terrain.color_at(-75,15).a<.01,"forest floor away from roads")
	var min_alpha:=1.0;var max_alpha:=0.0;var blended:=0
	var mesh: ArrayMesh=world.terrain.ground.mesh
	var arrays:=mesh.surface_get_arrays(0)
	for c in arrays[Mesh.ARRAY_COLOR]:
		min_alpha=minf(min_alpha,c.a);max_alpha=maxf(max_alpha,c.a)
		if c.a>.05 and c.a<.95:blended+=1
	check(min_alpha>=0.0 and max_alpha<=1.0 and min_alpha<.01 and max_alpha>.99,"bounded material weights on actual terrain")
	check(blended>100,"soft transitions between road and grass on mesh")
	check(arrays[Mesh.ARRAY_VERTEX].size()==114*89,"terrain vertex budget unchanged")
	print("VILLAGE_SURFACES_CONTRACT_COMPLETE")

func look_comparison() -> void:
	await super.look_comparison()
	var camera:=Camera3D.new();world.add_child(camera)
	camera.position=Vector3(-6,4.5,13);camera.look_at(Vector3(-18,1.8,0));camera.make_current()
	world.player.global_position=Vector3(-10,world.terrain.height_at(-10,3)+.1,3)
	world.player.facing_direction=Vector3(-1,0,0);world.hud.hide()
	for weather in [["day",12.0,0],["wet",15.0,4]]:
		atmosphere.set_hour(weather[1]);atmosphere.set_weather(weather[2],true,true);atmosphere.apply_look()
		for enabled in [false,true]:
			world.terrain.material.set_shader_parameter("detail_enabled",enabled)
			await settle(.6);await shot(str(weather[0])+"-"+("after" if enabled else "before"))
	world.terrain.material.set_shader_parameter("detail_enabled",true)
	camera.queue_free();world.hud.show();world.camera_rig.get_camera().make_current()
