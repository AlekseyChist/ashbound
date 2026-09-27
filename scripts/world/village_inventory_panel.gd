extends "res://scripts/courtyard/touch_inventory_panel.gd"
## Item gestures keep the header; native sliders own their pointers.
var native_settings: Control
var setting_pointers: Dictionary={}

func _input(event: InputEvent) -> void:
	if native_settings!=null and native_settings.is_visible_in_tree():
		var pointer:= -10
		if event is InputEventScreenTouch or event is InputEventScreenDrag: pointer=event.index
		if event is InputEventMouseButton or event is InputEventScreenTouch:
			if event.pressed and native_settings.get_global_rect().has_point(event.position):
				_reset_gesture();setting_pointers[pointer]=true
			if setting_pointers.has(pointer):
				if not event.pressed: setting_pointers.erase(pointer)
				return
		elif event is InputEventMouseMotion or event is InputEventScreenDrag:
			if setting_pointers.has(pointer): return
	else: setting_pointers.clear()
	super._input(event)

## Put the village Settings page in place of the generic one.
func use_settings_page(page: Control) -> void:
	$Margin/RootVBox.add_child(page)
	_sections._settings_view.page.hide()
	_sections._settings_view.page = page
	native_settings = page

func get_close_button() -> Button:
	return _close_button

func current_section() -> String:
	return _sections.current_section

## Book style for the section tabs; the open tab looks pressed. Coins only on the items tab.
func style_sections(book: Theme) -> void:
	_coins.visible = _sections.current_section == "items"
	var tabs := {_sections._items_tab: "items", _sections._map_tab: "map", _sections._quests_tab: "quests", _sections._character_tab: "character", _sections._settings_tab: "settings"}
	for button: Button in tabs.keys() + [_close_button]:
		button.custom_minimum_size = Vector2(240, 120)
		button.add_theme_font_size_override("font_size", 30)
		for color in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color", "font_disabled_color"]:
			button.remove_theme_color_override(color)
		for style in ["normal", "hover", "pressed", "focus", "disabled"]:
			var role: String = "pressed" if style == "normal" and tabs.get(button, "") == _sections.current_section else style
			button.add_theme_stylebox_override(style, book.get_stylebox(role, "Button"))
