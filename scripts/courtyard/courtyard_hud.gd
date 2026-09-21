class_name CourtyardHUD
extends CanvasLayer
## HUD первого играбельного сцены — Двор постоялого дома.
## Знает только о своих дочерних узлах. Уровень подключает сигналы.

signal move_changed(value: Vector2)
signal interact_pressed()
signal attack_pressed()
signal restart_pressed()
signal run_changed(enabled: bool)

const MIN_SIZE := Vector2(960, 540)
const ROOT_RES := Vector2(1920, 1080)

@export var force_touch_controls: bool = false

enum Dir { NONE, UP, DOWN, LEFT, RIGHT }

var _held_dir: int = Dir.NONE
var _attack_held := false
var _run_enabled := false
var _touch_move_index := -1
var _touch_attack_index := -1
var _touch_run_index := -1
var _suppress_mouse_until_ms := 0
var _message_visible := true

# --- Ссылки на дочерние узлы (заполняются в _ready) ---
var _root: Control
var _objective_label: Label
var _subtitle_label: Label
var _legend_label: Label
var _prompt_label: Label
var _speaker_label: Label
var _message_text: Label
var _message_panel: PanelContainer
var _dpad_up: Button
var _dpad_down: Button
var _dpad_left: Button
var _dpad_right: Button
var _btn_interact: Button
var _btn_attack: Button
var _btn_run: Button
var _btn_restart: Button

# Отслеживаемые тач-индексы (движение, удар, интеракт, рестарт, сообщение).
var _tracked_touches: Array[int] = []

# Ключи/параметры локализуемых элементов — для обновления при language_changed.
var _objective_key := ""
var _objective_params: Dictionary = {}
var _speaker_key := ""
var _message_key := ""
var _message_params: Dictionary = {}


func _ready() -> void:
	_root = $RootControl
	_objective_label = $RootControl/TopLeftPanel/VBox/ObjectiveLabel
	_subtitle_label = $RootControl/TopLeftPanel/VBox/SubtitleLabel
	_legend_label = $RootControl/BottomLeft/LegendLabel
	_prompt_label = $RootControl/PromptLabel
	_speaker_label = $RootControl/MessagePanel/VBox/SpeakerLabel
	_message_text = $RootControl/MessagePanel/VBox/MessageText
	_message_panel = $RootControl/MessagePanel
	_dpad_up = $RootControl/BottomLeft/DpadGrid/Up
	_dpad_down = $RootControl/BottomLeft/DpadGrid/Down
	_dpad_left = $RootControl/BottomLeft/DpadGrid/Left
	_dpad_right = $RootControl/BottomLeft/DpadGrid/Right
	_btn_interact = $RootControl/BottomRight/VBox/InteractButton
	_btn_attack = $RootControl/BottomRight/VBox/AttackButton
	_btn_run = $RootControl/BottomRight/VBox/RunButton
	_btn_restart = $RootControl/TopRightPanel/RestartButton

	# Текст, который получает из Localization, не должен повторно
	# автопереводиться (иначе ключ превратится в «перевод» самого себя).
	for n in [_objective_label, _subtitle_label, _legend_label, _prompt_label,
			_speaker_label, _message_text,
			_btn_interact, _btn_attack, _btn_run, _btn_restart]:
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	_refresh_localized_texts()

	_set_run_mode(false, false)

	var touch_mode := OS.has_feature("android") or force_touch_controls
	$RootControl/BottomLeft/DpadGrid.visible = touch_mode
	$RootControl/BottomRight.visible = touch_mode
	if touch_mode:
		_legend_label.size = Vector2(900, 60)
		_legend_label.position = Vector2(_legend_label.position.x, _legend_label.position.y - 68)
	else:
		_legend_label.size = Vector2(1100, 64)
		_legend_label.position = Vector2(0, 320)

	_apply_styles()

	# Кнопки: мышь (ПК) — button_down/button_up, тач обрабатывается в _input.
	for b in _all_buttons():
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.button_down.connect(_on_button_down.bind(b))
		b.button_up.connect(_on_button_up.bind(b))

	_message_panel.gui_input.connect(_on_message_gui_input)

	set_objective("COURTYARD_OBJECTIVE_MEET_HOST")
	clear_message()

	# Язык мог установиться до _ready — обновим отображение, не трогая
	# видимость/ввод. Сигнал может прийти и раньше ready: обработчик
	# сам проверяет is_node_ready().
	Localization.language_changed.connect(_on_language_changed)


