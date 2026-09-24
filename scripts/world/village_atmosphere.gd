extends Node
## Isolated preview clock: no campaign calendar, no offline catch-up.
const Profiles=preload("res://scripts/world/village_weather_profiles.gd")
const Rain=preload("res://scripts/world/village_rain.gd")
const SAVE_PATH="user://village_atmosphere.cfg"
var world: Node3D
var hour:=15.5
var effect_time:=0.0
var weather_index:=0
var current: Dictionary
var target: Dictionary
var transition_from: Dictionary
var transition_elapsed:=12.0
var wetness:=0.0
var daylight:=1.0
var profiles: Array[Dictionary]=Profiles.all()
var sky_material: ProceduralSkyMaterial
var rain: Node3D
var foliage_materials: Array[ShaderMaterial]=[]
var time_button: Button
var weather_button: Button
var clock_label: Label
var auto_weather:=true
var weather_elapsed:=0.0
var save_elapsed:=0.0
var force_pause:=false

func configure(scene: Node3D) -> void:
	world=scene
	current=profiles[0].duplicate();target=current.duplicate();transition_from=current.duplicate()
	var sky:=Sky.new()
	sky.radiance_size=Sky.RADIANCE_SIZE_64
	sky.process_mode=Sky.PROCESS_MODE_INCREMENTAL
	sky_material=ProceduralSkyMaterial.new()
	sky_material.sky_curve=.2
	sky.sky_material=sky_material
	world.environment.sky=sky
	world.environment.background_mode=Environment.BG_SKY
	world.environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	world.environment.adjustment_enabled=true
	world.environment.adjustment_contrast=1.12
	world.environment.adjustment_saturation=1.12
	world.environment.ambient_light_sky_contribution=0.0
	for building in world.buildings:
		var fill: OmniLight3D=building.get_node("InteriorFill")
		fill.shadow_enabled=true
		fill.omni_range=7.5
	_setup_foliage()
	_shade_legacy_props()
	rain=Rain.new();rain.name="Precipitation";world.add_child(rain);rain.configure(world)
	_controls()
	load_state()
	apply_look()
	Localization.language_changed.connect(_refresh_text)

func _process(delta: float) -> void:
	if world==null or not world.is_input_available() or force_pause: return
	advance(delta)
	apply_look()
	save_elapsed+=delta
	if save_elapsed>=15.0: save_elapsed=0.0;save_state()

func advance(seconds: float) -> void:
	if not is_finite(seconds) or seconds<0: return
	hour=fposmod(hour+seconds/60.0,24.0)
	effect_time=fposmod(effect_time+seconds,3600.0)
	# Preserve every crossed boundary; after a full cycle the wetness has settled.
	var remaining:=900.0+fmod(seconds,900.0) if auto_weather and seconds>1800.0 else seconds
	while remaining>0.000001:
		var step:=minf(remaining,180.0-weather_elapsed) if auto_weather else remaining
		_advance_transition(step)
		remaining-=step
		if auto_weather:
			weather_elapsed+=step
			if weather_elapsed>=179.999999: set_weather((weather_index+1)%profiles.size(),false)

func _advance_transition(seconds: float) -> void:
	transition_elapsed=minf(12.0,transition_elapsed+seconds)
	var weight:=smoothstep(0.0,12.0,transition_elapsed)
	for key in ["rain","wind","fog","cloud","wet"]:
		current[key]=lerpf(float(transition_from[key]),float(target[key]),weight)
	wetness=move_toward(wetness,float(current.wet),seconds/35.0)

func set_hour(value: float) -> void:
	if is_finite(value): hour=fposmod(value,24.0)

func set_weather(index: int, manual: bool=true, instant: bool=false) -> void:
	if index<0 or index>=profiles.size(): return
	weather_index=index
	transition_from=current.duplicate()
	target=profiles[index].duplicate()
	transition_elapsed=12.0 if instant else 0.0
	if instant: current=target.duplicate();wetness=float(current.wet)
	if manual: auto_weather=false
	weather_elapsed=0.0

