extends Control
## First courtyard world quick-slot HUD bar (10 slots, single row 1..9,0).
## Created as InventoryMenu/RootControl/QuickBar. Call setup() AFTER add_child().

const CELL_SIZE := Vector2(140.0, 140.0)
const CELL_GAP := 6.0
const BOTTOM_MARGIN := 24.0
const BAR_RESERVE := 170.0
const MAX_BAR_WIDTH := 1454.0

var cells: Array[Button] = []
var _touch_index: int = -1
var _touch_slot: int = -1
var _mouse_slot: int = -1
var _touch_cancelled := false

var _menu: Node = null
var _panel: Node = null
var _hud: Node = null
var _player: Node = null

var _setup_done := false
var _hud_shifted := false
var _legend_shifted := false

# Gesture state (single action finger + ignored fingers)
var _ignored_fingers: Array[int] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_cells()
	if is_instance_valid(_panel) and _panel.has_signal("quick_slots_changed"):
		_panel.connect("quick_slots_changed", _on_quick_slots_changed)

func setup(menu: Node, panel: Node, hud: Node, player: Node) -> void:
	_menu = menu
	_panel = panel
	_hud = hud
	_player = player
	if is_instance_valid(_panel) and _panel.has_signal("quick_slots_changed"):
		_panel.connect("quick_slots_changed", _on_quick_slots_changed)
	_shift_hud()
	_setup_done = true
	refresh_slots()

func _shift_hud() -> void:
	var force_touch := OS.has_feature("android") or bool(_hud.force_touch_controls) if is_instance_valid(_hud) else false
	if not _hud_shifted and is_instance_valid(_hud):
		var message_panel: Node = _hud.get_node_or_null("RootControl/MessagePanel")
		if message_panel is Control:
			message_panel.position.y -= BAR_RESERVE
		if force_touch:
			var bottom_left: Node = _hud.get_node_or_null("RootControl/BottomLeft")
			var bottom_right: Node = _hud.get_node_or_null("RootControl/BottomRight")
			if bottom_left is Control:
				bottom_left.position.y -= BAR_RESERVE
			if bottom_right is Control:
				bottom_right.position.y -= BAR_RESERVE
		else:
			var bottom_left: Node = _hud.get_node_or_null("RootControl/BottomLeft")
			if bottom_left != null:
				var legend: Node = bottom_left.get_node_or_null("LegendLabel")
				if legend is Control:
					legend.position.y -= BAR_RESERVE
		_hud_shifted = true

func _build_cells() -> void:
	for i in range(10):
		var btn := Button.new()
		btn.name = "Cell%d" % i
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = false
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 86)
		btn.custom_minimum_size = Vector2.ZERO
		btn.size = CELL_SIZE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.tooltip_text = ""
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.13, 0.12, 0.11, 0.92)
		bg.border_width_left = 2
		bg.border_width_top = 2
		bg.border_width_right = 2
		bg.border_width_bottom = 2
		bg.border_color = Color(0.72, 0.55, 0.30)
		bg.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", bg.duplicate())
		btn.add_theme_stylebox_override("hover", bg.duplicate())
		btn.add_theme_stylebox_override("pressed", bg.duplicate())
		btn.add_theme_stylebox_override("disabled", bg.duplicate())
		var num := Label.new()
		num.name = "Num"
		num.text = str(i + 1) if i < 9 else "0"
		num.position = Vector2(6, 4)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		num.add_theme_font_size_override("font_size", 24)
		num.add_theme_color_override("font_color", Color(0.85, 0.78, 0.6))
		btn.add_child(num)
		var qty := Label.new()
		qty.name = "Qty"
		qty.text = ""
		qty.position = Vector2(CELL_SIZE.x - 34, CELL_SIZE.y - 30)
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qty.add_theme_font_size_override("font_size", 22)
		qty.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		btn.add_child(qty)
		add_child(btn)
		cells.append(btn)

