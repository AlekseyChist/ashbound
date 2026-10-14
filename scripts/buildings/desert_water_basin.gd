extends Node3D
const WaterShader = preload("res://assets/shaders/settlement_basin_water.gdshader")
func _ready() -> void:
    for node in find_children("*", "MeshInstance3D", true, false):
        if node.get_meta("extras", {}).get("part_role", "") == "water_surface":
            var material := ShaderMaterial.new()
            material.shader = WaterShader
            node.material_override = material
            node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
