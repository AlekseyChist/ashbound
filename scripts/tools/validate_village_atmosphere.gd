extends "res://scripts/tools/validate_village_settlement.gd"
var validation_version := "0.23.1"
var validation_output := "user://atmosphere-qa"
var atmosphere: Node
var metrics: Dictionary={}
var completed: Array[String]=[]
func shot(name: String) -> void:
	if not capture:return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"capture "+name)

func run_checks() -> void:
	output=validation_output
	var args:=OS.get_cmdline_user_args()
	if args.has("--output"):output=args[args.find("--output")+1]
	DirAccess.make_dir_recursive_absolute(output)
	capture=DisplayServer.get_name()!="headless"
	world=Scene.instantiate();add_child(world)
	atmosphere=world.atmosphere;atmosphere.force_pause=true
	var deadline:=Time.get_ticks_msec()+45000
	while not atmosphere.rain.ready_to_draw and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(atmosphere.rain.ready_to_draw,"rain collision cover ready")
	await settle(.5)
	if not args.has("--look-only"):
		state_checks()
		cover_checks()
		await ui_and_pause_checks()
	if capture:await look_comparison()
	if not args.has("--look-only"):
		atmosphere.force_pause=false
		atmosphere.auto_weather=false
		atmosphere.set_hour(14)
		atmosphere.set_weather(4,true,true)
		for i in range(3):
			atmosphere.set_hour(23 if i==0 else 14)
			await door_route(i)
			var building: Node3D=world.buildings[i]
			await place(building.to_global(building.record.entry+Vector3(0,0,-2)))
			world.camera_rig._yaw=building.rotation.y+PI;world.camera_rig._apply_rotation();world.camera_rig.snap_to_target()
			await settle(.5);await shot(str(building.record.id)+"-rain-from-room")
			completed.append(str(building.record.id))
			print("ATMOSPHERE_ROUTE_COMPLETE ",building.record.id)
		await performance_route(0,"clear")
		await performance_route(4,"storm")
		world.select_building(0);atmosphere.set_hour(15.5);atmosphere.set_weather(0,false,true)
		atmosphere.force_pause=true;atmosphere.apply_look()
	var report: Dictionary={"version":validation_version,"checks":checks,"failures":failures,"completed":completed,"platform":OS.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"metrics":metrics}
	var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("ATMOSPHERE_QA_COMPLETE ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func state_checks() -> void:
	var expected: Array=[
		["clear",0.0,.15,.002,0.0,0.0],["rain",.65,.45,.01,.78,1.0],
		["wind",0.0,.95,.003,.25,0.0],["fog",0.0,.16,.034,.70,.20],["storm",1.0,1.0,.018,1.0,1.0]]
	check(atmosphere.profiles.size()==5,"five weather profiles")
	for i in range(5):
		var profile: Dictionary=atmosphere.profiles[i]
		check(profile.id==expected[i][0] and profile.label=="VILLAGE_WEATHER_"+str(profile.id).to_upper(),"profile identity "+str(i))
		for k in range(5):
			var value: Variant=profile[["rain","wind","fog","cloud","wet"][k]]
			check(value is float and is_equal_approx(value,expected[i][k+1]),"profile field "+str(i)+"/"+str(k))
	var independent: Array[Dictionary]=atmosphere.Profiles.all()
	independent[0].rain=.5
	check(atmosphere.Profiles.all()[0].rain==0.0,"profile calls are independent")
	atmosphere.auto_weather=false
	atmosphere.set_hour(23.5);atmosphere.advance(60)
	check(is_equal_approx(atmosphere.hour,.5),"24-minute day wraps midnight")
	atmosphere.set_hour(48);check(is_zero_approx(atmosphere.hour),"explicit time wraps")
	atmosphere.set_hour(3);atmosphere.advance(-1);atmosphere.advance(NAN);atmosphere.set_hour(INF)
	check(is_equal_approx(atmosphere.hour,3),"invalid times ignored")
	atmosphere.set_weather(0,true,true);atmosphere.set_weather(4)
	check(atmosphere.current.rain==0.0,"weather transition starts without a jump")
	atmosphere.advance(6)
	check(absf(float(atmosphere.current.rain)-.5)<.001,"weather midpoint smooth blend")
	atmosphere.advance(6)
	check(is_equal_approx(atmosphere.current.rain,1.0),"weather transition reaches target")
	check(atmosphere.hour>3 and atmosphere.hour<3.21,"weather does not replace time")
	var index: int=atmosphere.weather_index
	atmosphere.set_weather(-1);atmosphere.set_weather(5)
	check(atmosphere.weather_index==index,"invalid weather ignored")
	atmosphere.advance(35);check(is_equal_approx(atmosphere.wetness,1.0),"ground becomes wet")
	atmosphere.set_weather(0,true,true);atmosphere.auto_weather=true;atmosphere.weather_elapsed=0
	atmosphere.advance(360)
	check(atmosphere.weather_index==2 and is_zero_approx(atmosphere.weather_elapsed),"automatic weather handles multiple intervals")
	check(is_equal_approx(atmosphere.current.rain,.65) and is_equal_approx(atmosphere.wetness,1.0),"large step retains rain at the next transition boundary")
	atmosphere.auto_weather=false
	atmosphere.set_hour(22.5);atmosphere.set_weather(1,true,true);atmosphere.wetness=.6;atmosphere.weather_elapsed=73.0
	var file:=output.path_join("state-test.cfg")
	check(atmosphere.save_state(file)==OK,"save preview settings")
	atmosphere.set_hour(12);atmosphere.set_weather(0,true,true);atmosphere.load_state(file)
	check(is_equal_approx(atmosphere.hour,22.5) and atmosphere.weather_index==1 and not atmosphere.auto_weather and is_equal_approx(atmosphere.wetness,.6),"reload time weather and wetness")
	check(is_equal_approx(atmosphere.weather_elapsed,73.0),"reload automatic weather interval")
	var bad:=ConfigFile.new();bad.set_value("atmosphere","hour","wrong");bad.set_value("atmosphere","weather",-6);bad.set_value("atmosphere","automatic",[]);bad.set_value("atmosphere","wetness",INF);bad.save(file)
	atmosphere.load_state(file)
	check(is_equal_approx(atmosphere.hour,22.5) and atmosphere.weather_index==1 and is_equal_approx(atmosphere.wetness,.6),"invalid saved fields ignored")
	DirAccess.remove_absolute(file)
	atmosphere.set_hour(12);atmosphere.set_weather(0,true,true);atmosphere.apply_look()
	var day_energy: float=world.sun.light_energy
	var day_modulate: Color=world.player.get_node("Visual/Body").modulate
	atmosphere.set_hour(23);atmosphere.apply_look()
	check(world.sun.light_energy<day_energy*.3,"night lighting is darker")
	check(world.player.get_node("Visual/Body").modulate.get_luminance()<day_modulate.get_luminance()*.5,"whole hero responds to night")
	check(world.player.get_node("Visual/Body").sprite_frames==preload("res://assets/characters/world-graybox-v1/traveler_frames.tres"),"accepted animation resource preserved")
	check(atmosphere.foliage_materials.size()>=5,"tree grass fern wind materials")
	for material in atmosphere.foliage_materials:check(material.shader.resource_path.ends_with("village_foliage.gdshader"),"foliage uses wind shader")
	for body: AnimatedSprite3D in world.player.find_children("*","AnimatedSprite3D",true,false):
		check(body.material_override==null or body.material_override.shader.resource_path!="res://assets/shaders/village_foliage.gdshader","hero has no wind deformation")
	print("ATMOSPHERE_STATE_COMPLETE")

func cover_checks() -> void:
	for building in world.buildings:
		for x in [-1.0,0.0,1.0]:
			for z in [-2.0,0.0,2.0]:
				var point: Vector3=building.to_global(Vector3(x,1.5,z))
				check(atmosphere.rain.cover_height(Vector2(point.x,point.z))>point.y+1.0,str(building.name)+" dry roof volume")
	for point in [Vector2(-12,7),Vector2(14,-7),Vector2(-18,27)]:
		check(absf(atmosphere.rain.cover_height(point)-world.terrain.height_at(point.x,point.y))<.16,"rain reaches open ground "+str(point))
	check(atmosphere.rain.cover_height(Vector2(.25,-2))>2.0,"well roof also shelters rain")
	check(atmosphere.rain.drops.multimesh.instance_count==1100 and atmosphere.rain.splashes.multimesh.instance_count==180,"bounded precipitation budget")
	print("ATMOSPHERE_COVER_COMPLETE")

func ui_and_pause_checks() -> void:
	for language in ["ru","en"]:
		Localization.set_language(language);atmosphere.apply_look();await settle(.1)
		for control in [atmosphere.time_button,atmosphere.weather_button,atmosphere.clock_label]:
			check(not "VILLAGE_" in control.text,"localized weather controls "+language)
			check(world.hud.get_node("RootControl").get_global_rect().encloses(control.get_global_rect()),"weather controls inside safe area "+language)
	Localization.set_language("ru")
	world.camera_rig.set_mouse_capture(false)
	atmosphere.set_hour(12);atmosphere.set_weather(0,false,true);atmosphere.auto_weather=true
	await click_control(atmosphere.time_button)
	check(is_equal_approx(atmosphere.hour,18.5),"time button selects next period")
	await click_control(atmosphere.weather_button)
	check(atmosphere.weather_index==1 and not atmosphere.auto_weather,"weather button selects rain")
	for i in range(4):await click_control(atmosphere.weather_button)
	check(atmosphere.weather_index==0 and atmosphere.auto_weather,"weather cycle returns to automatic")
	world.camera_rig.set_mouse_capture(true)
	var before_hour: float=atmosphere.hour
	var before_time: float=atmosphere.effect_time
	atmosphere.force_pause=false
	world._notification(NOTIFICATION_APPLICATION_PAUSED)
	await settle(.4)
	check(is_equal_approx(before_hour,atmosphere.hour) and is_equal_approx(before_time,atmosphere.effect_time),"Android background freezes time and wind")
	world._notification(NOTIFICATION_APPLICATION_RESUMED);await settle(.4)
	check(atmosphere.hour>before_hour and atmosphere.hour<before_hour+.03,"resume has no time catch-up")
	atmosphere.force_pause=true
	print("ATMOSPHERE_INPUT_COMPLETE")

func click_control(control: Control) -> void:
	var event:=InputEventMouseButton.new()
	event.position=control.get_global_rect().get_center();event.global_position=event.position
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	get_viewport().push_input(event,true);await get_tree().process_frame
	event.pressed=false;get_viewport().push_input(event,true);await get_tree().process_frame

func performance_route(index: int,label: String) -> void:
	atmosphere.set_hour(14);atmosphere.set_weather(index,true,true)
	await place(Vector3(-11.75,world.terrain.height_at(-11.75,7.5),7.5))
	world.camera_rig._yaw=0;world.camera_rig._apply_rotation();world.camera_rig.snap_to_target()
	await settle(.5)
	frame_ms.clear()
	for cycle in range(2):
		check(await drive(Vector3(-12.25,0,-12.5),8,true),label+" north route")
		check(await drive(Vector3(-11.75,0,7.5),8,true),label+" south route")
	if not frame_ms.is_empty():
		frame_ms.sort();metrics[label]={"frames":frame_ms.size(),"p50_ms":frame_ms[frame_ms.size()/2],"p95_ms":frame_ms[int(frame_ms.size()*.95)]}
	await shot("route-"+label)
	print("ATMOSPHERE_PERFORMANCE_COMPLETE ",label," ",JSON.stringify(metrics.get(label,{})))

func look_comparison() -> void:
	var camera:=Camera3D.new();world.add_child(camera)
	camera.position=Vector3(-6,4.5,13);camera.look_at(Vector3(-18,1.8,0));camera.make_current()
	world.player.global_position=Vector3(-10,world.terrain.height_at(-10,3)+.1,3)
	world.player.facing_direction=Vector3(-1,0,0)
	world.hud.hide()
	for preset in [["day",12.0,0],["dusk",18.5,0],["night",23.0,0],["rain",7.0,1],["storm",15.0,4],["fog",8.0,3]]:
		atmosphere.set_hour(preset[1]);atmosphere.set_weather(preset[2],true,true);atmosphere.apply_look()
		await settle(.8);await shot(preset[0])
	camera.queue_free();world.hud.show();world.camera_rig.get_camera().make_current()
	world.select_building(0)
	atmosphere.set_hour(15.5);atmosphere.set_weather(0,true,true);atmosphere.apply_look()
	await settle(.5);await shot("game-day")
	atmosphere.set_hour(23);atmosphere.set_weather(4,true,true);atmosphere.apply_look()
	await settle(.5);await shot("game-night-storm")
