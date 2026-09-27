extends CanvasLayer
## Компактная панель «Тренировка» для combat-dodge превью.
## По умолчанию свёрнута: одна кнопка у верхнего левого края раскрывает
## две колонки крупных кнопок (новичок/обученный, рюкзак, камера, сброс).
## Не меняет технику/рюкзак/камеру и не ставит игру на паузу.

signal reset_requested

var _owner: Node = null
var _sandbox: Node = null

var _root: Control
var _toggle: Button
var _panel: PanelContainer
var _title: Label
var _novice_button: Button
var _trained_button: Button
var _backpack_button: Button
var _view_button: Button
var _reset_button: Button
var _dodge_hint: Label
var _defense_hint: Label
var _buttons: Array = []

# Владение жестом: один владелец (mouse pointer id или finger id).
# Сентинелы не совпадают ни с реальными device/index, ни друг с другом.
const _NO_OWNER_ID := -90001
const _MOUSE_DEVICE_OFFSET := 100000

var _owner_id: int = _NO_OWNER_ID
var _owner_button_index: int = -1
# Перманентно отключённый тап (перетаскивание/выход за кнопку).
var _gesture_disarmed: bool = false
# Блокировка (меню/пауза/потеря фокуса): жесты и F1–F4 игнорируются.
var _disabled: bool = false
# Персистентные флаги блокировки: каждый снимается только своим IN/RESUMED,
# чтобы одно снятие не стирало другое активное условие.
var _focus_out: bool = false
var _window_focus_out: bool = false
var _app_paused: bool = false

const _PI := PI
const UI_THEME := preload("res://assets/ui/ashbound_ui.tres")


func setup(owner: Node) -> void:
	if _owner != null:
		return
	_owner = owner
	_sandbox = owner
	layer = 50
	_build_ui()
	_connect_signals()
	refresh()


func refresh() -> void:
	if _owner == null or not is_inside_tree():
		return
	var loc := _get_localization()
	if loc != null:
		_toggle.text = loc.text("COMBAT_TOOLS_CLOSE") if _panel.visible else loc.text("COMBAT_TOOLS_OPEN")
		_title.text = loc.text("COMBAT_TOOLS_TITLE")
		_novice_button.text = loc.text("FIST_PREVIEW_NOVICE")
		_trained_button.text = loc.text("FIST_PREVIEW_TRAINED")
		_view_button.text = loc.text("FIST_PREVIEW_VIEW")
		_reset_button.text = loc.text("DEFENSE_RESET")
		var is_touch := OS.has_feature("android")
		var platform_key := "DODGE_HINT_TOUCH" if is_touch else "DODGE_HINT_PC"
		var level_key := "DEFENSE_NOVICE_HINT" if _is_novice() else "DEFENSE_TRAINED_HINT"
		_dodge_hint.text = loc.text(platform_key)
		_defense_hint.text = loc.text(level_key)
	var tech: String = _owner.technique
	_novice_button.set_pressed_no_signal(tech == "novice")
	_trained_button.set_pressed_no_signal(tech == "trained")
	_apply_button_style(_toggle, false)
	_apply_button_style(_novice_button, tech == "novice")
	_apply_button_style(_trained_button, tech == "trained")
	_apply_button_style(_view_button, false)
	_apply_button_style(_reset_button, false)


func _ready() -> void:
	if _owner != null:
		refresh()


func _process(_delta: float) -> void:
	if _owner == null or not is_inside_tree():
		return
	var disabled := _is_blocked()
	if disabled and not _disabled:
		_set_disabled(true)
	elif not disabled and _disabled:
		_set_disabled(false)


