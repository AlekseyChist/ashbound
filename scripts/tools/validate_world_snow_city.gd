extends SceneTree
## Use --fixture <script> only for the isolated contract test. Default uses the actual world.
const City = preload("res://scripts/world/world_snow_city.gd")
func _initialize() -> void:
    call_deferred("run")
func fail(message: String) -> void:
    push_error(message)
    quit(1)
func run() -> void:
    var args := OS.get_cmdline_user_args()
    var fixture_index := args.find("--fixture")
    var isolated := fixture_index >= 0 and fixture_index+1 < args.size()
    var world: Node3D
    if isolated:
        var fixture := load(args[fixture_index+1]) as Script
        if fixture == null:fail("Fixture missing");return
        world = fixture.new()
    else:
        world = load("res://scenes/world/world.tscn").instantiate()
    root.add_child(world)
    await physics_frame
    var city := City.new()
    var frame := world.get("world_root") as Node3D
    if frame == null:fail("World root frame missing");return
    frame.add_child(city)
    city.build(world)
    await physics_frame
    if city.placed.size()!=6 or city.unresolved.size()!=35:
        fail("Current six exact modules or explicit unfinished35 plots lost");return
    if city.get_doors().size()!=7:
        fail("Building door or library lower portal missing");return
    var actor := CharacterBody3D.new()
    actor.collision_layer=2
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75;shape.shape=capsule
    actor.add_child(shape);root.add_child(actor)
    for item in city.placed:
        var plot: Dictionary=item.plot
        var model: Node3D=item.node
        if not Vector2(model.position.x+1000,model.position.z+1000).is_equal_approx(Vector2(plot.x,plot.z)) or not is_equal_approx(model.rotation.y,-deg_to_rad(plot.yaw)) or model.scale!=Vector3.ONE:
            fail("Plot moved/rotated incorrectly/stretched: "+item.code);return
    for portal in city.get_doors():
        actor.global_position=portal.to_global(portal.entry+Vector3(0,.875,1.6))
        await physics_frame
        if city.nearest_usable_door(actor)!=portal:
            fail("Door cannot be offered through existing interaction: "+str(portal.get_path()));return
    city.set_lighting_enabled(false)
    for item in city.placed:
        if item.node.lights_enabled:fail("Lighting override lost");return
    city.set_lighting_enabled(true)
    var copy := city.get_doors();copy.clear()
    if city.get_doors().size()!=7:fail("Caller mutated registry");return
    print("SNOW_CITY_CONTRACT_PASS mapped=6 unresolved=35 doors=7 frame=world_root fixture=",isolated," whole_city_ready=false")
    # This interface test never establishes support, street clearance or whole-route acceptance.
    print("SNOW_CITY_PHYSICAL_PLACEMENT_ROUTES_WEATHER_MOBILE=UNVERIFIED")
    quit()
