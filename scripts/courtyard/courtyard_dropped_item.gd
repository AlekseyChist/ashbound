extends "res://scripts/courtyard/interaction_point.gd"
## Выпавший предмет двора: визуал-спрайт и точка взаимодействия.

const VISUAL_WORLD_HEIGHT: float = 0.55

var owner_manager: Node = null
var item: Dictionary = {}


func _ready() -> void:
	super._ready()
	interacted.connect(_on_interacted)
	_build_visual()


func get_display_name() -> String:
	return Localization.text("ITEM_" + str(item.get("id", "")).to_upper() + "_NAME")


func get_prompt() -> String:
	return Localization.text("DROP_PICK_UP")


func _on_interacted(_point: Node) -> void:
	if owner_manager != null and owner_manager.has_method("try_pickup"):
		owner_manager.try_pickup(str(item.get("instance_id", "")))


func _build_visual() -> void:
	var visual: Sprite3D = Sprite3D.new()
	visual.name = "Visual"
	visual.position = Vector3.ZERO
	var texture: Texture2D = owner_manager.get_script().call("texture_for_item", str(item.id))
	if texture == null:
		queue_free()
		return
	visual.texture = texture
	visual.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	visual.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	visual.shaded = false
	var texture_height: float = maxf(texture.get_size().y, 1.0)
	visual.pixel_size = VISUAL_WORLD_HEIGHT / texture_height
	visual.position.y = 0.22
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)


