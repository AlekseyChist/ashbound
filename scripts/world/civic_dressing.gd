extends Node3D
## FOREST-CITY-01 (owner 28 Sep, after the hand test): the town hall and the barracks lived in - a
## fire in the hearth's firebox (the model's `*_fire` marker), lanterns hung from the tie beams
## (`*_lamp*` markers), rugs and the CC0 tavern props. Few lights, no shadows; the flames, the
## lights and the crackle sleep when the hero is far.
const PROPS := "res://assets/props/tavern-v1/%s.glb"
const FIRE_SOUND := "res://assets/audio/village-v1/fire.ogg"
const RUG_TEXTURE := "res://assets/props/tavern-v1/rugs/fabric_pattern_05_diff_1k.jpg"
const RUG_NORMAL := "res://assets/props/tavern-v1/rugs/fabric_pattern_05_nor_1k.jpg"
const AWAKE := 45.0
## Codex's civic props (assets/props/civic-v1/README.md): a CC0 hand axe, a generated sheepskin.
const AXE := "res://assets/props/civic-v1/wooden_axe_03.glb"
const AXE_FOOT := 0.223756
const PELT := "res://assets/props/civic-v1/sheepskin-rug-v1.png"
## Sheepskins on the floor: [centre (y = floor), yaw°] - before the elder's dais, by the hearth.
const PELTS := {"R01": [[Vector3(7.4, 0.012, -2.0), 0.0], [Vector3(-8.3, 0.012, -3.8), 90.0]]}
## Hand axes standing against the barracks wall by the spear rack: [foot position, lean°, turn°].
const AXES := {"K01": [[Vector3(9.55, 0.0, 4.2), -12.0, 90.0], [Vector3(9.55, 0.0, 0.45), -10.0, 95.0],
	[Vector3(9.55, 0.0, 0.7), -12.0, 85.0]]}

## Per building, in the hall's Godot frame (y = the floor, z = -y of the Blender model):
## [prop, position, yaw°, scale].
const PLACED := {
	"R01": [
		["jug_01", Vector3(-3.0, 0.78, -2.1), 0.0, 1.0], ["brass_goblets", Vector3(-1.2, 0.78, -2.0), 30.0, 1.0],
		["brass_goblets", Vector3(2.4, 0.78, -2.2), -20.0, 1.0], ["carved_wooden_plate", Vector3(0.6, 0.78, -2.1), 0.0, 1.0],
		["wicker_basket_01", Vector3(-10.4, 0.0, -1.5), 0.0, 1.0], ["wine_barrel_01", Vector3(6.4, 0.0, -5.2), 0.0, 1.0],
	],
	"K01": [
		["wine_barrel_01", Vector3(9.0, 0.0, -2.4), 0.0, 1.0], ["wine_barrel_01", Vector3(9.0, 0.0, -1.5), 40.0, 1.0],
		["jug_01", Vector3(4.2, 0.78, 0.6), 0.0, 1.0], ["carved_wooden_plate", Vector3(5.4, 0.78, 0.6), 0.0, 1.0],
		["carved_wooden_plate", Vector3(6.2, 0.78, 0.6), 0.0, 1.0], ["wicker_basket_01", Vector3(-8.2, 0.0, 4.0), 0.0, 1.0],
	],
}
## Rugs: [centre (y = floor), size, tint]. The hall's long rug under the council table, a darker
## hide before the elder's dais and by the hearth; in the barracks one worn runner under the table.
const RUGS := {
	"R01": [[Vector3(0, 0.01, -2.1), Vector2(13.5, 3.4), Color(0.85, 0.62, 0.5)],
],
	"K01": [[Vector3(5.0, 0.01, 0.6), Vector2(5.0, 2.6), Color(0.6, 0.5, 0.42)]],
}

var hall: Node3D
var flames: Array[CPUParticles3D] = []
var fire_lights: Array[OmniLight3D] = []
var lights: Array[OmniLight3D] = []
var sounds: Array[AudioStreamPlayer3D] = []
var awake := true
var _time := 0.0
var _check := 0.0


func dress(building: Node3D, id: String, floor_height: float) -> void:
	hall = building
	name = "Dressing"
	building.add_child(self)
	for marker in building.model.find_children("*_fire", "Node3D", true, false):
		_fire(building.to_local((marker as Node3D).global_position))
	for marker in building.model.find_children("*_lamp*", "Node3D", true, false):
		_lantern(building.to_local((marker as Node3D).global_position))
	for rug in RUGS.get(id, []):
		_rug(rug[0] + Vector3.UP * floor_height, rug[1], rug[2])
	for item in PLACED.get(id, []):
		_place(item[0], item[1] + Vector3.UP * floor_height, item[2], item[3])
	for pelt in PELTS.get(id, []):
		_pelt(pelt[0] + Vector3.UP * floor_height, pelt[1])
	for axe in AXES.get(id, []):
		_axe(axe[0] + Vector3.UP * floor_height, axe[1], axe[2])


func _place(model: String, at: Vector3, yaw: float, scale_factor: float) -> void:
	var node: Node3D = (load(PROPS % model) as PackedScene).instantiate()
	node.position = at
	node.rotation.y = deg_to_rad(yaw)
	node.scale = Vector3.ONE * scale_factor
	add_child(node)
	for mesh in node.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).visibility_range_end = 40.0


