extends Node
## GRASS-02 (D-084): blade grass over the whole village, streamed around the camera.
## Chunks near the camera, none far; no grass on paths, in yards or at the well; the same
## layout every time a chunk streams back; the Grass setting (50 %, 0 %) and its save;
## wind reaches the grass; the ground grass stays matte (GRASS-01 variant A).
const Scene = preload("res://scenes/world/world.tscn")
const SETTINGS_QA := "user://village_settings_grass_qa.cfg"
var world: Node3D
var grass: Node3D
var failures: Array[String] = []
var checks := 0

func _ready() -> void: call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("GRASS_FAIL ", label)

func settle(seconds: float = .25) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

func focus() -> Vector2:
	return grass._focus()

func stream_all() -> void:
	for i in 400: grass.stream(grass.BUILDS_PER_TICK)

func run_checks() -> void:
	world = Scene.instantiate()
	add_child(world)
	await settle(.6)
	grass = world.grass
	world.settings.path = SETTINGS_QA
	grass.set_density(1.0)
	check(grass != null and not world.hud.get_node("RootControl").find_child("GrassMode", true, false), "grass without the old test button")
	stream_all()
	var built: int = grass.chunks.size()
	check(built > 20, "chunks around the camera (%d)" % built)
	var near_all := true
	for key in grass.chunks.keys():
		if grass._chunk_center(key).distance_to(focus()) > grass.DROP_RADIUS + .01: near_all = false
	check(near_all, "no chunk beyond the drop radius")
	# Every chunk within the radius and the village is there after streaming.
	var missing := 0
	var span := int(ceil(grass.RADIUS / grass.CHUNK))
	var middle := Vector2i(floori(focus().x / grass.CHUNK), floori(focus().y / grass.CHUNK))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key: Vector2i = middle + Vector2i(dx, dz)
			if grass._chunk_center(key).distance_to(focus()) <= grass.RADIUS and grass.extent.intersects(Rect2(Vector2(key) * grass.CHUNK, Vector2(grass.CHUNK, grass.CHUNK))) and not grass.chunks.has(key):
				missing += 1
	check(missing == 0, "all nearby chunks built (%d missing)" % missing)
	# Placement rules over the streamed area.
	var total := 0
	var on_path := 0
	var in_yard := 0
	var at_well := 0
	var outside := 0
	var drawn := 0
	for key in grass.chunks.keys():
		var points: Array = grass.chunk_points(key)
		var again: Array = grass.chunk_points(key)
		if points.size() != again.size() or (not points.is_empty() and points[0].point != again[0].point):
			check(false, "chunk %s is not repeatable" % key)
		drawn += int(grass.chunks[key].multimesh.instance_count)
		for clump in points:
			var p: Vector2 = clump.point
			total += 1
			var road: Vector2 = world.terrain.road_info(p)
			if road.x - road.y * .5 < .1: on_path += 1
			if world.terrain.reserved(p, 0.0): in_yard += 1
			if p.distance_to(grass._well) < 4.5: at_well += 1
			if not grass.extent.has_point(p): outside += 1
	check(total > 5000, "plenty of grass around the start (%d clumps)" % total)
	# Interpolated roots stay on the ground (sampled grid vs the exact terrain height).
	var worst := 0.0
	var sample_key: Vector2i = grass.chunks.keys()[0]
	for key in grass.chunks.keys():
		var batch: MultiMeshInstance3D = grass.chunks[key]
		if batch.multimesh.instance_count > 0:
			sample_key = key
			break
	var corner: Vector2 = Vector2(sample_key) * grass.CHUNK
	var cell: float = grass.CHUNK / float(grass.SAMPLES - 1)
	for clump in grass.chunk_points(sample_key):
		var p: Vector2 = clump.point
		var g: Vector2 = ((p - corner) / cell).clamp(Vector2.ZERO, Vector2(grass.SAMPLES - 1.001, grass.SAMPLES - 1.001))
		var i := int(g.x)
		var j := int(g.y)
		var f: Vector2 = g - Vector2(i, j)
		var h := func(ii, jj): return world.terrain.height_at(corner.x + ii * cell, corner.y + jj * cell)
		var guess: float = lerpf(lerpf(h.call(i, j), h.call(i + 1, j), f.x), lerpf(h.call(i, j + 1), h.call(i + 1, j + 1), f.x), f.y)
		worst = maxf(worst, absf(guess - world.terrain.height_at(p.x, p.y)))
	check(worst < .08, "grass roots within 8 cm of the ground (worst %.3f m)" % worst)
	check(drawn == total, "at full density every clump is drawn (%d of %d)" % [drawn, total])
	check(on_path == 0, "no grass on paths (%d)" % on_path)
	check(in_yard == 0, "no grass in yards (%d)" % in_yard)
	check(at_well == 0, "no grass at the well (%d)" % at_well)
	check(outside == 0, "grass stays in the village (%d)" % outside)
	for batch: MultiMeshInstance3D in grass.chunks.values():
		if batch.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			check(false, "grass casts no shadows")
			break
	# Streaming follows the camera: far chunks go, new ones come.
	var old_keys: Array = grass.chunks.keys()
	world.player.global_position = Vector3(90, world.terrain.height_at(90, -60) + .2, -60)
	world.camera_rig.snap_to_target()
	await settle(.1)
	stream_all()
	var kept_old := 0
	for key in old_keys:
		if grass.chunks.has(key) and grass._chunk_center(key).distance_to(focus()) > grass.DROP_RADIUS: kept_old += 1
	check(kept_old == 0, "far chunks are dropped")
	check(grass.chunks.size() > 10, "new chunks around the new place")
	world.select_building(0)
	await settle(.1)
	stream_all()
	var full: int = grass.clump_count()
	# The Grass setting.
	world.settings_menu._change("grass", 50.0)
	stream_all()
	var half: int = grass.clump_count()
	check(half > full * .35 and half < full * .65, "Grass at half draws about half (%d of %d)" % [half, full])
	world.settings_menu._change("grass", 0.0)
	stream_all()
	check(grass.chunks.is_empty(), "Grass 0 % turns the grass off")
	check(world.settings.save_settings() == OK, "the setting saves")
	var saved := preload("res://scripts/world/village_settings.gd").new()
	saved.load_settings(SETTINGS_QA)
	check(saved.grass_percent == 0.0, "the saved setting reads back")
	world.settings_menu._change("grass", 100.0)
	stream_all()
	check(grass.clump_count() == full, "Grass back to 100 % restores the same grass")
	# Grass distance (D-088): shorter reach, fewer chunks, the fade follows; saved.
	world.settings_menu._change("grass_distance", 15.0)
	stream_all()
	var short_ok := true
	for key in grass.chunks.keys():
		if grass._chunk_center(key).distance_to(focus()) > grass.DROP_RADIUS + .01: short_ok = false
	check(is_equal_approx(grass.FADE_END, 15.0) and float(grass.material.get_shader_parameter("fade_end")) == 15.0 and short_ok, "Grass distance 15 m shortens the grass")
	check(grass.clump_count() < full, "shorter grass draws fewer clumps (%d of %d)" % [grass.clump_count(), full])
	check(world.settings.save_settings() == OK, "grass distance saves")
	var reread := preload("res://scripts/world/village_settings.gd").new()
	reread.load_settings(SETTINGS_QA)
	check(reread.grass_distance == 15.0, "grass distance reads back")
	world.settings_menu._change("grass_distance", 30.0)
	stream_all()
	# Wind and the matte ground.
	world.atmosphere.set_weather(3, true, true)
	world.atmosphere.advance(3.0)
	await settle(.3)
	check(is_equal_approx(float(grass.material.get_shader_parameter("effect_time")), world.atmosphere.effect_time), "grass follows the wind clock")
	check(not world.atmosphere.foliage_materials.has(grass.material), "tree foliage list keeps only the foliage wind shader")
	var ground: Variant = world.terrain.material.get_shader_parameter("grass_specular")
	check(world.terrain.material.shader.code.contains("grass_specular") and float(ground if ground != null else .06) <= .1, "matte ground grass")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_QA))
	print("GRASS_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
