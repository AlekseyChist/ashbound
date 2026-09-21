class_name InventoryTouchGesture
extends RefCounted
## Touch/mouse gesture controller for the inventory panel.
## Replaces buggy UI pointer logic with explicit per-pointer tracking.

const DRAG_DELAY_MS: int = 250
const SCROLL_MIN_VY: float = 16.0
const DRAG_MIN_DIST: float = 8.0
const MOUSE_DRAG_DIST: float = 12.0
const GHOST_OFFSET: Vector2 = Vector2(-70, -190)
const GHOST_SIZE: int = 140

var _target_highlights: Dictionary = {}
var _panel: Control
var _active_pointers: Dictionary = {}
var _primary: int = -99
var _blocked: bool = false
var _mode: String = "pending" # pending | drag | scroll
var _press_pos: Vector2 = Vector2.ZERO
var _last_pos: Vector2 = Vector2.ZERO
var _pressed_target: Dictionary = {}
var _source: Dictionary = {}
var _press_msec: int = 0
var _scroll_accum: float = 0.0
var _highlight_modulate: Color = Color.WHITE
var _highlight_active: bool = false


func _init(owner: Control) -> void:
	_panel = owner


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func handle(event: InputEvent) -> bool:
	if _panel == null or not _panel.is_visible_in_tree():
		return false
	var ev := event as InputEvent
	if ev is InputEventMouseButton:
		return _handle_mouse_button(ev as InputEventMouseButton)
	if ev is InputEventMouseMotion:
		return _handle_mouse_motion(ev as InputEventMouseMotion)
	if ev is InputEventScreenTouch:
		return _handle_screen_touch(ev as InputEventScreenTouch)
	if ev is InputEventScreenDrag:
		return _handle_screen_drag(ev as InputEventScreenDrag)
	return false


func cancel() -> void:
	_active_pointers.clear()
	_primary = -99
	_blocked = false
	_mode = "pending"
	_press_pos = Vector2.ZERO
	_last_pos = Vector2.ZERO
	_pressed_target = {}
	_source = {}
	_scroll_accum = 0.0
	_restore_highlight()
	_hide_ghost()


# ---------------------------------------------------------------------------
# Mouse handling (device -1)
# ---------------------------------------------------------------------------

func _handle_mouse_button(ev: InputEventMouseButton) -> bool:
	if ev.device == -1:
		return false # emulated touch, not a real mouse
	if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		return false # wheel passes through
	if ev.pressed:
		if ev.button_index != MOUSE_BUTTON_LEFT:
			return false
		if _active_pointers.is_empty() and _language_menu_blocked(ev.position):
			return false
		_begin_pointer(-10, ev.position)
		return true
	else:
		if ev.button_index != MOUSE_BUTTON_LEFT:
			return false
		if not _active_pointers.has(-10):
			return false
		_end_pointer(-10, ev.position)
		return true

func _language_menu_blocked(pos: Vector2) -> bool:
	var lang_btn := _panel.get("_language_choice") as OptionButton
	if lang_btn == null:
		return false
	var popup := lang_btn.get_popup()
	if popup != null and popup.visible:
		return true
	if lang_btn.get_global_rect().has_point(pos):
		return true
	return false


func _handle_mouse_motion(ev: InputEventMouseMotion) -> bool:
	if ev.device == -1:
		return false # emulated touch, not a real mouse
	if _primary != -10 or not _active_pointers.has(-10):
		return false
	_track_motion(-10, ev.position)
	return true


# ---------------------------------------------------------------------------
# Touch handling (native devices)
# ---------------------------------------------------------------------------

func _handle_screen_touch(ev: InputEventScreenTouch) -> bool:
	if ev.canceled:
		if _active_pointers.has(ev.index):
			_active_pointers.erase(ev.index)
		if _primary == ev.index:
			_primary = -99
		_mode = "pending"
		_source = {}
		_pressed_target = {}
		_blocked = not _active_pointers.is_empty()
		_hide_ghost()
		_restore_highlight()
		return true
	if ev.pressed:
		if _active_pointers.is_empty() and _language_menu_blocked(ev.position):
			return false
		_begin_pointer(ev.index, ev.position)
	else:
		if not _active_pointers.has(ev.index):
			return false
		_end_pointer(ev.index, ev.position)
	return true


