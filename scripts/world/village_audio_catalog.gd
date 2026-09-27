extends RefCounted
const WIND := "res://assets/audio/village-v1/wind.ogg"
const RAIN := "res://assets/audio/village-v1/rain.ogg"
const FIRE := "res://assets/audio/village-v1/fire.ogg"
const THUNDER := "res://assets/audio/village-v1/thunder.ogg"

static func footsteps(surface: String) -> Array[String]:
	var paths: Array[String]=[]
	if surface not in ["grass","dirt","stone","wood","snow"]: return paths
	for i in range(4): paths.append("res://assets/audio/village-v1/step_%s_%d.ogg" % [surface,i])
	return paths

static func music(region: String) -> String:
	var names: Dictionary={"forest":"forest-watch","desert":"dusty-sands","mountains":"highland-stone","lowlands":"swamp-rituals","main":"catacomb-oath"}
	if not names.has(region): return ""
	return "res://assets/audio/soundtrack-v1/%s.ogg" % names[region]
