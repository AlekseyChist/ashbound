extends CharacterBody3D
## INN-BRAWL-01 (D-092, D-113): the innkeeper's daughter in the morning fight. She takes on one
## enemy (the brute): closes in, winds up, strikes; every third blow at her she blocks. She swings slower
## than the brute, so alone with him she is out first; with the hero's help he gives up first. After
## OUT_HITS landed blows she is out until the end - she walks to the bar and stays there; the fight
## is not lost because of it. She wears the approved look (D-111) in Codex's full drawn set (inn-v1). Stepped by the world's physics frame while the combat session runs.
const MAX_STEP := 1.0 / 60.0
const SPEED := 2.4
const REACH := 1.25
const WINDUP := 1.0
const RECOVERY := 1.2
const HIT_TIME := 0.45
## Trial numbers: blows she can take before she is out.
const OUT_HITS := 3
const GROUND_CLEARANCE := 0.12
## Drawn walk phases change at the reference 15 per second (Codex 142).
const POSE_FPS := 15.0
## A blocked blow shows her guard this long.
const BLOCK_SHOW := 0.4

var session: Node
var ground_height: Callable
## The enemy she fights; null = she stands where she is.
var target: Node3D = null
var spot := Vector3.ZERO
var facing_direction := Vector3.BACK
var state := "idle"
var state_time := 0.0
var landed := 0
var down := false
## Strikes that hit the target, for the checks.
var strikes := 0
var _blows := 0
var _out_spot := Vector3.ZERO
var _visual: Node3D
var _walk_time := 0.0
var _block_time := 0.0

func setup(p_session: Node, ground: Callable, at: Vector3, facing: Vector3) -> void:
	session = p_session
	ground_height = ground
	collision_layer = 4
	collision_mask = 7
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.85 + GROUND_CLEARANCE
	add_child(shape)
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.set_script(load("res://scripts/combat/corner_enemy_visual.gd"))
	add_child(_visual)
	_visual.setup("guard")
	var brawl: GDScript = load("res://scripts/world/inn_brawl.gd")  # not preload: inn_brawl preloads this script
	_visual.use_frames(brawl.frames_path(brawl.DAUGHTER_FRAMES))
	var label := Label3D.new()
	label.name = "NameLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 0.95, 0.85)
	label.font_size = 32
	label.pixel_size = 0.003
	label.outline_size = 8
	label.position = Vector3(0, 2.1, 0)
	label.text = Localization.text("INN_DAUGHTER_NAME")
	add_child(label)
	place(at, facing)

## Stand at a point, facing a direction, out of any fight.
func place(at: Vector3, facing: Vector3) -> void:
	spot = at
	global_position = Vector3(at.x, _floor(at.x, at.z), at.z)
	facing_direction = facing.normalized()
	target = null
	state = "idle"
	state_time = 0.0
	velocity = Vector3.ZERO
	_present()

## Back to how she stood before the fight (a fight left halfway starts over).
func restore() -> void:
	landed = 0
	down = false
	strikes = 0
	_blows = 0
	_block_time = 0.0
	place(spot, facing_direction)

func fight(enemy: Node3D, out_spot: Vector3) -> void:
	target = enemy
	_out_spot = out_spot
	state = "close"
	state_time = 0.0

func is_down() -> bool:
	return down

## An enemy's blow reaches her: every third one she blocks. Returns "block", "hit" or "miss".
func receive_enemy_hit(_attacker: Node) -> String:
	if down:
		return "miss"
	_blows += 1
	if _blows % 3 == 0:
		_block_time = BLOCK_SHOW
		return "block"
	landed += 1
	if landed >= OUT_HITS:
		down = true
		target = null
		state = "out"
	else:
		state = "hit"
	state_time = 0.0
	return "hit"

