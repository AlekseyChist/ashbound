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
	var key: String=_window._sections.current_section+Localization.get_language()
	if key==styled_section:return
	styled_section=key
	var book: Theme=_root_control.theme
	var sections: RefCounted=_window._sections
	_window._coins.visible=sections.current_section=="items"
	var tabs: Dictionary={sections._items_tab:"items",sections._map_tab:"map",sections._quests_tab:"quests",sections._character_tab:"character",sections._settings_tab:"settings"}
	for button: Button in tabs.keys()+[_window._close_button]:
		button.custom_minimum_size=Vector2(240,120)
		button.add_theme_font_size_override("font_size",30)
		for color in ["font_color","font_pressed_color","font_hover_color","font_focus_color","font_disabled_color"]:
			button.remove_theme_color_override(color)
		for style in ["normal","hover","pressed","focus","disabled"]:
			var role: String="pressed" if style=="normal" and tabs.get(button,"")==sections.current_section else style
			button.add_theme_stylebox_override(style,book.get_stylebox(role,"Button"))
