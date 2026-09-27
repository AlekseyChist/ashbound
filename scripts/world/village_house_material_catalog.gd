extends RefCounted
## CC0 source bytes and authors: assets/environment/village-house-materials-v1/.
const MAPS={
	"plaster":[preload("res://assets/environment/village-house-materials-v1/plaster_grey_04_diff_1k.jpg"),preload("res://assets/environment/village-house-materials-v1/plaster_grey_04_nor_gl_1k.jpg"),preload("res://assets/environment/village-house-materials-v1/plaster_grey_04_rough_1k.jpg")],
	"wood":[preload("res://assets/environment/village-house-materials-v1/fine_grained_wood_col_1k.jpg"),preload("res://assets/environment/village-house-materials-v1/fine_grained_wood_nor_gl_1k.jpg"),preload("res://assets/environment/village-house-materials-v1/fine_grained_wood_rough_1k.jpg")],
	"stone":[preload("res://assets/environment/village-house-materials-v1/stone_wall_02_diff_1k.jpg"),preload("res://assets/environment/village-house-materials-v1/stone_wall_02_nor_gl_1k.jpg"),preload("res://assets/environment/village-house-materials-v1/stone_wall_02_rough_1k.jpg")]
}
const FINISH={
	"plaster":["plaster",Color(1,.94,.82,1),.55,.12],
	"oak":["wood",Color.WHITE,.75,.12],
	"roof":["wood",Color(.76,.79,.83,1),.85,.10],
	"stone":["stone",Color(.96,1.02,1.13,1),.75,.10]
}

static func create(kind: String) -> Material:
	if not FINISH.has(kind):return null
	var settings: Array=FINISH[kind];var maps: Array=MAPS[settings[0]]
	if kind=="roof":
		var roof:=ShaderMaterial.new()
		roof.resource_name="H01_A_roof"
		roof.shader=preload("res://assets/shaders/village_house_roof.gdshader")
		for i in range(3):roof.set_shader_parameter(["albedo_map","normal_map","roughness_map"][i],maps[i])
		return roof
	var material:=StandardMaterial3D.new()
	material.resource_name="H01_A_"+kind
	material.albedo_texture=maps[0];material.albedo_color=settings[1]
	material.normal_enabled=true;material.normal_texture=maps[1];material.normal_scale=settings[2]
	material.roughness_texture=maps[2];material.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness=1.0;material.metallic_specular=settings[3]
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material
