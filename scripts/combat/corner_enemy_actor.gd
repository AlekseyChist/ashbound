extends CharacterBody3D
## Corner enemy actor (wolf / guard) for the isolated AshBound preview.
##
## The session drives this actor: it calls step(delta) in small physics
## substeps. This actor does NOT run _physics_process itself.
##
## step() API contract:
## - delta must be finite and >= 0.
## - For robustness each call is capped to <= 1/60 sec; the session is
##   expected to subdivide larger frames into multiple step() calls.
## - A single attack can produce at most one contact (guarded by a flag).

const MAX_STEP: float = 1.0 / 60.0
const DETECT_RADIUS: float = 3.0
const VERTICAL_TOLERANCE: float = 1.0
const RETURN_HOME_RADIUS: float = 5.5
const LOS_TIMEOUT: float = 1.0
const REACQUIRE_DELAY: float = 0.5
const IDLE_RESUME_DISTANCE: float = 0.12
const LUNGE_SPEED: float = 3.2
const CUE_WINDOW: float = 0.18
const STAGGER_TIME: float = 0.45
const BLOCK_STAGGER_TIME: float = 0.65

var kind: String = ""
var home: Vector3 = Vector3.ZERO
var session: Node = null
var facing_direction: Vector3 = Vector3.FORWARD
var state: String = "idle"
var state_time: float = 0.0
var contacts: int = 0
var hits_received: int = 0

# --- internal state ---
var _player: CharacterBody3D = null
var _visual: Node = null
var _label: Label3D = null
var _ring: MeshInstance3D = null
var _lang_connected: bool = false

var _chase_target: Vector3 = Vector3.ZERO
var _aim_direction: Vector3 = Vector3.FORWARD
var _contact_done: bool = false
var _los_lost_time: float = 0.0
var _reacquire_timer: float = 0.0
var _hit_flash_time: float = 0.0
var _walk_sim_time: float = 0.0
var _steer_side: int = 1
var _steer_attempts: int = 0
var _stagger_duration: float = STAGGER_TIME

# --- per-kind tuning ---
var _chase_speed: float = 2.6
var _stop_distance: float = 1.8
var _windup_time: float = 0.70
var _recovery_time: float = 0.70
var _capsule_radius: float = 0.3
var _capsule_height: float = 1.8
var _capsule_center: float = 0.9


## Optional ground under the actor, `func(x: float, z: float) -> float` (the world's terrain).
## Empty in the sandboxes: they keep their flat floor at y = 0.02.
var ground_height: Callable
const GROUND_CLEARANCE := 0.12

func setup(p_kind: String, p_home: Vector3, p_session: Node) -> void:
	kind = p_kind
	home = p_home
	session = p_session
	if session != null and "player" in session:
		_player = session.get("player")

	match kind:
		"wolf":
			_chase_speed = 2.6
			_stop_distance = 1.8
			_windup_time = 0.70
			_recovery_time = 0.70
			_capsule_radius = 0.32
			_capsule_height = 0.7
			_capsule_center = 0.35
		"guard":
			_chase_speed = 1.8
			_stop_distance = 1.3
			_windup_time = 0.80
			_recovery_time = 0.70
			_capsule_radius = 0.3
			_capsule_height = 1.8
			_capsule_center = 0.9
		_:
			push_warning("corner_enemy_actor: unknown kind '%s'" % kind)

	# Collision setup: own layer 4, mask 7 (world 1 + player 2 + NPC 4).
	collision_layer = 4
	collision_mask = 7
	var capsule := CapsuleShape3D.new()
	capsule.radius = _capsule_radius
	capsule.height = _capsule_height
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = _capsule_center + (GROUND_CLEARANCE if ground_height.is_valid() else 0.0)
	add_child(col)

	# Start at home, slightly above the flat floor.
	global_position = Vector3(home.x, _floor_y(home.x, home.z), home.z)
	state = "idle"
	state_time = 0.0
	contacts = 0
	hits_received = 0
	_contact_done = false
	_los_lost_time = 0.0
	_reacquire_timer = 0.0
	_hit_flash_time = 0.0
	_walk_sim_time = 0.0
	_steer_side = 1
	_steer_attempts = 0
	_stagger_duration = STAGGER_TIME

	_build_visual()


