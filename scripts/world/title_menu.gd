extends CanvasLayer
## TITLE-MENU-01 (owner 19 Oct): the start screen over the live world — Continue, New game,
## Settings, Quit and the language. The world stands paused behind it while a camera slowly
## circles the hero; the play HUD is hidden until the game starts.
## New game leaves a mark and reloads the scene; the next world start clears the progress
## before anything loads it (consume_new_game_mark). Settings and the language stay.

const MARK := "user://new_game.mark"
## World progress kept outside the world save until the campaign save (SAVE-01) joins them.
const PROGRESS_FILES := ["user://world_lesson.cfg", "user://world_inn.cfg", "user://village_atmosphere.cfg"]
const SAVE_DIRECTORY := "user://world-save-v1"
const BOOK := preload("res://assets/ui/ashbound_ui.tres")
## UI book 1.0 roles: panel #212429, border #B89452, text #EDE6D6; the logo is a new role (96).
const SHADE := Color(0.13, 0.14, 0.16)
const LOGO_SIZE := 96
const BUTTON_SIZE := Vector2(480, 120)
const ORBIT_RADIUS := 34.0
const ORBIT_HEIGHT := 16.0
const ORBIT_SPEED := 0.035
const SLIDERS := ["music", "sound", "distance", "grass", "grass_distance"]

var world: Node3D
var camera: Camera3D
var root: Control
var pages := {}
var buttons := {}
var language_buttons := {}
var slider_labels := {}
var confirm_label: Label
var loading_label: Label
var version_label: Label
var hidden_layers: Array[CanvasLayer] = []
var center := Vector3.ZERO
var angle := 0.0


## Clears the world progress when New game was chosen; true when it did (the title is then skipped).
static func consume_new_game_mark() -> bool:
	if not FileAccess.file_exists(MARK):
		return false
	for path in PROGRESS_FILES:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var directory := DirAccess.open(SAVE_DIRECTORY)
	if directory != null:
		for file in directory.get_files():
			directory.remove(file)
	# The inventory is an autoload: it outlives the scene reload.
	var inventory: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Inventory")
	if inventory != null:
		var equipped := {}
		for slot in inventory.equipped:
			equipped[slot] = null
		inventory.load_save_data({"schema_version": 1, "items": [], "equipped": equipped, "gold": 0})
	DirAccess.remove_absolute(MARK)
	return true


func open(owner_world: Node3D) -> void:
	world = owner_world
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	for node in world.find_children("*", "CanvasLayer", true, false):
		var canvas := node as CanvasLayer
		if canvas != self and canvas.visible:
			canvas.hide()
			hidden_layers.append(canvas)
	var play_camera: Camera3D = world.camera_rig.get_camera()
	center = world.player.global_position
	angle = world.camera_rig._yaw + PI
	camera = Camera3D.new()
	camera.name = "TitleCamera"
	camera.fov = play_camera.fov
	camera.far = play_camera.far
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(camera)
	camera.make_current()
	_place_camera()
	get_tree().paused = true
	world.sync_input_state()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	Localization.language_changed.connect(_refresh_text)
	_refresh_text()
	_show_page("main")


func _process(delta: float) -> void:
	angle += ORBIT_SPEED * delta
	_place_camera()


func _place_camera() -> void:
	camera.global_position = center + Vector3(sin(angle) * ORBIT_RADIUS, ORBIT_HEIGHT, cos(angle) * ORBIT_RADIUS)
	camera.look_at(center + Vector3.UP * 2.0)


