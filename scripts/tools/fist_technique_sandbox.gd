extends Node
## Fist technique preview sandbox (3D). Stance/attack only.
## No training, defense, rewards or saves.

const NOVICE_FRAMES := preload("res://assets/characters/courtyard/fist-preview/novice_frames.tres")
const NOVICE_PACK_FRAMES := preload("res://assets/characters/courtyard/fist-preview/novice_pack_frames.tres")
const TRAINED_FRAMES := preload("res://assets/characters/courtyard/fist-preview/trained_frames.tres")
const TRAINED_PACK_FRAMES := preload("res://assets/characters/courtyard/fist-preview/trained_pack_frames.tres")

var level: Node
var technique: String = "novice"

var _player: CharacterBody3D
var _toolbar: CanvasLayer
var _strike_count := 0

func _ready() -> void:
	DisplayServer.window_set_title("ASHBOUND — Fist preview")
	var inventory: Node = get_node("/root/Inventory")
	if not inventory.configure_storage([
		{"id": "traveler_clothing_pocket", "kind": "pocket", "capacity": 6},
	]):
		push_error("FIST_SANDBOX_FAIL: configure_storage")
		get_tree().quit(1)
		return
	if not inventory.add_item("traveler_backpack"):
		push_error("FIST_SANDBOX_FAIL: add_item traveler_backpack")
		get_tree().quit(1)
		return

	level = preload("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	var hud: Node = level.get_node("HUD")
	hud.force_touch_controls = true
	add_child(level)

	_player = level.get_node("Actors/Player")
	if _player == null:
		push_error("FIST_SANDBOX_FAIL: Actors/Player missing")
		get_tree().quit(1)
		return
	# Сравнительное превью: стартуем на чистом поле, чтобы камера не упиралась в манекен.
	_player.position = Vector3(0.0, 0.1, 4.0)
	_player.facing_direction = Vector3.RIGHT

	level._snap_camera_to_player()
	var camera_rig: Node3D = level.get_node("CameraRig")
	camera_rig.set_mouse_capture(false)
	level._apply_state(4) # PRACTICE

	for panel_path in ["RootControl/TopLeftPanel", "RootControl/TopRightPanel"]:
		var panel: Node = hud.get_node_or_null(panel_path)
		if panel != null:
			panel.visible = false
	var prompt: Node = hud.get_node_or_null("RootControl/PromptLabel")
	if prompt != null:
		prompt.visible = false

	# Разъединяем только квест-интеракции, чтобы превью не продвигало сюжет.
	for path in ["Actors/Innkeeper", "Actors/Watchman", "Interactions/Woodpile"]:
		var node: Node = level.get_node(path)
		if node != null and node.has_signal("interacted"):
			if node.interacted.is_connected(level._on_point_interacted):
				node.interacted.disconnect(level._on_point_interacted)

	_player.strike_requested.connect(_on_strike_requested)

	if not set_technique("novice"):
		push_error("FIST_SANDBOX_FAIL: initial novice pair")
		get_tree().quit(1)
		return

	_toolbar = preload("res://scripts/tools/fist_preview_toolbar.gd").new()
	add_child(_toolbar)
	_toolbar.setup(self)

	print("ASHBOUND_FIST_SANDBOX_READY")

func _process(_delta: float) -> void:
	if level != null and level.dummy_hits >= 3:
		level.dummy_hits = 0
		level._apply_state(4) # PRACTICE

func _on_strike_requested() -> void:
	_strike_count += 1
	print("ASHBOUND_FIST_SANDBOX_STRIKE count=%d" % _strike_count)

func set_technique(value: String) -> bool:
	if _player == null:
		return false
	if value != "novice" and value != "trained":
		return false
	var bare: SpriteFrames
	var worn: SpriteFrames
	if value == "novice":
		bare = NOVICE_FRAMES
		worn = NOVICE_PACK_FRAMES
	else:
		bare = TRAINED_FRAMES
		worn = TRAINED_PACK_FRAMES
	var layer: Node = _player.get_node("Visual/BackpackLayer")
	if layer == null or not layer.configure_body_frame_pair(bare, worn):
		return false
	technique = value
	if _toolbar != null:
		_toolbar.refresh()
	print("ASHBOUND_FIST_SANDBOX_TECHNIQUE=%s" % technique)
	return true

func set_backpack_enabled(enabled: bool) -> bool:
	if _player == null:
		return false
	var inventory: Node = get_node("/root/Inventory")
	var worn: Dictionary = inventory.get_worn_storage("backpack")
	if enabled == (not worn.is_empty()):
		return true
	if enabled:
		var found := ""
		for entry in inventory.items:
			if entry.id == "traveler_backpack":
				found = entry.instance_id
				break
		if found == "":
			return false
		if not inventory.equip_storage_item({"instance_id": found}):
			return false
	else:
		if not inventory.unequip_storage_item("backpack", "traveler_clothing_pocket"):
			return false
	if is_backpack_enabled() != enabled:
		return false
	var layer: Node = _player.get_node("Visual/BackpackLayer")
	if layer != null and layer.has_method("refresh_visual"):
		layer.refresh_visual()
	if _toolbar != null:
		_toolbar.refresh()
	print("ASHBOUND_FIST_SANDBOX_BACKPACK=%s" % ("on" if is_backpack_enabled() else "off"))
	return true

func is_backpack_enabled() -> bool:
	var inventory: Node = get_node("/root/Inventory")
	return not inventory.get_worn_storage("backpack").is_empty()