func _all_buttons() -> Array[Button]:
	return [_dpad_up, _dpad_down, _dpad_left, _dpad_right, _btn_interact, _btn_attack, _btn_run, _btn_restart]


func _apply_styles() -> void:
	var charcoal := Color(0.13, 0.14, 0.16, 0.92)
	var gold := Color(0.72, 0.58, 0.32)
	var body := Color(0.93, 0.90, 0.84)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = charcoal
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = gold
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_bottom = 10.0

	for p in [$RootControl/TopLeftPanel, $RootControl/MessagePanel]:
		p.add_theme_stylebox_override("panel", panel_style)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.17, 0.18, 0.21, 0.95)
	btn_style.border_width_left = 1
	btn_style.border_width_top = 1
	btn_style.border_width_right = 1
	btn_style.border_width_bottom = 1
	btn_style.border_color = gold
	btn_style.set_corner_radius_all(8)
	btn_style.content_margin_left = 12.0
	btn_style.content_margin_top = 8.0
	btn_style.content_margin_right = 12.0
	btn_style.content_margin_bottom = 8.0

	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = Color(0.22, 0.23, 0.27, 0.95)

	var btn_pressed := btn_style.duplicate()
	btn_pressed.bg_color = Color(0.28, 0.26, 0.22, 1.0)

	for b in _all_buttons():
		b.add_theme_stylebox_override("normal", btn_style)
		b.add_theme_stylebox_override("hover", btn_hover)
		b.add_theme_stylebox_override("pressed", btn_pressed)
		b.add_theme_color_override("font_color", body)
		b.add_theme_color_override("font_hover_color", body)
		b.add_theme_color_override("font_pressed_color", body)
		b.add_theme_font_size_override("font_size", 30)

	# Заголовок: приглушённое золото, разрядка букв.
	var title := $RootControl/TopLeftPanel/VBox/TitleLabel
	title.add_theme_color_override("font_color", gold)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_constant_override("line_spacing", 4)

	var subtitle := $RootControl/TopLeftPanel/VBox/SubtitleLabel
	subtitle.add_theme_color_override("font_color", body)
	subtitle.add_theme_font_size_override("font_size", 28)

	_objective_label.add_theme_color_override("font_color", body)
	_objective_label.add_theme_font_size_override("font_size", 30)

	_prompt_label.add_theme_color_override("font_color", gold)
	_prompt_label.add_theme_font_size_override("font_size", 32)

	_speaker_label.add_theme_color_override("font_color", gold)
	_speaker_label.add_theme_font_size_override("font_size", 28)
	_message_text.add_theme_color_override("font_color", body)
	_message_text.add_theme_font_size_override("font_size", 30)


# ---------------------------------------------------------------- Публичный API

func set_objective(key: String, parameters: Dictionary = {}) -> void:
	_objective_key = key
	_objective_params = _deep_copy_dict(parameters)
	if _objective_label:
		_objective_label.text = Localization.text(key, _objective_params)


func set_prompt(text: String) -> void:
	if _prompt_label:
		_prompt_label.text = text
		_prompt_label.visible = not text.is_empty()


func show_message(speaker_key: String, key: String, parameters: Dictionary = {}) -> void:
	if not _message_panel:
		return
	_speaker_key = speaker_key
	_message_key = key
	_message_params = _deep_copy_dict(parameters)
	_speaker_label.text = Localization.text(speaker_key) if not speaker_key.is_empty() else ""
	_message_text.text = Localization.text(key, _message_params)
	_message_visible = true
	_message_panel.visible = true


