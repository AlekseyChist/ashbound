extends Node3D
## WORLD-SEA-01 (D-099): the sea along the south edge of the map, to the horizon.
## The coast and the seabed are baked into the world heights (art/world/graybox-v1/build.py);
## this node adds the water surface, a wading floor just under it (no swimming yet: the hero
## walks in knee-deep water instead of sinking to the seabed) and a stop at the map edge.
const BEYOND := 6000.0
const WADE_DEPTH := 0.8
const WATER := Color("35627a")

var level := 0.0
var coast_z := INF
var surface: MeshInstance3D
var floor_body: StaticBody3D

func build(scene: Node3D) -> void:
	var sea: Variant = scene.world_layout.get("sea")
	if not sea is Dictionary:
		return
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
	# Wading floor under the water, over the whole map part of the sea (land above it hides it).
	floor_body = StaticBody3D.new()
	floor_body.name = "WadingFloor"
	add_child(floor_body)
	var slab := BoxShape3D.new()
	slab.size = Vector3(2.0 * half, 2.0, half - north)
	var shape := CollisionShape3D.new()
	shape.shape = slab
	shape.position = Vector3(0.0, level - WADE_DEPTH - 1.0, (north + half) * 0.5)
	floor_body.add_child(shape)
	floor_body.set_meta("footstep_surface", "ground")
	# The map ends at its south edge; the water goes on, the hero stops.
	var wall := BoxShape3D.new()
	wall.size = Vector3(2.0 * half, 8.0, 2.0)
	var edge := CollisionShape3D.new()
	edge.shape = wall
	edge.position = Vector3(0.0, level + 2.0, half - 4.0)
	floor_body.add_child(edge)
	print("WORLD_SEA level=%.1f coast_z=%.0f" % [level, coast_z])
