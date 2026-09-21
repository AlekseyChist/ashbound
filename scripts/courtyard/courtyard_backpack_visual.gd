extends Node3D
## Полнокадровая замена рюкзака для текущего путешественника.
## Узел Visual/BackpackLayer (без детей) переключает полные кадры Body/PocketPose
## между базовыми и нарисованными вариантами с рюкзаком.

const BACKPACK_BODY_FRAMES_PATH := "res://assets/characters/courtyard/traveler_backpack_frames.tres"
const BACKPACK_POCKET_FRAMES_PATH := "res://assets/characters/courtyard/traveler_backpack_pocket_frames.tres"

var _inventory: Node
var _body: AnimatedSprite3D
var _pocket: AnimatedSprite3D
var _worn := false
var _bare_body_frames: SpriteFrames
var _bare_pocket_frames: SpriteFrames
var _warned := false


func _ready() -> void:
	process_priority = 10
	_inventory = get_node_or_null("/root/Inventory")
	var visual := get_parent() as Node3D
	if visual != null:
		_body = visual.get_node_or_null("Body") as AnimatedSprite3D
		_pocket = visual.get_node_or_null("PocketPose") as AnimatedSprite3D
	refresh_visual()


func _process(_delta: float) -> void:
	refresh_visual()


## Публичное обновление для тестов и процесса.
func refresh_visual() -> void:
	if _inventory == null or _body == null or _pocket == null:
		return
	var worn_storage: Dictionary = _inventory.get_worn_storage("backpack")
	var is_worn := not worn_storage.is_empty()
	if is_worn == _worn:
		return
	if is_worn:
		_enter_worn()
	else:
		_exit_worn()


func _enter_worn() -> void:
	var body_frames := load(BACKPACK_BODY_FRAMES_PATH) as SpriteFrames
	var pocket_frames := load(BACKPACK_POCKET_FRAMES_PATH) as SpriteFrames
	if body_frames == null or pocket_frames == null:
		if not _warned:
			push_error("courtyard_backpack_visual: could not load painted backpack frames")
			_warned = true
		return
	var pocket_anim := _pocket.animation
	if pocket_anim.is_empty() or not pocket_frames.has_animation(pocket_anim) or pocket_frames.get_frame_count(pocket_anim) < _pocket.sprite_frames.get_frame_count(pocket_anim):
		if not _warned:
			push_error("courtyard_backpack_visual: incompatible pocket animation frames")
			_warned = true
		return
	_capture_bare_frames()
	var body_ok := _apply_body_frames(body_frames)
	if not body_ok:
		return
	_apply_pocket_frames(pocket_frames)
	_worn = true


func _exit_worn() -> void:
	var body_ok := _apply_body_frames(_bare_body_frames)
	if not body_ok:
		return
	_apply_pocket_frames(_bare_pocket_frames)
	_worn = false


func _capture_bare_frames() -> void:
	# Храним точные ссылки на ресурсы, а не дубликаты:
	# базовая кожа могла измениться между надеваниями.
	_bare_body_frames = _body.sprite_frames
	_bare_pocket_frames = _pocket.sprite_frames


func _apply_body_frames(frames: SpriteFrames) -> bool:
	var visual := get_parent() as Node3D
	if frames == null or visual == null:
		return false
	var speed_scale := _body.speed_scale
	var ok: bool = visual.set_appearance_frames(frames)
	if not ok:
		if not _warned:
			push_warning("BackpackLayer: could not apply backpack frames; appearance unchanged")
			_warned = true
		return false
	_body.speed_scale = speed_scale
	return true


func _apply_pocket_frames(frames: SpriteFrames) -> void:
	if frames == null:
		return
	var animation := _pocket.animation
	var frame := _pocket.frame
	var frame_progress := _pocket.frame_progress
	var is_playing: bool = _pocket.is_playing()
	var speed_scale := _pocket.speed_scale
	_pocket.sprite_frames = frames
	_pocket.animation = animation
	_pocket.speed_scale = speed_scale
	if is_playing:
		_pocket.play(animation)
	else:
		_pocket.pause()
	_pocket.set_frame_and_progress(frame, frame_progress)
