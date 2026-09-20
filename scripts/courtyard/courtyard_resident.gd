class_name CourtyardResident
extends CourtyardInteractionPoint

@export var appearance: SpriteFrames

func _ready() -> void:
	super._ready()
	var body := $Body as AnimatedSprite3D
	if body != null and appearance != null:
		body.sprite_frames = appearance
		body.play("idle")