func _handle_screen_drag(ev: InputEventScreenDrag) -> bool:
	if _primary != ev.index or not _active_pointers.has(ev.index):
		return false
	_track_motion(ev.index, ev.position)
	return true


# ---------------------------------------------------------------------------
# Pointer lifecycle
# ---------------------------------------------------------------------------

func _begin_pointer(id: int, pos: Vector2) -> void:
	if _blocked:
		_active_pointers[id] = true
		return
	if _primary != -99:
		# Second pointer: cancel current visual/drag, block until all released.
		_restore_highlight()
		_hide_ghost()
		_primary = -99
		_mode = "pending"
		_source = {}
		_pressed_target = {}
		_blocked = true
		_active_pointers[id] = true
		return
	_primary = id
	_active_pointers[id] = true
	_mode = "pending"
	_press_pos = pos
	_last_pos = pos
	_scroll_accum = 0.0
	_press_msec = Time.get_ticks_msec()
	_pressed_target = _hit_test(pos)
	_source = _capture_source(_pressed_target)


func _end_pointer(id: int, pos: Vector2) -> void:
	if not _active_pointers.has(id):
		return
	_active_pointers.erase(id)
	if id == _primary:
		if _blocked:
			# Blocked release: no action.
			_primary = -99
			_mode = "pending"
			_source = {}
			_pressed_target = {}
			if _active_pointers.is_empty():
				_blocked = false
			return
		_finish_primary(pos)
		_primary = -99
		_mode = "pending"
		_source = {}
		_pressed_target = {}
	else:
		if _blocked and _active_pointers.is_empty():
			_blocked = false


func _finish_primary(pos: Vector2) -> void:
	if _mode == "drag":
		_do_drop(pos)
	elif _mode == "pending":
		# Tap only if same hit identity as press.
		var tap_target := _hit_test(pos)
		if _same_identity(_pressed_target, tap_target):
			_do_tap(tap_target)
	_restore_highlight()
	_hide_ghost()


func _track_motion(id: int, pos: Vector2) -> void:
	if id != _primary or not _active_pointers.has(id):
		return
	var elapsed := Time.get_ticks_msec() - _press_msec
	var delta := pos - _last_pos
	var total := pos - _press_pos

	if _mode == "pending":
		if _is_touch_primary():
			# Touch: before 250ms, compare TOTAL displacement from press.
			# Vertical total > 16 AND pointer began inside ItemScroll => scroll.
			if elapsed < DRAG_DELAY_MS and absf(total.y) > SCROLL_MIN_VY:
				var item_scroll: ScrollContainer = _panel.get("_item_scroll")
				if item_scroll != null and (item_scroll is ScrollContainer) and item_scroll.get_global_rect().has_point(_press_pos):
					_mode = "scroll"
					_apply_scroll(total.y)
					_last_pos = pos
					return
			elif elapsed >= DRAG_DELAY_MS and (absf(total.x) > DRAG_MIN_DIST or absf(total.y) > DRAG_MIN_DIST):
				if _source_valid():
					_mode = "drag"
					_show_ghost(pos)
				else:
					# No valid source; stay pending (will be a tap on release).
					_last_pos = pos
					return
			else:
				# Early horizontal movement stays pending until hold or release.
				_last_pos = pos
				return
		else:
			# Mouse: > 12 => drag.
			if total.length() > MOUSE_DRAG_DIST:
				if _source_valid():
					_mode = "drag"
					_show_ghost(pos)
				else:
					_last_pos = pos
					return
	elif _mode == "scroll":
		# Scroll by delta from last position (not accumulated).
		_apply_scroll(delta.y)
		_last_pos = pos
		return
	elif _mode == "drag":
		_update_ghost(pos)
		_last_pos = pos
		return


func _is_touch_primary() -> bool:
	return _primary != -10


# ---------------------------------------------------------------------------
# Hit testing
# ---------------------------------------------------------------------------