func _build_visual() -> void:
	# Visual script is created in a later task; use load (not preload) so the
	# first import still works when it does not exist yet.
	var visual_script := load("res://scripts/combat/corner_enemy_visual.gd")
	if visual_script != null:
		var vis := Node3D.new()
		vis.name = "Visual"
		vis.set_script(visual_script)
		add_child(vis)
		if vis.has_method("setup"):
			vis.setup(kind)
		_visual = vis

	# Localized name label.
	_label = Label3D.new()
	_label.name = "EnemyLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1, 0.95, 0.85)
	_label.font_size = 32
	_label.pixel_size = 0.003
	_label.outline_size = 8
	var label_height: float = _capsule_height + 0.4
	_label.position = Vector3(0, label_height, 0)
	add_child(_label)
	_update_label_text()

	if not is_inside_tree():
		tree_entered.connect(_on_tree_entered_once)
	else:
		_connect_language()


func _on_tree_entered_once() -> void:
	_connect_language()


func _connect_language() -> void:
	if _lang_connected:
		return
	_lang_connected = true
	var loc := get_node_or_null("/root/Localization")
	if loc != null and loc.has_signal("language_changed"):
		loc.connect("language_changed", _on_language_changed)


func _on_language_changed(_language: String) -> void:
	_update_label_text()


func _update_label_text() -> void:
	if _label == null:
		return
	var key := "ENEMY_WOLF" if kind == "wolf" else "ENEMY_GUARD"
	var loc := get_node_or_null("/root/Localization")
	if loc != null and loc.has_method("text"):
		_label.text = loc.text(key)
	else:
		_label.text = tr(key)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"state": state,
		"state_time": state_time,
		"position": global_position,
		"home": home,
		"facing": facing_direction,
		"contacts": contacts,
		"hits_received": hits_received,
	}


func step(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	delta = minf(delta, MAX_STEP)
	if session == null:
		cancel_attack()
		velocity = Vector3.ZERO
		_present_visual()
		return
	if not _session_enabled():
		velocity = Vector3.ZERO
		_present_visual()
		return

	state_time += delta
	if _hit_flash_time > 0.0:
		_hit_flash_time = maxf(0.0, _hit_flash_time - delta)

	match state:
		"idle":
			_step_idle(delta)
		"chase":
			_step_chase(delta)
		"windup":
			_step_windup(delta)
		"recovery":
			_step_recovery(delta)
		"stagger":
			_step_stagger(delta)
		"return":
			_step_return(delta)

	_present_visual()


func cancel_attack() -> void:
	# Cancels ALL pending activity (chase/stagger included); never resets
	# counters or teleports.
	state = "idle"
	state_time = 0.0
	_contact_done = false
	_hit_flash_time = 0.0
	velocity = Vector3.ZERO
	_present_visual()


func reset_home() -> void:
	# Explicit test reset only.
	global_position = Vector3(home.x, _floor_y(home.x, home.z), home.z)
	state = "idle"
	state_time = 0.0
	contacts = 0
	hits_received = 0
	_contact_done = false
	_los_lost_time = 0.0
	_reacquire_timer = 0.0
	_hit_flash_time = 0.0
	_stagger_duration = STAGGER_TIME
	velocity = Vector3.ZERO
	_present_visual()


func receive_hit() -> void:
	if session == null or not _session_enabled():
		return
	hits_received += 1
	_hit_flash_time = 0.25
	# ALWAYS enter stagger (idle/chase/return/windup/recovery), no stale windup.
	state = "stagger"
	state_time = 0.0
	_stagger_duration = STAGGER_TIME
	_contact_done = false


func is_block_window_open() -> bool:
	if session == null or not _session_enabled():
		return false
	return state == "windup" and state_time >= _windup_time - CUE_WINDOW - 1e-8 and state_time < _windup_time


func has_line_to_player() -> bool:
	if _player == null:
		return false
	var from := global_position + Vector3(0, 0.5, 0)
	var to := _player.global_position + Vector3(0, 0.5, 0)
	var dir := to - from
	if dir.length() < 0.001:
		return true
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 5, [get_rid(), _player.get_rid()])
	var result := space_state.intersect_ray(query)
	# Empty means clear line of sight; a world or other NPC body blocks it.
	return result.is_empty()


