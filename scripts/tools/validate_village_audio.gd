extends "res://scripts/tools/validate_village_materials.gd"
const Preferences=preload("res://scripts/world/village_settings.gd")
var recorded: Dictionary={}

func run_checks() -> void:
	validation_version="0.23.6"
	validation_output="user://audio-qa"
	await super.run_checks()

func state_checks() -> void:
	super.state_checks()
	var prefs:=Preferences.new()
	var file: String=output.path_join("preference-test.cfg")
	prefs.load_settings(file)
	check(prefs.music_percent==45 and prefs.draw_distance==220,"new settings defaults")
	prefs.music_percent=0;prefs.sound_percent=50;prefs.draw_distance=80
	check(prefs.save_settings()==OK,"settings save")
	var loaded:=Preferences.new();loaded.load_settings(file)
	check(loaded.music_percent==0 and loaded.sound_percent==50 and loaded.draw_distance==80,"settings round trip")
	var config:=ConfigFile.new();config.load(file);config.set_value("unrelated","keep",72)
	config.set_value("audio","music","bad");config.set_value("audio","sound",INF);config.set_value("graphics","distance",9999);config.save(file)
	loaded.load_settings(file)
	check(loaded.music_percent==0 and loaded.sound_percent==50 and loaded.draw_distance==300,"invalid fields retained and range clamped")
	loaded.save_settings();config.load(file)
	check(config.get_value("unrelated","keep")==72,"other config section preserved")
	DirAccess.remove_absolute(file)
	for region in ["forest","desert","mountains","lowlands","main"]:
		var path: String=world.audio.Catalog.music(region)
		check(ResourceLoader.exists(path) and (load(path) as AudioStream).get_length()>180,"exported music "+region)
	check(world.audio.Catalog.music("invalid")=="" and world.audio.Catalog.footsteps("invalid").is_empty(),"catalog unknown keys safe")
	for surface in ["grass","dirt","stone","wood","snow"]:
		var streams: Array=world.audio.samples[surface]
		check(streams.size()==4,"four step variations "+surface)
		for sample: AudioStream in streams:check(sample.get_length()>.01 and sample.get_length()<3,"decoded footstep "+surface)
	check(world.audio.music.stream.resource_path=="" or world.audio.music.stream.loop,"music instance is looped")
	check(world.audio.fire.max_distance==14,"hearth is spatial and bounded")
	var collider_count:=world.find_children("*","CollisionShape3D",true,false).size()
	for distance in [80.0,300.0,220.0,80.0,300.0,220.0]:
		world.settings.draw_distance=distance;world.settings.apply_distance(world)
		check(is_equal_approx(world.camera_rig.get_camera().far,distance),"camera far "+str(distance))
		var batch: MultiMeshInstance3D=world.dressing.foliage_batches[0]
		check(is_equal_approx(batch.visibility_range_end,float(batch.get_meta("base_visibility_end"))*distance/220),"foliage distance no compound scale "+str(distance))
	check(world.find_children("*","CollisionShape3D",true,false).size()==collider_count,"draw setting retains collisions")
	print("AUDIO_STATE_COMPLETE")