func _input(event: InputEvent) -> void:
	if _owner == null or not is_inside_tree():
		return
	if _is_blocked():
		# Меню/пауза/потеря фокуса — клавиатура игнорируется, жест отменяем.
		_cancel_gesture()
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
		if _owner_id >= 0 and sd.index == _owner_id:
			_disarm_gesture(sd.position)
			get_viewport().set_input_as_handled()
		return

	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			# Эмуляция мыши на Android — глотаем, чтобы не дублировать тач.
			if _owner_id >= 0 or _point_in_panel(mb.position):
				get_viewport().set_input_as_handled()
			return
		var mouse_owner := mb.device + _MOUSE_DEVICE_OFFSET
		if mb.pressed:
			if mb.canceled:
				return
			if _owner_id != _NO_OWNER_ID:
				# Чужой жест уже идёт — не даём украсть.
				if _point_in_panel(mb.position):
					get_viewport().set_input_as_handled()
				return
			var idx := _button_index_at(mb.position)
			if idx >= 0:
				_owner_id = mouse_owner
				_owner_button_index = idx
				_gesture_disarmed = false
				get_viewport().set_input_as_handled()
			elif _toggle.get_global_rect().has_point(mb.position):
				# Тоггл: индекс 5, только видимость/подпись.
				_owner_id = mouse_owner
				_owner_button_index = 5
				_gesture_disarmed = false
				get_viewport().set_input_as_handled()
			elif _point_in_panel(mb.position):
				# Фон раскрытой панели — глотаем, чтобы камера не крутилась.
				_owner_id = mouse_owner
				_owner_button_index = -1
				_gesture_disarmed = false
				get_viewport().set_input_as_handled()
		else:
			# Чужая кнопка (например, ПКМ) не завершает удерживаемый жест ЛКМ.
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mouse_owner == _owner_id:
				var idx := _owner_button_index
				var was_canceled := mb.canceled
				var disarmed := _gesture_disarmed
				_clear_owner()
				get_viewport().set_input_as_handled()
				if not was_canceled and not disarmed and idx >= 0:
					_activate_if_inside(idx, mb.position)
		return

	var mm := event as InputEventMouseMotion
	if mm != null:
		# Только реальный жест мыши этого устройства; тач-жесты не трогаем.
		if _owner_id >= _MOUSE_DEVICE_OFFSET and mm.device + _MOUSE_DEVICE_OFFSET == _owner_id:
			_disarm_gesture(mm.position)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focus_out = true
			_set_disabled(_is_blocked())
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_focus_out = true
			_set_disabled(_is_blocked())
		NOTIFICATION_APPLICATION_PAUSED:
			_app_paused = true
			# _process остановлен — сворачиваем/прячем/отменяем немедленно.
			_set_disabled(_is_blocked())
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focus_out = false
			_set_disabled(_is_blocked())
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_focus_out = false
			_set_disabled(_is_blocked())
		NOTIFICATION_APPLICATION_RESUMED:
			_app_paused = false
			# Пересчёт объединённых гейтов; остаёмся свёрнутыми.
			_set_disabled(_is_blocked())
		NOTIFICATION_PAUSED:
			# Дерево на паузе — немедленно сворачиваем/прячем/отменяем жест.
			_set_disabled(true)
		NOTIFICATION_UNPAUSED:
			# Дерево снова идёт — пересчитываем блокировку.
			_set_disabled(_is_blocked())


