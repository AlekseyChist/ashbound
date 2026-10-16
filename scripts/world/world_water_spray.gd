extends Node3D
## WATER-01 (owner 27 Sep: water that splashes where it falls and hits the stones): white spray over
## the rapids - river stretches where the bed falls fast. Only the NEAREST rapids within REACH of
## the hero spray (a pool of particle emitters moved between them), so it stays cheap on a phone.
const REACH := 70.0
const NEAREST := 6
const STEEP := 0.6
const SPACING := 10.0

## WORLD-BUILD-01D (the book's W5, the Steam Rapids below the Spring Cave - a hot stream): steam over
## its falls, slow rising wisps (map 1412/640, its east river within W5_REACH).
const W5 := Vector2(1412 - 1000, 640 - 1000)
const W5_REACH := 18.0

var world: Node3D
var _rapids: Array[Vector3] = []
var _steam: Array[CPUParticles3D] = []
var _pool: Array[CPUParticles3D] = []
var _tick := 0.0
## FALLS-SPRAY-ART-01 (Codex 450): unshaded, the drops and the steam burned white at night like lamps;
## their colour now follows the day's light (moonlit at night), every half second with the rest.
const SPRAY_WHITE := Color(0.92, 0.95, 0.97)
const NIGHT_LIGHT := 0.24
var _materials: Array[StandardMaterial3D] = []


func configure(scene: Node3D) -> void:
	world = scene
	for river in world.world_layout.rivers:
		var points: Array = river.world_points
		var last := Vector3.INF
		for i in range(2, points.size() - 2):
			var a: Array = points[i - 2]
			var b: Array = points[i + 2]
			var run := Vector2(float(b[0]) - float(a[0]), float(b[2]) - float(a[2])).length()
			# WATER-02: the same measure as the ribbon's rapids (from 12 %, full at 42 %); the natural
			# rivers made nearly every mountain stretch spray under the old one (from 3 %, full at 15 %).
			var steep := (absf(float(b[1]) - float(a[1])) / maxf(run, 0.1) - 0.12) / 0.3
			if steep < STEEP:
				continue
			var p: Array = points[i]
			var at := Vector3(float(p[0]), float(p[1]) + 0.1, float(p[2]))
			if at.distance_to(last) < SPACING:
				continue
			_rapids.append(at)
			last = at
	for n in NEAREST:
		var spray := _emitter()
		world.world_root.add_child(spray)
		_pool.append(spray)
	# the W5 steam: an emitter over each of its pools (every 10 m of the east river by the falls)
	for river in world.world_layout.rivers:
		if str(river.id) != "east":
			continue
		var last := Vector3.INF
		for p in river.world_points:
			var at := Vector3(float(p[0]), float(p[1]) + 0.3, float(p[2]))
			if Vector2(at.x, at.z).distance_to(W5) > W5_REACH or at.distance_to(last) < SPACING:
				continue
			last = at
			var steam := _steam_emitter()
			steam.position = at
			world.world_root.add_child(steam)
			_steam.append(steam)
	print("WORLD_WATER_SPRAY rapids=%d steam=%d" % [_rapids.size(), _steam.size()])


func _emitter() -> CPUParticles3D:
	var spray := CPUParticles3D.new()
	spray.amount = 40
	spray.lifetime = 1.1
	spray.emitting = false
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spray.emission_sphere_radius = 2.2
	spray.direction = Vector3.UP
	spray.spread = 35.0
	spray.initial_velocity_min = 0.8
	spray.initial_velocity_max = 2.2
	spray.gravity = Vector3(0, -4.0, 0)
	spray.scale_amount_min = 0.15
	spray.scale_amount_max = 0.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.4))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	spray.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _soft_dot()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = SPRAY_WHITE
	_materials.append(material)
	# WATER-02: right in front of the camera a drop filled the view as a big white blur; it fades out.
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	material.distance_fade_min_distance = 1.5
	material.distance_fade_max_distance = 5.0
	quad.material = material
	spray.mesh = quad
	return spray


## Steam: few large soft wisps rising slowly and spreading, warm white.
func _steam_emitter() -> CPUParticles3D:
	var steam := _emitter()
	steam.amount = 28
	steam.lifetime = 4.0
	steam.emission_sphere_radius = 3.0
	steam.spread = 20.0
	steam.initial_velocity_min = 0.3
	steam.initial_velocity_max = 0.7
	steam.gravity = Vector3(0, 0.25, 0)
	steam.scale_amount_min = 3.0
	steam.scale_amount_max = 6.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.25, Color(1, 1, 1, 0.34))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	steam.color_ramp = fade
	steam.emitting = false
	return steam


## A soft round dot (owner: the spray was square pixels).
static func _soft_dot() -> Texture2D:
	# a soft falloff (FALLS-SPRAY-ART-01: an even disc read as bokeh balls): dense only at the centre
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
	var dot := GradientTexture2D.new()
	dot.gradient = ramp
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	return dot


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or world == null or _rapids.is_empty():
		return
	_tick = 0.5
	_follow_light()
	var hero: Vector3 = world.world_root.to_local(world.player.global_position)
	var near: Array = []
	for at in _rapids:
		var d := at.distance_to(hero)
		if d < REACH:
			near.append([d, at])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for steam in _steam:
		steam.emitting = steam.position.distance_to(hero) < REACH * 1.5
	for n in _pool.size():
		var spray := _pool[n]
		if n < near.size():
			var at: Vector3 = near[n][1]
			if spray.position.distance_to(at) > 0.5:
				spray.position = at
				spray.restart()
			spray.emitting = true
		else:
			spray.emitting = false


func _follow_light() -> void:
	var atmosphere: Node = world.get("atmosphere")
	if atmosphere == null:
		return
	var light := lerpf(NIGHT_LIGHT, 1.0, clampf(float(atmosphere.get("daylight")), 0.0, 1.0))
	var colour := Color(SPRAY_WHITE.r * light, SPRAY_WHITE.g * light, SPRAY_WHITE.b * light)
	for material in _materials:
		material.albedo_color = colour