func _hit_test(pos: Vector2) -> Dictionary:
	var panel := _panel
	if panel == null or not panel.is_visible_in_tree():
		return {}
	# Close button.
	var close_btn: Button = panel.get("_close_button")
	if close_btn is Button and close_btn.visible:
		if close_btn.get_global_rect().has_point(pos):
			return {"kind": "close", "id": "close", "control": close_btn}
	# Language choice (native popup preserved; if active pointer, release cancels).
	var lang_choice: OptionButton = panel.get("_language_choice")
	if lang_choice is OptionButton and lang_choice.visible:
		if lang_choice.get_global_rect().has_point(pos):
			return {"kind": "language", "id": "language", "control": lang_choice}
	# Menu sections (journal/quests etc. via existing controller).
	var sections: RefCounted = panel.get("_sections")
	if sections != null and sections.has_method("hit_test"):
		var section_hit: Dictionary = sections.hit_test(pos)
		if not section_hit.is_empty():
			return section_hit
	# If a non-items section is active, block storage tabs/quick/equipment/items.
	if sections != null and sections.get("current_section") != "items":
		return {}
	# Drop button (discard) — hit only when enabled or while dragging.
	var drop_button: Button = panel.get("_drop_button")
	if drop_button is Button and drop_button.visible:
		if (not drop_button.disabled or _mode == "drag") and drop_button.get_global_rect().has_point(pos):
			return {"kind": "discard", "id": "discard", "control": drop_button}
	# Tab buttons (active only).
	var tab_buttons: Dictionary = panel.get("_tab_buttons")
	if tab_buttons is Dictionary:
		for key in tab_buttons.keys():
			var btn: Button = tab_buttons[key]
			if btn is Button and btn.visible and not btn.disabled:
				if btn.get_global_rect().has_point(pos):
					return {"kind": "tab", "id": str(key), "control": btn}
	# Quick cells.
	var quick_cells: Array = panel.get("_quick_cells")
	if quick_cells is Array:
		for i in range(quick_cells.size()):
			var cell: Button = quick_cells[i]
			if cell is Button and cell.visible:
				if cell.get_global_rect().has_point(pos):
					return {"kind": "quick", "id": str(i), "index": i, "control": cell}
	# Equipment slots.
	var armor_slot: Button = panel.get("_armor_slot")
	if armor_slot is Button and armor_slot.visible:
		if armor_slot.get_global_rect().has_point(pos):
			return {"kind": "equip", "id": "armor", "control": armor_slot}
	var weapon_slot: Button = panel.get("_weapon_slot")
	if weapon_slot is Button and weapon_slot.visible:
		if weapon_slot.get_global_rect().has_point(pos):
			return {"kind": "equip", "id": "weapon", "control": weapon_slot}
	var backpack_slot: Button = panel.get("_backpack_slot")
	if backpack_slot is Button and backpack_slot.visible:
		if backpack_slot.get_global_rect().has_point(pos):
			return {"kind": "worn", "id": "backpack", "control": backpack_slot}
	var pouch_slot: Button = panel.get("_pouch_slot")
	if pouch_slot is Button and pouch_slot.visible:
		if pouch_slot.get_global_rect().has_point(pos):
			return {"kind": "worn", "id": "pouch", "control": pouch_slot}
	# Item cells (only within scroll rect).
	var item_scroll: ScrollContainer = panel.get("_item_scroll")
	var cell_nodes: Array = panel.get("_cell_nodes")
	if item_scroll is ScrollContainer and cell_nodes is Array:
		var scroll_rect := item_scroll.get_global_rect()
		if scroll_rect.has_point(pos):
			for i in range(cell_nodes.size()):
				var node: Control = cell_nodes[i]
				if node is Control and node.visible:
					if node.get_global_rect().has_point(pos):
						var iid: String = str(node.get_meta("item_id", ""))
						if iid.is_empty():
							return {"kind": "storage", "id": _current_container_id(), "index": i, "control": node}
						return {"kind": "item", "id": iid, "index": i, "control": node}
			# Empty grid area within scroll.
			return {"kind": "storage", "id": _current_container_id(), "control": item_scroll}
	# Outside all controls: no target (prevents unequip on outside release).
	return {}