func clear_message() -> void:
	_message_visible = false
	if _message_panel:
		_message_panel.visible = false


func reset_controls() -> void:
	_held_dir = Dir.NONE
	_attack_held = false
	_touch_move_index = -1
	_touch_attack_index = -1
	_touch_run_index = -1
	_tracked_touches.clear()
	# Рестарт синхронно очищает трек-состояние — не даём тачу рестарта
	# породить дублирующий эмулированный клик мышью.
	_suppress_mouse_until_ms = Time.get_ticks_msec() + 350
	if not is_node_ready():
		return
	_set_dpad_pressed(false)
	if _btn_attack:
		_btn_attack.button_pressed = false
	_set_run_mode(false, true)
	_emit_move()


# ---------------------------------------------------------------- Локализация

func _on_language_changed(_language: String) -> void:
	# Язык может установиться раньше _ready — тогда просто ничего не делаем.
	if not is_node_ready():
		return
	_refresh_localized_texts()


func _refresh_localized_texts() -> void:
	if _objective_label:
		_objective_label.text = Localization.text(_objective_key, _objective_params)
	if _subtitle_label:
		_subtitle_label.text = Localization.text("COURTYARD_TITLE")
	if _legend_label:
		var legend_touch := OS.has_feature("android") or force_touch_controls
		_legend_label.text = Localization.text(
			"COURTYARD_LEGEND_TOUCH" if legend_touch else "COURTYARD_LEGEND_DESKTOP")
	if _btn_interact:
		_btn_interact.text = Localization.text("UI_ACTION_INTERACT")
	if _btn_attack:
		_btn_attack.text = Localization.text("UI_ACTION_ATTACK")
	if _btn_restart:
		_btn_restart.text = Localization.text("UI_RESTART")
	if _btn_run:
		_btn_run.text = Localization.text("UI_ACTION_RUN" if _run_enabled else "UI_ACTION_WALK")
	if _speaker_label:
		_speaker_label.text = Localization.text(_speaker_key) if not _speaker_key.is_empty() else ""
	# Обновляем текст открытого сообщения; закрытое не открываем.
	if _message_visible and _message_text:
		_message_text.text = Localization.text(_message_key, _message_params)


func _deep_copy_dict(d: Dictionary) -> Dictionary:
	return d.duplicate(true)


# ---------------------------------------------------------------- Ввод

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		reset_controls()


func _input(event: InputEvent) -> void:
	# Закрытие диалога: interact или Escape (не эмуляция), либо реальный
	# левый клик мыши при захваченном курсоре.
	if _message_visible and _message_panel.is_visible_in_tree():
		if event is InputEventKey:
			var k := event as InputEventKey
			if k.pressed and not k.echo:
				var closes := k.is_action_pressed("interact") or k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE
				if closes:
					clear_message()
					get_viewport().set_input_as_handled()
					return
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.device != InputEvent.DEVICE_ID_EMULATION and mb.pressed \
					and mb.button_index == MOUSE_BUTTON_LEFT \
					and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				clear_message()
				get_viewport().set_input_as_handled()
				return
	# S23: эмулированные мышиные события (device=-1) дублируют тачи.
	# Если точка попадает в собственную кнопку HUD, глотаем и press, и release,
	# чтобы GUI button_down не переключал состояние раньше/позже тача.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.device == InputEvent.DEVICE_ID_EMULATION and _point_in_owned_control(_to_root_position(mb.position)):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var pos := _to_root_position(t.position)
		# Определяем попадание ДО диспетчеризации: reset_controls (рестарт)
		# синхронно очищает трек-состояние, поэтому was_tracked после
		# обработки мог бы потерять обработанный press.
		var was_tracked := _is_tracked(t.index)
		if t.pressed:
			was_tracked = was_tracked or _point_in_owned_control(pos)
			_on_touch_down(pos, t.index)
		else:
			_on_touch_up(t.index)
		# Блокируем проброс только собственных тачей (press и release).
		if was_tracked:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_move_index:
			_update_move_from_point(_to_root_position(d.position))
		elif d.index == _touch_attack_index:
			# Палец удара ушёл за пределы — считаем отпусканием.
			if not _point_in_attack(_to_root_position(d.position)):
				_release_attack()
		if _is_tracked(d.index):
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Клавиатура остаётся в общем потоке; здесь только защита от дублей мыши.
	pass


