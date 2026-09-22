extends Node
## Fist technique preview sandbox (3D). Stance/attack only.
## Optional isolated defense mode via defense_preview flag.
## No training, rewards or saves.

const NOVICE_FRAMES := preload("res://assets/characters/courtyard/fist-preview/novice_frames.tres")
const NOVICE_PACK_FRAMES := preload("res://assets/characters/courtyard/fist-preview/novice_pack_frames.tres")
const TRAINED_FRAMES := preload("res://assets/characters/courtyard/fist-preview/trained_frames.tres")
const TRAINED_PACK_FRAMES := preload("res://assets/characters/courtyard/fist-preview/trained_pack_frames.tres")
const NOVICE_DEFENSE_FRAMES := preload("res://assets/characters/courtyard/fist-defense/novice_frames.tres")
const NOVICE_DEFENSE_PACK_FRAMES := preload("res://assets/characters/courtyard/fist-defense/novice_pack_frames.tres")
const TRAINED_DEFENSE_FRAMES := preload("res://assets/characters/courtyard/fist-defense/trained_frames.tres")
const TRAINED_DEFENSE_PACK_FRAMES := preload("res://assets/characters/courtyard/fist-defense/trained_pack_frames.tres")

@export var defense_preview: bool = false

var level: Node
var technique: String = "novice"
var defense: Node

var _player: CharacterBody3D
var _toolbar: CanvasLayer
var _defense_toolbar: Node
var _strike_count := 0

func _ready() -> void:
	if defense_preview:
		DisplayServer.window_set_title("ASHBOUND — Defense preview")
	else:
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

	level = _create_level()
	var hud: Node = level.get_node("HUD")
	hud.force_touch_controls = true
	if defense_preview:
		var preview_player: Node = level.get_node("Actors/Player")
		preview_player.set_script(_create_preview_player_script())
		# Defense probe: hide the legacy touch legend (it spans the left world
		# and the NPC name) and clear stale quest instructions.
		var legend: Node = hud.get_node_or_null("RootControl/BottomLeft/LegendLabel")
		if legend != null:
			legend.visible = false
		if hud.has_method("clear_message"):
			hud.clear_message()
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

	_toolbar = _create_preview_toolbar()
	add_child(_toolbar)
	_toolbar.setup(self)

	if defense_preview:
		var defense_controller: Node = _create_defense_controller()
		defense_controller.name = "DefenseController"
		add_child(defense_controller)
		_player.set("defense_controller", defense_controller)
		defense = defense_controller
		defense.setup(self, _player)
		var defense_toolbar: Node = _create_defense_toolbar()
		add_child(defense_toolbar)
		defense_toolbar.setup(self, defense)

	print("ASHBOUND_FIST_SANDBOX_READY")

func _create_level() -> Node:
	return preload("res://scenes/courtyard/first_courtyard.tscn").instantiate()

func _create_preview_player_script() -> GDScript:
	return preload("res://scripts/tools/fist_defense_player.gd")

func _create_preview_toolbar() -> CanvasLayer:
	return preload("res://scripts/tools/fist_preview_toolbar.gd").new()

func _create_defense_controller() -> Node:
	return preload("res://scripts/tools/fist_defense_controller.gd").new()

func _create_defense_toolbar() -> Node:
	return preload("res://scripts/tools/fist_defense_toolbar.gd").new()

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
	if defense_preview:
		if value == "novice":
			bare = NOVICE_DEFENSE_FRAMES
			worn = NOVICE_DEFENSE_PACK_FRAMES
		else:
			bare = TRAINED_DEFENSE_FRAMES
			worn = TRAINED_DEFENSE_PACK_FRAMES
	else:
		if value == "novice":
			bare = NOVICE_FRAMES
			worn = NOVICE_PACK_FRAMES
		else:
			bare = TRAINED_FRAMES
			worn = TRAINED_PACK_FRAMES
	var layer: Node = _player.get_node("Visual/BackpackLayer")
	if layer == null or not layer.configure_body_frame_pair(bare, worn):
		return false
	if defense != null and technique != value:
		defense.cancel_trial()
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
