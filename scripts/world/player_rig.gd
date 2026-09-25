extends Node3D
## PLAYER-RIG-01A: the hero, the third-person camera and the HUD as one scene for every level
## built in code. Levels keep their own input wiring; a pocket menu added to the rig finds
## its siblings through the menu's default paths (../HUD, ../CameraRig, ../Player).
const AcceptedFrames = preload("res://assets/characters/world-graybox-v1/traveler_frames.tres")
## The accepted hero D-059; off only for levels that keep the older courtyard frames.
@export var accepted_appearance := true
@export var camera_far := 150.0
var player: CharacterBody3D
var camera_rig: Node3D
var hud: CanvasLayer

func _ready() -> void:
	player = $Player
	camera_rig = $CameraRig
	hud = $HUD
	if accepted_appearance:
		player.get_node("Visual").set_appearance_frames(AcceptedFrames)
	camera_rig.set_target(player)
	camera_rig.get_camera().far = camera_far
