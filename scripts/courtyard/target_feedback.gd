extends Node3D
class_name CourtyardTargetFeedback

@export var interaction_color: Color = Color(0.78, 0.66, 0.38, 0.65)
@export var attack_color: Color = Color(0.78, 0.33, 0.27, 0.65)
@export var ring_radius: float = 0.48

var _target: Node3D
var _kind: StringName
var _body: AnimatedSprite3D
var _original_modulate: Color

func set_target(target: Node3D, kind: StringName, radius: float = 0.48) -> void:
	if not is_instance_valid(target):
		clear_target()
		return
	if is_instance_valid(_target) and _target == target and _kind == kind and is_equal_approx(ring_radius, radius):
		return
	_restore_body()
	_target = target
	_kind = kind
	ring_radius = radius
	_apply_ring_scale()
	_body = null
	if is_instance_valid(target):
		var body := target.get_node_or_null("Body")
		if body is AnimatedSprite3D:
			_body = body
			_original_modulate = _body.modulate
			_apply_tint()
	var ring_mat := $Ring.material_override as StandardMaterial3D
	if ring_mat:
		ring_mat.albedo_color = attack_color if kind == &"attack" else interaction_color
	$Ring.global_position = target.global_position + Vector3(0.0, 0.04, 0.0)
	$Ring.show()

func clear_target() -> void:
	_restore_body()
	_target = null
	_kind = &""
	_body = null
	_original_modulate = Color.WHITE
	$Ring.hide()

func get_target() -> Node3D:
	return _target

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = interaction_color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	$Ring.material_override = mat

func _process(_delta: float) -> void:
	if not is_instance_valid(_target):
		clear_target()
		return
	$Ring.global_position = _target.global_position + Vector3(0.0, 0.04, 0.0)

func _exit_tree() -> void:
	if is_instance_valid(_body):
		_body.modulate = _original_modulate

func _restore_body() -> void:
	if is_instance_valid(_body):
		_body.modulate = _original_modulate

func _apply_tint() -> void:
	if not is_instance_valid(_body):
		return
	var tint := Color(1.12, 1.08, 1.0, 1.0)
	if _kind == &"attack":
		tint = Color(1.15, 1.02, 0.98, 1.0)
	_body.modulate = _original_modulate * tint

func _apply_ring_scale() -> void:
	var s := ring_radius / 0.48
	$Ring.scale = Vector3(s, 0.25, s)
