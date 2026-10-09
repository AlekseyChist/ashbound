extends Node
## D-117: the innkeeper of the forest inn in Codex's drawn set (inn-v1, variant A). He stands behind the
## bar (idle), turns to the hero when he is near, and talks (talk 1/2/3/2, 4 poses a second) while his own
## line is on screen; then idle again. The resident's old single sprite (the watchman) is hidden.
const TALK_POSES_PER_SECOND := 4.0
const TURN_RADIUS := 4.0
var world: Node
var visual: Node3D
var home_facing := Vector3.LEFT
var _talk_time := 0.0

func setup(p_world: Node, frames_path: String, facing: Vector3) -> void:
	world = p_world
	home_facing = facing.normalized()
	var keeper := get_parent() as Node3D
	var old := keeper.get_node_or_null("Body") as Node3D
	if old != null:
		old.visible = false
	visual = Node3D.new()
	visual.name = "Visual"
	visual.set_script(load("res://scripts/combat/corner_enemy_visual.gd"))
	keeper.add_child(visual)
	visual.setup("guard")
	visual.use_frames(frames_path)
	visual.external_feedback = true
	visual.breathing = true
	_present(0.0)

func talking() -> bool:
	return world != null and world.hud != null and world.hud.current_speaker() == "INN_KEEPER_NAME"

func _process(delta: float) -> void:
	_present(delta)

func _present(delta: float) -> void:
	if visual == null or world == null:
		return
	var keeper := get_parent() as Node3D
	var facing := home_facing
	var hero: Node3D = world.get("player")
	if hero != null:
		var to := hero.global_position - keeper.global_position
		to.y = 0.0
		if to.length() < TURN_RADIUS and to.length() > 0.05:
			facing = to.normalized()
	var action := "idle"
	if talking():
		_talk_time += delta
		action = "talk"
	else:
		_talk_time = 0.0
	visual.present(action, facing, fmod(_talk_time * TALK_POSES_PER_SECOND / 4.0, 1.0), false, false)
