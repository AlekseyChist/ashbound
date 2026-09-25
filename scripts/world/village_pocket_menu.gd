extends "res://scripts/courtyard/courtyard_inventory_menu.gd"
## Reuse pocket animation, inventory tabs and Android Back ownership.
var world: Node3D
var previous_pause:=false
var styled_section:=""

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	super._ready()
	_root_control.get_node("QuickBar").queue_free()
	var book: Theme=preload("res://assets/ui/ashbound_ui.tres")
	_root_control.theme=book
	_open_button.offset_top=180;_open_button.offset_bottom=300
	_open_button.custom_minimum_size=Vector2(288,120)
	_open_button.add_theme_font_size_override("font_size",30)
	for style in ["normal","hover","pressed","focus","disabled"]:
		_open_button.add_theme_stylebox_override(style,book.get_stylebox(style,"Button"))
	_window.add_theme_stylebox_override("panel",book.get_stylebox("panel","PanelContainer"))
	opened.connect(func():
		get_tree().paused=true
		world.sync_input_state())
	closed.connect(func():
		get_tree().paused=previous_pause
		if world.settings_menu!=null: world.settings_menu.save_settings()
		world.sync_input_state())

func request_open() -> bool:
	if not world.is_input_available(): return false
	previous_pause=get_tree().paused
	return super.request_open()

func _process(delta: float) -> void:
	super._process(delta)
	if state!=State.OPEN:return
	var key: String=_window.current_section()+Localization.get_language()
	if key==styled_section:return
	styled_section=key
	_window.style_sections(_root_control.theme)

func get_open_button() -> Button:
	return _open_button

func get_pocket_panel() -> Control:
	return _window
