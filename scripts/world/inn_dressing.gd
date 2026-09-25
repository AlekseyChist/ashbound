extends Node3D
## TAVERN-03: life in the forest inn. CC0 props from Poly Haven (lightened for the phone by
## art/blender/optimize_props.py), a fire in the big hearth with a flickering light and crackle,
## every light hangs or stands as a visible lantern/candle, rugs on the floors.
## Coordinates: the inn frame in Godot (x, y, z) = Blender (x, z, -y) of art/blender/tavern-v3.
const PROPS := "res://assets/props/tavern-v1/%s.glb"
const FLOOR := 0.36
const LOFT := 3.75
## Top of the bar counter and of the tables (Blender table helper: top slab at the given height).
const BAR_TOP := FLOOR + 1.08
const TABLE_TOP := FLOOR + 0.81
const HEARTH_FIRE := Vector3(1.0, FLOOR + 0.5, -8.9)
const FIRE_SOUND := "res://assets/audio/village-v1/fire.ogg"
const RUG_TEXTURE := "res://assets/props/tavern-v1/rugs/fabric_pattern_05_diff_1k.jpg"
const RUG_NORMAL := "res://assets/props/tavern-v1/rugs/fabric_pattern_05_nor_1k.jpg"

## [model, position, yaw degrees, scale]
const PLACED := [
	# The bar: bottles, goblets, a jug and bread; bottles on the shelf behind it.
	["wine_bottles_01", Vector3(2.8, BAR_TOP, 0.4), 90.0, 1.0],
	["brass_goblets", Vector3(2.75, BAR_TOP, -1.9), 0.0, 1.0],
	["jug_01", Vector3(2.85, BAR_TOP, -3.3), 30.0, 1.0],
	["hamburger_buns", Vector3(4.7, BAR_TOP, 1.5), 0.0, 1.0],
	["wine_bottles_01", Vector3(6.0, FLOOR + 0.78, -0.4), 90.0, 0.9],
	["wine_bottles_01", Vector3(6.0, FLOOR + 1.53, -2.4), 90.0, 0.9],
	["jug_01", Vector3(6.0, FLOOR + 1.53, -0.6), 0.0, 1.0],
	["wine_barrel_01", Vector3(5.4, FLOOR, 3.3), 90.0, 1.0],
	# Stools along the bar.
	["wooden_stool_01", Vector3(1.9, FLOOR, 0.2), 0.0, 1.0],
	["wooden_stool_01", Vector3(1.9, FLOOR, -1.6), 40.0, 1.0],
	["wooden_stool_01", Vector3(1.9, FLOOR, -3.4), 10.0, 1.0],
	# Food on the tables.
	["carved_wooden_plate", Vector3(-3.4, TABLE_TOP, 7.3), 0.0, 1.0],
	["food_apple_01", Vector3(-3.25, TABLE_TOP, 6.6), 0.0, 1.0],
	["hamburger_buns", Vector3(-0.2, TABLE_TOP, 6.5), 0.0, 1.0],
	["brass_goblets", Vector3(-0.3, TABLE_TOP, 5.7), 60.0, 1.0],
	["carved_wooden_plate", Vector3(-0.2, TABLE_TOP, 3.1), 0.0, 1.0],
	["yellow_onion", Vector3(-0.05, TABLE_TOP, 2.4), 0.0, 1.0],
	["jug_01", Vector3(-3.35, TABLE_TOP, 3.2), 0.0, 1.0],
	["wooden_bowl_01", Vector3(-0.2, TABLE_TOP, -0.9), 0.0, 1.0],
	# By the hearth: baskets of onions, a bucket.
	["wicker_basket_01", Vector3(-0.9, FLOOR, -8.5), 20.0, 1.0],
	["yellow_onion", Vector3(-0.9, FLOOR + 0.25, -8.5), 0.0, 1.0],
	["wooden_bucket_01", Vector3(3.0, FLOOR, -8.8), 0.0, 1.0],
	# The loft: a barrel of water and baskets by the beds.
	["wooden_bucket_01", Vector3(-2.2, LOFT, -1.0), 0.0, 1.0],
	["wicker_basket_01", Vector3(2.2, LOFT, 7.9), 0.0, 1.0],
]
## Candlesticks with a small glowing flame on three tables (no light of their own: phones count lights).
const CANDLES := [Vector3(-3.55, TABLE_TOP, 6.9), Vector3(-0.35, TABLE_TOP, 2.8), Vector3(-3.55, TABLE_TOP, 3.9)]
## Lanterns: hanging under the hall ceiling, standing on loft chests. Each carries a light.
## The inn's own fill light (village_building.gd) hangs as a lantern at the centre already.
const HANGING := [Vector3(-2.0, 3.05, -5.5), Vector3(-2.0, 3.05, 5.5)]
const STANDING := [Vector3(3.0, LOFT + 0.61, 6.55), Vector3(3.0, LOFT + 0.61, -1.85)]
## Rugs: [centre, size, tint]
const RUGS := [
	[Vector3(1.0, FLOOR + 0.006, -6.3), Vector2(3.4, 1.8), Color(0.78, 0.42, 0.32)],
	[Vector3(0.0, FLOOR + 0.006, 8.4), Vector2(2.6, 1.6), Color(0.7, 0.55, 0.38)],
	[Vector3(0.0, LOFT + 0.006, 0.0), Vector2(1.4, 8.0), Color(0.62, 0.36, 0.3)],
]

