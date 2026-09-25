extends Node
## GRASS-01 (D-083): the probe meadow. Three modes, no grass on paths or in yards, sane amount,
## EN/RU button text, wind reaches the grass, and matte grass in the ground shader (variant A).
const Scene = preload("res://scenes/world/world.tscn")
var world: Node3D
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

func instances(kind: int) -> Array:
	var total := 0
	for batch: MultiMeshInstance3D in world.grass.sets[kind].get_children(): total += batch.multimesh.instance_count
	check(total == world.grass.placed[kind].size(), "mode %d: every placed clump is drawn" % kind)
	return Array(world.grass.placed[kind])

func run_checks() -> void:
	var language: String = Localization._preference
	world = Scene.instantiate()
	add_child(world)
	await settle(.6)
	var grass: Node3D = world.grass
	check(grass != null and grass.mode == 1, "starts with blade grass")
	check(grass.button != null and grass.button.get_parent() == world.atmosphere.time_button.get_parent(), "grass button sits in the time/weather row")
	for kind in [1, 2]:
		grass.set_mode(kind)
		check(grass.sets[kind] != null and grass.sets[kind].visible, "mode %d shows its grass" % kind)
		for other in [1, 2]:
			if other != kind and grass.sets[other] != null: check(not grass.sets[other].visible, "mode %d hides mode %d" % [kind, other])
		var points := instances(kind)
		var area: float = grass.PATCH.get_area()
		check(points.size() > area * float(grass.DENSITY[kind]) * .35 and points.size() < area * float(grass.DENSITY[kind]) * 1.05, "mode %d amount %d is plausible" % [kind, points.size()])
		var on_path := 0
		var in_yard := 0
		var outside := 0
		var off_ground := 0
		for p: Vector3 in points:
			var point := Vector2(p.x, p.z)
			var road: Vector2 = world.terrain.road_info(point)
			if road.x - road.y * .5 < .1: on_path += 1
			if world.terrain.reserved(point, .3): in_yard += 1
			if not grass.PATCH.grow(.01).has_point(point): outside += 1
			if absf(p.y - world.terrain.height_at(p.x, p.z)) > .02: off_ground += 1
		check(on_path == 0, "mode %d: no grass on paths (%d)" % [kind, on_path])
		check(in_yard == 0, "mode %d: no grass in yards or at the well (%d)" % [kind, in_yard])
		check(outside == 0, "mode %d: grass stays in the probe meadow (%d)" % [kind, outside])
		check(off_ground == 0, "mode %d: grass roots on the ground (%d)" % [kind, off_ground])
		for batch: MultiMeshInstance3D in grass.sets[kind].get_children():
			if batch.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: check(false, "grass casts no shadows")
	grass.set_mode(0)
	for kind in [1, 2]: check(not grass.sets[kind].visible, "mode 0 hides all probe grass")
	grass.set_mode(1)
	world.atmosphere.set_weather(3, true, true)
	world.atmosphere.advance(3.0)
	await settle(.2)
	var material: ShaderMaterial = grass.materials[0]
	check(is_equal_approx(float(material.get_shader_parameter("effect_time")), world.atmosphere.effect_time), "grass follows the wind clock")
	check(is_equal_approx(float(material.get_shader_parameter("wind_strength")), float(world.atmosphere.current.wind)), "grass follows the wind strength")
	check(not world.atmosphere.foliage_materials.has(material), "tree foliage list keeps only the foliage wind shader")
	Localization.set_language("en")
	check(grass.button.text == "Grass: blades", "EN text " + grass.button.text)
	Localization.set_language("ru")
	check(grass.button.text == "Трава: травинки", "RU text " + grass.button.text)
	Localization.set_language(language)
	var ground: String = world.terrain.material.shader.code
	check(ground.contains("grass_specular") and float(world.terrain.material.get_shader_parameter("grass_specular") if world.terrain.material.get_shader_parameter("grass_specular") != null else .06) <= .1, "matte grass: low specular on the ground grass")
	print("GRASS_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