# ---------------------------------------------------------------------------
# Построение UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = (load("res://scripts/courtyard/adaptive_screen_root.gd") as GDScript).new()
	_root.name = "CombatToolsRoot"
	_root.theme = UI_THEME
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Кнопка раскрытия у верхнего левого края внутри safe rect.
	_toggle = _make_button("CombatToolsToggle", "COMBAT_TOOLS_OPEN", Vector2(260, 120), false)
	_toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toggle)
	_toggle.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toggle.position = Vector2.ZERO
	_toggle.offset_left = 24.0
	_toggle.offset_top = 24.0
	_toggle.offset_right = 284.0
	_toggle.offset_bottom = 144.0

	# Раскрытая панель слева под кнопкой, две колонки крупных кнопок.
	_panel = PanelContainer.new()
	_panel.name = "CombatToolsPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_root.add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2.ZERO
	_panel.offset_left = 432.0
	_panel.offset_top = 156.0
	_panel.offset_right = 1132.0
	_panel.offset_bottom = 792.0
	_style_panel(_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "CombatToolsVBox"
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	_title = Label.new()
	_title.name = "CombatToolsTitle"
	_title.add_theme_font_size_override("font_size", 32)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)

	var grid := GridContainer.new()
	grid.name = "CombatToolsGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)

	_novice_button = _make_button("NoviceButton", "FIST_PREVIEW_NOVICE", Vector2(260, 120))
	_trained_button = _make_button("TrainedButton", "FIST_PREVIEW_TRAINED", Vector2(260, 120))
	_backpack_button = _make_button("BackpackButton", "FIST_PREVIEW_PACK_OFF", Vector2(260, 120))
	_backpack_button.visible = false
	_view_button = _make_button("ViewButton", "FIST_PREVIEW_VIEW", Vector2(260, 120), false)
	_reset_button = _make_button("ToolsResetButton", "DEFENSE_RESET", Vector2(260, 120), false)

	grid.add_child(_novice_button)
	grid.add_child(_trained_button)
	grid.add_child(_backpack_button)
	grid.add_child(_view_button)
	grid.add_child(_reset_button)

	_buttons = [_novice_button, _trained_button, _backpack_button, _view_button, _reset_button]
	for i in range(_buttons.size()):
		var realButton: Button = _buttons[i]
		realButton.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dodge_hint = Label.new()
	_dodge_hint.name = "CombatToolsDodgeHint"
	_dodge_hint.add_theme_font_size_override("font_size", 22)
	_dodge_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_dodge_hint)

	_defense_hint = Label.new()
	_defense_hint.name = "CombatToolsDefenseHint"
	_defense_hint.add_theme_font_size_override("font_size", 22)
	_defense_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_defense_hint)


func _make_button(btn_name: String, text_key: String, min_size: Vector2, toggle: bool = true) -> Button:
	var b := Button.new()
	b.name = btn_name
	b.theme = UI_THEME
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 30)
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.text = Localization.text(text_key)
	return b


func _apply_button_style(button: Button, selected: bool) -> void:
	var hud := _get_hud_attack_button()
	if hud == null:
		return
	var normal_key := "pressed" if selected else "normal"
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var src_state: String = state if state != "normal" else normal_key
		var sb: StyleBox = hud.get_theme_stylebox(src_state)
		if sb != null:
			button.add_theme_stylebox_override(state, sb)
	var font: Font = hud.get_theme_font("font")
	if font != null:
		button.add_theme_font_override("font", font)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(state, hud.get_theme_color(state))


func _style_panel(p: PanelContainer) -> void:
	if _owner == null or not is_instance_valid(_owner):
		return
	var level: Node = _owner.get("level")
	if level == null or not is_instance_valid(level):
		return
	var panel: Node = level.get_node_or_null("HUD/RootControl/TopLeftPanel")
	if panel is PanelContainer:
		var sb: StyleBox = (panel as PanelContainer).get_theme_stylebox("panel")
		if sb != null:
			p.add_theme_stylebox_override("panel", sb)


func _get_hud_attack_button() -> Button:
	if _owner == null or not is_instance_valid(_owner):
		return null
	var level: Node = _owner.get("level")
	if level == null or not is_instance_valid(level):
		return null
	var hud: Node = level.get_node_or_null("HUD")
	if hud == null:
		return null
	var btn: Button = hud.get("_btn_attack") as Button
	return btn


func _connect_signals() -> void:
	var loc := _get_localization()
	if loc != null and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)
	var inv := _owner.get_node_or_null("/root/Inventory")
	if inv != null and inv.has_signal("storage_changed"):
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
	if _disabled or _get_menu_state() != 0 or get_tree().paused:
		return
	match index:
		0:
			_owner.set_technique("novice")
		1:
			_owner.set_technique("trained")
		2:
			pass # D-057: the backpack toggle is gone; the slot keeps button indices stable.
		3:
			_rotate_view()
		4:
			reset_requested.emit()
		5:
			# Тоггл: только видимость/подпись, без техники/рюкзака/камеры.
			_panel.visible = not _panel.visible
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
# Тач-обработка (один владелец жеста)
# ---------------------------------------------------------------------------

