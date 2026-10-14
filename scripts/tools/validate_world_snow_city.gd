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
    var city: City
    var frame := world.get("world_root") as Node3D
    if frame == null:fail("World root frame missing");return
    # WB01 now builds this city in world.gd. Inspect that instance; a second
    # overlapping city would hide integration defects and duplicate all physics.
    for property in world.get_property_list():
        if property.name == "snow_city":
            city = world.get("snow_city") as City
            break
    if city == null:
        city = City.new()
        frame.add_child(city)
        city.build(world)
    var city_count := 0
    for child in frame.get_children():
        if child.get_script() == City:city_count += 1
    if city_count!=1:fail("Snow city integration spawned duplicate/missing builders");return
    await physics_frame
    if city.placed.size()!=41 or not city.unresolved.is_empty():
        fail("Expected all41 accepted book plots with matching modules");return
    if city.get_doors().size()!=42:
        fail("Expected42 doors including library lower and tower maintenance portals");return
    for item in city.placed:
        var expected_doors := 0 if item.code=="Др" else (2 if item.code in ["Бб","Бш"] else 1)
        var actual_doors := 0
        for portal in city.get_doors():
            if item.node.is_ancestor_of(portal):actual_doors+=1
        if actual_doors!=expected_doors:
            fail("Missing or duplicate doors on book plot "+str(item.code));return
    var actor := CharacterBody3D.new()
    actor.collision_layer=2
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.75;shape.shape=capsule
    actor.add_child(shape);root.add_child(actor)
    # Compare the placement against the independent serialized design, not the
    # builder's cached floor field or a potentially lowered terrain sample.
    var design_path := "res://assets/world/graybox-v1/layout.json"
    var design_index := args.find("--fixture-design")
    if isolated and design_index>=0 and design_index+1<args.size():
        design_path=args[design_index+1]
    var design = JSON.parse_string(FileAccess.get_file_as_string(design_path))
    if not design is Dictionary or not design.get("snow_lots") is Array:
        fail("Serialized authored floor levels missing");return
    var expected_levels: Dictionary = {}
    for lot in design.snow_lots:expected_levels[str(lot.code)] = float(lot.level)
    for item in city.placed:
        var plot: Dictionary=item.plot
        var model: Node3D=item.node
        if not Vector2(model.position.x+1000,model.position.z+1000).is_equal_approx(Vector2(plot.x,plot.z)) or not is_equal_approx(model.rotation.y,-deg_to_rad(plot.yaw)) or model.scale!=Vector3.ONE:
            fail("Plot moved/rotated incorrectly/stretched: "+item.code);return
        if not expected_levels.has(item.code) or absf(model.position.y-float(expected_levels[item.code]))>.001:
            fail("Building floor followed terrain instead of authored level: "+item.code);return
    for portal in city.get_doors():
        actor.global_position=portal.to_global(portal.entry+Vector3(0,.875,1.6))
        await physics_frame
        if city.nearest_usable_door(actor)!=portal:
            fail("Door cannot be offered through existing interaction: "+str(portal.get_path()));return
    city.set_lighting_enabled(false)
    for item in city.placed:
        if item.node.lights_enabled:fail("Lighting override lost");return
    city.set_lighting_enabled(true)
    # Module visibility follows the real viewport camera. A near budget observer
    # with the game's camera still in the forest legitimately has zero lamps.
    var shadow_camera := Camera3D.new()
    root.add_child(shadow_camera)
    shadow_camera.make_current()
    var visited_shadow_lamps: Dictionary = {}
    for location in [city.placed[0].node.global_position,city.placed[3].node.global_position]:
        shadow_camera.global_position = location + Vector3.UP * 2
        for item in city.placed:item.node.set_interior_visible(true)
        city.set_lighting_enabled(true)
        var observer := shadow_camera.global_position
        city._update_shadow_budget(observer)
        var count := 0
        var eligible := 0
        for light in city.interior_lights:
            if light.is_visible_in_tree() and light.global_position.distance_to(observer)<city.SHADOW_DISTANCE:eligible += 1
            if light.shadow_enabled:
                count += 1
                visited_shadow_lamps[light.get_instance_id()] = true
                if light.global_position.distance_to(observer)>=city.SHADOW_DISTANCE:fail("Far lamp allocated shadows");return
        if count!=mini(city.MAX_SHADOW_LIGHTS,eligible) or count==0:fail("Near shadow allocation missing or over budget");return
    if visited_shadow_lamps.size()<=city.MAX_SHADOW_LIGHTS:fail("Observer movement did not reassign shadows");return
    city._update_shadow_budget(Vector3(10000,10000,10000))
    for light in city.interior_lights:
        if light.shadow_enabled:fail("Distant city kept shadow maps");return
    city.set_lighting_enabled(false)
    for light in city.interior_lights:
        if light.shadow_enabled:fail("Disabled lighting kept shadow maps");return
    city.set_lighting_enabled(true)
    var copy := city.get_doors();copy.clear()
    if city.get_doors().size()!=42:fail("Caller mutated registry");return
    print("SNOW_CITY_CONTRACT_PASS mapped=41 unresolved=0 doors=42 frame=world_root fixture=",isolated," whole_city_ready=false")
    # This interface test never establishes support, street clearance or whole-route acceptance.
    print("SNOW_CITY_PHYSICAL_PLACEMENT_ROUTES_WEATHER_MOBILE=UNVERIFIED")
    quit()
