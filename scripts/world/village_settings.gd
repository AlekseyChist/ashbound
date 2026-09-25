extends RefCounted
## Application preferences, isolated from campaign saves and language/time state.
const PATH := "user://village_settings.cfg"
var music_percent := 45.0
var sound_percent := 80.0
var draw_distance := 220.0
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
	draw_distance = _number(config.get_value("graphics", "distance", draw_distance), draw_distance, 80, 300)
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
	draw_distance = clampf(draw_distance, 80, 300)
	world.camera_rig.get_camera().far = draw_distance
	for node: GeometryInstance3D in world.dressing.find_children("*", "GeometryInstance3D", true, false):
		if not node.has_meta("base_visibility_end"):
			node.set_meta("base_visibility_end", node.visibility_range_end)
		var base: float = node.get_meta("base_visibility_end")
		if base <= 0: continue
		node.visibility_range_end = base * draw_distance / 220.0
		node.visibility_range_end_margin = minf(10, node.visibility_range_end * .15)

static func _number(value: Variant, fallback: float, low: float, high: float) -> float:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)): return fallback
	return clampf(float(value), low, high)
