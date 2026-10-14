extends Node3D
## PDF141 plots; Claude owns the source plan, terrain and world.gd connection.
const PLAN := "res://assets/world/snow-city-v1/plan.json"
const Door = preload("res://scripts/world/village_door.gd")
# Exact wall footprints and purpose: never stretch a different building into its lot.
const MODULES := {
    "Ск": {"scene":"res://scenes/buildings/world-architecture-v1/s_caravan_store.tscn","walls":Vector2(14,8)},
    "Кн": {"scene":"res://scenes/buildings/world-architecture-v1/s_stables.tscn","walls":Vector2(12,7)},
    "Кх": {"scene":"res://scenes/buildings/world-architecture-v1/s_porters_kitchen.tscn","walls":Vector2(8,6)},
    "Бб": {"scene":"res://scenes/buildings/world-architecture-v1/s_library.tscn","walls":Vector2(10,7)},
    "Лч": {"scene":"res://scenes/buildings/world-architecture-v1/s_infirmary.tscn","walls":Vector2(11,6)},
    "Ал": {"scene":"res://scenes/buildings/world-architecture-v1/s_alchemist.tscn","walls":Vector2(9,6)},
}
var world: Node3D
var placed: Array[Dictionary] = []
var unresolved: Array[Dictionary] = []
var doors: Array[Node3D] = []
var lighting_enabled := true
var _elapsed := 0.0
func build(world_node: Node3D) -> void:
    if world != null:
        push_error("Snow city already built; duplicate placement refused")
        return
    world = world_node
    name = "SnowCity"
    var source = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
    if not source is Dictionary or not source.get("buildings") is Array:
        push_error("Snow city accepted plot data missing/invalid")
        return
    for plot in source.buildings:
        var code := str(plot.code)
        if not MODULES.has(code):
            unresolved.append({"code":code,"reason":"distinct matching module not yet available","plot":plot})
            continue
        var spec: Dictionary = MODULES[code]
        var walls := Vector2(float(plot.w),float(plot.d))
        if not walls.is_equal_approx(spec.walls):
            unresolved.append({"code":code,"reason":"wall footprint mismatch","plot":plot})
            continue
        var packed := load(spec.scene) as PackedScene
        if packed == null:
            unresolved.append({"code":code,"reason":"scene unavailable","plot":plot})
            continue
        var x := float(plot.x)-1000.0
        var z := float(plot.z)-1000.0
        var floor_y: float = world.world_ground(x,z)
        var model := packed.instantiate() as Node3D
        model.name = code
        model.position = Vector3(x,floor_y,z)
        model.rotation.y = -deg_to_rad(float(plot.yaw))
        model.set_meta("snow_book_plot",plot.duplicate(true))
        add_child(model)
        placed.append({"code":code,"plot":plot,"node":model,"floor":floor_y})
        for portal in model.find_children("*","Node3D",true,false):
            if portal.get_script() == Door:
                doors.append(portal)
    print("SNOW_CITY placed=%d unresolved=%d complete=false" % [placed.size(),unresolved.size()])
func get_doors() -> Array[Node3D]:
    return doors.duplicate()
func nearest_usable_door(actor: CharacterBody3D) -> Node3D:
    var nearest: Node3D
    var distance := INF
    if actor == null:
        return null
    for portal in doors:
        if not is_instance_valid(portal) or not portal.can_interact(actor):
            continue
        var candidate: float = actor.global_position.distance_squared_to(portal.target_point())
        if candidate < distance:
            distance = candidate
            nearest = portal
    return nearest
func clear_door_highlights() -> void:
    for portal in doors:
        if is_instance_valid(portal):
            portal.set_highlight(false)
func set_lighting_enabled(enabled: bool) -> void:
    lighting_enabled = enabled
    for item in placed:
        item.node.set_interior_lights_enabled(enabled)
func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed < .5 or world == null or world.get("player") == null:
        return
    _elapsed = 0
    var actor := world.get("player") as Node3D
    if actor == null:
        return
    for item in placed:
        var model: Node3D = item.node
        var point := model.to_local(actor.global_position)
        var plot: Dictionary = item.plot
        var lower := -3.3 if item.code == "Бб" else -.1
        var occupied: bool = absf(point.x) < float(plot.w)*.5+.3 and absf(point.z) < float(plot.d)*.5+.3 and point.y > lower and point.y < 11
        var near: bool = Vector2(point.x,point.z).length() < 32
        model.set_interior_visible(near,occupied)
