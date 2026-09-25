extends Node3D
## GRASS-02 (D-084): blade grass over the whole village, streamed in 7.5 m chunks around the camera.
## Dense by the camera, thinning to a fifth by 30 m (shader), nothing past ~36 m; the ground
## under it already has the grass tone, so the edge does not show. No grass on paths, in yards,
## at the well. The "Grass" setting (0-100 %) scales the density; 0 turns it off.
## Each chunk is built from the same seed every time, so grass never jumps when it streams back.
const CHUNK := 7.5
## The "Grass distance" setting moves these together: fade to a fifth by `reach`,
## chunks streamed within reach + 6 m, dropped past reach + 15 m (defaults for 30 m).
var RADIUS := 36.0
var DROP_RADIUS := 45.0
## Clumps per square metre at 100 %.
const DENSITY := 8.0
## Streaming: at most one chunk per frame (a chunk costs a few ms on the phone), checked every TICK.
const BUILDS_PER_TICK := 1
const TICK := .05
## Ground height/colour are sampled on this grid per chunk and interpolated for the clumps.
const SAMPLES := 7
const SEED := 83092501
var FADE_START := 12.0
var FADE_END := 30.0
var world: Node3D
var density := 1.0
var material: ShaderMaterial
var mesh: ArrayMesh
var chunks := {}
var extent := Rect2()
var _segments: Array = []
var _yards: Array[Rect2] = []
var _well := Vector2.ZERO
var _tick := 0.0

func configure(scene: Node3D, amount: float = 1.0, reach: float = 30.0) -> void:
	world = scene
	var layout: Dictionary = world.terrain.data
	var origin: Vector2 = world.terrain.ORIGIN
	extent = Rect2(-origin, Vector2(layout.extent_m[0], layout.extent_m[1]))
	_well = Vector2(layout.well.x, layout.well.y) - origin
	for segment in world.terrain.segments:
		_segments.append(segment)
	for record in layout.buildings:
		var yard: Array = record.yard
		_yards.append(Rect2(Vector2(yard[0], yard[1]) - origin, Vector2(yard[2], yard[3])).grow(.3))
	material = ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/village_grass_blades.gdshader")
	material.set_shader_parameter("far_share", .2)
	mesh = _blade_clump()
	mesh.surface_set_material(0, material)
	_apply_reach(reach)
	density = -1.0
	set_density(amount)

## Grass distance setting (15-45 m); rebuilds the chunks so their visibility matches.
func set_reach(reach: float) -> void:
	reach = clampf(reach, 15.0, 45.0)
	if is_equal_approx(reach, FADE_END):
		return
	_apply_reach(reach)
	var amount := density
	density = -1.0
	set_density(amount)

func _apply_reach(reach: float) -> void:
	FADE_END = clampf(reach, 15.0, 45.0)
	FADE_START = FADE_END * .4
	RADIUS = FADE_END + 6.0
	DROP_RADIUS = FADE_END + 15.0
	material.set_shader_parameter("fade_start", FADE_START)
	material.set_shader_parameter("fade_end", FADE_END)

