extends CanvasLayer
## Isolated defense prototype toolbar (CanvasLayer 51).
## No shared HUD changes. All labels via Localization PO keys.
## All real mouse/touch/key input is handled manually in _input;
## GUI button signals are intentionally not used.

const UI_THEME := preload("res://assets/ui/ashbound_ui.tres")
const AdaptiveScreenRootScript := preload("res://scripts/courtyard/adaptive_screen_root.gd")

enum GuardSource { NONE, KEY, MOUSE, RIGHT_MOUSE, TOUCH }

const SWING := 1
const RESET := 2
const MOUSE_POINTER_ID := -1000

var _sandbox: Node = null
var _controller: Node = null
var _root: Control = null
var _swing_btn: Button = null
var _reset_btn: Button = null
var _guard_btn: Button = null
var _hint_label: Label = null
var _hint_panel: Panel = null
var _guard_cue_style: StyleBoxFlat = null
# Cached HUD Attack button styles/colors, copied once during creation.
var _hud_font: Font = null
var _hud_font_size: int = 30
var _hud_font_color: Color = Color.WHITE
var _hud_font_hover_color: Color = Color.WHITE
var _hud_font_pressed_color: Color = Color.WHITE
var _hud_font_disabled_color: Color = Color.WHITE
var _guard_normal_style: StyleBox = null
var _guard_hover_style: StyleBox = null
var _guard_pressed_style: StyleBox = null

# Pointer ownership: pointer_id (finger index or MOUSE_POINTER_ID) -> button id.
var _pointer_buttons := {}
# Single guard owner: source + optional finger id.
var _guard_source: int = GuardSource.NONE
var _guard_owner_finger: int = -1

var _menu_open: bool = false
var _app_focus: bool = true
var _app_paused: bool = false
var _tree_paused: bool = false


func setup(sandbox: Node, controller: Node) -> void:
	_sandbox = sandbox
	_controller = controller
	layer = 51
	_build_ui()
	_refresh_labels()
	_update_guard_visual()
	var loc := get_node_or_null("/root/Localization")
	if loc != null and loc.has_signal("language_changed"):
		loc.connect("language_changed", _on_language_changed)


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = AdaptiveScreenRootScript.new()
	_root.name = "FistDefenseRoot"
	_root.theme = UI_THEME
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var top_row := HBoxContainer.new()
	top_row.name = "DefenseTopRow"
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 12)
	_root.add_child(top_row)

	_swing_btn = _make_button("SwingButton", "DEFENSE_SWING", Vector2(260, 120))
	_reset_btn = _make_button("ResetTrialButton", "DEFENSE_RESET", Vector2(260, 120))
	top_row.add_child(_swing_btn)
	top_row.add_child(_reset_btn)

	_hint_panel = Panel.new()
	_hint_panel.name = "DefenseHintPanel"
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud: Node = _level().get_node("HUD") if _level() != null else null
	if hud != null:
		var top_left := hud.get_node_or_null("RootControl/TopLeftPanel")
		if top_left != null:
			var panel_style: StyleBox = top_left.get_theme_stylebox("panel")
			if panel_style != null:
				_hint_panel.add_theme_stylebox_override("panel", panel_style)
	_root.add_child(_hint_panel)

	_hint_label = Label.new()
	_hint_label.name = "DefenseHintLabel"
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 22)
	_root.add_child(_hint_label)

	_guard_btn = _make_button("GuardButton", "DEFENSE_GUARD", Vector2(240, 120))
	_root.add_child(_guard_btn)

	_build_guard_cue_style()
	_cache_hud_attack_styles(hud)

	# Anchors/offsets set AFTER all children are added.
	top_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_row.offset_left = -270.0
	top_row.offset_right = 270.0
	top_row.offset_top = 245.0
	top_row.offset_bottom = 365.0

	_hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint_panel.offset_left = -620.0
	_hint_panel.offset_right = 620.0
	_hint_panel.offset_top = 377.0
	_hint_panel.offset_bottom = 453.0

	_hint_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint_label.offset_left = -600.0
	_hint_label.offset_right = 600.0
	_hint_label.offset_top = 385.0
	_hint_label.offset_bottom = 445.0

	_guard_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Left of the main HUD attack button (x1640..1888 in logical 1920):
	# right edge at -310 leaves a 30px gap; UI Book action height is 120.
	_guard_btn.offset_left = -610.0
	_guard_btn.offset_top = -325.0
	_guard_btn.offset_right = -310.0
	_guard_btn.offset_bottom = -205.0