func _physics_process(delta: float) -> void:
	# She stands on the floor also while the scene waits (the men re-floor every step too).
	global_position.y = _floor(global_position.x, global_position.z)
	if session == null or not session.enabled():
		return
	var remaining := minf(delta, 0.25)
	while remaining > 0.0:
		var step := minf(remaining, MAX_STEP)
		_step(step)
		remaining -= step
	_present()

func _step(delta: float) -> void:
	state_time += delta
	_block_time = maxf(_block_time - delta, 0.0)
	match state:
		"close":
			if not _target_standing():
				state = "idle"
				return
			var to := target.global_position - global_position
			to.y = 0.0
			facing_direction = to.normalized() if to.length() > 0.01 else facing_direction
			if to.length() <= REACH:
				state = "windup"
				state_time = 0.0
			else:
				_move(facing_direction * SPEED, delta)
		"windup":
			if state_time >= WINDUP:
				if _target_standing():
					var to := target.global_position - global_position
					to.y = 0.0
					if to.length() <= REACH + 0.4:
						strikes += 1
						target.receive_hit()
				state = "recover"
				state_time = 0.0
		"recover":
			if state_time >= RECOVERY:
				state = "close"
				state_time = 0.0
		"hit":
			if state_time >= HIT_TIME:
				state = "close" if _target_standing() else "idle"
				state_time = 0.0
		"out":
			var to := _out_spot - global_position
			to.y = 0.0
			if to.length() > 0.15:
				facing_direction = to.normalized()
				_move(facing_direction * SPEED * 0.6, delta)
		_:
			velocity = Vector3.ZERO

func _target_standing() -> bool:
	return target != null and is_instance_valid(target) and not (target.state in ["flee", "gone"])

func _move(motion: Vector3, delta: float) -> void:
	var hit := move_and_collide(motion * delta)
	if hit != null:
		var tangent := motion - hit.get_normal() * motion.dot(hit.get_normal())
		move_and_collide(tangent * delta)
	global_position.y = _floor(global_position.x, global_position.z)
	_walk_time += delta

func _floor(x: float, z: float) -> float:
	return float(ground_height.call(x, z)) + 0.02 if ground_height.is_valid() else global_position.y

func _present() -> void:
	if _visual == null:
		return
	var action := "idle"
	var progress := 0.0
	var walking := velocity.length() > 0.01 or state == "close" 			or (state == "out" and (_out_spot - global_position).length() > 0.15)
	match state:
		"close", "out":
			if walking:
				action = "walk"
				progress = _cycle_progress("walk")
			elif state == "out":
				# Out of the fight she holds her arm (Codex 142: the "out" pose).
				action = _clip_or("out", "idle")
		"windup":
			action = "windup" if state_time < WINDUP - 0.18 else "attack"
			progress = clampf(state_time / WINDUP, 0.0, 1.0)
		"recover":
			action = "attack" if state_time < 0.12 else _clip_or("guard", "idle")
		"hit":
			action = "hit"
			progress = clampf(state_time / HIT_TIME, 0.0, 1.0)
	if _block_time > 0.0 and state in ["close", "recover"]:
		action = _clip_or("guard", action)
	_visual.present(action, facing_direction, progress, false, state == "hit")

## Phase of a looping drawn cycle: one frame per 1/POSE_FPS, whatever the number of phases.
func _cycle_progress(action: String) -> float:
	var frames := _frames()
	var count := 1
	if frames != null:
		for view in ["side", "front", "back"]:
			if frames.has_animation(action + "_" + view):
				count = maxi(count, frames.get_frame_count(action + "_" + view))
	return fmod(_walk_time * POSE_FPS / float(count), 1.0)

## A set without guard/out clips falls back instead of asking for a missing one.
func _clip_or(action: String, fallback: String) -> String:
	var frames := _frames()
	return action if frames != null and frames.has_animation(action + "_side") else fallback

func _frames() -> SpriteFrames:
	var body := _visual.get_node_or_null("Body") as AnimatedSprite3D
	return body.sprite_frames if body != null else null