func _process(_delta: float) -> void:
	if not _setup_done:
		return
	var desired := false
	if is_instance_valid(_menu) and is_instance_valid(_hud) and is_instance_valid(_player):
		desired = int(_menu.state) == 0 and bool(_hud.visible) and bool(_player.input_enabled) \
			and not bool(_player.is_attacking())
	if desired != visible:
		visible = desired
		if not desired:
			# Hiding cancels the intended action/visuals but retains claimed/ignored
			# finger indices until their own releases.
			_cancel_intended_action()
	_refresh_layout()


func _refresh_layout() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var viewport_size := vp.get_visible_rect().size
	var total_w := 10.0 * CELL_SIZE.x + 9.0 * CELL_GAP
	var cell_scale := 1.0
	var max_w := viewport_size.x - 48.0
	if total_w > max_w and total_w > 0.0:
		cell_scale = max_w / total_w
	var cell_w := CELL_SIZE.x * cell_scale
	var gap := CELL_GAP * cell_scale
	var bar_w := 10.0 * cell_w + 9.0 * gap
	var start_x := (viewport_size.x - bar_w) * 0.5
	var y := viewport_size.y - BOTTOM_MARGIN - CELL_SIZE.y * cell_scale
	if cells.size() == 10:
		for i in range(10):
			var btn: Button = cells[i]
			btn.size = Vector2(cell_w, CELL_SIZE.y * cell_scale)
			btn.position = Vector2(start_x + i * (cell_w + gap), y)
			var qty: Label = btn.get_node("Qty")
			qty.position = Vector2(cell_w - 34, CELL_SIZE.y * cell_scale - 30)

func refresh_slots() -> void:
	if not _setup_done or not is_instance_valid(_panel):
		return
	for i in range(10):
		var btn: Button = cells[i]
		var info: Dictionary = {}
		if _panel.has_method("get_quick_slot_info"):
			info = _panel.get_quick_slot_info(i)
		var qty_label: Label = btn.get_node("Qty")
		var available := bool(info.get("available", true)) if not info.is_empty() else false
		var equipped := bool(info.get("equipped", false))
		var border_color := Color(0.85, 0.7, 0.3) if equipped else Color(0.72, 0.55, 0.30)
		for style_name in ["normal", "hover", "pressed", "disabled"]:
			var sb: StyleBoxFlat = btn.get_theme_stylebox(style_name) as StyleBoxFlat
			if sb != null:
				sb.border_color = border_color
		if info.is_empty():
			btn.icon = null
			btn.tooltip_text = ""
			qty_label.text = ""
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5, 1.0)
		else:
			var icon_val: Variant = info.get("icon", null)
			btn.icon = icon_val as Texture2D
			btn.tooltip_text = str(info.get("name", ""))
			var q: int = int(info.get("quantity", 1))
			qty_label.text = str(q) if q > 1 else ""
			btn.disabled = not available
			btn.modulate = Color(0.5, 0.5, 0.5, 1.0) if not available else Color(1.0, 1.0, 1.0, 1.0)

func _on_quick_slots_changed() -> void:
	refresh_slots()

func _cancel_intended_action() -> void:
	# Cancel the intended action and visuals only; claimed/ignored finger indices
	# are retained until their own releases.
	_touch_cancelled = true
	_mouse_slot = -1
	for i in range(10):
		var btn: Button = cells[i]
		if btn.button_pressed:
			btn.set_pressed_no_signal(false)

func cancel_touch() -> void:
	_clear_gesture()

func _clear_gesture() -> void:
	_touch_index = -1
	_touch_slot = -1
	_touch_cancelled = false
	_mouse_slot = -1
	_ignored_fingers.clear()
	for i in range(10):
		var btn: Button = cells[i]
		if btn.button_pressed:
			btn.set_pressed_no_signal(false)


func _is_bar_active() -> bool:
	return visible and is_instance_valid(_menu) and int(_menu.state) == 0 \
		and is_instance_valid(_hud) and bool(_hud.visible) \
		and is_instance_valid(_player) and bool(_player.input_enabled) \
		and not bool(_player.is_attacking())


func _slot_at_local(local_pos: Vector2) -> int:
	for i in range(10):
		var btn: Button = cells[i]
		if btn.get_rect().has_point(local_pos):
			return i
	return -1

