extends CanvasLayer
## CourtyardInventoryMenu — модальное меню инвентаря двора (только чтение).
## Инстансируется последним как корневой дочерний узел InventoryMenu.

signal opened()
signal closed()

enum State { CLOSED, OPENING, OPEN }

const PANEL_SCENE: PackedScene = preload("res://scenes/courtyard/courtyard_inventory_panel.tscn")

@export var player_path: NodePath = ^"../Actors/Player"
@export var hud_path: NodePath = ^"../HUD"
@export var camera_path: NodePath = ^"../CameraRig"
@export var access_path: NodePath = ^"../Actors/Player/PocketAccess"

var state: int = State.CLOSED

# --- Ссылки (тип Node, резолвятся защитно) ---
var _player: Node = null
var _hud: Node = null
var _camera: Node = null
var _access: Node = null

# --- UI ---
var _root_control: Control = null
var _overlay: Control = null
var _window: Node = null
var _open_button: BaseButton = null

# --- Снимок состояния до открытия (восстанавливается при закрытии) ---
var _saved_player_input_enabled: bool = false
var _saved_camera_input_enabled: bool = false
var _saved_hud_visible: bool = false
var _saved_hud_processing_input: bool = false
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

# --- Активный доступ (для проверки тождественности) ---
var _active_access: Node = null
var _active_storage_id: StringName = &""

# --- Go-back ownership (Android) ---
var _go_back_owned: bool = false
var _original_quit_on_go_back: bool = true

# Защита от повторной доставки одного Back-события в пределах кадра/события:
# Android может доставить один KEYCODE_BACK и как ui_cancel (InputEventKey),
# и как NOTIFICATION_WM_GO_BACK_REQUEST. Первый обработчик закрывает меню,
# второй (в том же кадре) видит CLOSED и вызывает quit(). Хранится номер
# обработанного кадра: следующий кадр имеет другой номер, поэтому отдельное
# следующее нажатие Back работает как раньше.
var _go_back_handled_frame: int = -1

# Защита от МЕЖКАДРОВОГО дубля (Samsung S23): один физический KEYCODE_BACK
# может быть доставлен как ДВЕ отдельные NOTIFICATION_WM_GO_BACK_REQUEST
# с разницей ~7 мс на СОСЕДНИХ кадрах. Кадровая защита выше их не ловит:
# первый запрос закрывает меню (OPEN -> CLOSED), второй приходит в следующем
# кадре, видит CLOSED и вызывает quit() — приложение закрывается от одного
# нажатия Back. Поэтому фиксируем момент закрытия по Back/ui_cancel и
# игнорируем повторный GO_BACK_REQUEST в состоянии CLOSED в пределах
# ограниченного grace-окна (250 мс) после такого закрытия. Реальное
# нажатие Back позже окна обрабатывается как раньше (quit по политике).
const GO_BACK_GRACE_MSEC: int = 250
var _go_back_grace_deadline_ms: int = -1

# --- Touch-обработка OpenButton ---
var _open_button_touch_index: int = -1
var _open_button_pressed: bool = false
var _open_button_dragged_out: bool = false


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_hud = get_node_or_null(hud_path)
	_camera = get_node_or_null(camera_path)
	_access = get_node_or_null(access_path)

	_root_control = $RootControl
	_overlay = $RootControl/Overlay
	_window = _overlay.get_node("Window") if _overlay else null
	_open_button = $RootControl/OpenButton

	if _open_button:
		_open_button.pressed.connect(_on_open_button_pressed)
		_update_open_button_text()

	# Window: закрытие по крестику окна.
	if _window and is_instance_valid(_window) and _window.has_signal("close_requested"):
		_window.connect("close_requested", _on_window_close_requested)

	# Власть над SceneTree.quit_on_go_back, пока сцена существует.
	_go_back_owned = true
	_original_quit_on_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false

	# Локализация: подписываемся на смену языка, если доступен менеджер.
	var localization := _get_localization()
	if localization and localization.has_signal("language_changed"):
		localization.connect("language_changed", _on_language_changed)


