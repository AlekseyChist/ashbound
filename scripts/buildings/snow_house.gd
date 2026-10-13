extends Node3D
## Imported static collisions are already present; only the entry leaf is dynamic.
const Door = preload("res://scripts/world/village_door.gd")
var door: Node3D

func _ready() -> void:
    door = Door.new()
    door.name = "Door"
    add_child(door)
    door.configure(self, str(get_instance_id()), Vector3(0, 0, 3.32))