func apply_look() -> void:
	var elevation:=sin((hour-6.0)/24.0*TAU)
	daylight=smoothstep(-.25,.35,elevation)
	var dusk: float=(1.0-smoothstep(.0,.45,absf(elevation)))*(1.0-float(current.cloud))
	var overcast:=float(current.cloud)
	world.sun.rotation_degrees=Vector3(-maxf(4.0,absf(elevation)*(60.0 if elevation>=0 else 35.0)),hour*15.0-180.0,0)
	world.sun.light_color=Color("b7c6e5").lerp(Color("fff0da").lerp(Color("ffb078"),dusk),daylight)
	world.sun.light_energy=lerpf(.22,1.25,daylight)*(1.0-overcast*.65)
	world.environment.ambient_light_color=Color("576f94").lerp(Color("89978e"),daylight)
	world.environment.ambient_light_energy=lerpf(.16,.24,daylight)*(1.0-overcast*.12)
	world.environment.adjustment_contrast=lerpf(1.025,1.10,daylight)
	var horizon:=Color("16242f").lerp(Color("859487"),daylight).lerp(Color("a36f4b"),dusk*.7)
	horizon=horizon.lerp(Color("45545b").lerp(Color("101c29"),1.0-daylight),overcast*.75)
	sky_material.sky_top_color=Color("050b16").lerp(Color("355966"),daylight).lerp(horizon,overcast*.65)
	sky_material.sky_horizon_color=horizon
	sky_material.ground_bottom_color=Color("080c09")
	sky_material.ground_horizon_color=horizon
	world.environment.fog_light_color=horizon
	world.environment.fog_light_energy=lerpf(.25,.75,daylight)
	world.environment.fog_density=float(current.fog)
	world.environment.fog_height=.5
	world.environment.fog_height_density=float(current.fog)*.8
	world.terrain.material.set_shader_parameter("wetness",wetness)
	for material in foliage_materials:
		material.set_shader_parameter("effect_time",effect_time)
		material.set_shader_parameter("wind_strength",float(current.wind))
		material.set_shader_parameter("wetness",wetness)
	var warm:=0.0
	for building in world.buildings:
		var light: OmniLight3D=building.get_node("InteriorFill")
		light.light_color=Color("ffb264")
		light.light_energy=lerpf(1.8,.7,daylight)
		var local: Vector3=building.to_local(world.player.global_position)
		if absf(local.x)<float(building.record.width)*.5 and absf(local.z)<float(building.record.depth)*.5+1.0:
			warm=maxf(warm,1.0-smoothstep(2.0,6.0,local.length()))
	var hero_color:=Color("33415b").lerp(Color("eee1c9"),daylight*(1.0-overcast*.23))
	hero_color=hero_color.lerp(Color("d8a06d"),warm*(1.0-daylight*.55))
	world.player.get_node("Visual/Body").modulate=hero_color
	rain.update_weather(effect_time,float(current.rain),float(current.wind),daylight)
	_refresh_text()

func _shade_legacy_props() -> void:
	# Older imported kit props are unlit; make their response match the whole day/night scene.
	for mesh: MeshInstance3D in world.dressing.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var material: Material=mesh.get_active_material(surface)
			if material is StandardMaterial3D and material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED:
				var lit: StandardMaterial3D=material.duplicate()
				lit.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
				mesh.set_surface_override_material(surface,lit)

