extends Node3D
## Codex-owned local candidate. Explicitly attach to one cathedral model instance.
## Reuses the civic hearth's particle vocabulary; no global light/exposure changes.
const OWNER_KEY := &"cathedral_fire_runtime_owner"
const FIRE_SOUND := "res://assets/audio/village-v1/fire.ogg"
const Hearth = preload("res://scripts/world/civic_dressing.gd")
const FIRE_BASE := Vector3(2.6, 1.34, -6.3)
const WAKE_DISTANCE := 40.0
const SLEEP_DISTANCE := 45.0
var model: Node3D
var observer: Node3D
var placeholder: MeshInstance3D
var original_visible := true
var holder: Node3D
var flames: CPUParticles3D
var light: OmniLight3D
var sound: AudioStreamPlayer3D
var enabled := true
var awake := false
var effect_time := 0.0
var distance_check := 0.0

func configure(target_model: Node3D, target_observer: Node3D) -> bool:
	if not is_instance_valid(target_model) or not is_instance_valid(target_observer):
		return false
	if get_parent() != target_model or not target_model.is_inside_tree():
		return false
	var owner = target_model.get_meta(OWNER_KEY) if target_model.has_meta(OWNER_KEY) else null
	if owner is WeakRef and is_instance_valid(owner.get_ref()) and owner.get_ref() != self:
		return false
	var found: Array[MeshInstance3D] = []
	for mesh in target_model.find_children("fire basin flame*", "MeshInstance3D", true, false):
		found.append(mesh)
	if found.size() != 1:
		return false
	restore()
	model = target_model
	observer = target_observer
	placeholder = found[0]
	original_visible = placeholder.visible
	placeholder.visible = false
	model.set_meta(OWNER_KEY, weakref(self))
	transform = Transform3D.IDENTITY
	process_mode = Node.PROCESS_MODE_PAUSABLE
	holder = Node3D.new()
	holder.name = "BasinFireRuntime"
	add_child(holder)
	_make_flames()
	light = OmniLight3D.new()
	light.name = "BasinLight"
	light.position = FIRE_BASE + Vector3(0, 0.45, 0)
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 1.6
	light.omni_range = 8.0
	light.shadow_enabled = true
	holder.add_child(light)
	sound = AudioStreamPlayer3D.new()
	sound.name = "BasinCrackle"
	sound.position = FIRE_BASE
	var stream := load(FIRE_SOUND).duplicate() as AudioStreamOggVorbis
	stream.loop = true
	sound.stream = stream
	sound.bus = "VillageSound" if AudioServer.get_bus_index("VillageSound") >= 0 else "Master"
	sound.max_distance = 14.0
	sound.unit_size = 2.5
	sound.volume_db = -8.0
	holder.add_child(sound)
	awake = false
	effect_time = 0.0
	distance_check = 0.0
	_set_awake(enabled and model.is_visible_in_tree() and observer.global_position.distance_to(to_global(FIRE_BASE)) < WAKE_DISTANCE)
	set_process(true)
	return true

func set_enabled(value: bool) -> void:
	enabled = value
	distance_check = 0.0
	if not value and is_instance_valid(holder): _set_awake(false)

func _make_flames() -> void:
	flames = CPUParticles3D.new()
	flames.name = "BasinFlames"
	flames.position = FIRE_BASE
	flames.amount = 32
	flames.lifetime = 0.7
	flames.preprocess = 0.7
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(0.28, 0.015, 0.28)
	flames.direction = Vector3.UP
	flames.spread = 10.0
	flames.gravity = Vector3(0, 1.0, 0)
	flames.initial_velocity_min = 0.45
	flames.initial_velocity_max = 0.75
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.0
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0.6))
	fade.add_point(Vector2(0.3, 1.0))
	fade.add_point(Vector2(1, 0.0))
	flames.scale_amount_curve = fade
	var colours := Gradient.new()
	colours.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	colours.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
	colours.add_point(0.4, Color(1.0, 0.45, 0.08, 0.9))
	flames.color_ramp = colours
	var quad := QuadMesh.new()
	quad.size = Vector2(0.38, 0.62)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 0.35)
	mat.albedo_texture = Hearth._flame_texture()
	quad.material = mat
	flames.mesh = quad
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(flames)

func _set_awake(value: bool) -> void:
	awake = value
	holder.visible = value
	flames.emitting = value
	# Turning emission off alone leaves old particles simulating until their death.
	flames.speed_scale = 1.0 if value else 0.0
	light.visible = value
	if value:
		sound.play()
	else:
		sound.stop()

func _process(delta: float) -> void:
	if not is_instance_valid(model) or not is_instance_valid(observer):
		restore()
		return
	distance_check -= delta
	if distance_check <= 0.0:
		distance_check = 0.25
		var distance := observer.global_position.distance_to(to_global(FIRE_BASE))
		var next_awake := enabled and model.is_visible_in_tree() and distance < (SLEEP_DISTANCE if awake else WAKE_DISTANCE)
		if next_awake != awake:
			_set_awake(next_awake)
	if awake:
		effect_time += delta
		light.light_energy = 1.6 + 0.13 * sin(effect_time * 9.1) + 0.07 * sin(effect_time * 17.3)

func restore() -> void:
	set_process(false)
	if is_instance_valid(sound):
		sound.stop()
		sound.stream = null
	if is_instance_valid(holder):
		holder.visible = false
		remove_child(holder)
		holder.queue_free()
	if is_instance_valid(placeholder):
		placeholder.visible = original_visible
	if is_instance_valid(model):
		var owner = model.get_meta(OWNER_KEY) if model.has_meta(OWNER_KEY) else null
		if owner is WeakRef and owner.get_ref() == self:
			model.remove_meta(OWNER_KEY)
	model = null
	observer = null
	placeholder = null
	holder = null
	flames = null
	light = null
	sound = null
	awake = false

func _exit_tree() -> void:
	restore()
