class_name FistDefenseController
extends Node
## Isolated training-device prototype: wooden post with a padded striking arm.
## Not a humanoid NPC; no HP, wounds, rewards, unlocks or saves.

signal resolved(result: String)

enum Phase { IDLE, WINDUP, RECOVERY }

const WINDUP_TIME: float = 0.8
const RECOVERY_TIME: float = 0.7
const REACH: float = 1.9
const ATTACK_HALF_CONE: float = 30.0
const BLOCK_HALF_CONE: float = 55.0
const PERFECT_WINDOW: float = 0.18
const PERFECT_REFRACTORY: float = 0.45
const MAX_HEIGHT_OFFSET: float = 1.0
const CONTACT_EPS: float = 1e-8

var sandbox: Node
var player: CharacterBody3D
var device: Node3D

var _phase: int = Phase.IDLE
var _phase_time: float = 0.0
var _sim_time: float = 0.0
var _strike_dir: Vector3 = Vector3.FORWARD
var _guarding: bool = false
var _guard_started: float = -1.0
var _perfect_eligible: bool = false
var _refractory_until: float = -1.0
var _last_result: String = ""
var _contacts: int = 0
var _contact_done: bool = false

var _menu_open: bool = false
var _focus_lost: bool = false
var _paused: bool = false

var _pad_mesh: MeshInstance3D
var _pad_material: StandardMaterial3D
var _arm_pivot: Node3D
var _hero_visual: Node3D
var _hero_visual_base: Vector3 = Vector3.ZERO
var _recoil_until: float = -1.0
var _recoil_dir: Vector3 = Vector3.ZERO
var _deflect_until: float = -1.0

func _ready() -> void:
	# No-op; setup() is the entry point.
	pass

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_focus_lost = true
			_cancel_active()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_focus_lost = false
		NOTIFICATION_APPLICATION_PAUSED:
			_paused = true
			_cancel_active()
		NOTIFICATION_APPLICATION_RESUMED:
			_paused = false
		NOTIFICATION_PAUSED:
			_cancel_active()

func _physics_process(delta: float) -> void:
	advance(delta)

func setup(sbx: Node, plr: CharacterBody3D) -> void:
	sandbox = sbx
	player = plr
	device = Node3D.new()
	device.name = "FistDefenseDevice"
	device.position = Vector3(0.0, 0.0, 2.4)
	add_child(device)
	_build_device_meshes()
	if player != null:
		player.position = Vector3(0.0, 0.1, 4.0)
		if "facing_direction" in player:
			player.set("facing_direction", Vector3(0.0, 0.0, -1.0))
		_hero_visual = _find_hero_visual()
		if _hero_visual != null:
			_hero_visual_base = _hero_visual.position
	_apply_focus_state()
	_apply_defense_camera()
	print("ASHBOUND_DEFENSE_READY")

func start_swing() -> bool:
	if not _gameplay_enabled():
		return false
	if _phase != Phase.IDLE:
		return false
	var dir: Vector3 = player.global_position - device.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 0.0, -1.0)
	_strike_dir = dir.normalized()
	_phase = Phase.WINDUP
	_phase_time = 0.0
	_contact_done = false
	return true

func set_guard(pressed: bool) -> bool:
	if not pressed:
		_release_guard()
		return true
	if _guarding:
		# Duplicate press while already held retains the original edge.
		return true
	if not _gameplay_enabled():
		return false
	if player == null or not player.is_attack_allowed():
		return false
	if _menu_open or _focus_lost or _paused:
		return false
	if player.is_attacking():
		return false
	_guarding = true
	_guard_started = _sim_time
	# Eligibility is set on the DOWN edge only, and only if refractory has expired.
	_perfect_eligible = _sim_time >= _refractory_until
	# Arm the refractory from this fresh edge so release/repress cannot re-qualify.
	_refractory_until = _sim_time + PERFECT_REFRACTORY
	return true

func reset_trial() -> void:
	if not _gameplay_enabled():
		return
	_clear_state()
	# reset_trial clears contacts/result/refractory; monotonic time is preserved.
	_contacts = 0
	_last_result = ""
	_refractory_until = -1.0
	if player != null and player.has_method("stop_input"):
		player.stop_input()
		player.position = Vector3(0.0, 0.1, 4.0)
		if "facing_direction" in player:
			player.set("facing_direction", Vector3(0.0, 0.0, -1.0))
	device.global_position = Vector3(0.0, 0.0, 2.4)
	_restore_visual()
	_apply_defense_camera()

