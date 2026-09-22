extends "res://scripts/tools/fist_defense_controller.gd"
## Corner-enemy session: two scripted corner enemies (wolf/guard) replace the
## training device. All timing, guard, refractory and recoil logic is inherited
## from FistDefenseController; this file only wires the actors into it.

const ACTOR_SCRIPT_PATH := "res://scripts/tools/corner_enemy_actor.gd"
const HERO_POS := Vector3(0.0, 0.02, 5.0)
const WOLF_HOME := Vector3(-11.0, 0.02, 10.0)
const GUARD_HOME := Vector3(11.0, 0.02, 10.0)
const RING_RADIUS := 3.0
const RING_Y := 0.025
const MAX_DELTA := 0.25
const SUBSTEP_MAX := 1.0 / 60.0
const WOLF_REACH := 1.30
const GUARD_REACH := 1.65
const HERO_TARGET_RANGE := 1.9
const HERO_CONE_HALF: float = 55.0

var enemies: Array[Node] = []
var _active_source: CharacterBody3D
var _incoming_origin: Node3D


func setup(sbx: Node, plr: CharacterBody3D) -> void:
	sandbox = sbx
	player = plr
	device = Node3D.new()
	device.name = "IncomingOrigin"
	add_child(device)

	_hero_visual = _find_hero_visual()
	if _hero_visual != null:
		_hero_visual_base = _hero_visual.position
		if player != null:
			player.position = HERO_POS
			if "facing_direction" in player:
				player.set("facing_direction", Vector3(0.0, 0.0, -1.0))

	var actor_script: GDScript = load(ACTOR_SCRIPT_PATH)
	var wolf: CharacterBody3D = actor_script.new()
	wolf.name = "Wolf"
	add_child(wolf)
	wolf.setup("wolf", WOLF_HOME, self)
	enemies.append(wolf)

	var guard: CharacterBody3D = actor_script.new()
	guard.name = "Guard"
	add_child(guard)
	guard.setup("guard", GUARD_HOME, self)
	enemies.append(guard)

	_build_home_rings(WOLF_HOME)
	_build_home_rings(GUARD_HOME)

	_apply_focus_state()
	print("ASHBOUND_CORNER_SESSION_READY")


func _build_home_rings(home: Vector3) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.72, 0.52, 0.18)
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "HomeRing"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.02
	torus.outer_radius = RING_RADIUS + 0.02
	torus.ring_segments = 12
	torus.rings = 48
	ring.mesh = torus
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(home.x, RING_Y, home.z)
	add_child(ring)


func enabled() -> bool:
	if not is_inside_tree():
		return false
	if not can_process():
		return false
	if get_tree().paused:
		return false
	return _gameplay_enabled()


func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	_apply_focus_state()
	if not enabled():
		cancel_trial()
		return
	var remaining: float = minf(delta, MAX_DELTA)
	while remaining > 0.0:
		if not enabled():
			cancel_trial()
			return
		var step: float = minf(remaining, SUBSTEP_MAX)
		_sim_time += step
		for e in enemies:
			if is_instance_valid(e):
				e.step(step)
		_update_recoil(step)
		remaining -= step


func start_swing() -> bool:
	return false


func is_block_window_open() -> bool:
	if not enabled():
		return false
	for e in enemies:
		if is_instance_valid(e) and e.is_block_window_open():
			return true
	return false


func snapshot() -> Dictionary:
	var snap: Dictionary = super.snapshot()
	var any_windup: bool = false
	var any_recovery: bool = false
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var phase: String = e.state
		if phase == "windup":
			any_windup = true
		elif phase == "recovery" or phase == "stagger":
			any_recovery = true
	snap["phase"] = "windup" if any_windup else ("recovery" if any_recovery else "idle")
	return snap


func resolve_enemy_contact(actor: Node) -> String:
	if not enabled() or not enemies.has(actor):
		return "cancelled"
	_active_source = actor as CharacterBody3D
	device.global_position = _active_source.global_position
	_strike_dir = _active_source.facing_direction
	_contact_done = false
	_resolve_contact()
	return _last_result


