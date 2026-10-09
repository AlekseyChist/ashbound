extends VBoxContainer
## Embedded in the existing pocket menu Settings tab; no world-level button.
var world: Node3D
var settings: RefCounted
var panel: Control
var open_button: Button
var close_button: Button
var language_button: Button
## D-115: subtitles on/off and their language (the voice stays English).
var subtitles_button: Button
var subtitle_language_button: Button
var hint: Label
var error_label: Label
var sliders: Dictionary={}
## UI-CLEAN-01: checking tools (time, weather, house picker, return) instead of buttons on the game screen.
var grid: GridContainer
var debug_button: Button
var debug_page: VBoxContainer
var restart_button: Button
var teleport_button: MenuButton
var map_button: Button
var labels: Dictionary={}
var opened: bool:
	get: return is_visible_in_tree() and world.pocket.state==world.pocket.State.OPEN

func configure(owner_world: Node3D, preferences: RefCounted) -> void:
	world=owner_world;settings=preferences;panel=self
	theme=preload("res://assets/ui/ashbound_ui.tres")
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	open_button=world.pocket.get_open_button()
	close_button=world.pocket.get_pocket_panel().get_close_button()
	# D-088: five sliders in two columns, so the language row and the hint stay on a phone screen.
	grid=GridContainer.new();grid.columns=2;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",48);grid.add_theme_constant_override("v_separation",8);add_child(grid)
	for key in ["music","sound","distance","grass","grass_distance"]:
		var cell:=VBoxContainer.new();cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(cell)
		var label:=Label.new();cell.add_child(label);labels[key]=label
		var slider:=HSlider.new();slider.name=key.capitalize();slider.custom_minimum_size=Vector2(760,96)
		slider.min_value=80 if key=="distance" else 15 if key=="grass_distance" else 0
		slider.max_value=settings.MAX_DRAW_DISTANCE if key=="distance" else 45 if key=="grass_distance" else 100
		slider.step=10 if key=="distance" or key=="grass" else 5 if key=="grass_distance" else 1
		slider.value=settings.draw_distance if key=="distance" else settings.grass_percent if key=="grass" else settings.grass_distance if key=="grass_distance" else settings.music_percent if key=="music" else settings.sound_percent
		cell.add_child(slider);sliders[key]=slider
		slider.value_changed.connect(func(value: float): _change(key,value))
		slider.drag_ended.connect(func(_changed: bool): save_settings())
	var row:=HBoxContainer.new();add_child(row)
	var label:=Label.new();label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(label);labels.language=label
	language_button=world._button(row,Vector2(240,120))
	language_button.pressed.connect(func():
		Localization.set_language("en" if Localization.get_language()=="ru" else "ru"))
	var subtitle_row:=HBoxContainer.new();add_child(subtitle_row)
	var subtitle_label:=Label.new();subtitle_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	subtitle_row.add_child(subtitle_label);labels.subtitles=subtitle_label
	subtitles_button=world._button(subtitle_row,Vector2(240,120))
	subtitles_button.name="SubtitlesButton"
	subtitles_button.pressed.connect(func():
		settings.subtitles=not settings.subtitles;_apply_subtitles())
	subtitle_language_button=world._button(subtitle_row,Vector2(300,120))
	subtitle_language_button.name="SubtitleLanguageButton"
	subtitle_language_button.pressed.connect(func():
		var order: Array=settings.SUBTITLE_LANGUAGES
		settings.subtitle_language=order[(order.find(settings.subtitle_language)+1)%order.size()]
		_apply_subtitles())
	debug_button=world._button(row,Vector2(300,120))
	debug_button.name="DebugButton"
	debug_button.pressed.connect(func(): show_debug(not debug_page.visible))
	_build_debug_page()
	hint=Label.new();hint.add_theme_font_size_override("font_size",22);add_child(hint)
	error_label=Label.new();error_label.add_theme_font_size_override("font_size",22);add_child(error_label);error_label.hide()
	Localization.language_changed.connect(_refresh_text)
	_refresh_text();hide()

