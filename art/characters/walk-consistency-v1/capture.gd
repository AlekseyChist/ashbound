extends Node
## Read-only walk comparison. Both variants retain the owner-selected scale and running art.
const Route = preload("res://scenes/world/forest_route.tscn")
const FACTORS = {"back/run": 1.0 / 0.9, "front/run": 1.0 / 0.9, "side/walk": 0.95, "side/run": 0.9, "left/walk": 0.95, "left/run": 0.9}
var rows: Array[Dictionary] = []

func _ready() -> void:
    _run.call_deferred()

func _run() -> void:
    var route = Route.instantiate()
    add_child(route)
    await get_tree().create_timer(0.4).timeout
    route.reset_route()
    route.player.set_physics_process(false)
    var visual = route.player.get_node("Visual")
    var body: AnimatedSprite3D = visual.get_node("Body")
    var cam: Camera3D = get_viewport().get_camera_3d()
    var camera_transform := cam.global_transform
    var camera_fov := cam.fov
    var original: SpriteFrames = body.sprite_frames
    var revised: SpriteFrames = original.duplicate(true)
    var walk_image := Image.load_from_file("res://art/characters/walk-consistency-v1/walk-atlas.png")
    assert(walk_image != null and walk_image.get_size() == Vector2i(1536, 768))
    var walk_atlas := ImageTexture.create_from_image(walk_image)
    for clip in [&"walk", &"walk_side"]:
        assert(revised.get_frame_count(clip) == 8)
        for i in range(8):
            var tex := AtlasTexture.new()
            tex.atlas = walk_atlas
            tex.region = Rect2((i % 4) * 384, (i / 4) * 384, 384, 384)
            tex.filter_clip = true
            revised.set_frame(clip, i, tex, revised.get_frame_duration(clip, i))
    for variant in ["before", "candidate"]:
        visual.set_appearance_frames(original if variant == "before" else revised)
        var out: String = "user://walk-consistency-comparison/" + variant
        assert(DirAccess.make_dir_recursive_absolute(out) == OK)
        for entry in [["back", Vector3.FORWARD], ["front", Vector3.BACK], ["side", Vector3.RIGHT], ["left", Vector3.LEFT]]:
            for action in [&"idle", &"walk", &"run"]:
                visual.update_visual(action, entry[1])
                var source_pixel_size := body.pixel_size
                var factor := float(FACTORS.get(entry[0] + "/" + String(action), 1.0))
                body.pixel_size *= factor
                body.position.y = float(body.sprite_frames.get_meta("baseline_offset_pixels")) * body.pixel_size
                body.pause()
                for i in range(body.sprite_frames.get_frame_count(body.animation)):
                    body.set_frame_and_progress(i, 0.0)
                    # Let shadow proxies and render materials settle after changing a paused pose.
                    await RenderingServer.frame_post_draw
                    await RenderingServer.frame_post_draw
                    assert(cam.global_transform.is_equal_approx(camera_transform) and is_equal_approx(cam.fov, camera_fov))
                    var label := "%s-%s-%d" % [entry[0], action, i]
                    var tex: AtlasTexture = body.sprite_frames.get_frame_texture(body.animation, i)
                    var image := tex.atlas.get_image()
                    if image.is_compressed():
                        assert(image.decompress() == OK)
                    image.convert(Image.FORMAT_RGBA8)
                    var patch := image.get_region(tex.region)
                    var cell := Image.create(int(tex.get_width()), int(tex.get_height()), false, Image.FORMAT_RGBA8)
                    cell.blit_rect(patch, Rect2i(Vector2i.ZERO, patch.get_size()), Vector2i(tex.margin.position))
                    assert(cell.save_png(out + "/" + label + "-cell.png") == OK)
                    assert(get_viewport().get_texture().get_image().save_png(out + "/" + label + "-game.png") == OK)
                    rows.append({"variant": variant, "view": entry[0], "action": String(action), "frame": i, "clip": body.animation, "source_pixel_size": source_pixel_size, "candidate_factor": factor, "pixel_size": body.pixel_size, "body_y": body.position.y, "camera_position": cam.global_position, "camera_fov": cam.fov})
    assert(rows.size() == 160)
    var f := FileAccess.open("user://walk-consistency-comparison/metrics.json", FileAccess.WRITE)
    assert(f != null)
    f.store_string(JSON.stringify(rows, "  "))
    f.close()
    print("WALK_CONSISTENCY_CAPTURE_OK poses=160 same_camera=1 resources_written=0")
    get_tree().quit()