func _apply_defense_camera() -> void:
	# DEFENSE preview only: snap the comparison camera to the player, then
	# orbit 45 degrees horizontally (same pitch/distance) so the post sits
	# beside the body and the windup/pad stay visible. F4 orbital control
	# remains; main camera and player facing are untouched.
	var level: Node = sandbox.get("level") if sandbox != null else null
	if level == null or not level.has_method("_snap_camera_to_player"):
		return
	level._snap_camera_to_player()
	var cam: Node3D = level.get_node_or_null("CameraRig") as Node3D
	if cam == null or not cam.has_method("rotate_view"):
		return
	var sensitivity: float = cam.mouse_sensitivity
	if is_zero_approx(sensitivity):
		sensitivity = 1.0
	cam.rotate_view(Vector2(deg_to_rad(45.0) / sensitivity, 0.0))


func cancel_trial() -> void:
	# Cancel preserves contacts/result and the clock; only active FX/state reset.
	_clear_state()
	_restore_visual()

func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	_apply_focus_state()
	if _focus_lost or _paused:
		_cancel_active()
		return
	if not _gameplay_enabled():
		cancel_trial()
		return
	var remaining_delta: float = delta
	while remaining_delta > 0.0:
		if _phase == Phase.WINDUP:
			var to_contact: float = WINDUP_TIME - _phase_time
			var step: float = minf(to_contact, remaining_delta)
			_phase_time += step
			_sim_time += step
			remaining_delta -= step
			if _phase_time >= WINDUP_TIME - CONTACT_EPS:
				# Snap to the exact boundary; never advance contact earlier.
				_phase_time = WINDUP_TIME
				_resolve_contact()
				# Continue into recovery with any leftover time.
		elif _phase == Phase.RECOVERY:
			var to_idle: float = RECOVERY_TIME - _phase_time
			var step: float = minf(to_idle, remaining_delta)
			_phase_time += step
			_sim_time += step
			remaining_delta -= step
			if _phase_time >= RECOVERY_TIME - CONTACT_EPS:
				_phase = Phase.IDLE
				_phase_time = 0.0
				# Continue into idle with any leftover time.
		else:
			break
	if remaining_delta > 0.0 and _phase == Phase.IDLE:
		_sim_time += remaining_delta
	_update_arm_visual()
	_update_recoil(delta)


func snapshot() -> Dictionary:
	return {
		"time": _sim_time,
		"phase": _phase_name(),
		"guarding": _guarding,
		"result": _last_result,
		"contacts": _contacts,
		"guard_started": _guard_started,
	}

func _phase_name() -> String:
	match _phase:
		Phase.WINDUP:
			return "windup"
		Phase.RECOVERY:
			return "recovery"
		_:
			return "idle"

func _gameplay_enabled() -> bool:
	if sandbox == null or player == null:
		return false
	if not player.is_attack_allowed():
		return false
	if _focus_lost or _paused:
		return false
	var menu: Node = _find_menu()
	if menu != null and menu.get_menu_state() != 0:
		return false
	return true

func _find_menu() -> Node:
	if sandbox == null:
		return null
	var level: Node = sandbox.get("level")
	if level == null or not (level is Node):
		return null
	return level.get_node_or_null("InventoryMenu")

func _apply_focus_state() -> void:
	var menu: Node = _find_menu()
	_menu_open = menu != null and menu.get_menu_state() != 0
	if _menu_open:
		_cancel_active()

func _cancel_active() -> void:
	if _phase != Phase.IDLE or _guarding:
		_clear_state()
	_restore_visual()

func _clear_state() -> void:
	_phase = Phase.IDLE
	_phase_time = 0.0
	_guarding = false
	_guard_started = -1.0
	_perfect_eligible = false
	_contact_done = false
	_recoil_until = -1.0
	_deflect_until = -1.0
	_set_pad_color(Color(0.85, 0.65, 0.4))

func _release_guard() -> void:
	if not _guarding:
		return
	_guarding = false
	_guard_started = -1.0
	_perfect_eligible = false