func _current_container_id() -> String:
	var cur: Variant = _panel.get("_current_container")
	if cur is String and not cur.is_empty():
		return cur
	return ""


# ---------------------------------------------------------------------------
# Source capture & validation
# ---------------------------------------------------------------------------

func _capture_source(target: Dictionary) -> Dictionary:
	if target.is_empty():
		return {}
	var kind: String = str(target.get("kind", ""))
	var id: String = str(target.get("id", ""))
	match kind:
		"item":
			var found := _find_item_full(id)
			if found.is_empty() or not found.has("item"):
				return {}
			return {"kind": "carried", "instance_id": id, "owner_kind": str(found.get("kind", "")), "location": str(found.get("location", ""))}
		"equip":
			var eq := _find_equipped_by_slot(id)
			if eq.is_empty():
				return {}
			return {"kind": "equip", "instance_id": str(eq.get("instance_id", "")), "slot": id, "location": id}
		"worn":
			var w := _find_worn_by_id(id)
			if w.is_empty():
				return {}
			return {"kind": "worn", "instance_id": str(w.get("instance_id", "")), "id": id, "location": id}
		"quick":
			var idx: int = int(target.get("index", 0))
			var bindings: Array = _panel.get("_quick_bindings")
			if bindings is Array and idx < bindings.size():
				var bound_id: String = str(bindings[idx])
				if not bound_id.is_empty():
					var found := _find_item_full(bound_id)
					if found.is_empty() or not found.has("item"):
						return {}
					return {"kind": "quick", "index": idx, "instance_id": bound_id, "owner_kind": str(found.get("kind", "")), "location": str(found.get("location", ""))}
			return {}
		_:
			return {}


func _source_valid() -> bool:
	if _source.is_empty():
		return false
	var kind: String = str(_source.get("kind", ""))
	match kind:
		"carried":
			var iid: String = str(_source.get("instance_id", ""))
			if iid.is_empty():
				return false
			var found := _find_item_full(iid)
			if found.is_empty() or not found.has("item"):
				return false
			return str(found.get("kind", "")) == str(_source.get("owner_kind", "")) and str(found.get("location", "")) == str(_source.get("location", ""))
		"equip":
			var slot: String = str(_source.get("slot", ""))
			if slot.is_empty():
				return false
			var eq := _find_equipped_by_slot(slot)
			if eq.is_empty():
				return false
			return str(eq.get("instance_id", "")) == str(_source.get("instance_id", ""))
		"worn":
			var wid: String = str(_source.get("id", ""))
			if wid.is_empty():
				return false
			var w := _find_worn_by_id(wid)
			if w.is_empty():
				return false
			return str(w.get("instance_id", "")) == str(_source.get("instance_id", ""))
		"quick":
			var idx: int = int(_source.get("index", 0))
			if idx < 0 or idx > 9:
				return false
			var bindings: Array = _panel.get("_quick_bindings")
			if not (bindings is Array) or idx >= bindings.size():
				return false
			if str(bindings[idx]) != str(_source.get("instance_id", "")):
				return false
			var found := _find_item_full(str(bindings[idx]))
			if found.is_empty() or not found.has("item"):
				return false
			return str(found.get("kind", "")) == str(_source.get("owner_kind", "")) and str(found.get("location", "")) == str(_source.get("location", ""))
		_:
			return false


