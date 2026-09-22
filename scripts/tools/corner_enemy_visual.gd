extends "res://scripts/courtyard/courtyard_character_visual.gd"

var _kind: String = ""
var _stored_action: StringName = &"idle"
var _stored_facing: Vector3 = Vector3.FORWARD
var _stored_progress: float = 0.0
var _stored_cue: bool = false
var _hit_flash: bool = false
var _configured := false
var _cue_root: Node3D

func _ready() -> void:
	pass

func setup(kind: String) -> void:
	if _configured:
		return
	_kind = kind
	var frames_path := "res://assets/characters/courtyard/enemy-preview/%s_frames.tres" % kind
	var res := load(frames_path)
	var frames := res as SpriteFrames
	if frames == null:
		push_error("corner_enemy_visual: missing SpriteFrames at %s" % frames_path)
		return
	var body := AnimatedSprite3D.new()
	body.name = "Body"
	body.sprite_frames = frames
	body.animation = &"idle_front"
	body.shaded = false
	body.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	body.alpha_scissor_threshold = 0.25
	body.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var pose := AnimatedSprite3D.new()
	pose.name = "PocketPose"
	pose.sprite_frames = frames
	pose.animation = &"idle_front"
	pose.shaded = false
	pose.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	pose.alpha_scissor_threshold = 0.25
	pose.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	pose.visible = false
	add_child(body)
	add_child(pose)
	_configured = true
	super._ready()
	_build_cue()

func _build_cue() -> void:
	_cue_root = Node3D.new()
	_cue_root.name = "AttackCue"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	mat.emission_energy_multiplier = 2.0
	var y := 0.7 if _kind == "wolf" else 1.3
	for i in range(3):
		var spoke := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.4, 0.025, 0.025)
		spoke.mesh = mesh
		spoke.material_override = mat
		spoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spoke.position = Vector3(0.0, y, 0.04)
		spoke.rotation_degrees.z = float(i * 60)
		_cue_root.add_child(spoke)
	add_child(_cue_root)

func present(action: String, facing: Vector3, progress: float, cue: bool, hit_flash: bool) -> void:
	if not _configured:
		return
	_stored_action = StringName(action)
	_stored_facing = facing
	_stored_progress = progress
	_stored_cue = cue
	_hit_flash = hit_flash
	_process(0.0)

func _process(delta: float) -> void:
	if not _configured:
		return
	update_visual(_stored_action, _stored_facing)
	var body := get_node_or_null("Body") as AnimatedSprite3D
	if body != null:
		body.pause()
		var frame := 0
		if _stored_action == &"walk":
			frame = int(clampf(_stored_progress, 0.0, 0.999) * 2.0)
		body.set_frame_and_progress(frame, 0)
		body.modulate = Color(1.0, 0.35, 0.4) if _hit_flash else Color.WHITE
	if _cue_root != null:
		_cue_root.visible = _stored_cue
	super._process(delta)