func _build() -> void:
	root = Control.new()
	root.name = "Root"
	root.theme = BOOK
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# A shade from the left edge, so the panel reads over a bright sky or snow.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(SHADE, .78))
	gradient.set_color(1, Color(SHADE, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(.62, 0)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	holder.offset_left = 120
	holder.offset_right = 120 + 820
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_theme_constant_override("separation", 24)
	root.add_child(holder)
	var logo := Label.new()
	logo.text = "ASHBOUND"
	logo.add_theme_font_size_override("font_size", LOGO_SIZE)
	holder.add_child(logo)
	var main := _page(holder, "main")
	for id in ["continue", "new_game", "settings", "quit"]:
		_add_button(main, id)
	var languages := HBoxContainer.new()
	languages.add_theme_constant_override("separation", 12)
	main.add_child(languages)
	for code in ["en", "ru"]:
		var button := Button.new()
		button.text = "English" if code == "en" else "Русский"
		button.custom_minimum_size = Vector2(234, 96)
		button.toggle_mode = true
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.pressed.connect(func(): Localization.set_language(code))
		languages.add_child(button)
		language_buttons[code] = button
	buttons.continue.visible = _has_progress()
	buttons.quit.visible = not OS.has_feature("mobile")
	buttons.continue.pressed.connect(_start)
	buttons.new_game.pressed.connect(func(): _show_page("confirm") if _has_progress() else _start())
	buttons.settings.pressed.connect(func(): _show_page("settings"))
	buttons.quit.pressed.connect(func(): get_tree().quit())
	var confirm := _page(holder, "confirm")
	confirm_label = Label.new()
	confirm_label.custom_minimum_size.x = BUTTON_SIZE.x
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm.add_child(confirm_label)
	_add_button(confirm, "confirm_new").pressed.connect(_new_game)
	_add_button(confirm, "cancel").pressed.connect(func(): _show_page("main"))
	var loading := _page(holder, "loading")
	loading_label = Label.new()
	loading.add_child(loading_label)
	var settings := _page(holder, "settings")
	for key in SLIDERS:
		var source: HSlider = world.settings_menu.sliders[key]
		var label := Label.new()
		settings.add_child(label)
		slider_labels[key] = label
		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(760, 72)
		slider.min_value = source.min_value
		slider.max_value = source.max_value
		slider.step = source.step
		slider.value = source.value
		# The pocket menu's slider applies, saves and words the value (village_settings_menu.gd).
		slider.value_changed.connect(func(value: float):
			source.value = value
			label.text = world.settings_menu.labels[key].text)
		slider.drag_ended.connect(func(_changed: bool): world.settings_menu.save_settings())
		settings.add_child(slider)
	_add_button(settings, "back").pressed.connect(func():
		world.settings_menu.save_settings()
		_show_page("main"))
	version_label = Label.new()
	version_label.add_theme_font_size_override("font_size", 22)
	version_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version_label.offset_right = -32
	version_label.offset_bottom = -24
	root.add_child(version_label)


func _page(parent: Control, id: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	parent.add_child(page)
	pages[id] = page
	return page


func _add_button(parent: Control, id: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	parent.add_child(button)
	buttons[id] = button
	return button


func _show_page(id: String) -> void:
	for page_id in pages:
		pages[page_id].visible = page_id == id
	var first: Button = {"main": buttons.continue if buttons.continue.visible else buttons.new_game,
		"confirm": buttons.cancel, "settings": buttons.back}.get(id)
	if first != null:
		first.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (pages.confirm.visible or pages.settings.visible):
		world.settings_menu.save_settings()
		_show_page("main")
		get_viewport().set_input_as_handled()


func _refresh_text(_language: String = "") -> void:
	var keys := {"continue": "TITLE_CONTINUE", "new_game": "TITLE_NEW_GAME", "settings": "MENU_SECTION_SETTINGS",
		"quit": "TITLE_QUIT", "confirm_new": "TITLE_NEW_GAME", "cancel": "TITLE_CANCEL", "back": "TITLE_BACK"}
	for id in keys:
		buttons[id].text = Localization.text(keys[id])
	confirm_label.text = Localization.text("TITLE_NEW_GAME_CONFIRM")
	loading_label.text = Localization.text("TITLE_LOADING")
	version_label.text = "%s %s" % [Localization.text("TITLE_VERSION"), ProjectSettings.get_setting("application/config/version", "")]
	for code in language_buttons:
		language_buttons[code].set_pressed_no_signal(Localization.get_language() == code)
	for key in slider_labels:
		slider_labels[key].text = world.settings_menu.labels[key].text


func _has_progress() -> bool:
	return world.save != null and world.save.load_status in ["loaded", "recovered"]


func _start() -> void:
	for canvas in hidden_layers:
		if is_instance_valid(canvas):
			canvas.show()
	world.camera_rig.get_camera().make_current()
	camera.queue_free()
	get_tree().paused = false
	world.sync_input_state()
	queue_free()


func _new_game() -> void:
	var file := FileAccess.open(MARK, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("new game")
	file.close()
	if world.save != null:
		world.save.enabled = false
	_show_page("loading")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	get_tree().reload_current_scene()
