extends TextureRect
## Портрет текущего путешественника в инвентаре.
## Показывает полный кадр idle_front (frame 0). Рюкзака больше нет (D-057).

const BODY_FRAMES_PATH := "res://assets/characters/courtyard/traveler_frames.tres"


func _ready() -> void:
	refresh_preview()


func _process(_delta: float) -> void:
	refresh_preview()


func refresh_preview() -> void:
	var frames := load(BODY_FRAMES_PATH) as SpriteFrames
	if frames == null:
		return
	var target: Texture2D = frames.get_frame_texture("idle_front", 0)
	if target != null and texture != target:
		texture = target
