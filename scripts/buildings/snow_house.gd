extends Node3D
## Imported static collisions are already present; only the entry leaf is dynamic.
const Door = preload("res://scripts/world/village_door.gd")
var door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true

func _ready() -> void:
    door = Door.new()
    door.name = "Door"
    add_child(door)
    door.configure(self, str(get_instance_id()), Vector3(0, 0, 3.32))
    for node in find_children("*", "MeshInstance3D", true, false):
        var extras: Dictionary = node.get_meta("extras", {})
        if extras.get("part_role", "") == "interior_furniture":
            interior_meshes.append(node)
    set_physics_process(false)

func _physics_process(_delta: float) -> void:
    if door.moving or not is_zero_approx(door.fraction):
        set_interior_visible(true)

## The world controls distance and occupancy. An open portal must keep its contents.
## Floors, the stove/flue, walls, roof and physics always remain present.
func set_interior_visible(enabled: bool, occupied: bool = false) -> bool:
    if not enabled and (occupied or door == null or door.moving or not is_zero_approx(door.fraction)):
        return false
    for mesh in interior_meshes:
        mesh.visible = enabled
    interior_visible = enabled
    set_physics_process(not enabled)
    return true