func _find_item_full(iid: String) -> Dictionary:
	# Full lookup: carried, equipped, worn.
	var inv: Node = _panel.get("_inventory")
	if inv == null or not inv.has_method("get_save_data"):
		return {}
	var save: Variant = inv.call("get_save_data")
	if not (save is Dictionary):
		return {}
	var items: Variant = (save as Dictionary).get("items", [])
	if items is Array:
		for entry in items:
			if not (entry is Dictionary):
				continue
			if str((entry as Dictionary).get("instance_id", "")) == iid:
				return {"item": (entry as Dictionary).duplicate(true), "kind": "carried", "location": str(inv.call("get_item_storage", iid))}
	var equipped: Variant = (save as Dictionary).get("equipped", {})
	if equipped is Dictionary:
		for slot in (equipped as Dictionary).keys():
			var entry: Variant = (equipped as Dictionary).get(slot, null)
			if entry == null or not (entry is Dictionary):
				continue
			if str((entry as Dictionary).get("instance_id", "")) == iid:
				return {"item": (entry as Dictionary).duplicate(true), "kind": "equip", "location": str(slot)}
	var worn_storage: Variant = (save as Dictionary).get("worn_storage", {})
	if worn_storage is Dictionary:
		for slot in (worn_storage as Dictionary).keys():
			var entry: Variant = (worn_storage as Dictionary).get(slot, null)
			if entry == null or not (entry is Dictionary):
				continue
			if str((entry as Dictionary).get("instance_id", "")) == iid:
				return {"item": (entry as Dictionary).duplicate(true), "kind": "worn", "location": str(slot)}
	return {}


# ---------------------------------------------------------------------------
# Tap actions
# ---------------------------------------------------------------------------

func _do_tap(target: Dictionary) -> void:
	var kind: String = str(target.get("kind", ""))
	var id: String = str(target.get("id", ""))
	match kind:
		"item":
			_select_item(id)
			_refresh()
		"equip":
			_select_equipped(id)
			_refresh()
		"worn":
			_select_worn(id)
			_refresh()
		"close":
			if _panel.has_signal("close_requested"):
				_panel.emit_signal("close_requested")
		"tab":
			_set_current_container(id)
		"quick":
			_quick_tap(int(target.get("index", 0)))
			_refresh()
		"discard":
			if _panel.has_method("drop_instance"):
				_panel.drop_instance(_panel.get("_selected_item_id"))
		"storage":
			pass # No action on empty grid tap.
		"language":
			pass # Native popup preserved.
		"section":
			var sections: RefCounted = _panel.get("_sections")
			if sections != null and sections.has_method("select_section"):
				sections.select_section(id)


func _select_item(iid: String) -> void:
	var sel: Variant = _panel.get("_selected_item_id")
	if sel is String and sel == iid:
		return
	_panel.set("_selected_item_id", iid)


func _select_equipped(slot: String) -> void:
	var found := _find_equipped_by_slot(slot)
	if not found.is_empty():
		_panel.set("_selected_item_id", str(found.get("instance_id", "")))


func _select_worn(wid: String) -> void:
	var found := _find_worn_by_id(wid)
	if not found.is_empty():
		_panel.set("_selected_item_id", str(found.get("instance_id", "")))


func _set_current_container(cid: String) -> void:
	_panel.set("_current_container", cid)
	_panel.set("_selected_item_id", "")
	if _panel.has_method("refresh_contents"):
		_panel.call("refresh_contents")


func _quick_tap(idx: int) -> void:
	var bindings: Array = _panel.get("_quick_bindings")
	if not (bindings is Array) or idx < 0 or idx >= bindings.size():
		return
	_panel._on_quick_slot_tapped(idx)


# ---------------------------------------------------------------------------
# Drag / Drop
# ---------------------------------------------------------------------------

func _show_ghost(pos: Vector2) -> void:
	var found := _find_item_full(str(_source.get("instance_id", "")))
	if found.is_empty():
		return
	var ghost: TextureRect = _panel.get("_ghost")
	if ghost == null or not (ghost is TextureRect):
		return
	ghost.texture = _panel.call("_item_texture", str(found.item.id))
	ghost.size = Vector2(140, 140)
	ghost.global_position = pos + GHOST_OFFSET
	ghost.visible = true
	_update_ghost(pos)


func _update_ghost(pos: Vector2) -> void:
	var ghost: TextureRect = _panel.get("_ghost")
	if ghost == null or not (ghost is TextureRect):
		return
	_restore_highlight()
	ghost.global_position = pos + GHOST_OFFSET
	var target := _hit_test(pos)
	if _drop_target_valid(target):
		ghost.modulate = Color(1.0, 1.0, 1.0, 1.0)
		if target.has("control") and target["control"] is Control:
			var ctrl: Control = target["control"]
			if not _target_highlights.has(ctrl):
				_target_highlights[ctrl] = ctrl.modulate
			ctrl.modulate = Color(1.3, 1.2, 0.8, 1.0)
	else:
		ghost.modulate = Color(1.0, 0.4, 0.4, 1.0)