# ---------------------------------------------------------------- Тач-логика

func _to_root_position(local_pos: Vector2) -> Vector2:
	# event.position уже в логическом viewport (1920x1080 при stretch).
	return local_pos


func _is_tracked(index: int) -> bool:
	return index == _touch_move_index or index == _touch_attack_index \
		or index == _touch_run_index or _tracked_touches.has(index)


func _track(index: int) -> void:
	if not _tracked_touches.has(index):
		_tracked_touches.append(index)
	_suppress_mouse_until_ms = Time.get_ticks_msec() + 350


func _untrack(index: int) -> void:
	_tracked_touches.erase(index)
	_suppress_mouse_until_ms = Time.get_ticks_msec() + 350


func _point_in_dpad(p: Vector2) -> int:
	if _dpad_up.is_visible_in_tree() and _dpad_up.get_global_rect().has_point(p):
		return Dir.UP
	if _dpad_down.is_visible_in_tree() and _dpad_down.get_global_rect().has_point(p):
		return Dir.DOWN
	if _dpad_left.is_visible_in_tree() and _dpad_left.get_global_rect().has_point(p):
		return Dir.LEFT
	if _dpad_right.is_visible_in_tree() and _dpad_right.get_global_rect().has_point(p):
		return Dir.RIGHT
	return Dir.NONE


func _point_in_attack(p: Vector2) -> bool:
	return _btn_attack.is_visible_in_tree() and _btn_attack.get_global_rect().has_point(p)


func _point_in_run(p: Vector2) -> bool:
	return _btn_run.is_visible_in_tree() and _btn_run.get_global_rect().has_point(p)


func _point_in_owned_control(p: Vector2) -> bool:
	# Попадает ли точка в любую собственную кнопку или видимую панель
	# сообщения — до диспетчеризации тача (см. _input).
	if not is_node_ready():
		return false
	for b in _all_buttons():
		if b and b.is_visible_in_tree() and b.get_global_rect().has_point(p):
			return true
	if _message_visible and _message_panel and _message_panel.get_global_rect().has_point(p):
		return true
	return false


func _on_touch_down(pos: Vector2, index: int) -> void:
	var dir := _point_in_dpad(pos)
	if dir != Dir.NONE and _touch_move_index == -1:
		_touch_move_index = index
		_track(index)
		_held_dir = dir
		_set_dpad_pressed(true, dir)
		_emit_move()
		return
	if _point_in_attack(pos) and _touch_attack_index == -1:
		_touch_attack_index = index
		_track(index)
		_attack_held = true
		_btn_attack.button_pressed = true
		attack_pressed.emit()
		return
	if _point_in_run(pos) and _touch_run_index == -1:
		# Кнопка владеет своим тачем: камера не вращается от неё,
		# а режим переключается ровно один раз на press.
		_touch_run_index = index
		_track(index)
		_toggle_run_mode()
		return
	if _btn_interact.is_visible_in_tree() and _btn_interact.get_global_rect().has_point(pos):
		_track(index)
		if _message_visible:
			clear_message()
		else:
			interact_pressed.emit()
		return
	if _btn_restart.is_visible_in_tree() and _btn_restart.get_global_rect().has_point(pos):
		_track(index)
		restart_pressed.emit()
		return
	if _message_visible and _message_panel.get_global_rect().has_point(pos):
		_track(index)
		clear_message()


func _on_touch_up(index: int) -> void:
	if index == _touch_move_index:
		_touch_move_index = -1
		_held_dir = Dir.NONE
		_set_dpad_pressed(false)
		_emit_move()
	elif index == _touch_attack_index:
		_release_attack()
	elif index == _touch_run_index:
		# Отпускание только снимает владение тачем — режим не отключается.
		_touch_run_index = -1
	_untrack(index)


