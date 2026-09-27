extends Node3D
## WORLD-SEA-01 (D-099): the sea along the south edge of the map, to the horizon.
## The coast and the seabed are baked into the world heights (art/world/graybox-v1/build.py);
## this node adds the water surface and a stop at the map edge.
## WORLD-EDGES-01 (owner 27 Sep): the hero walks on the seabed into ever deeper water; he cannot
## swim, so where the water would reach his chest he stops and says he would drown.
const BEYOND := 6000.0
const STOP_DEPTH := 1.2
const WARN_EVERY := 4.0
const WARN_SHOWN := 3.0
const WATER := Color("35627a")

var world: Node3D
var _safe := Vector3.INF
var _warned_at := -INF

var level := 0.0
var coast_z := INF
var surface: MeshInstance3D
var floor_body: StaticBody3D

func build(scene: Node3D) -> void:
	var sea: Variant = scene.world_layout.get("sea")
	if not sea is Dictionary:
		return
	world = scene
	level = float(sea.level)
	for p: Array in sea.world_coast:
		coast_z = minf(coast_z, float(p[2]))
	var half: float = scene.HALF
	# The surface: from just north of the most northern coast point out past the horizon.
	var north := coast_z - 5.0
	var south := half + BEYOND
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0 * (half + BEYOND), south - north)
	surface = MeshInstance3D.new()
	surface.name = "SeaSurface"
	surface.mesh = plane
	surface.position = Vector3(0.0, level, (north + south) * 0.5)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = WATER
	material.roughness = 0.12
	material.metallic_specular = 0.6
	surface.material_override = material
	add_child(surface)
	# The map ends at its south edge; the water goes on, the hero stops (a safety behind the depth stop).
	floor_body = StaticBody3D.new()
	floor_body.name = "SeaEdge"
	add_child(floor_body)
	var wall := BoxShape3D.new()
	wall.size = Vector3(2.0 * half, 8.0, 2.0)
	var edge := CollisionShape3D.new()
	edge.shape = wall
	edge.position = Vector3(0.0, level + 2.0, half - 4.0)
	floor_body.add_child(edge)
	print("WORLD_SEA level=%.1f coast_z=%.0f stop_depth=%.1f" % [level, coast_z, STOP_DEPTH])


## Water depth over the ground at a scene point (0 on land).
func depth_at(p: Vector3) -> float:
	var local: Vector3 = world.world_root.to_local(p)
	return maxf(level - world.world_ground(local.x, local.z), 0.0)


func _physics_process(_delta: float) -> void:
	if world == null or world.player == null:
		return
	var player: CharacterBody3D = world.player
	var at := player.global_position
	if depth_at(at) <= STOP_DEPTH:
		_safe = at
		return
	# Too deep: back to the last point he could stand in, no drift further out.
	if _safe != Vector3.INF:
		player.global_position = _safe
	player.velocity = Vector3(0.0, minf(player.velocity.y, 0.0), 0.0)
	var now := Time.get_ticks_msec() / 1000.0
	if now - _warned_at > WARN_EVERY:
		_warned_at = now
		_warn()


func _warn() -> void:
	var hud: Node = world.hud
	if hud == null or not hud.has_method("show_message"):
		return
	hud.show_message("", "WORLD_SEA_TOO_DEEP")
	get_tree().create_timer(WARN_SHOWN).timeout.connect(func():
		if hud.get("_message_key") == "WORLD_SEA_TOO_DEEP":
			hud.clear_message())