# ---------------------------------------------------------------------------
# State steps
# ---------------------------------------------------------------------------

func _step_idle(delta: float) -> void:
	if _reacquire_timer > 0.0:
		_reacquire_timer = maxf(0.0, _reacquire_timer - delta)
		return
	if _player != null:
		var planar_dist := Vector2(global_position.x - _player.global_position.x, global_position.z - _player.global_position.z).length()
		var home_dist := Vector2(_player.global_position.x - home.x, _player.global_position.z - home.z).length()
		if planar_dist <= DETECT_RADIUS and home_dist <= RETURN_HOME_RADIUS and _vertical_ok() and has_line_to_player():
			state = "chase"
			state_time = 0.0
			_los_lost_time = 0.0
			return
	var actor_home_dist := Vector2(global_position.x - home.x, global_position.z - home.z).length()
	if actor_home_dist > 0.12:
		_begin_return()


func _step_chase(delta: float) -> void:
	if not has_line_to_player():
		_los_lost_time += delta
		if _los_lost_time > LOS_TIMEOUT:
			_begin_return()
			return
	else:
		_los_lost_time = 0.0

	var to_home := Vector2(global_position.x - home.x, global_position.z - home.z).length()
	var player_to_home := Vector2(_player.global_position.x - home.x, _player.global_position.z - home.z).length()
	if to_home > RETURN_HOME_RADIUS or player_to_home > RETURN_HOME_RADIUS:
		_begin_return()
		return

	var dir := (_player.global_position - global_position)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = facing_direction
	else:
		dir = dir.normalized()
	facing_direction = dir

	var planar_dist := Vector2(global_position.x - _player.global_position.x, global_position.z - _player.global_position.z).length()
	if not _vertical_ok():
		_begin_return()
		return
	if planar_dist <= _stop_distance:
		state = "windup"
		state_time = 0.0
		_aim_direction = dir
		_contact_done = false
		return

	_move_horizontal(dir * _chase_speed, delta)
	_walk_sim_time += delta


func _step_windup(delta: float) -> void:
	# Lock aim; never home in during windup. Only the wolf lunges, and only
	# during the last CUE_WINDOW of the windup (the guard stays stationary).
	if kind == "wolf" and state_time >= _windup_time - CUE_WINDOW - 1e-8:
		var lunge_dir := _aim_direction
		lunge_dir.y = 0.0
		if lunge_dir.length_squared() > 0.0001:
			_move_horizontal(lunge_dir.normalized() * LUNGE_SPEED, delta)
	# Contact exactly at end of windup; no movement after contact.
	if state_time >= _windup_time - 1e-8 and not _contact_done:
		_contact_done = true
		var result := ""
		if session != null and session.has_method("resolve_enemy_contact"):
			result = session.resolve_enemy_contact(self)
		contacts += 1
		if result == "perfect_block":
			state = "stagger"
			_stagger_duration = BLOCK_STAGGER_TIME
		else:
			state = "recovery"
		state_time = 0.0


func _step_recovery(delta: float) -> void:
	if state_time >= _recovery_time:
		state = "idle"
		state_time = 0.0
		_reacquire_timer = REACQUIRE_DELAY


