extends "res://scripts/tools/corner_enemy_toolbar.gd"
## Combat-dodge тулбар: наследует guard/блок/RMB/G/reset, добавляет кнопку Dodge.


var _dodge_btn: Button = null
# Владельцы dodge-жестов: MOUSE_POINTER_ID или finger id -> true.
var _dodge_owners := {}

func _build_ui() -> void:
	super._build_ui()
	# Старый ResetTrialButton/DefenseTopRow скрыты: сброс теперь в панели «Тренировка».
	if is_instance_valid(_reset_btn):
		_reset_btn.hide()
	var top_row := _reset_btn.get_parent() as Control
	if top_row != null and top_row.name == "DefenseTopRow":
		top_row.hide()
	# Новый reset_requested из панели «Тренировка» -> существующий _request_reset.
	var tools: Node = _sandbox.get("_toolbar") if _sandbox != null else null
	if tools != null and tools.has_signal("reset_requested"):
		tools.reset_requested.connect(_request_reset)
	# Компактная геометрия подсказки: одна строка, высота <=54, ширина <=1100, прижата к верху safe root.
	if is_instance_valid(_hint_panel):
		_hint_panel.offset_left = -550.0
		_hint_panel.offset_right = 550.0
		_hint_panel.offset_top = 16.0
		_hint_panel.offset_bottom = 70.0
	if is_instance_valid(_hint_label):
		_hint_label.offset_left = -540.0
		_hint_label.offset_right = 540.0
		_hint_label.offset_top = 22.0
		_hint_label.offset_bottom = 64.0
	_dodge_btn = _make_button("DodgeButton", "DODGE_ACTION", Vector2(250, 110))
	# Копируем кэшированные стили HUD guard (disabled = normal).
	if _guard_normal_style != null:
		_dodge_btn.add_theme_stylebox_override("normal", _guard_normal_style)
		_dodge_btn.add_theme_stylebox_override("disabled", _guard_normal_style)
	if _guard_hover_style != null:
		_dodge_btn.add_theme_stylebox_override("hover", _guard_hover_style)
	if _guard_pressed_style != null:
		_dodge_btn.add_theme_stylebox_override("pressed", _guard_pressed_style)
	_root.add_child(_dodge_btn)
	_dodge_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dodge_btn.position = Vector2.ZERO
	_dodge_btn.offset_left = -610.0
	_dodge_btn.offset_right = -310.0
	_dodge_btn.offset_top = -455.0
	_dodge_btn.offset_bottom = -345.0


func _inside_own_control(pos: Vector2) -> bool:
	if super._inside_own_control(pos):
		return true
	return _inside_button(_dodge_btn, pos)


func _update_hint() -> void:
	if _hint_label == null:
		return
	var key := "COMBAT_HINT_IDLE"
	var phase: String = _snapshot().get("phase", "idle")
	var window_open := _block_window_open()
	if phase == "windup" or window_open:
		if _is_novice():
			key = "COMBAT_HINT_NOVICE"
		elif window_open:
			key = "COMBAT_HINT_CUE"
		else:
			key = "COMBAT_HINT_WINDUP"
	var text := Localization.text(key)
	if _hint_label.text != text:
		_hint_label.text = text


func _handle_key(key: InputEventKey) -> void:
	# Только физический SPACE (DOWN, без echo) вызывает dodge.
	if key.physical_keycode == KEY_SPACE:
		if key.pressed and not key.echo:
			if _gating_ok():
				_try_dodge()
		get_viewport().set_input_as_handled()
		return
	super._handle_key(key)


func _handle_real_mouse(mb: InputEventMouseButton) -> void:
	# Только LEFT относится к dodge; остальные кнопки — базовый поток.
	if mb.button_index != MOUSE_BUTTON_LEFT:
		super._handle_real_mouse(mb)
		return
	# Уже принятый dodge-DOWN: любые follow-up (UP/canceled) снимаем вне зависимости от позиции.
	if _dodge_owners.has(MOUSE_POINTER_ID):
		if mb.pressed and not mb.canceled:
			# Повторный DOWN не перезапускает действие.
			get_viewport().set_input_as_handled()
			return
		_dodge_owners.erase(MOUSE_POINTER_ID)
		get_viewport().set_input_as_handled()
		return
	# Guard-жест мыши — сначала super: guard владеет вводом отдельно от _pointer_buttons.
	if _guard_source == GuardSource.MOUSE or _pointer_buttons.has(MOUSE_POINTER_ID):
		super._handle_real_mouse(mb)
		return
	# Отменённый (canceled) press не запрашивает dodge.
	if mb.pressed and not mb.canceled and _inside_button(_dodge_btn, mb.position):
		var inside := _inside_own_control(mb.position)
		if not inside:
			return
		get_viewport().set_input_as_handled()
		# Фиксируем владение даже при отклонённом запросе, чтобы release не утекал.
		_dodge_owners[MOUSE_POINTER_ID] = true
		if _gating_ok():
			_try_dodge()
		return
	super._handle_real_mouse(mb)


func _handle_screen_touch(st: InputEventScreenTouch) -> void:
	var finger := st.index
	# Уже принятый dodge-DOWN: любые follow-up (UP/canceled) снимаем вне зависимости от позиции.
	if _dodge_owners.has(finger):
		if st.pressed and not st.canceled:
			# Повторный DOWN не перезапускает действие.
			get_viewport().set_input_as_handled()
			return
		_dodge_owners.erase(finger)
		get_viewport().set_input_as_handled()
		return
	# Guard-палец — сначала super (включая release над Dodge: guard снимается, не застревает).
	if (_guard_source == GuardSource.TOUCH and _guard_owner_finger == finger) or _pointer_buttons.has(finger):
		super._handle_screen_touch(st)
		return
	if st.pressed and not st.canceled and _inside_button(_dodge_btn, st.position):
		var inside := _inside_own_control(st.position)
		if not inside:
			return
		get_viewport().set_input_as_handled()
		# Фиксируем владение даже при отклонённом запросе, чтобы release не утекал.
		_dodge_owners[finger] = true
		if _gating_ok():
			_try_dodge()
		return
	super._handle_screen_touch(st)


func _handle_screen_drag(sd: InputEventScreenDrag) -> void:
	var finger := sd.index
	if _dodge_owners.has(finger):
		# Свой жест: глотаем, но не повторяем действие.
		get_viewport().set_input_as_handled()
		return
	super._handle_screen_drag(sd)


func _clear_all_input() -> void:
	_dodge_owners.clear()
	super._clear_all_input()


func _refresh_labels() -> void:
	super._refresh_labels()
	if is_instance_valid(_dodge_btn):
		_dodge_btn.text = Localization.text("DODGE_ACTION")


func _process(_delta: float) -> void:
	super._process(_delta)
	_update_hint()
	if _dodge_btn == null or not is_instance_valid(_dodge_btn):
		return
	var player := _level().get_node_or_null("Actors/Player") if _level() != null else null
	var busy := false
	if player != null and is_instance_valid(player):
		busy = player.is_dodging() or player.dodge_cooldown_remaining() > 0.0
	_dodge_btn.disabled = busy


func _try_dodge() -> void:
	var level := _level()
	if level == null:
		return
	var player := level.get_node_or_null("Actors/Player")
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("request_dodge"):
		return
	player.request_dodge()


func _level() -> Node:
	return _sandbox.get("level") if _sandbox != null else null


