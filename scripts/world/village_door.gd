extends Node3D
## The closed portal's local +Z is outside. Keep one swing side until fully shut.
const DURATION := 0.7
const STEPS := 90
const OBSTACLE_LAYER := 8
const CREAK = preload("res://assets/audio/village-v1/door-creak.ogg")
const CLOSE = preload("res://assets/audio/village-v1/door-close.ogg")
var building_id := ""
var entry := Vector3.ZERO
var leaves: Array[Dictionary] = []
var fraction := 0.0
var goal := 0.0
var opening_sign := 1.0
var own_bodies: Array[RID] = []
var moving := false
var blocked := false
var suspended := false
var highlighted := false
var audio: AudioStreamPlayer3D
var highlight: StandardMaterial3D

func configure(model: Node3D, identity: String, entry_point: Vector3) -> void:
	building_id = identity
	entry = entry_point
	highlight = StandardMaterial3D.new()
	highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight.albedo_color = Color(0.72, 0.58, 0.32, 0.16)
	for node in model.find_children("*entry_hinge*", "Node3D", true, false):
		var pivot := node as Node3D
		# Godot imports glTF extras as one dictionary, not individual metadata keys.
		var metadata: Dictionary = pivot.get_meta("extras", {})
		for child in pivot.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			var body := AnimatableBody3D.new()
			body.name = "DoorCollision"
			body.collision_layer = 1 | OBSTACLE_LAYER
			body.collision_mask = 2 | 4
			body.sync_to_physics = false
			body.set_meta("village_door_id", identity)
			pivot.add_child(body)
			own_bodies.append(body.get_rid())
			body.global_transform = mesh.global_transform
			var collider := CollisionShape3D.new()
			collider.shape = mesh.mesh.create_convex_shape()
			body.add_child(collider)
			leaves.append({"pivot": pivot, "rest": pivot.transform, "local_shape": body.transform,
				"shape": collider.shape, "mesh": mesh, "body": body,
				"angle": deg_to_rad(float(metadata.get("open_angle_degrees", -90.0)))})
	audio = AudioStreamPlayer3D.new()
	audio.position = entry + Vector3.UP
	audio.max_distance = 12.0
	audio.unit_size = 2.0
	audio.volume_db = -8.0
	audio.stream = CREAK
	add_child(audio)

func target_point() -> Vector3:
	return to_global(entry + Vector3.UP)

func set_highlight(enabled: bool) -> void:
	if enabled == highlighted: return
	highlighted = enabled
	for leaf in leaves:
		leaf.mesh.material_overlay = highlight if enabled else null

func can_interact(actor: CharacterBody3D) -> bool:
	if suspended or actor == null: return false
	var offset := actor.global_position - to_global(entry)
	if Vector2(offset.x, offset.z).length() > 2.8 or absf(offset.y) > 1.5: return false
	var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP, target_point(), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider.get_meta("village_door_id", "") == building_id

func try_toggle(actor: CharacterBody3D) -> bool:
	if not can_interact(actor) or moving and not blocked: return false
	if moving:
		# A jammed leaf may return along the same arc; never choose a new side here.
		goal = 1.0 - goal
	elif is_zero_approx(fraction):
		opening_sign = -1.0 if to_local(actor.global_position).z >= entry.z else 1.0
		goal = 1.0
	else:
		goal = 0.0
	blocked = false
	moving = true
	audio.stream = CREAK
	audio.pitch_scale = randf_range(.96,1.04)
	if DisplayServer.get_name() != "headless": audio.play()
	return true

func _pose(leaf: Dictionary, value: float) -> Transform3D:
	var pose: Transform3D = leaf.rest
	pose.basis = pose.basis * Basis(Vector3.UP, leaf.angle * opening_sign * value)
	return pose

func _arc_clear(start: float, end: float) -> bool:
	var count := maxi(1, ceili(absf(end - start) * STEPS))
	var space := get_world_3d().direct_space_state
	# Test where the leaf is going, not its resting contact against the actor.
	for i in range(1, count + 1):
		var value := lerpf(start, end, float(i) / count)
		for leaf in leaves:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = leaf.shape
			query.transform = leaf.pivot.get_parent().global_transform * _pose(leaf, value) * leaf.local_shape
			# Floor/jambs define the portal; actors, furniture and other doors obstruct it.
			query.collision_mask = 2 | 4 | OBSTACLE_LAYER
			query.exclude = own_bodies
			query.margin = 0.002
			if not space.intersect_shape(query, 1).is_empty(): return false
	return true

func _physics_process(delta: float) -> void:
	if not moving or suspended: return
	if is_equal_approx(fraction, goal):
		moving = false
		blocked = false
		return
	var next := move_toward(fraction, goal, delta / DURATION)
	blocked = not _arc_clear(fraction, next)
	if blocked:
		audio.stop()
		return
	fraction = next
	for leaf in leaves:
		leaf.pivot.transform = _pose(leaf, fraction)
	if is_equal_approx(fraction, goal):
		moving = false
		if is_zero_approx(goal):
			audio.stream = CLOSE
			if DisplayServer.get_name() != "headless": audio.play()

func _exit_tree() -> void:
	if is_instance_valid(audio): audio.stop()