func _resolve_contact() -> void:
	if _contact_done:
		return
	# Revalidate the enable gate at the exact contact boundary; if disabled,
	# cancel immediately with ZERO contacts and no signal.
	if not _gameplay_enabled():
		_cancel_active()
		return
	_contact_done = true
	var result: String = "miss"
	var to_player: Vector3 = player.global_position - device.global_position
	var flat: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	var dist: float = flat.length()
	if absf(to_player.y) > MAX_HEIGHT_OFFSET or dist > REACH:
		result = "miss"
	elif not _in_cone(flat, _strike_dir, ATTACK_HALF_CONE):
		result = "miss"
	elif not _ray_visible():
		result = "obstructed"
	else:
		var trained: bool = _is_trained()
		var frontal: bool = _frontal_guard()
		if trained and _guarding and frontal:
			# Perfect iff this contact consumes a fresh eligible guard edge
			# started within PERFECT_WINDOW before the contact.
			var dt: float = _sim_time - _guard_started
			if _perfect_eligible and dt >= 0.0 and dt <= PERFECT_WINDOW:
				result = "perfect_block"
			else:
				result = "block"
		else:
			result = "hit"
	_contacts += 1
	_last_result = result
	# Refractory is set on the guard DOWN edge (see set_guard); consume eligibility here.
	_perfect_eligible = false
	_apply_result_fx(result)
	_phase = Phase.RECOVERY
	_phase_time = 0.0
	resolved.emit(result)
	print("ASHBOUND_DEFENSE_RESULT result=%s count=%d" % [result, _contacts])

func _is_trained() -> bool:
	if sandbox == null or not sandbox.has_method("get"):
		return false
	var tech: Variant = sandbox.get("technique")
	return tech == "trained"

func _frontal_guard() -> bool:
	# Frontal guard compares the incoming direction to the player's own facing,
	# never to the attack cone. Camera never affects this.
	if player == null or not ("facing_direction" in player):
		return false
	var facing: Vector3 = player.get("facing_direction")
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return false
	facing = facing.normalized()
	var to_device: Vector3 = device.global_position - player.global_position
	var flat: Vector3 = Vector3(to_device.x, 0.0, to_device.z)
	if flat.length_squared() < 0.0001:
		return true
	return _in_cone(flat, facing, BLOCK_HALF_CONE)

func _in_cone(flat: Vector3, dir: Vector3, half_deg: float) -> bool:
	if flat.length_squared() < 0.0001:
		return true
	var cos_a: float = flat.normalized().dot(dir)
	return cos_a >= cos(deg_to_rad(half_deg))

func _ray_visible() -> bool:
	var from: Vector3 = device.global_position + Vector3(0.0, 1.0, 0.0)
	var to: Vector3 = player.global_position + Vector3(0.0, 1.0, 0.0)
	var space: PhysicsDirectSpaceState3D = device.get_world_3d().direct_space_state
	if space == null:
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	return not hit.has("collider")

func _apply_result_fx(result: String) -> void:
	match result:
		"hit":
			_set_pad_color(Color(0.9, 0.25, 0.2))
			_start_recoil()
		"block", "perfect_block":
			_set_pad_color(Color(0.3, 0.5, 0.95) if result == "block" else Color(1.0, 0.85, 0.3))
			_deflect_until = _sim_time + 0.25
		_:
			_set_pad_color(Color(0.85, 0.65, 0.4))

func _start_recoil() -> void:
	if _hero_visual == null:
		return
	# Recoil goes AWAY from the striker, i.e. along +_strike_dir.
	_recoil_dir = _strike_dir
	_recoil_until = _sim_time + 0.2

func _update_recoil(delta: float) -> void:
	if _hero_visual == null:
		return
	if _recoil_until > 0.0 and _sim_time < _recoil_until:
		var t: float = clampf((_recoil_until - _sim_time) / 0.2, 0.0, 1.0)
		# Convert the world strike vector into the Visual's local basis so the
		# player's own rotation never reverses the recoil direction.
		var local_dir: Vector3 = _hero_visual.get_parent().global_transform.basis.inverse() * _recoil_dir
		_hero_visual.position = _hero_visual_base + local_dir * (0.15 * t)
	elif _deflect_until > 0.0 and _sim_time < _deflect_until:
		pass
	else:
		_hero_visual.position = _hero_visual_base


func _restore_visual() -> void:
	if _hero_visual != null:
		_hero_visual.position = _hero_visual_base
	_recoil_until = -1.0
	_deflect_until = -1.0

func _find_hero_visual() -> Node3D:
	if player == null:
		return null
	var visual: Node = player.get_node_or_null("Visual")
	if visual != null and visual is Node3D:
		return visual as Node3D
	return null

