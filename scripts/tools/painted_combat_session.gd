extends "res://scripts/tools/combat_feedback_session.gd"
## Изолированное превью раскрашенных (painted) боевых эффектов:
## переопределяются только фабрики FX/трейлов, остальная механика
## combat_feedback_session.gd не меняется.

const PAINTED_FX_SCRIPT_PATH := "res://scripts/tools/painted_combat_fx.gd"
const PAINTED_TRAILS_SCRIPT_PATH := "res://scripts/tools/painted_combat_trails.gd"


func _create_feedback_fx() -> Node:
	var fx_script: GDScript = load(PAINTED_FX_SCRIPT_PATH)
	return fx_script.new()


func _create_swing_trails() -> Node:
	var trails_script: GDScript = load(PAINTED_TRAILS_SCRIPT_PATH)
	return trails_script.new()