func _resolve_contact() -> void:
	if _contact_done:
		return
	if not enabled():
		_cancel_active()
		return
	_contact_done = true
	var result: String = "miss"
	var reach: float = GUARD_REACH if _active_source.kind == "guard" else WOLF_REACH
	var to_player: Vector3 = player.global_position - device.global_position
	var flat: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	var dist: float = flat.length()
	if absf(to_player.y) > MAX_HEIGHT_OFFSET or dist > reach:
		result = "miss"
	elif not _in_cone(flat, _strike_dir, ATTACK_HALF_CONE):
		result = "miss"
	elif not _ray_visible():
		result = "obstructed"
	else:
		var trained: bool = _is_trained()
		var frontal: bool = _frontal_guard()
		if trained and _guarding and frontal:
			var dt: float = _sim_time - _guard_started
			if _perfect_eligible and dt >= 0.0 and dt <= PERFECT_WINDOW + CONTACT_EPS:
				result = "perfect_block"
			else:
				result = "block"
		else:
			result = "hit"
	_contacts += 1
	_last_result = result
	_perfect_eligible = false
	_apply_result_fx(result)
	_phase = Phase.RECOVERY
	_phase_time = 0.0
	resolved.emit(result)
	print("ASHBOUND_DEFENSE_RESULT result=%s count=%d" % [result, _contacts])


func _ray_visible() -> bool:
	var from: Vector3 = _active_source.global_position + Vector3(0.0, 0.5, 0.0)
	var to: Vector3 = player.global_position + Vector3(0.0, 0.5, 0.0)
	var space: PhysicsDirectSpaceState3D = device.get_world_3d().direct_space_state
	if space == null:
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 5)
	query.exclude = [player.get_rid(), _active_source.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	return not hit.has("collider")


func cancel_trial() -> void:
	super.cancel_trial()
	for e in enemies:
		if is_instance_valid(e):
			e.cancel_attack()


func _cancel_active() -> void:
	cancel_trial()


func reset_trial() -> void:
	if not enabled():
		return
	cancel_trial()
	_contacts = 0
	_last_result = ""
	_refractory_until = -1.0
	if player != null and player.has_method("stop_input"):
		player.stop_input()
		player.position = HERO_POS
		if "facing_direction" in player:
			player.set("facing_direction", Vector3(0.0, 0.0, -1.0))
	for e in enemies:
		if is_instance_valid(e):
			e.reset_home()
	var level: Node = sandbox.get("level") if sandbox != null else null
	if level != null and level.has_method("_snap_camera_to_player"):
		level._snap_camera_to_player()


func eligible_target() -> Node3D:
	if not enabled():
		return null
	var best: Node3D = null
	var best_dist: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var actor: CharacterBody3D = e as CharacterBody3D
		var to_actor: Vector3 = actor.global_position - player.global_position
		var flat: Vector3 = Vector3(to_actor.x, 0.0, to_actor.z)
		var dist: float = flat.length()
		if dist > HERO_TARGET_RANGE or absf(to_actor.y) > MAX_HEIGHT_OFFSET:
			continue
		if not _in_cone(flat, player.facing_direction, HERO_CONE_HALF):
			continue
		if not _hero_ray_visible(actor):
			continue
		if dist < best_dist:
			best_dist = dist
			best = actor
	return best


func _hero_ray_visible(target: CharacterBody3D) -> bool:
	var from: Vector3 = player.global_position + Vector3(0.0, 0.5, 0.0)
	var to: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)
	var space: PhysicsDirectSpaceState3D = device.get_world_3d().direct_space_state
	if space == null:
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 5)
	query.exclude = [player.get_rid(), target.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	return not hit.has("collider")


func hero_strike() -> void:
	if not enabled():
		return
	var target: Node3D = eligible_target()
	if target == null:
		return
	target.receive_hit()
	print("ASHBOUND_ENEMY_HERO_HIT kind=%s" % [target.kind])