func _exit_tree() -> void:
	# Безопасное закрытие и восстановление владения SceneTree Back.
	close_menu(false)
	if _go_back_owned:
		get_tree().quit_on_go_back = _original_quit_on_go_back
		_go_back_owned = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			# Потеря фокуса/пауза: закрыть без восстановления захвата курсора.
			if state != State.CLOSED:
				close_menu(false)
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_handle_go_back()


# ---------------------------------------------------------------------------
# Публичный API
# ---------------------------------------------------------------------------

func get_menu_state() -> int:
	return state


func request_open() -> bool:
	if state != State.CLOSED:
		return false
	if _player == null or not is_instance_valid(_player):
		return false
	if not _bool_prop(_player, "input_enabled"):
		return false
	if _player.has_method("is_attacking") and _player.is_attacking():
		return false
	if _hud != null and is_instance_valid(_hud) and _dialogue_visible():
		return false
	var access := get_node_or_null(access_path)
	if access == null or not access.has_method("has_access") or not access.has_access():
		return false

	# Сохраняем состояние до открытия.
	_saved_player_input_enabled = _bool_prop(_player, "input_enabled")
	_saved_camera_input_enabled = _bool_prop(_camera, "input_enabled") if _camera else true
	_saved_hud_visible = _hud.visible if _hud else false
	_saved_hud_processing_input = _hud.is_processing_input() if _hud and _hud.has_method("is_processing_input") else false
	_saved_mouse_mode = Input.mouse_mode

	_active_access = access
	_active_storage_id = access.get("storage_id") if "storage_id" in access else &""

	# Состояние OPENING ДО обратных вызовов.
	state = State.OPENING

	# HUD: сбросить управление, скрыть, отключить обработку ввода.
	if _hud and is_instance_valid(_hud):
		if _hud.has_method("reset_controls"):
			_hud.reset_controls()
		_hud.visible = false
		if _hud.has_method("set_process_input"):
			_hud.set_process_input(false)

	# Player: очистить движение (НЕ stop_input — сбрасывает кулдауны), отключить ввод.
	if is_instance_valid(_player):
		if _player.has_method("clear_movement_input"):
			_player.clear_movement_input()
	_set_bool_prop(_player, "input_enabled", false)

	# Camera: отпустить look и захват мыши, отключить ввод.
	if _camera and is_instance_valid(_camera):
		if _camera.has_method("stop_look"):
			_camera.stop_look()
	_set_bool_prop(_camera, "input_enabled", false)

	# Overlay видим, Window скрыт.
	if _overlay:
		_overlay.visible = true
	if _window and is_instance_valid(_window):
		_window.visible = false

	_update_open_button_visibility()

	# Запустить жест визуала; при неудаче — откат через close_menu.
	var visual := _get_visual()
	if visual == null or not visual.has_method("begin_inventory_access"):
		_rollback_open()
		return false

	# Подписываемся на завершение визуала ДО запуска жеста, чтобы не пропустить сигнал.
	_connect_visual_signal(visual)

	if not visual.begin_inventory_access():
		_rollback_open()
		return false

	return true


func close_menu(restore_capture: bool = true) -> void:
	if state == State.CLOSED:
		return
	var was_active := state != State.CLOSED
	state = State.CLOSED

	# Закрыть/скрыть Window и Overlay.
	if _window and is_instance_valid(_window):
		if _window.has_method("close_panel"):
			_window.close_panel()
		_window.visible = false
	if _overlay:
		_overlay.visible = false

	# Завершить жест визуала, если он валиден и в дереве.
	var visual := _get_visual()
	if visual and is_instance_valid(visual) and visual.is_inside_tree():
		if visual.has_method("end_inventory_access"):
			visual.end_inventory_access()

	# Сбросить управление HUD и очистить движение Player, затем восстановить флаги.
	if _hud and is_instance_valid(_hud):
		if _hud.has_method("reset_controls"):
			_hud.reset_controls()
	if _player and is_instance_valid(_player):
		if _player.has_method("clear_movement_input"):
			_player.clear_movement_input()
	_set_bool_prop(_player, "input_enabled", _saved_player_input_enabled)
	_set_bool_prop(_camera, "input_enabled", _saved_camera_input_enabled)
	if _hud and is_instance_valid(_hud):
		_hud.visible = _saved_hud_visible
		if _hud.has_method("set_process_input"):
			_hud.set_process_input(_saved_hud_processing_input)

	# Курсор: false — вернуть захват как был; true — снять захват (видимый курсор).
	if _camera and is_instance_valid(_camera) and _camera.has_method("set_mouse_capture"):
		var was_captured: bool = _saved_mouse_mode == Input.MOUSE_MODE_CAPTURED
		_camera.set_mouse_capture(was_captured and restore_capture)

	_active_access = null
	_active_storage_id = &""
	_clear_open_button_touch()

	_update_open_button_visibility()

	if was_active:
		closed.emit()


