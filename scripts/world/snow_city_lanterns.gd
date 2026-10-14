extends "res://scripts/world/forest_city_lanterns.gd"
## Reuse accepted post/lantern geometry. Streets and terrain remain book-owned.
const PLAN := "res://assets/world/snow-city-v1/lanterns.json"
const MAX_ACTIVE := 8
var world: Node3D
var timber: Material
var enabled := true
var complete := false
var unresolved: Array[Dictionary] = []
var supports: Array[Dictionary] = []
var _bases: Dictionary = {}

func build(snow_city: Node3D) -> void:
    if world != null:
        push_error("Snow lanterns already built")
        return
    world = snow_city.world
    city = self
    name = "StreetLanterns"
    var wood := StandardMaterial3D.new()
    wood.albedo_texture = load("res://assets/environment/village-house-materials-v1/fine_grained_wood_col_1k.jpg")
    wood.albedo_color = Color(.32,.23,.15)
    wood.roughness = .96
    timber = wood
    _build_after_physics.call_deferred()

func ground_at(at: Vector2) -> Vector3:
    return _bases[at]

func _build_after_physics() -> void:
    # World builds its terrain and stairs in the same frame as the city.
    await get_tree().physics_frame
    await get_tree().physics_frame
    if not is_instance_valid(world): return
    var data = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
    if not data is Dictionary or not data.get("posts") is Array:
        push_error("Snow lantern plan unavailable")
        return
    var space := get_world_3d().direct_space_state
    for spec in data.posts:
        var at := Vector2(float(spec.at[0]),float(spec.at[1]))
        var level: float = world.world_ground(at.x-1000,at.y-1000) if spec.level == null else float(spec.level)
        var desired := Vector3(at.x-1000,level,at.y-1000)
        var query := PhysicsRayQueryParameters3D.create(world.world_root.to_global(desired+Vector3.UP*.4),world.world_root.to_global(desired-Vector3.UP*.4),1)
        var hit := space.intersect_ray(query)
        if hit.is_empty():
            unresolved.append({"label":spec.label,"reason":"no physical support within 0.4m of authored level"})
            continue
        var base: Vector3 = world.world_root.to_local(hit.position)
        _bases[at] = base
        _post(at,Vector2(float(spec.face[0]),float(spec.face[1])))
        posts[-1].name = str(spec.label)
        lights[-1].omni_range = 10.0
        supports.append({"label":spec.label,"base":base,"offset":base.y-level})
    complete = unresolved.is_empty() and posts.size() == data.posts.size()
    _apply(false)
    print("SNOW_LANTERNS placed=%d unresolved=%d" % [posts.size(),unresolved.size()])

func set_lighting_enabled(value: bool) -> void:
    enabled = value
    _apply(_lit)

func _apply(lit: bool) -> void:
    _lit = lit
    var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
    var nearby: Array[Dictionary] = []
    for i in lights.size():
        lights[i].visible = false
        lights[i].shadow_enabled = false
        if not enabled or not lit or camera == null: continue
        var distance := camera.global_position.distance_squared_to(lights[i].global_position)
        if distance < AWAKE*AWAKE:
            nearby.append({"index":i,"distance":distance})
    nearby.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.distance < b.distance)
    for i in mini(MAX_ACTIVE,nearby.size()):
        lights[nearby[i].index].visible = true