## A lantern on a short rope from the tie beam's underside (`top`), with a small warm light.
func _lantern(top: Vector3) -> void:
	var at := top - Vector3(0, 1.0, 0)
	_place("wooden_lantern_01", at, 0.0, 1.0)
	var rope := MeshInstance3D.new()
	rope.name = "LanternRope"
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.65, 0.02)
	rope.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.18, 0.1)
	rope.material_override = mat
	rope.position = top - Vector3(0, 0.325, 0)
	add_child(rope)
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.position = at + Vector3(0, 0.18, 0)
	light.omni_range = 6.5
	light.light_energy = 0.75
	light.light_color = Color(1.0, 0.76, 0.5)
	add_child(light)
	lights.append(light)


## Flames from particles on the firewood, a flickering light in front of the firebox, the crackle.
func _fire(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.name = "HearthFlames"
	p.position = at
	p.amount = 24
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.25, 0.04, 0.3)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 1.4, 0)
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.55
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0.6))
	fade.add_point(Vector2(0.3, 1.0))
	fade.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = fade
	var colours := Gradient.new()
	colours.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	colours.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
	colours.add_point(0.4, Color(1.0, 0.45, 0.08, 0.9))
	p.color_ramp = colours
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.42)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _flame_texture()
	quad.material = mat
	p.mesh = quad
	add_child(p)
	flames.append(p)
	var light := OmniLight3D.new()
	light.name = "HearthLight"
	# In front of the firebox: both hearths stand at the -x gable and open to +x.
	light.position = at + Vector3(0.8, 0.6, 0)
	light.omni_range = 8.0
	light.light_energy = 1.6
	light.light_color = Color(1.0, 0.55, 0.25)
	add_child(light)
	fire_lights.append(light)
	var crackle := AudioStreamPlayer3D.new()
	crackle.name = "HearthSound"
	var stream: AudioStream = load(FIRE_SOUND)
	if stream is AudioStreamOggVorbis:
		stream = (stream as AudioStreamOggVorbis).duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	crackle.stream = stream
	crackle.bus = "VillageSound" if AudioServer.get_bus_index("VillageSound") >= 0 else "Master"
	crackle.max_distance = 14.0
	crackle.unit_size = 2.5
	crackle.volume_db = -8.0
	crackle.position = at
	crackle.autoplay = true
	add_child(crackle)
	sounds.append(crackle)


func _pelt(centre: Vector3, yaw: float) -> void:
	var rug := MeshInstance3D.new()
	rug.name = "Sheepskin"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.2, 1.92)
	rug.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(PELT)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.roughness = 1.0
	mat.metallic_specular = 0.2
	rug.material_override = mat
	rug.position = centre
	rug.rotation.y = deg_to_rad(yaw)
	add_child(rug)


## The axe's handle end on the floor, its head leaning `lean`° against the wall (towards +x).
func _axe(foot: Vector3, lean: float, turn: float) -> void:
	var holder := Node3D.new()
	holder.position = foot
	holder.rotation = Vector3(0, deg_to_rad(turn), deg_to_rad(lean))
	add_child(holder)
	var axe: Node3D = (load(AXE) as PackedScene).instantiate()
	axe.position = Vector3(0, AXE_FOOT, 0)
	holder.add_child(axe)


func _rug(centre: Vector3, size: Vector2, tint: Color) -> void:
	var rug := MeshInstance3D.new()
	rug.name = "Rug"
	var plane := PlaneMesh.new()
	plane.size = size
	rug.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(RUG_TEXTURE)
	mat.normal_enabled = true
	mat.normal_texture = load(RUG_NORMAL)
	mat.albedo_color = tint
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(size.x / 1.2, size.y / 1.2, 1)
	rug.material_override = mat
	rug.position = centre
	add_child(rug)


static var _flame_cache: ImageTexture

## A soft round flame drawn once: bright middle, fading edges.
static func _flame_texture() -> ImageTexture:
	if _flame_cache != null:
		return _flame_cache
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var q := Vector2((x + 0.5) / size - 0.5, (y + 0.5) / size - 0.5)
			q.y *= 0.75
			var a := clampf(1.0 - q.length() * 2.2, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a * a))
	_flame_cache = ImageTexture.create_from_image(image)
	return _flame_cache


## The crackle is stopped and let go with the hall, never left playing a looped stream.
func _exit_tree() -> void:
	for crackle in sounds:
		crackle.stop()
		crackle.stream = null
	sounds.clear()


func _process(delta: float) -> void:
	_time += delta
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		var camera := get_viewport().get_camera_3d()
		var near := camera != null and camera.global_position.distance_to(global_position) < AWAKE
		if near != awake:
			awake = near
			for p in flames:
				p.emitting = near
			for l in fire_lights + lights:
				l.visible = near
			for s in sounds:
				s.stream_paused = not near
	if awake:
		for l in fire_lights:
			l.light_energy = 1.45 + 0.3 * sin(_time * 9.1) + 0.18 * sin(_time * 23.7 + 1.3)