func ui_and_pause_checks() -> void:
	await super.ui_and_pause_checks()
	var audio: Node=world.audio
	var menu: Control=world.settings_menu
	world.camera_rig.set_mouse_capture(false)
	await click_control(menu.open_button)
	await get_tree().create_timer(1.5,true).timeout
	check(world.pocket.state==world.pocket.State.OPEN,"pocket gesture opens existing inventory")
	await click_control(world.pocket._window._sections._settings_tab)
	check(menu.opened and get_tree().paused and not world.player.input_enabled and not world.camera_rig.input_enabled,"settings modal freezes game and camera")
	var before: Vector3=world.player.global_position
	world.player.set_move_input(Vector2.UP)
	await get_tree().create_timer(.2,true).timeout
	check(world.player.global_position.is_equal_approx(before),"settings touch does not move actor")
	check(not audio.music.stream_paused and audio.rain.stream_paused,"music audition in menu, world sound paused")
	for language in ["en","ru"]:
		Localization.set_language(language);await get_tree().process_frame
		for control in [menu.panel,menu.open_button,menu.close_button,menu.sliders.music,menu.sliders.distance]:
			check(world.pocket.get_node("RootControl").get_global_rect().encloses(control.get_global_rect()),"settings safe bounds "+language+"/"+control.name)
		check(not menu.labels.music.text.contains("VILLAGE_"),"settings translated "+language)
		await shot("settings-"+language)
	menu.sliders.music.value=0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(audio.MUSIC_BUS)),"music zero mutes bus")
	menu.sliders.music.value=100
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(audio.MUSIC_BUS)) and is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(audio.MUSIC_BUS))),"music hundred unmutes at unity")
	menu.sliders.music.value=45;menu.sliders.sound.value=80
	await click_control(menu.close_button)
	check(not menu.opened and not get_tree().paused and world.player.input_enabled,"close settings restores game")
	check(world.player._touch_move==Vector2.ZERO,"no retained movement after settings")
	check(world.player.get_node("Visual/Body").sprite_frames==world.AcceptedFrames and not world.player.get_node("Visual").is_inventory_access_active(),"accepted hero restored after pocket")
	var key:=InputEventKey.new();key.physical_keycode=KEY_I;key.keycode=KEY_I;key.pressed=true
	get_viewport().push_input(key,true);await get_tree().process_frame
	check(world.pocket.state==world.pocket.State.OPENING,"I starts existing pocket gesture")
	key.pressed=false;get_viewport().push_input(key,true)
	world._notification(NOTIFICATION_APPLICATION_PAUSED)
	world.pocket._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(world.pocket.state==world.pocket.State.CLOSED and not get_tree().paused,"background cancels opening without paused trap")
	world._notification(NOTIFICATION_APPLICATION_PAUSED);await get_tree().create_timer(.15,true).timeout
	check(audio.music.stream_paused and audio.fire.stream_paused,"all audio suspended in background")
	world._notification(NOTIFICATION_APPLICATION_RESUMED);await settle(.2)
	check(not audio.music.stream_paused and not audio.fire.stream_paused,"audio resumes in foreground")
	await audio_route()
	print("AUDIO_INPUT_COMPLETE")

