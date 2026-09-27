extends Node3D
## SNOW-01 / SAND-01 (owner 27 Sep): the hero leaves prints in the snow of the mountains and in the
## desert sand - left and right in turn, fading after a minute; the last PRINTS stay (a ring of
## quads sharing one mesh and material; each keeps its time and depth as instance uniforms).
const PRINTS := 96
const STRIDE_SIDE := 0.11

var world: Node3D
var _prints: Array[MeshInstance3D] = []
var _next := 0
var _left := true
var _material: ShaderMaterial


func configure(scene: Node3D) -> void:
	world = scene
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.32)
	quad.orientation = PlaneMesh.FACE_Y
	_material = ShaderMaterial.new()
	_material.shader = preload("res://assets/shaders/world_footprint.gdshader")
	for i in PRINTS:
		var print := MeshInstance3D.new()
		print.mesh = quad
		print.material_override = _material
		print.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		print.visible = false
		add_child(print)
		_prints.append(print)


func _process(_delta: float) -> void:
	if _material != null:
		_material.set_shader_parameter("now", Time.get_ticks_msec() / 1000.0)


## A step at `at` (scene frame) on `kind` ground ("snow", "sand"); anything else leaves no print.
func step(at: Vector3, kind: String) -> void:
	if kind != "snow" and kind != "sand":
		return
	var facing: Vector3 = world.player.facing_direction
	facing.y = 0.0
	if facing.length() < 0.01:
		return
	facing = facing.normalized()
	var side := Vector3(-facing.z, 0.0, facing.x) * (STRIDE_SIDE if _left else -STRIDE_SIDE)
	_left = not _left
	var p := at + side
	p.y = world.grass_height(p.x, p.z) + 0.03
	var print := _prints[_next]
	print.global_transform = Transform3D(Basis.looking_at(-facing, Vector3.UP), p)
	print.set_instance_shader_parameter("made", Time.get_ticks_msec() / 1000.0)
	print.set_instance_shader_parameter("depth", 0.6 if kind == "snow" else 0.5)
	print.visible = true
	_next = (_next + 1) % PRINTS