func _input(event: InputEvent) -> void:
	if not _setup_done:
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_screen_touch(ev: InputEventScreenTouch) -> void:
	var local := get_global_transform_with_canvas().affine_inverse() * ev.position
	var idx := _slot_at_local(local)
	if ev.pressed:
		# Claim the gesture even while attacking / slot unavailable (blocks camera).
		# A new press is only claimed when the bar is visible.
		if idx >= 0 and visible:
			if _touch_index == -1:
				_touch_index = int(ev.index)
				_touch_slot = idx
				_touch_cancelled = false
				cells[idx].set_pressed_no_signal(true)
			elif not _ignored_fingers.has(int(ev.index)):
				_ignored_fingers.append(int(ev.index))
			get_viewport().set_input_as_handled()
	else:
		var finger := int(ev.index)
		if finger == _touch_index:
			var slot := _touch_slot
			var was_cancelled := _touch_cancelled
			# Clear ONLY this primary state and visual before request_quick.
			_touch_index = -1
			_touch_slot = -1
			_touch_cancelled = false
			if slot >= 0:
				cells[slot].set_pressed_no_signal(false)
			if not ev.canceled and not was_cancelled and idx == slot \
					and _is_bar_active() and is_instance_valid(_menu):
				_menu.request_quick(slot)
			get_viewport().set_input_as_handled()
		elif _ignored_fingers.has(finger):
			_ignored_fingers.erase(finger)
			get_viewport().set_input_as_handled()


func _handle_screen_drag(ev: InputEventScreenDrag) -> void:
	var finger := int(ev.index)
	if finger == _touch_index:
		var local := get_global_transform_with_canvas().affine_inverse() * ev.position
		var idx := _slot_at_local(local)
		if not _touch_cancelled and idx != _touch_slot:
			# Dragged outside original cell: cancel permanently for this gesture,
			# but retain finger ownership until release.
			_touch_cancelled = true
			cells[_touch_slot].set_pressed_no_signal(false)
		get_viewport().set_input_as_handled()
	elif _ignored_fingers.has(finger):
		get_viewport().set_input_as_handled()


func _handle_mouse_button(ev: InputEventMouseButton) -> void:
	if ev.device == InputEvent.DEVICE_ID_EMULATION:
		# Emulated mouse (touch-driven): never invoke action. Consume only when
		# the event hits a VISIBLE cell or while any touch ownership exists.
		var local := get_global_transform_with_canvas().affine_inverse() * ev.position
		if (visible and _slot_at_local(local) >= 0) \
				or _touch_index != -1 or not _ignored_fingers.is_empty():
			get_viewport().set_input_as_handled()
		return
	var local := get_global_transform_with_canvas().affine_inverse() * ev.position
	var idx := _slot_at_local(local)
	if ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		# Only a real LMB press on a visible cell of the active bar establishes
		# the mouse origin.
		if idx >= 0 and visible and _is_bar_active() \
				and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_mouse_slot = idx
			cells[idx].set_pressed_no_signal(true)
		return
	if not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var slot := _mouse_slot
		_mouse_slot = -1
		if slot >= 0:
			cells[slot].set_pressed_no_signal(false)
		if slot >= 0 and not ev.canceled and idx == slot and visible \
				and _is_bar_active() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
				and is_instance_valid(_menu):
			_menu.request_quick(slot)
		# Consume the release if an origin existed or a visible cell was hit.
		if slot >= 0 or (visible and idx >= 0):
			get_viewport().set_input_as_handled()


func _handle_mouse_motion(ev: InputEventMouseMotion) -> void:
	if ev.device == InputEvent.DEVICE_ID_EMULATION:
		var local := get_global_transform_with_canvas().affine_inverse() * ev.position
		if (visible and _slot_at_local(local) >= 0) \
				or _touch_index != -1 or not _ignored_fingers.is_empty():
			get_viewport().set_input_as_handled()
		return
	if _mouse_slot == -1:
		return
	var local := get_global_transform_with_canvas().affine_inverse() * ev.position
	var idx := _slot_at_local(local)
	if idx != _mouse_slot:
		# Dragged outside original cell: cancel mouse intent permanently.
		_mouse_slot = -1
		for i in range(10):
			if cells[i].button_pressed:
				cells[i].set_pressed_no_signal(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_gesture()
