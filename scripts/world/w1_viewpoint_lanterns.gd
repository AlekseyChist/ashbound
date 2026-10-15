extends "res://scripts/world/forest_city_lanterns.gd"
## W1-NIGHT-READ-01: accepted timber posts and tavern lanterns at the viewpoint.
## Add under world_root and call build(world) after terrain / BookPlaces physics is ready.
## This owns only three supported lights; world geometry and atmosphere remain unchanged.
const PLAN := [
	{"label":"W1TerraceNorth", "at":Vector2(355.8, 383.25), "level":191.25, "face":Vector2(-1,0)},
	{"label":"W1TerraceSouth", "at":Vector2(355.8, 386.75), "level":191.25, "face":Vector2(-1,0)},
	{"label":"W1Arrival", "at":Vector2(360.35, 388.5), "level":191.0, "face":Vector2(-1,0)},
]
var world: Node3D
var timber: Material
var complete := false
var unresolved: Array[Dictionary] = []
var supports: Array[Dictionary] = []
var _bases: Dictionary = {}

func build(scene: Node3D) -> void:
	if world != null:
		return
	world = scene
	city = self
	name = "W1ViewpointLanterns"
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/environment/village-house-materials-v1/fine_grained_wood_col_1k.jpg")
	wood.albedo_color = Color(.32, .23, .15)
	wood.roughness = .96
	timber = wood
	_build_after_physics.call_deferred()

func ground_at(at: Vector2) -> Vector3:
	return _bases[at]

func _build_after_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(world):
		return
	var space := get_world_3d().direct_space_state
	for spec in PLAN:
		var at: Vector2 = spec.at
		var expected := Vector3(at.x - 1000, float(spec.level), at.y - 1000)
		var low := INF
		var high := -INF
		var hits: Array[Dictionary] = []
		for offset in [Vector2.ZERO, Vector2(-.1,-.1), Vector2(.1,-.1), Vector2(-.1,.1), Vector2(.1,.1)]:
			var p := expected + Vector3(offset.x, 0, offset.y)
			var query := PhysicsRayQueryParameters3D.create(world.world_root.to_global(p + Vector3.UP * .4), world.world_root.to_global(p - Vector3.UP * .4), 1)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var local: Vector3 = world.world_root.to_local(hit.position)
			low = minf(low, local.y)
			high = maxf(high, local.y)
			hits.append({"height":local.y, "body":str(hit.collider.get_path())})
		if hits.size() != 5 or high - low > .06:
			unresolved.append({"label":spec.label,"reason":"post footprint lacks level physical support","hits":hits})
			continue
		# The accepted pole embeds 0.4m into its support; its collision starts at the surface.
		_bases[at] = Vector3(expected.x, high, expected.z)
		_post(at, spec.face)
		posts[-1].name = spec.label
		lights[-1].omni_range = 10.0
		supports.append({"label":spec.label,"height":high,"spread":high-low,"hits":hits})
	complete = unresolved.is_empty() and posts.size() == PLAN.size()
	_apply(false)
	print("W1_LANTERNS placed=%d unresolved=%d" % [posts.size(), unresolved.size()])