func set_density(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if is_equal_approx(amount, density):
		return
	density = amount
	for key in chunks.keys():
		chunks[key].queue_free()
	chunks.clear()
	_tick = 0.0
	stream(12)

func _process(delta: float) -> void:
	if world == null:
		return
	var atmosphere: Node = world.atmosphere
	if atmosphere != null:
		material.set_shader_parameter("effect_time", atmosphere.effect_time)
		material.set_shader_parameter("wind_strength", float(atmosphere.current.wind))
		material.set_shader_parameter("wetness", atmosphere.wetness)
	_tick += delta
	if _tick >= TICK:
		_tick = 0.0
		stream(BUILDS_PER_TICK)

func _focus() -> Vector2:
	var camera: Camera3D = world.camera_rig.get_camera() if world.camera_rig != null else null
	var at: Vector3 = camera.global_position if camera != null else world.player.global_position
	return Vector2(at.x, at.z)

## Build missing chunks near the camera (nearest first, at most `budget`), drop far ones.
func stream(budget: int) -> void:
	if density <= 0.0:
		return
	var focus := _focus()
	for key in chunks.keys():
		if _chunk_center(key).distance_to(focus) > DROP_RADIUS:
			chunks[key].queue_free()
			chunks.erase(key)
	var wanted: Array = []
	var span := int(ceil(RADIUS / CHUNK))
	var middle := Vector2i(floori(focus.x / CHUNK), floori(focus.y / CHUNK))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := middle + Vector2i(dx, dz)
			if chunks.has(key):
				continue
			var d := _chunk_center(key).distance_to(focus)
			if d <= RADIUS and extent.intersects(Rect2(Vector2(key) * CHUNK, Vector2(CHUNK, CHUNK))):
				wanted.append([d, key])
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(mini(budget, wanted.size())):
		var key: Vector2i = wanted[i][1]
		chunks[key] = _build_chunk(key)

func _chunk_center(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(.5, .5)) * CHUNK

## Where the clumps of one chunk stand (village frame), before the density setting.
## Same seed every time; also used by the checks (headless builds keep no MultiMesh data).
func chunk_points(key: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED ^ (key.x * 73856093) ^ (key.y * 19349663)
	var corner := Vector2(key) * CHUNK
	var area := Rect2(corner, Vector2(CHUNK, CHUNK))
	var near_segments: Array = []
	for segment in _segments:
		var box := Rect2(segment.a, Vector2.ZERO).expand(segment.b).grow(float(segment.width) * .5 + 1.5)
		if box.intersects(area):
			near_segments.append(segment)
	var yards: Array[Rect2] = []
	for yard in _yards:
		if yard.intersects(area):
			yards.append(yard)
	var step := 1.0 / sqrt(DENSITY)
	var result: Array = []
	var x := corner.x
	while x < corner.x + CHUNK:
		var z := corner.y
		while z < corner.y + CHUNK:
			var point := Vector2(x + rng.randf() * step, z + rng.randf() * step)
			var keep := rng.randf()
			var size := rng.randf_range(.8, 1.2)
			var tall := size * rng.randf_range(.8, 1.15)
			var turn := rng.randf_range(-PI, PI)
			var variation := rng.randf()
			z += step
			if not extent.has_point(point) or point.distance_to(_well) < 4.8:
				continue
			var blocked := false
			for yard in yards:
				if yard.has_point(point):
					blocked = true
					break
			if blocked:
				continue
			var margin := INF
			for segment in near_segments:
				var closest := Geometry2D.get_closest_point_to_segment(point, segment.a, segment.b)
				margin = minf(margin, point.distance_to(closest) - float(segment.width) * .5)
			if margin < .1:
				continue
			size *= lerpf(.45, 1.0, smoothstep(.1, 1.4, margin))
			result.append({"point": point, "keep": keep, "size": size, "tall": tall, "turn": turn, "variation": variation})
		x += step
	return result

func _build_chunk(key: Vector2i) -> Node3D:
	var center := Vector3(_chunk_center(key).x, 0, _chunk_center(key).y)
	var corner := Vector2(key) * CHUNK
	var cell := CHUNK / float(SAMPLES - 1)
	var heights := PackedFloat32Array()
	var colors := PackedColorArray()
	for j in range(SAMPLES):
		for i in range(SAMPLES):
			var at := corner + Vector2(i, j) * cell
			heights.append(world.terrain.height_at(at.x, at.y))
			colors.append(world.terrain.color_at(at.x, at.y))
	var buffer := PackedFloat32Array()
	var count := 0
	for clump in chunk_points(key):
		if clump.keep > density:
			continue
		var point: Vector2 = clump.point
		var g := ((point - corner) / cell).clamp(Vector2.ZERO, Vector2(SAMPLES - 1.001, SAMPLES - 1.001))
		var i := int(g.x)
		var j := int(g.y)
		var f := g - Vector2(i, j)
		var a := j * SAMPLES + i
		var height: float = lerpf(lerpf(heights[a], heights[a + 1], f.x), lerpf(heights[a + SAMPLES], heights[a + SAMPLES + 1], f.x), f.y)
		var ground: Color = colors[a].lerp(colors[a + 1], f.x).lerp(colors[a + SAMPLES].lerp(colors[a + SAMPLES + 1], f.x), f.y)
		var basis := Basis(Vector3.UP, clump.turn).scaled(Vector3(clump.size, clump.tall, clump.size))
		var origin := Vector3(point.x, height, point.y) - center
		buffer.append_array([basis.x.x, basis.y.x, basis.z.x, origin.x, basis.x.y, basis.y.y, basis.z.y, origin.y, basis.x.z, basis.y.z, basis.z.z, origin.z, ground.r, ground.g, ground.b, clump.variation])
		count += 1
	var batch := MultiMeshInstance3D.new()
	batch.name = "Grass_%d_%d" % [key.x, key.y]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = count
	if count > 0:
		multi.buffer = buffer
	batch.multimesh = multi
	batch.position = center
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.visibility_range_end = FADE_END + 8.0
	batch.extra_cull_margin = .6
	batch.set_meta("clumps", count)
	add_child(batch)
	return batch

func clump_count() -> int:
	var total := 0
	for batch in chunks.values():
		total += int(batch.get_meta("clumps", 0))
	return total

## Seven tapered blades of 3 triangles; the custom alpha holds a random for the far thinning.
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
