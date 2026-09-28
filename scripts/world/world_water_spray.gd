extends Node3D
## WATER-01 (owner 27 Sep: water that splashes where it falls and hits the stones): white spray over
## the rapids - river stretches where the bed falls fast. Only the NEAREST rapids within REACH of
## the hero spray (a pool of particle emitters moved between them), so it stays cheap on a phone.
const REACH := 70.0
const NEAREST := 6
const STEEP := 0.6
const SPACING := 10.0

var world: Node3D
var _rapids: Array[Vector3] = []
var _pool: Array[CPUParticles3D] = []
var _tick := 0.0


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
	print("WORLD_WATER_SPRAY rapids=%d" % _rapids.size())


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
	fade.set_color(0, Color(1, 1, 1, 0.55))
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
	material.albedo_color = Color(0.92, 0.95, 0.97)
	# WATER-02: right in front of the camera a drop filled the view as a big white blur; it fades out.
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	material.distance_fade_min_distance = 1.5
	material.distance_fade_max_distance = 5.0
	quad.material = material
	spray.mesh = quad
	return spray


## A soft round dot (owner: the spray was square pixels).
static func _soft_dot() -> Texture2D:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
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
	var hero: Vector3 = world.world_root.to_local(world.player.global_position)
	var near: Array = []
	for at in _rapids:
		var d := at.distance_to(hero)
		if d < REACH:
			near.append([d, at])
	near.sort_custom(func(a, b): return a[0] < b[0])
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
