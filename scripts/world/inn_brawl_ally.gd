extends CharacterBody3D
## INN-BRAWL-01 (D-092, D-113): the innkeeper's daughter in the morning fight. She takes on one
## enemy (the brute): closes in, winds up, strikes; every third blow at her she blocks. She swings slower
## than the brute, so alone with him she is out first; with the hero's help he gives up first. After
## OUT_HITS landed blows she is out until the end - she walks to the bar and stays there; the fight
## is not lost because of it. She wears the approved look (D-111), cut from the motion proof sheet
## until Codex's full set. Stepped by the world's physics frame while the combat session runs.
const MAX_STEP := 1.0 / 60.0
const SPEED := 2.4
const REACH := 1.25
const WINDUP := 1.0
const RECOVERY := 1.2
const HIT_TIME := 0.45
## Trial numbers: blows she can take before she is out.
const OUT_HITS := 3
const GROUND_CLEARANCE := 0.12

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
	_visual.use_frames("res://assets/characters/inn-temp/daughter_frames.tres")
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
	match state:
		"close", "out":
			if velocity.length() > 0.01 or state == "close" or (state == "out" and (_out_spot - global_position).length() > 0.2):
				action = "walk"
				progress = fmod(_walk_time * 4.0, 1.0)
		"windup":
			action = "windup" if state_time < WINDUP - 0.18 else "attack"
			progress = clampf(state_time / WINDUP, 0.0, 1.0)
		"recover":
			action = "attack" if state_time < 0.12 else "idle"
		"hit":
			action = "hit"
			progress = clampf(state_time / HIT_TIME, 0.0, 1.0)
	_visual.present(action, facing_direction, progress, false, state == "hit")
