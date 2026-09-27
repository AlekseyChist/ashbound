extends Node3D
## SAND-01 (owner 27 Sep: small sandstorms in the wind): in the desert, when the wind blows, one or
## two whirls of sand spin up 25-70 m from the hero, drift with the wind and die down after a while.
const MAX_DEVILS := 2
const LIFE := Vector2(9.0, 16.0)
const WIND_DIR := Vector2(0.85, 0.53)

var world: Node3D
var _devils: Array = []   # [emitter, age, life]
var _cooldown := 2.0
var _rng := RandomNumberGenerator.new()


func configure(scene: Node3D) -> void:
	world = scene
	_rng.seed = 270928


func _emitter() -> CPUParticles3D:
	var dust := CPUParticles3D.new()
	dust.amount = 140
	dust.lifetime = 3.6
	dust.local_coords = true
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = 1.2
	dust.emission_ring_inner_radius = 0.3
	dust.emission_ring_height = 0.2
	dust.direction = Vector3.UP
	dust.spread = 12.0
	dust.initial_velocity_min = 2.5
	dust.initial_velocity_max = 5.0
	dust.gravity = Vector3(0, 0.3, 0)
	# The spin: speed around the axis and a pull towards it, widening as it rises.
	dust.orbit_velocity_min = 0.5
	dust.orbit_velocity_max = 0.9
	dust.radial_accel_min = 0.6
	dust.radial_accel_max = 1.4
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 2.4
	var fade := Gradient.new()
	fade.set_color(0, Color(0.6, 0.48, 0.32, 0.0))
	fade.add_point(0.15, Color(0.6, 0.48, 0.32, 0.55))
	fade.set_color(fade.get_point_count() - 1, Color(0.7, 0.6, 0.42, 0.0))
	dust.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	quad.material = material
	dust.mesh = quad
	return dust


func _process(delta: float) -> void:
	if world == null or world.atmosphere == null:
		return
	var windy: float = float(world.atmosphere.current.get("wind", 0.0))
	var hot: float = world.atmosphere.heat
	for devil in _devils.duplicate():
		devil[1] += delta
		var dust: CPUParticles3D = devil[0]
		var drift := WIND_DIR * (1.5 + 3.0 * windy) * delta
		dust.global_position += Vector3(drift.x, 0.0, drift.y)
		dust.global_position.y = world.grass_height(dust.global_position.x, dust.global_position.z)
		if devil[1] > devil[2]:
			dust.emitting = false
		if devil[1] > devil[2] + dust.lifetime:
			dust.queue_free()
			_devils.erase(devil)
	_cooldown -= delta
	if _cooldown > 0.0 or hot < 0.6 or windy < 0.15 or _devils.size() >= MAX_DEVILS:
		return
	_cooldown = _rng.randf_range(4.0, 10.0)
	var around := Vector2.from_angle(_rng.randf_range(-PI, PI)) * _rng.randf_range(25.0, 70.0)
	var at: Vector3 = world.player.global_position + Vector3(around.x, 0.0, around.y)
	if world.ground_kind(at.x, at.z) != "sand":
		return
	var dust := _emitter()
	add_child(dust)
	dust.global_position = Vector3(at.x, world.grass_height(at.x, at.z), at.z)
	dust.emitting = true
	_devils.append([dust, 0.0, _rng.randf_range(LIFE.x, LIFE.y)])
