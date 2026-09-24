extends VBoxContainer
## Embedded in the existing pocket menu Settings tab; no world-level button.
var world: Node3D
var settings: RefCounted
var panel: Control
var open_button: Button
var close_button: Button
var language_button: Button
var hint: Label
var error_label: Label
var sliders: Dictionary={}
var labels: Dictionary={}
var opened: bool:
	get: return is_visible_in_tree() and world.pocket.state==world.pocket.State.OPEN

func configure(owner_world: Node3D, preferences: RefCounted) -> void:
	world=owner_world;settings=preferences;panel=self
	theme=preload("res://assets/ui/ashbound_ui.tres")
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	open_button=world.pocket._open_button
	close_button=world.pocket._window._close_button
	for key in ["music","sound","distance"]:
		var label:=Label.new();add_child(label);labels[key]=label
		var slider:=HSlider.new();slider.name=key.capitalize();slider.custom_minimum_size=Vector2(1000,120)
		slider.min_value=80 if key=="distance" else 0
		slider.max_value=300 if key=="distance" else 100
		slider.step=10 if key=="distance" else 1
		slider.value=settings.draw_distance if key=="distance" else settings.music_percent if key=="music" else settings.sound_percent
		add_child(slider);sliders[key]=slider
		slider.value_changed.connect(func(value: float): _change(key,value))
		slider.drag_ended.connect(func(_changed: bool): save_settings())
	var row:=HBoxContainer.new();add_child(row)
	var label:=Label.new();label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(label);labels.language=label
	language_button=world._button(row,Vector2(240,120))
	language_button.pressed.connect(func():
		Localization.set_language("en" if Localization.get_language()=="ru" else "ru"))
	hint=Label.new();hint.add_theme_font_size_override("font_size",22);add_child(hint)
	error_label=Label.new();error_label.add_theme_font_size_override("font_size",22);add_child(error_label);error_label.hide()
	Localization.language_changed.connect(_refresh_text)
	_refresh_text();hide()

func _change(key: String, value: float) -> void:
	if key=="distance": settings.draw_distance=value;settings.apply_distance(world)
	elif key=="music": settings.music_percent=value
	else: settings.sound_percent=value
	world.audio.apply_volume();_refresh_text()

func save_settings() -> void:
	if error_label==null:return
	error_label.visible=settings.save_settings()!=OK
	error_label.text=Localization.text("VILLAGE_SETTINGS_ERROR")

func _refresh_text(_language: String="") -> void:
	labels.music.text=Localization.text("VILLAGE_MUSIC_VOLUME")+" · %d%%" % settings.music_percent
	labels.sound.text=Localization.text("VILLAGE_SOUND_VOLUME")+" · %d%%" % settings.sound_percent
	labels.distance.text=Localization.text("VILLAGE_DRAW_DISTANCE")+" · %d " % settings.draw_distance+Localization.text("VILLAGE_METRES")
	labels.language.text=Localization.text("SETTINGS_LANGUAGE_TITLE")
	language_button.text="English" if Localization.get_language()=="ru" else "Русский"
	hint.text=Localization.text("VILLAGE_SETTINGS_HINT")