# ---------------------------------------------------------------------------
# Ввод
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Подавляем ТОЛЬКО эмулированные мышь/движение мыши над видимым OpenButton,
	# чтобы не было двойного переключения (сырое касание + эмуляция мыши).
	# Нативная мышь должна пройти в GUI (OpenButton.pressed).
	if _open_button and _open_button.visible and event.device == InputEvent.DEVICE_ID_EMULATION:
		var emulated := false
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			emulated = true
		if emulated and _open_button.get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			return

	# Ключ инвентаря (I / Tab в InputMap): CLOSED — открыть, OPENING/OPEN — закрыть.
	if event.is_action_pressed("inventory") and not event.is_echo():
		if state == State.CLOSED:
			request_open()
		else:
			close_menu(true)
		get_viewport().set_input_as_handled()
		return

	# Esc закрывает меню в любом активном состоянии (CLOSED не трогаем).
	if event.is_action_pressed("ui_cancel") and state != State.CLOSED:
		# Один Back может прийти и как ui_cancel, и как GO_BACK_REQUEST;
		# обрабатываем только первый канал в пределах кадра.
		if _go_back_handled_frame != Engine.get_process_frames():
			_go_back_handled_frame = Engine.get_process_frames()
			close_menu(true)
			# Закрытие по Back/ui_cancel: открываем grace-окно, чтобы
			# межкадровый дубль GO_BACK_REQUEST в CLOSED не вызвал quit().
			_go_back_grace_deadline_ms = Time.get_ticks_msec() + GO_BACK_GRACE_MSEC
		get_viewport().set_input_as_handled()
		return

	# Touch-обработка OpenButton (сырые касания, как в HUD).
	if _open_button and state != State.OPEN:
		_handle_open_button_touch(event)


func _handle_go_back() -> void:
	# Один Back может прийти и как ui_cancel, и как GO_BACK_REQUEST;
	# обрабатываем только первый канал в пределах кадра.
	if _go_back_handled_frame == Engine.get_process_frames():
		return
	_go_back_handled_frame = Engine.get_process_frames()
	if state != State.CLOSED:
		close_menu(false)
		# Закрытие по GO_BACK_REQUEST: открываем grace-окно против
		# межкадрового дубля (см. _go_back_grace_deadline_ms).
		_go_back_grace_deadline_ms = Time.get_ticks_msec() + GO_BACK_GRACE_MSEC
	elif Time.get_ticks_msec() < _go_back_grace_deadline_ms:
		# Межкадровый дубль того же Back, доставленный уже в CLOSED
		# (Samsung S23): подавляем, чтобы не выйти из приложения.
		return
	elif _original_quit_on_go_back:
		get_tree().quit()


# ---------------------------------------------------------------------------
# Touch-логика OpenButton
# ---------------------------------------------------------------------------

func _toggle_from_button() -> void:
	if state == State.OPENING:
		close_menu(true)
	elif state == State.CLOSED:
		request_open()


func _handle_open_button_touch(event: InputEvent) -> void:
	var rect := _open_button.get_global_rect()
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _open_button_touch_index == -1 and _open_button.visible and rect.has_point(touch.position):
			_open_button_touch_index = touch.index
			_open_button_pressed = true
			_open_button_dragged_out = false
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _open_button_touch_index:
			if _open_button_pressed and not _open_button_dragged_out and not touch.canceled and rect.has_point(touch.position):
				_toggle_from_button()
			_clear_open_button_touch()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _open_button_touch_index and _open_button_pressed:
			if not rect.grow(8.0).has_point(drag.position):
				_open_button_dragged_out = true
			get_viewport().set_input_as_handled()