func _hide_ghost() -> void:
	var ghost: TextureRect = _panel.get("_ghost")
	if ghost is TextureRect:
		ghost.visible = false


func _drop_target_valid(target: Dictionary) -> bool:
	if target.is_empty():
		return false
	if not _source_valid():
		return false
	var found: Dictionary = _find_item_full(str(_source.get("instance_id", "")))
	if found.is_empty():
		return false
	var item: Dictionary = found.get("item", {})
	if item.is_empty():
		return false
	var inv: Node = _panel.get("_inventory")
	if inv == null:
		return false
	var iid: String = str(_source.get("instance_id", ""))
	var kind: String = str(target.get("kind", ""))
	match kind:
		"storage":
			var dest_id: String = str(target.get("id", ""))
			if dest_id.is_empty():
				return false
			var containers: Array = inv.call("get_storage_containers")
			for c in containers:
				if str(c.get("id", "")) == dest_id:
					var used: int = int(c.get("used", 0))
					var capacity: int = int(c.get("capacity", 0))
					var same_carried: bool = str(_source.get("location", "")) == dest_id and _source_kind_is("carried")
					if same_carried:
						return true
					return used < capacity
			return false
		"tab":
			var dest_id: String = str(target.get("id", ""))
			if dest_id.is_empty():
				return false
			var containers: Array = inv.call("get_storage_containers")
			for c in containers:
				if str(c.get("id", "")) == dest_id:
					var used: int = int(c.get("used", 0))
					var capacity: int = int(c.get("capacity", 0))
					var same_carried: bool = str(_source.get("location", "")) == dest_id and _source_kind_is("carried")
					if same_carried:
						return true
					return used < capacity
			return false
		"item":
			var cell_index: int = int(target.get("index", -1))
			var dest_id: String = _current_container_id()
			if dest_id.is_empty():
				return false
			var containers: Array = inv.call("get_storage_containers")
			for c in containers:
				if str(c.get("id", "")) == dest_id:
					var used: int = int(c.get("used", 0))
					var capacity: int = int(c.get("capacity", 0))
					var same_carried: bool = str(_source.get("location", "")) == dest_id and _source_kind_is("carried")
					if cell_index >= 0:
						if not _source_kind_is("carried"):
							return false
						if used < capacity:
							return true
						# occupied swap allowed even when full (source has a real cell)
						return true
					if same_carried:
						return true
					return used < capacity
			return false
		"equip":
			if not _source_kind_is("carried"):
				return false
			var slot: String = str(target.get("id", ""))
			return bool(inv.call("can_equip_in_slot", {"instance_id": iid}, slot))
		"worn":
			if not _source_kind_is("carried"):
				return false
			var slot: String = str(target.get("id", ""))
			return bool(inv.call("can_equip_in_slot", {"instance_id": iid}, slot))
		"discard":
			return _source_kind_is("carried") and bool(_panel.can_drop_instance(iid))
		"quick":
			var idx: int = int(target.get("index", -1))
			if idx < 0 or idx > 9:
				return false
			return bool(inv.call("can_assign_quick", {"instance_id": iid}))
		_:
			return false


func _source_kind_is(k: String) -> bool:
	return str(_source.get("kind", "")) == k


