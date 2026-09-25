extends Node3D
## GRASS-01 probe (D-083): one 30 x 30 m meadow by the first house, in two builds of real grass,
## to compare the look and the phone cost before grass covers the village.
## Mode 0: off (only the old sparse tufts), 1: opaque blade clumps, 2: alpha-cut cards.
const PATCH := Rect2(-6, -12, 30, 30)
const CHUNK := 7.5
const LABELS := ["VILLAGE_GRASS_OFF", "VILLAGE_GRASS_BLADES", "VILLAGE_GRASS_CARDS"]
## Clumps per square metre near the camera; far away the shader keeps only a share of them.
const DENSITY := [0.0, 9.0, 3.2]
const SEED := 83092501
var world: Node3D
var mode := 0
var sets: Array[Node3D] = [null, null, null]
var materials: Array[ShaderMaterial] = []
var button: Button
var clump_counts := [0, 0, 0]
## Where each clump stands (village local), for checks: headless builds do not keep MultiMesh data.
var placed: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]

func configure(scene: Node3D) -> void:
	world = scene
	button = world._button(world.atmosphere.time_button.get_parent(), Vector2(260, 120))
	button.name = "GrassMode"
	button.pressed.connect(func():
		if world.is_input_available(): set_mode((mode + 1) % LABELS.size()))
	Localization.language_changed.connect(_refresh_text)
	_refresh_text()

## Same wind, time and wetness as the rest of the foliage (kept out of the atmosphere's own foliage list).
func _process(_delta: float) -> void:
	var atmosphere: Node = world.atmosphere if world else null
	if atmosphere == null or mode == 0: return
	for material in materials:
		material.set_shader_parameter("effect_time", atmosphere.effect_time)
		material.set_shader_parameter("wind_strength", float(atmosphere.current.wind))
		material.set_shader_parameter("wetness", atmosphere.wetness)

func set_mode(value: int) -> void:
	mode = clampi(value, 0, LABELS.size() - 1)
	if mode > 0 and sets[mode] == null: sets[mode] = _build(mode)
	for i in range(sets.size()):
		if sets[i] != null: sets[i].visible = i == mode
	_refresh_text()

func _refresh_text(_language: String = "") -> void:
	if button != null: button.text = Localization.text(LABELS[mode])

func _build(kind: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Grass" + ["", "Blades", "Cards"][kind]
	add_child(root)
	var material := ShaderMaterial.new()
	if kind == 1:
		material.shader = preload("res://assets/shaders/village_grass_blades.gdshader")
	else:
		material.shader = preload("res://assets/shaders/village_grass_cards.gdshader")
		material.set_shader_parameter("blades_texture", _card_texture())
	# Cards overdraw more, so they thin out a little closer.
	var fade_end := 38.0 if kind == 1 else 34.0
	material.set_shader_parameter("fade_start", fade_end - 20.0)
	material.set_shader_parameter("fade_end", fade_end)
	materials.append(material)
	var mesh := _blade_clump() if kind == 1 else _card_clump()
	mesh.surface_set_material(0, material)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + kind
	var chunks := {}
	var step := 1.0 / sqrt(float(DENSITY[kind]))
	var x := PATCH.position.x
	while x < PATCH.end.x:
		var z := PATCH.position.y
		while z < PATCH.end.y:
			var point := Vector2(x + rng.randf() * step, z + rng.randf() * step)
			z += step
			if world.terrain.reserved(point, .3): continue
			var road: Vector2 = world.terrain.road_info(point)
			var margin: float = road.x - road.y * .5
			if margin < .1: continue
			# The meadow thins out over its last 4 m, so the probe has no hard square edge.
			var inside := minf(minf(point.x - PATCH.position.x, PATCH.end.x - point.x), minf(point.y - PATCH.position.y, PATCH.end.y - point.y))
			var edge := smoothstep(0.0, 4.0, inside)
			if rng.randf() > edge: continue
			var at := Vector3(point.x, world.terrain.height_at(point.x, point.y), point.y)
			# Shorter at the path edge and at the meadow edge, fuller inside.
			var size := rng.randf_range(.8, 1.2) * lerpf(.45, 1.0, smoothstep(.1, 1.4, margin)) * lerpf(.5, 1.0, edge)
			var tall := size * rng.randf_range(.8, 1.15)
			var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(size, tall, size))
			var ground: Color = world.terrain.color_at(point.x, point.y)
			var key := Vector2i(floori(point.x / CHUNK), floori(point.y / CHUNK))
			if not chunks.has(key): chunks[key] = []
			chunks[key].append([Transform3D(basis, at), Color(ground.r, ground.g, ground.b, rng.randf())])
			placed[kind].append(at)
		x += step
	for key: Vector2i in chunks:
		var list: Array = chunks[key]
		var center := Vector3((key.x + .5) * CHUNK, 0, (key.y + .5) * CHUNK)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = mesh
		multi.instance_count = list.size()
		for i in range(list.size()):
			var transform: Transform3D = list[i][0]
			transform.origin -= center
			multi.set_instance_transform(i, transform)
			multi.set_instance_custom_data(i, list[i][1])
		var batch := MultiMeshInstance3D.new()
		batch.name = "Chunk_%d_%d" % [key.x, key.y]
		batch.multimesh = multi
		batch.position = center
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.visibility_range_end = fade_end + 12.0
		batch.extra_cull_margin = .5
		root.add_child(batch)
		clump_counts[kind] += list.size()
	print("VILLAGE_GRASS mode=", kind, " clumps=", clump_counts[kind], " chunks=", chunks.size(), " triangles=", clump_counts[kind] * mesh.surface_get_array_len(0) / 3)
	return root