func _clear_open_button_touch() -> void:
	_open_button_touch_index = -1
	_open_button_pressed = false
	_open_button_dragged_out = false


func _on_open_button_pressed() -> void:
	# Реальный клик мыши/клавиатуры по кнопке (эмуляция GUI).
	_toggle_from_button()


func _on_window_close_requested() -> void:
	close_menu(true)


# ---------------------------------------------------------------------------
# Визуал жеста
# ---------------------------------------------------------------------------

func _get_visual() -> Node:
	if _player and is_instance_valid(_player):
		var visual := _player.get_node_or_null("Visual")
		return visual
	return null


func _connect_visual_signal(visual: Node) -> void:
	if visual == null or not visual.has_signal("inventory_access_finished"):
		return
	if not visual.is_connected("inventory_access_finished", _on_inventory_access_finished):
		visual.connect("inventory_access_finished", _on_inventory_access_finished)


func _on_inventory_access_finished() -> void:
	if state != State.OPENING:
		return
	var access := get_node_or_null(access_path)
	if access == null or access != _active_access:
		close_menu(true)
		return
	if not access.has_method("has_access") or not access.has_access():
		close_menu(true)
		return
	var current_id: StringName = access.get("storage_id") if "storage_id" in access else &""
	if current_id != _active_storage_id:
		close_menu(true)
		return

	state = State.OPEN
	if _window and is_instance_valid(_window):
		if _window.has_method("open_panel"):
			_window.open_panel()
		_window.visible = true
	_update_open_button_visibility()
	opened.emit()


# ---------------------------------------------------------------------------
# Валидация доступа во время активного состояния
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if state == State.CLOSED:
		return
	var access := get_node_or_null(access_path)
	if access == null or access != _active_access:
		close_menu(true)
		return
	if not access.has_method("has_access") or not access.has_access():
		close_menu(true)
		return
	var current_id: StringName = access.get("storage_id") if "storage_id" in access else &""
	if current_id != _active_storage_id:
		close_menu(true)


# ---------------------------------------------------------------------------
# Локализация и UI-текст
# ---------------------------------------------------------------------------

func _get_localization() -> Node:
	var node := get_node_or_null(^"/root/Localization")
	if node:
		return node
	var root := get_tree().root
	for child in root.get_children():
		if child is Node and child.name == "Localization":
			return child
	return null


func _on_language_changed(_language: String) -> void:
	_update_open_button_text()


func _update_open_button_text() -> void:
	if not _open_button:
		return
	var key := "INV_OPEN_DESKTOP"
	if OS.get_name() == "Android" or (_hud and _bool_prop(_hud, "force_touch_controls")):
		key = "INV_OPEN"
	if state == State.OPENING:
		key = "UI_CLOSE"
	_open_button.text = _localize(key)


func _update_open_button_visibility() -> void:
	if not _open_button:
		return
	# Кнопка видна только когда меню не открыто (CLOSED/OPENING).
	_open_button.visible = state != State.OPEN
	_update_open_button_text()


func _localize(key: String, params: Dictionary = {}) -> String:
	var localization := _get_localization()
	if localization and localization.has_method("text"):
		return localization.text(key, params)
	return key


# ---------------------------------------------------------------------------
# Вспомогательные
# ---------------------------------------------------------------------------

func _dialogue_visible() -> bool:
	if not _hud or not is_instance_valid(_hud):
		return false
	var panel := _hud.get_node_or_null(^"RootControl/MessagePanel")
	if panel and panel is Control:
		return (panel as Control).visible
	return false


func _bool_prop(node: Node, prop: String) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if prop in node:
		var value: Variant = node.get(prop)
		return bool(value)
	return false


func _set_bool_prop(node: Node, prop: String, value: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	if prop in node:
		node.set(prop, value)


func _rollback_open() -> void:
	# Откат неудачного открытия: состояние ещё OPENING, close_menu восстановит
	# курсор/флаги/UI и очистит touch-состояние. Захваченных локов не остаётся.
	close_menu(true)
