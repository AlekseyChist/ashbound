extends CanvasLayer
## Компактная панель предпросмотра кулака (отдельный 3D-вьюпорт).
## Никаких допущений про 2D-камеру/игрока.

var sandbox: Node = null
var _owner: Node = null

var _root: Control
var _panel: PanelContainer
var _title: Label
var _hint: Label
var _note: Label
var _novice_button: Button
var _trained_button: Button
var _backpack_button: Button
var _view_button: Button
var _buttons: Array = []

# Состояние тач-обработки (один палец).
var _touch_finger_id: int = -1
var _touch_button_index: int = -1

const _PI := PI


func setup(owner: Node) -> void:
	if _owner != null:
		return
	_owner = owner
	sandbox = owner
	_build_ui()
	_connect_signals()
	refresh()


func refresh() -> void:
	if _owner == null or not is_inside_tree():
		return
	var loc := _get_localization()
	if loc != null:
		_title.text = loc.text("FIST_PREVIEW_TITLE")
		_novice_button.text = loc.text("FIST_PREVIEW_NOVICE")
		_trained_button.text = loc.text("FIST_PREVIEW_TRAINED")
		_backpack_button.text = loc.text(
			"FIST_PREVIEW_PACK_ON" if _owner.is_backpack_enabled() else "FIST_PREVIEW_PACK_OFF"
		)
		_view_button.text = loc.text("FIST_PREVIEW_VIEW")
		_hint.text = loc.text("FIST_PREVIEW_HINT")
		_note.text = loc.text("FIST_PREVIEW_NOTE")
	var tech: String = _owner.technique
	_novice_button.set_pressed_no_signal(tech == "novice")
	_trained_button.set_pressed_no_signal(tech == "trained")
	_backpack_button.set_pressed_no_signal(_owner.is_backpack_enabled())
	_apply_button_style(_novice_button, tech == "novice")
	_apply_button_style(_trained_button, tech == "trained")
	_apply_button_style(_backpack_button, _owner.is_backpack_enabled())
	_apply_button_style(_view_button, false)


func _ready() -> void:
	if _owner != null:
		refresh()


func _process(_delta: float) -> void:
	if _owner == null or not is_inside_tree():
		return
	var state := _get_menu_state()
	if state != 0:
		# Меню открыто/открывается — прячем панель и сбрасываем тач.
		_cancel_touch()
		if _root.visible:
			_root.visible = false
	else:
		if not _root.visible:
			_root.visible = true


func _input(event: InputEvent) -> void:
	if _owner == null or not is_inside_tree():
		return
	var menu_state := _get_menu_state()
	if menu_state != 0:
		# Меню поверх — клавиатура игнорируется, тач отменяем.
		_cancel_touch()
		return

	if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		return

	var key := _key_event(event)
	if key != -1:
		match key:
			KEY_F1, KEY_F2, KEY_F3, KEY_F4:
				_activate(key - KEY_F1)
				get_viewport().set_input_as_handled()
		return

	var st := event as InputEventScreenTouch
	if st != null:
		_handle_screen_touch(st)
		return

	var sd := event as InputEventScreenDrag
	if sd != null:
		if _touch_finger_id >= 0 and sd.index == _touch_finger_id:
			get_viewport().set_input_as_handled()
		return

	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			# Эмуляция мыши на Android — глотаем, чтобы не дублировать тач.
			if _touch_finger_id >= 0 or _point_in_panel(mb.position):
				get_viewport().set_input_as_handled()
		return


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_touch()


# ---------------------------------------------------------------------------
# Построение UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	layer = 50
	_root = (load("res://scripts/courtyard/adaptive_screen_root.gd") as GDScript).new()
	_root.name = "FistPreviewRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "FistPreviewPanel"
	_root.add_child(_panel)
	# Якорь: центр по горизонтали, верх.
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -620.0
	_panel.offset_right = 620.0
	_panel.offset_top = 12.0
	_style_panel(_panel)

	var margin := MarginContainer.new()
	margin.name = "FistPreviewMargin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "FistPreviewVBox"
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_title = Label.new()
	_title.name = "FistPreviewTitle"
	_title.add_theme_font_size_override("font_size", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)

	var hbox := HBoxContainer.new()
	hbox.name = "FistPreviewButtons"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	_novice_button = _make_button("NoviceButton")
	_trained_button = _make_button("TrainedButton")
	_backpack_button = _make_button("BackpackButton")
	_view_button = _make_button("ViewButton", false)

	hbox.add_child(_novice_button)
	hbox.add_child(_trained_button)
	hbox.add_child(_backpack_button)
	hbox.add_child(_view_button)

	_buttons = [_novice_button, _trained_button, _backpack_button, _view_button]
	for i in range(_buttons.size()):
		var realButton: Button = _buttons[i]
		realButton.pressed.connect(_activate.bind(i))

	_hint = Label.new()
	_hint.name = "FistPreviewHint"
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = OS.get_name() != "Android"
	vbox.add_child(_hint)

	_note = Label.new()
	_note.name = "FistPreviewNote"
	_note.add_theme_font_size_override("font_size", 18)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_note)