func _build_debug_page() -> void:
	debug_page=VBoxContainer.new();debug_page.name="DebugPage"
	debug_page.add_theme_constant_override("separation",12)
	add_child(debug_page);move_child(debug_page,grid.get_index()+1)
	if world.atmosphere!=null and world.atmosphere.controls!=null:
		debug_page.add_child(world.atmosphere.controls)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);debug_page.add_child(row)
	world.picker.reparent(row,false)
	world.picker.custom_minimum_size=Vector2(360,120)
	restart_button=world._button(row,Vector2(360,120))
	restart_button.name="RestartButton"
	restart_button.pressed.connect(return_to_start)
	if world.has_method("debug_locations"):
		teleport_button=MenuButton.new();teleport_button.name="TeleportButton"
		teleport_button.custom_minimum_size=Vector2(360,120);teleport_button.flat=false
		row.add_child(teleport_button)
		teleport_button.get_popup().add_theme_font_size_override("font_size",36)
		teleport_button.get_popup().id_pressed.connect(func(id: int):
			world.pocket.close_menu()
			world.teleport_to(world.debug_locations()[id]))
	if world.has_method("open_debug_map"):
		map_button=world._button(row,Vector2(300,120));map_button.name="MapButton"
		map_button.pressed.connect(func():
			world.pocket.close_menu()
			world.open_debug_map())
	debug_page.hide()

## Settings or the Debug page in the same place; the sliders make room for it on a phone.
func show_debug(value: bool) -> void:
	debug_page.visible=value
	grid.visible=not value
	_refresh_text()

## Back to the entrance of the chosen house, as the old "Return to start" button did.
func return_to_start() -> void:
	world.pocket.close_menu()
	world.select_building(world.selected)

func _change(key: String, value: float) -> void:
	if key=="distance": settings.draw_distance=value;settings.apply_distance(world)
	elif key=="grass_distance":
		settings.grass_distance=value
		if world.grass!=null: world.grass.set_reach(value)
	elif key=="grass":
		settings.grass_percent=value
		if world.grass!=null: world.grass.set_density(value/100.0)
	elif key=="music": settings.music_percent=value
	else: settings.sound_percent=value
	world.audio.apply_volume();_refresh_text()

## Shows the subtitle choice on the HUD at once and keeps it.
func _apply_subtitles() -> void:
	world.hud.set_subtitles(settings.subtitles, settings.subtitle_language)
	save_settings();_refresh_text()

func save_settings() -> void:
	if error_label==null:return
	error_label.visible=settings.save_settings()!=OK
	error_label.text=Localization.text("VILLAGE_SETTINGS_ERROR")

func _refresh_text(_language: String="") -> void:
	labels.music.text=Localization.text("VILLAGE_MUSIC_VOLUME")+" · %d%%" % settings.music_percent
	labels.sound.text=Localization.text("VILLAGE_SOUND_VOLUME")+" · %d%%" % settings.sound_percent
	labels.grass.text=Localization.text("VILLAGE_GRASS_DENSITY")+" · %d%%" % settings.grass_percent
	labels.grass_distance.text=Localization.text("VILLAGE_GRASS_DISTANCE")+" · %d " % settings.grass_distance+Localization.text("VILLAGE_METRES")
	labels.distance.text=Localization.text("VILLAGE_DRAW_DISTANCE")+" · %d " % settings.draw_distance+Localization.text("VILLAGE_METRES")
	labels.language.text=Localization.text("SETTINGS_LANGUAGE_TITLE")
	language_button.text="English" if Localization.get_language()=="ru" else "Русский"
	labels.subtitles.text=Localization.text("SETTINGS_SUBTITLES")
	subtitles_button.text=Localization.text("SETTINGS_ON" if settings.subtitles else "SETTINGS_OFF")
	subtitle_language_button.text={"": Localization.text("SETTINGS_SUBTITLES_AS_GAME"), "en": "English", "ru": "Русский"}[settings.subtitle_language]
	subtitle_language_button.disabled=not settings.subtitles
	debug_button.text=Localization.text("MENU_SECTION_SETTINGS" if debug_page.visible else "SETTINGS_DEBUG")
	restart_button.text=Localization.text("FOREST_RETURN_START")
	if map_button!=null: map_button.text=Localization.text("SETTINGS_DEBUG_MAP")
	if teleport_button!=null:
		teleport_button.text=Localization.text("SETTINGS_DEBUG_TELEPORT")
		var popup:=teleport_button.get_popup();popup.clear()
		var places: Array=world.debug_locations()
		for i in places.size():popup.add_item(Localization.text(places[i].key),i)
	hint.text=Localization.text("SETTINGS_DEBUG_HINT" if debug_page.visible else "VILLAGE_SETTINGS_HINT")