var fire_light: OmniLight3D
var flames: CPUParticles3D
var _time := 0.0

func build() -> void:
	for item in PLACED:
		_place(item[0], item[1], item[2], item[3])
	for at in CANDLES:
		_place("wooden_candlestick", at, 0.0, 1.0)
		_candle_flame(at + Vector3(0, 0.27, 0))
	for at in HANGING:
		_lantern(at, true)
	for at in STANDING:
		_lantern(at, false)
	for rug in RUGS:
		_rug(rug[0], rug[1], rug[2])
	_hearth_fire()

func _place(model: String, at: Vector3, yaw: float, scale_factor: float) -> Node3D:
	var scene: PackedScene = load(PROPS % model)
	var node: Node3D = scene.instantiate()
	node.name = model
	node.position = at
	node.rotation.y = deg_to_rad(yaw)
	node.scale = Vector3.ONE * scale_factor
	add_child(node)
	for mesh in node.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).visibility_range_end = 40.0
	return node

func _lantern(at: Vector3, hanging: bool) -> void:
	_place("wooden_lantern_01", at, 0.0, 1.0)
	if hanging:
		var rope := MeshInstance3D.new()
		rope.name = "LanternRope"
		var box := BoxMesh.new()
		box.size = Vector3(0.02, 3.7 - at.y - 0.35, 0.02)
		rope.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.18, 0.1)
		rope.material_override = mat
		rope.position = at + Vector3(0, 0.35 + box.size.y * 0.5, 0)
		add_child(rope)
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.position = at + Vector3(0, 0.18, 0)
	light.omni_range = 7.5 if hanging else 9.0
	light.light_energy = 0.8 if hanging else 1.3
	light.light_color = Color(1.0, 0.76, 0.5)
	add_child(light)

func _candle_flame(at: Vector3) -> void:
	var flame := MeshInstance3D.new()
	flame.name = "CandleFlame"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.11)
	flame.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _flame()
	mat.albedo_color = Color(1.0, 0.72, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	mat.emission_energy_multiplier = 2.0
	flame.material_override = mat
	flame.position = at
	add_child(flame)

func _rug(centre: Vector3, size: Vector2, tint: Color) -> void:
	var rug := MeshInstance3D.new()
	rug.name = "Rug"
	var plane := PlaneMesh.new()
	plane.size = size
	rug.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(RUG_TEXTURE)
	mat.normal_enabled = true
	mat.normal_texture = load(RUG_NORMAL)
	mat.albedo_color = tint
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(size.x / 1.2, size.y / 1.2, 1)
	rug.material_override = mat
	rug.position = centre
	add_child(rug)

## Flames from particles (cheap on phones), a warm light that flickers, the village fire loop.
func _hearth_fire() -> void:
	flames = CPUParticles3D.new()
	flames.name = "HearthFlames"
	flames.position = HEARTH_FIRE
	flames.amount = 36
	flames.lifetime = 0.7
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(0.5, 0.05, 0.25)
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.gravity = Vector3(0, 1.6, 0)
	flames.initial_velocity_min = 0.3
	flames.initial_velocity_max = 0.7
	flames.scale_amount_min = 0.7
	flames.scale_amount_max = 1.2
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0.6))
	fade.add_point(Vector2(0.3, 1.0))
	fade.add_point(Vector2(1, 0.0))
	flames.scale_amount_curve = fade
	var colours := Gradient.new()
	colours.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	colours.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
	colours.add_point(0.4, Color(1.0, 0.45, 0.08, 0.9))
	flames.color_ramp = colours
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _flame()
	quad.material = mat
	flames.mesh = quad
	add_child(flames)
	fire_light = OmniLight3D.new()
	fire_light.name = "HearthLight"
	fire_light.position = HEARTH_FIRE + Vector3(0, 0.6, -0.7)
	fire_light.omni_range = 10.0
	fire_light.light_energy = 2.0
	fire_light.light_color = Color(1.0, 0.55, 0.25)
	fire_light.shadow_enabled = false
	add_child(fire_light)
	var crackle := AudioStreamPlayer3D.new()
	crackle.name = "HearthSound"
	var stream: AudioStream = load(FIRE_SOUND)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	crackle.stream = stream
	crackle.bus = "VillageSound" if AudioServer.get_bus_index("VillageSound") >= 0 else "Master"
	crackle.max_distance = 16.0
	crackle.unit_size = 2.5
	crackle.volume_db = -7.0
	crackle.position = HEARTH_FIRE
	crackle.autoplay = true
	add_child(crackle)

var _flame_cache: ImageTexture

func _flame() -> ImageTexture:
	if _flame_cache == null:
		_flame_cache = _flame_texture()
	return _flame_cache

## A soft round flame drawn once: bright middle, fading edges.
func _flame_texture() -> ImageTexture:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5) / size - 0.5, (y + 0.5) / size - 0.5)
			p.y *= 0.75
			var a := clampf(1.0 - p.length() * 2.2, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(image)

func _process(delta: float) -> void:
	if fire_light == null:
		return
	_time += delta
	fire_light.light_energy = 1.8 + 0.35 * sin(_time * 9.1) + 0.2 * sin(_time * 23.7 + 1.3)
