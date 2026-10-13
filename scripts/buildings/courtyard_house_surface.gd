@tool
extends Node3D
const Door = preload("res://scripts/world/village_door.gd")
var door: Node3D
## Canonical D-H scene enables the exported linear Weather vertex colours.
## Godot4.7.2 imported the COLOR_0 array but left the material flag disabled.
func _ready() -> void:
    for node in find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        for surface in range(mesh.mesh.get_surface_count()):
            var material := mesh.get_active_material(surface) as StandardMaterial3D
            if material != null and material.resource_name.contains("D warm lime plaster"):
                var own := material.duplicate() as StandardMaterial3D
                own.vertex_color_use_as_albedo = true
                own.vertex_color_is_srgb = false
                mesh.set_surface_override_material(surface, own)
    if not Engine.is_editor_hint():
        door = Door.new()
        door.name = "Door"
        add_child(door)
        door.configure(self, str(get_instance_id()), Vector3(0, 0, 4.30))
