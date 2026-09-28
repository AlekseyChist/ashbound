extends CanvasLayer
## DEBUG-MAP-01 (owner 27 Sep): Settings -> Debug -> Map. The whole 2 x 2 km world from above
## (relief shading, biome colours, roads, rivers, the sea), city and site names, the hero as an
## arrow. A tap on the map puts the hero there. A checking tool, not the in-game map (that one
## needs a carried map item, CHARACTER_MENU_AND_CONDITION).
const SIZE := 401
const WATER := Color("3f7fa0")
const ROAD := Color("b08a5a")

var world: Node3D
var panel: Panel
var picture: TextureRect
var hero: Polygon2D
var close_button: Button
var labels: Array[Label] = []


func configure(scene: Node3D) -> void:
	world = scene
	layer = 100
	visible = false
	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.theme = preload("res://assets/ui/ashbound_ui.tres")
	add_child(panel)
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.offset_left = 24.0
	picture.offset_top = 24.0
	picture.offset_right = -360.0
	picture.offset_bottom = -24.0
	picture.gui_input.connect(_on_picture_input)
	panel.add_child(picture)
	hero = Polygon2D.new()
	hero.polygon = PackedVector2Array([Vector2(0, -22), Vector2(13, 14), Vector2(0, 7), Vector2(-13, 14)])
	hero.color = Color("f2d25c")
	picture.add_child(hero)
	close_button = Button.new()
	close_button.custom_minimum_size = Vector2(300, 120)
	close_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_button.offset_left = -330.0
	close_button.offset_right = -30.0
	close_button.offset_top = 30.0
	close_button.offset_bottom = 150.0
	close_button.pressed.connect(close)
	panel.add_child(close_button)
	var hint := Label.new()
	hint.name = "Hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -330.0
	hint.offset_right = -30.0
	hint.offset_top = 180.0
	hint.offset_bottom = 600.0
	hint.add_theme_font_size_override("font_size", 26)
	panel.add_child(hint)
	Localization.language_changed.connect(func(_l: String): _refresh_text())
	_refresh_text()


func open() -> void:
	if picture.texture == null:
		picture.texture = ImageTexture.create_from_image(_render())
		_add_labels()
	visible = true
	_place_labels.call_deferred()


func close() -> void:
	visible = false


func _refresh_text() -> void:
	close_button.text = Localization.text("UI_CLOSE")
	(panel.get_node("Hint") as Label).text = Localization.text("DEBUG_MAP_HINT")
	for label in labels:
		label.text = Localization.text(label.get_meta("key"))


func _process(_delta: float) -> void:
	if not visible or world == null:
		return
	var local: Vector3 = world.world_root.to_local(world.player.global_position)
	hero.position = _to_screen(Vector2(local.x + world.HALF, local.z + world.HALF))
	var f: Vector3 = world.player.facing_direction
	hero.rotation = atan2(f.x, -f.z)


## The drawn map inside the picture (keep-aspect, centred).
func _map_rect() -> Rect2:
	var side := minf(picture.size.x, picture.size.y)
	return Rect2((picture.size - Vector2(side, side)) * 0.5, Vector2(side, side))


func _to_screen(map: Vector2) -> Vector2:
	var rect := _map_rect()
	return rect.position + map / 2000.0 * rect.size.x


func _on_picture_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	var rect := _map_rect()
	if not rect.has_point(event.position):
		return
	var map: Vector2 = (event.position - rect.position) / rect.size.x * 2000.0
	var x: float = map.x - world.HALF
	var z: float = map.y - world.HALF
	world.teleport_to({"id": "map", "spawn": [x, world.world_ground(x, z) + 0.2, z], "point": [map.x, map.y + 5.0]})
	close()


func _add_labels() -> void:
	for place in world.debug_locations():
		var label := Label.new()
		label.set_meta("key", place.key)
		label.set_meta("map", Vector2(float(place.spawn[0]) + world.HALF, float(place.spawn[2]) + world.HALF))
		label.text = Localization.text(place.key)
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
		picture.add_child(label)
		labels.append(label)


func _place_labels() -> void:
	for label in labels:
		label.position = _to_screen(label.get_meta("map")) - Vector2(label.size.x * 0.5, 28)


## Relief shading on the ground colours, water blue, roads from the road mask.
func _render() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var heights: PackedFloat32Array = world.world_heights
	var sea_level: float = float(world.world_layout.sea.level) if world.world_layout.get("sea") is Dictionary else -INF
	for z in SIZE:
		for x in SIZE:
			var i := z * SIZE + x
			var h := heights[i]
			var dx := heights[z * SIZE + mini(x + 1, SIZE - 1)] - heights[z * SIZE + maxi(x - 1, 0)]
			var dz := heights[mini(z + 1, SIZE - 1) * SIZE + x] - heights[maxi(z - 1, 0) * SIZE + x]
			var shade := clampf(0.8 + (-dx - dz) * 0.06, 0.45, 1.25)
			var c: Color = world.world_colors[i].linear_to_srgb() * shade
			if h < sea_level:
				c = WATER.darkened(clampf((sea_level - h) / 20.0, 0.0, 0.5))
			if world.road_mask != null and world.road_mask.get_pixel(mini(x * 5, 1999), mini(z * 5, 1999)).r > 0.5:
				c = ROAD
			image.set_pixel(x, z, Color(c.r, c.g, c.b))
	for river in world.world_layout.rivers:
		var points: Array = river.world_points
		for n in range(points.size()):
			var p: Array = points[n]
			var r := maxi(1, int(float(river.world_widths[n]) / 10.0))
			var cx := int((float(p[0]) + world.HALF) / 5.0)
			var cz := int((float(p[2]) + world.HALF) / 5.0)
			for oz in range(-r, r + 1):
				for ox in range(-r, r + 1):
					if cx + ox >= 0 and cx + ox < SIZE and cz + oz >= 0 and cz + oz < SIZE:
						image.set_pixel(cx + ox, cz + oz, WATER)
	return image