func _make_button(btn_name: String, text_key: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.name = btn_name
	b.theme = UI_THEME
	b.custom_minimum_size = min_size
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.focus_mode = Control.FOCUS_NONE
	if _hud_font != null:
		b.add_theme_font_override("font", _hud_font)
	b.add_theme_font_size_override("font_size", _hud_font_size)
	b.add_theme_color_override("font_color", _hud_font_color)
	b.add_theme_color_override("font_hover_color", _hud_font_hover_color)
	b.add_theme_color_override("font_pressed_color", _hud_font_pressed_color)
	b.add_theme_color_override("font_disabled_color", _hud_font_disabled_color)
	b.text = Localization.text(text_key)
	return b


func _cache_hud_attack_styles(hud: Node) -> void:
	if hud == null:
		return
	var attack := hud.get("_btn_attack") as Button
	if attack == null:
		return
	_hud_font = attack.get_theme_font("font")
	_hud_font_size = attack.get_theme_font_size("font_size")
	_hud_font_color = attack.get_theme_color("font_color")
	_hud_font_hover_color = attack.get_theme_color("font_hover_color")
	_hud_font_pressed_color = attack.get_theme_color("font_pressed_color")
	_hud_font_disabled_color = attack.get_theme_color("font_disabled_color")
	_guard_normal_style = attack.get_theme_stylebox("normal")
	_guard_hover_style = attack.get_theme_stylebox("hover")
	_guard_pressed_style = attack.get_theme_stylebox("pressed")
	for btn: Button in [_swing_btn, _reset_btn, _guard_btn]:
		if btn == null:
			continue
		if _hud_font != null:
			btn.add_theme_font_override("font", _hud_font)
		if _hud_font_size > 0:
			btn.add_theme_font_size_override("font_size", _hud_font_size)
		if _hud_font_color.a > 0.0:
			btn.add_theme_color_override("font_color", _hud_font_color)
		if _hud_font_hover_color.a > 0.0:
			btn.add_theme_color_override("font_hover_color", _hud_font_hover_color)
		if _hud_font_pressed_color.a > 0.0:
			btn.add_theme_color_override("font_pressed_color", _hud_font_pressed_color)
		if _hud_font_disabled_color.a > 0.0:
			btn.add_theme_color_override("font_disabled_color", _hud_font_disabled_color)
		if _guard_normal_style != null:
			btn.add_theme_stylebox_override("normal", _guard_normal_style)
		for state in ["disabled", "focus"]:
			btn.add_theme_stylebox_override(state, attack.get_theme_stylebox(state))
		if _guard_hover_style != null:
			btn.add_theme_stylebox_override("hover", _guard_hover_style)
		if _guard_pressed_style != null:
			btn.add_theme_stylebox_override("pressed", _guard_pressed_style)
	if _hint_label != null and _hud_font_color.a > 0.0:
		_hint_label.add_theme_color_override("font_color", _hud_font_color)


func _build_guard_cue_style() -> void:
	_guard_cue_style = UI_THEME.get_stylebox("normal", "GuardCue") as StyleBoxFlat


func _refresh_labels() -> void:
	if _swing_btn:
		_swing_btn.text = Localization.text("DEFENSE_SWING")
	if _reset_btn:
		_reset_btn.text = Localization.text("DEFENSE_RESET")
	if _guard_btn:
		_guard_btn.text = Localization.text("DEFENSE_GUARD")
	_update_hint()
	_update_guard_visual()


func _on_language_changed(_language: String) -> void:
	_refresh_labels()


# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

func _level() -> Node:
	if _sandbox == null:
		return null
	var level: Node = _sandbox.get("level")
	return level


func _is_novice() -> bool:
	if _sandbox == null:
		return false
	return _sandbox.get("technique") == "novice"


func _player_attack_allowed() -> bool:
	var level := _level()
	if level == null:
		return false
	# The courtyard sandbox keeps the hero under Actors; the player rig of the world at its root.
	var player := level.get_node_or_null("Actors/Player")
	if player == null:
		player = level.get_node_or_null("Player")
	if player == null or not player.has_method("is_attack_allowed"):
		return false
	return player.is_attack_allowed()


func _menu_is_open() -> bool:
	var level := _level()
	if level == null:
		return false
	var menu := level.get_node_or_null("InventoryMenu")
	if menu == null or not menu.has_method("get_menu_state"):
		return false
	return menu.get_menu_state() != 0


func _gating_ok() -> bool:
	return _app_focus and not _app_paused and not _tree_paused \
		and not _menu_is_open() and _player_attack_allowed()


func _snapshot() -> Dictionary:
	if not is_instance_valid(_controller) or not _controller.has_method("snapshot"):
		return {}
	var snap: Dictionary = _controller.snapshot()
	return snap if snap is Dictionary else {}


func _phase() -> String:
	return String(_snapshot().get("phase", "idle"))


# ---------------------------------------------------------------------------
# Guard ownership (single owner: keyboard, real mouse or one touch finger)
# ---------------------------------------------------------------------------

func _guard_is_active() -> bool:
	if not is_instance_valid(_controller):
		return false
	var snap := _snapshot()
	return bool(snap.get("guarding", false))


func _release_guard(source: int, finger: int = -1) -> void:
	if _guard_source == source and (source != GuardSource.TOUCH or finger == _guard_owner_finger):
		_guard_source = GuardSource.NONE
		_guard_owner_finger = -1
		if is_instance_valid(_controller) and _controller.has_method("set_guard"):
			_controller.set_guard(false)
	_update_guard_visual()


func _block_window_open() -> bool:
	return is_instance_valid(_controller) \
		and _controller.has_method("is_block_window_open") \
		and bool(_controller.is_block_window_open())


func _update_guard_visual() -> void:
	if _guard_btn:
		var guarding := _guard_is_active()
		var cue := _gating_ok() and _block_window_open()
		if cue:
			_guard_btn.text = Localization.text("DEFENSE_GUARD")
			_guard_btn.modulate = Color.WHITE
			_guard_btn.add_theme_stylebox_override("normal", _guard_cue_style)
			_guard_btn.add_theme_stylebox_override("hover", _guard_cue_style)
			_guard_btn.add_theme_stylebox_override("pressed", _guard_cue_style)
			_guard_btn.add_theme_color_override("font_color", UI_THEME.get_color("font_color", "GuardCue"))
			_guard_btn.add_theme_color_override("font_hover_color", UI_THEME.get_color("font_color", "GuardCue"))
			_guard_btn.add_theme_color_override("font_pressed_color", UI_THEME.get_color("font_color", "GuardCue"))
		else:
			_guard_btn.text = Localization.text("DEFENSE_GUARD")
			_guard_btn.modulate = Color.WHITE
			if _guard_normal_style != null:
				# Held state shows the cached pressed style in normal state.
				_guard_btn.add_theme_stylebox_override("normal", _guard_pressed_style if guarding else _guard_normal_style)
			if _guard_hover_style != null:
				_guard_btn.add_theme_stylebox_override("hover", _guard_hover_style)
			if _guard_pressed_style != null:
				_guard_btn.add_theme_stylebox_override("pressed", _guard_pressed_style)
			if _hud_font_color.a > 0.0:
				_guard_btn.add_theme_color_override("font_color", _hud_font_color)
			if _hud_font_hover_color.a > 0.0:
				_guard_btn.add_theme_color_override("font_hover_color", _hud_font_hover_color)
			if _hud_font_pressed_color.a > 0.0:
				_guard_btn.add_theme_color_override("font_pressed_color", _hud_font_pressed_color)
	# Disable the swing visual while the phase is not idle.
	if _swing_btn:
		_swing_btn.disabled = _phase() != "idle"


# ---------------------------------------------------------------------------
# Actions (single entry for keys, mouse and touch)
# ---------------------------------------------------------------------------

func _request_swing() -> void:
	if not _gating_ok():
		return
	var phase := _phase()
	if phase == "windup" or phase == "recovery":
		return
	if is_instance_valid(_controller) and _controller.has_method("start_swing"):
		_controller.start_swing()


func _request_reset() -> void:
	if not _gating_ok():
		return
	if is_instance_valid(_controller) and _controller.has_method("reset_trial"):
		_clear_all_input()
		_controller.reset_trial()


# ---------------------------------------------------------------------------
# Input (before GUI/camera/HUD)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _root == null or not is_inside_tree():
		return

	# While the toolbar is disabled/hidden (menu open, paused, no focus,
	# attack not allowed) we must not consume or track touches at all so
	# menu fingers reach the actual menu. This gate runs before ANY event
	# processing, including emulated mouse from touch.
	if not _gating_ok():
		_clear_all_input()
		return

	var key := event as InputEventKey
	if key != null:
		_handle_key(key)
		return

	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			# Emulated mouse from touch: never invoke guard/actions.
			if _inside_own_control(mb.position):
				get_viewport().set_input_as_handled()
			return
		_handle_real_mouse(mb)
		return

	var st := event as InputEventScreenTouch
	if st != null:
		_handle_screen_touch(st)
		return

	var sd := event as InputEventScreenDrag
	if sd != null:
		_handle_screen_drag(sd)


func _handle_key(key: InputEventKey) -> void:
	# Physical keycodes keep G/F5/F6 working on non-QWERTY layouts.
	var kc := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if kc == KEY_G:
		if key.pressed and not key.echo:
			if _gating_ok() and _guard_source == GuardSource.NONE:
				if is_instance_valid(_controller) and _controller.has_method("set_guard"):
					if bool(_controller.set_guard(true)):
						_guard_source = GuardSource.KEY
						_guard_owner_finger = -1
						_update_guard_visual()
			get_viewport().set_input_as_handled()
		elif not key.pressed:
			_release_guard(GuardSource.KEY)
			get_viewport().set_input_as_handled()
		return

	if key.pressed and not key.echo:
		if kc == KEY_F5:
			_request_swing()
			get_viewport().set_input_as_handled()
		elif kc == KEY_F6:
			_request_reset()
			get_viewport().set_input_as_handled()


func _handle_real_mouse(mb: InputEventMouseButton) -> void:
	# Right mouse is an independent guard owner (desktop only). It must be
	# resolved before the LEFT path so leftUP/G-UP/touch-UP cannot release a
	# right-owned guard and rightUP cannot release another owner.
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if OS.has_feature("android"):
			return
		# Canceled is always a release, even while pressed, so a canceled
		# press can never leave the right-owned guard stuck.
		if mb.canceled:
			if _guard_source == GuardSource.RIGHT_MOUSE:
				_release_guard(GuardSource.RIGHT_MOUSE)
				get_viewport().set_input_as_handled()
			return
		if mb.pressed:
			# Ordinary RMB guards anywhere in gameplay (world center, captured
			# mouse), not only inside our controls.
			get_viewport().set_input_as_handled()
			# Guard acts immediately; another owner never steals it.
			if _guard_source == GuardSource.NONE and _gating_ok():
				if is_instance_valid(_controller) and _controller.has_method("set_guard"):
					if bool(_controller.set_guard(true)):
						_guard_source = GuardSource.RIGHT_MOUSE
						_guard_owner_finger = -1
						_update_guard_visual()
			return
		# Release: clear the right-owned guard unconditionally, even outside
		# our controls or window controls, so a drag-out can never stick.
		if _guard_source == GuardSource.RIGHT_MOUSE:
			_release_guard(GuardSource.RIGHT_MOUSE)
			get_viewport().set_input_as_handled()
		return

	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var inside := _inside_own_control(mb.position)

	if mb.pressed:
		if not inside:
			return
		get_viewport().set_input_as_handled()
		if _inside_button(_guard_btn, mb.position):
			# Guard acts immediately; another owner never steals it.
			if _guard_source == GuardSource.NONE and _gating_ok():
				if is_instance_valid(_controller) and _controller.has_method("set_guard"):
					if bool(_controller.set_guard(true)):
						_guard_source = GuardSource.MOUSE
						_guard_owner_finger = -1
						_update_guard_visual()
			return
		# Independent action buttons work even while another owner holds guard.
		var btn_id := _action_button_at(mb.position)
		if btn_id != 0:
			_pointer_buttons[MOUSE_POINTER_ID] = btn_id
		return

	# Release: always clear the tracked mouse action, even outside our controls.
	if _pointer_buttons.has(MOUSE_POINTER_ID):
		var btn_id: int = _pointer_buttons[MOUSE_POINTER_ID]
		_pointer_buttons.erase(MOUSE_POINTER_ID)
		get_viewport().set_input_as_handled()
		if mb.canceled or btn_id <= 0:
			return
		# Tap release must be inside the same original button.
		if inside and _inside_button(_button_for_id(btn_id), mb.position):
			if btn_id == SWING:
				_request_swing()
			else:
				_request_reset()
		return

	# Owned guard release is unconditional on leftUP/canceled, even outside
	# our controls, so a drag-out can never leave the guard stuck.
	if _guard_source == GuardSource.MOUSE:
		_release_guard(GuardSource.MOUSE)
		get_viewport().set_input_as_handled()
		return

	if not inside:
		return
	get_viewport().set_input_as_handled()


func _handle_screen_touch(st: InputEventScreenTouch) -> void:
	var finger := st.index
	var inside := _inside_own_control(st.position)

	if st.pressed and not st.canceled:
		if not inside:
			return  # world movement/camera touch: pass through
		get_viewport().set_input_as_handled()
		if _inside_button(_guard_btn, st.position):
			# Guard acts immediately; a second finger never steals it.
			if _guard_source == GuardSource.NONE and _gating_ok():
				if is_instance_valid(_controller) and _controller.has_method("set_guard"):
					if bool(_controller.set_guard(true)):
						_guard_source = GuardSource.TOUCH
						_guard_owner_finger = finger
						_update_guard_visual()
			return
		if _guard_source == GuardSource.TOUCH and finger == _guard_owner_finger:
			return
		var btn_id := _action_button_at(st.position)
		if btn_id != 0 and not _pointer_buttons.has(finger):
			_pointer_buttons[finger] = btn_id
		elif btn_id == 0 and not _pointer_buttons.has(finger):
			# Extra finger inside our control but on no button: track it as
			# ignored so its drag/up never feed the camera.
			_pointer_buttons[finger] = 0
		return

	if st.canceled:
		# Canceled touch must cancel even if pressed=true.
		if _guard_source == GuardSource.TOUCH and finger == _guard_owner_finger:
			_release_guard(GuardSource.TOUCH, finger)
			get_viewport().set_input_as_handled()
		elif _pointer_buttons.has(finger):
			_pointer_buttons.erase(finger)
			get_viewport().set_input_as_handled()
		return

	# Release (pressed=false, not canceled).
	if _guard_source == GuardSource.TOUCH and finger == _guard_owner_finger:
		_release_guard(GuardSource.TOUCH, finger)
		get_viewport().set_input_as_handled()
		return
	if _pointer_buttons.has(finger):
		var btn_id: int = _pointer_buttons[finger]
		_pointer_buttons.erase(finger)
		get_viewport().set_input_as_handled()
		if btn_id <= 0:
			return
		# Tap release must be inside the same original button.
		if inside and _inside_button(_button_for_id(btn_id), st.position):
			if btn_id == SWING:
				_request_swing()
			else:
				_request_reset()


func _handle_screen_drag(sd: InputEventScreenDrag) -> void:
	var finger := sd.index
	if _guard_source == GuardSource.TOUCH and finger == _guard_owner_finger:
		# Drag outside the guard button cancels the guard immediately, even if
		# the finger is still inside another owned control. Ownership is kept
		# until release so other fingers don't inherit the gesture.
		if not _inside_button(_guard_btn, sd.position):
			_release_guard(GuardSource.TOUCH, finger)
		get_viewport().set_input_as_handled()
		return
	if _pointer_buttons.has(finger):
		# Drag outside the original action button invalidates the tap but
		# keeps ownership until release so the camera doesn't inherit it.
		var btn_id: int = _pointer_buttons[finger]
		if btn_id != 0 and not _inside_button(_button_for_id(btn_id), sd.position):
			_pointer_buttons[finger] = -1
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

func _inside_own_control(pos: Vector2) -> bool:
	for b in [_swing_btn, _reset_btn, _guard_btn]:
		if b != null and b.get_global_rect().has_point(pos):
			return true
	return false


func _inside_button(b: Control, pos: Vector2) -> bool:
	return b != null and b.get_global_rect().has_point(pos)


func _action_button_at(pos: Vector2) -> int:
	if _inside_button(_swing_btn, pos):
		return SWING
	if _inside_button(_reset_btn, pos):
		return RESET
	return 0


func _button_for_id(btn_id: int) -> Control:
	if btn_id == SWING:
		return _swing_btn
	if btn_id == RESET:
		return _reset_btn
	return null


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func _clear_all_input() -> void:
	_pointer_buttons.clear()
	if _guard_source != GuardSource.NONE:
		_guard_source = GuardSource.NONE
		_guard_owner_finger = -1
		if is_instance_valid(_controller) and _controller.has_method("set_guard"):
			_controller.set_guard(false)
	_update_guard_visual()


func _update_hint() -> void:
	if not _hint_label:
		return
	var base_key := "DEFENSE_HINT_PC" if not OS.has_feature("android") else "DEFENSE_HINT_TOUCH"
	var text := Localization.text(base_key)
	if _is_novice():
		text += "\n" + Localization.text("DEFENSE_NOVICE_HINT")
	else:
		text += "\n" + Localization.text("DEFENSE_TRAINED_HINT")
	_hint_label.text = text


# ---------------------------------------------------------------------------
# Per-frame sync
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _root == null or not is_inside_tree():
		return
	var gating_ok := _gating_ok()
	_root.visible = gating_ok

	# While disabled (menu open, paused, no focus, attack blocked) clear ALL
	# pending input and guard state every frame so a tap that started before
	# the menu opened can never fire on release. Focus/pause flags are kept.
	if not gating_ok:
		_clear_all_input()
		return

	# If the controller canceled the guard, clear owner/pending touches;
	# never renew while old input is held.
	if _guard_source != GuardSource.NONE and not _guard_is_active():
		_guard_source = GuardSource.NONE
		_guard_owner_finger = -1
		_pointer_buttons.clear()

	_update_guard_visual()

	# Keep hint fresh on technique change without queued actions.
	var novice := _is_novice()
	var had_meta := _hint_label.has_meta("novice")
	var stored: Variant = null if not had_meta else _hint_label.get_meta("novice")
	if not had_meta or stored != novice:
		_hint_label.set_meta("novice", novice)
		_update_hint()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_app_focus = false
			_clear_all_input()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_app_focus = true
		NOTIFICATION_APPLICATION_PAUSED:
			_app_paused = true
			_clear_all_input()
		NOTIFICATION_APPLICATION_RESUMED:
			_app_paused = false
		NOTIFICATION_PAUSED:
			_tree_paused = true
			_clear_all_input()
		NOTIFICATION_UNPAUSED:
			_tree_paused = false


func _exit_tree() -> void:
	# Clear all input first (guards against a freed controller), then drop the
	# reference so later calls cannot touch a freed instance.
	_clear_all_input()
	_controller = null
