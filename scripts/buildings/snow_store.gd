extends Node3D
const Door = preload("res://scripts/world/village_door.gd")
var door: Node3D
var interior_meshes: Array[MeshInstance3D] = []
var interior_visible := true
func _ready() -> void:
    door = Door.new()
    door.name = "Door"
    add_child(door)
    door.configure(self, str(get_instance_id()), Vector3(0, 0, 3.8))
    for node in find_children("*", "MeshInstance3D", true, false):
        if node.get_meta("extras", {}).get("part_role", "") == "interior_furniture":
            interior_meshes.append(node)
    set_physics_process(false)

func _physics_process(_delta: float) -> void:
    if door.moving or not is_zero_approx(door.fraction):
        set_interior_visible(true)

func set_interior_visible(enabled: bool, occupied: bool = false) -> bool:
    if not enabled and (occupied or door == null or door.moving or not is_zero_approx(door.fraction)):
        return false
    for mesh in interior_meshes:
        mesh.visible = enabled
    interior_visible = enabled
    set_physics_process(not enabled)
    return true