func _release_attack() -> void:
	_touch_attack_index = -1
	_attack_held = false
	_btn_attack.button_pressed = false


func _update_move_from_point(p: Vector2) -> void:
	var dir := _point_in_dpad(p)
	if dir == Dir.NONE:
		dir = _nearest_dpad_dir(p)
	if dir != _held_dir:
		_held_dir = dir
		_set_dpad_pressed(dir != Dir.NONE, dir)
		_emit_move()


func _nearest_dpad_dir(p: Vector2) -> int:
	var best := -1.0
	var result := Dir.NONE
	for b in _all_buttons():
		if b == _btn_interact or b == _btn_attack or b == _btn_run or b == _btn_restart:
			continue
		if not b.is_visible_in_tree():
			continue
		var r := b.get_global_rect()
		if r.grow(40).has_point(p):
			var d := (r.get_center() - p).length()
			if best < 0.0 or d < best:
				best = d
				result = _dir_of_button(b)
	return result


func _dir_of_button(b: Button) -> int:
	if b == _dpad_up:
		return Dir.UP
	if b == _dpad_down:
		return Dir.DOWN
	if b == _dpad_left:
		return Dir.LEFT
	if b == _dpad_right:
		return Dir.RIGHT
	return Dir.NONE


func _set_dpad_pressed(pressed: bool, dir: int = -1) -> void:
	for b in _all_buttons():
		if b == _btn_interact or b == _btn_attack or b == _btn_run or b == _btn_restart:
			continue
		b.button_pressed = pressed and (dir == -1 or _dir_of_button(b) == dir)


func _emit_move() -> void:
	var v := Vector2.ZERO
	match _held_dir:
		Dir.UP:
			v = Vector2(0, -1)
		Dir.DOWN:
			v = Vector2(0, 1)
		Dir.LEFT:
			v = Vector2(-1, 0)
		Dir.RIGHT:
			v = Vector2(1, 0)
	move_changed.emit(v)


# ---------------------------------------------------------------- Кнопки (мышь/ПК)

func _on_button_down(b: Button) -> void:
	if Time.get_ticks_msec() < _suppress_mouse_until_ms:
		return
	match b:
		_dpad_up, _dpad_down, _dpad_left, _dpad_right:
			var dir := _dir_of_button(b)
			_held_dir = dir
			_set_dpad_pressed(true, dir)
			_emit_move()
		_btn_interact:
			interact_pressed.emit()
		_btn_attack:
			attack_pressed.emit()
		_btn_run:
			# Единственная точка переключения режима: эмулированные
			# мышиные события не должны переключать его второй раз.
			if _touch_run_index == -1:
				_toggle_run_mode()
		_btn_restart:
			restart_pressed.emit()


func _on_button_up(b: Button) -> void:
	# Эмулированный mouse release от второго пальца не должен сбивать
	# движение, удерживаемое первым (и наоборот).
	if Time.get_ticks_msec() < _suppress_mouse_until_ms or _touch_move_index != -1:
		return
	if b == _dpad_up or b == _dpad_down or b == _dpad_left or b == _dpad_right:
		if _held_dir == _dir_of_button(b):
			_held_dir = Dir.NONE
			_set_dpad_pressed(false)
			_emit_move()


# ---------------------------------------------------------------- Режим бега

func _toggle_run_mode() -> void:
	_set_run_mode(not _run_enabled, true)


func _set_run_mode(enabled: bool, emit_change: bool) -> void:
	if _run_enabled == enabled and not emit_change:
		return
	_run_enabled = enabled
	if is_node_ready() and _btn_run:
		_btn_run.text = Localization.text("UI_ACTION_RUN" if enabled else "UI_ACTION_WALK")
		_btn_run.button_pressed = enabled
	if emit_change:
		run_changed.emit(enabled)


func _on_message_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if _message_visible:
			clear_message()
