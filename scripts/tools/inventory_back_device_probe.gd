extends Node
## QA-only Android event trace. Never used by the production main scene.
var menu: Node

func _ready() -> void:
	var scene := preload("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	add_child(scene)
	menu = scene.get_node("InventoryMenu")
	menu.closed.connect(_closed)
	menu.opened.connect(func(): _trace("opened"))
	get_tree().root.go_back_requested.connect(func(): _trace("window_back"))
	_trace("ready")

func _trace(label: String) -> void:
	print("BACK_PROBE ", label, " frame=", Engine.get_process_frames(), " state=", menu.get_menu_state() if is_instance_valid(menu) else -1, " auto=", get_tree().quit_on_go_back)

func _closed() -> void:
	_trace("closed")
	print_stack()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and is_instance_valid(menu):
		_trace("notification " + str(what))

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_trace("key code=%s physical=%s pressed=%s echo=%s" % [event.keycode, event.physical_keycode, event.pressed, event.echo])