func _handle_screen_touch(st: InputEventScreenTouch) -> void:
	var vp := get_viewport()
	if st.pressed:
		if st.canceled:
			return
		if _owner_id != _NO_OWNER_ID:
			# Второй палец внутри панели — глотаем, не даём украсть/активировать.
			if _point_in_panel(st.position):
				vp.set_input_as_handled()
			return
		var idx := _button_index_at(st.position)
		if idx >= 0:
			_owner_id = st.index
			_owner_button_index = idx
			_gesture_disarmed = false
			vp.set_input_as_handled()
		elif _toggle.get_global_rect().has_point(st.position):
			# Тоггл: индекс 5, только видимость/подпись.
			_owner_id = st.index
			_owner_button_index = 5
			_gesture_disarmed = false
			vp.set_input_as_handled()
		elif _point_in_panel(st.position):
			# Фон раскрытой панели — глотаем, чтобы камера не крутилась.
			_owner_id = st.index
			_owner_button_index = -1
			_gesture_disarmed = false
			vp.set_input_as_handled()
	else:
		if st.index == _owner_id:
			var idx := _owner_button_index
			var was_canceled := st.canceled
			var disarmed := _gesture_disarmed
			_clear_owner()
			vp.set_input_as_handled()
			if not was_canceled and not disarmed and idx >= 0:
				_activate_if_inside(idx, st.position)


func _cancel_gesture() -> void:
	_clear_owner()


func _clear_owner() -> void:
	_owner_id = _NO_OWNER_ID
	_owner_button_index = -1
	_gesture_disarmed = false


func _disarm_gesture(pos: Vector2) -> void:
	# Перманентно отключаем текущий тап (перетаскивание/выход за кнопку).
	if _owner_id == _NO_OWNER_ID:
		return
	var idx := _owner_button_index
	if idx < 0:
		# Фон панели — не отключаем: маленький дрейф остаётся валидным тапом.
		return
	var btn: Button
	if idx == 5:
		btn = _toggle
	else:
		btn = _buttons[idx]
	if not btn.is_visible_in_tree():
		return
	# Только выход ТЕКУЩЕЙ точки за исходный прямоугольник кнопки отключает;
	# мелкий дрейф внутри кнопки остаётся валидным тапом.
	if not btn.get_global_rect().has_point(pos):
		_gesture_disarmed = true


func _is_blocked() -> bool:
	if _owner == null or not is_inside_tree():
		return false
	return (
		_focus_out
		or _window_focus_out
		or _app_paused
		or _get_menu_state() != 0
		or get_tree().paused
	)


func _activate_if_inside(index: int, pos: Vector2) -> void:
	if index == 5:
		if _toggle != null and is_instance_valid(_toggle):
			if _toggle.get_global_rect().has_point(pos):
				_activate(5)
		return
	if index < 0 or index >= _buttons.size():
		return
	var btn: Button = _buttons[index]
	if btn == null or not is_instance_valid(btn):
		return
	if btn.get_global_rect().has_point(pos):
		_activate(index)


func _set_disabled(disabled: bool) -> void:
	if disabled == _disabled:
		return
	_disabled = disabled
	_cancel_gesture()
	if disabled:
		# Меню/пауза/потеря фокуса — прячем весь корень, панель сворачиваем.
		if _root != null and is_instance_valid(_root):
			_root.visible = false
		if _panel != null and is_instance_valid(_panel) and _panel.visible:
			_panel.visible = false
	else:
		# Возврат — остаёмся свёрнутыми, корень снова виден.
		if _root != null and is_instance_valid(_root):
			_root.visible = true
	refresh()


# ---------------------------------------------------------------------------
# Вспомогательные
# ---------------------------------------------------------------------------

func _point_in_panel(pos: Vector2) -> bool:
	if not _root.visible or not _panel.visible:
		return false
	if not _panel.is_visible_in_tree():
		return false
	return _panel.get_global_rect().has_point(pos)


func _button_index_at(pos: Vector2) -> int:
	for i in range(_buttons.size()):
		var b: Button = _buttons[i]
		if not b.is_visible_in_tree():
			continue
		if b.get_global_rect().has_point(pos):
			return i
	return -1


func _key_event(event: InputEvent) -> int:
	var kb := event as InputEventKey
	if kb == null or not kb.pressed or kb.echo:
		return -1
	return kb.keycode


func _is_novice() -> bool:
	if _owner == null:
		return false
	return _owner.get("technique") == "novice"


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