func _make_button(btn_name: String, toggle: bool = true) -> Button:
	var b := Button.new()
	b.name = btn_name
	b.custom_minimum_size = Vector2(280, 88)
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	return b


func _apply_button_style(button: Button, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = Color(0.32, 0.24, 0.1, 0.95)
		style.border_color = Color(0.85, 0.68, 0.3)
	else:
		style.bg_color = Color(0.1, 0.11, 0.14, 0.92)
		style.border_color = Color(0.3, 0.32, 0.38, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	button.add_theme_stylebox_override("normal", style)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.36, 0.27, 0.12, 0.95) if selected else Color(0.14, 0.15, 0.19, 0.95)
	hover.border_color = style.border_color
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(10)
	hover.content_margin_left = 12.0
	hover.content_margin_right = 12.0
	hover.content_margin_top = 8.0
	hover.content_margin_bottom = 8.0
	button.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.26, 0.19, 0.08, 0.95) if selected else Color(0.08, 0.09, 0.12, 0.95)
	pressed.border_color = style.border_color
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(10)
	pressed.content_margin_left = 12.0
	pressed.content_margin_right = 12.0
	pressed.content_margin_top = 8.0
	pressed.content_margin_bottom = 8.0
	button.add_theme_stylebox_override("pressed", pressed)

	var font_color := Color(1.0, 0.95, 0.8) if selected else Color(0.78, 0.8, 0.85)
	for state in ["font", "hover_font", "pressed_font"]:
		button.add_theme_color_override(state, font_color)


func _style_panel(p: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.92)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	p.add_theme_stylebox_override("panel", style)


func _connect_signals() -> void:
	var loc := _get_localization()
	if loc != null:
		loc.language_changed.connect(_on_language_changed)
	var inv := _owner.get_node_or_null("/root/Inventory")
	if inv != null:
		inv.storage_changed.connect(_on_storage_changed)


func _on_language_changed(_language: String) -> void:
	refresh()


func _on_storage_changed() -> void:
	refresh()


# ---------------------------------------------------------------------------
# Действия (единый вход для кнопок, клавиш и тача)
# ---------------------------------------------------------------------------

func _activate(index: int) -> void:
	if _owner == null:
		return
	if _get_menu_state() != 0:
		return
	match index:
		0:
			_owner.set_technique("novice")
		1:
			_owner.set_technique("trained")
		2:
			_owner.set_backpack_enabled(not _owner.is_backpack_enabled())
		3:
			_rotate_view()
	refresh()


func _rotate_view() -> void:
	var level: Node = _owner.level
	if level == null:
		return
	var cam := level.get_node_or_null("CameraRig") as Node3D
	if cam == null or not cam.has_method("rotate_view"):
		return
	var sensitivity: float = cam.mouse_sensitivity
	if is_zero_approx(sensitivity):
		sensitivity = 1.0
	cam.rotate_view(Vector2(-_PI / 2.0 / sensitivity, 0.0))


# ---------------------------------------------------------------------------
# Тач-обработка
# ---------------------------------------------------------------------------

func _handle_screen_touch(st: InputEventScreenTouch) -> void:
	var vp := get_viewport()
	if st.pressed:
		if _touch_finger_id >= 0:
			# Второй палец внутри панели — глотаем, не даём украсть/активировать.
			if _point_in_panel(st.position):
				vp.set_input_as_handled()
			return
		var idx := _button_index_at(st.position)
		if idx >= 0:
			_touch_finger_id = st.index
			_touch_button_index = idx
			vp.set_input_as_handled()
		elif _point_in_panel(st.position):
			# Фон панели — глотаем, чтобы камера не крутилась.
			vp.set_input_as_handled()
	else:
		if st.index == _touch_finger_id:
			var idx := _touch_button_index
			_touch_finger_id = -1
			_touch_button_index = -1
			vp.set_input_as_handled()
			if not st.canceled and idx >= 0:
				var btn: Button = _buttons[idx]
				if btn.get_global_rect().has_point(st.position):
					_activate(idx)


func _cancel_touch() -> void:
	_touch_finger_id = -1
	_touch_button_index = -1


# ---------------------------------------------------------------------------
# Вспомогательные
# ---------------------------------------------------------------------------




func _point_in_panel(pos: Vector2) -> bool:
	if not _root.visible or not _panel.visible:
		return false
	return _panel.get_global_rect().has_point(pos)


func _button_index_at(pos: Vector2) -> int:
	for i in range(_buttons.size()):
		var b: Button = _buttons[i]
		if b.get_global_rect().has_point(pos):
			return i
	return -1


func _key_event(event: InputEvent) -> int:
	var kb := event as InputEventKey
	if kb == null or not kb.pressed or kb.echo:
		return -1
	return kb.keycode


func _get_localization() -> Node:
	return get_node_or_null("/root/Localization")


func _get_menu_state() -> int:
	var level: Node = _owner.level if _owner != null else null
	if level == null:
		return 0
	var menu: Node = level.get_node_or_null("InventoryMenu")
	if menu == null or not menu.has_method("get_menu_state"):
		return 0
	return menu.get_menu_state()
