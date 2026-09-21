extends Node3D
## Visible 2D backpack accessory on the hero when a real backpack is worn.
## Parent: Player/Visual (CourtyardCharacterVisual). Child Sprite3D "Pack".

const PACK_TEXTURE_PATH := "res://assets/characters/courtyard/traveler-backpack-layer-v1.png"
const CELL_COUNT := 3
const CELL_SIZE := Vector2(724, 724)
const PIXEL_SIZE := 0.00115
const BASE_CENTER_HEIGHT := 1.25
const CAMERA_PUSH := 0.025
const SIDE_OFFSET_PX := 70.0
const WALK_BOB := 0.01
const RUN_BOB := 0.018

var _pack: Sprite3D
var _atlas: Array[AtlasTexture] = []
var _source: AnimatedSprite3D
var _inventory: Node

func _ready() -> void:
	process_priority = 10
	_inventory = get_node_or_null("/root/Inventory")
	var visual := get_parent() as Node3D
	_pack = Sprite3D.new()
	_pack.name = "Pack"
	_pack.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_pack.shaded = false
	_pack.cast_shadow = 0
	_pack.alpha_cut = 1
	_pack.alpha_scissor_threshold = 0.25
	_pack.pixel_size = PIXEL_SIZE
	_pack.no_depth_test = false
	add_child(_pack)
	_pack.visible = false
	var texture: Texture2D = preload(PACK_TEXTURE_PATH)
	for i in CELL_COUNT:
		var at := AtlasTexture.new()
		at.atlas = texture
		at.region = Rect2(Vector2(i * CELL_SIZE.x, 0), CELL_SIZE)
		at.filter_clip = true
		_atlas.append(at)
	_pack.texture = _atlas[1]
	_pack.position = Vector3(0.0, BASE_CENTER_HEIGHT, 0.0)
	refresh_visual()


func _process(_delta: float) -> void:
	refresh_visual()

func refresh_visual() -> void:
	if _pack == null or _inventory == null:
		return
	var worn: Dictionary = _inventory.get_worn_storage("backpack")
	if worn.is_empty():
		_pack.visible = false
		return
	var visual := get_parent() as Node3D
	_source = _find_active_source(visual)
	if _source == null or not is_instance_valid(_source) or not _source.visible:
		_pack.visible = false
		return
	_pack.visible = true
	var dir: StringName = visual.get_visual_direction()
	var frame: int = _source.frame
	var bob := 0.0
	var anim := str(_source.animation).to_lower()
	var is_run := anim.begins_with("run")
	if is_run:
		bob = RUN_BOB if frame % 2 == 1 else 0.0
	elif anim.begins_with("walk") or anim.begins_with("idle"):
		bob = WALK_BOB if frame % 2 == 1 else 0.0
	var cell := 1
	var flip := false
	var side_px := 0.0
	match String(dir):
		"front":
			cell = 0
		"back":
			cell = 1
		"right":
			cell = 2
			side_px = -SIDE_OFFSET_PX
		"left":
			cell = 2
			flip = true
			side_px = SIDE_OFFSET_PX
		_:
			cell = 1
	if is_run:
		side_px *= 45.0 / SIDE_OFFSET_PX
	var center_height := BASE_CENTER_HEIGHT - (0.30 if is_run else 0.0)
	_pack.texture = _atlas[cell]
	_pack.flip_h = flip
	var cam := get_viewport().get_camera_3d()
	var push := Vector3.ZERO
	if cam != null:
		var to_cam: Vector3 = (cam.global_position - global_position).normalized()
		to_cam.y = 0.0
		push = to_cam * CAMERA_PUSH
	_pack.offset = Vector2(side_px, 0.0)
	_pack.position = Vector3(0.0, center_height + bob, 0.0) + push


func _find_active_source(visual: Node3D) -> AnimatedSprite3D:
	var pocket := visual.get_node_or_null("PocketPose") as AnimatedSprite3D
	if pocket != null and pocket.visible:
		return pocket
	return visual.get_node_or_null("Body") as AnimatedSprite3D