func _setup_foliage() -> void:
	var cache: Dictionary={}
	for batch in world.dressing.foliage_batches:
		var original: StandardMaterial3D=batch.multimesh.mesh.surface_get_material(0)
		var tree: bool="pine" in batch.name or "spruce" in batch.name
		var key:=str(original.get_instance_id())+str(tree)
		if not cache.has(key):
			var material:=ShaderMaterial.new();material.shader=preload("res://assets/shaders/village_foliage.gdshader")
			material.set_shader_parameter("tint",original.albedo_color)
			material.set_shader_parameter("has_texture",original.albedo_texture!=null)
			if original.albedo_texture!=null: material.set_shader_parameter("albedo_texture",original.albedo_texture)
			material.set_shader_parameter("painted_weight",tree)
			material.set_shader_parameter("amplitude",.55 if tree else .16)
			foliage_materials.append(material);cache[key]=material
		batch.material_override=cache[key]
		batch.extra_cull_margin=2.0 if tree else .6

func _controls() -> void:
	var bar:=VBoxContainer.new();bar.name="AtmosphereControls";bar.position=Vector2(24,176)
	bar.add_theme_constant_override("separation",12)
	world.hud.get_node("RootControl").add_child(bar)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);bar.add_child(row)
	time_button=world._button(row,Vector2(240,120))
	weather_button=world._button(row,Vector2(340,120))
	clock_label=Label.new();clock_label.add_theme_font_size_override("font_size",22);bar.add_child(clock_label)
	time_button.pressed.connect(func():
		if not world.is_input_available(): return
		var hours: Array[float]=[6.5,12,18.5,23]
		var next: float=hours[0]
		for at in hours:
			if at>hour+.05: next=at;break
		set_hour(next);apply_look();save_state())
	weather_button.pressed.connect(func():
		if not world.is_input_available(): return
		if weather_index==profiles.size()-1 and not auto_weather:
			auto_weather=true;set_weather(0,false)
		else: set_weather((weather_index+1)%profiles.size())
		_refresh_text();save_state())

func _refresh_text(_language: String="") -> void:
	if time_button==null: return
	time_button.text=Localization.text("VILLAGE_TIME")+" %02d:%02d"%[floori(hour),floori(fmod(hour,1.0)*60)]
	weather_button.text=Localization.text(str(profiles[weather_index].label))
	clock_label.text=Localization.text("VILLAGE_WEATHER_AUTO" if auto_weather else "VILLAGE_WEATHER_MANUAL")

func save_state(path: String=SAVE_PATH) -> Error:
	var config:=ConfigFile.new()
	config.set_value("atmosphere","hour",hour)
	config.set_value("atmosphere","weather",weather_index)
	config.set_value("atmosphere","automatic",auto_weather)
	config.set_value("atmosphere","wetness",wetness)
	config.set_value("atmosphere","weather_elapsed",weather_elapsed)
	return config.save(path)

func load_state(path: String=SAVE_PATH) -> void:
	var config:=ConfigFile.new()
	if config.load(path)!=OK: return
	var saved_hour: Variant=config.get_value("atmosphere","hour",hour)
	var saved_weather: Variant=config.get_value("atmosphere","weather",0)
	var saved_auto: Variant=config.get_value("atmosphere","automatic",true)
	var saved_wet: Variant=config.get_value("atmosphere","wetness",0.0)
	var saved_elapsed: Variant=config.get_value("atmosphere","weather_elapsed",0.0)
	if (saved_hour is float or saved_hour is int) and is_finite(float(saved_hour)): set_hour(float(saved_hour))
	if saved_weather is int and saved_weather>=0 and saved_weather<profiles.size(): set_weather(saved_weather,false,true)
	if saved_auto is bool: auto_weather=saved_auto
	if (saved_wet is float or saved_wet is int) and is_finite(float(saved_wet)):wetness=clampf(float(saved_wet),0,1)
	if (saved_elapsed is float or saved_elapsed is int) and is_finite(float(saved_elapsed)):weather_elapsed=clampf(float(saved_elapsed),0,179.999)
	# A new launch starts at the saved target profile, keeps ground wetness, and never advances offline.

func _notification(what: int) -> void:
	if world!=null and what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_CLOSE_REQUEST]: save_state()
