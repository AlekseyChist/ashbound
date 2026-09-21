extends TextureRect
## Портрет текущего путешественника в инвентаре.
## Показывает полный кадр idle_front (frame 0) с рюкзаком, если он надет.

const BODY_FRAMES_PATH := "res://assets/characters/courtyard/traveler_frames.tres"
const BACKPACK_BODY_FRAMES_PATH := "res://assets/characters/courtyard/traveler_backpack_frames.tres"


func _ready() -> void:
	refresh_preview()


func _process(_delta: float) -> void:
	refresh_preview()


## Обновляет портрет на полный кадр с рюкзаком, если рюкзак надет.
func refresh_preview() -> void:
	var inventory := get_node_or_null("/root/Inventory") as Node
	if inventory == null:
		return
	var worn_storage: Dictionary = inventory.get_worn_storage("backpack")
	var frames_path := BODY_FRAMES_PATH
	if not worn_storage.is_empty():
		frames_path = BACKPACK_BODY_FRAMES_PATH
	var frames := load(frames_path) as SpriteFrames
	if frames == null:
		return
	var target: Texture2D = frames.get_frame_texture("idle_front", 0)
	if target != null and texture != target:
		texture = target