func _do_drop(pos: Vector2) -> void:
	if not _source_valid():
		return
	var src_snapshot := _source.duplicate(true)
	var target := _hit_test(pos)
	if target.is_empty():
		var sidx: int = int(src_snapshot.get("index", -1))
		if str(src_snapshot.get("kind", "")) == "quick" and sidx >= 0 and sidx <= 9:
			var bindings: Array = _panel.get("_quick_bindings")
			if bindings is Array and sidx < bindings.size():
				bindings[sidx] = ""
				_refresh()
		return
	var tkind: String = str(target.get("kind", ""))
	if (tkind == "storage" or tkind == "item") and int(target.get("index", -1)) >= 0 and str(src_snapshot.get("kind", "")) == "carried":
		var inv:Node = _panel.get('_inventory')
		var dest: String = str(target.get("id", "")) if tkind == "storage" else _current_container_id()
		if inv.move_item_to_cell({"instance_id": src_snapshot.instance_id}, dest, int(target.get("index", -1))):
			_refresh()
		else:
			_flash_error()
		return
	elif tkind == "discard":
		if str(src_snapshot.get("kind", "")) == "carried":
			_panel.drop_instance(str(src_snapshot.instance_id))
		return
	match tkind:
		"tab":
			_drop_to_storage(str(target.get("id", "")))
		"storage":
			_drop_to_storage(str(target.get("id", "")))
		"item":
			_drop_to_storage(_current_container_id())
		"equip":
			_drop_to_equipment(str(target.get("id", "")))
		"worn":
			_drop_to_worn(str(target.get("id", "")))
		"quick":
			_drop_to_quick(int(target.get("index", 0)))
		_:
			pass


func _drop_to_storage(dest_id: String) -> void:
	if dest_id.is_empty():
		return
	var src_kind: String = str(_source.get("kind", ""))
	if not _source_valid():
		return
	var captured: Dictionary = _source.duplicate(true)
	var inv: Node = _panel.get("_inventory")
	if inv == null:
		return
	var containers: Array = inv.call("get_storage_containers")
	var dest_ok := false
	for c in containers:
		if c is Dictionary and str(c.get("id", "")) == dest_id:
			if int(c.get("used", 0)) < int(c.get("capacity", 0)):
				dest_ok = true
			break
	match src_kind:
		"carried":
			var iid: String = str(captured.get("instance_id", ""))
			var src_loc: String = str(captured.get("location", ""))
			if src_loc == dest_id:
				return # Same container, no-op.
			if not dest_ok or inv == null or not inv.has_method("move_item_to_storage"):
				_flash_error()
				return
			var ok: bool = inv.call("move_item_to_storage", {"instance_id": iid}, dest_id)
			if ok:
				_refresh()
			else:
				_flash_error()
		"equip":
			var slot: String = str(captured.get("slot", ""))
			if not dest_ok or inv == null or not inv.has_method("unequip_to_storage"):
				_flash_error()
				return
			var ok2: bool = inv.call("unequip_to_storage", slot, dest_id)
			if ok2:
				_refresh()
			else:
				_flash_error()
		"worn":
			var wid: String = str(captured.get("id", ""))
			if not dest_ok or inv == null or not inv.has_method("unequip_storage_item"):
				_flash_error()
				return
			var ok3: bool = inv.call("unequip_storage_item", wid, dest_id)
			if ok3:
				_refresh()
			else:
				_flash_error()
		"quick":
			# Quick to storage: clear binding only if still matches and owned.
			var qidx: int = int(captured.get("index", 0))
			var qiid: String = str(captured.get("instance_id", ""))
			var bindings: Array = _panel.get("_quick_bindings")
			if bindings is Array and qidx < bindings.size():
				if str(bindings[qidx]) == qiid and not qiid.is_empty():
					bindings[qidx] = ""
					_refresh()


func _drop_to_equipment(slot: String) -> void:
	if not _source_kind_is("carried"):
		return
	var iid: String = str(_source.get("instance_id", ""))
	var found := _find_item_full(iid)
	if found.is_empty():
		return
	var item: Dictionary = found.get("item", {})
	var canon_slot: String = str(item.get("slot", ""))
	var itype: int = int(item.get("type", -1))
	# Validate matching canonical slot AND type.
	if canon_slot != slot:
		_flash_error()
		return
	var valid_type: bool = false
	if slot == "weapon":
		valid_type = (itype == 0)
	elif slot == "armor":
		valid_type = (itype == 1)
	else:
		valid_type = false
	if not valid_type:
		_flash_error()
		return
	var inv: Node = _panel.get("_inventory")
	if inv == null or not inv.has_method("equip_item"):
		return
	var handle := {"instance_id": iid}
	inv.call("equip_item", handle)
	_refresh()


