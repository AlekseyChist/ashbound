extends Node3D
## L-H (WORLD-PLAN-01 plate L, D-118): the canonical scene of the lowland town house. The same
## contract as Codex's D-H/S-H scenes: the entry leaf (on L_entry_hinge) swings through the shared
## village_door.gd - consumers call door.try_toggle(actor), never add a second door - and the world
## may hide the interior furniture from afar with set_interior_visible(), which refuses while the
## house is occupied or the door is open or moving; opening the door shows the furniture again.
const Door = preload("res://scripts/world/village_door.gd")
## The doorway's middle on the front wall (Godot frame: Blender (x, y) -> (x, -y)).
const ENTRY := Vector3(-1.8, 0.0, 3.5)
var door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true


func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.get_meta("extras", {}).get("part_role", "") == "interior_furniture":
			interior_meshes.append(mesh)
	door = Door.new()
	door.name = "Door"
	add_child(door)
	door.configure(self, str(get_instance_id()), ENTRY)
	set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if door != null and (door.moving or not is_zero_approx(door.fraction)):
		set_interior_visible(true)


## Hides or shows the furniture (the stair, hearth, ceiling and every collision stay).
func set_interior_visible(enabled: bool, occupied: bool = false) -> bool:
	if not enabled and (occupied or door == null or door.moving or not is_zero_approx(door.fraction)):
		return false
	for mesh in interior_meshes:
		mesh.visible = enabled
	interior_visible = enabled
	set_physics_process(not enabled)
	return true
