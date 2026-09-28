extends RefCounted
## Application preferences, isolated from campaign saves and language/time state.
const PATH := "user://village_settings.cfg"
var music_percent := 45.0
var sound_percent := 80.0
var draw_distance := 220.0
## Owner 27 Sep: up to 1 km on PC and on a strong phone; the default stays 220 m.
const MAX_DRAW_DISTANCE := 1000.0
const TERRAIN_FAR := 3000.0
## GRASS-02: share of the full grass density; 0 turns the grass off.
var grass_percent := 100.0
## GRASS-02 / D-088: how far grass is drawn, metres.
var grass_distance := 30.0
var path := PATH

func load_settings(file: String = PATH) -> void:
	path = file
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	music_percent = _number(config.get_value("audio", "music", music_percent), music_percent, 0, 100)
	sound_percent = _number(config.get_value("audio", "sound", sound_percent), sound_percent, 0, 100)
	draw_distance = _number(config.get_value("graphics", "distance", draw_distance), draw_distance, 80, MAX_DRAW_DISTANCE)
	grass_percent = _number(config.get_value("graphics", "grass", grass_percent), grass_percent, 0, 100)
	grass_distance = _number(config.get_value("graphics", "grass_distance", grass_distance), grass_distance, 15, 45)

func save_settings() -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND: return error
	config.set_value("audio", "music", music_percent)
	config.set_value("audio", "sound", sound_percent)
	config.set_value("graphics", "distance", draw_distance)
	config.set_value("graphics", "grass", grass_percent)
	config.set_value("graphics", "grass_distance", grass_distance)
	return config.save(path)

func apply_distance(world: Node3D) -> void:
	draw_distance = clampf(draw_distance, 80, MAX_DRAW_DISTANCE)
	# The ground and the mountains are always drawn to the horizon (the fog hides the far end); the
	# setting limits the objects on them (trees, grass, props) through their visibility ranges.
	# Clipping the ground at the draw distance left the sky showing under distant mountains.
	world.camera_rig.get_camera().far = maxf(draw_distance, TERRAIN_FAR)
	# WORLD-DRESS-01A: batches outside the village dressing join through a group.
	var scaled: Array = world.dressing.find_children("*", "GeometryInstance3D", true, false)
	for node in world.get_tree().get_nodes_in_group(&"draw_distance_scaled"):
		if node is GeometryInstance3D and not scaled.has(node): scaled.append(node)
	for node: GeometryInstance3D in scaled:
		if not node.has_meta("base_visibility_end"):
			node.set_meta("base_visibility_end", node.visibility_range_end)
		var base: float = node.get_meta("base_visibility_end")
		# TREES-01: where near trees end and the far cones begin moves with the setting too.
		if node.has_meta("base_visibility_begin"):
			node.visibility_range_begin = float(node.get_meta("base_visibility_begin")) * draw_distance / 220.0
		if base <= 0: continue
		node.visibility_range_end = base * draw_distance / 220.0
		node.visibility_range_end_margin = minf(10, node.visibility_range_end * .15)

static func _number(value: Variant, fallback: float, low: float, high: float) -> float:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)): return fallback
	return clampf(float(value), low, high)
