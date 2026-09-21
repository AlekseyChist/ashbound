class_name SettingsMenuView
extends RefCounted
## View for the courtyard settings page (language selection).
## Composed into touch_inventory_panel; does not own navigation.

const _BG_COLOR := Color(0.10, 0.11, 0.12)
const _BORDER_COLOR := Color(0.56, 0.44, 0.25)
const _TEXT_COLOR := Color(0.88, 0.85, 0.77)
const _SELECTED_BG_COLOR := Color(0.56, 0.44, 0.25)
const _SELECTED_TEXT_COLOR := Color(0.98, 0.93, 0.80)
const _CORNER_RADIUS := 6.0
const _MARGIN := 20.0

enum LanguageCode { AUTO, EN, RU }

var page: VBoxContainer

var _panel: Control
var _localization: Node
var _settings_error: Label
var _heading: Label
var _hint: Label
var _buttons: Dictionary = {}


func _init(panel: Control) -> void:
	_panel = panel
	_localization = panel.get("_localization") as Node
	_settings_error = panel.get("_settings_error") as Label
	page = _build_page()
	var root_vbox: VBoxContainer = panel.get_node("Margin/RootVBox")
	var body_index := root_vbox.get_node_or_null("Body").get_index() if root_vbox.has_node("Body") else -1
	if body_index >= 0:
		root_vbox.add_child(page)
		root_vbox.move_child(page, body_index + 1)
	else:
		root_vbox.add_child(page)
	page.visible = false
	refresh()


func _build_page() -> VBoxContainer:
	var p := VBoxContainer.new()
	p.name = "SettingsPage"
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_constant_override("separation", 24)

	var margin := MarginContainer.new()
	margin.name = "PageMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(_MARGIN))
	margin.add_theme_constant_override("margin_right", int(_MARGIN))
	margin.add_theme_constant_override("margin_top", int(_MARGIN))
	margin.add_theme_constant_override("margin_bottom", int(_MARGIN))
	p.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	margin.add_child(content)

	_heading = Label.new()
	_heading.name = "LanguageTitle"
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading.add_theme_font_size_override("font_size", 44)
	content.add_child(_heading)

	_hint = Label.new()
	_hint.name = "LanguageHint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 30)
	content.add_child(_hint)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	_buttons[LanguageCode.AUTO] = _build_button("LanguageAuto", "UI_LANGUAGE_AUTO")
	_buttons[LanguageCode.EN] = _build_button("LanguageEnglish", "LOC_LANGUAGE_ENGLISH")
	_buttons[LanguageCode.RU] = _build_button("LanguageRussian", "LOC_LANGUAGE_RUSSIAN")
	for code in [LanguageCode.AUTO, LanguageCode.EN, LanguageCode.RU]:
		content.add_child(_buttons[code])

	return p


func _build_button(control_name: String, text_key: String) -> Button:
	var button := Button.new()
	button.name = control_name
	button.text = text_key
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.custom_minimum_size = Vector2(600, 120)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 38)
	_apply_button_style(button, false)
	return button


func _apply_button_style(button: Button, selected: bool) -> void:
	var border_color := _SELECTED_BG_COLOR if selected else _BORDER_COLOR
	var text_color := _SELECTED_TEXT_COLOR if selected else _TEXT_COLOR
	var width := 3 if selected else 1
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_stylebox_override("normal", _make_style(_BG_COLOR, border_color, width))
	button.add_theme_stylebox_override("hover", _make_style(_BG_COLOR, border_color, width))
	button.add_theme_stylebox_override("pressed", _make_style(_SELECTED_BG_COLOR if selected else _BG_COLOR, border_color, width))
	button.add_theme_stylebox_override("focus", _make_style(_BG_COLOR, border_color, width))


func _make_style(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(int(_CORNER_RADIUS))
	style.content_margin_left = _MARGIN
	style.content_margin_right = _MARGIN
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


func refresh() -> void:
	if page == null:
		return
	var has_service := _localization != null and _localization.has_method("get_preference")
	var preference := "auto"
	if has_service:
		preference = str(_localization.get_preference())
	_heading.text = _panel._text("SETTINGS_LANGUAGE_TITLE")
	_hint.text = _panel._text("SETTINGS_LANGUAGE_HINT")
	for code in [LanguageCode.AUTO, LanguageCode.EN, LanguageCode.RU]:
		var button: Button = _buttons[code]
		button.disabled = not has_service
		var selected := preference == _code_to_string(code)
		button.set_pressed_no_signal(selected)
		match code:
			LanguageCode.AUTO:
				button.text = _panel._text("UI_LANGUAGE_AUTO")
			LanguageCode.EN:
				button.text = _panel._text("LOC_LANGUAGE_ENGLISH")
			LanguageCode.RU:
				button.text = _panel._text("LOC_LANGUAGE_RUSSIAN")
		_apply_button_style(button, selected)


func hit_test(pos: Vector2) -> Dictionary:
	if page == null or not is_instance_valid(page) or not page.is_visible_in_tree():
		return {}
	for code in [LanguageCode.AUTO, LanguageCode.EN, LanguageCode.RU]:
		var button: Button = _buttons[code]
		if button.disabled or not button.is_visible_in_tree():
			continue
		if button.get_global_rect().has_point(pos):
			return {"kind": "setting_language", "id": _code_to_string(code), "control": button}
	return {}


func choose_language(code: String) -> void:
	if page == null or not is_instance_valid(page) or not page.is_visible_in_tree():
		return
	var has_service := _localization != null and _localization.has_method("set_language")
	if not has_service or not _is_supported_code(code):
		return
	var result: Error = _localization.set_language(code)
	if result == OK:
		_settings_error.visible = false
	else:
		_settings_error.text = _panel._text("INV_SETTINGS_FAILURE")
		_settings_error.visible = true
	refresh()




func _code_to_string(code: int) -> String:
	match code:
		LanguageCode.AUTO:
			return "auto"
		LanguageCode.EN:
			return "en"
		LanguageCode.RU:
			return "ru"
	return "auto"


func _is_supported_code(code: String) -> bool:
	return code == "auto" or code == "en" or code == "ru"