## Seven tapered blades of 3 triangles; colour red channel = per-blade shade variation.
func _blade_clump() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in range(7):
		var angle := rng.randf() * TAU
		var root := Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0, .14)
		var facing := rng.randf() * TAU
		var across := Vector3(cos(facing), 0, sin(facing))
		var lean := Vector3(-across.z, 0, across.x) * rng.randf_range(.06, .2) + root * .6
		var height := rng.randf_range(.3, .55)
		var width := rng.randf_range(.035, .055)
		var shade := rng.randf()
		var points := [
			[root - across * width, 0.0], [root + across * width, 0.0],
			[root - across * width * .65 + lean * .3 + Vector3.UP * height * .55, .55],
			[root + across * width * .65 + lean * .3 + Vector3.UP * height * .55, .55],
			[root + lean + Vector3.UP * height, 1.0]]
		for triangle in [[0, 1, 2], [1, 3, 2], [2, 3, 4]]:
			for index in triangle:
				tool.set_color(Color(shade, 0, 0))
				tool.set_uv(Vector2(.5, points[index][1]))
				tool.set_normal(Vector3.UP)
				tool.add_vertex(points[index][0])
	return tool.commit()

## Three crossed quads 0.7 x 0.5 m; UV.y 0 at the root.
func _card_clump() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in range(3):
		var angle := float(q) * PI / 3.0
		var across := Vector3(cos(angle), 0, sin(angle)) * .35
		var corners := [[-across, Vector2(0, 0)], [across, Vector2(1, 0)], [across + Vector3.UP * .5, Vector2(1, 1)], [-across + Vector3.UP * .5, Vector2(0, 1)]]
		for index in [0, 1, 2, 0, 2, 3]:
			tool.set_color(Color(float(q) / 3.0, 0, 0))
			tool.set_uv(corners[index][1])
			tool.set_normal(Vector3.UP)
			tool.add_vertex(corners[index][0])
	return tool.commit()

## A painted-looking tuft drawn at start: grey = shade along the blade, alpha = blade shape. Row 0 is the root.
func _card_texture() -> ImageTexture:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	for b in range(16):
		var base := rng.randf_range(.12, .88) * size
		var top := base + rng.randf_range(-.22, .22) * size
		var height := rng.randf_range(.55, .98) * size
		var width := rng.randf_range(2.2, 4.2)
		var shade := rng.randf_range(.55, 1.0)
		for y in range(int(height)):
			var t := float(y) / height
			var center := lerpf(base, top, t * t)
			var half := width * (1.0 - t)
			for x in range(maxi(0, int(center - half - 1)), mini(size, int(center + half + 2))):
				var cover := clampf(half + .5 - absf(float(x) + .5 - center), 0, 1)
				if cover <= 0: continue
				var value := shade * lerpf(.6, 1.0, t)
				image.set_pixel(x, y, Color(value, value, value, maxf(image.get_pixel(x, y).a, cover)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