func _update_arm_visual() -> void:
	if _arm_pivot == null or device == null:
		return
	# Orient the whole arm toward the locked world strike direction.
	var target: Vector3 = _strike_dir
	target.y = 0.0
	if target.length_squared() < 0.0001:
		target = Vector3(0.0, 0.0, -1.0)
	_arm_pivot.rotation = _rotation_toward(target)
	# Prismatic slide along the strike axis (local +Z):
	# neutral pad center ~1.25 from post, full extension ~1.65 (within REACH 1.9).
	# Windup: monotonic visible retraction held through the end of windup so the
	# pad never moves toward the hero before contact; then forward strike at .8.
	var punch: float = 0.0
	match _phase:
		Phase.WINDUP:
			# Retract monotonically to -0.35 and HOLD it until contact.
			var t: float = clampf(_phase_time / WINDUP_TIME, 0.0, 1.0)
			punch = -0.35 * minf(t / 0.25, 1.0)
		Phase.RECOVERY:
			# Snap out at contact then retract to neutral.
			var t: float = clampf(_phase_time / RECOVERY_TIME, 0.0, 1.0)
			punch = lerpf(0.4, 0.0, t)
		_:
			punch = 0.0
	if _deflect_until > 0.0 and _sim_time < _deflect_until:
		# Pad deflection: actually push the pad back along the strike axis.
		var dt: float = clampf((_deflect_until - _sim_time) / 0.25, 0.0, 1.0)
		punch -= 0.3 * dt
	_arm_pivot.position = Vector3(0.0, 1.4, 0.0) + target * punch
	# Restore the neutral pad color once fully back in idle; never touch the
	# color while a contact effect (recoil/deflect) is still visible.
	var recoil_active: bool = _recoil_until > 0.0 and _sim_time < _recoil_until
	var deflect_active: bool = _deflect_until > 0.0 and _sim_time < _deflect_until
	if not recoil_active and not deflect_active:
		_set_pad_color(Color(0.85, 0.65, 0.4))


func _rotation_toward(dir: Vector3) -> Vector3:
	# Yaw only: the arm's local +Z must follow the locked world strike direction.
	var yaw: float = atan2(dir.x, dir.z)
	return Vector3(0.0, yaw, 0.0)


func _set_pad_color(c: Color) -> void:
	if _pad_material != null:
		_pad_material.albedo_color = c

func _build_device_meshes() -> void:
	# Placeholder device: fixed wooden post + prismatic sliding spar with pad.
	var post_mat: StandardMaterial3D = StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.55, 0.4, 0.25)
	var post: MeshInstance3D = MeshInstance3D.new()
	post.name = "Post"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.25, 1.6, 0.25)
	post.mesh = box
	post.material_override = post_mat
	post.position = Vector3(0.0, 0.8, 0.0)
	device.add_child(post)

	_arm_pivot = Node3D.new()
	_arm_pivot.name = "ArmPivot"
	_arm_pivot.position = Vector3(0.0, 1.4, 0.0)
	device.add_child(_arm_pivot)

	var arm_mat: StandardMaterial3D = StandardMaterial3D.new()
	arm_mat.albedo_color = Color(0.7, 0.5, 0.3)
	var arm: MeshInstance3D = MeshInstance3D.new()
	arm.name = "Arm"
	var arm_box: BoxMesh = BoxMesh.new()
	# Wooden spar from post to pad along local +Z (pad center at ~1.25 neutral).
	# Length 2.0 with a 0.45 rear overhang; centered so the front end sits at
	# the pad center (1.25) when extended, and the rear still passes the post
	# at full retraction (-0.35).
	arm_box.size = Vector3(0.18, 0.18, 2.0)
	arm.mesh = arm_box
	arm.material_override = arm_mat
	arm.position = Vector3(0.0, 0.0, 0.25)
	_arm_pivot.add_child(arm)

	_pad_material = StandardMaterial3D.new()
	_pad_material.albedo_color = Color(0.85, 0.65, 0.4)
	_pad_mesh = MeshInstance3D.new()
	_pad_mesh.name = "Pad"
	var pad_box: BoxMesh = BoxMesh.new()
	pad_box.size = Vector3(0.3, 0.3, 0.3)
	_pad_mesh.mesh = pad_box
	_pad_mesh.material_override = _pad_material
	_pad_mesh.position = Vector3(0.0, 0.0, 1.25)
	_arm_pivot.add_child(_pad_mesh)
