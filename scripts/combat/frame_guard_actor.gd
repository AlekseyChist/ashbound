extends "res://scripts/combat/corner_enemy_actor.gd"
## Guard actor with a real startup/active/recovery attack driven by an
## attack_frame_data resource. Extends the corner enemy actor and reuses its
## movement, aggro, return, cancellation and stagger logic. Only the guard
## uses this class; the wolf keeps the old actor.

const DEFAULT_ATTACK_PATH := "res://assets/combat/guard_unarmed_v1.tres"

# Public attack data (owned duplicate of the configured resource).
var attack_data: Resource = null

# Internal active-phase bookkeeping.
var _active_duration: float = 0.0


func setup(p_kind: String, p_home: Vector3, p_session: Node) -> void:
	super.setup(p_kind, p_home, p_session)
	var default_data := load(DEFAULT_ATTACK_PATH)
	if not configure_attack(default_data):
		push_error("frame_guard_actor: default attack data is invalid or missing")


func configure_attack(data: Resource) -> bool:
	if state != "idle":
		return false
	if data == null or not data.has_method("is_valid") or not data.is_valid():
		return false
	var owned := data.duplicate()
	attack_data = owned
	_windup_time = owned.startup_seconds()
	_recovery_time = owned.recovery_seconds()
	_active_duration = owned.active_seconds()
	_contact_done = false
	return true


func is_block_window_open() -> bool:
	if session == null or not _session_enabled():
		return false
	if state != "windup" or attack_data == null:
		return false
	var cue: float = attack_data.cue_seconds
	return state_time >= _windup_time - cue - 1e-8 and state_time < _windup_time


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

	if state == "active":
		state_time += delta
		if _hit_flash_time > 0.0:
			_hit_flash_time = maxf(0.0, _hit_flash_time - delta)
		_step_active()
		_present_visual()
		return

	super.step(delta)


func cancel_attack() -> void:
	# Inherited transitions must leave no deferred strike pending.
	_contact_done = false
	super.cancel_attack()


func reset_home() -> void:
	_contact_done = false
	super.reset_home()


func receive_hit() -> void:
	# Inherited stagger transition; clear any deferred strike bookkeeping.
	_contact_done = false
	super.receive_hit()


func snapshot() -> Dictionary:
	var snap := super.snapshot()
	snap["attack_id"] = String(attack_data.attack_id) if attack_data != null else ""
	match state:
		"windup":
			snap["attack_phase"] = "startup"
			snap["attack_elapsed"] = state_time
		"active":
			snap["attack_phase"] = "active"
			snap["attack_elapsed"] = _windup_time + state_time
		"recovery":
			snap["attack_phase"] = "recovery"
			snap["attack_elapsed"] = _windup_time + _active_duration + state_time
		_:
			snap["attack_phase"] = "ready"
			snap["attack_elapsed"] = 0.0
	return snap


# ---------------------------------------------------------------------------
# State steps (overrides)
# ---------------------------------------------------------------------------

func _step_windup(delta: float) -> void:
	# Guard is stationary; aim stays locked in _aim_direction.
	if state_time >= _windup_time - 1e-8:
		var overshoot := maxf(0.0, state_time - _windup_time)
		state = "active"
		state_time = overshoot
		_step_active()


func _step_active() -> void:
	if not _contact_done and state_time < (_active_duration - 1e-8):
		var result := ""
		if session != null and session.has_method("enemy_contact_geometry"):
			result = session.enemy_contact_geometry(self)
		if result == "contact":
			_contact_done = true
			var resolve_result := ""
			if session != null and session.has_method("resolve_enemy_contact"):
				resolve_result = session.resolve_enemy_contact(self)
			contacts += 1
			if resolve_result == "perfect_block":
				state = "stagger"
				state_time = 0.0
				_stagger_duration = BLOCK_STAGGER_TIME
				return
	elif not _contact_done and state_time >= (_active_duration - 1e-8):
		# Active window ended without contact: exactly one expired resolution.
		_contact_done = true
		if session != null and session.has_method("resolve_expired_enemy_attack"):
			session.resolve_expired_enemy_attack(self)
		contacts += 1

	if state == "active" and state_time >= (_active_duration - 1e-8):
		var overshoot := maxf(0.0, state_time - _active_duration)
		state = "recovery"
		state_time = overshoot


func _step_recovery(delta: float) -> void:
	super._step_recovery(delta)


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

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
			var cue_seconds: float = attack_data.cue_seconds if attack_data != null else CUE_WINDOW
			if state_time >= _windup_time - cue_seconds:
				action = "attack"
				cue = true
			else:
				action = "windup"
			progress = clampf(state_time / maxf(_windup_time, 0.0001), 0.0, 1.0)
		"active":
			action = "attack"
			progress = clampf(state_time / maxf(_active_duration, 0.0001), 0.0, 1.0)
		"recovery":
			action = "idle"
			progress = clampf(state_time / maxf(_recovery_time, 0.0001), 0.0, 1.0)
		"stagger":
			action = "hit"
			progress = clampf(state_time / maxf(_stagger_duration, 0.0001), 0.0, 1.0)
	var hit_flash := _hit_flash_time > 0.0
	_visual.present(action, facing_direction, progress, cue, hit_flash)
	# Guard never changes body Y.
	_visual.position.y = 0.0
