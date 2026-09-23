extends Node
## Read-only comparison of current art. Candidate corrections affect this capture only.
const Route = preload("res://scenes/world/forest_route.tscn")
const FACTORS = {"back/run": 1.0 / 0.9, "front/run": 1.0 / 0.9, "side/walk": 0.95, "side/run": 0.9}
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
    for variant in ["before", "candidate"]:
        var out: String = "user://motion-scale-comparison/" + variant
        assert(DirAccess.make_dir_recursive_absolute(out) == OK)
        for entry in [["back", Vector3.FORWARD], ["front", Vector3.BACK], ["side", Vector3.RIGHT]]:
            for action in [&"idle", &"walk", &"run"]:
                visual.update_visual(action, entry[1])
                var source_pixel_size := body.pixel_size
                var factor := float(FACTORS.get(entry[0] + "/" + String(action), 1.0)) if variant == "candidate" else 1.0
                body.pixel_size *= factor
                body.position.y = float(body.sprite_frames.get_meta("baseline_offset_pixels")) * body.pixel_size
                body.pause()
                for i in range(body.sprite_frames.get_frame_count(body.animation)):
                    body.set_frame_and_progress(i, 0.0)
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
    assert(rows.size() == 120)
    var f := FileAccess.open("user://motion-scale-comparison/metrics.json", FileAccess.WRITE)
    assert(f != null)
    f.store_string(JSON.stringify(rows, "  "))
    f.close()
    print("MOTION_SCALE_COMPARISON_OK poses=120 same_camera=1 resources_written=0")
    get_tree().quit()