func _drop_to_worn(wid: String) -> void:
	if not _source_valid():
		return
	if _source.get("kind", "") != "carried":
		return
	var iid: String = str(_source.get("instance_id", ""))
	var expected_id: String = ""
	if wid == "backpack":
		expected_id = "traveler_backpack"
	elif wid == "pouch":
		expected_id = "belt_pouch"
	else:
		_flash_error()
		return
	var full: Dictionary = _find_item_full(_source.get("instance_id", 0))
	var item: Dictionary = full.get("item", {})
	if str(item.get("id", "")) != expected_id:
		_flash_error()
		return
	var inv: Node = _panel.get("_inventory")
	if inv == null or not inv.has_method("equip_storage_item"):
		_flash_error()
		return
	var ok: bool = inv.call("equip_storage_item", {"instance_id": iid})
	if not ok:
		_flash_error()
	else:
		_refresh()


func _drop_to_quick(idx: int) -> void:
	if not _source_valid():
		return
	if idx < 0 or idx >= 10:
		return
	var bindings: Array = _panel.get("_quick_bindings")
	if not (bindings is Array):
		return
	if bindings.size() != 10:
		return
	var src_kind: String = str(_source.get("kind", ""))
	match src_kind:
		"carried", "equip":
			var iid: String = str(_source.get("instance_id", ""))
			var found := _find_item_full(iid)
			if found.is_empty():
				return
			var inv = _panel._inventory
			if not inv.can_assign_quick({"instance_id": iid}):
				_flash_error()
				return
			bindings[idx] = iid
			_refresh()
		"quick":
			var qidx: int = int(_source.get("index", 0))
			if qidx < 0 or qidx > 9:
				return
			var src_id: String = str(_source.get("instance_id", ""))
			if bindings[qidx] != src_id:
				return
			# Swap bindings by stable identity; never resize the array.
			bindings[qidx] = bindings[idx]
			bindings[idx] = src_id
			_refresh()
		_:
			pass


# ---------------------------------------------------------------------------
# Scroll
# ---------------------------------------------------------------------------

func _apply_scroll(delta_y: float) -> void:
	var item_scroll: ScrollContainer = _panel.get("_item_scroll")
	if item_scroll == null or not (item_scroll is ScrollContainer):
		return
	item_scroll.scroll_vertical -= roundi(delta_y)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _same_identity(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if str(a.get("kind", "")) != str(b.get("kind", "")):
		return false
	if str(a.get("id", "")) != str(b.get("id", "")):
		return false
	return true


func _find_equipped_by_slot(slot: String) -> Dictionary:
	var inv: Node = _panel.get("_inventory")
	if inv == null or not inv.has_method("get_save_data"):
		return {}
	var save: Variant = inv.call("get_save_data")
	if not (save is Dictionary):
		return {}
	var equipped: Dictionary = save.get("equipped", {})
	if equipped is Dictionary and equipped.has(slot):
		var eq: Variant = equipped[slot]
		if eq is Dictionary:
			return eq.duplicate(true)
	return {}


func _find_worn_by_id(wid: String) -> Dictionary:
	var inv: Node = _panel.get("_inventory")
	if inv == null or not inv.has_method("get_save_data"):
		return {}
	var save: Variant = inv.call("get_save_data")
	if not (save is Dictionary):
		return {}
	var worn: Dictionary = save.get("worn_storage", {})
	if worn is Dictionary and worn.has(wid):
		var w: Variant = worn[wid]
		if w is Dictionary:
			return w.duplicate(true)
	return {}


func _flash_error() -> void:
	if _panel.has_method("_flash_error"):
		_panel.call("_flash_error")


func _refresh() -> void:
	if _panel.has_method("refresh_contents"):
		_panel.call("refresh_contents")


func _restore_highlight() -> void:
	for key in _target_highlights.keys():
		if is_instance_valid(key):
			key.modulate = _target_highlights[key]
	_target_highlights.clear()
	if _panel != null:
		var ghost: TextureRect = _panel.get("_ghost")
		if ghost is TextureRect and is_instance_valid(ghost):
			ghost.modulate = Color.WHITE
