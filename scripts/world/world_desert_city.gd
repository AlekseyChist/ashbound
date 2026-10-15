extends Node3D
## Owned Codex builder. Claude owns PDF plan, lots, walls and world connection.
const PLAN := "res://assets/world/desert-city-v1/plan.json"
const MODULES := {
    "С": {"scene":"res://scenes/buildings/world-architecture-v1/d_cathedral.tscn", "walls":Vector2(30,18)},
    "К": {"scene":"res://scenes/buildings/world-architecture-v1/d_baths.tscn", "walls":Vector2(12,7)},
    "Ш": {"scene":"res://scenes/buildings/world-architecture-v1/d_order_cells.tscn", "walls":Vector2(14,7)},
    "Пп": {"scene":"res://scenes/buildings/world-architecture-v1/d_pilgrim.tscn", "walls":Vector2(12,7)},
    "Ст": {"scene":"res://scenes/buildings/world-architecture-v1/d_courtyard_house.tscn", "walls":Vector2(8,6)},
    "Мт": {"scene":"res://scenes/buildings/world-architecture-v1/d_courtyard_house.tscn", "walls":Vector2(8,6)},
    "к1": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "к2": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "к3": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "к10": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "к11": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "к12": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "к13": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "с1": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_6x5.tscn", "walls":Vector2(6,5)},
    "с2": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_6x5.tscn", "walls":Vector2(6,5)},
    "с10": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_7x6.tscn", "walls":Vector2(7,6)},
    "с11": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_7x6.tscn", "walls":Vector2(7,6)},
    "с12": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_7x6.tscn", "walls":Vector2(7,6)},
    "д1": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_6x5.tscn", "walls":Vector2(6,5)},
    "д10": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_6x5.tscn", "walls":Vector2(6,5)},
    "д30": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_6x6.tscn", "walls":Vector2(6,6)},
    "д31": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_6x6.tscn", "walls":Vector2(6,6)},
    "д40": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_6x5.tscn", "walls":Vector2(6,5)},
    "д41": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_6x5.tscn", "walls":Vector2(6,5)},
    "д50": {"scene":"res://scenes/buildings/world-architecture-v1/d_home_6x5.tscn", "walls":Vector2(6,5)},
    "пр1": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "пр2": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "пр3": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "пр10": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "пр11": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
    "пр12": {"scene":"res://scenes/buildings/world-architecture-v1/d_poor_home_6x5.tscn", "walls":Vector2(6,5)},
}
var placed: Array[Dictionary] = []
var unresolved: Array[Dictionary] = []
var doors: Array[Node3D] = []
var world: Node3D
var lighting_enabled := true
var _built := false
func _instantiate(path: String) -> Node3D:
    if not ResourceLoader.exists(path):return null
    var scene := load(path) as PackedScene
    return scene.instantiate() as Node3D if scene != null else null
func build(world_node: Node3D, plan_path := PLAN) -> bool:
    if _built:return false
    if world_node == null:return false
    var lots = world_node.get("snow_lots")
    if lots == null or not lots.has_method("level_of"):return false
    var source = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
    if not source is Dictionary or not source.get("buildings") is Array:return false
    var codes := {}
    # Validate the entire input before creating any models.
    for plot in source.buildings:
        if not plot is Dictionary:return false
        for key in ["code","x","z","w","d","yaw"]:
            if not plot.has(key):return false
        var code := str(plot.code)
        if code.is_empty() or codes.has(code):return false
        codes[code] = true
        for key in ["x","z","w","d","yaw"]:
            if not (plot[key] is float or plot[key] is int) or not is_finite(float(plot[key])):return false
        if float(plot.w) <= 0 or float(plot.d) <= 0:return false
    _built = true
    world = world_node
    name = "DesertCity"
    for plot in source.buildings:
        var code := str(plot.code)
        if not MODULES.has(code):
            unresolved.append({"code":code,"reason":"dedicated model pending"})
            continue
        var spec: Dictionary = MODULES[code]
        if not Vector2(float(plot.w),float(plot.d)).is_equal_approx(spec.walls):
            unresolved.append({"code":code,"reason":"wall footprint mismatch"})
            continue
        # Never use snow's overlapping code or resample terrain under its authored clearance.
        var level := float(lots.level_of(code,"desert"))
        if not is_finite(level):
            unresolved.append({"code":code,"reason":"authored desert level unavailable"})
            continue
        var model := _instantiate(spec.scene)
        if model == null:
            unresolved.append({"code":code,"reason":"scene unavailable"})
            continue
        model.name = code
        model.position = Vector3(float(plot.x)-1000,level,float(plot.z)-1000)
        model.rotation.y = -deg_to_rad(float(plot.yaw))
        model.set_meta("desert_book_plot",plot.duplicate(true))
        add_child(model)
        placed.append({"code":code,"plot":plot,"node":model,"floor":level})
        for portal in model.find_children("*","Node3D",true,false):
            if portal.has_method("can_interact") and portal.has_method("target_point") and portal.has_method("set_highlight"):
                doors.append(portal)
        if model.has_method("set_interior_lights_enabled"):
            model.set_interior_lights_enabled(lighting_enabled)
    return true
func get_doors() -> Array[Node3D]:return doors.duplicate()
func nearest_usable_door(actor: CharacterBody3D) -> Node3D:
    if actor == null:return null
    var nearest: Node3D
    var distance := INF
    for portal in doors:
        if not is_instance_valid(portal) or not portal.can_interact(actor):continue
        var candidate: float = actor.global_position.distance_squared_to(portal.target_point())
        if candidate < distance:
            distance = candidate
            nearest = portal
    return nearest
func clear_door_highlights() -> void:
    for portal in doors:
        if is_instance_valid(portal):portal.set_highlight(false)
func set_lighting_enabled(enabled: bool) -> void:
    lighting_enabled = enabled
    for item in placed:
        if item.node.has_method("set_interior_lights_enabled"):
            item.node.set_interior_lights_enabled(enabled)
func _process(_delta: float) -> void:
    if world == null:return
    var actor = world.get("player")
    if not actor is Node3D:return
    for item in placed:
        var model: Node3D = item.node
        if not model.has_method("set_interior_visible"):continue
        var point := model.to_local(actor.global_position)
        var plot: Dictionary = item.plot
        var occupied := absf(point.x) < float(plot.w)*.5+.3 and absf(point.z) < float(plot.d)*.5+.3 and point.y > -.1 and point.y < 11
        model.set_interior_visible(Vector2(point.x,point.z).length() < 45,occupied)