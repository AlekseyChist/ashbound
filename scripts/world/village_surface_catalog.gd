class_name VillageSurfaceCatalog
extends RefCounted
## Static catalog of CC0 village terrain surface textures and their physical
## scale (metres per texture tile). Pure data + binding helper, no nodes.

const GRASS_ALBEDO: Texture2D = preload("res://assets/environment/village-surfaces-v1/Grass001_1K-JPG_Color.jpg")
const GRASS_NORMAL: Texture2D = preload("res://assets/environment/village-surfaces-v1/Grass001_1K-JPG_NormalGL.jpg")
const GRASS_ROUGHNESS: Texture2D = preload("res://assets/environment/village-surfaces-v1/Grass001_1K-JPG_Roughness.jpg")

const PATH_ALBEDO: Texture2D = preload("res://assets/environment/village-surfaces-v1/forest_ground_04_diff_1k.jpg")
const PATH_NORMAL: Texture2D = preload("res://assets/environment/village-surfaces-v1/forest_ground_04_nor_gl_1k.jpg")
const PATH_ROUGHNESS: Texture2D = preload("res://assets/environment/village-surfaces-v1/forest_ground_04_rough_1k.jpg")

## Physical width of one grass texture tile in metres.
const GRASS_METERS: float = 1.4
## Physical width of one path texture tile in metres.
const PATH_METERS: float = 3.2


static func apply_to(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"grass_albedo", GRASS_ALBEDO)
	material.set_shader_parameter(&"grass_normal", GRASS_NORMAL)
	material.set_shader_parameter(&"grass_roughness", GRASS_ROUGHNESS)
	material.set_shader_parameter(&"path_albedo", PATH_ALBEDO)
	material.set_shader_parameter(&"path_normal", PATH_NORMAL)
	material.set_shader_parameter(&"path_roughness", PATH_ROUGHNESS)
	material.set_shader_parameter(&"grass_meters", GRASS_METERS)
	material.set_shader_parameter(&"path_meters", PATH_METERS)