func _step_stagger(delta: float) -> void:
	if state_time >= _stagger_duration:
		state = "idle"
		state_time = 0.0
		_reacquire_timer = REACQUIRE_DELAY


func _step_return(delta: float) -> void:
	var to_home := home - global_position
	var planar_dist := Vector2(to_home.x, to_home.z).length()
	if planar_dist <= IDLE_RESUME_DISTANCE:
		state = "idle"
		state_time = 0.0
		_reacquire_timer = REACQUIRE_DELAY
		return

	var dir := Vector3(to_home.x, 0.0, to_home.z).normalized()
	facing_direction = dir
	var moved := _move_horizontal(dir * _chase_speed, delta)
	_walk_sim_time += delta
	if not moved:
		# Blocked: try a deterministic local steer (left/right), no random.
		_steer_attempts += 1
		if _steer_attempts > 4:
			_steer_attempts = 0
			_steer_side = -_steer_side
		var perp := Vector3(-dir.z, 0, dir.x) * _steer_side
		var steer_dir := (dir + perp * 0.7).normalized()
		_move_horizontal(steer_dir * _chase_speed, delta)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _session_enabled() -> bool:
	if session == null or not session.has_method("enabled"):
		return false
	var v = session.enabled()
	return v == true


func _vertical_ok() -> bool:
	if _player == null:
		return false
	return absf(global_position.y - _player.global_position.y) <= VERTICAL_TOLERANCE


func _begin_return() -> void:
	state = "return"
	state_time = 0.0
	_steer_side = 1
	_steer_attempts = 0


## Moves horizontally with swept collision; slides once along the tangent if
## blocked. Returns true if meaningful forward progress was made.
func _move_horizontal(dir: Vector3, delta: float) -> bool:
	var step_vec := dir * delta
	var prev_pos := global_position
	var collision := move_and_collide(step_vec)
	if collision != null:
		# Slide residual tangent once along the contact normal.
		var remainder := collision.get_remainder()
		var tangent := (dir - collision.get_normal() * dir.dot(collision.get_normal())).normalized()
		if tangent.length_squared() > 0.0001 and remainder.length_squared() > 0.0:
			move_and_collide(tangent * remainder.length())
	if ground_height.is_valid():
		global_position.y = _floor_y(global_position.x, global_position.z)
	return global_position.distance_squared_to(prev_pos) > 1e-8


func _floor_y(x: float, z: float) -> float:
	return float(ground_height.call(x, z)) + 0.02 if ground_height.is_valid() else 0.02


func _present_visual() -> void:
	if _visual == null or not _visual.has_method("present"):
		return
	var action := "idle"
	var progress := 0.0
	var cue := false
	match state:
		"idle":
			action = "idle"
		"chase", "return":
			action = "walk"
			progress = fmod(_walk_sim_time * 4.0, 1.0)
		"windup":
			if state_time >= _windup_time - CUE_WINDOW:
				action = "attack"
				cue = true
			else:
				action = "windup"
			progress = clampf(state_time / _windup_time, 0.0, 1.0)
		"recovery":
			if state_time < CUE_WINDOW * 0.67: # first ~0.12s
				action = "attack"
			else:
				action = "idle"
			progress = clampf(state_time / _recovery_time, 0.0, 1.0)
		"stagger":
			action = "hit"
			progress = clampf(state_time / maxf(_stagger_duration, 0.0001), 0.0, 1.0)
	var hit_flash := _hit_flash_time > 0.0
	_visual.present(action, facing_direction, progress, cue, hit_flash)
	# Wolf attack: small vertical lunge arc only during the lunge window;
	# no body Y change otherwise.
	if kind == "wolf" and state == "windup" and state_time >= _windup_time - CUE_WINDOW:
		var lunge_progress := clampf((state_time - (_windup_time - CUE_WINDOW)) / CUE_WINDOW, 0.0, 1.0)
		_visual.position.y = sin(lunge_progress * PI) * 0.14
	elif _visual != null:
		_visual.position.y = 0.0