func audio_route() -> void:
	var audio: Node=world.audio
	atmosphere.set_weather(0,true,true);atmosphere.set_hour(14);atmosphere.apply_look()
	var at:=Vector3(-11.75,world.terrain.height_at(-11.75,7.5),7.5)
	await place(at)
	check(audio.surface_at(world.player.global_position)=="dirt","actual road ray selects dirt")
	var before: int=audio.step_count
	await settle(.5)
	check(audio.step_count==before,"idle no footsteps")
	await drive(Vector3(-12.25,0,-4.5),5)
	check(audio.step_count>=before+5,"walking real distance emits footsteps")
	check(audio.last_surface=="dirt","walking road uses dirt bank")
	var grass:=Vector3(-5,world.terrain.height_at(-5,5),5)
	await place(grass)
	check(audio.surface_at(world.player.global_position)=="grass","grass ray differs from road")
	before=audio.step_count;await settle(.2)
	check(audio.step_count==before,"teleport has no extra step burst")
	await place(world.buildings[0].to_global(Vector3(0,.36,0)))
	check(audio.surface_at(world.player.global_position)=="stone","raised house floor overrides terrain")
	# The floor ray honors a real collider's material tag, independent of room ID.
	var fixture:=StaticBody3D.new();fixture.collision_layer=1
	world.add_child(fixture);fixture.position=Vector3(120,12,70)
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(2,.2,2);collider.shape=shape;fixture.add_child(collider)
	await get_tree().physics_frame
	for surface in ["wood","snow"]:
		fixture.set_meta("footstep_surface",surface)
		check(audio.surface_at(fixture.position+Vector3.UP*.1)==surface,"physical surface tag "+surface)
	fixture.queue_free()
	check(audio.surface_at(Vector3(120,20,70)).is_empty(),"no ground ray means no step")
	atmosphere.set_weather(4,true,true);await settle(1.0)
	check(audio.covered and audio.exposure<.3,"roof attenuates weather")
	var indoor_rain: float=audio.rain.volume_db
	await place(at);await settle(1)
	check(not audio.covered and audio.rain.volume_db>indoor_rain+8,"weather louder outdoors")
	audio.thunder_timer=.02;await settle(.2)
	check(audio.thunder.playing,"storm produces thunder")
	atmosphere.set_weather(0,true,true);await settle(.2)
	check(not audio.thunder.playing and audio.rain.volume_db<-60,"clear weather removes rain and thunder")
	if capture:
		world.settings.sound_percent=0
		for value in [0,50,100]:
			world.settings.music_percent=value;audio.apply_volume();audio.music.play(30)
			await settle(.15)
			await record_mix("music-"+str(value),1,value>0)
		check(recorded["music-50"].rms>recorded["music-100"].rms*.18 and recorded["music-50"].rms<recorded["music-100"].rms*.32,"real music volume scales independently")
		world.settings.music_percent=45;world.settings.sound_percent=80;audio.apply_volume()
		await record_mix("forest-clear",3)
		atmosphere.set_weather(4,true,true);audio.thunder_timer=.15
		await record_mix("forest-storm",4)
		await place(world.buildings[0].to_global(Vector3(-.8,.36,-1.9)))
		await record_mix("hearth",3)
		# Record footsteps with music muted for audible surface comparison.
		world.settings.music_percent=0;audio.apply_volume();atmosphere.set_weather(0,true,true)
		for record in [["steps-dirt",at],["steps-grass",grass]]:
			await place(record[1]);world.player.set_move_input(Vector2.UP)
			await record_mix(record[0],2.0);world.player.stop_input()
		world.select_building(0)
		var building: Node3D=world.buildings[0]
		await place(building.to_global(building.record.entry+Vector3(0,0,1.4)))
		check(building.door.try_toggle(world.player),"wooden door begins opening")
		await record_mix("door-open",1.2)
		check(building.door.fraction>.99 and building.door.audio.stream==building.door.CREAK,"recorded creak accompanies opening")
		check(building.door.try_toggle(world.player),"wooden door begins closing")
		await record_mix("door-close",1.5)
		check(building.door.fraction<.01 and building.door.audio.stream==building.door.CLOSE,"wooden close sound only at closed endpoint")
		world.settings.music_percent=45;audio.apply_volume()
		for distance in [80.0,300.0]:
			world.settings.draw_distance=distance;world.settings.apply_distance(world)
			await settle(.2);await shot("distance-"+str(int(distance)))
		world.settings.draw_distance=220;world.settings.apply_distance(world)
		var file:=FileAccess.open(output.path_join("audio-results.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(recorded,"\t"));file.close()
	world.select_building(0)

func record_mix(label: String, seconds: float, audible: bool=true) -> void:
	var recorder:=AudioEffectRecord.new()
	AudioServer.add_bus_effect(0,recorder)
	var index:=AudioServer.get_bus_effect_count(0)-1
	recorder.set_recording_active(true)
	await settle(seconds)
	recorder.set_recording_active(false)
	var recording:=recorder.get_recording()
	check(recording!=null and recording.data.size()>44100,"real mixer recorded "+label)
	if recording!=null:
		check(recording.save_to_wav(output.path_join(label+".wav"))==OK,"save mix "+label)
		var peak:=0.0;var sum:=0.0;var count:=0
		var pcm:=recording.data
		for i in range(0,pcm.size()-1,2):
			var value:=float(pcm.decode_s16(i))/32768
			peak=maxf(peak,absf(value));sum+=value*value;count+=1
		var rms:=sqrt(sum/maxi(count,1))
		check((rms>.0001 if audible else rms<.00002) and peak<.999,"mixer level and no clipping "+label)
		recorded[label]={"peak":peak,"rms":rms,"samples":count}
	AudioServer.remove_bus_effect(0,index)
