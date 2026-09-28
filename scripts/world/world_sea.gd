extends Node3D
## WORLD-SEA-01 (D-099): the sea along the south edge of the map, to the horizon.
## The coast and the seabed are baked into the world heights (art/world/graybox-v1/build.py);
## this node adds the water surface and a stop at the map edge.
## WORLD-EDGES-01 (owner 27 Sep): the hero walks on the seabed into ever deeper water; he cannot
## swim, so where the water would reach his chest he stops and says he would drown. The same holds
## for the mountain lake and the rivers (owner: "I walked into the lake over my head").
const BEYOND := 6000.0
const STOP_DEPTH := 1.2
const WARN_EVERY := 4.0
const WARN_SHOWN := 3.0
const WATER := Color("35627a")

var world: Node3D
var _safe := Vector3.INF
## River water points by 32 m cells (world frame): [position xz, water height, half width].
const RIVER_CELL := 32.0
var _river_cells := {}
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
	for river in world.world_layout.rivers:
		for i in river.world_points.size():
			var p: Array = river.world_points[i]
			var key := Vector2i(floori(float(p[0]) / RIVER_CELL), floori(float(p[2]) / RIVER_CELL))
			if not _river_cells.has(key):
				_river_cells[key] = []
			_river_cells[key].append([Vector2(float(p[0]), float(p[2])), float(p[1]), float(river.world_widths[i]) * 0.5])
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
	# WATER-01: the same living water as the rivers, still (swell instead of flow), a deeper colour.
	var material: ShaderMaterial = scene.water_material(false) if scene.has_method("water_material") else null
	if material != null:
		material.set_shader_parameter("deep_colour", Color(0.05, 0.16, 0.24))
		material.set_shader_parameter("ripple_metres", 4.0)
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


## Water depth over the ground at a scene point (0 on land): the sea, the lake inside its shore
## ellipse, a river within its width.
func depth_at(p: Vector3) -> float:
	var w := water_at(p)
	return maxf(w.x - w.y, 0.0)


## (water surface, ground) heights under a scene point, in the world frame.
func water_at(p: Vector3) -> Vector2:
	var local: Vector3 = world.world_root.to_local(p)
	var at := Vector2(local.x, local.z)
	var water := level
	for lake in world.world_layout.lakes:
		var c: Array = lake.center
		var r: Array = lake.radii_m
		var q := Vector2((at.x + world.HALF - float(c[0])) / float(r[0]), (at.y + world.HALF - float(c[1])) / float(r[1]))
		if q.length() < 1.05:
			water = maxf(water, float(c[2]))
	var key := Vector2i(floori(at.x / RIVER_CELL), floori(at.y / RIVER_CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for point: Array in _river_cells.get(key + Vector2i(dx, dz), []):
				if at.distance_to(point[0]) <= point[2]:
					water = maxf(water, point[1])
	return Vector2(water, world.world_ground(local.x, local.z))


func _physics_process(_delta: float) -> void:
	if world == null or world.player == null:
		return
	var player: CharacterBody3D = world.player
	var at := player.global_position
	var w := water_at(at)
	# Only in the water: on a bridge (feet over the surface) the depth under it does not matter.
	var in_water: bool = world.world_root.to_local(at).y < w.x + 0.1
	if not in_water or w.x - w.y <= STOP_DEPTH:
		# JUMP-WATER-01 (owner 28 Sep: a running jump into deep water stuck the hero sinking there
		# again and again): a point in the air over deep water is not safe; only where he stands.
		if player.is_on_floor():
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


## After a teleport the old safe point is far away: the new place is the safe point when it is not
## too deep itself.
func forget_safe_point() -> void:
	var at: Vector3 = world.player.global_position
	_safe = at if depth_at(at) <= STOP_DEPTH else Vector3.INF


func _warn() -> void:
	var hud: Node = world.hud
	if hud == null or not hud.has_method("show_message"):
		return
	hud.show_message("", "WORLD_SEA_TOO_DEEP")
	get_tree().create_timer(WARN_SHOWN).timeout.connect(func():
		if hud.get("_message_key") == "WORLD_SEA_TOO_DEEP":
			hud.clear_message())
