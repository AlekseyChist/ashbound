extends Node
## Village mixer: actual ground travel, current weather, and a real hearth position.
const Catalog = preload("res://scripts/world/village_audio_catalog.gd")
const MUSIC_BUS := "VillageMusic"
const SOUND_BUS := "VillageSound"
const MIX_BUS := "VillageMix"
var world: Node3D
var settings: RefCounted
var music: AudioStreamPlayer
var wind: AudioStreamPlayer
var rain: AudioStreamPlayer
var thunder: AudioStreamPlayer
var step: AudioStreamPlayer
var fire: AudioStreamPlayer3D
var samples: Dictionary = {}
var last_position := Vector3.ZERO
var travel := 0.0
var step_count := 0
var last_surface := ""
var last_variant := -1
var exposure := 1.0
var cover_timer := 0.0
var covered := false
var thunder_timer := 9.0
var rng := RandomNumberGenerator.new()

func configure(owner_world: Node3D, preferences: RefCounted) -> void:
	world=owner_world; settings=preferences
	process_mode=Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	for bus in [MIX_BUS,MUSIC_BUS,SOUND_BUS]:
		if AudioServer.get_bus_index(bus)<0:
			AudioServer.add_bus(); AudioServer.set_bus_name(AudioServer.bus_count-1,bus)
	for bus in [MUSIC_BUS,SOUND_BUS]: AudioServer.set_bus_send(AudioServer.get_bus_index(bus),MIX_BUS)
	var mix_index:=AudioServer.get_bus_index(MIX_BUS)
	if AudioServer.get_bus_effect_count(mix_index)==0:
		var limiter:=AudioEffectHardLimiter.new();limiter.ceiling_db=-1
		AudioServer.add_bus_effect(mix_index,limiter)
	for surface in ["grass","dirt","stone","wood","snow"]:
		var streams: Array[AudioStream]=[]
		for path in Catalog.footsteps(surface): streams.append(load(path))
		samples[surface]=streams
	music=_player("Music",Catalog.music("forest"),true,MUSIC_BUS)
	music.volume_db=-7
	wind=_player("Wind",Catalog.WIND,true,SOUND_BUS)
	rain=_player("Rain",Catalog.RAIN,true,SOUND_BUS)
	thunder=_player("Thunder",Catalog.THUNDER,false,SOUND_BUS)
	step=_player("Footsteps","",false,SOUND_BUS); step.max_polyphony=3
	fire=AudioStreamPlayer3D.new();fire.name="Hearth";fire.bus=SOUND_BUS
	fire.stream=_stream(Catalog.FIRE,true);fire.max_distance=14;fire.unit_size=2.0;fire.volume_db=-9
	world.buildings[0].add_child(fire)
	# Coordinates of the existing H01 hearth (Blender XY -> Godot X/-Z).
	fire.position=Vector3(-1.6,.8,-2.65)
	var listener:=AudioListener3D.new();listener.position=Vector3.UP*1.3
	world.player.add_child(listener);listener.make_current()
	for building in world.buildings: building.door.audio.bus=SOUND_BUS
	last_position=world.player.global_position
	apply_volume()
	for sound in [music,wind,rain,fire]: sound.play()

func _stream(path: String, looped: bool) -> AudioStream:
	var stream: AudioStreamOggVorbis=load(path).duplicate()
	stream.loop=looped
	return stream

func _player(label: String, path: String, looped: bool, bus: String) -> AudioStreamPlayer:
	var sound:=AudioStreamPlayer.new();sound.name=label;sound.bus=bus
	if not path.is_empty(): sound.stream=_stream(path,looped)
	add_child(sound)
	return sound

func apply_volume() -> void:
	for pair in [[MUSIC_BUS,settings.music_percent],[SOUND_BUS,settings.sound_percent]]:
		var index:=AudioServer.get_bus_index(pair[0])
		var volume:=clampf(float(pair[1])/100,0,1)
		AudioServer.set_bus_volume_db(index,linear_to_db(maxf(volume*volume,.0001)))
		AudioServer.set_bus_mute(index,volume<=0)

func _process(delta: float) -> void:
	if world==null: return
	var foreground: bool=world.focus_ok and world.window_focus_ok and world.app_active
	var active: bool=world.is_input_available()
	music.stream_paused=not foreground
	for sound in [wind,rain,thunder,step,fire]: sound.stream_paused=not active
	for building in world.buildings: building.door.audio.stream_paused=not active
	if not active: return
	cover_timer-=delta
	if cover_timer<=0:
		cover_timer=.15
		var origin: Vector3=world.player.global_position+Vector3.UP*1.4
		var query:=PhysicsRayQueryParameters3D.create(origin,origin+Vector3.UP*12,1,[world.player.get_rid()])
		covered=not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	exposure=move_toward(exposure,.22 if covered else 1.0,delta*1.7)
	var weather: Dictionary=world.atmosphere.current
	var gust:=.86+.14*sin(world.atmosphere.effect_time*.71)
	wind.volume_db=linear_to_db(maxf(.30*float(weather.wind)*exposure*gust,.0001))
	rain.volume_db=linear_to_db(maxf(.48*float(weather.rain)*exposure,.0001))
	if world.atmosphere.weather_index==4 and float(weather.rain)>.75:
		thunder_timer-=delta
		if thunder_timer<=0:
			thunder.volume_db=linear_to_db(.6*exposure);thunder.pitch_scale=rng.randf_range(.92,1.06);thunder.play()
			thunder_timer=rng.randf_range(13,26)
	else:
		thunder_timer=9
		if thunder.playing: thunder.stop()
	# Dampen an indoor source outside the house; listener distance is handled by Godot.
	fire.volume_db=-9 if world.buildings[0].contains(world.player.global_position) else -22

func _physics_process(_delta: float) -> void:
	if world==null: return
	var at: Vector3=world.player.global_position
	var moved:=Vector2(at.x-last_position.x,at.z-last_position.z).length()
	last_position=at
	if not world.is_input_available() or not world.player.is_on_floor() or moved>.8 or moved<.002:
		travel=0
		return
	travel+=moved
	var running: bool=world.player.is_running()
	var stride:=1.7 if running else 1.35
	if travel<stride: return
	travel=fmod(travel,stride)
	var surface:=surface_at(at)
	if surface.is_empty(): return
	var choices: Array=samples[surface]
	var variant:=rng.randi_range(0,choices.size()-2)
	if variant>=last_variant: variant+=1
	last_variant=variant;last_surface=surface;step_count+=1
	step.stream=choices[variant]
	step.pitch_scale=rng.randf_range(.95,1.05)
	step.volume_db=-9 if running else -13
	step.play()

func surface_at(at: Vector3) -> String:
	var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*.45,at-Vector3.UP*.65,1,[world.player.get_rid()])
	var hit:=world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<.5: return ""
	var surface: String=hit.collider.get_meta("footstep_surface","stone")
	if surface=="ground":
		return "dirt" if world.terrain.color_at(hit.position.x,hit.position.z).a>.5 else "grass"
	return surface if samples.has(surface) else "stone"

func _notification(what: int) -> void:
	if world==null or music==null: return
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		for sound in [music,wind,rain,thunder,step,fire]: sound.stream_paused=true
		for building in world.buildings: building.door.audio.stream_paused=true

func _exit_tree() -> void:
	# External hearth is owned by the building and freed with the world.
	if is_instance_valid(fire): fire.stop()
