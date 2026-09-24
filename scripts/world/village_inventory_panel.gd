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
