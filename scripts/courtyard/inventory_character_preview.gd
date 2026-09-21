extends TextureRect
## Портрет в инвентаре: показывает лямки рюкзака, если он надет.

var _backpack_preview: TextureRect


func _ready() -> void:
	_backpack_preview = TextureRect.new()
	_backpack_preview.name = "BackpackPreview"
	_backpack_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backpack_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backpack_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = preload("res://assets/characters/courtyard/traveler-backpack-layer-v1.png")
	atlas_texture.region = Rect2(0, 0, 724, 724)
	atlas_texture.filter_clip = true
	_backpack_preview.texture = atlas_texture
	add_child(_backpack_preview)


func _process(_delta: float) -> void:
	refresh_preview()


## Обновляет наложение лямок рюкзака на портрет.
func refresh_preview() -> void:
	var inventory := get_node_or_null("/root/Inventory") as Node
	if not is_visible_in_tree() or texture == null or inventory == null:
		_backpack_preview.visible = false
		return
	var worn_storage: Dictionary = inventory.get_worn_storage("backpack")
	if worn_storage.is_empty():
		_backpack_preview.visible = false
		return

	var frames := preload("res://assets/characters/courtyard/traveler_frames.tres") as SpriteFrames
	var p: float = float(frames.get_meta("pixel_size_front", 0.00577849))
	var body_world_center: float = float(frames.get_meta("baseline_offset_pixels", 182.0)) * p

	var texture_size := texture.get_size()
	var fit_scale: float = min(size.x / texture_size.x, size.y / texture_size.y)
	var fit_origin := Vector2((size.x - texture_size.x * fit_scale) / 2.0, (size.y - texture_size.y * fit_scale) / 2.0)

	# Центр рюкзака: мировая высота 1.25 м, по горизонтали по центру.
	var backpack_center_px := Vector2(
		texture_size.x / 2.0,
		texture_size.y / 2.0 - (1.25 - body_world_center) / p
	)

	# Полотно 724 px = 724 * 0.00115 м; перевод в пиксели портрета и масштаб fit.
	var accessory_size: float = 724.0 * 0.00115 / p * fit_scale

	_backpack_preview.size = Vector2(accessory_size, accessory_size)
	_backpack_preview.position = fit_origin + backpack_center_px * fit_scale - _backpack_preview.size / 2.0
	_backpack_preview.visible = true
